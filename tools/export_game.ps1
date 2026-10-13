#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$GodotExecutable = $env:GODOT_BIN,
    [string]$PythonExecutable = 'python',
    [string]$ProjectPath = (Join-Path $PSScriptRoot '..' 'game'),
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..' 'artifacts' 'builds'),
    [ValidateRange(30, 1800)][int]$TimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This pipeline requires Windows to validate the exported executable and its native close lifecycle.' }
if (-not ('AWBuildWindow' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class AWBuildWindow {
    private delegate bool WindowCallback(IntPtr window, IntPtr state);
    [DllImport("user32.dll")] private static extern bool EnumWindows(WindowCallback callback, IntPtr state);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr window);
    [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern int GetWindowText(IntPtr window, StringBuilder text, int length);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern int GetClassName(IntPtr window, StringBuilder text, int length);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll", SetLastError=true)] private static extern bool PostMessage(IntPtr window, uint message, IntPtr wparam, IntPtr lparam);
    public static IntPtr FindWindow(uint processId) {
        IntPtr match = IntPtr.Zero;
        EnumWindows((window, state) => {
            uint owner;
            GetWindowThreadProcessId(window, out owner);
            Rect rect;
            if (owner == processId && GetClientRect(window, out rect) && rect.Right - rect.Left > 100 && rect.Bottom - rect.Top > 100) { match = window; return false; }
            return true;
        }, IntPtr.Zero);
        return match;
    }
    public static bool HideAndClose(IntPtr window) {
        ShowWindow(window, 0);
        return PostMessage(window, 0x0010, IntPtr.Zero, IntPtr.Zero);
    }
    public static string Describe(IntPtr window) {
        StringBuilder title=new StringBuilder(512), cls=new StringBuilder(128); Rect rect;
        GetWindowText(window,title,title.Capacity); GetClassName(window,cls,cls.Capacity); GetClientRect(window,out rect);
        return cls.ToString()+" | "+title.ToString()+" | client="+(rect.Right-rect.Left)+"x"+(rect.Bottom-rect.Top)+" | visible="+IsWindowVisible(window);
    }
}
'@
}
if ([string]::IsNullOrWhiteSpace($GodotExecutable)) { throw 'Provide -GodotExecutable or set GODOT_BIN.' }
$enginePath = (Resolve-Path -LiteralPath $GodotExecutable).Path
$pythonPath = (Get-Command $PythonExecutable -CommandType Application | Select-Object -First 1).Source
$sourcePath = (Resolve-Path -LiteralPath $ProjectPath).Path
$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$toolchain = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-toolchain.lock.json') -Raw | ConvertFrom-Json
$runPath = Join-Path ([IO.Path]::GetFullPath($OutputRoot)) ([guid]::NewGuid().ToString('N'))
$stagePath = Join-Path $runPath 'staging'
$toolingPath = Join-Path $runPath 'tooling'
$distributionPath = Join-Path $runPath 'windows'
$logPath = Join-Path $runPath 'logs'
New-Item -ItemType Directory -Force -Path $stagePath, $toolingPath, $distributionPath, $logPath | Out-Null
$sourceProjectHash = (Get-FileHash -LiteralPath (Join-Path $sourcePath 'project.godot')).Hash
$denyPatterns = @('^(?:\.godot|reports|tests)(?:/|$)', '^addons/(?:godot_ai|gdUnit4)(?:/|$)', '^\.gdunit')
$snapshot = [System.Collections.Generic.List[object]]::new()
foreach ($file in Get-ChildItem -LiteralPath $sourcePath -Recurse -File -Force) {
    $relative = [IO.Path]::GetRelativePath($sourcePath, $file.FullName).Replace('\', '/')
    $excluded = $false
    foreach ($pattern in $denyPatterns) { if ($relative -match $pattern) { $excluded = $true; break } }
    if ($excluded) { continue }
    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse-point source rejected: $relative" }
    $destination = Join-Path $stagePath $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    $hashBefore = (Get-FileHash -LiteralPath $file.FullName).Hash
    Copy-Item -LiteralPath $file.FullName -Destination $destination
    $hashCopied = (Get-FileHash -LiteralPath $destination).Hash
    $hashAfter = (Get-FileHash -LiteralPath $file.FullName).Hash
    if ($hashBefore -ne $hashCopied -or $hashBefore -ne $hashAfter) { throw "Source changed during snapshot: $relative. Retry on the current source state." }
    $snapshot.Add([ordered]@{ path = $relative; sha256 = $hashCopied; bytes = $file.Length })
}
$snapshot | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runPath 'source-snapshot.json') -Encoding utf8
@'
config_version=5
[application]
config/name="Another World Export Tool"
[rendering]
renderer/rendering_method="gl_compatibility"
'@ | Set-Content -LiteralPath (Join-Path $toolingPath 'project.godot') -Encoding utf8

function Invoke-BuildProcess {
    param([string]$Executable, [string[]]$Arguments, [string]$Name, [string]$WorkingDirectory = $stagePath, [hashtable]$ProcessEnvironment = @{}, [switch]$CloseWindowAfterStartup)
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $startInfo.ArgumentList.Add($argument) }
    foreach ($key in $ProcessEnvironment.Keys) { $startInfo.Environment[$key] = $ProcessEnvironment[$key] }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $elapsed = [Diagnostics.Stopwatch]::StartNew()
    $started = $false
    $logsWritten = $false
    try {
        $started = $process.Start()
        if (-not $started) { throw "Cannot start $Name" }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if ($CloseWindowAfterStartup) {
            while ($elapsed.Elapsed.TotalSeconds -lt 3.0 -and -not $process.HasExited) { [Threading.Thread]::Sleep(50) }
            if ($process.HasExited) { throw "$Name exited before its real close request." }
            $window = [AWBuildWindow]::FindWindow([uint32]$process.Id)
            [AWBuildWindow]::Describe($window) | Set-Content -LiteralPath (Join-Path $logPath "$Name.window.log") -Encoding utf8NoBOM
            if ($window -eq [IntPtr]::Zero -or -not [AWBuildWindow]::HideAndClose($window)) {
                throw "$Name window for its exact process ID could not receive WM_CLOSE."
            }
        }
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) { $process.Kill($true); $process.WaitForExit() }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $logPath "$Name.stdout.log"), $stdout)
        [IO.File]::WriteAllText((Join-Path $logPath "$Name.stderr.log"), $stderr)
        $logsWritten = $true
        if ($timedOut) { throw "$Name timed out; build not accepted. Logs: $logPath" }
        if ($process.ExitCode -ne 0) { throw "$Name exited $($process.ExitCode). Logs: $logPath" }
        if (($stdout + $stderr) -match '(?m)SCRIPT ERROR:|Parse Error:|ERROR:|ObjectDB instances were leaked|resources still in use at exit') {
            throw "$Name emitted a script/engine/lifetime error despite exit 0. Logs: $logPath"
        }
        return [pscustomobject]@{ stdout = $stdout; stderr = $stderr; seconds = $elapsed.Elapsed.TotalSeconds; exit_code = $process.ExitCode }
    }
    finally {
        if ($started -and -not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
        if ($started -and -not $logsWritten) {
            [IO.File]::WriteAllText((Join-Path $logPath "$Name.stdout.log"), $stdoutTask.GetAwaiter().GetResult())
            [IO.File]::WriteAllText((Join-Path $logPath "$Name.stderr.log"), $stderrTask.GetAwaiter().GetResult())
        }
        $elapsed.Stop()
        $process.Dispose()
    }
}

