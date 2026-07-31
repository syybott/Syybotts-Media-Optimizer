#requires -version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$failures = New-Object System.Collections.Generic.List[string]

foreach ($file in Get-ChildItem -LiteralPath $repositoryRoot -Recurse -File) {
    if ($file.Extension -notin @(".ps1", ".psm1", ".psd1")) {
        continue
    }
    if ($file.FullName -match '[\\/](dist|artifacts|work)[\\/]') {
        continue
    }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    )

    foreach ($parseError in @($parseErrors)) {
        $location = "{0}:{1}:{2}" -f @(
            $file.FullName
            $parseError.Extent.StartLineNumber
            $parseError.Extent.StartColumnNumber
        )
        [void]$failures.Add(
            "$location`: $($parseError.Message)"
        )
    }

    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    if (
        $bytes.Length -lt 3 -or
        $bytes[0] -ne 0xEF -or
        $bytes[1] -ne 0xBB -or
        $bytes[2] -ne 0xBF
    ) {
        [void]$failures.Add(
            "$($file.FullName): Windows PowerShell source must use UTF-8 with BOM."
        )
    }
}

$versionPath = Join-Path $repositoryRoot "version.json"
try {
    $version = Get-Content -LiteralPath $versionPath -Raw | ConvertFrom-Json
    foreach ($property in @(
        "productVersion",
        "fileVersion",
        "engineVersion",
        "copyWorkerVersion",
        "ps2exeVersion"
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$version.$property)) {
            [void]$failures.Add("version.json is missing '$property'.")
        }
    }
}
catch {
    [void]$failures.Add("version.json is invalid: $($_.Exception.Message)")
}

foreach ($requiredPath in @(
    "src\MediaOptimizer.Gui.ps1",
    "src\MediaOptimizer.Engine.ps1",
    "src\MediaOptimizer.CopyWorker.ps1",
    "build\Build-MediaOptimizer.ps1",
    ".github\workflows\build.yml"
)) {
    $fullRequiredPath = Join-Path $repositoryRoot $requiredPath
    if (-not (Test-Path -LiteralPath $fullRequiredPath -PathType Leaf)) {
        [void]$failures.Add("Missing required project file: $requiredPath")
    }
}

$guiPath = Join-Path $repositoryRoot "src\MediaOptimizer.Gui.ps1"
if (Test-Path -LiteralPath $guiPath -PathType Leaf) {
    $guiSource = [IO.File]::ReadAllText($guiPath)
    foreach ($url in [regex]::Matches($guiSource, 'https?://[^"\s]+')) {
        if (-not $url.Value.StartsWith("https://", [StringComparison]::OrdinalIgnoreCase)) {
            [void]$failures.Add("Non-HTTPS tool URL: $($url.Value)")
        }
    }
    $webPChecksum = [regex]::Match(
        $guiSource,
        '(?m)^\$WebPArchiveSha256\s*=\s*"([a-fA-F0-9]{64})"\r?$'
    )
    if (-not $webPChecksum.Success) {
        [void]$failures.Add("The pinned WebP SHA-256 checksum is missing or invalid.")
    }
    foreach ($requiredAssembly in @(
        "System.IO.Compression",
        "System.IO.Compression.FileSystem"
    )) {
        if ($guiSource -notmatch (
            'Add-Type\s+-AssemblyName\s+' + [regex]::Escape($requiredAssembly)
        )) {
            [void]$failures.Add(
                "The downloader does not load required assembly '$requiredAssembly'."
            )
        }
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    throw "$($failures.Count) static validation failure(s)."
}

Write-Host "Static checks passed." -ForegroundColor Green
