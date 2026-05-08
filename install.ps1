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

# Only x64 Windows builds are published.
$os = 'windows'
$arch = 'amd64'
$cpu = $env:PROCESSOR_ARCHITECTURE
if ($cpu -ne 'AMD64') {
  Warn "GizmoSQL only ships an x64 Windows build; you appear to be on '$cpu'. Continuing anyway."
}

# ---- resolve version -------------------------------------------------------
if (-not $Version) {
  Info "Resolving latest GizmoSQL release..."
  # Follow the redirect from /releases/latest to the tagged release page and
  # peel the tag off the final URL — avoids needing a GitHub API token.
  $latestUrl = "https://github.com/$Repo/releases/latest"
  try {
    $resp = Invoke-WebRequest -Uri $latestUrl -MaximumRedirection 0 -ErrorAction SilentlyContinue
  } catch {
    $resp = $_.Exception.Response
  }
  $loc = $null
  if ($resp -and $resp.Headers -and $resp.Headers.Location) {
    $loc = $resp.Headers.Location.ToString()
  } elseif ($resp -and $resp.Headers['Location']) {
    $loc = $resp.Headers['Location']
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

  # Best-effort SHA-256 verification (sibling .sha256 file if published).
  try {
    $shaUrl = "$url.sha256"
    $shaPath = "$zipPath.sha256"
    Invoke-WebRequest -Uri $shaUrl -OutFile $shaPath -UseBasicParsing -ErrorAction Stop
    $expected = (Get-Content $shaPath -First 1).Trim().Split()[0]
    $actual   = (Get-FileHash -Algorithm SHA256 -Path $zipPath).Hash.ToLower()
    if ($expected.ToLower() -ne $actual) {
      Fatal "SHA-256 mismatch for $artifact`n  expected: $expected`n  actual:   $actual"
    }
    Info "SHA-256 verified."
  } catch {
    Info "(no published SHA-256 manifest for this release; skipping verification)"
  }

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

# ---- PATH hint -------------------------------------------------------------
if (-not $NoPathHint) {
  $pathParts = $env:PATH -split ';'
  if ($pathParts -notcontains $Prefix) {
    Write-Host ""
    Write-Host "Next step: add $Prefix to your PATH." -ForegroundColor Cyan
    Write-Host "  For the current session:"
    Write-Host "    `$env:PATH = '$Prefix;' + `$env:PATH"
    Write-Host "  Permanently (user-scoped):"
    Write-Host "    [Environment]::SetEnvironmentVariable('PATH', '$Prefix;' + [Environment]::GetEnvironmentVariable('PATH','User'), 'User')"
  }
}

Write-Host ""
Write-Host "Get started:"
Write-Host "    gizmosql_server${binSuffix}.exe --password tiger" -ForegroundColor White
Write-Host "    `$env:GIZMOSQL_PASSWORD = 'tiger'; gizmosql_client${binSuffix}.exe"
Write-Host "    gizmosql_server${binSuffix}.exe --help"
Write-Host ""
Write-Host "Docs:    https://docs.gizmosql.com"
Write-Host "LTS:     https://docs.gizmosql.com/#/lts_channel"
Write-Host "Issues:  https://github.com/$Repo/issues"
