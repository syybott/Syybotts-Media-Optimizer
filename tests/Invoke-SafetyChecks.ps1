#requires -version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
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

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    $threw = $false
    try {
        & $Action
    }
    catch {
        $threw = $true
    }
    if (-not $threw) {
        throw $Message
    }
}

$root = [IO.Path]::GetPathRoot((Get-Location).Path)
Assert-True `
    -Condition ((Get-NormalizedDirectoryPath $root) -eq $root) `
    -Message "Root normalization changed the filesystem root."

$parent = Join-Path ([IO.Path]::GetTempPath()) "media"
$child = Join-Path $parent "child"
$sibling = Join-Path ([IO.Path]::GetTempPath()) "media-backup"
Assert-True `
    -Condition (Test-DirectoryContains -Parent $parent -Child $parent) `
    -Message "Equal paths were not recognized as overlapping."
Assert-True `
    -Condition (Test-DirectoryContains -Parent $parent -Child $child) `
    -Message "A child path was not recognized as overlapping."
Assert-True `
    -Condition (-not (Test-DirectoryContains -Parent $parent -Child $sibling)) `
    -Message "A sibling path was incorrectly recognized as a child."

Assert-Throws `
    -Action {
        Assert-SafeRebuildDestination -Path $root -ConfirmedPath $root
    } `
    -Message "A filesystem root was accepted as a Rebuild destination."

$destination = Join-Path ([IO.Path]::GetTempPath()) "destination"
$other = Join-Path ([IO.Path]::GetTempPath()) "other"
Assert-Throws `
    -Action {
        Assert-SafeRebuildDestination `
            -Path $destination `
            -ConfirmedPath $other
    } `
    -Message "A mismatched Rebuild confirmation was accepted."

Write-Host "Safety checks passed." -ForegroundColor Green
