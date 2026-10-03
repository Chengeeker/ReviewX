param(
  [string]$KeyStore = $env:REVIEW_X_KEYSTORE,
  [string]$JavaHome = $env:JAVA_HOME,
  [string]$BcProvider = $env:REVIEW_X_BC_PROVIDER,
  [string]$FlutterCommand = 'flutter'
)
$ErrorActionPreference = 'Stop'
$keyAlias = $env:REVIEW_X_KEY_ALIAS
if ([string]::IsNullOrWhiteSpace($KeyStore) -or !(Test-Path -LiteralPath $KeyStore -PathType Leaf)) {
  throw 'Set REVIEW_X_KEYSTORE to your local BKS keystore file.'
}
if ([string]::IsNullOrWhiteSpace($keyAlias)) {
  throw 'Set REVIEW_X_KEY_ALIAS to the alias in your local keystore.'
}
if ([string]::IsNullOrWhiteSpace($JavaHome)) {
  throw 'Set JAVA_HOME to a local JDK 17 installation.'
}
if ([string]::IsNullOrWhiteSpace($BcProvider) -or !(Test-Path -LiteralPath $BcProvider -PathType Leaf)) {
  throw 'Set REVIEW_X_BC_PROVIDER to a local Bouncy Castle provider JAR.'
}
if (!(Get-Command $FlutterCommand -ErrorAction SilentlyContinue)) {
  throw 'Flutter was not found. Add it to PATH or pass -FlutterCommand.'
}
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$tempRoot = Join-Path $projectRoot 'build/.signing-temp'
New-Item -ItemType Directory -Force $tempRoot | Out-Null
$temporaryStore = Join-Path $tempRoot 'release.p12'
$taskPassword = [Console]::ReadLine()
if ([string]::IsNullOrEmpty($taskPassword)) { throw 'Supply signing password through standard input.' }
$signingEnvironmentNames = @(
  'REVIEW_X_STORE_FILE', 'REVIEW_X_STORE_PASSWORD',
  'REVIEW_X_KEY_PASSWORD', 'REVIEW_X_KEY_ALIAS'
)
$oldSigningEnvironment = @{}
foreach ($name in $signingEnvironmentNames) {
  $oldSigningEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$oldJava = $env:JAVA_HOME
$oldTemp = $env:TEMP
$oldTmp = $env:TMP
$oldGradle = $env:GRADLE_OPTS
$oldJavaOptions = $env:JAVA_TOOL_OPTIONS
$pipeTemporaryFiles = @('ReviewXPipeProbe.java', 'ReviewXPipeProbe.class', 'ReviewXPipeAgent.java', 'ReviewXPipeAgent.class', 'pipe-agent.mf', 'pipe-agent.jar')
try {
  $env:JAVA_HOME = $JavaHome
  $env:TEMP = $tempRoot
  $env:TMP = $tempRoot
  $env:GRADLE_OPTS = '-Dorg.gradle.daemon=false'
  # Some Windows builds accept a Unix-domain listener but reject its connection.
  # Check the real JDK pipe first; only that failing build process uses TCP pipes.
  @'
public class ReviewXPipeProbe {
  public static void main(String[] args) throws Exception {
    var pipe = java.nio.channels.Pipe.open();
    pipe.source().close();
    pipe.sink().close();
  }
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot 'ReviewXPipeProbe.java') -Encoding ascii
  & (Join-Path $JavaHome 'bin/javac.exe') -d $tempRoot (Join-Path $tempRoot 'ReviewXPipeProbe.java')
  if ($LASTEXITCODE -ne 0) { throw 'JDK pipe probe compilation failed.' }
  & (Join-Path $JavaHome 'bin/java.exe') -cp $tempRoot ReviewXPipeProbe *> $null
  if ($LASTEXITCODE -ne 0) {
    @'
import java.lang.instrument.Instrumentation;
public class ReviewXPipeAgent {
  public static void premain(String args, Instrumentation instrumentation) throws Exception {
    var field = Class.forName("sun.nio.ch.PipeImpl").getDeclaredField("noUnixDomainSockets");
    field.setAccessible(true);
    field.setBoolean(null, true);
  }
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot 'ReviewXPipeAgent.java') -Encoding ascii
    & (Join-Path $JavaHome 'bin/javac.exe') -d $tempRoot (Join-Path $tempRoot 'ReviewXPipeAgent.java')
    if ($LASTEXITCODE -ne 0) { throw 'JDK pipe compatibility agent compilation failed.' }
    'Premain-Class: ReviewXPipeAgent' | Set-Content -LiteralPath (Join-Path $tempRoot 'pipe-agent.mf') -Encoding ascii
    $pipeAgent = Join-Path $tempRoot 'pipe-agent.jar'
    & (Join-Path $JavaHome 'bin/jar.exe') cfm $pipeAgent (Join-Path $tempRoot 'pipe-agent.mf') -C $tempRoot ReviewXPipeAgent.class
    if ($LASTEXITCODE -ne 0) { throw 'JDK pipe compatibility agent packaging failed.' }
    $env:JAVA_TOOL_OPTIONS = ($oldJavaOptions + ' --add-opens=java.base/sun.nio.ch=ALL-UNNAMED "-javaagent:' + $pipeAgent + '"').Trim()
    & (Join-Path $JavaHome 'bin/java.exe') -cp $tempRoot ReviewXPipeProbe *> $null
    if ($LASTEXITCODE -ne 0) { throw 'JDK pipe compatibility check failed; cannot start Gradle safely.' }
    Write-Host 'JDK pipe compatibility enabled for this build process.'
  }
  $env:REVIEW_X_STORE_PASSWORD = $taskPassword
  $env:REVIEW_X_KEY_PASSWORD = $taskPassword
  $env:REVIEW_X_KEY_ALIAS = $keyAlias
  $env:REVIEW_X_STORE_FILE = $temporaryStore
  & (Join-Path $JavaHome 'bin/keytool.exe') -importkeystore -noprompt -srckeystore $KeyStore -srcstoretype BKS -srcalias $keyAlias -srcstorepass:env REVIEW_X_STORE_PASSWORD -srckeypass:env REVIEW_X_KEY_PASSWORD -destkeystore $temporaryStore -deststoretype PKCS12 -deststorepass:env REVIEW_X_STORE_PASSWORD -destkeypass:env REVIEW_X_KEY_PASSWORD -providerclass org.bouncycastle.jce.provider.BouncyCastleProvider -providerpath $BcProvider
  if ($LASTEXITCODE -ne 0) { throw 'BKS conversion failed.' }
  Push-Location $projectRoot
  try {
    & $FlutterCommand build apk --release --target-platform android-arm64 --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Release build failed.' }
    $versionLine = Select-String -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Pattern '^version:\s*(\d+\.\d+\.\d+)\+\d+'
    if (!$versionLine) { throw 'Invalid pubspec version.' }
    $versionName = $versionLine.Matches[0].Groups[1].Value
    Copy-Item -LiteralPath (Join-Path $projectRoot 'build/app/outputs/flutter-apk/app-release.apk') -Destination (Join-Path $projectRoot "Review_X_v$versionName.apk") -Force
  } finally { Pop-Location }
} finally {
  if (Test-Path -LiteralPath $temporaryStore) { Remove-Item -LiteralPath $temporaryStore -Force }
  foreach ($name in $signingEnvironmentNames) { [Environment]::SetEnvironmentVariable($name, $oldSigningEnvironment[$name], 'Process') }
  $env:JAVA_HOME = $oldJava
  $env:TEMP = $oldTemp
  $env:TMP = $oldTmp
  $env:GRADLE_OPTS = $oldGradle
  $env:JAVA_TOOL_OPTIONS = $oldJavaOptions
  foreach ($name in $pipeTemporaryFiles) {
    Remove-Item -LiteralPath (Join-Path $tempRoot $name) -Force -ErrorAction SilentlyContinue
  }
  $taskPassword = $null
}