$version = Invoke-BuildProcess -Executable $enginePath -Arguments @('--headless', '--version') -Name 'version'
if ($version.stdout.Trim() -ne $toolchain.godot_version) { throw 'Godot version differs from test-toolchain.lock.json.' }
$null = Invoke-BuildProcess -Executable $enginePath -Arguments @('--headless', '--path', $toolingPath, '--script', (Join-Path $PSScriptRoot 'prepare_export.gd'), '--', (Join-Path $stagePath 'project.godot'), (Join-Path $runPath 'production-config.json'), $distributionPath) -Name 'prepare' -WorkingDirectory $toolingPath
$productionConfig = Get-Content -LiteralPath (Join-Path $runPath 'production-config.json') -Raw | ConvertFrom-Json
if (-not $productionConfig.ok -or $productionConfig.production_main_scene -ne 'res://presentation/main.tscn') { throw 'Production main scene configuration did not validate.' }
if ((Get-Content -LiteralPath (Join-Path $stagePath 'project.godot') -Raw) -match 'godot_ai|gdUnit4|_mcp_game_helper|\[editor_plugins\]') { throw 'Staged production configuration still contains developer tooling.' }
$import = Invoke-BuildProcess -Executable $enginePath -Arguments @('--headless', '--path', $stagePath, '--editor', '--import') -Name 'import'
$executable = Join-Path $distributionPath 'AnotherWorld.exe'
$export = Invoke-BuildProcess -Executable $enginePath -Arguments @('--headless', '--path', $stagePath, '--export-release', 'Windows Production', $executable) -Name 'export'
$pack = Join-Path $distributionPath 'AnotherWorld.pck'
if (-not (Test-Path -LiteralPath $executable -PathType Leaf) -or -not (Test-Path -LiteralPath $pack -PathType Leaf)) { throw 'Windows exe/PCK output missing.' }
$null = Invoke-BuildProcess -Executable $pythonPath -Arguments @((Join-Path $PSScriptRoot 'inspect_pck.py'), $pack, '--report', (Join-Path $runPath 'pack-audit.json')) -Name 'pack-audit'
$audit = Get-Content -LiteralPath (Join-Path $runPath 'pack-audit.json') -Raw | ConvertFrom-Json
if (-not $audit.ok -or $audit.file_count -le 0) { throw 'Production PCK audit did not pass.' }

