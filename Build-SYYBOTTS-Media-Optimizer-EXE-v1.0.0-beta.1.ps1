$ErrorActionPreference = "Stop"

# ============================================================
# SYYBOTT'S MEDIA OPTIMIZER v1.0.31
# ============================================================
# Image mode requires cwebp.exe beside this script.
# Video mode requires ffmpeg.exe and ffprobe.exe beside this script.
# The selected mode scans this script's folder and normal subfolders.
# ============================================================

$MediaOptimizerVersion = "1.0.31"
$script:ReportRoot = Join-Path $PSScriptRoot "Logs"
$script:TestOutputRoot = $PSScriptRoot

function Read-OptimizationMode {
    while ($true) {
        Write-Host ""
        Write-Host "Choose what to optimize:" -ForegroundColor Cyan
        Write-Host "1. Images - Convert PNG/JPG/JPEG files to WebP and keep the most storage-efficient result" -ForegroundColor Green
        Write-Host "2. Videos - Convert supported video files to optimized MP4/H.264/AAC" -ForegroundColor Yellow
        Write-Host ""

        $answer = (Read-Host "Optimization type [1-2, default 1]").Trim()

        if ([string]::IsNullOrWhiteSpace($answer)) {
            return 1
        }

        switch ($answer) {
            "1" { return 1 }
            "2" { return 2 }
            default {
                Write-Host "Please enter 1 or 2." -ForegroundColor Yellow
            }
        }
    }
}

function Read-EndAction {
    while ($true) {
        Write-Host ""
        Write-Host "What would you like to do next?" -ForegroundColor Cyan
        Write-Host "1. Return to the main menu" -ForegroundColor Green
        Write-Host "2. Exit" -ForegroundColor Yellow
        Write-Host ""

        $answer = (Read-Host "Selection [1-2, default 2]").Trim()

        if ([string]::IsNullOrWhiteSpace($answer) -or $answer -eq "2") {
            return $false
        }

        if ($answer -eq "1") {
            return $true
        }

        Write-Host "Please enter 1 or 2." -ForegroundColor Yellow
    }
}

