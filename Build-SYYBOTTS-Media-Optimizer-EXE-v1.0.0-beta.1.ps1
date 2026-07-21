#requires -version 5.1
$ErrorActionPreference = "Stop"

$BuildVersion = "1.0.0.1"
$MinimumPS2EXEVersion = [version]"1.0.18"
$SourceFile = Join-Path $PSScriptRoot "SYYBOTTS-Media-Optimizer-GUI-v1.0.0-beta.1.ps1"
$EngineFile = Join-Path $PSScriptRoot "SYYBOTTS-Media-Optimizer-v1.0.31.ps1"
$CopyWorkerFile = Join-Path $PSScriptRoot "SYYBOTTS-Copy-Mode-v1.0.3.ps1"
$IconFile = Join-Path $PSScriptRoot "SYYBOTTS-Media-Optimizer-build-v1.0.0-beta.1.ico"
$FightMascotFile = Join-Path $PSScriptRoot "Assets\Fight-Mode-Mascot.png"
$OutputDirectory = Join-Path $PSScriptRoot "dist"
$OutputFile = Join-Path $OutputDirectory "SYYBOTTS-Media-Optimizer-v1.0.0-beta.1.exe"
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

    if (-not (Test-Path -LiteralPath $IconFile -PathType Leaf)) {
        Stop-WithError "Missing icon file: $IconFile"
    }

    if (-not (Test-Path -LiteralPath $FightMascotFile -PathType Leaf)) {
        Stop-WithError "Missing Fight Mode mascot: $FightMascotFile"
    }

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

    [void](New-Item -ItemType Directory -Path $OutputDirectory -Force)

    Write-Host "SYYBOTT'S MEDIA OPTIMIZER EXE BUILDER" -ForegroundColor Magenta
    Write-Host "Source: $SourceFile"
    Write-Host "Icon: $IconFile"
    Write-Host "Fight Mode mascot: $FightMascotFile"
    Write-Host "Output: $OutputFile"
    Write-Host ""

    $existingModule = Get-Module -ListAvailable -Name ps2exe |
        Where-Object { $_.Version -ge $MinimumPS2EXEVersion } |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if ($null -eq $existingModule) {
        Write-Host "Installing the current PS2EXE release (minimum $MinimumPS2EXEVersion) for the current user..." -ForegroundColor Cyan

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
                -MinimumVersion $MinimumPS2EXEVersion `
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
            Where-Object { $_.Version -ge $MinimumPS2EXEVersion } |
            Sort-Object Version -Descending |
            Select-Object -First 1
    }

    if ($null -eq $existingModule) {
        Stop-WithError "PS2EXE $MinimumPS2EXEVersion or newer could not be installed or located."
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

    $mascotBase64 = [System.Convert]::ToBase64String(
        [System.IO.File]::ReadAllBytes($FightMascotFile)
    )
    $preparedSource = $sourceText.Replace($assetMarker, $mascotBase64)

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

    Invoke-ps2exe `
        -inputFile $PreparedSourceFile `
        -outputFile $OutputFile `
        -x64 `
        -STA `
        -noConsole `
        -DPIAware `
        -supportOS `
        -iconFile $IconFile `
        -title "SYYBOTT'S Media Optimizer" `
        -description "Image and video media optimization utility" `
        -company "SYYBOTT" `
        -product "SYYBOTT'S Media Optimizer" `
        -copyright "Copyright 2026 SYYBOTT" `
        -version $BuildVersion

    if (-not (Test-Path -LiteralPath $OutputFile -PathType Leaf)) {
        Stop-WithError "PS2EXE did not create the expected executable."
    }

    $embeddedIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($OutputFile)

    if ($null -eq $embeddedIcon) {
        Stop-WithError "The compiled EXE does not expose an embedded icon."
    }

    $embeddedIcon.Dispose()

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
