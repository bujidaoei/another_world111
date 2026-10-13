#requires -Version 7.0
# Pure classification of captured logs against a passed JUnit and a frozen policy.
# The wrapper retains the raw streams and performs source-hash collection separately.

function Test-GdUnitStrictPhaseError {
    param([string]$Stdout, [string]$Stderr)
    return ($Stdout + $Stderr) -match 'SCRIPT ERROR:|Parse Error:|ERROR:|(?i:ObjectDB.*leak|\bRIDs?\b.*leak)'
}

function Get-GdUnitPassedJUnit {
    param([Parameter(Mandatory)][xml]$Document)
    $root = $Document.get_DocumentElement()
    # XML's PowerShell adapter exposes the report's name attribute as .Name.
    # Use the actual DOM getter, never that adapted attribute, for node identity.
    if ($root.get_Name() -cne 'testsuites') { throw 'JUnit root must be testsuites.' }
    $declared = 0
    if (-not [int]::TryParse($root.GetAttribute('tests'), [ref]$declared) -or $declared -le 0) {
        throw 'No complete nonzero test execution in fresh JUnit.'
    }
    $nodes = @($Document.SelectNodes('//testcase'))
    if ($nodes.Count -ne $declared) { throw 'JUnit declared count differs from actual testcase nodes.' }
    if (@($Document.SelectNodes('//failure|//error|//skipped|//flakyFailure|//flakyError')).Count -ne 0) {
        throw 'JUnit contains failure, error, skipped or flaky testcase results.'
    }
    $suiteTotal = 0
    foreach ($node in @($root) + @($Document.SelectNodes('//testsuite'))) {
        foreach ($attribute in @('failures', 'errors', 'skipped', 'flaky')) {
            if (-not $node.HasAttribute($attribute)) { continue }
            $number = -1
            if (-not [int]::TryParse($node.GetAttribute($attribute), [ref]$number) -or $number -ne 0) {
                throw "JUnit $attribute must be exactly zero."
            }
        }
        if ($node.get_Name() -ceq 'testsuite') {
            $count = -1
            if (-not [int]::TryParse($node.GetAttribute('tests'), [ref]$count) -or $count -lt 0) {
                throw 'JUnit suite test count is invalid.'
            }
            $suiteTotal += $count
        }
    }
    if ($suiteTotal -ne $declared) { throw 'JUnit suite totals differ from root count.' }
    $passed = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($node in $nodes) {
        $identity = $node.GetAttribute('classname') + ':' + $node.GetAttribute('name')
        if ([string]::IsNullOrWhiteSpace($node.GetAttribute('name')) -or -not $passed.Add($identity)) {
            throw 'JUnit testcase names are missing or duplicated.'
        }
    }
    return [pscustomobject]@{ Tests = $declared; PassedCaseIds = $passed }
}

function ConvertFrom-GdUnitDiagnosticJson {
    param([string]$Text)
    $options = [Text.Json.JsonDocumentOptions]::new()
    $options.MaxDepth = 4
    $options.AllowTrailingCommas = $false
    $options.CommentHandling = [Text.Json.JsonCommentHandling]::Disallow
    $document = [Text.Json.JsonDocument]::Parse($Text, $options)
    try {
        if ($document.RootElement.ValueKind -ne [Text.Json.JsonValueKind]::Object) { throw 'Diagnostic must be a JSON object.' }
        $values = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
        foreach ($property in $document.RootElement.EnumerateObject()) {
            if ($property.Value.ValueKind -ne [Text.Json.JsonValueKind]::String -or $values.ContainsKey($property.Name)) {
                throw 'Diagnostic values must be strings with unique exact-case keys.'
            }
            $values.Add($property.Name, $property.Value.GetString())
        }
        return ,$values
    }
    finally { $document.Dispose() }
}

function Test-GdUnitExactJson {
    param($Values, $Expected)
    if ($Values.get_Count() -ne $Expected.get_Count()) { return $false }
    foreach ($key in $Expected.get_Keys()) {
        if (-not $Values.ContainsKey($key) -or $Values[$key] -cne [string]$Expected[$key]) { return $false }
    }
    return $true
}

function Test-GdUnitFrame {
    param($Actual, $Expected)
    return $Actual.method -ceq $Expected.method -and $Actual.path -ceq $Expected.path -and $Actual.line -eq $Expected.line
}

