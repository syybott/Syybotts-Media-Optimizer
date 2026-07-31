#requires -version 5.1
[CmdletBinding()]
param(
    [string]$OutputFile = ""
)

$ErrorActionPreference = "Stop"

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$VersionFile = Join-Path $RepositoryRoot "version.json"
if (-not (Test-Path -LiteralPath $VersionFile -PathType Leaf)) {
    throw "Missing version manifest: $VersionFile"
}
$VersionManifest = Get-Content -LiteralPath $VersionFile -Raw | ConvertFrom-Json
$ProductVersion = [string]$VersionManifest.productVersion
$BuildVersion = [string]$VersionManifest.fileVersion
$RequiredPS2EXEVersion = [version][string]$VersionManifest.ps2exeVersion
$SourceFile = Join-Path $RepositoryRoot "src\MediaOptimizer.Gui.ps1"
$EngineFile = Join-Path $RepositoryRoot "src\MediaOptimizer.Engine.ps1"
$CopyWorkerFile = Join-Path $RepositoryRoot "src\MediaOptimizer.CopyWorker.ps1"
$IconFile = Join-Path $RepositoryRoot "assets\app.ico"
$FightMascotFile = Join-Path $RepositoryRoot "assets\fight-mode-mascot.png"
$OutputDirectory = Join-Path $RepositoryRoot "dist"
if ([string]::IsNullOrWhiteSpace($OutputFile)) {
    $OutputFile = Join-Path $OutputDirectory "SYYBOTTS-Media-Optimizer-$ProductVersion.exe"
}
elseif (-not [IO.Path]::IsPathRooted($OutputFile)) {
    $OutputFile = Join-Path $RepositoryRoot $OutputFile
}
$OutputFile = [IO.Path]::GetFullPath($OutputFile)
$OutputDirectory = Split-Path -Parent $OutputFile
$PreparedSourceFile = $null

Add-Type -AssemblyName System.Drawing

function Stop-WithError {
    param([Parameter(Mandatory = $true)][string]$Message)

    Write-Host ""
    Write-Host "BUILD ERROR: $Message" -ForegroundColor Red
    Write-Host ""

    if ($env:CI -ne "true") {
        Read-Host "Press Enter to close"
    }

    exit 1
}

