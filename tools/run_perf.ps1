#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BuildDirectory,
    [string]$GodotExecutable = $env:GODOT_BIN,
    [string]$PythonExecutable = 'python',
    [string]$InputDriver = (Join-Path $PSScriptRoot '..' 'game' 'tests' 'runtime' 'input_playtest_driver.gd'),
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..' 'artifacts' 'performance'),
    [ValidateRange(60, 1800)][int]$MinimumSeconds = 60,
    [ValidateRange(2, 50)][int]$MinimumCompletedRuns = 2,
    [ValidateRange(90, 3600)][int]$MaximumSeconds = 600,
    [switch]$PrepareOnly
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Real release/Vulkan/window measurement requires the Windows target.' }
if ([string]::IsNullOrWhiteSpace($GodotExecutable)) { throw 'Provide -GodotExecutable or set GODOT_BIN; the editor engine is used only to assemble QA startup data.' }
if ($MaximumSeconds -le $MinimumSeconds + 5) { throw 'MaximumSeconds must exceed warmup and minimum measurement exposure.' }
$enginePath = (Resolve-Path -LiteralPath $GodotExecutable).Path
$pythonPath = (Get-Command $PythonExecutable -CommandType Application | Select-Object -First 1).Source
$buildPath = (Resolve-Path -LiteralPath $BuildDirectory).Path
$inputPath = (Resolve-Path -LiteralPath $InputDriver).Path
$summary = Get-Content -LiteralPath (Join-Path $buildPath 'build-summary.json') -Raw | ConvertFrom-Json
if (-not $summary.ok -or $summary.configuration -ne 'release') { throw 'Build must have passed the production export pipeline.' }
$version = (& $enginePath --version | Out-String).Trim()
$expectedVersion = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-toolchain.lock.json') -Raw | ConvertFrom-Json).godot_version
if ($LASTEXITCODE -ne 0 -or $version -ne $expectedVersion -or $summary.godot_version -ne $expectedVersion) { throw 'Pinned Godot build version mismatch.' }
$distribution = Join-Path $buildPath 'windows'
$exe = Join-Path $distribution 'AnotherWorld.exe'
$pack = Join-Path $distribution 'AnotherWorld.pck'
foreach ($name in @('AnotherWorld.exe', 'AnotherWorld.pck')) {
    $record = $summary.files | Where-Object name -EQ $name
    if (-not $record -or (Get-FileHash -LiteralPath (Join-Path $distribution $name)).Hash -ne $record.sha256) { throw "Frozen production artifact hash differs: $name" }
}
$runPath = Join-Path ([IO.Path]::GetFullPath($OutputRoot)) ([guid]::NewGuid().ToString('N'))
$workPath = Join-Path $runPath 'pack-work'
$toolPath = Join-Path $runPath 'tooling'
$qaPath = Join-Path $runPath 'qa-runtime'
$driverPath = Join-Path $runPath 'external'
New-Item -ItemType Directory -Path $runPath, $workPath, $toolPath, $qaPath, $driverPath -Force | Out-Null
'config_version=5' | Set-Content -LiteralPath (Join-Path $toolPath 'project.godot') -Encoding utf8NoBOM
$copiedRunner = Join-Path $driverPath 'measure_game.gd'
$copiedDriver = Join-Path $driverPath 'input_playtest_driver.gd'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'measure_game.gd') -Destination $copiedRunner
Copy-Item -LiteralPath $inputPath -Destination $copiedDriver
@'
[gd_scene format=3]
[node name="QALaunch" type="Node"]
'@ | Set-Content -LiteralPath (Join-Path $driverPath 'qa-main.tscn') -Encoding utf8NoBOM
$driverHash = (Get-FileHash -LiteralPath $copiedDriver).Hash
if ((Get-FileHash -LiteralPath $inputPath).Hash -ne $driverHash) { throw 'Input driver changed during its QA snapshot.' }
# Only its logger is adapted: gameplay and input behavior inherit the audited driver unchanged.
$adapterPath = Join-Path $driverPath 'perf_input_driver.gd'
$escapedDriverPath = $copiedDriver.Replace('\', '/').Replace('"', '\"')
@"
extends "$escapedDriverPath"
func _log(event: String, data: Dictionary) -> void:
    results.append({"at_seconds": elapsed, "event": event, "data": data})
"@ | Set-Content -LiteralPath $adapterPath -Encoding utf8NoBOM
$auditPath = Join-Path $runPath 'production-pack-audit.json'
& $pythonPath (Join-Path $PSScriptRoot 'inspect_pck.py') $pack --report $auditPath
if ($LASTEXITCODE -ne 0) { throw 'Production pack audit failed.' }
$qaExe = Join-Path $qaPath 'AnotherWorld.exe'
$qaPack = Join-Path $qaPath 'AnotherWorld.pck'
Copy-Item -LiteralPath $exe -Destination $qaExe
$prepareLog = & $enginePath --headless --path $toolPath --script (Join-Path $PSScriptRoot 'prepare_perf_pack.gd') -- $pack $auditPath $copiedRunner.Replace('\', '/') $workPath.Replace('\', '/') $qaPack.Replace('\', '/') 2>&1 | Out-String
$prepareExit = $LASTEXITCODE
$prepareLog | Set-Content -LiteralPath (Join-Path $runPath 'prepare.log') -Encoding utf8NoBOM
if ($prepareExit -ne 0 -or $prepareLog -match '(?m)^\s*(?:SCRIPT ERROR|ERROR|Parse Error):') { throw "QA pack preparation failed; inspect $runPath/prepare.log" }
& $pythonPath (Join-Path $PSScriptRoot 'audit_perf_pack.py') $pack $qaPack --report (Join-Path $runPath 'qa-pack-audit.json')
if ($LASTEXITCODE -ne 0 -or (Get-FileHash -LiteralPath $qaExe).Hash -ne ($summary.files | Where-Object name -EQ 'AnotherWorld.exe').sha256) { throw 'QA executable/game-resource identity did not validate.' }
$configuration = [ordered]@{
    warmup_seconds = 5; minimum_seconds = $MinimumSeconds; minimum_completed_runs = $MinimumCompletedRuns; maximum_seconds = $MaximumSeconds
    driver_path = $adapterPath.Replace('\', '/'); save_directory = (Join-Path $runPath 'isolated-saves').Replace('\', '/')
    report_path = (Join-Path $runPath 'engine-performance.json').Replace('\', '/')
}
$configPath = Join-Path $runPath 'measurement-config.json'
$configuration | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding utf8NoBOM
$identity = [ordered]@{
    kind = 'release template / byte-identical production gameplay resources / QA launch pack'
    production_build = $buildPath; production_exe_sha256 = (Get-FileHash -LiteralPath $exe).Hash
    production_pack_sha256 = (Get-FileHash -LiteralPath $pack).Hash; qa_pack_sha256 = (Get-FileHash -LiteralPath $qaPack).Hash
    external_runner_sha256 = (Get-FileHash -LiteralPath $copiedRunner).Hash; input_driver_sha256 = $driverHash
    driver_logger_adapter_sha256 = (Get-FileHash -LiteralPath $adapterPath).Hash; prepared_utc = [DateTime]::UtcNow.ToString('o')
    prepared_only = [bool]$PrepareOnly
}
$identity | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runPath 'identity.json') -Encoding utf8NoBOM
if ($PrepareOnly) { Write-Output "PERF_PREPARED $runPath"; exit 0 }

if (-not ('AWPerfWindow' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class AWPerfWindow {
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    private delegate bool Callback(IntPtr hwnd, IntPtr parameter);
    [DllImport("user32.dll")] private static extern bool EnumWindows(Callback callback, IntPtr parameter);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint owner);
    [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr window, uint message, IntPtr wparam, IntPtr lparam);
    public static bool ReadClientPhysical(IntPtr window, out Rect rect) {
        IntPtr previous = SetThreadDpiAwarenessContext(new IntPtr(-4));
        try { return GetClientRect(window, out rect); }
        finally { if (previous != IntPtr.Zero) SetThreadDpiAwarenessContext(previous); }
    }
    public static IntPtr Find(uint pid) {
        IntPtr result = IntPtr.Zero;
        EnumWindows((hwnd, parameter) => {
            uint owner; Rect rect;
            GetWindowThreadProcessId(hwnd, out owner);
            if (owner == pid && IsWindowVisible(hwnd) && GetClientRect(hwnd, out rect) && rect.Right > 100) { result = hwnd; return false; }
            return true;
        }, IntPtr.Zero);
        return result;
    }
}
'@
}
$hardware = [ordered]@{
    captured_utc = [DateTime]::UtcNow.ToString('o')
    cpu = @(Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed)
    system = @(Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer, Model, TotalPhysicalMemory)
    gpu = @(Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, DriverDate, VideoModeDescription)
    os = @(Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber)
    concurrent_gpu_capable_processes = @(Get-Process | Where-Object ProcessName -Match 'Godot|Blender|Comfy|AnotherWorld' | Select-Object ProcessName, Id)
}
$hardware | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runPath 'hardware.json') -Encoding utf8NoBOM
$rss = [System.Collections.Generic.List[object]]::new()
$windows = [System.Collections.Generic.List[object]]::new()
$info = [Diagnostics.ProcessStartInfo]::new()
$info.FileName = $qaExe
$info.WorkingDirectory = $qaPath
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
# This QA task explicitly requires a real, visible, non-minimized 1080p window.
$info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Normal
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
foreach ($argument in @('--windowed', '--resolution', '1920x1080', '--position', '0,0', '--rendering-method', 'mobile', '--rendering-driver', 'vulkan', '--', $configPath.Replace('\', '/'))) { $info.ArgumentList.Add($argument) }
foreach ($key in @('APPDATA', 'LOCALAPPDATA')) {
    $directory = Join-Path $runPath $key.ToLowerInvariant()
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $info.Environment[$key] = $directory
}
$process = [Diagnostics.Process]::new()
$process.StartInfo = $info
$watch = [Diagnostics.Stopwatch]::StartNew()
$started = $false
$forcedTermination = $false
$nativePeakWorkingSet = 0L
$failure = $null
$lastWindowCheck = -1.0
$lastProgress = 0.0
$window = [IntPtr]::Zero
$finalReportAt = $null
try {
    $started = $process.Start()
    if (-not $started) { throw 'Could not start the production release template.' }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    while (-not $process.HasExited) {
        $process.Refresh()
        if ($process.HasExited) { break }
        $rss.Add([ordered]@{ seconds = $watch.Elapsed.TotalSeconds; working_set_bytes = $process.WorkingSet64; private_bytes = $process.PrivateMemorySize64 })
        $nativePeakWorkingSet = [Math]::Max($nativePeakWorkingSet, $process.PeakWorkingSet64)
        if ($null -eq $finalReportAt -and (Test-Path -LiteralPath $configuration.report_path)) { $finalReportAt = $watch.Elapsed.TotalSeconds }
        if ($null -ne $finalReportAt -and $watch.Elapsed.TotalSeconds - $finalReportAt -gt 15) { throw 'Production normal close exceeded its bounded 15-second retirement period.' }
        if ($watch.Elapsed.TotalSeconds - $lastWindowCheck -ge 1) {
            $lastWindowCheck = $watch.Elapsed.TotalSeconds
            $window = [AWPerfWindow]::Find([uint32]$process.Id)
            if ($window -ne [IntPtr]::Zero) {
                $rect = [AWPerfWindow+Rect]::new()
                if (-not [AWPerfWindow]::ReadClientPhysical($window, [ref]$rect)) { throw 'Cannot read QA window physical client size.' }
                $state = [ordered]@{ seconds = $watch.Elapsed.TotalSeconds; width = $rect.Right - $rect.Left; height = $rect.Bottom - $rect.Top; minimized = [AWPerfWindow]::IsIconic($window); visible = [AWPerfWindow]::IsWindowVisible($window); dpi = [AWPerfWindow]::GetDpiForWindow($window) }
                $windows.Add($state)
                if ($state.minimized -or -not $state.visible -or $state.width -ne 1920 -or $state.height -ne 1080) { throw 'QA window is minimized, invisible or its client size differs from 1920x1080.' }
            } elseif ($watch.Elapsed.TotalSeconds -gt 20 -and -not (Test-Path -LiteralPath $configuration.report_path)) { throw 'QA process lacks a measurable real window during measurement.' }
        }
        if ($watch.Elapsed.TotalSeconds - $lastProgress -ge 20) {
            $lastProgress = $watch.Elapsed.TotalSeconds
            Write-Output ("PERF_RUNNING seconds={0:N1} rssMiB={1:N1}" -f $watch.Elapsed.TotalSeconds, ($process.WorkingSet64 / 1MB))
        }
        if ($watch.Elapsed.TotalSeconds -gt $MaximumSeconds + 30) { throw 'Performance process exceeded its bounded exposure.' }
        [Threading.Thread]::Sleep(100)
    }
} catch {
    $failure = $_.Exception.Message
    if ($started -and -not $process.HasExited) {
        if ($window -ne [IntPtr]::Zero) { [void][AWPerfWindow]::PostMessage($window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) }
        if (-not $process.WaitForExit(5000)) { $forcedTermination = $true; $process.Kill($true); $process.WaitForExit() }
    }
} finally {
    $rss | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runPath 'process-memory-samples.json') -Encoding utf8NoBOM
    $windows | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runPath 'native-window-samples.json') -Encoding utf8NoBOM
    if ($started) {
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $stdout | Set-Content -LiteralPath (Join-Path $runPath 'runtime.stdout.log') -Encoding utf8NoBOM
        $stderr | Set-Content -LiteralPath (Join-Path $runPath 'runtime.stderr.log') -Encoding utf8NoBOM
        $exitCode = $process.ExitCode
    } else { $stdout = ''; $stderr = ''; $exitCode = -1 }
    $process.Dispose()
}
$reportPath = Join-Path $runPath 'engine-performance.json'
$engineReport = if (Test-Path -LiteralPath $reportPath) { Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json } else { $null }
$errors = ($stdout + "`n" + $stderr) -match '(?m)^\s*(?:SCRIPT ERROR|ERROR|Parse Error):|ObjectDB instances leaked|resources still in use|RIDs of type.+were leaked'
$ok = -not $failure -and -not $forcedTermination -and $exitCode -eq 0 -and -not $errors -and $null -ne $engineReport -and $engineReport.ok -and $engineReport.coverage_verified -and $engineReport.measurement_seconds -ge $MinimumSeconds -and $windows.Count -gt 5 -and $engineReport.frame_ms.samples -gt 100 -and $engineReport.engine_process_frame_count -eq $engineReport.frame_ms.samples
if ($ok -and ($engineReport.metadata.renderer -ne 'mobile' -or $engineReport.metadata.rendering_driver -ne 'vulkan' -or -not $engineReport.metadata.release -or $engineReport.metadata.debug -or $engineReport.metadata.display_server -eq 'headless')) { $ok = $false; $failure = 'Reported renderer/release metadata violates the measurement contract.' }
if ((Get-FileHash -LiteralPath $exe).Hash -ne $identity.production_exe_sha256 -or (Get-FileHash -LiteralPath $pack).Hash -ne $identity.production_pack_sha256) { $ok = $false; $failure = 'Production artifacts changed during measurement.' }
$result = [ordered]@{
    ok = $ok; failure = $failure; engine_exit = $exitCode; forced_termination = $forcedTermination; runtime_errors = $errors
    run_directory = $runPath; identity = $identity; duration_process_seconds = $watch.Elapsed.TotalSeconds
    rss_peak_os_bytes = $nativePeakWorkingSet; rss_peak_sampled_bytes = if ($rss.Count) { ($rss | ForEach-Object { $_['working_set_bytes'] } | Measure-Object -Maximum).Maximum } else { $null }
    rss_sample_interval_seconds = 0.1; native_window_checks = $windows.Count; engine_measurement = $engineReport
}
$result | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath (Join-Path $runPath 'performance-summary.json') -Encoding utf8NoBOM
Write-Output ("PERF_RESULT " + ([pscustomobject]$result | Select-Object ok, failure, run_directory, engine_exit, forced_termination, rss_peak_os_bytes, native_window_checks | ConvertTo-Json -Compress))
if (-not $ok) { exit 1 }
exit 0
