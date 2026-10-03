param(
  [string]$ProtocolPath = (Join-Path $PSScriptRoot '../assets/twitter_protocol.json'),
  [string]$WebShellUrl = 'https://x.com/i/jf/'
)

$ErrorActionPreference = 'Stop'

$shell = Invoke-WebRequest -Uri $WebShellUrl -TimeoutSec 30
$scriptMatch = [regex]::Match(
  $shell.Content,
  'https://abs\.twimg\.com/responsive-web/client-web/main\.[^"''?]+\.js'
)
if (!$scriptMatch.Success) { throw 'Could not find the first-party X client bundle in its web shell.' }

$bundle = Invoke-WebRequest -Uri $scriptMatch.Value -TimeoutSec 60
$queryIds = @{}
$operationPattern = 'queryId\s*:\s*"(?<id>[^"]+)"\s*,\s*operationName\s*:\s*"(?<name>[^"]+)"'
foreach ($match in [regex]::Matches($bundle.Content, $operationPattern)) {
  $queryIds[$match.Groups['name'].Value] = $match.Groups['id'].Value
}
if ($queryIds.Count -lt 10) {
  throw "Only found $($queryIds.Count) operation IDs; refusing to update the protocol snapshot."
}

$protocol = Get-Content -LiteralPath $ProtocolPath -Raw | ConvertFrom-Json -AsHashtable
$updated = [System.Collections.Generic.List[string]]::new()
$preserved = [System.Collections.Generic.List[string]]::new()
foreach ($operation in $protocol.Keys) {
  if ($queryIds.ContainsKey($operation)) {
    $protocol[$operation]['id'] = $queryIds[$operation]
    $updated.Add($operation)
  } else {
    # Some routes are lazy-loaded or account-gated; preserve their pinned ID.
    $preserved.Add($operation)
  }
}

$json = ConvertTo-Json -InputObject $protocol -Depth 32
[IO.File]::WriteAllText([string](Resolve-Path $ProtocolPath), $json, [Text.UTF8Encoding]::new($false))
Write-Output "Refreshed $($updated.Count) IDs from the public X client bundle."
if ($preserved.Count -gt 0) {
  Write-Output "Kept pinned IDs for: $($preserved -join ', ')"
}
Write-Output 'Review the protocol diff and run tests before release.'
