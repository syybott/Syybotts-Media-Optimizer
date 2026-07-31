#requires -version 5.1

BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $enginePath = Join-Path $repositoryRoot "src\MediaOptimizer.Engine.ps1"
    $copyWorkerPath = Join-Path $repositoryRoot "src\MediaOptimizer.CopyWorker.ps1"
    $guiPath = Join-Path $repositoryRoot "src\MediaOptimizer.Gui.ps1"

    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile(
        $enginePath,
        [ref]$tokens,
        [ref]$errors
    )
    if ($errors.Count -gt 0) {
        throw "The media engine does not parse."
    }

    $functionAst = $ast.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq "Get-MinimumSavingsDecision"
    }, $true)
    if ($null -eq $functionAst) {
        throw "Could not find Get-MinimumSavingsDecision."
    }
    Invoke-Expression $functionAst.Extent.Text
}

Describe "Minimum savings decisions" {
    It "accepts an exact threshold boundary" {
        $decision = Get-MinimumSavingsDecision `
            -SourceLength 1000 `
            -CandidateLength 950 `
            -MinimumSavingsPct 5

        $decision.SavingsPct | Should -Be 5
        $decision.MeetsMinimum | Should -BeTrue
    }

    It "rejects a smaller candidate below the threshold" {
        $decision = Get-MinimumSavingsDecision `
            -SourceLength 1000 `
            -CandidateLength 951 `
            -MinimumSavingsPct 5

        $decision.IsSmaller | Should -BeTrue
        $decision.MeetsMinimum | Should -BeFalse
    }

    It "accepts any strictly smaller candidate when the threshold is zero" {
        $decision = Get-MinimumSavingsDecision `
            -SourceLength 1000 `
            -CandidateLength 999 `
            -MinimumSavingsPct 0

        $decision.MeetsMinimum | Should -BeTrue
    }

    It "rejects equal and larger candidates even when the threshold is zero" {
        (Get-MinimumSavingsDecision -SourceLength 1000 -CandidateLength 1000 -MinimumSavingsPct 0).MeetsMinimum |
            Should -BeFalse
        (Get-MinimumSavingsDecision -SourceLength 1000 -CandidateLength 1001 -MinimumSavingsPct 0).MeetsMinimum |
            Should -BeFalse
    }

    It "reports negative savings for a larger candidate" {
        $decision = Get-MinimumSavingsDecision `
            -SourceLength 1000 `
            -CandidateLength 1100 `
            -MinimumSavingsPct 5

        $decision.SavedBytes | Should -Be -100
        $decision.SavingsPct | Should -Be -10
    }
}

Describe "Minimum savings integration" {
    It "uses the same boundary behavior in Copy Mode" {
        $copyTokens = $null
        $copyErrors = $null
        $copyAst = [Management.Automation.Language.Parser]::ParseFile(
            $copyWorkerPath,
            [ref]$copyTokens,
            [ref]$copyErrors
        )
        $copyErrors.Count | Should -Be 0
        $copyFunctionAst = $copyAst.Find({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq "Get-MinimumSavingsDecision"
        }, $true)
        $copyFunctionAst | Should -Not -BeNullOrEmpty
        Invoke-Expression $copyFunctionAst.Extent.Text

        (Get-MinimumSavingsDecision -SourceLength 1000 -CandidateLength 950 -MinimumSavingsPct 5).MeetsMinimum |
            Should -BeTrue
        (Get-MinimumSavingsDecision -SourceLength 1000 -CandidateLength 951 -MinimumSavingsPct 5).MeetsMinimum |
            Should -BeFalse
    }

    It "wires separate persisted JPEG and video settings through the GUI" {
        $guiSource = Get-Content -LiteralPath $guiPath -Raw
        $guiSource | Should -Match 'JpegMinimumSavingsPct'
        $guiSource | Should -Match 'VideoMinimumSavingsPct'
        $guiSource | Should -Match '"-JpegMinimumSavingsPct"'
        $guiSource | Should -Match '"-VideoMinimumSavingsPct"'
    }

    It "applies both thresholds in Copy Mode" {
        $copySource = Get-Content -LiteralPath $copyWorkerPath -Raw
        $copySource | Should -Match '\$minimumDecision\.MeetsMinimum'
        $copySource | Should -Match 'JpegMinimumSavingsPct'
        $copySource | Should -Match 'VideoMinimumSavingsPct'
    }

    It "retains test outputs and reports threshold results" {
        $engineSource = Get-Content -LiteralPath $enginePath -Raw
        $engineSource | Should -Match 'Savings threshold:'
        $engineSource | Should -Match 'Test outputs below minimum:'
        $engineSource | Should -Not -Match 'No storage savings with this test setting.*Test output discarded'
    }
}
