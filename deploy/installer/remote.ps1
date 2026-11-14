<#
.SYNOPSIS
Installs RIoT2 on another Docker host (a NAS) from the site folder on this PC: copies the host's folder
there, runs install.sh over SSH, and writes what it exports back into the site folder (ADR 0020).
install.ps1 -RemoteHost calls it.

.DESCRIPTION
The remote host needs Docker, bash and the RIoT2 files (deploy/) at RemoteDeploy. hosts/<HostName>/ is
there, in its .install-site/ folder, only while install.sh runs; exports come back from its
.install-export/ folder. Both are deleted afterwards, also when install.sh fails. This PC needs ssh and
tar (Windows 10 and later have both).
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
# ssh with one remote command and stdin or stdout from a file (binary safe, unlike a PowerShell pipe).
function Invoke-Ssh([string] $Command, [string] $InputFile = '', [string] $OutputFile = '') {
    $options = @{ FilePath = 'ssh'; ArgumentList = "$RemoteHost `"$Command`""; NoNewWindow = $true; Wait = $true; PassThru = $true }
    if ($InputFile) { $options.RedirectStandardInput = $InputFile }
    if ($OutputFile) { $options.RedirectStandardOutput = $OutputFile }
    $process = Start-Process @options
    if ($process.ExitCode -ne 0) { throw "ssh $RemoteHost failed with exit code $($process.ExitCode)" }
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
    $files = @(Get-ChildItem -Recurse -File -Force $hostDir | Where-Object { $_.FullName.Substring($hostDir.Length + 1) -notmatch '^\.git[\\/]' })
    Write-Host "== Copying hosts/$HostName ($($files.Count) files) to ${RemoteHost}:$remoteSite"
    $tarFile = Join-Path $local 'site.tar'
    Invoke-Native 'tar' @('--format', 'ustar', '--exclude', './.git', '-cf', $tarFile, '-C', $hostDir, '.') | Out-Null
    $uploaded = $true
    Invoke-Ssh "umask 077; rm -rf '$remoteSite' '$remoteExport' && mkdir -p '$remoteSite' && tar -xf - -C '$remoteSite'" -InputFile $tarFile
    Remove-Item -Force $tarFile

    $commit = ''
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $commit = "$(Invoke-Native 'git' @('-C', $Site, 'rev-parse', '--short', 'HEAD') -AllowFailure)".Trim()
        if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-f]+$') { $commit = '' }
    }
    $remoteArgs = @("--plain '$remoteSite'", "--host '$HostName'") + $InstallArgs
    if ($commit) { $remoteArgs += "--site-commit $commit" }
    # A terminal on the remote side, so install.sh can ask its questions.
    $sshArgs = @()
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
            Invoke-Ssh "if [ -d '$remoteExport' ]; then tar -cf - -C '$remoteExport' .; fi" -OutputFile $exportTar
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
            try { Invoke-Ssh "rm -rf '$remoteSite' '$remoteExport'" }
            catch { [Console]::Error.WriteLine("WARNING: delete ${RemoteHost}:$remoteSite and $remoteExport by hand: they hold the site's secrets") }
        }
    }
    Remove-Item -Recurse -Force $local -ErrorAction SilentlyContinue
}
exit $code
