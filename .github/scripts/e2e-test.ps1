<#
.SYNOPSIS
    End-to-end smoke test: start gizmosql_server, connect to it with
    gizmosql_client, run a query, and verify the result.
    Compatible with Windows PowerShell 5.1 and PowerShell 7+.
#>
param(
  [Parameter(Mandatory = $true)][string]$Server,
  [Parameter(Mandatory = $true)][string]$Client,
  [int]$Port = 31400
)

$proc = Start-Process -FilePath $Server `
  -ArgumentList @('--password', 'tiger', '--port', "$Port") `
  -PassThru -WindowStyle Hidden

$env:GIZMOSQL_PASSWORD = 'tiger'
$out = ''
$ok = $false
try {
  # The server needs a moment to start listening; retry for up to 30s.
  for ($i = 0; $i -lt 30; $i++) {
    $out = (& $Client --host localhost --port $Port --username gizmosql_user `
        --quiet --csv --command 'SELECT 1 AS one' 2>&1) | Out-String
    if ($LASTEXITCODE -eq 0) { $ok = $true; break }
    Start-Sleep -Seconds 1
  }
} finally {
  if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
}

Write-Host $out
if (-not $ok) {
  Write-Host 'error: client could not connect to the server' -ForegroundColor Red
  exit 1
}
if ($out -notmatch '(?m)^1\s*$') {
  Write-Host "error: expected query result '1' not found in client output" -ForegroundColor Red
  exit 1
}
Write-Host 'E2E OK: installed server answered SELECT 1 via installed client'
