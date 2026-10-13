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
if ([string]::IsNullOrWhiteSpace($GodotExecutable)) {
    throw 'Provide -GodotExecutable or set GODOT_BIN to the pinned Godot console executable.'
}
$enginePath = (Resolve-Path -LiteralPath $GodotExecutable).Path
$gamePath = (Resolve-Path -LiteralPath $ProjectPath).Path
$toolchain = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-toolchain.lock.json') -Raw | ConvertFrom-Json
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
            throw "Godot exceeded the ${TimeoutSeconds}s timeout; no passing result was recorded."
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $reportPath "$LogName.stdout.log"), $stdout)
        [IO.File]::WriteAllText((Join-Path $reportPath "$LogName.stderr.log"), $stderr)
        if ($process.ExitCode -ne 0) {
            throw "Godot $LogName exited $($process.ExitCode). Logs: $reportPath"
        }
        if (($stdout + $stderr) -match '(?m)SCRIPT ERROR:|Parse Error:|ERROR:') {
            throw "Godot $LogName emitted an engine/script error despite exit 0. Logs: $reportPath"
        }
        return [pscustomobject]@{ Stdout = $stdout; Stderr = $stderr }
    }
    finally { $process.Dispose() }
}

$versionResult = Invoke-GodotChecked -LogName 'version' -Arguments @('--headless', '--version')
if ($versionResult.Stdout.Trim() -ne $toolchain.godot_version) {
    throw "Godot version differs from the pinned test toolchain. Logs: $reportPath"
}
$null = Invoke-GodotChecked -LogName 'import' -Arguments @('--headless', '--path', $gamePath, '--editor', '--import')
$null = Invoke-GodotChecked -LogName 'tests' -Arguments @(
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
$testCount = [int]$junit.testsuites.tests
$caseCount = @($junit.SelectNodes('//testcase')).Count
$failureCount = @($junit.SelectNodes('//failure')).Count
$errorCount = @($junit.SelectNodes('//error')).Count
$skippedCount = @($junit.SelectNodes('//skipped')).Count
$flakyCount = [int]$junit.testsuites.flaky
if ($testCount -le 0 -or $caseCount -ne $testCount) {
    throw "No complete nonzero test execution: declared $testCount, testcase nodes $caseCount."
}
if ($failureCount -gt 0 -or $errorCount -gt 0 -or $skippedCount -gt 0 -or $flakyCount -gt 0) {
    throw "Test gate failed: failures=$failureCount errors=$errorCount skipped=$skippedCount flaky=$flakyCount."
}
$summary = [ordered]@{
    ok = $true; tests = $testCount; failures = $failureCount; errors = $errorCount
    skipped = $skippedCount; flaky = $flakyCount; report = $reports[0].FullName
    godot_executable = $enginePath; godot_version = $toolchain.godot_version
    gdunit4_version = $toolchain.gdunit4_version; project = $gamePath
}
$summary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $reportPath 'summary.json') -Encoding utf8
$summary | ConvertTo-Json -Compress