function Get-GdUnitDiagnosticAudit {
    param(
        [string]$Stdout,
        [string]$Stderr,
        [Parameter(Mandatory)]$PassedJUnit,
        [Parameter(Mandatory)]$Policy,
        [Parameter(Mandatory)]$ObservedSourceHashes
    )
    if (($Policy.policy_version -isnot [int] -and $Policy.policy_version -isnot [long]) -or $Policy.policy_version -ne 2 -or $Policy.ContainsKey('suite_resource') -or $Policy.ContainsKey('suite_classname')) {
        throw 'Only explicitly registered policy version 2 is supported.'
    }
    $productionSource = 'res://presentation/game_session.gd'
    $assertSource = 'res://addons/gdUnit4/src/asserts/GdUnitGodotErrorAssertImpl.gd'
    $sourcePaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $null = $sourcePaths.Add($productionSource)
    $null = $sourcePaths.Add($assertSource)
    $suites = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $classnames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    if ($Policy.suites -isnot [Collections.IDictionary] -or $Policy.suites.Count -eq 0) { throw 'Policy must explicitly register at least one diagnostic suite.' }
    foreach ($resource in $Policy.suites.Keys) {
        $suite = $Policy.suites[$resource]
        if ($resource -cnotmatch '^res://tests/(?:[a-z0-9_]+/)*test_[a-z0-9_]+\.gd$' -or $suite.classname -cnotmatch '^test_[a-z0-9_]+$' -or [IO.Path]::GetFileNameWithoutExtension($resource) -cne $suite.classname -or -not $classnames.Add($suite.classname)) { throw 'Registered suite resource/classname must be exact, distinct game test identities.' }
        if ([string]::IsNullOrWhiteSpace($suite.evidence_origin) -or $suite.observed_log_sha256 -cnotmatch '^[0-9A-F]{64}$') { throw 'Registered suites require an actual observation origin and SHA256.' }
        foreach ($tail in $suite.allowed_tail_frames) {
            if ($tail.path -cne $resource -or [string]::IsNullOrWhiteSpace($tail.method) -or ($tail.line -isnot [int] -and $tail.line -isnot [long]) -or $tail.line -le 0) { throw 'Suite-specific tails must belong to their registered suite and exact line.' }
        }
        $suites.Add($resource, $suite)
        $null = $sourcePaths.Add($resource)
    }
    if ($Policy.source_sha256.Count -ne $sourcePaths.Count) { throw 'Policy must anchor exactly Main, official assert and every registered suite.' }
    foreach ($source in $sourcePaths) {
        if (-not $Policy.source_sha256.ContainsKey($source) -or $Policy.source_sha256[$source] -cnotmatch '^[0-9A-F]{64}$') { throw 'Frozen source SHA256 is missing or malformed.' }
    }
    foreach ($tail in $Policy.allowed_framework_tail_frames) {
        if ($tail.path -cnotmatch '^res://addons/gdUnit4/src/(?:[a-zA-Z0-9_]+/)*[a-zA-Z0-9_]+\.gd$' -or [string]::IsNullOrWhiteSpace($tail.method) -or ($tail.line -isnot [int] -and $tail.line -isnot [long]) -or $tail.line -le 0) { throw 'Shared tails must be exact official GdUnit framework frames.' }
    }
    $expected = [Collections.Generic.List[object]]::new()
    $unexpected = [Collections.Generic.List[object]]::new()
    $native = [Collections.Generic.List[object]]::new()
    $script = [Collections.Generic.List[object]]::new()
    $budgetFailures = [Collections.Generic.List[string]]::new()
    $counts = @{}
    $registeredRuleCounts = @{}
    $signatures = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($resource in $suites.Keys) { $registeredRuleCounts[$resource] = 0 }
    if ($Policy.rules.Count -le 0) { throw 'Frozen diagnostic policy cannot have an empty rule list.' }
    foreach ($rule in $Policy.rules) {
        if (($rule.budget -isnot [int] -and $rule.budget -isnot [long]) -or $rule.budget -ne 1 -or $counts.ContainsKey([string]$rule.id)) { throw 'Frozen rules must have distinct IDs and integer budget one.' }
        if (-not $suites.ContainsKey([string]$rule.suite_resource)) { throw 'Every diagnostic rule must belong to an explicitly registered suite.' }
        $ruleSourcePaths = @($productionSource, $assertSource, $rule.suite_resource)
        if ($rule.case -cnotmatch '^test_[a-z0-9_]+$' -or $rule.stack_prefix.Count -lt 5) { throw 'Frozen rule must identify a specific case and full source/assert stack.' }
        $jsonShape = if ($rule.json.module -ceq 'save') { @{ code = $rule.json.code; module = 'save'; operation = 'save'; version = '0.1.0' } } else { @{ code = 'io_error'; module = 'preferences'; operation = 'save' } }
        if ($rule.json.code -cnotin @('io_error', 'future_schema') -or -not (Test-GdUnitExactJson $rule.json $jsonShape)) { throw 'Frozen JSON must be a precisely scoped save/preferences diagnostic.' }
        $origin = $rule.stack_prefix[0]
        $expectedOrigin = if ($rule.json.module -ceq 'save') { '_save_progress' } else { '_save_preferences' }
        if ($origin.method -cne $expectedOrigin -or $origin.path -cne $productionSource) { throw 'Frozen diagnostic has the wrong production origin.' }
        $assertPosition = -1
        for ($prefixIndex = 0; $prefixIndex -lt $rule.stack_prefix.Count; $prefixIndex++) {
            $prefixFrame = $rule.stack_prefix[$prefixIndex]
            if (($prefixFrame.line -isnot [int] -and $prefixFrame.line -isnot [long]) -or $prefixFrame.line -le 0 -or $prefixFrame.path -cnotin $ruleSourcePaths) { throw 'Frozen prefix frame must have an exact anchored source location belonging to its rule suite.' }
            if ($prefixFrame.method -ceq '_execute' -and $prefixFrame.path -ceq $assertSource -and $prefixFrame.line -eq 17) { $assertPosition = $prefixIndex }
        }
        if ($assertPosition -lt 0 -or $assertPosition + 1 -ge $rule.stack_prefix.Count -or -not (Test-GdUnitFrame $rule.stack_prefix[$assertPosition + 1] @{ method = 'is_push_error'; path = $assertSource; line = 132 })) { throw 'Official GdUnit is_push_error stack is absent from frozen prefix.' }
        $caseFrame = $rule.stack_prefix[-1]
        if ($caseFrame.method -cne $rule.case -or $caseFrame.path -cne $rule.suite_resource) { throw 'Frozen prefix must end at its registered suite corresponding testcase source.' }
        $signature = ($rule.json.GetEnumerator() | Sort-Object Key | ForEach-Object { $_.Key + '=' + $_.Value }) -join ';'
        $signature += '|' + (($rule.stack_prefix | ForEach-Object { $_.method + ':' + $_.path + ':' + $_.line }) -join '|')
        if (-not $signatures.Add($signature)) { throw 'Diagnostic rules must not have ambiguous identical JSON/stack signatures.' }
        $registeredRuleCounts[$rule.suite_resource]++
        $counts[[string]$rule.id] = 0
    }
    foreach ($resource in $registeredRuleCounts.Keys) {
        if ($registeredRuleCounts[$resource] -eq 0) { throw 'A registered diagnostic suite must have an observed, scoped rule.' }
    }
    foreach ($stream in @(@{ name = 'stdout'; text = $Stdout }, @{ name = 'stderr'; text = $Stderr })) {
        # ANSI styling is removed only for matching; raw original bytes are retained by the caller.
        $clean = [regex]::Replace([string]$stream.text, '\x1B\[[0-?]*[ -/]*[@-~]', '')
        $lines = [regex]::Split($clean, '\r?\n')
        for ($index = 0; $index -lt $lines.Length; $index++) {
            $line = $lines[$index]
            if ($line -match 'SCRIPT ERROR:|Parse Error:') {
                $script.Add(@{ stream = $stream.name; line = $index + 1; reason = 'script_or_parse_error' })
                continue
            }
            if ($line -notmatch 'ERROR:' -and $line -match '(?i)ObjectDB.*leak|\bRIDs?\b.*leak|\b[1-9][0-9]* orphans?\b') {
                $native.Add(@{ stream = $stream.name; line = $index + 1; reason = 'leak_or_orphan' })
            }
            if ($line -notmatch 'ERROR:') { continue }
            $headerLine = $index + 1
            $header = [regex]::Match($line, '^ERROR:\s*(\{.*\})\s*$')
            if (-not $header.Success) {
                $native.Add(@{ stream = $stream.name; line = $headerLine; reason = 'non_allowlisted_error_header' })
                continue
            }
            try { $values = ConvertFrom-GdUnitDiagnosticJson $header.Groups[1].Value }
            catch {
                $unexpected.Add(@{ stream = $stream.name; line = $headerLine; reason = 'invalid_diagnostic_json' })
                continue
            }
            if ($index + 2 -ge $lines.Length -or $lines[$index + 1].Trim() -cne 'at: push_error (core/variant/variant_utility.cpp:1023)' -or $lines[$index + 2].Trim() -cne 'GDScript backtrace (most recent call first):') {
                $unexpected.Add(@{ stream = $stream.name; line = $headerLine; reason = 'missing_official_push_error_backtrace' })
                continue
            }
            $frames = [Collections.Generic.List[object]]::new()
            $cursor = $index + 3
            while ($cursor -lt $lines.Length) {
                $frameMatch = [regex]::Match($lines[$cursor], '^\s+\[([0-9]+)\] (.+) \((res://[^()\r\n]+):([1-9][0-9]*)\)$')
                if (-not $frameMatch.Success) { break }
                if ([int]$frameMatch.Groups[1].Value -ne $frames.Count) { break }
                $frames.Add(@{ method = $frameMatch.Groups[2].Value; path = $frameMatch.Groups[3].Value; line = [int]$frameMatch.Groups[4].Value })
                $cursor++
            }
            if ($cursor -lt $lines.Length -and $lines[$cursor] -match '^\s+\[') {
                $unexpected.Add(@{ stream = $stream.name; line = $headerLine; reason = 'malformed_or_noncontiguous_stack' })
                continue
            }
            $matched = $null
            foreach ($rule in $Policy.rules) {
                if (-not (Test-GdUnitExactJson $values $rule.json) -or $frames.Count -lt $rule.stack_prefix.Count) { continue }
                $samePrefix = $true
                for ($frameIndex = 0; $frameIndex -lt $rule.stack_prefix.Count; $frameIndex++) {
                    if (-not (Test-GdUnitFrame $frames[$frameIndex] $rule.stack_prefix[$frameIndex])) { $samePrefix = $false; break }
                }
                if ($samePrefix) { $matched = $rule; break }
            }
            if ($null -eq $matched -or $stream.name -cne 'stderr') {
                $unexpected.Add(@{ stream = $stream.name; line = $headerLine; reason = 'json_case_or_origin_not_allowlisted' })
                continue
            }
            $identity = $suites[$matched.suite_resource].classname + ':' + $matched.case
            if (-not $PassedJUnit.PassedCaseIds.Contains($identity)) {
                $unexpected.Add(@{ stream = $stream.name; line = $headerLine; reason = 'corresponding_junit_case_not_passed' })
                continue
            }
            $hashesMatch = $true
            foreach ($source in $Policy.source_sha256.Keys) {
                if (-not $ObservedSourceHashes.ContainsKey($source) -or $ObservedSourceHashes[$source] -cne $Policy.source_sha256[$source]) { $hashesMatch = $false; break }
            }
            if (-not $hashesMatch) {
                $unexpected.Add(@{ stream = $stream.name; line = $headerLine; reason = 'frozen_source_hash_mismatch' })
                continue
            }
            $tailValid = $true
            for ($frameIndex = $matched.stack_prefix.Count; $frameIndex -lt $frames.Count; $frameIndex++) {
                $known = $false
                foreach ($tail in @($Policy.allowed_framework_tail_frames) + @($suites[$matched.suite_resource].allowed_tail_frames)) {
                    if (Test-GdUnitFrame $frames[$frameIndex] $tail) { $known = $true; break }
                }
                if (-not $known) { $tailValid = $false; break }
            }
            if (-not $tailValid) {
                $unexpected.Add(@{ stream = $stream.name; line = $headerLine; reason = 'non_official_stack_tail' })
                continue
            }
            $counts[$matched.id]++
            if ($counts[$matched.id] -gt $matched.budget) {
                $unexpected.Add(@{ stream = $stream.name; line = $headerLine; reason = 'diagnostic_budget_exceeded'; rule = $matched.id })
                continue
            }
            $expected.Add(@{ rule = $matched.id; suite_resource = $matched.suite_resource; case = $matched.case; stream = $stream.name; line = $headerLine; json = $matched.json })
            $index = $cursor - 1
        }
    }
    foreach ($rule in $Policy.rules) {
        if ($PassedJUnit.PassedCaseIds.Contains($suites[$rule.suite_resource].classname + ':' + $rule.case) -and $counts[$rule.id] -ne $rule.budget) {
            $budgetFailures.Add("$($rule.id): expected $($rule.budget), observed $($counts[$rule.id])")
        }
    }
    return [pscustomobject]@{
        ok = $unexpected.Count -eq 0 -and $native.Count -eq 0 -and $script.Count -eq 0 -and $budgetFailures.Count -eq 0
        policy_version = $Policy.policy_version
        expected_diagnostics = $expected.ToArray()
        unexpected_diagnostics = $unexpected.ToArray()
        unexpected_native = $native.ToArray()
        unexpected_script = $script.ToArray()
        budget_failures = $budgetFailures.ToArray()
    }
}