# OS_Windows in the pinned engine derives user:// from process-local APPDATA.
# Only the smoke child receives these overrides; live editor/environment remain intact.
$smokeRoaming = Join-Path $runPath 'smoke-userdata' 'roaming'
$smokeLocal = Join-Path $runPath 'smoke-userdata' 'local'
New-Item -ItemType Directory -Force -Path $smokeRoaming, $smokeLocal | Out-Null
$smoke = Invoke-BuildProcess -Executable $executable -Arguments @('--verbose', '--position', '-32000,-32000', '--resolution', '640x360', '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--log-file', (Join-Path $logPath 'smoke.engine.log')) -Name 'smoke' -WorkingDirectory $distributionPath -ProcessEnvironment @{ APPDATA = $smokeRoaming; LOCALAPPDATA = $smokeLocal } -CloseWindowAfterStartup
if (Test-Path -LiteralPath (Join-Path $logPath 'smoke.engine.log')) {
    if ((Get-Content -LiteralPath (Join-Path $logPath 'smoke.engine.log') -Raw) -match '(?m)SCRIPT ERROR:|Parse Error:|ERROR:|ObjectDB instances were leaked|resources still in use at exit') { throw 'Exported smoke engine log contains an error.' }
}
if ((Get-FileHash -LiteralPath (Join-Path $sourcePath 'project.godot')).Hash -ne $sourceProjectHash) { throw 'Development project.godot changed during build; build tool did not modify it, verify concurrent editor changes.' }
foreach ($entry in @(@{ source = 'source-assets/manifest.json'; name = 'ASSET_PROVENANCE.json' }, @{ source = 'source-assets/audio/manifest.json'; name = 'AUDIO_PROVENANCE.json' }, @{ source = 'source-assets/ui/manifest.json'; name = 'UI_PROVENANCE.json' })) {
    $origin = Join-Path $repositoryRoot $entry.source
    if (Test-Path -LiteralPath $origin -PathType Leaf) { Copy-Item -LiteralPath $origin -Destination (Join-Path $distributionPath $entry.name) }
}
$distributionFiles = @(Get-ChildItem -LiteralPath $distributionPath -File | ForEach-Object { [ordered]@{ name = $_.Name; bytes = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName).Hash } })
$archivePath = Join-Path $runPath 'AnotherWorld-Windows-x64.zip'
[IO.Compression.ZipFile]::CreateFromDirectory($distributionPath, $archivePath, [IO.Compression.CompressionLevel]::Optimal, $false)
$archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    if ($archive.Entries.Count -ne $distributionFiles.Count) { throw 'Distribution ZIP entry count differs from the verified directory.' }
    foreach ($entry in $archive.Entries) {
        $expected = @($distributionFiles | Where-Object { $_.name -eq $entry.FullName })
        if ($expected.Count -ne 1) { throw 'ZIP contains an unverified file or unexpected directory.' }
        $stream = $entry.Open()
        try {
            $archiveHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))
            if ($archiveHash -ne $expected[0].sha256) { throw 'Distribution ZIP content hash differs from the verified file.' }
        }
        finally { $stream.Dispose() }
    }
}
finally { $archive.Dispose() }
$summary = [ordered]@{
    ok = $true; platform = 'Windows x86_64'; configuration = 'release'; godot_version = $toolchain.godot_version
    source_project_sha256 = $sourceProjectHash; source_files = $snapshot.Count; removed_debug_autoloads = $productionConfig.removed_debug_autoloads
    packaged_files = $audit.file_count; debug_test_paths = $audit.debug_test_paths; project_binary_checked = $audit.project_binary_checked
    import_seconds = $import.seconds; export_seconds = $export.seconds; smoke_seconds = $smoke.seconds; smoke_exit = $smoke.exit_code
    smoke_mode = 'offscreen 640x360 OpenGL compatibility/Dummy main scene + real WM_CLOSE, isolated process APPDATA/LOCALAPPDATA'
    graphics_acceptance = 'startup only, visual/performance/device acceptance not performed'
    signed = $false; distribution = $distributionPath; files = $distributionFiles; pack_audit = (Join-Path $runPath 'pack-audit.json')
    zip = $archivePath; zip_bytes = (Get-Item -LiteralPath $archivePath).Length; zip_sha256 = (Get-FileHash -LiteralPath $archivePath).Hash
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runPath 'build-summary.json') -Encoding utf8
$summary | ConvertTo-Json -Depth 8 -Compress
