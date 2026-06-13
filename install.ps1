<#
.SYNOPSIS
    GizmoSQL one-line installer for Windows (PowerShell).

.DESCRIPTION
    Downloads the latest GizmoSQL Windows zip from GitHub Releases and
    extracts it to the chosen install directory. Use it like:

        irm https://install.gizmosql.com/install.ps1 | iex

    Or with options (PowerShell's pipe-to-iex doesn't accept arguments,
    so download then invoke for those cases):

        iwr https://install.gizmosql.com/install.ps1 -OutFile install.ps1
        .\install.ps1 -Channel lts

.PARAMETER Channel
    Release channel: stable (default) or lts.

.PARAMETER Version
    Install a specific version, e.g. v1.25.1. Defaults to the latest release.

.PARAMETER Prefix
    Directory to install gizmosql_server.exe and gizmosql_client.exe into.
    Defaults to %LOCALAPPDATA%\Programs\GizmoSQL (no admin rights needed).

.PARAMETER NoPathHint
    Suppress the "add this to your PATH" hint at the end.

.EXAMPLE
    irm https://install.gizmosql.com/install.ps1 | iex
.EXAMPLE
    .\install.ps1 -Channel lts
.EXAMPLE
    .\install.ps1 -Version v1.25.1 -Prefix "$env:USERPROFILE\bin"

.LINK
    Source:        https://github.com/gizmodata/gizmosql-install
    Releases:      https://github.com/gizmodata/gizmosql/releases
    Channel guide: https://docs.gizmosql.com/#/lts_channel
#>

[CmdletBinding()]
param(
  [ValidateSet('stable', 'lts')]
  [string]$Channel = 'stable',

  [string]$Version = '',

  [string]$Prefix = (Join-Path $env:LOCALAPPDATA 'Programs\GizmoSQL'),

  [switch]$NoPathHint
)

$ErrorActionPreference = 'Stop'
$Repo = 'gizmodata/gizmosql'

# ---- pretty output ---------------------------------------------------------
function Info  { param([string]$msg) Write-Host "==> $msg" -ForegroundColor Green }
function Warn  { param([string]$msg) Write-Warning $msg }
function Fatal { param([string]$msg) Write-Host "error: $msg" -ForegroundColor Red; exit 1 }

# ---- artifact naming -------------------------------------------------------
$artifactSuffix = if ($Channel -eq 'lts') { '_lts' } else { '' }
$binSuffix      = if ($Channel -eq 'lts') { '_lts' } else { '' }

# Pick the artifact for the machine's native architecture (x64 and arm64
# builds are published as of v1.30.0). The registry value reflects the real
# hardware even when this PowerShell session runs emulated (e.g. x64
# PowerShell on a Windows ARM64 machine, where PROCESSOR_ARCHITECTURE lies).
$os = 'windows'
$cpu = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -ErrorAction SilentlyContinue).PROCESSOR_ARCHITECTURE
if (-not $cpu) { $cpu = $env:PROCESSOR_ARCHITECTURE }
switch ($cpu) {
  'ARM64' { $arch = 'arm64' }
  'AMD64' { $arch = 'amd64' }
  default {
    Warn "unrecognized architecture '$cpu'; defaulting to the x64 build."
    $arch = 'amd64'
  }
}

# ---- resolve version -------------------------------------------------------
if (-not $Version) {
  Info "Resolving latest GizmoSQL release..."
  # Ask /releases/latest where it redirects to and peel the tag off the
  # Location header — avoids needing a GitHub API token. HttpWebRequest with
  # AllowAutoRedirect disabled returns the 302 as a normal response in both
  # Windows PowerShell 5.1 and PowerShell 7+, unlike
  # Invoke-WebRequest -MaximumRedirection 0, which 5.1 reports as an error
  # without a usable .Response.
  $loc = $null
  try {
    $req = [System.Net.WebRequest]::Create("https://github.com/$Repo/releases/latest")
    $req.AllowAutoRedirect = $false
    $req.UserAgent = 'gizmosql-install'
    $resp = $req.GetResponse()
    try { $loc = $resp.Headers['Location'] } finally { $resp.Close() }
  } catch {
    $loc = $null
  }
  if (-not $loc) {
    Fatal "could not resolve latest version; pass -Version v1.25.1 explicitly"
  }
  $Version = ($loc -split '/')[-1]
  if ($Version -notmatch '^v') {
    Fatal "could not parse version from '$loc'"
  }
}
Info "GizmoSQL $Version ($Channel channel) for $os/$arch"

