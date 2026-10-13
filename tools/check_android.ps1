#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$SdkDirectory = $(if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android/Sdk' }),
    [string]$JdkDirectory = $env:JAVA_HOME,
    [string]$TemplateDirectory,
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..' 'artifacts' 'android-preflight')
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This preflight currently examines the Windows development host.' }
if ([string]::IsNullOrWhiteSpace($JdkDirectory)) { throw 'Provide -JdkDirectory or JAVA_HOME; do not guess a machine-specific JDK location.' }
$sdk = (Resolve-Path -LiteralPath $SdkDirectory).Path
$jdk = (Resolve-Path -LiteralPath $JdkDirectory).Path
$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-toolchain.lock.json') -Raw | ConvertFrom-Json
$engineTemplateVersion = (($lock.godot_version -split '\.')[0..3] -join '.')
if ([string]::IsNullOrWhiteSpace($TemplateDirectory)) { $TemplateDirectory = Join-Path $env:APPDATA "Godot/export_templates/$engineTemplateVersion" }
$templates = (Resolve-Path -LiteralPath $TemplateDirectory).Path
$java = Join-Path $jdk 'bin/java.exe'
$adb = Join-Path $sdk 'platform-tools/adb.exe'
$javaLog = & $java -version 2>&1 | Out-String
$javaExit = $LASTEXITCODE
$adbVersion = & $adb version 2>&1 | Out-String
$adbVersionExit = $LASTEXITCODE
$adbDevices = & $adb devices -l 2>&1 | Out-String
$adbDevicesExit = $LASTEXITCODE
$deviceLines = @($adbDevices -split "`r?`n" | Where-Object { $_ -match '^\S+\s+device(?:\s|$)' })
$physicalDevices = @($deviceLines | Where-Object { $_ -notmatch '^emulator-' })
function Get-ComponentDirectories([string]$name) {
    $path = Join-Path $sdk $name
    if (Test-Path -LiteralPath $path -PathType Container) { return @(Get-ChildItem -LiteralPath $path -Directory | Sort-Object Name | Select-Object -ExpandProperty Name) }
    return @()
}
$templateFiles = @()
foreach ($name in @('android_debug.apk', 'android_release.apk', 'android_source.zip')) {
    $path = Join-Path $templates $name
    if (Test-Path -LiteralPath $path -PathType Leaf) { $templateFiles += [ordered]@{ name = $name; bytes = (Get-Item -LiteralPath $path).Length; sha256 = (Get-FileHash -LiteralPath $path).Hash } }
}
$recommended = @('build-tools/35.0.1', 'platforms/android-35', 'cmake/3.10.2.4988404', 'ndk/28.1.13356709')
$missing = @($recommended | Where-Object { -not (Test-Path -LiteralPath (Join-Path $sdk $_) -PathType Container) })
$runPath = Join-Path ([IO.Path]::GetFullPath($OutputRoot)) ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runPath -Force | Out-Null
$javaLog | Set-Content -LiteralPath (Join-Path $runPath 'java-version.log') -Encoding utf8NoBOM
$adbVersion | Set-Content -LiteralPath (Join-Path $runPath 'adb-version.log') -Encoding utf8NoBOM
$adbDevices | Set-Content -LiteralPath (Join-Path $runPath 'adb-devices.log') -Encoding utf8NoBOM
$result = [ordered]@{
    preflight_commands_ok = $javaExit -eq 0 -and $adbVersionExit -eq 0 -and $adbDevicesExit -eq 0
    captured_utc = [DateTime]::UtcNow.ToString('o'); sdk_directory = $sdk; jdk_directory = $jdk
    godot_template_version = $engineTemplateVersion; template_files = $templateFiles
    build_tools = @(Get-ComponentDirectories 'build-tools'); platforms = @(Get-ComponentDirectories 'platforms')
    ndk = @(Get-ComponentDirectories 'ndk'); cmake = @(Get-ComponentDirectories 'cmake'); command_line_tools = @(Get-ComponentDirectories 'cmdline-tools')
    recommended_components_missing = $missing; authorized_devices = $deviceLines.Count; physical_authorized_devices = $physicalDevices.Count
    apk_build_attempted = $false; device_acceptance_performed = $false; touch_and_device_performance_verified = $false
    next_build_policy = 'Isolated editor settings and staging; debug signed development APK only. No storefront publishing or real-device acceptance without actual evidence.'
    version_gap_note = 'Recommended exact versions differ from installed alternatives; this preflight does not claim built-in APK export fails or succeeds. Verify with a real isolated export.'
    documentation = 'https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html'
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runPath 'preflight.json') -Encoding utf8NoBOM
Write-Output ([pscustomobject]$result | Select-Object preflight_commands_ok, physical_authorized_devices, apk_build_attempted, recommended_components_missing | ConvertTo-Json -Compress)
Write-Output "ANDROID_PREFLIGHT $runPath"
if (-not $result.preflight_commands_ok) { exit 1 }
exit 0