try {
    if ($env:OS -ne "Windows_NT") {
        Stop-WithError "This EXE must be compiled on Windows."
    }

    if (-not [Environment]::Is64BitOperatingSystem) {
        Stop-WithError "This build targets 64-bit Windows."
    }

    if (-not (Test-Path -LiteralPath $SourceFile -PathType Leaf)) {
        Stop-WithError "Missing source file: $SourceFile"
    }
    if (-not (Test-Path -LiteralPath $EngineFile -PathType Leaf)) {
        Stop-WithError "Missing engine file: $EngineFile"
    }
    if (-not (Test-Path -LiteralPath $CopyWorkerFile -PathType Leaf)) {
        Stop-WithError "Missing Copy Mode worker: $CopyWorkerFile"
    }

    $HasIcon = Test-Path -LiteralPath $IconFile -PathType Leaf
    $HasFightMascot = Test-Path -LiteralPath $FightMascotFile -PathType Leaf

    if ($HasIcon) {
        try {
            $sourceIcon = New-Object System.Drawing.Icon($IconFile)

            if ($sourceIcon.Width -lt 1 -or $sourceIcon.Height -lt 1) {
                throw "The icon does not contain a readable Windows icon frame."
            }
        }
        catch {
            Stop-WithError "The supplied ICO is not readable by Windows: $($_.Exception.Message)"
        }
        finally {
            if ($null -ne $sourceIcon) {
                $sourceIcon.Dispose()
            }
        }
    }
    else {
        Write-Warning "No application icon was found. The executable will use the default PS2EXE icon."
    }

    if ($HasFightMascot) {
        try {
            $mascotImage = [System.Drawing.Image]::FromFile($FightMascotFile)

            if ($mascotImage.Width -lt 1 -or $mascotImage.Height -lt 1) {
                throw "The mascot image does not contain a readable image frame."
            }
        }
        catch {
            Stop-WithError "The Fight Mode mascot is not readable: $($_.Exception.Message)"
        }
        finally {
            if ($null -ne $mascotImage) {
                $mascotImage.Dispose()
            }
        }
    }
    else {
        Write-Warning "No Fight Mode mascot was found. Fight Mode will use its text-only presentation."
    }

    [void](New-Item -ItemType Directory -Path $OutputDirectory -Force)

    Write-Host "SYYBOTT'S MEDIA OPTIMIZER EXE BUILDER" -ForegroundColor Magenta
    Write-Host "Source: $SourceFile"
    Write-Host "Product version: $ProductVersion"
    Write-Host "Icon: $(if ($HasIcon) { $IconFile } else { '[default]' })"
    Write-Host "Fight Mode mascot: $(if ($HasFightMascot) { $FightMascotFile } else { '[not embedded]' })"
    Write-Host "Output: $OutputFile"
    Write-Host ""

    $existingModule = Get-Module -ListAvailable -Name ps2exe |
        Where-Object { $_.Version -eq $RequiredPS2EXEVersion } |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if ($null -eq $existingModule) {
        Write-Host "Installing pinned PS2EXE $RequiredPS2EXEVersion for the current user..." -ForegroundColor Cyan

        Import-Module PowerShellGet -Force -ErrorAction Stop
        $repository = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue

        if ($null -eq $repository) {
            Register-PSRepository -Default -ErrorAction Stop
            $repository = Get-PSRepository -Name PSGallery -ErrorAction Stop
        }

        $originalPolicy = $repository.InstallationPolicy

        try {
            if ($originalPolicy -ne "Trusted") {
                Set-PSRepository `
                    -Name PSGallery `
                    -InstallationPolicy Trusted `
                    -ErrorAction Stop
            }

            Install-Module `
                -Name ps2exe `
                -RequiredVersion $RequiredPS2EXEVersion `
                -Scope CurrentUser `
                -Force `
                -AllowClobber `
                -Repository PSGallery `
                -Confirm:$false `
                -ErrorAction Stop
        }
        finally {
            if ($originalPolicy -ne "Trusted") {
                Set-PSRepository `
                    -Name PSGallery `
                    -InstallationPolicy $originalPolicy `
                    -ErrorAction SilentlyContinue
            }
        }

        $existingModule = Get-Module -ListAvailable -Name ps2exe |
            Where-Object { $_.Version -eq $RequiredPS2EXEVersion } |
            Sort-Object Version -Descending |
            Select-Object -First 1
    }

    if ($null -eq $existingModule) {
        Stop-WithError "Pinned PS2EXE $RequiredPS2EXEVersion could not be installed or located."
    }

    Write-Host "Using PS2EXE $($existingModule.Version)." -ForegroundColor Green
    Import-Module $existingModule.Path -Force -ErrorAction Stop

    Remove-Item -LiteralPath $OutputFile -Force -ErrorAction SilentlyContinue

    Write-Host "Compiling the Windows executable..." -ForegroundColor Cyan

    $sourceText = [System.IO.File]::ReadAllText($SourceFile)
    $assetMarker = "__FIGHT_MODE_MASCOT_BASE64__"

    if (-not $sourceText.Contains($assetMarker)) {
        Stop-WithError "The GUI source does not contain the Fight Mode asset marker."
    }

    $preparedSource = $sourceText
    $preparedSource = [regex]::Replace(
        $preparedSource,
        '(?m)^\$GuiVersion\s*=\s*"[^"]*"\s*$',
        ('$GuiVersion = "' + $ProductVersion.Replace('"', '\"') + '"'),
        1
    )
    $preparedSource = [regex]::Replace(
        $preparedSource,
        '(?m)^\$EngineVersion\s*=\s*"[^"]*"\s*$',
        ('$EngineVersion = "' + ([string]$VersionManifest.engineVersion) + '"'),
        1
    )
    $preparedSource = [regex]::Replace(
        $preparedSource,
        '(?m)^\$CopyWorkerVersion\s*=\s*"[^"]*"\s*$',
        ('$CopyWorkerVersion = "' + ([string]$VersionManifest.copyWorkerVersion) + '"'),
        1
    )
    if ($HasFightMascot) {
        $mascotBase64 = [System.Convert]::ToBase64String(
            [System.IO.File]::ReadAllBytes($FightMascotFile)
        )
        $preparedSource = $preparedSource.Replace($assetMarker, $mascotBase64)
    }

    $engineBytes = [IO.File]::ReadAllBytes($EngineFile)
    $engineMemory = New-Object IO.MemoryStream
    $engineGzip = New-Object IO.Compression.GzipStream(
        $engineMemory,
        [IO.Compression.CompressionLevel]::Optimal,
        $true
    )
    $engineGzip.Write($engineBytes, 0, $engineBytes.Length)
    $engineGzip.Dispose()
    $engineBase64 = [Convert]::ToBase64String($engineMemory.ToArray())
    $engineMemory.Dispose()
    $enginePattern = '(?s)\$EmbeddedEngineGzipBase64\s*=\s*@''.*?''@'
    if (-not [regex]::IsMatch($preparedSource, $enginePattern)) {
        Stop-WithError "The GUI source does not contain the embedded engine block."
    }
    $engineRegex = New-Object Text.RegularExpressions.Regex($enginePattern)
    $preparedSource = $engineRegex.Replace(
        $preparedSource,
        ('$EmbeddedEngineGzipBase64 = @''' + "`r`n" + $engineBase64 + "`r`n'@"),
        1
    )

    $copyWorkerBase64 = [Convert]::ToBase64String(
        [IO.File]::ReadAllBytes($CopyWorkerFile)
    )
    if (-not $preparedSource.Contains("__COPY_MODE_WORKER_BASE64__")) {
        Stop-WithError "The GUI source does not contain the Copy Mode worker marker."
    }
    $preparedSource = $preparedSource.Replace(
        "__COPY_MODE_WORKER_BASE64__",
        $copyWorkerBase64
    )
    $PreparedSourceFile = Join-Path (
        [System.IO.Path]::GetTempPath()
    ) ("SYYBOTTS-GUI-Build-" + [guid]::NewGuid().ToString("N") + ".ps1")

    [System.IO.File]::WriteAllText(
        $PreparedSourceFile,
        $preparedSource,
        (New-Object System.Text.UTF8Encoding($false))
    )

    $ps2exeParameters = @{
        inputFile = $PreparedSourceFile
        outputFile = $OutputFile
        x64 = $true
        STA = $true
        noConsole = $true
        DPIAware = $true
        supportOS = $true
        title = "SYYBOTT'S Media Optimizer"
        description = "Image and video media optimization utility"
        company = "SYYBOTT"
        product = "SYYBOTT'S Media Optimizer"
        copyright = "Copyright 2026 SYYBOTT"
        version = $BuildVersion
    }
    if ($HasIcon) {
        $ps2exeParameters.iconFile = $IconFile
    }
    Invoke-ps2exe @ps2exeParameters

    if (-not (Test-Path -LiteralPath $OutputFile -PathType Leaf)) {
        Stop-WithError "PS2EXE did not create the expected executable."
    }

    if ($HasIcon) {
        $embeddedIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($OutputFile)
        if ($null -eq $embeddedIcon) {
            Stop-WithError "The compiled EXE does not expose the supplied icon."
        }
        $embeddedIcon.Dispose()
    }

    $hash = Get-FileHash -LiteralPath $OutputFile -Algorithm SHA256
    $hashFile = "$OutputFile.sha256"
    "$($hash.Hash.ToLowerInvariant())  $([System.IO.Path]::GetFileName($OutputFile))" |
        Set-Content -LiteralPath $hashFile -Encoding ASCII

    Write-Host ""
    Write-Host "BUILD COMPLETE" -ForegroundColor Green
    Write-Host "Executable: $OutputFile"
    Write-Host "SHA-256: $($hash.Hash)"
    Write-Host ""
    Write-Host "The compiled application is a single standalone EXE." -ForegroundColor Green

    if ($env:CI -ne "true") {
        Start-Process explorer.exe -ArgumentList @("/select,", "`"$OutputFile`"")
        Read-Host "Press Enter to close"
    }
}
catch {
    Stop-WithError $_.Exception.Message
}
finally {
    if (
        -not [string]::IsNullOrWhiteSpace($PreparedSourceFile) -and
        (Test-Path -LiteralPath $PreparedSourceFile -PathType Leaf)
    ) {
        Remove-Item -LiteralPath $PreparedSourceFile -Force -ErrorAction SilentlyContinue
    }
}
