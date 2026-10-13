#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$GodotExecutable = $env:GODOT_BIN,
    [string]$ProjectPath = (Join-Path $PSScriptRoot '..' 'game'),
    [string]$Suite = 'res://tests',
    [string]$ReportRoot = (Join-Path $PSScriptRoot '..' 'artifacts' 'gdunit'),
    [ValidateRange(10, 1800)][int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'gdunit_diagnostic_gate.ps1')
$diagnosticPolicyPath = Join-Path $PSScriptRoot 'gdunit_expected_diagnostics.json'
$diagnosticPolicy = Get-Content -LiteralPath $diagnosticPolicyPath -Raw | ConvertFrom-Json -AsHashtable
if ([string]::IsNullOrWhiteSpace($GodotExecutable)) {
    throw 'Provide -GodotExecutable or set GODOT_BIN to the pinned Godot console executable.'
}
$enginePath = (Resolve-Path -LiteralPath $GodotExecutable).Path
$gamePath = (Resolve-Path -LiteralPath $ProjectPath).Path
$toolchain = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-toolchain.lock.json') -Raw | ConvertFrom-Json
if ($diagnosticPolicy.godot_version -cne $toolchain.godot_version -or $diagnosticPolicy.gdunit4_version -cne $toolchain.gdunit4_version) {
    throw 'Frozen diagnostic policy differs from the pinned test toolchain.'
}
if (-not (Test-Path -LiteralPath (Join-Path $gamePath 'project.godot') -PathType Leaf)) {
    throw 'ProjectPath must contain project.godot.'
}
$pluginConfig = Get-Content -LiteralPath (Join-Path $gamePath 'addons' 'gdUnit4' 'plugin.cfg') -Raw
if ($pluginConfig -notmatch ('(?m)^version="' + [regex]::Escape($toolchain.gdunit4_version) + '"\r?$')) {
    throw 'GdUnit4 plugin version differs from test-toolchain.lock.json.'
}
if ($Suite -ne 'res://tests' -and -not $Suite.StartsWith('res://tests/')) {
    throw 'Suite must be inside res://tests; vendor self-tests are separate from game acceptance.'
}
$reportPath = Join-Path ([System.IO.Path]::GetFullPath($ReportRoot)) ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $reportPath -Force | Out-Null

function Invoke-GodotChecked {
    param([string[]]$Arguments, [string]$LogName)
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $enginePath
    $startInfo.WorkingDirectory = $gamePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $startInfo.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'Godot process did not start.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill($true)
            $process.WaitForExit()
            $timedOut = $true
        } else {
            $timedOut = $false
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $reportPath "$LogName.stdout.log"), $stdout)
        [IO.File]::WriteAllText((Join-Path $reportPath "$LogName.stderr.log"), $stderr)
        if ($timedOut) { throw "Godot exceeded the ${TimeoutSeconds}s timeout; raw logs retained, no passing result recorded: $reportPath" }
        if ($process.ExitCode -ne 0) {
            throw "Godot $LogName exited $($process.ExitCode). Logs: $reportPath"
        }
        if ($LogName -cne 'tests' -and (Test-GdUnitStrictPhaseError $stdout $stderr)) {
            throw "Godot $LogName emitted an engine/script error despite exit 0. Logs: $reportPath"
        }
        return [pscustomobject]@{ Stdout = $stdout; Stderr = $stderr }
    }
    finally { $process.Dispose() }
}

function Get-FrozenSourceHashes {
    $hashes = @{}
    foreach ($resource in $diagnosticPolicy.source_sha256.Keys) {
        if (-not $resource.StartsWith('res://', [StringComparison]::Ordinal) -or $resource.Contains('..')) { throw 'Diagnostic source anchor must be a project resource.' }
        $sourcePath = Join-Path $gamePath $resource.Substring(6)
        $hashes[$resource] = if (Test-Path -LiteralPath $sourcePath -PathType Leaf) { (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash } else { 'missing' }
    }
    return $hashes
}

$versionResult = Invoke-GodotChecked -LogName 'version' -Arguments @('--headless', '--version')
if ($versionResult.Stdout.Trim() -ne $toolchain.godot_version) {
    throw "Godot version differs from the pinned test toolchain. Logs: $reportPath"
}
$null = Invoke-GodotChecked -LogName 'import' -Arguments @('--headless', '--path', $gamePath, '--editor', '--import')
$sourceHashesBefore = Get-FrozenSourceHashes
$testsResult = Invoke-GodotChecked -LogName 'tests' -Arguments @(
    '--headless', '--path', $gamePath, '--script', $toolchain.runner,
    '-a', $Suite, '-c', '-rd', $reportPath, '--ignoreHeadlessMode'
)
$reports = @(Get-ChildItem -LiteralPath $reportPath -Recurse -Filter 'results.xml' -File)
if ($reports.Count -ne 1) { throw "Expected exactly one fresh JUnit report, found $($reports.Count)." }
$xmlSettings = [Xml.XmlReaderSettings]::new()
$xmlSettings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
$xmlSettings.XmlResolver = $null
$reader = [Xml.XmlReader]::Create($reports[0].FullName, $xmlSettings)
try {
    $junit = [Xml.XmlDocument]::new()
    $junit.XmlResolver = $null
    $junit.Load($reader)
}
finally { $reader.Dispose() }
$passedJUnit = Get-GdUnitPassedJUnit $junit
$sourceHashesAfter = Get-FrozenSourceHashes
foreach ($resource in $sourceHashesBefore.Keys) {
    if ($sourceHashesBefore[$resource] -cne $sourceHashesAfter[$resource]) { throw "Source anchor changed during test execution: $resource" }
}
$diagnostics = Get-GdUnitDiagnosticAudit -Stdout $testsResult.Stdout -Stderr $testsResult.Stderr -PassedJUnit $passedJUnit -Policy $diagnosticPolicy -ObservedSourceHashes $sourceHashesAfter
$diagnostics | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $reportPath 'diagnostics.json') -Encoding utf8
if (-not $diagnostics.ok) { throw "Unexpected/incorrectly budgeted diagnostics despite passed JUnit. Raw logs and audit: $reportPath" }
$summary = [ordered]@{
    ok = $true; tests = $passedJUnit.Tests; failures = 0; errors = 0; skipped = 0; flaky = 0
    expected_diagnostics = $diagnostics.expected_diagnostics; expected_diagnostic_count = $diagnostics.expected_diagnostics.Count
    unexpected_native = $diagnostics.unexpected_native.Count; unexpected_script = $diagnostics.unexpected_script.Count
    unexpected_diagnostics = $diagnostics.unexpected_diagnostics.Count; report = $reports[0].FullName
    diagnostic_policy_version = $diagnosticPolicy.policy_version; diagnostic_policy_sha256 = (Get-FileHash -LiteralPath $diagnosticPolicyPath -Algorithm SHA256).Hash
    source_sha256 = $sourceHashesAfter
    godot_executable = $enginePath; godot_version = $toolchain.godot_version
    gdunit4_version = $toolchain.gdunit4_version; project = $gamePath
}
$summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $reportPath 'summary.json') -Encoding utf8
$summary | ConvertTo-Json -Depth 12 -Compress