# ---- download --------------------------------------------------------------
$artifact = "gizmosql_cli_${os}_${arch}${artifactSuffix}.zip"
$url      = "https://github.com/$Repo/releases/download/$Version/$artifact"

$tmp = New-Item -ItemType Directory -Path (Join-Path $env:TEMP "gizmosql-install-$([Guid]::NewGuid())") | Select-Object -ExpandProperty FullName

try {
  Info "Downloading $artifact..."
  $zipPath = Join-Path $tmp $artifact
  try {
    Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
  } catch {
    Fatal "download failed: $url`n  (the channel/version combination may not exist; see https://github.com/$Repo/releases)"
  }

  # Transit integrity is covered by HTTPS + the zip's own CRCs. For
  # supply-chain provenance we publish Sigstore build attestations on every
  # release asset — verify with `gh attestation verify <file> --repo $Repo`
  # if you want it.

  Info "Extracting..."
  $extract = Join-Path $tmp 'extracted'
  Expand-Archive -Path $zipPath -DestinationPath $extract -Force

  if (-not (Test-Path $Prefix)) {
    New-Item -ItemType Directory -Path $Prefix -Force | Out-Null
  }

  $files = @(
    "gizmosql_server${binSuffix}.exe",
    "gizmosql_client${binSuffix}.exe"
  )
  # The Windows zip also bundles the VC++ runtime DLLs alongside the exes.
  $dlls = @('vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll')

  foreach ($f in ($files + $dlls)) {
    $src = Join-Path $extract $f
    if (-not (Test-Path $src)) {
      if ($f -in $dlls) { continue }   # DLLs are nice-to-have; exes are required
      Fatal "expected $f in $artifact but it wasn't there"
    }
    Copy-Item -Path $src -Destination (Join-Path $Prefix $f) -Force
  }
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

# ---- post-install summary --------------------------------------------------
Info "Installed:"
foreach ($f in $files) {
  Write-Host "    $(Join-Path $Prefix $f)"
}

# Quick sanity: --version
$srv = Join-Path $Prefix $files[0]
try {
  $reported = & $srv --version 2>&1 | Select-Object -First 1
  Info $reported
} catch {
  Warn "binary installed but '$srv --version' failed; check that you have the right architecture and that Defender hasn't quarantined the file."
}

# ---- PATH / shadowing checks -----------------------------------------------
$prefixNorm = $Prefix.TrimEnd('\')
$onPath = @($env:PATH -split ';' | ForEach-Object { $_.TrimEnd('\') }) -contains $prefixNorm

# An older copy elsewhere on PATH (e.g. from the MSI or a manual unzip)
# resolves ahead of the one we just installed and would silently shadow it.
$existing = Get-Command $files[0] -ErrorAction SilentlyContinue
if ($existing -and $existing.Source -and
    ((Split-Path $existing.Source).TrimEnd('\') -ne $prefixNorm)) {
  Warn "another $($files[0]) at $($existing.Source) takes precedence on your PATH and will shadow the copy just installed."
}

# ---- PATH hint -------------------------------------------------------------
if (-not $NoPathHint -and -not $onPath) {
  Write-Host ""
  Write-Host "Next step: add $Prefix to your PATH." -ForegroundColor Cyan
  Write-Host "  For the current session:"
  Write-Host "    `$env:PATH = '$Prefix;' + `$env:PATH"
  Write-Host "  Permanently (user-scoped):"
  Write-Host "    [Environment]::SetEnvironmentVariable('PATH', '$Prefix;' + [Environment]::GetEnvironmentVariable('PATH','User'), 'User')"
}

# Show copy-pasteable commands: bare names when $Prefix is on PATH, full
# paths otherwise so the examples work as-is in the current session.
if ($onPath) {
  $srvCmd = $files[0]
  $cliCmd = $files[1]
} else {
  $srvCmd = "& `"$(Join-Path $Prefix $files[0])`""
  $cliCmd = "& `"$(Join-Path $Prefix $files[1])`""
}

Write-Host ""
Write-Host "Get started:"
Write-Host "    $srvCmd --password tiger" -ForegroundColor White
Write-Host "    `$env:GIZMOSQL_PASSWORD = 'tiger'; $cliCmd"
Write-Host "    $srvCmd --help"
Write-Host ""
Write-Host "Docs:    https://docs.gizmosql.com"
Write-Host "LTS:     https://docs.gizmosql.com/#/lts_channel"
Write-Host "Issues:  https://github.com/$Repo/issues"
