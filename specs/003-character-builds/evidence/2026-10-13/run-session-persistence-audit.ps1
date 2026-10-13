#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$GodotExecutable,
    [string]$RepositoryRoot = 'D:/bugu_projects/another_world',
    [string]$Suite = 'res://tests/test_session_persistence.gd'
)

$ErrorActionPreference = 'Stop'
$taskRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$gamePath = Join-Path $taskRoot 'game'
$enginePath = (Resolve-Path -LiteralPath $GodotExecutable).Path
$reportPath = Join-Path $taskRoot ('artifacts/session-persistence-independent-' + [guid]::NewGuid().ToString('N'))
$policyPath = Join-Path $taskRoot 'tools/gdunit_expected_diagnostics.json'
$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json -AsHashtable
$toolchain = Get-Content -LiteralPath (Join-Path $taskRoot 'tools/test-toolchain.lock.json') -Raw | ConvertFrom-Json
if (-not $policy.suites.ContainsKey($Suite)) { throw 'Independent target must be an explicitly registered policy suite.' }
. (Join-Path $taskRoot 'tools/gdunit_diagnostic_gate.ps1')
New-Item -ItemType Directory -Path $reportPath | Out-Null
$startedUtc = [DateTime]::UtcNow.ToString('o')
$sourcePaths = @(
    'game/tests/test_session_persistence.gd',
    'game/tests/test_rebinding_transition.gd',
    'game/presentation/game_session.gd',
    'game/presentation/game_hud.gd',
    'game/persistence/save_repository.gd',
    'game/persistence/user_preferences.gd',
    'game/addons/gdUnit4/src/asserts/GdUnitGodotErrorAssertImpl.gd'
)

function Get-SourceSnapshot {
    $snapshot = [ordered]@{}
    foreach ($relative in $sourcePaths) {
        $snapshot[$relative] = (Get-FileHash -LiteralPath (Join-Path $taskRoot $relative) -Algorithm SHA256).Hash
    }
    return $snapshot
}

function Invoke-ObservedGodot {
    param([string]$Phase, [string[]]$Arguments)
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $enginePath
    $info.WorkingDirectory = $gamePath
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw 'Godot did not start.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(45000)) {
            $process.Kill($true)
            $process.WaitForExit()
            $timedOut = $true
        } else { $timedOut = $false }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $reportPath ($Phase + '.stdout.log')), $stdout)
        [IO.File]::WriteAllText((Join-Path $reportPath ($Phase + '.stderr.log')), $stderr)
        $observed = [ordered]@{ exit_code = $process.ExitCode; timed_out = $timedOut; arguments = $Arguments }
        $observed | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $reportPath ($Phase + '.process.json')) -Encoding utf8
        if ($timedOut -or $process.ExitCode -ne 0) { throw "Godot phase $Phase failed; evidence retained at $reportPath" }
        return [pscustomobject]@{ Stdout = $stdout; Stderr = $stderr; ExitCode = $process.ExitCode }
    } finally { $process.Dispose() }
}

$sourceBefore = Get-SourceSnapshot
$sourceBefore | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $reportPath 'source-before.json') -Encoding utf8
$version = Invoke-ObservedGodot -Phase 'version' -Arguments @('--headless', '--version')
if ($version.Stdout.Trim() -cne $toolchain.godot_version -or (Test-GdUnitStrictPhaseError $version.Stdout $version.Stderr)) { throw 'Pinned engine version check failed.' }
if ($policy.godot_version -cne $toolchain.godot_version -or $policy.gdunit4_version -cne $toolchain.gdunit4_version) { throw 'Policy/toolchain mismatch.' }
# Existing cache only: the root owns all project import and editor/MCP sessions.
$arguments = @('--headless', '--path', $gamePath, '--script', $toolchain.runner, '-a', $Suite, '-c', '-rd', $reportPath, '--ignoreHeadlessMode')
$tests = Invoke-ObservedGodot -Phase 'tests' -Arguments $arguments
$sourceAfter = Get-SourceSnapshot
$sourceAfter | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $reportPath 'source-after.json') -Encoding utf8
foreach ($relative in $sourcePaths) {
    if ($sourceBefore[$relative] -cne $sourceAfter[$relative]) { throw "Source changed while executing: $relative" }
}
$reports = @(Get-ChildItem -LiteralPath $reportPath -Recurse -Filter results.xml -File)
if ($reports.Count -ne 1) { throw 'Exactly one fresh JUnit report required.' }
$settings = [Xml.XmlReaderSettings]::new()
$settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
$settings.XmlResolver = $null
$reader = [Xml.XmlReader]::Create($reports[0].FullName, $settings)
try {
    $document = [Xml.XmlDocument]::new()
    $document.XmlResolver = $null
    $document.Load($reader)
} finally { $reader.Dispose() }
$passed = Get-GdUnitPassedJUnit $document
$resourceHashes = @{}
foreach ($resource in $policy.source_sha256.Keys) {
    $resourceHashes[$resource] = (Get-FileHash -LiteralPath (Join-Path $gamePath $resource.Substring(6)) -Algorithm SHA256).Hash
}
$diagnostics = Get-GdUnitDiagnosticAudit -Stdout $tests.Stdout -Stderr $tests.Stderr -PassedJUnit $passed -Policy $policy -ObservedSourceHashes $resourceHashes
$diagnostics | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $reportPath 'diagnostics.json') -Encoding utf8
if (-not $diagnostics.ok) { throw "Strict diagnostic gate failed: $reportPath" }
$summary = [ordered]@{
    ok = $true
    started_utc = $startedUtc
    completed_utc = [DateTime]::UtcNow.ToString('o')
    engine_executable = $enginePath
    engine_version = $version.Stdout.Trim()
    gdunit4_version = $toolchain.gdunit4_version
    suite = $Suite
    tests = $passed.Tests
    failures = 0; errors = 0; skipped = 0; flaky = 0
    runner_exit_code = $tests.ExitCode
    imported = $false
    report_path = $reports[0].FullName
    source_sha256 = $sourceAfter
    expected_diagnostic_count = $diagnostics.expected_diagnostics.Count
    unexpected_native = $diagnostics.unexpected_native.Count
    unexpected_script = $diagnostics.unexpected_script.Count
    unexpected_diagnostics = $diagnostics.unexpected_diagnostics.Count
    policy_sha256 = (Get-FileHash -LiteralPath $policyPath -Algorithm SHA256).Hash
}
$summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $reportPath 'summary.json') -Encoding utf8
$summary | ConvertTo-Json -Depth 12 -Compress
