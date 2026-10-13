#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$ObservedLog,
    [Parameter(Mandatory)][string[]]$ObservedJUnit,
    [string]$EvidenceRoot = (Join-Path $PSScriptRoot '..' 'artifacts' 'gdunit-diagnostic-gate')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'gdunit_diagnostic_gate.ps1')
$policyPath = Join-Path $PSScriptRoot 'gdunit_expected_diagnostics.json'
$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json -AsHashtable
$log = ($ObservedLog | ForEach-Object { Get-Content -LiteralPath $_ -Raw }) -join "`n"
$document = [xml]'<testsuites tests="0" failures="0" errors="0" skipped="0" flaky="0"/>'
$combinedTests = 0
foreach ($report in $ObservedJUnit) {
    $observedDocument = [xml](Get-Content -LiteralPath $report -Raw)
    $observedPassed = Get-GdUnitPassedJUnit $observedDocument
    $combinedTests += $observedPassed.Tests
    foreach ($suiteNode in $observedDocument.SelectNodes('/testsuites/testsuite')) {
        $null = $document.DocumentElement.AppendChild($document.ImportNode($suiteNode, $true))
    }
}
$document.DocumentElement.SetAttribute('tests', [string]$combinedTests)
$passed = Get-GdUnitPassedJUnit $document
$sourceHashes = @{}
foreach ($resource in $policy.source_sha256.Keys) {
    $path = Join-Path (Join-Path $PSScriptRoot '..' 'game') $resource.Substring(6)
    $sourceHashes[$resource] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
# The upstream observation was captured as one combined stream. Separate its exact
# raw error blocks for pure classification; the actual wrapper verifies true streams.
$blockPattern = '(?m)^ERROR:[^\r\n]*\r?\n\s+at: push_error \(core/variant/variant_utility.cpp:1023\)\r?\n\s+GDScript backtrace \(most recent call first\):\r?\n(?:[ \t]+\[[0-9]+\][^\r\n]*\r?\n)+'
$blocks = @([regex]::Matches($log, $blockPattern))
$applicableRules = @($policy.rules | Where-Object { $passed.PassedCaseIds.Contains($policy.suites[$_.suite_resource].classname + ':' + $_.case) })
if ($blocks.Count -ne $applicableRules.Count) { throw 'Actual observation error-block count differs from the rules for the passed observed suites.' }
$stderrBaseline = ($blocks | ForEach-Object Value) -join ''
$stdoutBaseline = [regex]::Replace($log, $blockPattern, '')
$results = [Collections.Generic.List[object]]::new()
function Assert-Classification {
    param([string]$Name, [string]$Stdout, [string]$Stderr, [bool]$ShouldPass, $JUnitState = $passed, $Hashes = $sourceHashes, $PolicyState = $policy)
    $audit = Get-GdUnitDiagnosticAudit -Stdout $Stdout -Stderr $Stderr -PassedJUnit $JUnitState -Policy $PolicyState -ObservedSourceHashes $Hashes
    if ($audit.ok -ne $ShouldPass) { throw "Classification '$Name' expected pass=$ShouldPass, actual=$($audit.ok)." }
    $results.Add(@{ name = $Name; passed = $true; accepted_expected = $audit.expected_diagnostics.Count; unexpected_native = $audit.unexpected_native.Count; unexpected_script = $audit.unexpected_script.Count; unexpected_diagnostics = $audit.unexpected_diagnostics.Count; budget_failures = $audit.budget_failures.Count })
}
function Copy-Policy {
    return $policy | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable
}
function Assert-BadPolicy {
    param([string]$Name, $PolicyState)
    $rejected = $false
    try { $null = Get-GdUnitDiagnosticAudit -Stdout $stdoutBaseline -Stderr $stderrBaseline -PassedJUnit $passed -Policy $PolicyState -ObservedSourceHashes $sourceHashes }
    catch { $rejected = $true }
    if (-not $rejected) { throw "Bad policy '$Name' was accepted." }
    $results.Add(@{ name = $Name; passed = $true; policy_rejected_before_log_classification = $true })
}
function Assert-BadJUnit {
    param([string]$Name, [xml]$BadDocument)
    $rejected = $false
    try { $null = Get-GdUnitPassedJUnit $BadDocument } catch { $rejected = $true }
    if (-not $rejected) { throw "Bad JUnit '$Name' was accepted." }
    $results.Add(@{ name = $Name; passed = $true; junit_rejected_before_log_classification = $true })
}
Assert-Classification 'actual-officially-asserted-observation' $stdoutBaseline $stderrBaseline $true
if (-not (Test-GdUnitStrictPhaseError '' $stderrBaseline)) { throw 'Version/import strict phase would accept expected test errors.' }
$results.Add(@{ name = 'version-and-import-never-allow-test-diagnostics'; passed = $true })
Assert-Classification 'unknown-native-cpp759' $stdoutBaseline ($stderrBaseline + "`nERROR: Parameter instance is null.`n   at: particles_get_instance_buffer_motion_vectors_offsets (servers/rendering/renderer_rd/particles_storage.cpp:759)`n") $false
Assert-Classification 'script-parse-error' $stdoutBaseline ($stderrBaseline + "`nSCRIPT ERROR: Parse Error: Invalid identifier.`n") $false
Assert-Classification 'native-objectdb-leak-warning' $stdoutBaseline ($stderrBaseline + "`nWARNING: ObjectDB instances leaked at exit.`n") $false
Assert-Classification 'native-rid-leak-warning' $stdoutBaseline ($stderrBaseline + "`nWARNING: 2 RIDs leaked at exit.`n") $false
Assert-Classification 'nonzero-orphan-report' ($stdoutBaseline + "`n1 orphan detected`n") $stderrBaseline $false
Assert-Classification 'fake-json-without-stack' $stdoutBaseline ($stderrBaseline + "`nERROR: {`"code`":`"io_error`",`"module`":`"save`",`"operation`":`"save`",`"version`":`"0.1.0`"}`n") $false
$firstBlock = $blocks[0].Value
$remaining = $stderrBaseline.Substring($firstBlock.Length)
Assert-Classification 'correct-json-on-stdout-cannot-spoof-push-error' ($stdoutBaseline + $firstBlock) $remaining $false
Assert-Classification 'unknown-module-json' $stdoutBaseline ($firstBlock.Replace('"module":"save"', '"module":"other"') + $remaining) $false
Assert-Classification 'extra-json-key' $stdoutBaseline ($firstBlock.Replace('"code":"io_error"', '"code":"io_error","extra":"forbidden"') + $remaining) $false
Assert-Classification 'duplicate-json-key' $stdoutBaseline ($firstBlock.Replace('"code":"io_error"', '"code":"io_error","code":"io_error"') + $remaining) $false
Assert-Classification 'non-string-json-value' $stdoutBaseline ($firstBlock.Replace('"version":"0.1.0"', '"version":1') + $remaining) $false
Assert-Classification 'missing-main-source-frame' $stdoutBaseline ([regex]::Replace($firstBlock, '(?m)^\s+\[0\].*\r?\n', '') + $remaining) $false
Assert-Classification 'missing-official-assert-frame' $stdoutBaseline ([regex]::Replace($firstBlock, '(?m)^.*GdUnitGodotErrorAssertImpl.gd:17.*\r?\n', '') + $remaining) $false
Assert-Classification 'wrong-official-assert-method' $stdoutBaseline ($firstBlock.Replace('is_push_error', 'is_push_warning') + $remaining) $false
Assert-Classification 'missing-corresponding-case-stack' $stdoutBaseline ($firstBlock.Replace('test_real_progress_write_failure_preserves_slots_and_returns_result_then_retry_succeeds', 'test_unrelated_case') + $remaining) $false
Assert-Classification 'extra-diagnostic-over-fixed-budget' $stdoutBaseline ($stderrBaseline + $firstBlock) $false
Assert-Classification 'missing-asserted-diagnostic-under-fixed-budget' $stdoutBaseline $remaining $false
$otherDocument = [xml]$document.OuterXml
$otherDocument.SelectSingleNode('//testcase').SetAttribute('name', 'test_unrelated_case')
Assert-Classification 'stack-case-absent-from-passed-junit' $stdoutBaseline $stderrBaseline $false (Get-GdUnitPassedJUnit $otherDocument)
$wrongHashes = @{} + $sourceHashes
$wrongHashes['res://presentation/game_session.gd'] = '0' * 64
Assert-Classification 'frozen-source-sha-changed' $stdoutBaseline $stderrBaseline $false $passed $wrongHashes
$wrongHashes = @{} + $sourceHashes
$wrongHashes[$applicableRules[0].suite_resource] = '0' * 64
Assert-Classification 'registered-suite-source-sha-changed' $stdoutBaseline $stderrBaseline $false $passed $wrongHashes
$otherDocument = [xml]$document.OuterXml
$otherDocument.SelectSingleNode('//testcase').SetAttribute('classname', 'test_unregistered_suite')
Assert-Classification 'passed-case-wrong-suite-classname' $stdoutBaseline $stderrBaseline $false (Get-GdUnitPassedJUnit $otherDocument)
Assert-Classification 'unregistered-suite-cannot-borrow-exact-json' $stdoutBaseline ($firstBlock.Replace($applicableRules[0].suite_resource, 'res://tests/test_unregistered_suite.gd') + $remaining) $false
$badPolicy = Copy-Policy
$badPolicy.policy_version = 1
Assert-BadPolicy 'legacy-policy-version-1-is-not-supported' $badPolicy
$badPolicy = Copy-Policy
$badPolicy.rules[0].suite_resource = 'res://tests/test_unregistered_suite.gd'
Assert-BadPolicy 'rule-cannot-target-an-unregistered-suite' $badPolicy
$badPolicy = Copy-Policy
$badPolicy.rules[0].case = 'test_different_registered_case'
Assert-BadPolicy 'rule-case-must-match-own-final-source-frame' $badPolicy
$badPolicy = Copy-Policy
$originalSuite = $badPolicy.rules[0].suite_resource
$newSuite = 'res://tests/test_wrong_owner.gd'
$badPolicy.suites[$newSuite] = @{ classname = 'test_wrong_owner'; evidence_origin = 'pure malformed-policy mutation'; observed_log_sha256 = 'A' * 64; allowed_tail_frames = @() }
$badPolicy.source_sha256[$newSuite] = 'A' * 64
$badPolicy.rules[0].suite_resource = $newSuite
Assert-BadPolicy 'rule-stack-cannot-belong-to-another-registered-suite' $badPolicy
$badPolicy = Copy-Policy
$badPolicy.suites[$originalSuite].allowed_tail_frames = @(@{ method = 'after_test'; path = $newSuite; line = 151 })
Assert-BadPolicy 'suite-tail-cannot-authorize-another-suite' $badPolicy
$badPolicy = Copy-Policy
$badPolicy.source_sha256.Remove($originalSuite)
Assert-BadPolicy 'every-registered-suite-needs-a-source-anchor' $badPolicy
$badPolicy = Copy-Policy
$duplicateRule = $badPolicy.rules[0] | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable
$duplicateRule.id += ':duplicate-signature'
$badPolicy.rules += $duplicateRule
Assert-BadPolicy 'different-rule-ids-cannot-have-identical-signatures' $badPolicy
foreach ($kind in @('failure', 'error', 'skipped')) {
    $bad = [xml]$document.OuterXml
    $null = $bad.SelectSingleNode('//testcase').AppendChild($bad.CreateElement($kind))
    Assert-BadJUnit "junit-$kind-cannot-be-allowed-by-log" $bad
}
$bad = [xml]$document.OuterXml
$bad.SelectSingleNode('//testsuite').SetAttribute('flaky', '1')
Assert-BadJUnit 'junit-flaky-suite' $bad
Assert-BadJUnit 'junit-zero-discovery' ([xml]'<testsuites tests="0" failures="0" skipped="0" flaky="0"/>')
$runPath = Join-Path ([IO.Path]::GetFullPath($EvidenceRoot)) ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runPath -Force | Out-Null
$summary = [ordered]@{
    ok = $true; kind = 'pure diagnostic classifier regression, no Godot execution'; cases = $results.Count
    observation_log_sha256 = @($ObservedLog | ForEach-Object { @{ path = [IO.Path]::GetFullPath($_); sha256 = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash } })
    observation_junit_sha256 = @($ObservedJUnit | ForEach-Object { @{ path = [IO.Path]::GetFullPath($_); sha256 = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash } })
    policy_sha256 = (Get-FileHash -LiteralPath $policyPath -Algorithm SHA256).Hash
    source_sha256 = $sourceHashes; results = $results.ToArray(); evidence = $runPath
}
$summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $runPath 'summary.json') -Encoding utf8
$summary | ConvertTo-Json -Depth 12 -Compress
