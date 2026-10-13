#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BuildDirectory,
    [string]$GodotExecutable = $env:GODOT_BIN,
    [string]$PythonExecutable = 'python',
    [string]$SdkDirectory = $(if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android/Sdk' }),
    [string]$JdkDirectory = $env:JAVA_HOME,
    [string]$TemplateDirectory,
    [string]$SigningDirectory = (Join-Path $env:LOCALAPPDATA 'AnotherWorld/development-signing'),
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..' 'artifacts' 'android-builds'),
    [ValidateRange(30,1800)][int]$TimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows -or [string]::IsNullOrWhiteSpace($GodotExecutable) -or [string]::IsNullOrWhiteSpace($JdkDirectory)) { throw 'Windows, GodotExecutable/GODOT_BIN and JdkDirectory/JAVA_HOME are required.' }
$engine = (Resolve-Path -LiteralPath $GodotExecutable).Path
$jdk = (Resolve-Path -LiteralPath $JdkDirectory).Path
$sdk = (Resolve-Path -LiteralPath $SdkDirectory).Path
$build = (Resolve-Path -LiteralPath $BuildDirectory).Path
$python = (Get-Command $PythonExecutable -CommandType Application | Select-Object -First 1).Source
$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-toolchain.lock.json') -Raw | ConvertFrom-Json
$version = (& $engine --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $version -ne $lock.godot_version) { throw 'Pinned Godot version mismatch.' }
$summary = Get-Content -LiteralPath (Join-Path $build 'build-summary.json') -Raw | ConvertFrom-Json
if (-not $summary.ok -or $summary.configuration -ne 'release' -or $summary.godot_version -ne $lock.godot_version) { throw 'Input source must be a passed production Windows snapshot.' }
$templateVersion = (($lock.godot_version -split '\.')[0..3] -join '.')
if ([string]::IsNullOrWhiteSpace($TemplateDirectory)) { $TemplateDirectory = Join-Path $env:APPDATA "Godot/export_templates/$templateVersion" }
$templates = (Resolve-Path -LiteralPath $TemplateDirectory).Path
$java = Join-Path $jdk 'bin/java.exe'
$keytool = Join-Path $jdk 'bin/keytool.exe'
$tools = Get-ChildItem -LiteralPath (Join-Path $sdk 'build-tools') -Directory | Sort-Object Name -Descending | Where-Object { (Test-Path -LiteralPath (Join-Path $_.FullName 'aapt2.exe')) -and (Test-Path -LiteralPath (Join-Path $_.FullName 'lib/apksigner.jar')) } | Select-Object -First 1
if (-not $tools) { throw 'An installed build-tools/aapt2 and apksigner.jar are required.' }
$run = Join-Path ([IO.Path]::GetFullPath($OutputRoot)) ([guid]::NewGuid().ToString('N'))
$stage = Join-Path $run 'staging'
$portable = Join-Path $run 'portable-godot'
$editorData = Join-Path $portable 'editor_data'
$portableTemplates = Join-Path $editorData "export_templates/$templateVersion"
$distribution = Join-Path $run 'android-development'
$toolProject = Join-Path $run 'tooling'
New-Item -ItemType Directory -Path $stage,$portable,$editorData,$portableTemplates,$distribution,$toolProject -Force | Out-Null
'config_version=5' | Set-Content -LiteralPath (Join-Path $toolProject 'project.godot') -Encoding utf8NoBOM
$sources = [System.Collections.Generic.List[object]]::new()
$sourceStage = Join-Path $build 'staging'
foreach ($file in Get-ChildItem -LiteralPath $sourceStage -Recurse -File -Force) {
    $relative = [IO.Path]::GetRelativePath($sourceStage, $file.FullName).Replace('\','/')
    if ($relative -match '^(?:\.godot|tests|reports)(?:/|$)|^addons/(?:godot_ai|gdUnit4)(?:/|$)') { continue }
    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Reparse-point source rejected.' }
    $target = Join-Path $stage $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    $hash = (Get-FileHash -LiteralPath $file.FullName).Hash
    Copy-Item -LiteralPath $file.FullName -Destination $target
    if ((Get-FileHash -LiteralPath $file.FullName).Hash -ne $hash -or (Get-FileHash -LiteralPath $target).Hash -ne $hash) { throw 'Frozen source changed during Android snapshot.' }
    $sources.Add([ordered]@{ path=$relative; sha256=$hash; bytes=$file.Length })
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'android_dev_export.cfg') -Destination (Join-Path $stage 'export_presets.cfg') -Force
$iconDirectory = Join-Path $stage 'assets/ui'
New-Item -ItemType Directory -Path $iconDirectory -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..' 'source-assets/ui/app_icon.svg') -Destination (Join-Path $iconDirectory 'app_icon.svg')
$sources | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $run 'source-snapshot.json') -Encoding utf8NoBOM
foreach ($file in Get-ChildItem -LiteralPath (Split-Path -Parent $engine) -Filter 'Godot*win64*.exe' -File) { Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $portable $file.Name) }
$portableEngine = Join-Path $portable (Split-Path -Leaf $engine)
if (-not (Test-Path -LiteralPath $portableEngine)) { throw 'Portable pinned editor executable was not copied.' }
New-Item -ItemType File -Path (Join-Path $portable '_sc_') | Out-Null
Copy-Item -LiteralPath (Join-Path $templates 'android_debug.apk') -Destination (Join-Path $portableTemplates 'android_debug.apk')

