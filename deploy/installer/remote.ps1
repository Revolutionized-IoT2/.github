<#
.SYNOPSIS
Installs RIoT2 on another Docker host (a NAS) from this PC: decrypts the site here, runs install.sh there
over SSH, and encrypts what it exports back into the site here (ADR 0020). install.ps1 -RemoteHost calls it.

.DESCRIPTION
The remote host needs Docker, bash and the RIoT2 files (deploy/) at RemoteDeploy, but no age key: it gets
hosts/<HostName>/ decrypted, in its .install-site/ folder only while install.sh runs. Exports come back
from its .install-export/ folder and are encrypted here with the site's .sops.yaml. Both folders are
deleted afterwards, also when install.sh fails. This PC needs sops, ssh and tar (Windows 10 and later
have ssh and tar), and an age key that decrypts the host's files: -AgeKey, or sops's default
(%AppData%\sops\age\keys.txt on Windows).
#>
param(
    [Parameter(Mandatory = $true)] [string] $Site,
    [Parameter(Mandatory = $true)] [string] $HostName,
    # user@host, or a host from ~/.ssh/config.
    [Parameter(Mandatory = $true)] [string] $RemoteHost,
    # The deploy/ folder of the RIoT2 files on the remote host, for example /share/Container/riot2/.github/deploy.
    [Parameter(Mandatory = $true)] [string] $RemoteDeploy,
    [string] $AgeKey = '',
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
function Get-SopsType([string] $Name) {
    switch -Regex ($Name) {
        '\.env$' { return 'dotenv' }
        '\.json$' { return 'json' }
        '\.ya?ml$' { return 'yaml' }
        '\.ini$' { return 'ini' }
        default { return 'binary' }
    }
}
function Get-SopsName([string] $Rel) {
    $dir = ''; $base = $Rel
    if ($Rel.Contains('/')) { $dir = $Rel.Substring(0, $Rel.LastIndexOf('/') + 1); $base = $Rel.Substring($Rel.LastIndexOf('/') + 1) }
    if ($base -match '^(.*)(\.[^./]+)$') { return "$dir$($Matches[1]).sops$($Matches[2])" }
    return "$dir$base.sops"
}

foreach ($tool in 'sops', 'ssh', 'tar') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { Stop-Invalid "$tool is not installed on this PC, or not on PATH" }
}
# Single-quoted in the remote command, so only plain path characters.
if ($RemoteDeploy -notmatch '^/[A-Za-z0-9/_.-]+$') { Stop-Invalid "-RemoteDeploy must be an absolute path of letters, digits and / _ . -, not '$RemoteDeploy'" }
if ($RemoteHost -notmatch '^[A-Za-z0-9@._:-]+$') { Stop-Invalid "-RemoteHost must be a host name or user@host, not '$RemoteHost'" }
if ($AgeKey) {
    if (-not (Test-Path -PathType Leaf $AgeKey)) { Stop-Invalid "there is no age key at $AgeKey" }
    $env:SOPS_AGE_KEY_FILE = (Resolve-Path $AgeKey).Path
}
$Site = (Resolve-Path $Site).Path
$hostDir = Join-Path $Site "hosts/$HostName"
$remotePlain = "$RemoteDeploy/.install-site"
$remoteExport = "$RemoteDeploy/.install-export"
$local = Join-Path ([IO.Path]::GetTempPath()) "riot2-remote-$([guid]::NewGuid().ToString('N'))"
$plainDir = Join-Path $local 'site'
$exportDir = Join-Path $local 'export'
New-Item -ItemType Directory -Force $plainDir, $exportDir | Out-Null
$code = 1
$uploaded = $false

