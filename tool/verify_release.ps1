param([Parameter(Mandatory=$true)][string]$Apk,
  [string]$BuildTools = $env:ANDROID_BUILD_TOOLS,
  [string]$JavaHome = $env:JAVA_HOME)
$ErrorActionPreference = 'Stop'
$resolvedApk = (Resolve-Path -LiteralPath $Apk).Path
$androidSdk = $env:ANDROID_SDK_ROOT
if ([string]::IsNullOrWhiteSpace($androidSdk)) { $androidSdk = $env:ANDROID_HOME }
if ([string]::IsNullOrWhiteSpace($androidSdk) -and $env:LOCALAPPDATA) {
  $androidSdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
}
if ([string]::IsNullOrWhiteSpace($BuildTools) -and $androidSdk) {
  $buildToolsRoot = Join-Path $androidSdk 'build-tools'
  if (Test-Path -LiteralPath $buildToolsRoot -PathType Container) {
    $BuildTools = Get-ChildItem -LiteralPath $buildToolsRoot -Directory |
      Sort-Object { try { [version]$_.Name } catch { [version]'0.0' } } -Descending |
      Select-Object -First 1 -ExpandProperty FullName
  }
}
if ([string]::IsNullOrWhiteSpace($BuildTools) -or !(Test-Path -LiteralPath $BuildTools -PathType Container)) {
  throw 'Set ANDROID_SDK_ROOT or ANDROID_BUILD_TOOLS to your local Android SDK.'
}
foreach ($tool in @('aapt2.exe', 'apksigner.bat', 'zipalign.exe')) {
  if (!(Test-Path -LiteralPath (Join-Path $BuildTools $tool) -PathType Leaf)) {
    throw "Android Build Tools are missing $tool."
  }
}
$previousJava = $env:JAVA_HOME
try {
  $env:JAVA_HOME = $JavaHome
  $metadata = & (Join-Path $BuildTools 'aapt2.exe') dump badging $resolvedApk
  if ($LASTEXITCODE -ne 0) { throw 'APK metadata failed' }
  $metadata | Where-Object { $_ -match '^(package:|sdkVersion:|minSdkVersion:|targetSdkVersion:|application-label:|native-code:)' }
  if (!($metadata | Where-Object { $_ -match "^package: name='com.review.x'" })) { throw 'Unexpected package name' }
  $signature = & (Join-Path $BuildTools 'apksigner.bat') verify --verbose --print-certs $resolvedApk
  if ($LASTEXITCODE -ne 0) { throw 'APK signature failed' }
  $signature | Where-Object { $_ -match '^Verifies|v2 scheme|certificate SHA-256 digest|Number of signers:' }
  & (Join-Path $BuildTools 'zipalign.exe') -c -P 16 4 $resolvedApk
  if ($LASTEXITCODE -ne 0) { throw 'APK alignment failed' }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead($resolvedApk)
  try {
    $libraries = @($zip.Entries | Where-Object { $_.FullName -match '^lib/[^/]+/[^/]+\.so$' })
    if (!$libraries.Count) { throw 'No native libraries found' }
    foreach ($entry in $libraries) {
      if (!$entry.FullName.StartsWith('lib/arm64-v8a/')) { throw "Unexpected ABI: $($entry.FullName)" }
      $stream = $entry.Open()
      $buffer = [IO.MemoryStream]::new()
      try { $stream.CopyTo($buffer); $bytes = $buffer.ToArray() }
      finally { $stream.Dispose(); $buffer.Dispose() }
      if ($bytes.Length -lt 64 -or $bytes[0] -ne 127 -or $bytes[1] -ne 69 -or $bytes[2] -ne 76 -or $bytes[3] -ne 70 -or $bytes[4] -ne 2 -or $bytes[5] -ne 1) { throw 'Invalid ARM64 ELF' }
      $offset = [BitConverter]::ToUInt64($bytes,32)
      $stride = [BitConverter]::ToUInt16($bytes,54)
      $count = [BitConverter]::ToUInt16($bytes,56)
      $minimum = [UInt64]::MaxValue
      for ($i=0; $i -lt $count; $i++) {
        $position = $offset + $i * $stride
        if ($position + 56 -gt $bytes.Length) { throw 'Invalid ELF program headers' }
        if ([BitConverter]::ToUInt32($bytes,[int]$position) -eq 1) {
          $alignment = [BitConverter]::ToUInt64($bytes,[int]($position+48))
          $minimum = [Math]::Min($minimum,$alignment)
        }
      }
      if ($minimum -eq [UInt64]::MaxValue -or $minimum -lt 16384) { throw "ELF requires smaller pages: $($entry.FullName)" }
      Write-Output "$($entry.FullName): PT_LOAD min alignment $minimum"
    }
  } finally { $zip.Dispose() }
  Write-Output "Bytes: $((Get-Item -LiteralPath $resolvedApk).Length)"
  Write-Output "SHA256: $((Get-FileHash -LiteralPath $resolvedApk -Algorithm SHA256).Hash)"
  Write-Output 'Static APK verification passed. This is not device acceptance.'
} finally { $env:JAVA_HOME = $previousJava }
