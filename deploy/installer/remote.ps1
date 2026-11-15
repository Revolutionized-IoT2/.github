<#
.SYNOPSIS
Installs RIoT2 on another Docker host (a NAS) from the site folder on this PC: copies the host's folder
there, runs install.sh over SSH, and writes what it exports back into the site folder (ADR 0020).
install.ps1 -RemoteHost calls it.

.DESCRIPTION
The remote host needs Docker, bash and the RIoT2 files (deploy/) at RemoteDeploy. hosts/<HostName>/ is
there, in its .install-site/ folder, only while install.sh runs; exports come back from its
.install-export/ folder. Both are deleted afterwards, also when install.sh fails. This PC needs ssh and
tar (Windows 10 and later have both). With an SSH key no password is asked; otherwise it's asked once,
and every connection of the installation gets it through SSH_ASKPASS.
#>
param(
    [Parameter(Mandatory = $true)] [string] $Site,
    [Parameter(Mandatory = $true)] [string] $HostName,
    # user@host, or a host from ~/.ssh/config.
    [Parameter(Mandatory = $true)] [string] $RemoteHost,
    # The deploy/ folder of the RIoT2 files on the remote host, for example /share/Container/riot2/.github/deploy.
    [Parameter(Mandatory = $true)] [string] $RemoteDeploy,
    # install.sh's options, for example --dry-run or --keep-existing.
    [string[]] $InstallArgs = @()
)

$ErrorActionPreference = 'Stop'

function Stop-Invalid([string] $Message) { [Console]::Error.WriteLine("ERROR: $Message"); exit 2 }
function Write-Note([string] $Message) { Write-Host "  $Message" }

