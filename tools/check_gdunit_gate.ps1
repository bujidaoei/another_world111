#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$GodotExecutable = $env:GODOT_BIN,
    [string]$EvidenceRoot = (Join-Path $PSScriptRoot '..' 'artifacts' 'gdunit-gate'),
    [ValidateRange(10, 1800)][int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($GodotExecutable)) {
    throw 'Provide -GodotExecutable or set GODOT_BIN.'
}
$enginePath = (Resolve-Path -LiteralPath $GodotExecutable).Path
$runPath = Join-Path ([IO.Path]::GetFullPath($EvidenceRoot)) ([guid]::NewGuid().ToString('N'))
$probeProject = Join-Path $runPath 'project'
$addonSource = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' 'game' 'addons' 'gdUnit4')).Path
$probeAddonDirectory = Join-Path $probeProject 'addons'
New-Item -ItemType Directory -Force -Path $probeAddonDirectory | Out-Null
Copy-Item -LiteralPath $addonSource -Destination $probeAddonDirectory -Recurse
@'
config_version=5
[application]
config/name="Another World GdUnit Gate Probe"
[rendering]
renderer/rendering_method="gl_compatibility"
'@ | Set-Content -LiteralPath (Join-Path $probeProject 'project.godot') -Encoding utf8
foreach ($probeName in @('pass', 'fail', 'zero')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $probeProject 'tests' $probeName) | Out-Null
}
@'
extends GdUnitTestSuite
func test_real_runner_passes() -> void:
    assert_bool(true).is_true()
'@ | Set-Content -LiteralPath (Join-Path $probeProject 'tests' 'pass' 'test_pass.gd') -Encoding utf8
@'
extends GdUnitTestSuite
func test_deliberate_failure_must_block_the_gate() -> void:
    assert_bool(false).is_true()
'@ | Set-Content -LiteralPath (Join-Path $probeProject 'tests' 'fail' 'test_fail.gd') -Encoding utf8

$shellExecutable = (Get-Process -Id $PID).Path
$runnerPath = Join-Path $PSScriptRoot 'run_gdunit.ps1'
$results = [ordered]@{}
foreach ($probeName in @('pass', 'fail', 'zero')) {
    $logPath = Join-Path $runPath "$probeName.log"
    & $shellExecutable -NoProfile -File $runnerPath -GodotExecutable $enginePath `
        -ProjectPath $probeProject -Suite "res://tests/$probeName" `
        -ReportRoot (Join-Path $runPath $probeName) -TimeoutSeconds $TimeoutSeconds *> $logPath
    $results[$probeName] = $LASTEXITCODE
}
if ($results.pass -ne 0) { throw "Nonzero passing fixture did not pass. Evidence: $runPath" }
if ($results.fail -eq 0) { throw "Deliberately failing fixture incorrectly passed. Evidence: $runPath" }
if ($results.zero -eq 0) { throw "Zero-discovery fixture incorrectly passed. Evidence: $runPath" }
if ((Get-Content -LiteralPath (Join-Path $runPath 'fail.log') -Raw) -notmatch 'Godot tests exited') {
    throw "Failure probe failed for an unrelated reason. Evidence: $runPath"
}
if ((Get-Content -LiteralPath (Join-Path $runPath 'zero.log') -Raw) -notmatch 'Expected exactly one fresh JUnit report|No complete nonzero test execution') {
    throw "Zero probe failed for an unrelated reason. Evidence: $runPath"
}
$summary = [ordered]@{ ok = $true; pass_exit = $results.pass; deliberate_failure_exit = $results.fail; zero_discovery_exit = $results.zero; evidence = $runPath }
$summary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runPath 'gate-summary.json') -Encoding utf8
$summary | ConvertTo-Json -Compress
