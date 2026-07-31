#requires -version 5.1

BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $workerPath = Join-Path $repositoryRoot "src\MediaOptimizer.CopyWorker.ps1"
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile(
        $workerPath,
        [ref]$tokens,
        [ref]$errors
    )
    if ($errors.Count -gt 0) {
        throw "The Copy Mode worker does not parse."
    }

    foreach ($functionName in @(
        "Get-NormalizedDirectoryPath",
        "Test-DirectoryContains",
        "Assert-SafeRebuildDestination"
    )) {
        $functionAst = $ast.Find({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq $functionName
        }, $true)
        if ($null -eq $functionAst) {
            throw "Could not find function $functionName."
        }
        Invoke-Expression $functionAst.Extent.Text
    }
}

Describe "Copy Mode path safety" {
    It "preserves a filesystem root during normalization" {
        $root = [IO.Path]::GetPathRoot((Get-Location).Path)
        Get-NormalizedDirectoryPath $root | Should -Be $root
    }

    It "recognizes equal paths as overlapping" {
        $path = Join-Path ([IO.Path]::GetTempPath()) "same"
        Test-DirectoryContains -Parent $path -Child $path | Should -BeTrue
    }

    It "recognizes a child directory as overlapping" {
        $parent = Join-Path ([IO.Path]::GetTempPath()) "parent"
        $child = Join-Path $parent "child"
        Test-DirectoryContains -Parent $parent -Child $child | Should -BeTrue
    }

    It "does not use a sibling with a shared prefix as a child" {
        $parent = Join-Path ([IO.Path]::GetTempPath()) "media"
        $sibling = Join-Path ([IO.Path]::GetTempPath()) "media-backup"
        Test-DirectoryContains -Parent $parent -Child $sibling | Should -BeFalse
    }

    It "rejects a drive or filesystem root for Rebuild" {
        $root = [IO.Path]::GetPathRoot((Get-Location).Path)
        {
            Assert-SafeRebuildDestination -Path $root -ConfirmedPath $root
        } | Should -Throw
    }

    It "rejects a confirmation that does not match the resolved destination" {
        $destination = Join-Path ([IO.Path]::GetTempPath()) "destination"
        $other = Join-Path ([IO.Path]::GetTempPath()) "other"
        {
            Assert-SafeRebuildDestination `
                -Path $destination `
                -ConfirmedPath $other
        } | Should -Throw
    }
}