$signing = [IO.Path]::GetFullPath($SigningDirectory)
New-Item -ItemType Directory -Path $signing -Force | Out-Null
$keyPath = Join-Path $signing 'prototype-development.keystore'
$secretPath = Join-Path $signing 'password.dpapi.xml'
$alias = 'aw-prototype-debug'
$secret = $null
function Invoke-AndroidTool {
    param([string]$Executable,[string[]]$Arguments,[string]$Name,[hashtable]$Environment=@{})
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$Executable; $start.WorkingDirectory=$stage; $start.UseShellExecute=$false
    $start.CreateNoWindow=$true; $start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
    $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    foreach ($nameKey in $Environment.Keys) { $start.Environment[$nameKey]=$Environment[$nameKey] }
    $process=[Diagnostics.Process]::new(); $process.StartInfo=$start
    try {
        if (-not $process.Start()) { throw "Unable to start $Name" }
        $outTask=$process.StandardOutput.ReadToEndAsync(); $errTask=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) { $process.Kill($true); $process.WaitForExit(); throw "$Name timed out." }
        $output=$outTask.GetAwaiter().GetResult()+"`n"+$errTask.GetAwaiter().GetResult()
        if ($secret) { $output=$output.Replace($secret,'[redacted]') }
        $output | Set-Content -LiteralPath (Join-Path $run "$Name.log") -Encoding utf8NoBOM
        if ($process.ExitCode -ne 0 -or $output -match '(?m)^\s*(?:ERROR|SCRIPT ERROR|Parse Error):|ObjectDB instances leaked|resources still in use') { throw "$Name failed; inspect $run/$Name.log" }
        return $output
    } finally { $process.Dispose() }
}
try {
    if ((Test-Path -LiteralPath $keyPath) -ne (Test-Path -LiteralPath $secretPath)) { throw 'Existing development signing pair is incomplete; refuse to overwrite it.' }
    if (Test-Path -LiteralPath $secretPath) {
        $secure = Import-Clixml -LiteralPath $secretPath
        if ($secure -isnot [Security.SecureString]) { throw 'Signing password is not a Windows DPAPI SecureString.' }
        $secret = [Net.NetworkCredential]::new('', $secure).Password
    } else {
        $secret = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
        $secure = ConvertTo-SecureString $secret -AsPlainText -Force
        $keyEnvironment=@{ AW_ANDROID_DEBUG_SECRET=$secret; JAVA_HOME=$jdk }
        [void](Invoke-AndroidTool $keytool @('-genkeypair','-noprompt','-keystore',$keyPath,'-alias',$alias,'-keyalg','RSA','-keysize','2048','-sigalg','SHA256withRSA','-validity','3650','-dname','CN=Another World Development','-storepass:env','AW_ANDROID_DEBUG_SECRET','-keypass:env','AW_ANDROID_DEBUG_SECRET') 'generate-development-key' $keyEnvironment)
        $secure | Export-Clixml -LiteralPath $secretPath
    }
    $sdkSetting=$sdk.Replace('\','/'); $jdkSetting=$jdk.Replace('\','/'); $keySetting=$keyPath.Replace('\','/')
    @"
[gd_resource type="EditorSettings" format=3]
[resource]
export/android/android_sdk_path="$sdkSetting"
export/android/java_sdk_path="$jdkSetting"
export/android/debug_keystore="$keySetting"
"@ | Set-Content -LiteralPath (Join-Path $editorData 'editor_settings-4.7.tres') -Encoding utf8NoBOM
    $environment=@{ JAVA_HOME=$jdk; ANDROID_HOME=$sdk; ANDROID_SDK_ROOT=$sdk; GODOT_ANDROID_KEYSTORE_DEBUG_PATH=$keyPath; GODOT_ANDROID_KEYSTORE_DEBUG_USER=$alias; GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=$secret }
    [void](Invoke-AndroidTool $portableEngine @('--headless','--path',$toolProject,'--script',(Join-Path $PSScriptRoot 'prepare_android_project.gd'),'--',(Join-Path $stage 'project.godot')) 'prepare-android-project' $environment)
    [void](Invoke-AndroidTool $portableEngine @('--headless','--editor','--path',$stage,'--import') 'import' $environment)
    $apk=Join-Path $distribution 'AnotherWorld-Development-arm64.apk'
    [void](Invoke-AndroidTool $portableEngine @('--headless','--path',$stage,'--export-debug','Android Development',$apk) 'export' $environment)
    [void](Invoke-AndroidTool $java @('-jar',(Join-Path $tools.FullName 'lib/apksigner.jar'),'verify','--verbose','--print-certs',$apk) 'signature-verification' @{JAVA_HOME=$jdk})
    $manifest=Invoke-AndroidTool (Join-Path $tools.FullName 'aapt2.exe') @('dump','badging',$apk) 'manifest-badging'
    [void](Invoke-AndroidTool (Join-Path $tools.FullName 'aapt2.exe') @('dump','xmltree',$apk,'--file','AndroidManifest.xml') 'manifest-xmltree')
    if ($manifest -notmatch 'application-debuggable' -or $manifest -notmatch "package: name='org.anotherworld.prototype.dev'" -or $manifest -notmatch "native-code: 'arm64-v8a'" -or $manifest -notmatch "(?m)^minSdkVersion:'24'" -or $manifest -notmatch "(?m)^targetSdkVersion:'36'") { throw 'Actual APK manifest does not match the pinned built-in development template contract.' }
    if ($manifest -match "uses-permission: name='android.permission.(?:INTERNET|RECORD_AUDIO|CAMERA|ACCESS_FINE_LOCATION|READ_EXTERNAL_STORAGE|WRITE_EXTERNAL_STORAGE|MANAGE_EXTERNAL_STORAGE)'") { throw 'Development APK requested an unexpected permission.' }
    & $python (Join-Path $PSScriptRoot 'inspect_apk.py') $apk --report (Join-Path $run 'apk-audit.json')
    if ($LASTEXITCODE -ne 0) { throw 'APK content/CRC audit failed.' }
    foreach ($name in @('GODOT_LICENSE.txt','GODOT_THIRD_PARTY.json','ASSET_PROVENANCE.json','AUDIO_PROVENANCE.json')) { Copy-Item -LiteralPath (Join-Path $build "windows/$name") -Destination (Join-Path $distribution $name) }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..' 'source-assets/ui/manifest.json') -Destination (Join-Path $distribution 'UI_PROVENANCE.json')
    $result=[ordered]@{ ok=$true; configuration='debug-development'; godot_version=$lock.godot_version; source_windows_build=$build; source_windows_pack_sha256=($summary.files | Where-Object name -EQ 'AnotherWorld.pck').sha256; apk=$apk; apk_bytes=(Get-Item -LiteralPath $apk).Length; apk_sha256=(Get-FileHash -LiteralPath $apk).Hash; actual_arm64_only=$true; signature_verified=$true; development_key_location=$signing; signing_password_storage='Windows DPAPI outside repository'; offline_permissions_verified=$true; installed_on_device=$false; device_acceptance_performed=$false; store_release=$false }
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'android-build-summary.json') -Encoding utf8NoBOM
    Write-Output ("ANDROID_BUILD " + ($result | ConvertTo-Json -Compress))
} finally {
    $secret=$null
    if ($secure) { $secure.Dispose() }
}
