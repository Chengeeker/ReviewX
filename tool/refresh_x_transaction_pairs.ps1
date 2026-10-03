param(
  [string]$Commit = 'ce8b0a2a7fcbb9b8b0bf594a25344c9fc3a0c00d',
  [string]$OutputPath = (Join-Path $PSScriptRoot '../assets/x_transaction_pairs.json')
)

$ErrorActionPreference = 'Stop'
if ($Commit -notmatch '^[0-9a-f]{40}$') { throw 'Commit must be a full lowercase Git SHA.' }

$url = "https://raw.githubusercontent.com/fa0311/x-client-transaction-id-pair-dict/$Commit/pair.json"
$response = Invoke-WebRequest -Uri $url -TimeoutSec 30
$pairs = $response.Content | ConvertFrom-Json
if ($pairs -isnot [array] -or $pairs.Count -lt 1 -or $pairs.Count -gt 1000) {
  throw 'The transaction pair dataset has an unexpected shape.'
}
foreach ($pair in $pairs) {
  if ($pair.verification -isnot [string] -or $pair.animationKey -isnot [string] -or
      $pair.verification.Length -eq 0 -or $pair.animationKey -notmatch '^[0-9a-f]+$') {
    throw 'The transaction pair dataset contains an invalid entry.'
  }
  [void][Convert]::FromBase64String($pair.verification)
}

$json = ConvertTo-Json -InputObject $pairs -Depth 5
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), $json, [Text.UTF8Encoding]::new($false))
Write-Output "Wrote $($pairs.Count) validated transaction pairs from $Commit."