do {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor DarkMagenta
    Write-Host "              SYYBOTT'S MEDIA OPTIMIZER" -ForegroundColor Magenta
    Write-Host "                       v$MediaOptimizerVersion" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor DarkMagenta

    $script:RunAgain = $false
    $optimizationMode = Read-OptimizationMode

    switch ($optimizationMode) {
    1 {
        & {
            # IMAGE OPTIMIZATION MODE
            $ScriptVersion = $MediaOptimizerVersion
            $ScriptDisplayName = "SYYBOTT'S MEDIA OPTIMIZER - IMAGE MODE"

            # Invisible NTFS alternate-data-stream used to remember JPG/JPEG files whose
            # attempted WebP conversion was larger than the original.
            $JpegLargerWebPTagStream = "SYYBOTT.WebP.LargerAttempt"

            # =========================
            # FIXED PATHS
            # =========================

            # Keep cwebp.exe in the same folder as this script.
            $cwebp = Join-Path $PSScriptRoot "cwebp.exe"

            # Scan the folder containing this script and every subfolder beneath it.
            $targetFolder = $PSScriptRoot

            # =========================
            # DISPLAY COLORS
            # =========================

            $entryColors = @(
                "Cyan",
                "Green",
                "Yellow",
                "Magenta",
                "Blue",
                "White",
                "DarkCyan",
                "DarkGreen",
                "DarkYellow",
                "DarkMagenta"
            )

            # =========================
            # HELPERS
            # =========================

            function Read-YesNoOption {
                param(
                    [Parameter(Mandatory = $true)]
                    [string]$Prompt,

                    [Parameter(Mandatory = $true)]
                    [bool]$Default
                )

                $defaultLabel = if ($Default) { "Y" } else { "N" }

                while ($true) {
                    $answer = (Read-Host "$Prompt [Y/N, default $defaultLabel]").Trim()

                    if ([string]::IsNullOrWhiteSpace($answer)) {
                        return $Default
                    }

                    switch ($answer.ToUpperInvariant()) {
                        "Y"   { return $true }
                        "YES" { return $true }
                        "N"   { return $false }
                        "NO"  { return $false }
                        default {
                            Write-Host "Please enter Y or N." -ForegroundColor Yellow
                        }
                    }
                }
            }

            function Read-IntegerOption {
                param(
                    [Parameter(Mandatory = $true)]
                    [string]$Prompt,

                    [Parameter(Mandatory = $true)]
                    [int]$Minimum,

                    [Parameter(Mandatory = $true)]
                    [int]$Maximum,

                    [Parameter(Mandatory = $true)]
                    [int]$Default
                )

                while ($true) {
                    $answer = (Read-Host "$Prompt [$Minimum-$Maximum, default $Default]").Trim()

                    if ([string]::IsNullOrWhiteSpace($answer)) {
                        return $Default
                    }

                    [int]$value = 0

                    if (
                        [int]::TryParse($answer, [ref]$value) -and
                        $value -ge $Minimum -and
                        $value -le $Maximum
                    ) {
                        return $value
                    }

                    Write-Host "Please enter a whole number from $Minimum through $Maximum." -ForegroundColor Yellow
                }
            }

            function Format-ByteSize {
                param(
                    [Parameter(Mandatory = $true)]
                    [long]$Bytes
                )

                if ($Bytes -ge 1TB) {
                    return "{0:N2} TB" -f ($Bytes / 1TB)
                }
                elseif ($Bytes -ge 1GB) {
                    return "{0:N2} GB" -f ($Bytes / 1GB)
                }
                elseif ($Bytes -ge 1MB) {
                    return "{0:N2} MB" -f ($Bytes / 1MB)
                }
                elseif ($Bytes -ge 1KB) {
                    return "{0:N2} KB" -f ($Bytes / 1KB)
                }
                else {
                    return "$Bytes bytes"
                }
            }

            function Format-NetSavings {
                param(
                    [Parameter(Mandatory = $true)]
                    [long]$Bytes
                )

                if ($Bytes -ge 0) {
                    return "Net saved: $(Format-ByteSize $Bytes)"
                }
                else {
                    return "Net increase: $(Format-ByteSize ([math]::Abs($Bytes)))"
                }
            }

            function Test-WebPFile {
                param(
                    [Parameter(Mandatory = $true)]
                    [string]$Path
                )

                try {
                    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
                        return $false
                    }

                    $file = Get-Item -LiteralPath $Path

                    if ($file.Length -lt 12) {
                        return $false
                    }

                    $stream = [System.IO.File]::Open(
                        $Path,
                        [System.IO.FileMode]::Open,
                        [System.IO.FileAccess]::Read,
                        [System.IO.FileShare]::Read
                    )

                    try {
                        $header = New-Object byte[] 12
                        $bytesRead = $stream.Read($header, 0, 12)
                    }
                    finally {
                        $stream.Dispose()
                    }

                    if ($bytesRead -ne 12) {
                        return $false
                    }

                    $riff = [System.Text.Encoding]::ASCII.GetString($header, 0, 4)
                    $webp = [System.Text.Encoding]::ASCII.GetString($header, 8, 4)

                    if ($riff -ne "RIFF" -or $webp -ne "WEBP") {
                        return $false
                    }

                    [long]$declaredLength = [System.BitConverter]::ToUInt32($header, 4) + 8
                    return ($declaredLength -eq $file.Length)
                }
                catch {
                    return $false
                }
            }

            function Invoke-CWebP {
                param(
                    [Parameter(Mandatory = $true)]
                    [string[]]$Arguments
                )

                $processInfo = New-Object System.Diagnostics.ProcessStartInfo
                $processInfo.FileName = $cwebp
                $processInfo.UseShellExecute = $false
                $processInfo.RedirectStandardOutput = $true
                $processInfo.RedirectStandardError = $true
                $processInfo.CreateNoWindow = $true

                $quotedArguments = foreach ($argument in $Arguments) {
                    if ($argument -match '\s|[()]') {
                        '"' + $argument + '"'
                    }
                    else {
                        $argument
                    }
                }

                $processInfo.Arguments = $quotedArguments -join " "

                $process = New-Object System.Diagnostics.Process
                $process.StartInfo = $processInfo
                [void]$process.Start()

                $standardOutput = $process.StandardOutput.ReadToEnd()
                $standardError = $process.StandardError.ReadToEnd()

                $process.WaitForExit()

                $result = [PSCustomObject]@{
                    ExitCode = $process.ExitCode
                    Output   = (($standardOutput, $standardError) -join [Environment]::NewLine).Trim()
                }

                $process.Dispose()
                return $result
            }

            function Get-ImageFilesSafe {
                param(
                    [Parameter(Mandatory = $true)]
                    [string]$Root
                )

                $results = New-Object System.Collections.Generic.List[object]
                $script:SkippedReparsePointDirs = New-Object System.Collections.Generic.List[string]
                $script:SkippedTestFolders = New-Object System.Collections.Generic.List[string]

                function Scan-Folder {
                    param(
                        [Parameter(Mandatory = $true)]
                        [string]$FolderPath
                    )

                    foreach ($item in (Get-ChildItem -LiteralPath $FolderPath -Force)) {
                        if ($item.PSIsContainer) {
                            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                                [void]$script:SkippedReparsePointDirs.Add($item.FullName)
                                continue
                            }

                            if (
                                $item.Name -ieq "Test Images" -or
                                $item.Name -ieq "Test Videos" -or
                                $item.Name -ieq "SYYBOTT-JPG-Test" -or
                                $item.Name -ieq "SYYBOTT-Video-Test"
                            ) {
                                [void]$script:SkippedTestFolders.Add($item.FullName)
                                continue
                            }

                            Scan-Folder -FolderPath $item.FullName
                        }
                        else {
                            switch ($item.Extension.ToLowerInvariant()) {
                                ".png"  { [void]$results.Add($item) }
                                ".jpg"  { [void]$results.Add($item) }
                                ".jpeg" { [void]$results.Add($item) }
                                ".webp" { [void]$results.Add($item) }
                            }
                        }
                    }
                }

                Scan-Folder -FolderPath $Root
                return $results | Sort-Object FullName
            }

            function Remove-FileSafe {
                param(
                    [Parameter(Mandatory = $true)]
                    [string]$Path
                )

                Remove-Item -LiteralPath $Path -Force
            }

            function Add-ImageIssue {
                param(
                    [Parameter(Mandatory = $true)]
                    [string]$Type,

                    [Parameter(Mandatory = $true)]
                    [string]$Path,

                    [Parameter(Mandatory = $true)]
                    [AllowEmptyString()]
                    [string]$Message
                )

                [void]$script:ImageIssues.Add([PSCustomObject]@{
                    Type    = $Type
                    Path    = $Path
                    Message = $Message
                })

                if (-not [string]::IsNullOrWhiteSpace($script:ImageReportPath)) {
                    $stamp = Get-Date -Format "HH:mm:ss"
                    $line = "[$stamp] [$Type] '$Path': $Message"
                    Add-Content -LiteralPath $script:ImageReportPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
                }
            }

            function Test-JpegLargerWebPTag {
                param(
                    [Parameter(Mandatory = $true)]
                    [string]$Path,

                    [Parameter(Mandatory = $true)]
                    [long]$SourceLength,

                    [Parameter(Mandatory = $true)]
                    [int]$JpegQuality,

                    [Parameter(Mandatory = $true)]
                    [string]$CwebpSha256
                )

                try {
                    $rawTag = Get-Content `
                        -LiteralPath $Path `
                        -Stream $JpegLargerWebPTagStream `
                        -Raw `
                        -ErrorAction Stop

                    $tag = $rawTag | ConvertFrom-Json -ErrorAction Stop

                    if ([int]$tag.SchemaVersion -ne 1) {
                        return $false
                    }

                    if ([string]$tag.Outcome -ne "WebPLarger") {
                        return $false
                    }

                    if ([int]$tag.JpegQuality -ne $JpegQuality) {
                        return $false
                    }

                    if ([long]$tag.SourceLength -ne $SourceLength) {
                        return $false
                    }

                    if (
                        -not [string]::Equals(
                            [string]$tag.CwebpSha256,
                            $CwebpSha256,
                            [System.StringComparison]::OrdinalIgnoreCase
                        )
                    ) {
                        return $false
                    }

                    $currentSourceHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash

                    return [string]::Equals(
                        [string]$tag.SourceSha256,
                        $currentSourceHash,
                        [System.StringComparison]::OrdinalIgnoreCase
                    )
                }
                catch {
                    return $false
                }
            }

            function Set-JpegLargerWebPTag {
                param(
                    [Parameter(Mandatory = $true)]
                    [string]$Path,

                    [Parameter(Mandatory = $true)]
                    [long]$SourceLength,

                    [Parameter(Mandatory = $true)]
                    [int]$JpegQuality,

                    [Parameter(Mandatory = $true)]
                    [string]$CwebpSha256
                )

                try {
                    $sourceHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash

                    $tag = [ordered]@{
                        SchemaVersion = 1
                        Outcome       = "WebPLarger"
                        JpegQuality   = $JpegQuality
                        SourceLength  = $SourceLength
                        SourceSha256  = $sourceHash
                        CwebpSha256   = $CwebpSha256
                        ScriptVersion = $ScriptVersion
                    }

                    $tag |
                        ConvertTo-Json -Compress |
                        Set-Content `
                            -LiteralPath $Path `
                            -Stream $JpegLargerWebPTagStream `
                            -Encoding UTF8 `
                            -Force `
                            -ErrorAction Stop

                    return $true
                }
                catch {
                    $script:LastJpegTagError = $_.Exception.Message
                    return $false
                }
            }

            function Test-PngHasTransparency {
                param(
                    [Parameter(Mandatory = $true)]
                    [string]$Path
                )

                $stream = $null
                $reader = $null

                try {
                    $stream = [System.IO.File]::OpenRead($Path)
                    $reader = New-Object System.IO.BinaryReader($stream)
                    $signature = $reader.ReadBytes(8)

                    if (
                        $signature.Count -ne 8 -or
                        $signature[0] -ne 137 -or
                        $signature[1] -ne 80 -or
                        $signature[2] -ne 78 -or
                        $signature[3] -ne 71
                    ) {
                        return $false
                    }

                    while (($stream.Position + 8) -le $stream.Length) {
                        $lengthBytes = $reader.ReadBytes(4)

                        if ($lengthBytes.Count -ne 4) {
                            return $false
                        }

                        [uint32]$chunkLength = (
                            ([uint32]$lengthBytes[0] -shl 24) -bor
                            ([uint32]$lengthBytes[1] -shl 16) -bor
                            ([uint32]$lengthBytes[2] -shl 8) -bor
                            [uint32]$lengthBytes[3]
                        )

                        $chunkTypeBytes = $reader.ReadBytes(4)

                        if ($chunkTypeBytes.Count -ne 4) {
                            return $false
                        }

                        $chunkType = [System.Text.Encoding]::ASCII.GetString(
                            $chunkTypeBytes
                        )

                        if (
                            $chunkLength -gt [int]::MaxValue -or
                            ($stream.Position + [long]$chunkLength + 4) -gt
                                $stream.Length
                        ) {
                            return $false
                        }

                        if ($chunkType -eq "IHDR") {
                            $chunkData = $reader.ReadBytes([int]$chunkLength)

                            if ($chunkData.Count -lt 10) {
                                return $false
                            }

                            $colorType = [int]$chunkData[9]
                            [void]$reader.ReadBytes(4)

                            if ($colorType -in @(4, 6)) {
                                return $true
                            }

                            continue
                        }

                        if ($chunkType -eq "tRNS") {
                            return $true
                        }

                        if ($chunkType -eq "IDAT") {
                            return $false
                        }

                        [void]$stream.Seek(
                            ([long]$chunkLength + 4),
                            [System.IO.SeekOrigin]::Current
                        )
                    }

                    return $false
                }
                catch {
                    return $false
                }
                finally {
                    if ($null -ne $reader) {
                        $reader.Dispose()
                    }
                    elseif ($null -ne $stream) {
                        $stream.Dispose()
                    }
                }
            }

            function Test-WebPHasTransparency {
                param(
                    [Parameter(Mandatory = $true)]
                    [string]$Path
                )

                $stream = $null
                $reader = $null

                try {
                    $stream = [System.IO.File]::OpenRead($Path)
                    $reader = New-Object System.IO.BinaryReader($stream)
                    $header = $reader.ReadBytes(12)

                    if (
                        $header.Count -ne 12 -or
                        [System.Text.Encoding]::ASCII.GetString(
                            $header,
                            0,
                            4
                        ) -ne "RIFF" -or
                        [System.Text.Encoding]::ASCII.GetString(
                            $header,
                            8,
                            4
                        ) -ne "WEBP"
                    ) {
                        return $false
                    }

                    while (($stream.Position + 8) -le $stream.Length) {
                        $chunkTypeBytes = $reader.ReadBytes(4)
                        $chunkSizeBytes = $reader.ReadBytes(4)

                        if (
                            $chunkTypeBytes.Count -ne 4 -or
                            $chunkSizeBytes.Count -ne 4
                        ) {
                            return $false
                        }

                        $chunkType = [System.Text.Encoding]::ASCII.GetString(
                            $chunkTypeBytes
                        )
                        [uint32]$chunkSize = [System.BitConverter]::ToUInt32(
                            $chunkSizeBytes,
                            0
                        )
                        [long]$dataStart = $stream.Position
                        [long]$paddedSize = (
                            [long]$chunkSize +
                            ([long]$chunkSize % 2)
                        )

                        if (($dataStart + $paddedSize) -gt $stream.Length) {
                            return $false
                        }

                        if ($chunkType -eq "ALPH") {
                            return $true
                        }

                        if ($chunkType -eq "VP8X" -and $chunkSize -ge 1) {
                            $flags = $reader.ReadByte()

                            if (($flags -band 0x10) -ne 0) {
                                return $true
                            }
                        }
                        elseif ($chunkType -eq "VP8L" -and $chunkSize -ge 5) {
                            $losslessHeader = $reader.ReadBytes(5)

                            if (
                                $losslessHeader.Count -eq 5 -and
                                $losslessHeader[0] -eq 0x2F
                            ) {
                                [uint32]$losslessBits = (
                                    [System.BitConverter]::ToUInt32(
                                        $losslessHeader,
                                        1
                                    )
                                )

                                if (
                                    ($losslessBits -band 0x10000000) -ne 0
                                ) {
                                    return $true
                                }
                            }
                        }

                        $stream.Position = $dataStart + $paddedSize
                    }

                    return $false
                }
                catch {
                    return $false
                }
                finally {
                    if ($null -ne $reader) {
                        $reader.Dispose()
                    }
                    elseif ($null -ne $stream) {
                        $stream.Dispose()
                    }
                }
            }

            function Invoke-ImageCollisionGroup {
                param(
                    [Parameter(Mandatory = $true)]
                    [object[]]$Sources,

                    [Parameter(Mandatory = $true)]
                    [string]$FinalWebPPath,

                    [Parameter(Mandatory = $true)]
                    [int]$PngCompression,

                    [Parameter(Mandatory = $true)]
                    [int]$JpegQuality
                )

                $candidateRecords = New-Object System.Collections.Generic.List[object]
                $sourceRecords = New-Object System.Collections.Generic.List[object]
                $backupRecords = New-Object System.Collections.Generic.List[object]
                $issues = New-Object System.Collections.Generic.List[object]
                $finalCreated = $false
                $candidateNumber = 0
                $generatedCandidates = 0
                $transparencyProtected = $false

                try {
                    $transparentPngPresent = $false

                    foreach ($source in $Sources) {
                        if (
                            -not (
                                Test-Path `
                                    -LiteralPath $source.FullName `
                                    -PathType Leaf
                            )
                        ) {
                            throw "Source file is missing: $($source.FullName)"
                        }

                        $sourceFile = Get-Item -LiteralPath $source.FullName
                        $extension = $sourceFile.Extension.ToLowerInvariant()

                        [void]$sourceRecords.Add([PSCustomObject]@{
                            File      = $sourceFile
                            Extension = $extension
                            Length    = [long]$sourceFile.Length
                        })

                        if (
                            $extension -eq ".png" -and
                            (Test-PngHasTransparency -Path $sourceFile.FullName)
                        ) {
                            $transparentPngPresent = $true
                        }
                    }

                    $existingWebPFile = $null

                    if (Test-Path -LiteralPath $FinalWebPPath -PathType Leaf) {
                        $existingWebPFile = Get-Item -LiteralPath $FinalWebPPath

                        [void]$sourceRecords.Add([PSCustomObject]@{
                            File      = $existingWebPFile
                            Extension = ".webp"
                            Length    = [long]$existingWebPFile.Length
                        })
                    }

                    foreach ($sourceRecord in $sourceRecords) {
                        if ($sourceRecord.Extension -eq ".webp") {
                            continue
                        }

                        if (
                            $transparentPngPresent -and
                            $sourceRecord.Extension -in @(".jpg", ".jpeg")
                        ) {
                            $transparencyProtected = $true
                            continue
                        }

                        $candidateNumber++
                        $candidatePath = (
                            "$FinalWebPPath.candidate-$candidateNumber.part"
                        )

                        Remove-Item `
                            -LiteralPath $candidatePath `
                            -Force `
                            -ErrorAction SilentlyContinue

                        if ($sourceRecord.Extension -eq ".png") {
                            $conversion = Invoke-CWebP -Arguments @(
                                "-z", "$PngCompression",
                                "-o", $candidatePath,
                                $sourceRecord.File.FullName
                            )
                            $candidatePreference = 0
                        }
                        else {
                            $conversion = Invoke-CWebP -Arguments @(
                                "-preset", "photo",
                                "-q", "$JpegQuality",
                                "-m", "6",
                                "-mt",
                                "-o", $candidatePath,
                                $sourceRecord.File.FullName
                            )
                            $candidatePreference = 3
                        }

                        if (
                            $conversion.ExitCode -ne 0 -or
                            -not (
                                Test-Path `
                                    -LiteralPath $candidatePath `
                                    -PathType Leaf
                            ) -or
                            -not (Test-WebPFile -Path $candidatePath)
                        ) {
                            $details = if ($conversion.Output) {
                                $conversion.Output
                            }
                            else {
                                "cwebp did not create a valid WebP."
                            }

                            throw (
                                "Conversion failed for {0}: {1}" -f
                                $sourceRecord.File.FullName,
                                $details
                            )
                        }

                        $candidateFile = Get-Item -LiteralPath $candidatePath
                        $generatedCandidates++

                        [void]$candidateRecords.Add([PSCustomObject]@{
                            Path       = $candidatePath
                            Length     = [long]$candidateFile.Length
                            SourceName = $sourceRecord.File.Name
                            Preference = $candidatePreference
                            Index      = $candidateNumber
                        })
                    }

                    if ($null -ne $existingWebPFile) {
                        if (Test-WebPFile -Path $existingWebPFile.FullName) {
                            $existingHasTransparency = (
                                Test-WebPHasTransparency `
                                    -Path $existingWebPFile.FullName
                            )

                            if (
                                $transparentPngPresent -and
                                -not $existingHasTransparency
                            ) {
                                $transparencyProtected = $true

                                [void]$issues.Add([PSCustomObject]@{
                                    Type = "TRANSPARENCY PROTECTION"
                                    Path = $existingWebPFile.FullName
                                    Message = (
                                        "The existing WebP was excluded from " +
                                        "selection because it does not retain " +
                                        "the transparent PNG's alpha channel."
                                    )
                                })
                            }
                            else {
                                $candidateNumber++
                                $candidatePath = (
                                    "$FinalWebPPath.candidate-$candidateNumber.part"
                                )

                                Copy-Item `
                                    -LiteralPath $existingWebPFile.FullName `
                                    -Destination $candidatePath `
                                    -Force `
                                    -ErrorAction Stop

                                if (-not (Test-WebPFile -Path $candidatePath)) {
                                    throw (
                                        "The copied existing WebP candidate " +
                                        "failed validation."
                                    )
                                }

                                $candidateFile = Get-Item `
                                    -LiteralPath $candidatePath

                                $existingCandidatePreference = if (
                                    $existingHasTransparency
                                ) {
                                    1
                                }
                                else {
                                    2
                                }

                                [void]$candidateRecords.Add(
                                    [PSCustomObject]@{
                                        Path       = $candidatePath
                                        Length     = [long]$candidateFile.Length
                                        SourceName = $existingWebPFile.Name
                                        Preference = $existingCandidatePreference
                                        Index      = $candidateNumber
                                    }
                                )
                            }
                        }
                        else {
                            [void]$issues.Add([PSCustomObject]@{
                                Type = "INVALID EXISTING WEBP"
                                Path = $existingWebPFile.FullName
                                Message = (
                                    "The existing WebP failed validation and " +
                                    "was not considered as a candidate."
                                )
                            })
                        }
                    }

                    if ($candidateRecords.Count -eq 0) {
                        throw "No valid WebP candidate was created."
                    }

                    $winner = $candidateRecords |
                        Sort-Object Length, Preference, Index |
                        Select-Object -First 1

                    foreach ($candidate in $candidateRecords) {
                        if ($candidate.Path -ne $winner.Path) {
                            Remove-FileSafe -Path $candidate.Path
                        }
                    }

                    foreach ($sourceRecord in $sourceRecords) {
                        $backupPath = "{0}.syybott-delete-{1}.bak" -f (
                            $sourceRecord.File.FullName
                        ), ([guid]::NewGuid().ToString("N"))

                        Move-Item `
                            -LiteralPath $sourceRecord.File.FullName `
                            -Destination $backupPath `
                            -ErrorAction Stop

                        [void]$backupRecords.Add([PSCustomObject]@{
                            OriginalPath = $sourceRecord.File.FullName
                            BackupPath   = $backupPath
                            Extension    = $sourceRecord.Extension
                            Length       = $sourceRecord.Length
                        })
                    }

                    Move-Item `
                        -LiteralPath $winner.Path `
                        -Destination $FinalWebPPath `
                        -ErrorAction Stop

                    $finalCreated = $true

                    if (-not (Test-WebPFile -Path $FinalWebPPath)) {
                        throw (
                            "The finalized duplicate WebP did not pass " +
                            "validation."
                        )
                    }

                    [long]$deletedSourceBytes = 0
                    $pngDeleted = 0
                    $jpgDeleted = 0
                    $webpDeleted = 0
                    $filesRemoved = 0
                    $deleteErrors = 0

                    foreach ($backup in $backupRecords) {
                        try {
                            Remove-FileSafe -Path $backup.BackupPath
                            $deletedSourceBytes += [long]$backup.Length
                            $filesRemoved++

                            switch ($backup.Extension) {
                                ".png" {
                                    $pngDeleted++
                                }
                                ".jpg" {
                                    $jpgDeleted++
                                }
                                ".jpeg" {
                                    $jpgDeleted++
                                }
                                ".webp" {
                                    $webpDeleted++
                                }
                            }
                        }
                        catch {
                            $deleteErrors++
                            $deleteMessage = $_.Exception.Message

                            [void]$issues.Add([PSCustomObject]@{
                                Type = "DUPLICATE DELETE ERROR"
                                Path = $backup.BackupPath
                                Message = $deleteMessage
                            })

                            try {
                                if (
                                    -not (
                                        Test-Path `
                                            -LiteralPath $backup.OriginalPath `
                                            -PathType Leaf
                                    )
                                ) {
                                    Move-Item `
                                        -LiteralPath $backup.BackupPath `
                                        -Destination $backup.OriginalPath `
                                        -ErrorAction Stop
                                }
                            }
                            catch {
                                [void]$issues.Add([PSCustomObject]@{
                                    Type = "DUPLICATE RESTORE ERROR"
                                    Path = $backup.BackupPath
                                    Message = $_.Exception.Message
                                })
                            }
                        }
                    }

                    $finalFile = Get-Item -LiteralPath $FinalWebPPath
                    [long]$finalLength = $finalFile.Length

                    return [PSCustomObject]@{
                        Success              = $true
                        Error                = $null
                        CandidatesCreated    = $generatedCandidates
                        PngDeleted           = $pngDeleted
                        JpgDeleted           = $jpgDeleted
                        WebpDeleted          = $webpDeleted
                        FilesRemoved         = $filesRemoved
                        TransparencyProtected = $transparencyProtected
                        DeleteErrors         = $deleteErrors
                        DataDeleted          = $deletedSourceBytes
                        NetSavings           = (
                            $deletedSourceBytes -
                            $finalLength
                        )
                        WinnerSource         = $winner.SourceName
                        WinnerSize           = $finalLength
                        Issues               = @($issues)
                    }
                }
                catch {
                    foreach ($candidate in $candidateRecords) {
                        Remove-Item `
                            -LiteralPath $candidate.Path `
                            -Force `
                            -ErrorAction SilentlyContinue
                    }

                    if ($finalCreated) {
                        Remove-Item `
                            -LiteralPath $FinalWebPPath `
                            -Force `
                            -ErrorAction SilentlyContinue
                    }

                    foreach ($backup in $backupRecords) {
                        if (
                            (
                                Test-Path `
                                    -LiteralPath $backup.BackupPath `
                                    -PathType Leaf
                            ) -and
                            -not (
                                Test-Path `
                                    -LiteralPath $backup.OriginalPath `
                                    -PathType Leaf
                            )
                        ) {
                            Move-Item `
                                -LiteralPath $backup.BackupPath `
                                -Destination $backup.OriginalPath `
                                -ErrorAction SilentlyContinue
                        }
                    }

                    return [PSCustomObject]@{
                        Success               = $false
                        Error                 = $_.Exception.Message
                        CandidatesCreated     = $generatedCandidates
                        PngDeleted            = 0
                        JpgDeleted            = 0
                        WebpDeleted           = 0
                        FilesRemoved          = 0
                        TransparencyProtected = $transparencyProtected
                        DeleteErrors          = 0
                        DataDeleted           = 0L
                        NetSavings            = 0L
                        WinnerSource          = $null
                        WinnerSize            = 0L
                        Issues                = @($issues)
                    }
                }
            }

            function Invoke-JpegTestBatch {
                param(
                    [Parameter(Mandatory = $true)]
                    [string]$Root,

                    [Parameter(Mandatory = $true)]
                    [int]$TestCount,

                    [Parameter(Mandatory = $true)]
                    [int]$QualityMode,

                    [Parameter(Mandatory = $true)]
                    [int]$CustomQuality
                )

                $rootFullPath = [System.IO.Path]::GetFullPath($Root).TrimEnd(
                    [char[]]@('\', '/')
                )
                $testFilesList = New-Object System.Collections.Generic.List[object]
                $excludedTestFolderNames = @(
                    "Test Images",
                    "Test Videos",
                    "SYYBOTT-JPG-Test",
                    "SYYBOTT-Video-Test"
                )

                function Scan-TestImageFolder {
                    param(
                        [Parameter(Mandatory = $true)]
                        [string]$FolderPath,

                        [Parameter(Mandatory = $true)]
                        [int]$Depth
                    )

                    try {
                        $folderItems = @(Get-ChildItem -LiteralPath $FolderPath -Force)
                    }
                    catch {
                        Write-Host "TEST FOLDER SKIP: $FolderPath" -ForegroundColor DarkYellow
                        Write-Host "    $($_.Exception.Message)" -ForegroundColor DarkYellow
                        return
                    }

                    foreach ($item in $folderItems) {
                        if ($item.PSIsContainer) {
                            if (
                                $item.Attributes -band
                                [System.IO.FileAttributes]::ReparsePoint
                            ) {
                                continue
                            }

                            if ($item.Name -in $excludedTestFolderNames) {
                                continue
                            }

                            if ($Depth -lt 2) {
                                Scan-TestImageFolder `
                                    -FolderPath $item.FullName `
                                    -Depth ($Depth + 1)
                            }

                            continue
                        }

                        if (
                            $item.Extension.ToLowerInvariant() -in @(
                                ".jpg",
                                ".jpeg"
                            )
                        ) {
                            [void]$testFilesList.Add($item)
                        }
                    }
                }

                Scan-TestImageFolder -FolderPath $rootFullPath -Depth 0

                $testFiles = @(
                    $testFilesList |
                        Sort-Object Name, FullName
                )

                if ($testFiles.Count -eq 0) {
                    Write-Host ""
                    Write-Host "No JPG/JPEG files were found within two folder levels of:" -ForegroundColor Yellow
                    Write-Host $rootFullPath -ForegroundColor Cyan
                    return
                }

                $testFolder = Join-Path $script:TestOutputRoot "Test Images"
                $oldTestRootFolder = Join-Path $rootFullPath "Test Images"
                $legacyRootFolder = Join-Path $rootFullPath "SYYBOTT-JPG-Test"
                [void](New-Item -ItemType Directory -Path $testFolder -Force)

                $qualities = if ($QualityMode -eq 1) {
                    @(90, 80, 10)
                }
                else {
                    @($CustomQuality)
                }

                $plannedOutputPaths = [System.Collections.Generic.HashSet[string]]::new(
                    [System.StringComparer]::OrdinalIgnoreCase
                )

                $imagesCompared = 0
                $existingOutputsUsed = 0
                $newOutputsCreated = 0
                $noSavingsDiscards = 0
                $testFailures = 0
                $sourcesAlreadyTested = 0
                $sourceNumber = 0

                Write-Host ""
                Write-Host "JPG/JPEG TEST BATCH" -ForegroundColor Magenta
                Write-Host "Media folder: $rootFullPath" -ForegroundColor White
                Write-Host "Output folder: $testFolder" -ForegroundColor White
                Write-Host "Source images available: $($testFiles.Count)" -ForegroundColor White
                Write-Host "Images requested: $TestCount" -ForegroundColor White
                Write-Host "Search depth: Selected folder plus two subfolder levels" -ForegroundColor White
                Write-Host "Original files changed: No" -ForegroundColor Green
                Write-Host ""

                foreach ($source in $testFiles) {
                    if ($imagesCompared -ge $TestCount) {
                        break
                    }

                    $sourceNumber++
                    $sourceFile = Get-Item -LiteralPath $source.FullName
                    $baseName = [System.IO.Path]::GetFileNameWithoutExtension(
                        $source.Name
                    )
                    $sourceExtensionName = (
                        $source.Extension.TrimStart(".").ToLowerInvariant()
                    )

                    $relativePath = $source.FullName.Substring(
                        $rootFullPath.Length
                    ).TrimStart([char[]]@('\', '/'))
                    $relativeDirectory = Split-Path -Parent $relativePath

                    $outputDirectory = if (
                        [string]::IsNullOrWhiteSpace($relativeDirectory)
                    ) {
                        $testFolder
                    }
                    else {
                        Join-Path $testFolder $relativeDirectory
                    }

                    $legacyMirroredDirectory = if (
                        [string]::IsNullOrWhiteSpace($relativeDirectory)
                    ) {
                        $legacyRootFolder
                    }
                    else {
                        Join-Path $legacyRootFolder $relativeDirectory
                    }

                    $oldTestMirroredDirectory = if (
                        [string]::IsNullOrWhiteSpace($relativeDirectory)
                    ) {
                        $oldTestRootFolder
                    }
                    else {
                        Join-Path $oldTestRootFolder $relativeDirectory
                    }

                    $sourceLegacyDirectory = Join-Path `
                        $source.DirectoryName `
                        "SYYBOTT-JPG-Test"

                    [void](New-Item `
                        -ItemType Directory `
                        -Path $outputDirectory `
                        -Force)

                    $qualityResults = New-Object System.Collections.Generic.List[object]
                    $hasUsableResult = $false
                    $sourceHasNewOutput = $false

                    Write-Host (
                        "[{0}/{1} | IMAGE] Testing {2}" -f
                        $sourceNumber,
                        $testFiles.Count,
                        $relativePath
                    ) -ForegroundColor DarkCyan

                    foreach ($quality in $qualities) {
                        $outputName = "{0}_{1}.webp" -f $baseName, $quality
                        $outputPath = Join-Path $outputDirectory $outputName

                        if (-not $plannedOutputPaths.Add($outputPath)) {
                            $outputName = "{0}_{1}_{2}.webp" -f (
                                $baseName,
                                $sourceExtensionName,
                                $quality
                            )
                            $outputPath = Join-Path $outputDirectory $outputName
                            [void]$plannedOutputPaths.Add($outputPath)
                        }

                        $candidatePaths = New-Object System.Collections.Generic.List[string]
                        $candidateSet = [System.Collections.Generic.HashSet[string]]::new(
                            [System.StringComparer]::OrdinalIgnoreCase
                        )

                        foreach ($candidatePath in @(
                            $outputPath,
                            (Join-Path $oldTestMirroredDirectory $outputName),
                            (Join-Path $oldTestRootFolder $outputName),
                            (Join-Path $legacyMirroredDirectory $outputName),
                            (Join-Path $legacyRootFolder $outputName),
                            (Join-Path $sourceLegacyDirectory $outputName)
                        )) {
                            if ($candidateSet.Add($candidatePath)) {
                                [void]$candidatePaths.Add($candidatePath)
                            }
                        }

                        $existingResult = $null

                        foreach ($candidatePath in $candidatePaths) {
                            if (-not (
                                Test-Path `
                                    -LiteralPath $candidatePath `
                                    -PathType Leaf
                            )) {
                                continue
                            }

                            try {
                                $candidateFile = Get-Item `
                                    -LiteralPath $candidatePath `
                                    -ErrorAction Stop

                                if (
                                    (Test-WebPFile -Path $candidatePath) -and
                                    [long]$candidateFile.Length -lt
                                    [long]$sourceFile.Length
                                ) {
                                    if (-not [string]::Equals(
                                        [IO.Path]::GetFullPath($candidatePath),
                                        [IO.Path]::GetFullPath($outputPath),
                                        [StringComparison]::OrdinalIgnoreCase
                                    )) {
                                        Copy-Item `
                                            -LiteralPath $candidatePath `
                                            -Destination $outputPath `
                                            -Force `
                                            -ErrorAction Stop
                                        $candidatePath = $outputPath
                                        $candidateFile = Get-Item `
                                            -LiteralPath $outputPath `
                                            -ErrorAction Stop
                                    }
                                    [long]$savedBytes = (
                                        [long]$sourceFile.Length -
                                        [long]$candidateFile.Length
                                    )
                                    [double]$savedPercent = (
                                        [double]$savedBytes /
                                        [double]$sourceFile.Length
                                    ) * 100

                                    $existingResult = [PSCustomObject]@{
                                        Quality      = $quality
                                        Status       = "Existing"
                                        TestSize     = [long]$candidateFile.Length
                                        SavedBytes   = $savedBytes
                                        SavedPercent = $savedPercent
                                        OutputPath   = $candidatePath
                                        Message      = ""
                                    }
                                    break
                                }

                                if ([IO.Path]::GetFullPath($candidatePath).StartsWith(
                                    [IO.Path]::GetFullPath($testFolder).TrimEnd('\') + '\',
                                    [StringComparison]::OrdinalIgnoreCase
                                )) {
                                    Remove-FileSafe -Path $candidatePath
                                    $noSavingsDiscards++
                                }
                            }
                            catch {
                                $testFailures++
                                Write-Host "    Existing test file error: $candidatePath" -ForegroundColor Red
                                Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
                            }
                        }

                        if ($null -ne $existingResult) {
                            [void]$qualityResults.Add($existingResult)
                            $existingOutputsUsed++
                            $hasUsableResult = $true
                            continue
                        }

                        $tempPath = "$outputPath.part"

                        Remove-Item `
                            -LiteralPath $tempPath `
                            -Force `
                            -ErrorAction SilentlyContinue

                        $conversion = Invoke-CWebP -Arguments @(
                            "-preset", "photo",
                            "-q", "$quality",
                            "-m", "6",
                            "-mt",
                            "-o", $tempPath,
                            $source.FullName
                        )

                        if (
                            $conversion.ExitCode -ne 0 -or
                            -not (
                                Test-Path `
                                    -LiteralPath $tempPath `
                                    -PathType Leaf
                            ) -or
                            -not (Test-WebPFile -Path $tempPath)
                        ) {
                            $testFailures++

                            $failureMessage = if ($conversion.Output) {
                                ($conversion.Output -split "`r?`n" |
                                    Where-Object { $_ -ne "" } |
                                    Select-Object -First 1)
                            }
                            else {
                                "Conversion or validation failed."
                            }

                            [void]$qualityResults.Add([PSCustomObject]@{
                                Quality      = $quality
                                Status       = "Failed"
                                TestSize     = 0L
                                SavedBytes   = 0L
                                SavedPercent = 0.0
                                OutputPath   = ""
                                Message      = $failureMessage
                            })

                            Remove-Item `
                                -LiteralPath $tempPath `
                                -Force `
                                -ErrorAction SilentlyContinue
                            continue
                        }

                        $tempFile = Get-Item -LiteralPath $tempPath

                        if ([long]$tempFile.Length -ge [long]$sourceFile.Length) {
                            $noSavingsDiscards++
                            Remove-FileSafe -Path $tempPath

                            [void]$qualityResults.Add([PSCustomObject]@{
                                Quality      = $quality
                                Status       = "NoSavings"
                                TestSize     = 0L
                                SavedBytes   = 0L
                                SavedPercent = 0.0
                                OutputPath   = ""
                                Message      = "No storage savings. Test output discarded."
                            })
                            continue
                        }

                        try {
                            Move-Item `
                                -LiteralPath $tempPath `
                                -Destination $outputPath `
                                -ErrorAction Stop

                            $outputFile = Get-Item -LiteralPath $outputPath
                            [long]$savedBytes = (
                                [long]$sourceFile.Length -
                                [long]$outputFile.Length
                            )
                            [double]$savedPercent = (
                                [double]$savedBytes /
                                [double]$sourceFile.Length
                            ) * 100

                            [void]$qualityResults.Add([PSCustomObject]@{
                                Quality      = $quality
                                Status       = "Created"
                                TestSize     = [long]$outputFile.Length
                                SavedBytes   = $savedBytes
                                SavedPercent = $savedPercent
                                OutputPath   = $outputPath
                                Message      = ""
                            })

                            $newOutputsCreated++
                            $hasUsableResult = $true
                            $sourceHasNewOutput = $true
                        }
                        catch {
                            $testFailures++

                            [void]$qualityResults.Add([PSCustomObject]@{
                                Quality      = $quality
                                Status       = "Failed"
                                TestSize     = 0L
                                SavedBytes   = 0L
                                SavedPercent = 0.0
                                OutputPath   = $outputPath
                                Message      = $_.Exception.Message
                            })

                            Remove-Item `
                                -LiteralPath $tempPath `
                                -Force `
                                -ErrorAction SilentlyContinue
                        }
                    }

                    Write-Host ""
                    Write-Host "IMAGE: $relativePath" -ForegroundColor Magenta
                    Write-Host "Original size: $(Format-ByteSize $sourceFile.Length)" -ForegroundColor White
                    Write-Host ""

                    foreach ($result in $qualityResults) {
                        Write-Host "Quality $($result.Quality):" -ForegroundColor Cyan

                        switch ($result.Status) {
                            "Existing" {
                                Write-Host "  Original size:   $(Format-ByteSize $sourceFile.Length)" -ForegroundColor White
                                Write-Host "  Test size:       $(Format-ByteSize $result.TestSize)" -ForegroundColor White
                                Write-Host "  Storage saved:   $(Format-ByteSize $result.SavedBytes)" -ForegroundColor Green
                                Write-Host (
                                    "  Size reduction:  {0:N2}%" -f
                                    $result.SavedPercent
                                ) -ForegroundColor Green
                                Write-Host "  Existing test output" -ForegroundColor DarkYellow
                                Write-Host "  Output: $($result.OutputPath)" -ForegroundColor Yellow
                            }
                            "Created" {
                                Write-Host "  Original size:   $(Format-ByteSize $sourceFile.Length)" -ForegroundColor White
                                Write-Host "  Test size:       $(Format-ByteSize $result.TestSize)" -ForegroundColor White
                                Write-Host "  Storage saved:   $(Format-ByteSize $result.SavedBytes)" -ForegroundColor Green
                                Write-Host (
                                    "  Size reduction:  {0:N2}%" -f
                                    $result.SavedPercent
                                ) -ForegroundColor Green
                                Write-Host "  New test output" -ForegroundColor Green
                                Write-Host "  Output: $($result.OutputPath)" -ForegroundColor Yellow
                            }
                            "NoSavings" {
                                Write-Host "  No storage savings. Test output discarded." -ForegroundColor DarkYellow
                            }
                            "Failed" {
                                Write-Host "  Test failed." -ForegroundColor Red

                                if (-not [string]::IsNullOrWhiteSpace($result.Message)) {
                                    Write-Host "  $($result.Message)" -ForegroundColor Red
                                }
                            }
                        }

                        Write-Host ""
                    }

                    if ($hasUsableResult) {
                        if ($sourceHasNewOutput) {
                            # New output was created for this source this run;
                            # count it and stop so the next run starts fresh.
                            $imagesCompared++
                        }
                        else {
                            # Every quality already had a valid retained output.
                            # This source was tested in a prior run; skip it so
                            # the next untested source is selected instead.
                            $sourcesAlreadyTested++
                            Write-Host "    Already tested; skipping to next source." -ForegroundColor DarkYellow
                            Write-Host ""
                        }
                    }
                    else {
                        Write-Host "This image did not produce a usable comparison and does not count toward the requested total." -ForegroundColor DarkYellow
                        Write-Host ""
                    }
                }

                if ($imagesCompared -eq 0 -and $sourcesAlreadyTested -ge $testFiles.Count) {
                    Write-Host "No untested source images remain. All $($testFiles.Count) supported image(s) have already been tested." -ForegroundColor Yellow
                }
                else {
                    Write-Host "JPG/JPEG test finished." -ForegroundColor Green
                }
                Write-Host "Images requested: $TestCount" -ForegroundColor Cyan
                Write-Host "Images compared: $imagesCompared" -ForegroundColor Cyan
                Write-Host "Already-tested sources skipped: $sourcesAlreadyTested" -ForegroundColor DarkYellow
                Write-Host "Existing outputs used: $existingOutputsUsed" -ForegroundColor DarkYellow
                Write-Host "New test outputs created: $newOutputsCreated" -ForegroundColor Green
                Write-Host "No-savings outputs discarded: $noSavingsDiscards" -ForegroundColor DarkYellow
                Write-Host "Test failures: $testFailures" -ForegroundColor $(if ($testFailures -gt 0) { "Red" } else { "Green" })
                Write-Host "Original files changed: 0" -ForegroundColor Green
                Write-Host "Output folder: $testFolder" -ForegroundColor Yellow
            }

            # =========================
            # PRECHECKS
            # =========================

            if (-not (Test-Path -LiteralPath $cwebp -PathType Leaf)) {
                Write-Host "ERROR: cwebp.exe was not found beside the script:" -ForegroundColor Red
                Write-Host $cwebp -ForegroundColor Red
                Read-Host "Press Enter to close"
                exit 1
            }

            $CwebpSha256 = (Get-FileHash -LiteralPath $cwebp -Algorithm SHA256).Hash

            Write-Host ""
            Write-Host "$ScriptDisplayName v$ScriptVersion" -ForegroundColor Magenta

            # =========================
            # INTERACTIVE OPTIONS
            # =========================

            Write-Host ""
            Write-Host "Choose image operation:" -ForegroundColor Cyan
            Write-Host "1. Optimize image library. Default: 1." -ForegroundColor White
            Write-Host "2. JPG/JPEG Test Batch - selected folder plus two subfolder levels, no originals changed." -ForegroundColor Green
            $ImageOperationMode = Read-IntegerOption `
                -Prompt "Image operation" `
                -Minimum 1 `
                -Maximum 2 `
                -Default 1

            if ($ImageOperationMode -eq 2) {
                Write-Host ""
                $ImageTestCount = Read-IntegerOption `
                    -Prompt "Number of images to test" `
                    -Minimum 1 `
                    -Maximum 10 `
                    -Default 5

                Write-Host ""
                Write-Host "Choose test quality output:" -ForegroundColor Cyan
                Write-Host "1. Create quality 90, 80, and 10 versions of each selected image. Default: 1." -ForegroundColor Green
                Write-Host "2. Create one version at a custom quality." -ForegroundColor White
                $ImageTestQualityMode = Read-IntegerOption `
                    -Prompt "Test quality mode" `
                    -Minimum 1 `
                    -Maximum 2 `
                    -Default 1

                $ImageTestCustomQuality = 90

                if ($ImageTestQualityMode -eq 2) {
                    $ImageTestCustomQuality = Read-IntegerOption `
                        -Prompt "Custom JPG/JPEG WebP quality" `
                        -Minimum 0 `
                        -Maximum 100 `
                        -Default 90
                }

                Invoke-JpegTestBatch `
                    -Root $targetFolder `
                    -TestCount $ImageTestCount `
                    -QualityMode $ImageTestQualityMode `
                    -CustomQuality $ImageTestCustomQuality

                $script:RunAgain = Read-EndAction
                return
            }

            Write-Host ""
            Write-Host "WEBP CONVERSION OPTIONS" -ForegroundColor Magenta
            Write-Host "Press Enter at any prompt to accept its displayed default." -ForegroundColor White
            Write-Host ""


            $CleanupExistingPairs = $true

            Write-Host ""
            Write-Host "Choose PNG handling:" -ForegroundColor Cyan
            Write-Host "1. Skip PNG - Leave PNG files untouched. Default: 2." -ForegroundColor White
            Write-Host "2. Process PNG - Convert PNG files to lossless WebP." -ForegroundColor Green
            $PngHandlingMode = Read-IntegerOption `
                -Prompt "PNG handling" `
                -Minimum 1 `
                -Maximum 2 `
                -Default 2
            $SkipPngFiles = ($PngHandlingMode -eq 1)

            Write-Host ""
            Write-Host "Choose JPG/JPEG handling:" -ForegroundColor Cyan
            Write-Host "1. Skip JPG/JPEG - Process PNG files only. Default: 1." -ForegroundColor White
            Write-Host "2. Process JPG/JPEG - Process every JPG/JPEG file; duplicate cleanup is automatic." -ForegroundColor Yellow
            $JpegHandlingMode = Read-IntegerOption `
                -Prompt "JPG/JPEG handling" `
                -Minimum 1 `
                -Maximum 2 `
                -Default 1

            $SkipJpegFiles = ($JpegHandlingMode -eq 1)
            $ProcessAllJpeg = ($JpegHandlingMode -eq 2)

            if (-not $SkipJpegFiles) {
                Write-Host ""
                Write-Host "============================================================" -ForegroundColor Red
                Write-Host "             JPG/JPEG PERMANENT-DELETION WARNING" -ForegroundColor Red
                Write-Host "============================================================" -ForegroundColor Red
                Write-Host $(if ($SkipPngFiles) {
                    "Duplicate cleanup can permanently delete JPG/JPEG and existing WebP files after a valid winner is installed. PNG files remain untouched."
                } else {
                    "Duplicate cleanup can permanently delete JPG/JPEG, PNG, and existing WebP files after a valid winner is installed."
                }) -ForegroundColor Yellow
                Write-Host "When a nontransparent PNG and JPG/JPEG share a name, the smallest valid WebP can be selected even when it came from a lossy JPG/JPEG source." -ForegroundColor Yellow
                Write-Host "Transparent PNG groups are protected: JPG/JPEG candidates and nontransparent existing WebPs cannot replace the transparent PNG result." -ForegroundColor White
                Write-Host "Back up the full library before continuing whenever possible." -ForegroundColor White
                Write-Host "============================================================" -ForegroundColor Red
                Write-Host ""

                $ProceedWithJpeg = Read-YesNoOption `
                    -Prompt "Proceed with the selected JPG/JPEG handling" `
                    -Default $false

                if (-not $ProceedWithJpeg) {
                    $JpegHandlingMode = 1
                    $SkipJpegFiles = $true
                    $ProcessAllJpeg = $false
                    Write-Host ""
                    Write-Host "JPG/JPEG processing disabled. Continuing with PNG files only." -ForegroundColor Yellow
                }
            }

            $ProcessImageCollisions = (-not $SkipJpegFiles)

            $PngCompressionLevel = 10
            if (-not $SkipPngFiles) {
                Write-Host ""
                Write-Host "PNG compression level?" -ForegroundColor Cyan
                Write-Host "1 = fastest. 10 = highest compression, smallest file. Default: 10." -ForegroundColor White
                $PngCompressionLevel = Read-IntegerOption `
                    -Prompt "PNG compression" `
                    -Minimum 1 `
                    -Maximum 10 `
                    -Default 10
            }

            # cwebp -z uses 0 through 9 internally.
            $PngCompression = $PngCompressionLevel - 1
            $JpegQuality = 90

            if (-not $SkipJpegFiles) {
                Write-Host ""
                Write-Host "JPG/JPEG WebP quality?" -ForegroundColor Cyan
                Write-Host "0-100. Higher preserves more detail. Default: 90. For lightweight devices, quality 10 is recommended (honestly it looks pretty good, test it below yourself)." -ForegroundColor White
                $JpegQuality = Read-IntegerOption `
                    -Prompt "JPG/JPEG quality" `
                    -Minimum 0 `
                    -Maximum 100 `
                    -Default 90
            }

            switch ($JpegHandlingMode) {
                1 {
                    $JpegHandlingDescription = "Skip JPG/JPEG"
                }
                2 {
                    $JpegHandlingDescription = "Process JPG/JPEG"
                }
            }

            Write-Host ""
            Write-Host "Selected options:" -ForegroundColor Magenta
            Write-Host "PNG handling:                 $(if ($SkipPngFiles) { 'Skip PNG' } else { 'Process PNG' })" -ForegroundColor White
            Write-Host "JPG/JPEG handling:            $JpegHandlingDescription" -ForegroundColor White
            if (-not $SkipPngFiles) {
                Write-Host "PNG compression:              $PngCompressionLevel/10 (lossless; cwebp effort $PngCompression)" -ForegroundColor White
            }

            if (-not $SkipJpegFiles) {
                Write-Host "JPG/JPEG WebP quality:        $JpegQuality/100" -ForegroundColor White
            }

            Write-Host ""

            $discoveredImageFiles = @(Get-ImageFilesSafe -Root $targetFolder)
            $discoveredSourceFiles = @(
                $discoveredImageFiles |
                Where-Object {
                    $_.Extension.ToLowerInvariant() -in @(
                        ".png",
                        ".jpg",
                        ".jpeg"
                    )
                }
            )
            $discoveredPngFiles = @(
                $discoveredSourceFiles |
                Where-Object {
                    $_.Extension.ToLowerInvariant() -eq ".png"
                }
            )
            $discoveredJpegFiles = @(
                $discoveredSourceFiles |
                Where-Object {
                    $_.Extension.ToLowerInvariant() -in @(
                        ".jpg",
                        ".jpeg"
                    )
                }
            )
            $discoveredWebPFiles = @(
                $discoveredImageFiles |
                Where-Object {
                    $_.Extension.ToLowerInvariant() -eq ".webp"
                }
            )

            $inventoryDuplicateGroups = @(
                $discoveredImageFiles |
                Group-Object {
                    [System.IO.Path]::ChangeExtension(
                        $_.FullName,
                        ".webp"
                    ).ToLowerInvariant()
                } |
                Where-Object {
                    @(
                        $_.Group |
                        ForEach-Object {
                            $_.Extension.ToLowerInvariant()
                        } |
                        Select-Object -Unique
                    ).Count -gt 1
                }
            )

            $duplicateJpegPaths = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::OrdinalIgnoreCase
            )

            foreach ($group in $inventoryDuplicateGroups) {
                foreach ($item in $group.Group) {
                    if (
                        $item.Extension.ToLowerInvariant() -in @(
                            ".jpg",
                            ".jpeg"
                        )
                    ) {
                        [void]$duplicateJpegPaths.Add($item.FullName)
                    }
                }
            }

            switch ($JpegHandlingMode) {
                1 {
                    $allFiles = if ($SkipPngFiles) {
                        @()
                    } else {
                        @($discoveredPngFiles)
                    }
                }
                2 {
                    $allFiles = @(
                        $discoveredSourceFiles |
                        Where-Object {
                            -not (
                                $SkipPngFiles -and
                                $_.Extension.ToLowerInvariant() -eq ".png"
                            )
                        }
                    )
                }
            }

            $allFiles = @($allFiles | Sort-Object FullName)
            $total = $allFiles.Count
            $pngFiles = @(
                $allFiles |
                Where-Object {
                    $_.Extension.ToLowerInvariant() -eq ".png"
                }
            )
            $jpgFiles = @(
                $allFiles |
                Where-Object {
                    $_.Extension.ToLowerInvariant() -in @(
                        ".jpg",
                        ".jpeg"
                    )
                }
            )
            $jpegFilesSkippedByOption = (
                $discoveredJpegFiles.Count -
                $jpgFiles.Count
            )
            $pngFilesSkippedByOption = (
                $discoveredPngFiles.Count -
                $pngFiles.Count
            )

            if ($total -eq 0) {
                if (
                    $SkipJpegFiles -and
                    $discoveredJpegFiles.Count -gt 0
                ) {
                    Write-Host "No image files were selected for processing." -ForegroundColor Yellow
                }
                else {
                    Write-Host "No supported image files were found in:" -ForegroundColor Yellow
                    Write-Host $targetFolder -ForegroundColor Cyan
                }

                Read-Host "Press Enter to close"
                exit 0
            }

            $initialImagePaths = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::OrdinalIgnoreCase
            )

            foreach ($imageFile in $allFiles) {
                [void]$initialImagePaths.Add($imageFile.FullName)

                $existingWebPPath = [System.IO.Path]::ChangeExtension(
                    $imageFile.FullName,
                    ".webp"
                )

                if (Test-Path -LiteralPath $existingWebPPath -PathType Leaf) {
                    [void]$initialImagePaths.Add($existingWebPPath)
                }
            }

            [long]$initialImageLibraryBytes = 0

            foreach ($initialImagePath in $initialImagePaths) {
                try {
                    $initialImageLibraryBytes += (
                        Get-Item `
                            -LiteralPath $initialImagePath `
                            -ErrorAction Stop
                    ).Length
                }
                catch {
                    # Files that disappear during measurement are ignored.
                }
            }

            $selectedSourcePaths = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::OrdinalIgnoreCase
            )

            foreach ($selectedSource in $allFiles) {
                [void]$selectedSourcePaths.Add($selectedSource.FullName)
            }

            $collisionPaths = @{}
            $collisionGroupKeyByPath = @{}
            $collisionGroupRecords = @{}
            $collisionGroups = New-Object System.Collections.Generic.List[object]

            if ($ProcessImageCollisions) {
                foreach ($group in $inventoryDuplicateGroups) {
                    $selectedSources = @(
                        $group.Group |
                        Where-Object {
                            $_.Extension.ToLowerInvariant() -ne ".webp" -and
                            $selectedSourcePaths.Contains($_.FullName)
                        }
                    )

                    if ($selectedSources.Count -eq 0) {
                        continue
                    }

                    $groupKey = [string]$group.Name
                    $finalWebPPath = [System.IO.Path]::ChangeExtension(
                        $selectedSources[0].FullName,
                        ".webp"
                    )

                    $groupRecord = [PSCustomObject]@{
                        Key       = $groupKey
                        FinalPath = $finalWebPPath
                        Sources   = @($selectedSources)
                    }

                    $collisionGroupRecords[$groupKey] = $groupRecord
                    [void]$collisionGroups.Add($groupRecord)

                    foreach ($item in $selectedSources) {
                        $collisionPaths[$item.FullName] = $true
                        $collisionGroupKeyByPath[$item.FullName] = $groupKey
                    }
                }
            }

            Write-Host "Scan root:" -ForegroundColor Magenta
            Write-Host $targetFolder -ForegroundColor White
            Write-Host ""
            Write-Host "Files found:" -ForegroundColor Magenta
            Write-Host "PNG selected:                $($pngFiles.Count)" -ForegroundColor Cyan
            Write-Host "JPG/JPEG selected:           $($jpgFiles.Count)" -ForegroundColor Green

            if ($jpegFilesSkippedByOption -gt 0) {
                Write-Host "JPG/JPEG skipped by option:  $jpegFilesSkippedByOption" -ForegroundColor DarkCyan
            }
            if ($pngFilesSkippedByOption -gt 0) {
                Write-Host "PNG skipped by option:       $pngFilesSkippedByOption" -ForegroundColor DarkCyan
            }

            Write-Host "Total files to process:      $total" -ForegroundColor Yellow
            Write-Host "Name-collision groups:       $($collisionGroups.Count)" -ForegroundColor DarkYellow
            Write-Host "Skipped reparse-point dirs:  $($script:SkippedReparsePointDirs.Count)" -ForegroundColor DarkYellow
            Write-Host ""

            if ($inventoryDuplicateGroups.Count -gt 0) {
                Write-Host "Duplicate groups found:       $($inventoryDuplicateGroups.Count)" -ForegroundColor DarkYellow
            }

            if ($collisionGroups.Count -gt 0) {
                Write-Host "Duplicate groups selected:    $($collisionGroups.Count)" -ForegroundColor DarkCyan
                Write-Host "Each selected group will keep the smallest valid WebP candidate." -ForegroundColor DarkCyan
            }

            if ($script:SkippedReparsePointDirs.Count -gt 0) {
                Write-Host "Junctions / symbolic-link directories were excluded from the scan." -ForegroundColor DarkYellow
            }

            Write-Host ""
            Write-Host "Mode summary:" -ForegroundColor Magenta
            Write-Host "Existing source/WebP pairs:   Cleaned automatically" -ForegroundColor White
            Write-Host "PNG handling:                 $(if ($SkipPngFiles) { 'Skip PNG' } else { 'Process PNG' })" -ForegroundColor White
            Write-Host "JPG/JPEG handling:            $JpegHandlingDescription" -ForegroundColor White

            if (-not $SkipPngFiles) {
                Write-Host "PNG compression:              $PngCompressionLevel/10 (lossless; cwebp effort $PngCompression)" -ForegroundColor White
            }

            if (-not $SkipJpegFiles) {
                Write-Host "JPG/JPEG WebP quality:        $JpegQuality" -ForegroundColor White
            }

            Write-Host ""

            Write-Host "IMMEDIATE CLEANUP MODE" -ForegroundColor Yellow
            Write-Host "Newly created WEBP files are validated and then cleaned up immediately." -ForegroundColor Yellow
            Write-Host "Deleted files bypass the Recycle Bin." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "What the image optimizer does:" -ForegroundColor Magenta
            Write-Host "1. Creates and validates temporary WebPs before deleting originals." -ForegroundColor White
            Write-Host "2. Cleans existing source/WebP pairs automatically." -ForegroundColor White
            Write-Host "3. PNG stays lossless; JPG/JPEG keeps whichever file is smaller." -ForegroundColor White

            if ($SkipJpegFiles) {
                Write-Host "4. JPG/JPEG files are ignored." -ForegroundColor White
            }
            else {
                Write-Host "4. All JPG/JPEG files are processed; duplicate-name groups are consolidated automatically." -ForegroundColor White
            }

            Write-Host "5. Transparent PNG groups cannot be replaced by JPG/JPEG-derived or nontransparent WebP candidates." -ForegroundColor White

            Write-Host "6. Linked directories are excluded." -ForegroundColor White
            Write-Host ""

            Write-Host "Use this script at your own risk." -ForegroundColor Yellow
            Write-Host "The script author and contributors are not responsible for lost or damaged data." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Press Enter to continue to the final confirmation." -ForegroundColor Yellow
            Write-Host "Press Ctrl+C now to exit without changing any image files." -ForegroundColor Yellow
            [void](Read-Host)

            Write-Host ""
            $confirmation = Read-Host 'Type CONVERT AND DELETE to begin'
            $normalizedConfirmation = (($confirmation -replace '\s+', ' ').Trim())

            $confirmationAccepted = [string]::Equals(
                $normalizedConfirmation,
                "CONVERT AND DELETE",
                [System.StringComparison]::OrdinalIgnoreCase
            )

            if (-not $confirmationAccepted) {
                Write-Host ""
                Write-Host "Cancelled. No image files were changed." -ForegroundColor Yellow
                Read-Host "Press Enter to close"
                exit 0
            }

            [void](New-Item `
                -ItemType Directory `
                -Path $script:ReportRoot `
                -Force)

            $script:ImageReportPath = Join-Path $script:ReportRoot (
                "SYYBOTT-Media-Optimizer-Image-Report-{0}.txt" -f
                (Get-Date -Format "yyyyMMdd-HHmmss")
            )
            $script:ImageIssues = New-Object System.Collections.Generic.List[object]

            $imageHeader = New-Object System.Collections.Generic.List[string]
            [void]$imageHeader.Add("SYYBOTT'S MEDIA OPTIMIZER v$MediaOptimizerVersion")
            [void]$imageHeader.Add("IMAGE OPTIMIZATION REPORT")
            [void]$imageHeader.Add("Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
            [void]$imageHeader.Add("Scan root: $targetFolder")
            [void]$imageHeader.Add("")
            [void]$imageHeader.Add("SETTINGS")
            [void]$imageHeader.Add("PNG handling: $(if ($SkipPngFiles) { 'Skip PNG' } else { 'Process PNG' })")
            [void]$imageHeader.Add("JPG/JPEG handling: $JpegHandlingDescription")
            if (-not $SkipPngFiles) {
                [void]$imageHeader.Add("PNG compression: $PngCompressionLevel/10")
            }
            if (-not $SkipJpegFiles) {
                [void]$imageHeader.Add("JPG/JPEG WebP quality: $JpegQuality/100")
            }
            [void]$imageHeader.Add("Duplicate groups found: $($inventoryDuplicateGroups.Count)")
            [void]$imageHeader.Add("Duplicate groups selected: $($collisionGroups.Count)")
            [void]$imageHeader.Add("")
            $imageHeader | Set-Content -LiteralPath $script:ImageReportPath -Encoding UTF8

            Write-Host ""
            Write-Host "Beginning conversion with immediate cleanup..." -ForegroundColor Magenta
            Write-Host "Report file: $script:ImageReportPath" -ForegroundColor DarkCyan
            Write-Host ""

            # =========================
            # COUNTERS
            # =========================

            $newConversions = 0
            $existingPairsSkipped = 0
            $existingPairsCleaned = 0
            $collisionSkips = 0
            $collisionGroupsProcessed = 0
            $duplicateFilesRemoved = 0
            $duplicateWebpFilesRemoved = 0
            $transparencyProtectedGroups = 0
            $failed = 0
            $deleteErrors = 0

            $pngDeleted = 0
            $jpgDeleted = 0
            $largerWebpDeleted = 0
            $equalWebpDeleted = 0
            $largerWebpJpgTagsWritten = 0
            $largerWebpJpgTagSkips = 0
            $jpegTagWriteWarnings = 0

            [long]$netSavings = 0
            [long]$dataDeleted = 0

            # =========================
            # MAIN LOOP
            # =========================

            $processedCollisionGroups = @{}

            for ($index = 0; $index -lt $total; $index++) {
                $source = $allFiles[$index]
                $current = $index + 1
                $color = $entryColors[$index % $entryColors.Count]
                $progressText = Format-NetSavings $netSavings

                if ($collisionPaths.ContainsKey($source.FullName)) {
                    if (-not $ProcessImageCollisions) {
                        Write-Host "[$current/$total | $progressText] MATCHING-NAME SKIP: $($source.Name)" -ForegroundColor DarkYellow
                        $collisionSkips++
                        continue
                    }

                    $groupKey = [string]$collisionGroupKeyByPath[$source.FullName]

                    if ($processedCollisionGroups.ContainsKey($groupKey)) {
                        continue
                    }

                    $processedCollisionGroups[$groupKey] = $true
                    $groupRecord = $collisionGroupRecords[$groupKey]

                    $collisionResult = Invoke-ImageCollisionGroup `
                        -Sources $groupRecord.Sources `
                        -FinalWebPPath $groupRecord.FinalPath `
                        -PngCompression $PngCompression `
                        -JpegQuality $JpegQuality

                    if (-not $collisionResult.Success) {
                        $failed++
                        Write-Host "[$current/$total | $progressText] MATCHING-NAME ERROR: $([System.IO.Path]::GetFileName($groupRecord.FinalPath))" -ForegroundColor Red
                        Write-Host "    $($collisionResult.Error)" -ForegroundColor Red
                        Add-ImageIssue `
                            -Type "MATCHING-NAME ERROR" `
                            -Path (($groupRecord.Sources | ForEach-Object FullName) -join " | ") `
                            -Message $collisionResult.Error
                        continue
                    }

                    $collisionGroupsProcessed++
                    $newConversions += $collisionResult.CandidatesCreated
                    $pngDeleted += $collisionResult.PngDeleted
                    $jpgDeleted += $collisionResult.JpgDeleted
                    $duplicateWebpFilesRemoved += $collisionResult.WebpDeleted
                    $duplicateFilesRemoved += $collisionResult.FilesRemoved

                    if ($collisionResult.TransparencyProtected) {
                        $transparencyProtectedGroups++
                    }

                    $deleteErrors += $collisionResult.DeleteErrors
                    $dataDeleted += $collisionResult.DataDeleted
                    $netSavings += $collisionResult.NetSavings

                    foreach ($issue in $collisionResult.Issues) {
                        Add-ImageIssue `
                            -Type $issue.Type `
                            -Path $issue.Path `
                            -Message $issue.Message
                    }

                    $progressText = Format-NetSavings $netSavings
                    Write-Host "[$current/$total | $progressText] DUPLICATE GROUP CONSOLIDATED; smallest valid WebP kept from $($collisionResult.WinnerSource)" -ForegroundColor DarkCyan
                    continue
                }

                try {
                    if (-not (Test-Path -LiteralPath $source.FullName -PathType Leaf)) {
                        Write-Host "[$current/$total | $progressText] SOURCE MISSING: $($source.Name)" -ForegroundColor DarkYellow
                        Add-ImageIssue `
                            -Type "SOURCE MISSING" `
                            -Path $source.FullName `
                            -Message "The source disappeared after the initial scan."
                        continue
                    }

                    $sourceFile = Get-Item -LiteralPath $source.FullName
                    [long]$sourceLength = $sourceFile.Length
                    $sourceName = $sourceFile.Name
                    $extension = $sourceFile.Extension.ToLowerInvariant()
                    $webpPath = [System.IO.Path]::ChangeExtension($sourceFile.FullName, ".webp")
                    $webpExists = Test-Path -LiteralPath $webpPath -PathType Leaf

                    # ---------------------------------
                    # EXISTING SAME-NAMED WEBP PAIR
                    # ---------------------------------
                    if ($webpExists) {
                        if (-not (Test-WebPFile -Path $webpPath)) {
                            Write-Host "[$current/$total | $progressText] ERROR: Existing WEBP is invalid: $webpPath" -ForegroundColor Red
                            Add-ImageIssue -Type "INVALID WEBP" -Path $webpPath -Message "Existing WebP failed validation."
                            $failed++
                            continue
                        }

                        if (-not $CleanupExistingPairs) {
                            Write-Host "[$current/$total | $progressText] EXISTING PAIR SKIP: $sourceName" -ForegroundColor $color
                            $existingPairsSkipped++
                            continue
                        }

                        $webpFile = Get-Item -LiteralPath $webpPath
                        [long]$webpLength = $webpFile.Length
                        $existingPairsCleaned++


                        try {
                            if ($extension -eq ".png") {
                                Remove-FileSafe -Path $sourceFile.FullName
                                $pngDeleted++
                                $dataDeleted += $sourceLength
                                $netSavings += $sourceLength

                                $progressText = Format-NetSavings $netSavings
                                Write-Host "[$current/$total | $progressText] PNG DELETED; existing valid WEBP kept: $sourceName" -ForegroundColor $color
                            }
                            else {
                                if ($webpLength -lt $sourceLength) {
                                    Remove-FileSafe -Path $sourceFile.FullName
                                    $jpgDeleted++
                                    $dataDeleted += $sourceLength
                                    $netSavings += $sourceLength

                                    $progressText = Format-NetSavings $netSavings
                                    Write-Host "[$current/$total | $progressText] JPG/JPEG deleted; existing smaller WEBP kept: $sourceName" -ForegroundColor $color
                                }
                                elseif ($webpLength -gt $sourceLength) {
                                    Remove-FileSafe -Path $webpFile.FullName
                                    $largerWebpDeleted++
                                    $dataDeleted += $webpLength
                                    $netSavings += $webpLength

                                    $progressText = Format-NetSavings $netSavings
                                    Write-Host "[$current/$total | $progressText] Larger existing WEBP deleted; JPG/JPEG kept: $sourceName" -ForegroundColor $color
                                }
                                else {
                                    Remove-FileSafe -Path $webpFile.FullName
                                    $equalWebpDeleted++
                                    $dataDeleted += $webpLength
                                    $netSavings += $webpLength

                                    $progressText = Format-NetSavings $netSavings
                                    Write-Host "[$current/$total | $progressText] Equal-size existing WEBP deleted; JPG/JPEG kept: $sourceName" -ForegroundColor $color
                                }
                            }
                        }
                        catch {
                            $deleteErrors++
                            $progressText = Format-NetSavings $netSavings
                            Write-Host "[$current/$total | $progressText] DELETE ERROR: $($sourceFile.FullName)" -ForegroundColor Red
                            Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
                            Add-ImageIssue -Type "DELETE ERROR" -Path $sourceFile.FullName -Message $_.Exception.Message
                        }

                        continue
                    }

                    # ---------------------------------
                    # NO EXISTING WEBP
                    # ---------------------------------

                    if (
                        $extension -in @(".jpg", ".jpeg") -and
                        (Test-JpegLargerWebPTag `
                            -Path $sourceFile.FullName `
                            -SourceLength $sourceLength `
                            -JpegQuality $JpegQuality `
                            -CwebpSha256 $CwebpSha256)
                    ) {
                        $largerWebpJpgTagSkips++
                        Write-Host "[$current/$total | $progressText] PREVIOUS LARGER-WEBP SKIP: $sourceName" -ForegroundColor DarkCyan
                        continue
                    }

                    $tempWebpPath = "$webpPath.part"

                    if (Test-Path -LiteralPath $tempWebpPath -PathType Leaf) {
                        try {
                            Remove-FileSafe -Path $tempWebpPath
                        }
                        catch {
                            $failed++
                            Write-Host "[$current/$total | $progressText] ERROR: Could not remove stale temp file: $tempWebpPath" -ForegroundColor Red
                            Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
                            Add-ImageIssue -Type "TEMP DELETE ERROR" -Path $tempWebpPath -Message $_.Exception.Message
                            continue
                        }
                    }

                    if ($extension -eq ".png") {
                        $result = Invoke-CWebP -Arguments @(
                            "-z", "$PngCompression",
                            "-o", $tempWebpPath,
                            $sourceFile.FullName
                        )
                    }
                    else {
                        $result = Invoke-CWebP -Arguments @(
                            "-preset", "photo",
                            "-q", "$JpegQuality",
                            "-m", "6",
                            "-mt",
                            "-o", $tempWebpPath,
                            $sourceFile.FullName
                        )
                    }

                    if (
                        $result.ExitCode -ne 0 -or
                        -not (Test-Path -LiteralPath $tempWebpPath -PathType Leaf) -or
                        -not (Test-WebPFile -Path $tempWebpPath)
                    ) {
                        Write-Host "[$current/$total | $progressText] ERROR: Conversion failed: $($sourceFile.FullName)" -ForegroundColor Red

                        if ($result.Output) {
                            $result.Output -split "`r?`n" | ForEach-Object {
                                if ($_ -ne "") {
                                    Write-Host "    $_" -ForegroundColor Red
                                }
                            }
                        }

                        Add-ImageIssue `
                            -Type "CONVERSION ERROR" `
                            -Path $sourceFile.FullName `
                            -Message $result.Output
                        Remove-Item -LiteralPath $tempWebpPath -Force -ErrorAction SilentlyContinue
                        $failed++
                        continue
                    }

                    try {
                        Move-Item -LiteralPath $tempWebpPath -Destination $webpPath -Force
                    }
                    catch {
                        Write-Host "[$current/$total | $progressText] ERROR: Could not finalize temp WEBP: $tempWebpPath" -ForegroundColor Red
                        Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
                        Add-ImageIssue -Type "FINALIZE ERROR" -Path $tempWebpPath -Message $_.Exception.Message
                        Remove-Item -LiteralPath $tempWebpPath -Force -ErrorAction SilentlyContinue
                        $failed++
                        continue
                    }

                    $newConversions++
                    $webpFile = Get-Item -LiteralPath $webpPath
                    [long]$webpLength = $webpFile.Length

                    if ($extension -eq ".png") {
                        try {
                            Remove-FileSafe -Path $sourceFile.FullName
                            $pngDeleted++
                            $dataDeleted += $sourceLength
                            $netSavings += ($sourceLength - $webpLength)

                            $progressText = Format-NetSavings $netSavings
                            Write-Host "[$current/$total | $progressText] CONVERTED; PNG deleted; lossless WEBP kept: $sourceName" -ForegroundColor $color
                        }
                        catch {
                            # Roll back the newly created WEBP when PNG deletion fails.
                            try {
                                Remove-FileSafe -Path $webpFile.FullName
                                $progressText = Format-NetSavings $netSavings
                                Write-Host "[$current/$total | $progressText] DELETE ERROR: PNG retained; new WEBP rolled back: $sourceName" -ForegroundColor Red
                                Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
                                Add-ImageIssue -Type "SOURCE DELETE ERROR" -Path $sourceFile.FullName -Message $_.Exception.Message
                            }
                            catch {
                                $netSavings -= $webpLength
                                $progressText = Format-NetSavings $netSavings
                                Write-Host "[$current/$total | $progressText] DELETE ERROR: PNG retained and WEBP rollback failed: $sourceName" -ForegroundColor Red
                                Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
                                Add-ImageIssue -Type "ROLLBACK ERROR" -Path $webpFile.FullName -Message $_.Exception.Message
                            }

                            $deleteErrors++
                        }
                    }
                    else {
                        if ($webpLength -lt $sourceLength) {
                            try {
                                Remove-FileSafe -Path $sourceFile.FullName
                                $jpgDeleted++
                                $dataDeleted += $sourceLength
                                $netSavings += ($sourceLength - $webpLength)

                                $progressText = Format-NetSavings $netSavings
                                Write-Host "[$current/$total | $progressText] CONVERTED; JPG/JPEG deleted; smaller WEBP kept: $sourceName" -ForegroundColor $color
                            }
                            catch {
                                # Roll back the newly created WEBP when source deletion fails.
                                try {
                                    Remove-FileSafe -Path $webpFile.FullName
                                    $progressText = Format-NetSavings $netSavings
                                    Write-Host "[$current/$total | $progressText] DELETE ERROR: JPG/JPEG retained; new WEBP rolled back: $sourceName" -ForegroundColor Red
                                    Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
                                    Add-ImageIssue -Type "SOURCE DELETE ERROR" -Path $sourceFile.FullName -Message $_.Exception.Message
                                }
                                catch {
                                    $netSavings -= $webpLength
                                    $progressText = Format-NetSavings $netSavings
                                    Write-Host "[$current/$total | $progressText] DELETE ERROR: JPG/JPEG retained and WEBP rollback failed: $sourceName" -ForegroundColor Red
                                    Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
                                    Add-ImageIssue -Type "ROLLBACK ERROR" -Path $webpFile.FullName -Message $_.Exception.Message
                                }

                                $deleteErrors++
                            }
                        }
                        elseif ($webpLength -gt $sourceLength) {
                            try {
                                Remove-FileSafe -Path $webpFile.FullName
                                $largerWebpDeleted++
                                $dataDeleted += $webpLength

                                if (
                                    Set-JpegLargerWebPTag `
                                        -Path $sourceFile.FullName `
                                        -SourceLength $sourceLength `
                                        -JpegQuality $JpegQuality `
                                        -CwebpSha256 $CwebpSha256
                                ) {
                                    $largerWebpJpgTagsWritten++
                                    $tagStatus = "JPG/JPEG tagged to skip the same attempt later"
                                }
                                else {
                                    $jpegTagWriteWarnings++
                                    $tagStatus = "tag could not be written"
                                }

                                $progressText = Format-NetSavings $netSavings
                                Write-Host "[$current/$total | $progressText] WEBP was larger and was discarded; JPG/JPEG kept; $tagStatus`: $sourceName" -ForegroundColor $color

                                if ($script:LastJpegTagError -and $tagStatus -eq "tag could not be written") {
                                    Write-Host "    TAG WARNING: $script:LastJpegTagError" -ForegroundColor Yellow
                                    Add-ImageIssue -Type "TAG WARNING" -Path $sourceFile.FullName -Message $script:LastJpegTagError
                                    $script:LastJpegTagError = $null
                                }
                            }
                            catch {
                                $netSavings -= $webpLength
                                $progressText = Format-NetSavings $netSavings
                                Write-Host "[$current/$total | $progressText] DELETE ERROR: Larger new WEBP retained: $sourceName" -ForegroundColor Red
                                Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
                                Add-ImageIssue -Type "TEMP DELETE ERROR" -Path $webpFile.FullName -Message $_.Exception.Message
                                $deleteErrors++
                            }
                        }
                        else {
                            try {
                                Remove-FileSafe -Path $webpFile.FullName
                                $equalWebpDeleted++
                                $dataDeleted += $webpLength

                                $progressText = Format-NetSavings $netSavings
                                Write-Host "[$current/$total | $progressText] Equal-size WEBP deleted; JPG/JPEG kept: $sourceName" -ForegroundColor $color
                            }
                            catch {
                                $netSavings -= $webpLength
                                $progressText = Format-NetSavings $netSavings
                                Write-Host "[$current/$total | $progressText] DELETE ERROR: Equal-size new WEBP retained: $sourceName" -ForegroundColor Red
                                Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
                                Add-ImageIssue -Type "TEMP DELETE ERROR" -Path $webpFile.FullName -Message $_.Exception.Message
                                $deleteErrors++
                            }
                        }
                    }
                }
                catch {
                    $failed++
                    $progressText = Format-NetSavings $netSavings
                    Write-Host "[$current/$total | $progressText] ERROR: $($source.FullName)" -ForegroundColor Red
                    Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
                    Add-ImageIssue -Type "UNEXPECTED ERROR" -Path $source.FullName -Message $_.Exception.Message
                }
            }

            # =========================
            # SUMMARY
            # =========================

            Write-Host ""
            Write-Host "Finished." -ForegroundColor Green

            Write-Host "New conversions completed:       $newConversions" -ForegroundColor Cyan
            Write-Host "Existing-pair cleanups:          $existingPairsCleaned" -ForegroundColor Green
            Write-Host "Existing-pair skips:             $existingPairsSkipped" -ForegroundColor White

            if ($jpegFilesSkippedByOption -gt 0) {
                Write-Host "JPG/JPEG skipped by option:      $jpegFilesSkippedByOption" -ForegroundColor DarkCyan
            }
            if ($pngFilesSkippedByOption -gt 0) {
                Write-Host "PNG skipped by option:           $pngFilesSkippedByOption" -ForegroundColor DarkCyan
            }

            Write-Host "PNG originals deleted:           $pngDeleted" -ForegroundColor Cyan
            Write-Host "JPG/JPEG originals deleted:      $jpgDeleted" -ForegroundColor Green
            Write-Host "Larger WEBPs deleted:            $largerWebpDeleted" -ForegroundColor Magenta
            Write-Host "Equal-size WEBPs deleted:        $equalWebpDeleted" -ForegroundColor Yellow
            Write-Host "Larger-WEBP JPG tags written:    $largerWebpJpgTagsWritten" -ForegroundColor DarkCyan
            Write-Host "Previously tagged JPG skips:     $largerWebpJpgTagSkips" -ForegroundColor DarkCyan
            Write-Host "JPG tag write warnings:          $jpegTagWriteWarnings" -ForegroundColor DarkYellow
            Write-Host "Duplicate groups found:          $($inventoryDuplicateGroups.Count)" -ForegroundColor DarkYellow
            Write-Host "Duplicate groups processed:      $collisionGroupsProcessed" -ForegroundColor DarkCyan
            Write-Host "Duplicate files removed:         $duplicateFilesRemoved" -ForegroundColor Green
            Write-Host "Existing WebP duplicates removed:$duplicateWebpFilesRemoved" -ForegroundColor Green
            Write-Host "Transparency-protected groups:   $transparencyProtectedGroups" -ForegroundColor DarkCyan
            Write-Host "Matching-name file skips:        $collisionSkips" -ForegroundColor DarkYellow

            if ($failed -gt 0) {
                Write-Host "Conversion/validation errors:    $failed" -ForegroundColor Red
            }
            else {
                Write-Host "Conversion/validation errors:    0" -ForegroundColor Green
            }

            if ($deleteErrors -gt 0) {
                Write-Host "Deletion errors:                 $deleteErrors" -ForegroundColor Red
            }
            else {
                Write-Host "Deletion errors:                 0" -ForegroundColor Green
            }

            if ($initialImageLibraryBytes -gt 0) {
                $imageStorageChangePercent = (
                    [double]$netSavings /
                    [double]$initialImageLibraryBytes
                ) * 100
            }
            else {
                $imageStorageChangePercent = 0
            }

            if ($netSavings -ge 0) {
                Write-Host "Actual net storage saved:        $(Format-ByteSize $netSavings)" -ForegroundColor Yellow
                Write-Host (
                    "Library size reduction:           {0:N2}%" -f
                    $imageStorageChangePercent
                ) -ForegroundColor Yellow
            }
            else {
                Write-Host "Actual net storage increase:     $(Format-ByteSize ([math]::Abs($netSavings)))" -ForegroundColor Yellow
                Write-Host (
                    "Library size increase:            {0:N2}%" -f
                    ([math]::Abs($imageStorageChangePercent))
                ) -ForegroundColor Yellow
            }

            Write-Host "Skipped reparse-point dirs:      $($script:SkippedReparsePointDirs.Count)" -ForegroundColor DarkYellow
            Write-Host "Test folders skipped:            $($script:SkippedTestFolders.Count)" -ForegroundColor DarkYellow

            $imageReportLines = New-Object System.Collections.Generic.List[string]
            [void]$imageReportLines.Add("")
            [void]$imageReportLines.Add("SUMMARY")
            [void]$imageReportLines.Add("Finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
            [void]$imageReportLines.Add("New conversions completed:       $newConversions")
            [void]$imageReportLines.Add("Existing-pair cleanups:          $existingPairsCleaned")
            [void]$imageReportLines.Add("Existing-pair skips:             $existingPairsSkipped")
            if ($jpegFilesSkippedByOption -gt 0) {
                [void]$imageReportLines.Add("JPG/JPEG skipped by option:      $jpegFilesSkippedByOption")
            }
            if ($pngFilesSkippedByOption -gt 0) {
                [void]$imageReportLines.Add("PNG skipped by option:           $pngFilesSkippedByOption")
            }
            [void]$imageReportLines.Add("PNG originals deleted:           $pngDeleted")
            [void]$imageReportLines.Add("JPG/JPEG originals deleted:      $jpgDeleted")
            [void]$imageReportLines.Add("Larger WEBPs deleted:            $largerWebpDeleted")
            [void]$imageReportLines.Add("Equal-size WEBPs deleted:        $equalWebpDeleted")
            [void]$imageReportLines.Add("Larger-WEBP JPG tags written:    $largerWebpJpgTagsWritten")
            [void]$imageReportLines.Add("Previously tagged JPG skips:     $largerWebpJpgTagSkips")
            [void]$imageReportLines.Add("JPG tag write warnings:          $jpegTagWriteWarnings")
            [void]$imageReportLines.Add("Duplicate groups processed:      $collisionGroupsProcessed")
            [void]$imageReportLines.Add("Duplicate files removed:         $duplicateFilesRemoved")
            [void]$imageReportLines.Add("Existing WebP duplicates removed:$duplicateWebpFilesRemoved")
            [void]$imageReportLines.Add("Transparency-protected groups:   $transparencyProtectedGroups")
            [void]$imageReportLines.Add("Matching-name file skips:        $collisionSkips")
            [void]$imageReportLines.Add("Conversion/validation errors:    $failed")
            [void]$imageReportLines.Add("Deletion errors:                 $deleteErrors")
            [void]$imageReportLines.Add("Actual net storage saved:        $(Format-ByteSize $netSavings)")
            [void]$imageReportLines.Add(("Library size reduction:           {0:N2}%" -f $imageStorageChangePercent))

            if ($script:SkippedReparsePointDirs.Count -gt 0) {
                [void]$imageReportLines.Add("")
                [void]$imageReportLines.Add("SKIPPED LINKED DIRECTORIES")
                foreach ($directory in $script:SkippedReparsePointDirs) {
                    [void]$imageReportLines.Add($directory)
                }
            }

            if ($script:SkippedTestFolders.Count -gt 0) {
                [void]$imageReportLines.Add("")
                [void]$imageReportLines.Add("EXCLUDED TEST FOLDERS")
                foreach ($directory in $script:SkippedTestFolders) {
                    [void]$imageReportLines.Add($directory)
                }
            }

            $imageReportLines |
                Add-Content -LiteralPath $script:ImageReportPath -Encoding UTF8

            Write-Host "Report file:                       $script:ImageReportPath" -ForegroundColor DarkCyan
            Write-Host ""

            $script:RunAgain = Read-EndAction
        }
    }

    2 {
        & {
            # ============================================================
            # VIDEO OPTIMIZATION MODE
            # ============================================================
            # Keep ffmpeg.exe and ffprobe.exe in the same folder as this script.
            # The script recursively scans its own folder and normal subfolders.
            #
            # Supported source extensions:
            # .mp4 .mkv .avi .wmv .mov .webm
            #
            # Output:
            # MP4 / H.264 / AAC / yuv420p / faststart
            # ============================================================

            # =========================
            # FIXED PATHS
            # =========================

            $ffmpeg = Join-Path $PSScriptRoot "ffmpeg.exe"
            $ffprobe = Join-Path $PSScriptRoot "ffprobe.exe"
            $targetFolder = $PSScriptRoot

            # =========================
            # DISPLAY COLORS
            # =========================

            $entryColors = @(
                "Cyan",
                "Green",
                "Yellow",
                "Magenta",
                "Blue",
                "White",
                "DarkCyan",
                "DarkGreen",
                "DarkYellow",
                "DarkMagenta"
            )

            # =========================
            # HELPERS
            # =========================

            function Read-MenuOption {
                param(
                    [Parameter(Mandatory = $true)]
                    [string]$Prompt,

                    [Parameter(Mandatory = $true)]
                    [int]$Minimum,

                    [Parameter(Mandatory = $true)]
                    [int]$Maximum,

                    [Parameter(Mandatory = $true)]
                    [int]$Default
                )

                while ($true) {
                    $answer = (Read-Host "$Prompt [$Minimum-$Maximum, default $Default]").Trim()

                    if ([string]::IsNullOrWhiteSpace($answer)) {
                        return $Default
                    }

                    [int]$value = 0

                    if (
                        [int]::TryParse($answer, [ref]$value) -and
                        $value -ge $Minimum -and
                        $value -le $Maximum
                    ) {
                        return $value
                    }

                    Write-Host "Please enter a whole number from $Minimum through $Maximum." -ForegroundColor Yellow
                }
            }

            function Format-ByteSize {
                param(
                    [Parameter(Mandatory = $true)]
                    [long]$Bytes
                )

                if ($Bytes -ge 1TB) {
                    return "{0:N2} TB" -f ($Bytes / 1TB)
                }
                elseif ($Bytes -ge 1GB) {
                    return "{0:N2} GB" -f ($Bytes / 1GB)
                }
                elseif ($Bytes -ge 1MB) {
                    return "{0:N2} MB" -f ($Bytes / 1MB)
                }
                elseif ($Bytes -ge 1KB) {
                    return "{0:N2} KB" -f ($Bytes / 1KB)
                }
                else {
                    return "$Bytes bytes"
                }
            }

            function Format-NetSavings {
                param(
                    [Parameter(Mandatory = $true)]
                    [long]$Bytes
                )

                if ($Bytes -ge 0) {
                    return "Net saved: $(Format-ByteSize $Bytes)"
                }
                else {
                    return "Net increase: $(Format-ByteSize ([math]::Abs($Bytes)))"
                }
            }

            function Convert-ToCommandLineArgument {
                param(
                    [AllowEmptyString()]
                    [string]$Argument
                )

                if ($null -eq $Argument -or $Argument.Length -eq 0) {
                    return '""'
                }

                if ($Argument -notmatch '[\s&()^;|<>"]') {
                    return $Argument
                }

                # Windows command-line quoting. File names cannot contain literal double quotes,
                # but escaping is retained here for other argument types.
                $escaped = $Argument -replace '(\\*)"', '$1$1\"'
                $escaped = $escaped -replace '(\\+)$', '$1$1'
                return '"' + $escaped + '"'
            }

            function Invoke-ExternalProcess {
                param(
                    [Parameter(Mandatory = $true)]
                    [string]$FilePath,

                    [Parameter(Mandatory = $true)]
                    [string[]]$Arguments
                )

                $processInfo = New-Object System.Diagnostics.ProcessStartInfo
                $processInfo.FileName = $FilePath
                $processInfo.UseShellExecute = $false
                $processInfo.RedirectStandardOutput = $true
                $processInfo.RedirectStandardError = $true
                $processInfo.CreateNoWindow = $true
                $processInfo.Arguments = (($Arguments | ForEach-Object {
                    Convert-ToCommandLineArgument -Argument $_
                }) -join " ")

                $process = New-Object System.Diagnostics.Process
                $process.StartInfo = $processInfo

                try {
                    [void]$process.Start()

                    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
                    $stderrTask = $process.StandardError.ReadToEndAsync()

                    $process.WaitForExit()

                    $standardOutput = $stdoutTask.Result
                    $standardError = $stderrTask.Result

                    return [PSCustomObject]@{
                        ExitCode = $process.ExitCode
                        StdOut   = $standardOutput.Trim()
                        StdErr   = $standardError.Trim()
                        Output   = (($standardOutput, $standardError) -join [Environment]::NewLine).Trim()
                    }
                }
                finally {
                    $process.Dispose()
                }
            }

            function Get-MediaProbe {
                param(
                    [Parameter(Mandatory = $true)]
                    [string]$Path
                )

                $result = Invoke-ExternalProcess -FilePath $ffprobe -Arguments @(
                    "-v", "error",
                    "-print_format", "json",
                    "-show_format",
                    "-show_streams",
                    $Path
                )

                if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.StdOut)) {
                    return [PSCustomObject]@{
                        Success = $false
                        Probe   = $null
                        Error   = $result.Output
                    }
                }

                try {
                    $probe = $result.StdOut | ConvertFrom-Json

                    return [PSCustomObject]@{
                        Success = $true
                        Probe   = $probe
                        Error   = ""
                    }
                }
                catch {
                    return [PSCustomObject]@{
                        Success = $false
                        Probe   = $null
                        Error   = "ffprobe returned invalid JSON: $($_.Exception.Message)"
                    }
                }
            }

            function Get-PrimaryVideoStream {
                param(
                    [Parameter(Mandatory = $true)]
                    [object]$Probe
                )

                $videoStreams = @($Probe.streams | Where-Object { $_.codec_type -eq "video" })

                if ($videoStreams.Count -eq 0) {
                    return $null
                }

                $normalVideo = @(
                    $videoStreams | Where-Object {
                        $null -eq $_.disposition -or
                        $null -eq $_.disposition.attached_pic -or
                        [int]$_.disposition.attached_pic -ne 1
                    }
                )

                if ($normalVideo.Count -gt 0) {
                    return $normalVideo[0]
                }

                return $videoStreams[0]
            }

            function Get-PrimaryAudioStream {
                param(
                    [Parameter(Mandatory = $true)]
                    [object]$Probe
                )

                $audioStreams = @($Probe.streams | Where-Object { $_.codec_type -eq "audio" })

                if ($audioStreams.Count -eq 0) {
                    return $null
                }

                return $audioStreams[0]
            }

            function Convert-RationalToDouble {
                param(
                    [AllowNull()]
                    [object]$Value
                )

                if ($null -eq $Value) {
                    return 0.0
                }

                $text = "$Value".Trim()

                if (
                    [string]::IsNullOrWhiteSpace($text) -or
                    $text -eq "N/A" -or
                    $text -eq "0/0"
                ) {
                    return 0.0
                }

                try {
                    if ($text -match '^(-?\d+(?:\.\d+)?)/(-?\d+(?:\.\d+)?)$') {
                        $numerator = [double]::Parse(
                            $Matches[1],
                            [System.Globalization.CultureInfo]::InvariantCulture
                        )
                        $denominator = [double]::Parse(
                            $Matches[2],
                            [System.Globalization.CultureInfo]::InvariantCulture
                        )

                        if ([math]::Abs($denominator) -lt 0.0000001) {
                            return 0.0
                        }

                        return ($numerator / $denominator)
                    }

                    return [double]::Parse(
                        $text,
                        [System.Globalization.CultureInfo]::InvariantCulture
                    )
                }
                catch {
                    return 0.0
                }
            }

            function Get-ProbeDuration {
                param(
                    [Parameter(Mandatory = $true)]
                    [object]$Probe,

                    [AllowNull()]
                    [object]$VideoStream
                )

                $formatDuration = 0.0

                if ($null -ne $Probe.format -and $null -ne $Probe.format.duration) {
                    $formatDuration = Convert-RationalToDouble -Value $Probe.format.duration
                }

                if ($formatDuration -gt 0) {
                    return $formatDuration
                }

                if ($null -ne $VideoStream -and $null -ne $VideoStream.duration) {
                    return (Convert-RationalToDouble -Value $VideoStream.duration)
                }

                return 0.0
            }

            function Get-StreamFrameRate {
                param(
                    [AllowNull()]
                    [object]$VideoStream
                )

                if ($null -eq $VideoStream) {
                    return 0.0
                }

                $frameRate = Convert-RationalToDouble -Value $VideoStream.avg_frame_rate

                if ($frameRate -gt 0) {
                    return $frameRate
                }

                return (Convert-RationalToDouble -Value $VideoStream.r_frame_rate)
            }

            function Get-OptimizerProfileRank {
                param(
                    [Parameter(Mandatory = $true)]
                    [object]$Probe
                )

                try {
                    if ($null -eq $Probe.format -or $null -eq $Probe.format.tags) {
                        return -1
                    }

                    $comment = "$($Probe.format.tags.comment)"

                    if (
                        $comment -match "(?i)SYYBOTT'S Video Optimizer" -and
                        $comment -match 'CRF=(\d+)'
                    ) {
                        switch ([int]$Matches[1]) {
                            20 { return 0 }
                            21 { return 1 }
                            22 { return 1 }
                            24 { return 2 }
                            25 { return 3 }
                            26 { return 4 }
                            27 { return 5 }
                            28 { return 6 }
                        }
                    }

                    if (
                        $comment -match "(?i)SYYBOTT'S Video Optimizer" -and
                        $comment -match 'Rank=(\d+)'
                    ) {
                        return [int]$Matches[1]
                    }

                    if ($comment -match "(?i)SYYBOTT'S Media Optimizer TEST") {
                        if ($comment -match 'Profile=Default') {
                            return 2
                        }

                        if ($comment -match 'Profile=SuperLight') {
                            return 6
                        }
                    }
                }
                catch {
                    return -1
                }

                return -1
            }

            function Get-VideoProfileConfig {
                param(
                    [Parameter(Mandatory = $true)]
                    [ValidateRange(1, 7)]
                    [int]$Choice
                )

                $settings = switch ($Choice) {
                    1 { @("H.264 CRF 20 / AAC 160k", "CRF20_AAC160k", 0, 20, "160k", 1) }
                    2 { @("H.264 CRF 22 / AAC 128k", "CRF22_AAC128k", 1, 22, "128k", 1) }
                    3 { @("Default", "Default", 2, 24, "96k", 1) }
                    4 { @("H.264 CRF 25 / AAC 88k", "CRF25_AAC88k", 3, 25, "88k", 1) }
                    5 { @("H.264 CRF 26 / AAC 80k", "CRF26_AAC80k", 4, 26, "80k", 1) }
                    6 { @("H.264 CRF 27 / AAC 72k", "CRF27_AAC72k", 5, 27, "72k", 1) }
                    7 { @("Super Light", "SuperLight", 6, 28, "64k", 2) }
                }

                return [PSCustomObject]@{
                    Name               = [string]$settings[0]
                    FileName           = [string]$settings[1]
                    Rank               = [int]$settings[2]
                    Crf                = [int]$settings[3]
                    AudioBitrate       = [string]$settings[4]
                    DefaultEncoderMode = [int]$settings[5]
                    MaximumWidth       = 0
                    MaximumHeight      = 0
                    MaximumFrameRate   = 30.0
                }
            }

            function Get-VideoFilesSafe {
                param(
                    [Parameter(Mandatory = $true)]
                    [string]$Root
                )

                $results = New-Object System.Collections.Generic.List[object]
                $script:SkippedReparsePointDirs = New-Object System.Collections.Generic.List[string]
                $script:SkippedFolderErrors = New-Object System.Collections.Generic.List[string]
                $script:SkippedTestFolders = New-Object System.Collections.Generic.List[string]

                function Scan-Folder {
                    param(
                        [Parameter(Mandatory = $true)]
                        [string]$FolderPath
                    )

                    try {
                        $folderItems = @(Get-ChildItem -LiteralPath $FolderPath -Force)
                    }
                    catch {
                        [void]$script:SkippedFolderErrors.Add(
                            "$FolderPath :: $($_.Exception.Message)"
                        )
                        return
                    }

                    foreach ($item in $folderItems) {
                        if ($item.PSIsContainer) {
                            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                                [void]$script:SkippedReparsePointDirs.Add($item.FullName)
                                continue
                            }

                            if (
                                $item.Name -ieq "Test Images" -or
                                $item.Name -ieq "Test Videos" -or
                                $item.Name -ieq "SYYBOTT-JPG-Test" -or
                                $item.Name -ieq "SYYBOTT-Video-Test"
                            ) {
                                [void]$script:SkippedTestFolders.Add($item.FullName)
                                continue
                            }

                            Scan-Folder -FolderPath $item.FullName
                        }
                        else {
                            switch ($item.Extension.ToLowerInvariant()) {
                                ".mp4"  { [void]$results.Add($item) }
                                ".mkv"  { [void]$results.Add($item) }
                                ".avi"  { [void]$results.Add($item) }
                                ".wmv"  { [void]$results.Add($item) }
                                ".mov"  { [void]$results.Add($item) }
                                ".webm" { [void]$results.Add($item) }
                            }
                        }
                    }
                }

                Scan-Folder -FolderPath $Root
                return $results | Sort-Object FullName
            }

            function Remove-FileSafe {
                param(
                    [Parameter(Mandatory = $true)]
                    [string]$Path
                )

                Remove-Item -LiteralPath $Path -Force
            }

            function Write-Log {
                param(
                    [Parameter(Mandatory = $true)]
                    [string]$Type,

                    [Parameter(Mandatory = $true)]
                    [string]$Path,

                    [Parameter(Mandatory = $true)]
                    [AllowEmptyString()]
                    [string]$Message
                )

                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                Add-Content -LiteralPath $script:LogPath -Encoding UTF8 -Value (
                    "[$timestamp] [$Type] $Path`r`n    $Message"
                )
            }

            function Test-OptimizedVideo {
                param(
                    [Parameter(Mandatory = $true)]
                    [string]$Path,

                    [Parameter(Mandatory = $true)]
                    [double]$SourceDuration,

                    [Parameter(Mandatory = $true)]
                    [bool]$SourceHasAudio,

                    [Parameter(Mandatory = $true)]
                    [int]$MaximumWidth,

                    [Parameter(Mandatory = $true)]
                    [int]$MaximumHeight,

                    [Parameter(Mandatory = $true)]
                    [double]$MaximumFrameRate
                )

                if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
                    return [PSCustomObject]@{
                        Valid  = $false
                        Reason = "Output file does not exist."
                        Probe  = $null
                    }
                }

                $file = Get-Item -LiteralPath $Path

                if ($file.Length -le 0) {
                    return [PSCustomObject]@{
                        Valid  = $false
                        Reason = "Output file is empty."
                        Probe  = $null
                    }
                }

                $probeResult = Get-MediaProbe -Path $Path

                if (-not $probeResult.Success) {
                    return [PSCustomObject]@{
                        Valid  = $false
                        Reason = "ffprobe validation failed: $($probeResult.Error)"
                        Probe  = $null
                    }
                }

                $probe = $probeResult.Probe
                $video = Get-PrimaryVideoStream -Probe $probe
                $audio = Get-PrimaryAudioStream -Probe $probe

                if ($null -eq $video) {
                    return [PSCustomObject]@{
                        Valid  = $false
                        Reason = "No valid video stream was found."
                        Probe  = $probe
                    }
                }

                if ("$($video.codec_name)" -ne "h264") {
                    return [PSCustomObject]@{
                        Valid  = $false
                        Reason = "Output video codec is not H.264."
                        Probe  = $probe
                    }
                }

                if ("$($video.pix_fmt)" -ne "yuv420p") {
                    return [PSCustomObject]@{
                        Valid  = $false
                        Reason = "Output pixel format is not yuv420p."
                        Probe  = $probe
                    }
                }

                [int]$width = $video.width
                [int]$height = $video.height

                if ($width -le 0 -or $height -le 0) {
                    return [PSCustomObject]@{
                        Valid  = $false
                        Reason = "Output dimensions are invalid."
                        Probe  = $probe
                    }
                }

                if (
                    ($MaximumWidth -gt 0 -and $width -gt $MaximumWidth) -or
                    ($MaximumHeight -gt 0 -and $height -gt $MaximumHeight)
                ) {
                    return [PSCustomObject]@{
                        Valid  = $false
                        Reason = "Output dimensions exceed the selected profile."
                        Probe  = $probe
                    }
                }

                if (($width % 2) -ne 0 -or ($height % 2) -ne 0) {
                    return [PSCustomObject]@{
                        Valid  = $false
                        Reason = "Output dimensions are not divisible by 2."
                        Probe  = $probe
                    }
                }

                $frameRate = Get-StreamFrameRate -VideoStream $video

                if ($frameRate -gt ($MaximumFrameRate + 0.05)) {
                    return [PSCustomObject]@{
                        Valid  = $false
                        Reason = "Output frame rate exceeds the selected profile."
                        Probe  = $probe
                    }
                }

                if ($SourceHasAudio) {
                    if ($null -eq $audio) {
                        return [PSCustomObject]@{
                            Valid  = $false
                            Reason = "The source had audio, but the output does not."
                            Probe  = $probe
                        }
                    }

                    if ("$($audio.codec_name)" -ne "aac") {
                        return [PSCustomObject]@{
                            Valid  = $false
                            Reason = "Output audio codec is not AAC."
                            Probe  = $probe
                        }
                    }
                }
                elseif ($null -ne $audio) {
                    return [PSCustomObject]@{
                        Valid  = $false
                        Reason = "The source was silent, but the output unexpectedly contains audio."
                        Probe  = $probe
                    }
                }

                $outputDuration = Get-ProbeDuration -Probe $probe -VideoStream $video

                if ($SourceDuration -gt 0) {
                    if ($outputDuration -le 0) {
                        return [PSCustomObject]@{
                            Valid  = $false
                            Reason = "Output duration could not be verified."
                            Probe  = $probe
                        }
                    }

                    $durationTolerance = [math]::Max(0.5, ($SourceDuration * 0.01))
                    $durationDifference = [math]::Abs($SourceDuration - $outputDuration)

                    if ($durationDifference -gt $durationTolerance) {
                        return [PSCustomObject]@{
                            Valid  = $false
                            Reason = "Output duration differs from the source by more than the allowed tolerance."
                            Probe  = $probe
                        }
                    }
                }

                $formatName = "$($probe.format.format_name)"

                if ($formatName -notmatch 'mp4|mov') {
                    return [PSCustomObject]@{
                        Valid  = $false
                        Reason = "Output container was not recognized as MP4."
                        Probe  = $probe
                    }
                }

                return [PSCustomObject]@{
                    Valid  = $true
                    Reason = ""
                    Probe  = $probe
                }
            }

            function Invoke-VideoTestEncode {
                param(
                    [Parameter(Mandatory = $true)]
                    [string]$Root,

                    [Parameter(Mandatory = $true)]
                    [int]$TestChoice
                )

                $rootFullPath = [System.IO.Path]::GetFullPath($Root).TrimEnd(
                    [char[]]@('\', '/')
                )
                $testFilesList = New-Object System.Collections.Generic.List[object]
                $excludedTestFolderNames = @(
                    "Test Images",
                    "Test Videos",
                    "SYYBOTT-JPG-Test",
                    "SYYBOTT-Video-Test"
                )

                function Scan-TestVideoFolder {
                    param(
                        [Parameter(Mandatory = $true)]
                        [string]$FolderPath,

                        [Parameter(Mandatory = $true)]
                        [int]$Depth
                    )

                    try {
                        $folderItems = @(Get-ChildItem -LiteralPath $FolderPath -Force)
                    }
                    catch {
                        Write-Host "TEST FOLDER SKIP: $FolderPath" -ForegroundColor DarkYellow
                        Write-Host "    $($_.Exception.Message)" -ForegroundColor DarkYellow
                        return
                    }

                    foreach ($item in $folderItems) {
                        if ($item.PSIsContainer) {
                            if (
                                $item.Attributes -band
                                [System.IO.FileAttributes]::ReparsePoint
                            ) {
                                continue
                            }

                            if ($item.Name -in $excludedTestFolderNames) {
                                continue
                            }

                            if ($Depth -lt 2) {
                                Scan-TestVideoFolder `
                                    -FolderPath $item.FullName `
                                    -Depth ($Depth + 1)
                            }

                            continue
                        }

                        if (
                            $item.Extension.ToLowerInvariant() -in @(
                                ".mp4",
                                ".mkv",
                                ".avi",
                                ".wmv",
                                ".mov",
                                ".webm"
                            )
                        ) {
                            [void]$testFilesList.Add($item)
                        }
                    }
                }

                Scan-TestVideoFolder -FolderPath $rootFullPath -Depth 0

                $testFiles = @(
                    $testFilesList |
                        Sort-Object Name, FullName
                )

                if ($testFiles.Count -eq 0) {
                    Write-Host ""
                    Write-Host "No supported videos were found within two folder levels of:" -ForegroundColor Yellow
                    Write-Host $rootFullPath -ForegroundColor Cyan
                    return
                }

                # Sources are iterated in case-insensitive alphabetical order.
                # The first source whose test output does not yet exist is encoded.
                # Sources that already have a retained output are skipped so that
                # each Video Test run advances to the next untested source.
                $availableTestVideoCount = $testFiles.Count
                $skippedAlreadyTested = 0

                $testProfileChoice = [int][Math]::Ceiling($TestChoice / 2.0)
                $testProfile = Get-VideoProfileConfig -Choice $testProfileChoice
                $testProfileName = $testProfile.FileName
                $testMarkerProfileName = $testProfile.Name
                $testProfileRank = $testProfile.Rank
                $testCrf = $testProfile.Crf
                $testAudioBitrate = $testProfile.AudioBitrate

                if (($TestChoice % 2) -eq 0) {
                    $testEncoderName = "Heavy"
                    $testEncoderModeName = "Maximum Compression"
                    $testPreset = "slow"
                }
                else {
                    $testEncoderName = "Medium"
                    $testEncoderModeName = "Balanced"
                    $testPreset = "medium"
                }

                $testOptimizerMarker = (
                    "SYYBOTT'S Video Optimizer v$MediaOptimizerVersion | " +
                    "Profile=$testMarkerProfileName | " +
                    "Rank=$testProfileRank | " +
                    "CRF=$testCrf | " +
                    "EncoderMode=$testEncoderModeName | " +
                    "Preset=$testPreset | " +
                    "TestMode=Yes"
                )

                $testMaximumWidth = 0
                $testMaximumHeight = 0
                $testMaximumFrameRate = 30.0
                $testFolder = Join-Path $script:TestOutputRoot "Test Videos"
                $oldTestRootFolder = Join-Path $rootFullPath "Test Videos"
                $legacyRootFolder = Join-Path $rootFullPath "SYYBOTT-Video-Test"
                [void](New-Item -ItemType Directory -Path $testFolder -Force)

                $plannedOutputPaths = [System.Collections.Generic.HashSet[string]]::new(
                    [System.StringComparer]::OrdinalIgnoreCase
                )

                $existingOutputsUsed = 0
                $noSavingsDiscards = 0
                $probeErrors = 0
                $conversionErrors = 0
                $validationErrors = 0
                $finalizeErrors = 0
                $retained = $false
                $sourceNumber = 0
                $sourcesTried = 0

                Write-Host ""
                Write-Host "VIDEO TEST" -ForegroundColor Magenta
                Write-Host "Media folder: $rootFullPath" -ForegroundColor White
                Write-Host "Output folder: $testFolder" -ForegroundColor White
                Write-Host "Supported videos available: $availableTestVideoCount" -ForegroundColor White
                Write-Host "Profile: $testMarkerProfileName" -ForegroundColor White
                Write-Host "Encoder level: $testEncoderName" -ForegroundColor White
                Write-Host "FFmpeg preset: $testPreset" -ForegroundColor White
                Write-Host "CRF: $testCrf" -ForegroundColor White
                Write-Host "Audio bitrate: $testAudioBitrate" -ForegroundColor White
                Write-Host "Goal: One smaller retained test video" -ForegroundColor White
                Write-Host "Search depth: Selected folder plus two subfolder levels" -ForegroundColor White
                Write-Host "Original files changed: No" -ForegroundColor Green
                Write-Host ""

                foreach ($source in $testFiles) {
                    if ($retained) {
                        break
                    }

                    $sourceNumber++
                    $sourcesTried++
                    $sourceFile = Get-Item -LiteralPath $source.FullName
                    $baseName = [System.IO.Path]::GetFileNameWithoutExtension(
                        $source.Name
                    )
                    $sourceExtensionName = (
                        $source.Extension.TrimStart(".").ToLowerInvariant()
                    )

                    $relativePath = $source.FullName.Substring(
                        $rootFullPath.Length
                    ).TrimStart([char[]]@('\', '/'))
                    $relativeDirectory = Split-Path -Parent $relativePath

                    $outputDirectory = if (
                        [string]::IsNullOrWhiteSpace($relativeDirectory)
                    ) {
                        $testFolder
                    }
                    else {
                        Join-Path $testFolder $relativeDirectory
                    }

                    $legacyMirroredDirectory = if (
                        [string]::IsNullOrWhiteSpace($relativeDirectory)
                    ) {
                        $legacyRootFolder
                    }
                    else {
                        Join-Path $legacyRootFolder $relativeDirectory
                    }

                    $oldTestMirroredDirectory = if (
                        [string]::IsNullOrWhiteSpace($relativeDirectory)
                    ) {
                        $oldTestRootFolder
                    }
                    else {
                        Join-Path $oldTestRootFolder $relativeDirectory
                    }

                    $sourceLegacyDirectory = Join-Path `
                        $source.DirectoryName `
                        "SYYBOTT-Video-Test"

                    [void](New-Item `
                        -ItemType Directory `
                        -Path $outputDirectory `
                        -Force)

                    $finalName = "{0}_{1}_{2}.mp4" -f (
                        $baseName,
                        $testProfileName,
                        $testEncoderName
                    )
                    $finalPath = Join-Path $outputDirectory $finalName

                    if (-not $plannedOutputPaths.Add($finalPath)) {
                        $finalName = "{0}_{1}_{2}_{3}.mp4" -f (
                            $baseName,
                            $sourceExtensionName,
                            $testProfileName,
                            $testEncoderName
                        )
                        $finalPath = Join-Path $outputDirectory $finalName
                        [void]$plannedOutputPaths.Add($finalPath)
                    }

                    $candidatePaths = New-Object System.Collections.Generic.List[string]
                    $candidateSet = [System.Collections.Generic.HashSet[string]]::new(
                        [System.StringComparer]::OrdinalIgnoreCase
                    )

                    foreach ($candidatePath in @(
                        $finalPath,
                        (Join-Path $oldTestMirroredDirectory $finalName),
                        (Join-Path $oldTestRootFolder $finalName),
                        (Join-Path $legacyMirroredDirectory $finalName),
                        (Join-Path $legacyRootFolder $finalName),
                        (Join-Path $sourceLegacyDirectory $finalName)
                    )) {
                        if ($candidateSet.Add($candidatePath)) {
                            [void]$candidatePaths.Add($candidatePath)
                        }
                    }

                    Write-Host (
                        "[{0}/{1} | TEST] Checking {2}" -f
                        $sourceNumber,
                        $testFiles.Count,
                        $relativePath
                    ) -ForegroundColor DarkCyan

                    $sourceProbeResult = Get-MediaProbe -Path $source.FullName

                    if (-not $sourceProbeResult.Success) {
                        $probeErrors++
                        Write-Host "    SOURCE PROBE ERROR: $relativePath" -ForegroundColor Red
                        Write-Host "    $($sourceProbeResult.Error)" -ForegroundColor Red
                        continue
                    }

                    $sourceProbe = $sourceProbeResult.Probe
                    $sourceVideo = Get-PrimaryVideoStream -Probe $sourceProbe
                    $sourceAudio = Get-PrimaryAudioStream -Probe $sourceProbe

                    if ($null -eq $sourceVideo) {
                        $probeErrors++
                        Write-Host "    SOURCE PROBE ERROR: No video stream was found." -ForegroundColor Red
                        continue
                    }

                    $sourceHasAudio = ($null -ne $sourceAudio)
                    $sourceDuration = Get-ProbeDuration `
                        -Probe $sourceProbe `
                        -VideoStream $sourceVideo
                    $sourceFrameRate = Get-StreamFrameRate `
                        -VideoStream $sourceVideo

                    $existingOutputPath = $null
                    $existingOutputFile = $null

                    foreach ($candidatePath in $candidatePaths) {
                        if (-not (
                            Test-Path `
                                -LiteralPath $candidatePath `
                                -PathType Leaf
                        )) {
                            continue
                        }

                        try {
                            $candidateFile = Get-Item `
                                -LiteralPath $candidatePath `
                                -ErrorAction Stop

                            if (
                                [long]$candidateFile.Length -ge
                                [long]$sourceFile.Length
                            ) {
                                if ([IO.Path]::GetFullPath($candidatePath).StartsWith(
                                    [IO.Path]::GetFullPath($testFolder).TrimEnd('\') + '\',
                                    [StringComparison]::OrdinalIgnoreCase
                                )) {
                                    Remove-FileSafe -Path $candidatePath
                                    $noSavingsDiscards++
                                }
                                continue
                            }

                            $existingValidation = Test-OptimizedVideo `
                                -Path $candidatePath `
                                -SourceDuration $sourceDuration `
                                -SourceHasAudio $sourceHasAudio `
                                -MaximumWidth $testMaximumWidth `
                                -MaximumHeight $testMaximumHeight `
                                -MaximumFrameRate $testMaximumFrameRate

                            if (-not $existingValidation.Valid) {
                                if ([IO.Path]::GetFullPath($candidatePath).StartsWith(
                                    [IO.Path]::GetFullPath($testFolder).TrimEnd('\') + '\',
                                    [StringComparison]::OrdinalIgnoreCase
                                )) {
                                    Remove-FileSafe -Path $candidatePath
                                }
                                $validationErrors++
                                continue
                            }

                            if (-not [string]::Equals(
                                [IO.Path]::GetFullPath($candidatePath),
                                [IO.Path]::GetFullPath($finalPath),
                                [StringComparison]::OrdinalIgnoreCase
                            )) {
                                Copy-Item `
                                    -LiteralPath $candidatePath `
                                    -Destination $finalPath `
                                    -Force `
                                    -ErrorAction Stop
                                $candidatePath = $finalPath
                                $candidateFile = Get-Item `
                                    -LiteralPath $finalPath `
                                    -ErrorAction Stop
                            }
                            $existingOutputPath = $candidatePath
                            $existingOutputFile = $candidateFile
                            break
                        }
                        catch {
                            $validationErrors++
                            Write-Host "    Existing test file error: $candidatePath" -ForegroundColor Red
                            Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
                        }
                    }

                    if ($null -ne $existingOutputFile) {
                        # A retained output already exists for this source and test
                        # setting. This source was tested in a prior run. Skip it so
                        # the next untested source is selected instead.
                        $skippedAlreadyTested++
                        $existingOutputsUsed++
                        Write-Host "    Already tested; skipping to next source." -ForegroundColor DarkYellow
                        continue
                    }

                    $tempPath = "$finalPath.part"

                    Remove-Item `
                        -LiteralPath $tempPath `
                        -Force `
                        -ErrorAction SilentlyContinue

                    Write-Host "    Encoding new test output..." -ForegroundColor DarkCyan

                    $filterParts = New-Object System.Collections.Generic.List[string]
                    [void]$filterParts.Add(
                        "scale=w='trunc(iw/2)*2':h='trunc(ih/2)*2'"
                    )

                    if ($sourceFrameRate -gt ($testMaximumFrameRate + 0.05)) {
                        [void]$filterParts.Add("fps=30")
                    }

                    $videoFilter = $filterParts -join ","
                    $ffmpegArguments = New-Object System.Collections.Generic.List[string]

                    foreach ($argument in @(
                        "-hide_banner",
                        "-loglevel", "error",
                        "-nostdin",
                        "-y",
                        "-i", $source.FullName,
                        "-map", "0:$($sourceVideo.index)"
                    )) {
                        [void]$ffmpegArguments.Add($argument)
                    }

                    if ($sourceHasAudio) {
                        [void]$ffmpegArguments.Add("-map")
                        [void]$ffmpegArguments.Add("0:$($sourceAudio.index)")
                    }
                    else {
                        [void]$ffmpegArguments.Add("-an")
                    }

                    foreach ($argument in @(
                        "-sn",
                        "-dn",
                        "-map_metadata", "-1",
                        "-map_chapters", "-1",
                        "-vf", $videoFilter,
                        "-c:v", "libx264",
                        "-preset", $testPreset,
                        "-crf", "$testCrf",
                        "-pix_fmt", "yuv420p",
                        "-fps_mode:v", "vfr",
                        "-movflags", "+faststart",
                        "-metadata", "comment=$testOptimizerMarker",
                        "-max_muxing_queue_size", "2048"
                    )) {
                        [void]$ffmpegArguments.Add($argument)
                    }

                    if ($sourceHasAudio) {
                        foreach ($argument in @(
                            "-c:a", "aac",
                            "-b:a", $testAudioBitrate,
                            "-ac", "2"
                        )) {
                            [void]$ffmpegArguments.Add($argument)
                        }
                    }

                    [void]$ffmpegArguments.Add("-f")
                    [void]$ffmpegArguments.Add("mp4")
                    [void]$ffmpegArguments.Add($tempPath)

                    $encodeResult = Invoke-ExternalProcess `
                        -FilePath $ffmpeg `
                        -Arguments $ffmpegArguments.ToArray()

                    if (
                        $encodeResult.ExitCode -ne 0 -or
                        -not (
                            Test-Path `
                                -LiteralPath $tempPath `
                                -PathType Leaf
                        )
                    ) {
                        $conversionErrors++
                        Write-Host "    VIDEO TEST CONVERSION ERROR" -ForegroundColor Red

                        if ($encodeResult.Output) {
                            $encodeResult.Output -split "`r?`n" |
                                ForEach-Object {
                                    if ($_ -ne "") {
                                        Write-Host "    $_" -ForegroundColor Red
                                    }
                                }
                        }

                        Remove-Item `
                            -LiteralPath $tempPath `
                            -Force `
                            -ErrorAction SilentlyContinue
                        continue
                    }

                    $validation = Test-OptimizedVideo `
                        -Path $tempPath `
                        -SourceDuration $sourceDuration `
                        -SourceHasAudio $sourceHasAudio `
                        -MaximumWidth $testMaximumWidth `
                        -MaximumHeight $testMaximumHeight `
                        -MaximumFrameRate $testMaximumFrameRate

                    if (-not $validation.Valid) {
                        $validationErrors++
                        Write-Host "    VIDEO TEST VALIDATION ERROR" -ForegroundColor Red
                        Write-Host "    $($validation.Reason)" -ForegroundColor Red
                        Remove-Item `
                            -LiteralPath $tempPath `
                            -Force `
                            -ErrorAction SilentlyContinue
                        continue
                    }

                    $tempFile = Get-Item -LiteralPath $tempPath

                    if ([long]$tempFile.Length -ge [long]$sourceFile.Length) {
                        $noSavingsDiscards++
                        Remove-FileSafe -Path $tempPath
                        Write-Host (
                            "    No storage savings with this test setting for {0}. Test output discarded." -f
                            $relativePath
                        ) -ForegroundColor DarkYellow
                        continue
                    }

                    try {
                        Move-Item `
                            -LiteralPath $tempPath `
                            -Destination $finalPath `
                            -ErrorAction Stop
                    }
                    catch {
                        $finalizeErrors++
                        Write-Host "    VIDEO TEST FINALIZE ERROR" -ForegroundColor Red
                        Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
                        Remove-Item `
                            -LiteralPath $tempPath `
                            -Force `
                            -ErrorAction SilentlyContinue
                        continue
                    }

                    $outputFile = Get-Item -LiteralPath $finalPath
                    [long]$savedBytes = (
                        [long]$sourceFile.Length -
                        [long]$outputFile.Length
                    )
                    [double]$savedPercent = (
                        [double]$savedBytes /
                        [double]$sourceFile.Length
                    ) * 100

                    $retained = $true

                    Write-Host ""
                    Write-Host "VIDEO TEST SAMPLE RESULT" -ForegroundColor Green
                    Write-Host "  Test setting:    $testMarkerProfileName + $testEncoderModeName" -ForegroundColor White
                    Write-Host "  Original size:   $(Format-ByteSize $sourceFile.Length)" -ForegroundColor White
                    Write-Host "  Test size:       $(Format-ByteSize $outputFile.Length)" -ForegroundColor White
                    Write-Host "  Storage saved:   $(Format-ByteSize $savedBytes)" -ForegroundColor Green
                    Write-Host (
                        "  Size reduction:  {0:N2}%" -f
                        $savedPercent
                    ) -ForegroundColor Green
                    Write-Host "New test output" -ForegroundColor Green
                    Write-Host "Original file changed: No" -ForegroundColor Green
                    Write-Host "Output: $finalPath" -ForegroundColor Yellow
                    Write-Host "Full-library savings will vary. Test this file on its target device before choosing a full-library setting." -ForegroundColor Cyan
                }

                if (-not $retained) {
                    Write-Host ""
                    if ($skippedAlreadyTested -ge $availableTestVideoCount) {
                        Write-Host "No untested source videos remain. All $availableTestVideoCount supported video(s) have already been tested." -ForegroundColor Yellow
                    }
                    else {
                        Write-Host "Video test finished without a smaller retained output." -ForegroundColor Yellow
                    }
                    Write-Host "Sources tried: $sourcesTried" -ForegroundColor DarkYellow
                    Write-Host "Already-tested sources skipped: $skippedAlreadyTested" -ForegroundColor DarkYellow
                    Write-Host "No-savings outputs discarded: $noSavingsDiscards" -ForegroundColor DarkYellow
                    Write-Host "Source probe errors: $probeErrors" -ForegroundColor $(if ($probeErrors -gt 0) { "Red" } else { "Green" })
                    Write-Host "Conversion errors: $conversionErrors" -ForegroundColor $(if ($conversionErrors -gt 0) { "Red" } else { "Green" })
                    Write-Host "Validation errors: $validationErrors" -ForegroundColor $(if ($validationErrors -gt 0) { "Red" } else { "Green" })
                    Write-Host "Finalize errors: $finalizeErrors" -ForegroundColor $(if ($finalizeErrors -gt 0) { "Red" } else { "Green" })
                    Write-Host "Original files changed: 0" -ForegroundColor Green
                    Write-Host "Output folder: $testFolder" -ForegroundColor Yellow
                }
            }

            # =========================
            # PRECHECKS
            # =========================

            if ($PSVersionTable.PSVersion.Major -lt 5) {
                Write-Host "ERROR: Windows PowerShell 5.1 or newer is required." -ForegroundColor Red
                Read-Host "Press Enter to close"
                exit 1
            }

            if (-not (Test-Path -LiteralPath $ffmpeg -PathType Leaf)) {
                Write-Host "ERROR: ffmpeg.exe was not found beside the script:" -ForegroundColor Red
                Write-Host $ffmpeg -ForegroundColor Red
                Read-Host "Press Enter to close"
                exit 1
            }

            if (-not (Test-Path -LiteralPath $ffprobe -PathType Leaf)) {
                Write-Host "ERROR: ffprobe.exe was not found beside the script:" -ForegroundColor Red
                Write-Host $ffprobe -ForegroundColor Red
                Read-Host "Press Enter to close"
                exit 1
            }

            $encoderCheck = Invoke-ExternalProcess -FilePath $ffmpeg -Arguments @(
                "-hide_banner",
                "-encoders"
            )

            if (
                $encoderCheck.ExitCode -ne 0 -or
                $encoderCheck.Output -notmatch '\blibx264\b'
            ) {
                Write-Host "ERROR: This FFmpeg build does not include the libx264 encoder." -ForegroundColor Red
                Write-Host "Use a full Windows FFmpeg build that includes libx264." -ForegroundColor Red
                Read-Host "Press Enter to close"
                exit 1
            }

            if ($encoderCheck.Output -notmatch '(?m)^\s*[A-Z\.]{6}\s+aac\s') {
                Write-Host "ERROR: This FFmpeg build does not include the AAC encoder." -ForegroundColor Red
                Write-Host "Use a full Windows FFmpeg build that includes AAC encoding." -ForegroundColor Red
                Read-Host "Press Enter to close"
                exit 1
            }

            # =========================
            # INTERACTIVE OPTIONS
            # =========================

            Write-Host ""
            Write-Host "SYYBOTT'S MEDIA OPTIMIZER - VIDEO MODE v$MediaOptimizerVersion" -ForegroundColor Magenta
            Write-Host "Press Enter at any prompt to accept its displayed default." -ForegroundColor White
            Write-Host ""

            Write-Host "Choose video operation:" -ForegroundColor Cyan
            Write-Host "1. Optimize video library. Default: 1." -ForegroundColor White
            Write-Host "2. Video Test - selected folder plus two subfolder levels, no source changes." -ForegroundColor Green
            $VideoOperationMode = Read-MenuOption `
                -Prompt "Video operation" `
                -Minimum 1 `
                -Maximum 2 `
                -Default 1

            if ($VideoOperationMode -eq 2) {
                Write-Host ""
                Write-Host "Choose video tests:" -ForegroundColor Cyan
                $testMenuProfiles = @(
                    "H.264 CRF 20 / AAC 160k",
                    "H.264 CRF 22 / AAC 128k",
                    "Default - CRF 24 / AAC 96k",
                    "H.264 CRF 25 / AAC 88k",
                    "H.264 CRF 26 / AAC 80k",
                    "H.264 CRF 27 / AAC 72k",
                    "Super Light - CRF 28 / AAC 64k"
                )
                $testMenuNumber = 1
                foreach ($testMenuProfile in $testMenuProfiles) {
                    Write-Host "$testMenuNumber. $testMenuProfile + Balanced" -ForegroundColor Green
                    $testMenuNumber++
                    Write-Host "$testMenuNumber. $testMenuProfile + Maximum Compression" -ForegroundColor Yellow
                    $testMenuNumber++
                }
                Write-Host "Enter one or more numbers separated by commas." -ForegroundColor White
                Write-Host "Default tests: 5,6,13,14" -ForegroundColor Green

                while ($true) {
                    $videoTestAnswer = (
                        Read-Host "Video tests [comma-separated 1-14, default 5,6,13,14]"
                    ).Trim()

                    if ([string]::IsNullOrWhiteSpace($videoTestAnswer)) {
                        $videoTestAnswer = "5,6,13,14"
                    }

                    $videoTestChoices = New-Object System.Collections.Generic.List[int]
                    $videoTestChoiceSet = [System.Collections.Generic.HashSet[int]]::new()
                    $videoTestAnswerValid = $true

                    foreach ($videoTestToken in ($videoTestAnswer -split ',')) {
                        [int]$parsedVideoTestChoice = 0

                        if (
                            -not [int]::TryParse(
                                $videoTestToken.Trim(),
                                [ref]$parsedVideoTestChoice
                            ) -or
                            $parsedVideoTestChoice -lt 1 -or
                            $parsedVideoTestChoice -gt 14
                        ) {
                            $videoTestAnswerValid = $false
                            break
                        }

                        if ($videoTestChoiceSet.Add($parsedVideoTestChoice)) {
                            [void]$videoTestChoices.Add($parsedVideoTestChoice)
                        }
                    }

                    if ($videoTestAnswerValid -and $videoTestChoices.Count -gt 0) {
                        break
                    }

                    Write-Host "Enter comma-separated values from 1 through 14." -ForegroundColor Yellow
                }

                foreach ($VideoTestChoice in $videoTestChoices) {
                    Invoke-VideoTestEncode `
                        -Root $targetFolder `
                        -TestChoice $VideoTestChoice
                }

                $script:RunAgain = Read-EndAction
                return
            }

            Write-Host "Choose an optimization profile:" -ForegroundColor Cyan
            Write-Host "1. H.264 CRF 20 / AAC 160k" -ForegroundColor White
            Write-Host "2. H.264 CRF 22 / AAC 128k" -ForegroundColor White
            Write-Host "3. Default - H.264 CRF 24 / AAC 96k" -ForegroundColor Green
            Write-Host "4. H.264 CRF 25 / AAC 88k" -ForegroundColor White
            Write-Host "5. H.264 CRF 26 / AAC 80k" -ForegroundColor White
            Write-Host "6. H.264 CRF 27 / AAC 72k" -ForegroundColor White
            Write-Host "7. Super Light - H.264 CRF 28 / AAC 64k" -ForegroundColor Yellow
            $profileChoice = Read-MenuOption -Prompt "Profile" -Minimum 1 -Maximum 7 -Default 3

            $profile = Get-VideoProfileConfig -Choice $profileChoice
            $profileName = $profile.Name
            $profileRank = $profile.Rank
            $maximumWidth = $profile.MaximumWidth
            $maximumHeight = $profile.MaximumHeight
            $resolutionDescription = "Source resolution (no profile cap)"
            $maximumFrameRate = $profile.MaximumFrameRate
            $crf = $profile.Crf
            $audioBitrate = $profile.AudioBitrate
            $defaultEncoderMode = $profile.DefaultEncoderMode

            Write-Host ""
            Write-Host "Choose the H.264 encoder mode:" -ForegroundColor Cyan
            Write-Host "1. Balanced            - Faster conversion with strong compression" -ForegroundColor Green
            Write-Host "2. Maximum Compression - Slower conversion with somewhat smaller output files" -ForegroundColor Yellow
            $encoderModeChoice = Read-MenuOption -Prompt "H.264 encoder mode" -Minimum 1 -Maximum 2 -Default $defaultEncoderMode

            if ($encoderModeChoice -eq 2) {
                $encoderModeName = "Maximum Compression"
                $encoderPreset = "slow"
            }
            else {
                $encoderModeName = "Balanced"
                $encoderPreset = "medium"
            }

            $optimizerMarker = "SYYBOTT'S Video Optimizer v$MediaOptimizerVersion | Profile=$profileName | Rank=$profileRank | CRF=$crf | EncoderMode=$encoderModeName | Preset=$encoderPreset"

            Write-Host ""
            Write-Host "Selected options:" -ForegroundColor Magenta
            Write-Host "Profile:             $profileName" -ForegroundColor White
            Write-Host "Maximum frame rate:  30 FPS" -ForegroundColor White
            Write-Host "Video:               H.264, CRF $crf, $encoderModeName mode, yuv420p" -ForegroundColor White
            Write-Host "Audio:               AAC $audioBitrate stereo when present" -ForegroundColor White
            Write-Host "Output container:    MP4 with faststart" -ForegroundColor White
            Write-Host ""

            # =========================
            # SCAN
            # =========================

            $allFiles = @(Get-VideoFilesSafe -Root $targetFolder)
            $total = $allFiles.Count

            if ($total -eq 0) {
                Write-Host "No supported video files were found in:" -ForegroundColor Yellow
                Write-Host $targetFolder -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Supported extensions: .mp4 .mkv .avi .wmv .mov .webm" -ForegroundColor White
                Read-Host "Press Enter to close"
                exit 0
            }

            $collisionPaths = @{}
            $collisionGroups = @(
                $allFiles |
                Group-Object {
                    [System.IO.Path]::ChangeExtension($_.FullName, ".mp4").ToLowerInvariant()
                } |
                Where-Object { $_.Count -gt 1 }
            )

            foreach ($group in $collisionGroups) {
                foreach ($item in $group.Group) {
                    $collisionPaths[$item.FullName] = $true
                }
            }

            [long]$totalSourceBytes = 0

            foreach ($file in $allFiles) {
                $totalSourceBytes += $file.Length
            }

            Write-Host "Scan root:" -ForegroundColor Magenta
            Write-Host $targetFolder -ForegroundColor White
            Write-Host ""
            Write-Host "Files found:" -ForegroundColor Magenta
            Write-Host "Supported videos:              $total" -ForegroundColor Cyan
            Write-Host "Total source size:             $(Format-ByteSize $totalSourceBytes)" -ForegroundColor Green
            Write-Host "Name-collision groups:         $($collisionGroups.Count)" -ForegroundColor DarkYellow
            Write-Host "Skipped reparse-point dirs:    $($script:SkippedReparsePointDirs.Count)" -ForegroundColor DarkYellow
            Write-Host "Unreadable folders skipped:    $($script:SkippedFolderErrors.Count)" -ForegroundColor DarkYellow
            Write-Host ""

            if ($collisionGroups.Count -gt 0) {
                Write-Host "Same-basename video collisions are skipped entirely for safety." -ForegroundColor DarkYellow
            }

            if ($script:SkippedReparsePointDirs.Count -gt 0) {
                Write-Host "Junctions and symbolic-link directories were excluded from the scan." -ForegroundColor DarkYellow
            }

            if ($script:SkippedFolderErrors.Count -gt 0) {
                Write-Host "Unreadable folders were skipped instead of stopping the entire scan." -ForegroundColor DarkYellow
            }

            Write-Host ""
            Write-Host "IMMEDIATE CLEANUP MODE" -ForegroundColor Yellow
            Write-Host "Every output is written to .mp4.part and validated before any source is removed." -ForegroundColor Yellow
            Write-Host "The smaller valid file is kept. Deleted files bypass the Recycle Bin." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "What the script does:" -ForegroundColor Magenta
            Write-Host "1. Uses the first video stream and the first audio stream when one is present." -ForegroundColor White
            Write-Host "2. Removes subtitles, chapters, attachments, extra streams, and source metadata that ES-DE previews do not need." -ForegroundColor White
            Write-Host "3. Preserves aspect ratio, never upscales, and limits frame rate to 30 FPS." -ForegroundColor White
            Write-Host "4. Encodes audio as stereo AAC at the selected profile bitrate while leaving silent videos silent." -ForegroundColor White
            Write-Host "5. Validates the output container, codec, pixel format, dimensions, frame rate, audio presence, and duration before replacing the source." -ForegroundColor White
            Write-Host "6. Recognizes files previously optimized by this script and skips them when the selected profile would not reduce them further." -ForegroundColor White
            Write-Host "7. Skips same-basename collisions and linked directories to avoid ambiguous replacements or unintended folder scans." -ForegroundColor White
            Write-Host ""
            Write-Host "Use this script at your own risk." -ForegroundColor Yellow
            Write-Host "The script author and contributors are not responsible for lost or damaged data." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Press Enter to continue to the final confirmation." -ForegroundColor Yellow
            Write-Host "Press Ctrl+C now to exit without changing any video files." -ForegroundColor Yellow
            [void](Read-Host)

            Write-Host ""
            $confirmation = Read-Host 'Type CONVERT AND DELETE to begin'
            $normalizedConfirmation = (($confirmation -replace '\s+', ' ').Trim())

            $confirmationAccepted = [string]::Equals(
                $normalizedConfirmation,
                "CONVERT AND DELETE",
                [System.StringComparison]::OrdinalIgnoreCase
            )

            if (-not $confirmationAccepted) {
                Write-Host ""
                Write-Host "Cancelled. No video files were changed." -ForegroundColor Yellow
                Read-Host "Press Enter to close"
                exit 0
            }

            [void](New-Item `
                -ItemType Directory `
                -Path $script:ReportRoot `
                -Force)

            $script:LogPath = Join-Path $script:ReportRoot (
                "SYYBOTT-Media-Optimizer-Video-Report-{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss")
            )

            @(
                "SYYBOTT'S Video Optimizer v$MediaOptimizerVersion"
                "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                "Scan root: $targetFolder"
                "Profile: $profileName"
                "Maximum frame rate: $maximumFrameRate"
                "CRF: $crf"
                "Encoder mode: $encoderModeName"
                "FFmpeg preset: $encoderPreset"
                "Audio bitrate: $audioBitrate"
                ""
            ) | Set-Content -LiteralPath $script:LogPath -Encoding UTF8

            Write-Host ""
            Write-Host "Beginning video optimization with immediate cleanup..." -ForegroundColor Magenta
            Write-Host "Report file: $script:LogPath" -ForegroundColor DarkCyan
            Write-Host ""

            # =========================
            # COUNTERS
            # =========================

            $encoded = 0
            $optimizedFilesKept = 0
            $originalFilesDeleted = 0
            $largerOutputsDiscarded = 0
            $equalOutputsDiscarded = 0
            $collisionSkips = 0
            $alreadyOptimizedSkips = 0
            $staleBackupSkips = 0
            $sourceProbeErrors = 0
            $conversionErrors = 0
            $validationErrors = 0
            $deleteErrors = 0

            [long]$netSavings = 0

            # =========================
            # MAIN LOOP
            # =========================

            for ($index = 0; $index -lt $total; $index++) {
                $source = $allFiles[$index]
                $current = $index + 1
                $color = $entryColors[$index % $entryColors.Count]
                $progressText = Format-NetSavings $netSavings

                if ($collisionPaths.ContainsKey($source.FullName)) {
                    Write-Host "[$current/$total | $progressText] COLLISION SKIP: $($source.Name)" -ForegroundColor DarkYellow
                    Write-Log -Type "COLLISION" -Path $source.FullName -Message "Multiple supported videos map to the same MP4 basename."
                    $collisionSkips++
                    continue
                }

                try {
                    if (-not (Test-Path -LiteralPath $source.FullName -PathType Leaf)) {
                        Write-Host "[$current/$total | $progressText] SOURCE MISSING: $($source.Name)" -ForegroundColor DarkYellow
                        Write-Log -Type "MISSING" -Path $source.FullName -Message "The source disappeared after the initial scan."
                        continue
                    }

                    $sourceFile = Get-Item -LiteralPath $source.FullName
                    $sourceName = $sourceFile.Name
                    $sourcePath = $sourceFile.FullName
                    $sourceExtension = $sourceFile.Extension.ToLowerInvariant()
                    [long]$sourceLength = $sourceFile.Length

                    $finalPath = [System.IO.Path]::ChangeExtension($sourcePath, ".mp4")
                    $tempPath = "$finalPath.part"
                    $backupPath = "$sourcePath.video-optimizer-backup"

                    if (
                        $sourceExtension -eq ".mp4" -and
                        (Test-Path -LiteralPath $backupPath -PathType Leaf)
                    ) {
                        Write-Host "[$current/$total | $progressText] BACKUP EXISTS; SKIPPED: $sourceName" -ForegroundColor Red
                        Write-Host "    Resolve this safety backup before rerunning: $backupPath" -ForegroundColor Red
                        Write-Log -Type "STALE BACKUP" -Path $sourcePath -Message "Safety backup already exists: $backupPath"
                        $staleBackupSkips++
                        continue
                    }

                    if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
                        try {
                            Remove-FileSafe -Path $tempPath
                        }
                        catch {
                            Write-Host "[$current/$total | $progressText] ERROR: Could not remove stale temp file: $tempPath" -ForegroundColor Red
                            Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
                            Write-Log -Type "TEMP DELETE ERROR" -Path $tempPath -Message $_.Exception.Message
                            $deleteErrors++
                            continue
                        }
                    }

                    $sourceProbeResult = Get-MediaProbe -Path $sourcePath

                    if (-not $sourceProbeResult.Success) {
                        Write-Host "[$current/$total | $progressText] SOURCE PROBE ERROR: $sourceName" -ForegroundColor Red
                        if ($sourceProbeResult.Error) {
                            Write-Host "    $($sourceProbeResult.Error)" -ForegroundColor Red
                        }
                        Write-Log -Type "SOURCE PROBE ERROR" -Path $sourcePath -Message $sourceProbeResult.Error
                        $sourceProbeErrors++
                        continue
                    }

                    $sourceProbe = $sourceProbeResult.Probe
                    $sourceVideo = Get-PrimaryVideoStream -Probe $sourceProbe
                    $sourceAudio = Get-PrimaryAudioStream -Probe $sourceProbe

                    if ($null -eq $sourceVideo) {
                        Write-Host "[$current/$total | $progressText] SOURCE PROBE ERROR: No video stream: $sourceName" -ForegroundColor Red
                        Write-Log -Type "SOURCE PROBE ERROR" -Path $sourcePath -Message "No valid video stream was found."
                        $sourceProbeErrors++
                        continue
                    }

                    $existingOptimizerRank = Get-OptimizerProfileRank -Probe $sourceProbe

                    if ($existingOptimizerRank -ge $profileRank) {
                        Write-Host "[$current/$total | $progressText] ALREADY OPTIMIZED SKIP: $sourceName" -ForegroundColor $color
                        $alreadyOptimizedSkips++
                        continue
                    }

                    $sourceHasAudio = ($null -ne $sourceAudio)
                    $sourceDuration = Get-ProbeDuration -Probe $sourceProbe -VideoStream $sourceVideo
                    $sourceFrameRate = Get-StreamFrameRate -VideoStream $sourceVideo

                    $filterParts = New-Object System.Collections.Generic.List[string]

                    if ($maximumWidth -gt 0 -and $maximumHeight -gt 0) {
                        [void]$filterParts.Add(
                            "scale=w='min(iw,$maximumWidth)':h='min(ih,$maximumHeight)':force_original_aspect_ratio=decrease:force_divisible_by=2"
                        )
                    }
                    else {
                        # Preserve source resolution. yuv420p requires even
                        # dimensions, so an odd edge is reduced by one pixel.
                        [void]$filterParts.Add(
                            "scale=w='trunc(iw/2)*2':h='trunc(ih/2)*2'"
                        )
                    }

                    if ($sourceFrameRate -gt ($maximumFrameRate + 0.05)) {
                        [void]$filterParts.Add("fps=30")
                    }

                    $videoFilter = $filterParts -join ","

                    $ffmpegArguments = New-Object System.Collections.Generic.List[string]

                    foreach ($argument in @(
                        "-hide_banner",
                        "-loglevel", "error",
                        "-nostdin",
                        "-y",
                        "-i", $sourcePath,
                        "-map", "0:$($sourceVideo.index)"
                    )) {
                        [void]$ffmpegArguments.Add($argument)
                    }

                    if ($sourceHasAudio) {
                        [void]$ffmpegArguments.Add("-map")
                        [void]$ffmpegArguments.Add("0:$($sourceAudio.index)")
                    }
                    else {
                        [void]$ffmpegArguments.Add("-an")
                    }

                    foreach ($argument in @(
                        "-sn",
                        "-dn",
                        "-map_metadata", "-1",
                        "-map_chapters", "-1",
                        "-vf", $videoFilter,
                        "-c:v", "libx264",
                        "-preset", $encoderPreset,
                        "-crf", "$crf",
                        "-pix_fmt", "yuv420p",
                        "-fps_mode:v", "vfr",
                        "-movflags", "+faststart",
                        "-metadata", "comment=$optimizerMarker",
                        "-max_muxing_queue_size", "2048"
                    )) {
                        [void]$ffmpegArguments.Add($argument)
                    }

                    if ($sourceHasAudio) {
                        foreach ($argument in @(
                            "-c:a", "aac",
                            "-b:a", $audioBitrate,
                            "-ac", "2"
                        )) {
                            [void]$ffmpegArguments.Add($argument)
                        }
                    }

                    [void]$ffmpegArguments.Add("-f")
                    [void]$ffmpegArguments.Add("mp4")
                    [void]$ffmpegArguments.Add($tempPath)

                    Write-Host "[$current/$total | $progressText] ENCODING: $sourceName" -ForegroundColor DarkCyan

                    $encodeResult = Invoke-ExternalProcess -FilePath $ffmpeg -Arguments $ffmpegArguments.ToArray()

                    if (
                        $encodeResult.ExitCode -ne 0 -or
                        -not (Test-Path -LiteralPath $tempPath -PathType Leaf)
                    ) {
                        Write-Host "[$current/$total | $progressText] CONVERSION ERROR: $sourceName" -ForegroundColor Red

                        if ($encodeResult.Output) {
                            $encodeResult.Output -split "`r?`n" | ForEach-Object {
                                if ($_ -ne "") {
                                    Write-Host "    $_" -ForegroundColor Red
                                }
                            }
                        }

                        Write-Log -Type "CONVERSION ERROR" -Path $sourcePath -Message $encodeResult.Output

                        try {
                            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
                        }
                        catch {
                            # SilentlyContinue above should normally prevent this branch.
                        }

                        $conversionErrors++
                        continue
                    }

                    $encoded++

                    $validation = Test-OptimizedVideo `
                        -Path $tempPath `
                        -SourceDuration $sourceDuration `
                        -SourceHasAudio $sourceHasAudio `
                        -MaximumWidth $maximumWidth `
                        -MaximumHeight $maximumHeight `
                        -MaximumFrameRate $maximumFrameRate

                    if (-not $validation.Valid) {
                        Write-Host "[$current/$total | $progressText] VALIDATION ERROR: $sourceName" -ForegroundColor Red
                        Write-Host "    $($validation.Reason)" -ForegroundColor Red
                        Write-Log -Type "VALIDATION ERROR" -Path $sourcePath -Message $validation.Reason

                        try {
                            Remove-FileSafe -Path $tempPath
                        }
                        catch {
                            [long]$tempLength = 0
                            if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
                                $tempLength = (Get-Item -LiteralPath $tempPath).Length
                                $netSavings -= $tempLength
                            }

                            Write-Host "    Could not delete invalid temp output: $($_.Exception.Message)" -ForegroundColor Red
                            Write-Log -Type "TEMP DELETE ERROR" -Path $tempPath -Message $_.Exception.Message
                            $deleteErrors++
                        }

                        $validationErrors++
                        continue
                    }

                    $tempFile = Get-Item -LiteralPath $tempPath
                    [long]$tempLength = $tempFile.Length

                    if ($tempLength -lt $sourceLength) {
                        if ($sourceExtension -eq ".mp4") {
                            $sourceMovedToBackup = $false
                            $tempMovedToFinal = $false

                            try {
                                Move-Item -LiteralPath $sourcePath -Destination $backupPath
                                $sourceMovedToBackup = $true

                                Move-Item -LiteralPath $tempPath -Destination $sourcePath
                                $tempMovedToFinal = $true

                                try {
                                    Remove-FileSafe -Path $backupPath

                                    $optimizedFilesKept++
                                    $originalFilesDeleted++
                                    $netSavings += ($sourceLength - $tempLength)

                                    $progressText = Format-NetSavings $netSavings
                                    Write-Host "[$current/$total | $progressText] OPTIMIZED MP4 KEPT; original deleted: $sourceName" -ForegroundColor $color
                                }
                                catch {
                                    Write-Host "[$current/$total | $progressText] DELETE ERROR: Could not remove MP4 safety backup." -ForegroundColor Red
                                    Write-Host "    Attempting rollback to the original file..." -ForegroundColor Red
                                    Write-Log -Type "BACKUP DELETE ERROR" -Path $backupPath -Message $_.Exception.Message
                                    $deleteErrors++

                                    try {
                                        if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
                                            Remove-FileSafe -Path $sourcePath
                                        }

                                        Move-Item -LiteralPath $backupPath -Destination $sourcePath
                                        Write-Host "    Rollback completed; original MP4 restored." -ForegroundColor Yellow
                                    }
                                    catch {
                                        Write-Host "    CRITICAL: Automatic rollback failed." -ForegroundColor Red
                                        Write-Host "    Original backup: $backupPath" -ForegroundColor Red
                                        Write-Host "    Current output:   $sourcePath" -ForegroundColor Red
                                        Write-Log -Type "CRITICAL ROLLBACK ERROR" -Path $sourcePath -Message $_.Exception.Message
                                    }
                                }
                            }
                            catch {
                                $replacementError = $_.Exception.Message

                                if ($tempMovedToFinal) {
                                    try {
                                        Remove-FileSafe -Path $sourcePath
                                    }
                                    catch {
                                        # Preserve all remaining files and report below.
                                    }
                                }

                                if (
                                    $sourceMovedToBackup -and
                                    (Test-Path -LiteralPath $backupPath -PathType Leaf) -and
                                    -not (Test-Path -LiteralPath $sourcePath -PathType Leaf)
                                ) {
                                    try {
                                        Move-Item -LiteralPath $backupPath -Destination $sourcePath
                                    }
                                    catch {
                                        Write-Log -Type "CRITICAL ROLLBACK ERROR" -Path $sourcePath -Message $_.Exception.Message
                                    }
                                }

                                if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
                                    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
                                }

                                Write-Host "[$current/$total | $progressText] REPLACEMENT ERROR: Original MP4 retained or recoverable from backup." -ForegroundColor Red
                                Write-Host "    $replacementError" -ForegroundColor Red
                                Write-Log -Type "REPLACEMENT ERROR" -Path $sourcePath -Message $replacementError
                                $deleteErrors++
                            }
                        }
                        else {
                            $finalCreated = $false

                            try {
                                Move-Item -LiteralPath $tempPath -Destination $finalPath
                                $finalCreated = $true

                                try {
                                    Remove-FileSafe -Path $sourcePath

                                    $optimizedFilesKept++
                                    $originalFilesDeleted++
                                    $netSavings += ($sourceLength - $tempLength)

                                    $progressText = Format-NetSavings $netSavings
                                    Write-Host "[$current/$total | $progressText] CONVERTED TO MP4; original deleted: $sourceName" -ForegroundColor $color
                                }
                                catch {
                                    Write-Host "[$current/$total | $progressText] DELETE ERROR: Original retained; rolling back new MP4." -ForegroundColor Red
                                    Write-Log -Type "SOURCE DELETE ERROR" -Path $sourcePath -Message $_.Exception.Message
                                    $deleteErrors++

                                    try {
                                        Remove-FileSafe -Path $finalPath
                                        Write-Host "    Rollback completed; original retained." -ForegroundColor Yellow
                                    }
                                    catch {
                                        $netSavings -= $tempLength
                                        Write-Host "    Rollback failed; both source and MP4 remain." -ForegroundColor Red
                                        Write-Log -Type "ROLLBACK DELETE ERROR" -Path $finalPath -Message $_.Exception.Message
                                    }
                                }
                            }
                            catch {
                                $replacementError = $_.Exception.Message

                                if ($finalCreated -and (Test-Path -LiteralPath $finalPath -PathType Leaf)) {
                                    Remove-Item -LiteralPath $finalPath -Force -ErrorAction SilentlyContinue
                                }

                                if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
                                    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
                                }

                                Write-Host "[$current/$total | $progressText] REPLACEMENT ERROR: Original retained: $sourceName" -ForegroundColor Red
                                Write-Host "    $replacementError" -ForegroundColor Red
                                Write-Log -Type "REPLACEMENT ERROR" -Path $sourcePath -Message $replacementError
                                $deleteErrors++
                            }
                        }
                    }
                    elseif ($tempLength -gt $sourceLength) {
                        try {
                            Remove-FileSafe -Path $tempPath
                            $largerOutputsDiscarded++

                            $progressText = Format-NetSavings $netSavings
                            Write-Host "[$current/$total | $progressText] OUTPUT WAS LARGER; original kept: $sourceName" -ForegroundColor $color
                        }
                        catch {
                            $netSavings -= $tempLength
                            Write-Host "[$current/$total | $progressText] DELETE ERROR: Larger temp output remains: $sourceName" -ForegroundColor Red
                            Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
                            Write-Log -Type "TEMP DELETE ERROR" -Path $tempPath -Message $_.Exception.Message
                            $deleteErrors++
                        }
                    }
                    else {
                        try {
                            Remove-FileSafe -Path $tempPath
                            $equalOutputsDiscarded++

                            $progressText = Format-NetSavings $netSavings
                            Write-Host "[$current/$total | $progressText] EQUAL-SIZE OUTPUT DISCARDED; original kept: $sourceName" -ForegroundColor $color
                        }
                        catch {
                            $netSavings -= $tempLength
                            Write-Host "[$current/$total | $progressText] DELETE ERROR: Equal-size temp output remains: $sourceName" -ForegroundColor Red
                            Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
                            Write-Log -Type "TEMP DELETE ERROR" -Path $tempPath -Message $_.Exception.Message
                            $deleteErrors++
                        }
                    }
                }
                catch {
                    $progressText = Format-NetSavings $netSavings
                    Write-Host "[$current/$total | $progressText] UNEXPECTED ERROR: $($source.FullName)" -ForegroundColor Red
                    Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
                    Write-Log -Type "UNEXPECTED ERROR" -Path $source.FullName -Message $_.Exception.Message
                    $conversionErrors++
                }
            }

            # =========================
            # SUMMARY
            # =========================

            Write-Host ""
            Write-Host "Finished." -ForegroundColor Green
            Write-Host ""
            Write-Host "Profile used:                     $profileName" -ForegroundColor Cyan
            Write-Host "H.264 encoder mode:               $encoderModeName" -ForegroundColor Cyan
            Write-Host "Videos encoded:                   $encoded" -ForegroundColor Cyan
            Write-Host "Optimized videos kept:            $optimizedFilesKept" -ForegroundColor Green
            Write-Host "Original videos deleted:          $originalFilesDeleted" -ForegroundColor Green
            Write-Host "Larger outputs discarded:         $largerOutputsDiscarded" -ForegroundColor Magenta
            Write-Host "Equal-size outputs discarded:     $equalOutputsDiscarded" -ForegroundColor Yellow
            Write-Host "Already-optimized skips:          $alreadyOptimizedSkips" -ForegroundColor White
            Write-Host "Filename-collision skips:         $collisionSkips" -ForegroundColor DarkYellow
            Write-Host "Existing-backup skips:            $staleBackupSkips" -ForegroundColor DarkYellow
            Write-Host "Skipped reparse-point dirs:       $($script:SkippedReparsePointDirs.Count)" -ForegroundColor DarkYellow
            Write-Host "Test folders skipped:             $($script:SkippedTestFolders.Count)" -ForegroundColor DarkYellow
            Write-Host "Unreadable folders skipped:       $($script:SkippedFolderErrors.Count)" -ForegroundColor DarkYellow

            if ($sourceProbeErrors -gt 0) {
                Write-Host "Source probe errors:              $sourceProbeErrors" -ForegroundColor Red
            }
            else {
                Write-Host "Source probe errors:              0" -ForegroundColor Green
            }

            if ($conversionErrors -gt 0) {
                Write-Host "Conversion errors:                $conversionErrors" -ForegroundColor Red
            }
            else {
                Write-Host "Conversion errors:                0" -ForegroundColor Green
            }

            if ($validationErrors -gt 0) {
                Write-Host "Validation errors:                $validationErrors" -ForegroundColor Red
            }
            else {
                Write-Host "Validation errors:                0" -ForegroundColor Green
            }

            if ($deleteErrors -gt 0) {
                Write-Host "Deletion/replacement errors:      $deleteErrors" -ForegroundColor Red
            }
            else {
                Write-Host "Deletion/replacement errors:      0" -ForegroundColor Green
            }

            if ($totalSourceBytes -gt 0) {
                $storageChangePercent = ([double]$netSavings / [double]$totalSourceBytes) * 100
            }
            else {
                $storageChangePercent = 0
            }

            $reportedSavings = [math]::Max([long]0, $netSavings)
            $reportedSavingsPercent = [math]::Max([double]0, $storageChangePercent)

            Write-Host (
                "Actual net storage saved:         {0}" -f
                (Format-ByteSize $reportedSavings)
            ) -ForegroundColor Yellow

            Write-Host (
                "Library size reduction:           {0:N2}%" -f
                $reportedSavingsPercent
            ) -ForegroundColor Yellow

            $videoReportLines = New-Object System.Collections.Generic.List[string]
            [void]$videoReportLines.Add("")
            [void]$videoReportLines.Add("SUMMARY")
            [void]$videoReportLines.Add("Finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
            [void]$videoReportLines.Add("Profile used:                     $profileName")
            [void]$videoReportLines.Add("H.264 encoder mode:               $encoderModeName")
            [void]$videoReportLines.Add("Videos encoded:                   $encoded")
            [void]$videoReportLines.Add("Optimized videos kept:            $optimizedFilesKept")
            [void]$videoReportLines.Add("Original videos deleted:          $originalFilesDeleted")
            [void]$videoReportLines.Add("Larger outputs discarded:         $largerOutputsDiscarded")
            [void]$videoReportLines.Add("Equal-size outputs discarded:     $equalOutputsDiscarded")
            [void]$videoReportLines.Add("Already-optimized skips:          $alreadyOptimizedSkips")
            [void]$videoReportLines.Add("Filename-collision skips:         $collisionSkips")
            [void]$videoReportLines.Add("Existing-backup skips:            $staleBackupSkips")
            [void]$videoReportLines.Add("Skipped reparse-point dirs:       $($script:SkippedReparsePointDirs.Count)")
            [void]$videoReportLines.Add("Test folders skipped:             $($script:SkippedTestFolders.Count)")
            [void]$videoReportLines.Add("Unreadable folders skipped:       $($script:SkippedFolderErrors.Count)")
            [void]$videoReportLines.Add("Source probe errors:              $sourceProbeErrors")
            [void]$videoReportLines.Add("Conversion errors:                $conversionErrors")
            [void]$videoReportLines.Add("Validation errors:                $validationErrors")
            [void]$videoReportLines.Add("Deletion/replacement errors:      $deleteErrors")
            [void]$videoReportLines.Add("Actual net storage saved:         $(Format-ByteSize $reportedSavings)")
            [void]$videoReportLines.Add(("Library size reduction:           {0:N2}%" -f $reportedSavingsPercent))

            if ($script:SkippedReparsePointDirs.Count -gt 0) {
                [void]$videoReportLines.Add("")
                [void]$videoReportLines.Add("SKIPPED LINKED DIRECTORIES")
                foreach ($directory in $script:SkippedReparsePointDirs) {
                    [void]$videoReportLines.Add($directory)
                }
            }

            if ($script:SkippedTestFolders.Count -gt 0) {
                [void]$videoReportLines.Add("")
                [void]$videoReportLines.Add("EXCLUDED TEST FOLDERS")
                foreach ($directory in $script:SkippedTestFolders) {
                    [void]$videoReportLines.Add($directory)
                }
            }

            if ($script:SkippedFolderErrors.Count -gt 0) {
                [void]$videoReportLines.Add("")
                [void]$videoReportLines.Add("UNREADABLE FOLDERS")
                foreach ($folderError in $script:SkippedFolderErrors) {
                    [void]$videoReportLines.Add($folderError)
                }
            }

            $videoReportLines |
                Add-Content -LiteralPath $script:LogPath -Encoding UTF8

            Write-Host "Report file:                       $script:LogPath" -ForegroundColor DarkCyan
            Write-Host ""

            $script:RunAgain = Read-EndAction
        }
    }
    }
} while ($script:RunAgain)
