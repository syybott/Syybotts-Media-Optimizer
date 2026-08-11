#requires -version 5.1

BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $enginePath = Join-Path $repositoryRoot "src\MediaOptimizer.Engine.ps1"
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
        $node.Name -eq "Get-OptimizerProfileRank"
    }, $true)
    if ($null -eq $functionAst) {
        throw "Could not find Get-OptimizerProfileRank."
    }
    Invoke-Expression $functionAst.Extent.Text

    function New-ProbeWithComment {
        param([string]$Comment)
        return [pscustomobject]@{
            format = [pscustomobject]@{
                tags = [pscustomobject]@{
                    comment = $Comment
                }
            }
        }
    }
}

Describe "Video optimizer marker compatibility" {
    It "recognizes the current Video Optimizer marker" {
        $probe = New-ProbeWithComment (
            "SYYBOTT'S Video Optimizer v1.0.32 | " +
            "Profile=Default | Rank=2 | CRF=24"
        )
        Get-OptimizerProfileRank -Probe $probe | Should -Be 2
    }

    It "recognizes the legacy Media Optimizer marker" {
        $probe = New-ProbeWithComment (
            "SYYBOTT'S Media Optimizer v1.0.13 | " +
            "Profile=Medium | Rank=2 | CRF=24"
        )
        Get-OptimizerProfileRank -Probe $probe | Should -Be 2
    }

    It "treats explicit Rank as authoritative" {
        $probe = New-ProbeWithComment (
            "SYYBOTT'S Video Optimizer | Rank=5 | CRF=24"
        )
        Get-OptimizerProfileRank -Probe $probe | Should -Be 5
    }

    It "infers rank from legacy CRF when Rank is absent" {
        $probe = New-ProbeWithComment (
            "SYYBOTT'S Media Optimizer v1.0.1 | CRF=24"
        )
        Get-OptimizerProfileRank -Probe $probe | Should -Be 2
    }

    It "does not recognize unrelated comments" {
        $probe = New-ProbeWithComment "Downloaded media preview"
        Get-OptimizerProfileRank -Probe $probe | Should -Be -1
    }
}