try {
    Write-Host "== Decrypting hosts/$HostName on this PC"
    $root = (Resolve-Path $hostDir).Path
    $encryptedNames = @()
    $names = @{}
    foreach ($file in @(Get-ChildItem -Recurse -File -Force $root | Sort-Object FullName)) {
        $rel = $file.FullName.Substring($root.Length + 1).Replace('\', '/')
        if ($rel -match '^\.git/') { continue }
        $plain = $rel
        if ($rel -match '^(.*)\.sops(\.[^./]+)?$') { $plain = $Matches[1] + $Matches[2]; $encryptedNames += $plain }
        if ($names.ContainsKey($plain)) { Stop-Invalid "both a plaintext and an encrypted copy of $plain (delete the plaintext one)" }
        $names[$plain] = $true
        $target = Join-Path $plainDir $plain
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        if ($plain -ne $rel) {
            $type = Get-SopsType $plain
            Invoke-Native 'sops' @('decrypt', '--input-type', $type, '--output-type', $type, '--output', $target, $file.FullName) -AllowFailure | Out-Null
            if ($LASTEXITCODE -ne 0) { Stop-Invalid "can't decrypt hosts/$HostName/${rel}: is your key (-AgeKey, or sops's keys.txt) among its recipients?" }
        }
        else { Copy-Item $file.FullName $target }
    }
    Write-Note "$($names.Count) files, $($encryptedNames.Count) of them decrypted"

    Write-Host "== Sending them to ${RemoteHost}:$remotePlain"
    $tarFile = Join-Path $local 'site.tar'
    Invoke-Native 'tar' @('--format', 'ustar', '-cf', $tarFile, '-C', $plainDir, '.') | Out-Null
    $uploaded = $true
    Invoke-Ssh "umask 077; rm -rf '$remotePlain' '$remoteExport' && mkdir -p '$remotePlain' && tar -xf - -C '$remotePlain'" -InputFile $tarFile
    Remove-Item -Recurse -Force $plainDir, $tarFile

    $commit = ''
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $commit = "$(Invoke-Native 'git' @('-C', $Site, 'rev-parse', '--short', 'HEAD') -AllowFailure)".Trim()
        if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-f]+$') { $commit = '' }
    }
    $remoteArgs = @("--plain '$remotePlain'", "--host '$HostName'") + $InstallArgs
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
            Push-Location $Site
            try {
                foreach ($file in @(Get-ChildItem -Recurse -File $exportRoot | Sort-Object FullName)) {
                    $rel = $file.FullName.Substring($exportRoot.Length + 1).Replace('\', '/')
                    if ($encryptedNames -contains $rel -or $rel -like 'volumes/*' -or $rel -like 'configuration/*') {
                        $target = Get-SopsName $rel
                        $type = Get-SopsType $rel
                        New-Item -ItemType Directory -Force (Split-Path (Join-Path $hostDir $target)) | Out-Null
                        Invoke-Native 'sops' @('encrypt', '--filename-override', "hosts/$HostName/$target", '--input-type', $type,
                            '--output-type', $type, '--output', "hosts/$HostName/$target", $file.FullName) -AllowFailure | Out-Null
                        if ($LASTEXITCODE -ne 0) { throw "can't encrypt hosts/$HostName/${target}: does .sops.yaml have a creation rule for it?" }
                        Write-Note "wrote hosts/$HostName/$target (encrypted)"
                    }
                    else {
                        New-Item -ItemType Directory -Force (Split-Path (Join-Path $hostDir $rel)) | Out-Null
                        Copy-Item -Force $file.FullName (Join-Path $hostDir $rel)
                        Write-Note "wrote hosts/$HostName/$rel"
                    }
                    $written++
                }
            }
            finally { Pop-Location }
            if ($written -gt 0) { Write-Note "Review and commit the site: git -C $Site status" }
        }
        catch {
            [Console]::Error.WriteLine("ERROR: the exported files couldn't be brought back: $($_.Exception.Message)")
            if ($code -eq 0) { $code = 1 }
        }
        finally {
            try { Invoke-Ssh "rm -rf '$remotePlain' '$remoteExport'" }
            catch { [Console]::Error.WriteLine("WARNING: delete ${RemoteHost}:$remotePlain and $remoteExport by hand: they hold decrypted secrets") }
        }
    }
    Remove-Item -Recurse -Force $local -ErrorAction SilentlyContinue
}
exit $code