# Native commands are judged by their exit code alone (see install.ps1).
function Invoke-Native([string] $Command, [string[]] $Arguments, [switch] $AllowFailure) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = & $Command @Arguments 2>&1 }
    finally { $ErrorActionPreference = $previous }
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) { throw "$Command $($Arguments -join ' ') failed with exit code ${LASTEXITCODE}: $($output -join ' ')" }
    return $output
}
# ssh's options: NumberOfPasswordPrompts once a password is in use (Enable-Askpass).
$script:sshOptions = @()
# ssh with one remote command and stdin or stdout from a file. Binary safe: Start-Process redirects through
# file handles on Windows only; elsewhere it copies the stream as text lines, which breaks a tar stream, so
# there sh does the redirection.
function Invoke-Ssh([string] $Command, [string] $InputFile = '', [string] $OutputFile = '', [string] $ErrorFile = '',
    [string[]] $Options = $script:sshOptions, [switch] $AllowFailure) {
    if ($IsLinux -or $IsMacOS) {
        $redirect = 'i=$1 o=$2 e=$3; shift 3; [ "$i" = - ] || exec <"$i"; [ "$o" = - ] || exec >"$o"; [ "$e" = - ] || exec 2>"$e"; exec ssh "$@"'
        $files = foreach ($file in $InputFile, $OutputFile, $ErrorFile) { if ($file) { $file } else { '-' } }
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { & /bin/sh -c $redirect sh @files @Options $RemoteHost $Command | Out-Host }
        finally { $ErrorActionPreference = $previous }
        $exitCode = $LASTEXITCODE
    }
    else {
        $arguments = "$((@($Options) + $RemoteHost) -join ' ') `"$Command`""
        $start = @{ FilePath = 'ssh'; ArgumentList = $arguments; NoNewWindow = $true; Wait = $true; PassThru = $true }
        if ($InputFile) { $start.RedirectStandardInput = $InputFile }
        if ($OutputFile) { $start.RedirectStandardOutput = $OutputFile }
        if ($ErrorFile) { $start.RedirectStandardError = $ErrorFile }
        $exitCode = (Start-Process @start).ExitCode
    }
    if ($exitCode -ne 0 -and -not $AllowFailure) { throw "ssh $RemoteHost failed with exit code $exitCode" }
    return $exitCode
}
# The password is asked once: every later connection gets it from this helper (SSH_ASKPASS), which answers
# password prompts only, so ssh never accepts a host key on its behalf.
function Enable-Askpass([securestring] $Password) {
    if ($IsLinux -or $IsMacOS) {
        $helper = Join-Path $local 'askpass.sh'
        [IO.File]::WriteAllText($helper, "#!/bin/sh`ncase `"`$1`" in *[Pp]assword*) printf '%s\n' `"`$RIOT2_SSH_PASSWORD`" ;; *) exit 1 ;; esac`n")
        & chmod 700 $helper
    }
    else {
        $script = Join-Path $local 'askpass.ps1'
        # UTF-8 bytes, whatever the console's code page.
        [IO.File]::WriteAllText($script, ("param([string] `$Prompt)`r`nif (`$Prompt -notmatch '(?i)password') { exit 1 }`r`n" +
            "`$bytes = [Text.Encoding]::UTF8.GetBytes(`$env:RIOT2_SSH_PASSWORD)`r`n" +
            "`$out = [Console]::OpenStandardOutput(); `$out.Write(`$bytes, 0, `$bytes.Length); `$out.Flush()`r`n"))
        $helper = Join-Path $local 'askpass.cmd'
        [IO.File]::WriteAllText($helper, "@powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"%~dp0askpass.ps1`" %*`r`n")
    }
    $env:RIOT2_SSH_PASSWORD = (New-Object System.Net.NetworkCredential('', $Password)).Password
    $env:SSH_ASKPASS = $helper
    $env:SSH_ASKPASS_REQUIRE = 'force'
    $script:sshOptions = @('-o', 'NumberOfPasswordPrompts=1')
}

foreach ($tool in 'ssh', 'tar') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { Stop-Invalid "$tool is not installed on this PC, or not on PATH" }
}
# Single-quoted in the remote command, so only plain path characters.
if ($RemoteDeploy -notmatch '^/[A-Za-z0-9/_.-]+$') { Stop-Invalid "-RemoteDeploy must be an absolute path of letters, digits and / _ . -, not '$RemoteDeploy'" }
if ($RemoteHost -notmatch '^[A-Za-z0-9@._:-]+$') { Stop-Invalid "-RemoteHost must be a host name or user@host, not '$RemoteHost'" }
$Site = (Resolve-Path $Site).Path
$hostDir = (Resolve-Path (Join-Path $Site "hosts/$HostName")).Path

$remoteSite = "$RemoteDeploy/.install-site"
$remoteExport = "$RemoteDeploy/.install-export"
$local = Join-Path ([IO.Path]::GetTempPath()) "riot2-remote-$([guid]::NewGuid().ToString('N'))"
$exportDir = Join-Path $local 'export'
New-Item -ItemType Directory -Force $exportDir | Out-Null
$code = 1
$uploaded = $false

try {
    # Before anything is copied: a connection that fails here leaves nothing behind to clean up. An SSH key
    # (or agent) needs no password; otherwise it's asked here, once.
    Write-Host "== Connecting to $RemoteHost"
    $check = "test -f '$RemoteDeploy/install.sh'"
    $errorFile = Join-Path $local 'ssh-error.txt'
    $connected = Invoke-Ssh $check -Options @('-o', 'BatchMode=yes') -ErrorFile $errorFile -AllowFailure
    $sshError = "$(Get-Content -Raw $errorFile -ErrorAction SilentlyContinue)"
    for ($try = 1; $connected -eq 255 -and $sshError -match 'Permission denied' -and $try -le 3; $try++) {
        if ($try -gt 1) { Write-Note "The password was refused" }
        Enable-Askpass (Read-Host -AsSecureString "${RemoteHost}'s password")
        $connected = Invoke-Ssh $check -ErrorFile $errorFile -AllowFailure
        $sshError = "$(Get-Content -Raw $errorFile -ErrorAction SilentlyContinue)"
    }
    switch ($connected) {
        0 { }
        255 {
            [Console]::Error.Write($sshError)
            if ($sshError -match 'Permission denied') { Stop-Invalid "$RemoteHost refused the password, or the SSH key" }
            Stop-Invalid ("ssh couldn't connect to $RemoteHost (above). If it reports a changed or unknown host key, and " +
                "the NAS was reinstalled or updated, check the key, run 'ssh-keygen -R <host>' and connect once with 'ssh $RemoteHost'")
        }
        default { Stop-Invalid "$RemoteDeploy/install.sh doesn't exist on ${RemoteHost}: -RemoteDeploy must be the deploy/ folder of the RIoT2 files there" }
    }

    $files = @(Get-ChildItem -Recurse -File -Force $hostDir | Where-Object { $_.FullName.Substring($hostDir.Length + 1) -notmatch '^\.git[\\/]' })
    Write-Host "== Copying hosts/$HostName ($($files.Count) files) to ${RemoteHost}:$remoteSite"
    $tarFile = Join-Path $local 'site.tar'
    Invoke-Native 'tar' @('--format', 'ustar', '--exclude', './.git', '-cf', $tarFile, '-C', $hostDir, '.') | Out-Null
    $uploaded = $true
    Invoke-Ssh "umask 077; rm -rf '$remoteSite' '$remoteExport' && mkdir -p '$remoteSite' && tar -xf - -C '$remoteSite'" -InputFile $tarFile | Out-Null
    Remove-Item -Force $tarFile

    $commit = ''
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $commit = "$(Invoke-Native 'git' @('-C', $Site, 'rev-parse', '--short', 'HEAD') -AllowFailure)".Trim()
        if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-f]+$') { $commit = '' }
    }
    $remoteArgs = @("--plain '$remoteSite'", "--host '$HostName'") + $InstallArgs
    if ($commit) { $remoteArgs += "--site-commit $commit" }
    # A terminal on the remote side, so install.sh can ask its questions.
    $sshArgs = @($script:sshOptions)
    if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) { $sshArgs += '-t' }
    $sshArgs += @($RemoteHost, "bash '$RemoteDeploy/install.sh' $($remoteArgs -join ' ')")
    Write-Host "== Running install.sh on $RemoteHost"
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & ssh @sshArgs }
    finally { $ErrorActionPreference = $previous }
    $code = $LASTEXITCODE
}
finally {
    if ($uploaded) {
        # Whatever install.sh exported, also when it failed later on.
        try {
            $exportTar = Join-Path $local 'export.tar'
            Invoke-Ssh "if [ -d '$remoteExport' ]; then tar -cf - -C '$remoteExport' .; fi" -OutputFile $exportTar | Out-Null
            if ((Get-Item $exportTar).Length -gt 0) { Invoke-Native 'tar' @('-xf', $exportTar, '-C', $exportDir) | Out-Null }
            $written = 0
            $exportRoot = (Resolve-Path $exportDir).Path
            foreach ($file in @(Get-ChildItem -Recurse -File $exportRoot | Sort-Object FullName)) {
                $rel = $file.FullName.Substring($exportRoot.Length + 1).Replace('\', '/')
                $target = Join-Path $hostDir $rel
                New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
                Copy-Item -Force $file.FullName $target
                Write-Note "wrote hosts/$HostName/$rel"
                $written++
            }
            if ($written -gt 0) { Write-Note "The site's files changed: $hostDir" }
        }
        catch {
            [Console]::Error.WriteLine("ERROR: the exported files couldn't be brought back: $($_.Exception.Message)")
            if ($code -eq 0) { $code = 1 }
        }
        finally {
            try { Invoke-Ssh "rm -rf '$remoteSite' '$remoteExport'" | Out-Null }
            catch { [Console]::Error.WriteLine("WARNING: delete ${RemoteHost}:$remoteSite and $remoteExport by hand: they hold the site's secrets") }
        }
    }
    Remove-Item -Recurse -Force $local -ErrorAction SilentlyContinue
    Remove-Item Env:RIOT2_SSH_PASSWORD, Env:SSH_ASKPASS, Env:SSH_ASKPASS_REQUIRE -ErrorAction SilentlyContinue
}
exit $code
