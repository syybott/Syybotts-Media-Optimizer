#requires -version 5.1
# SYYBOTT'S MEDIA OPTIMIZER COPY MODE v1.0.3
param(
    [Parameter(Mandatory = $true)][ValidateSet("Image", "Video")][string]$Mode,
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [Parameter(Mandatory = $true)][string]$DestinationRoot,
    [Parameter(Mandatory = $true)][ValidateSet("Skip", "ReplaceSmaller", "Rebuild")][string]$Policy,
    [Parameter(Mandatory = $true)][string]$LogsRoot,
    [Parameter(Mandatory = $true)][string]$CwebpPath,
    [Parameter(Mandatory = $true)][string]$FfmpegPath,
    [Parameter(Mandatory = $true)][string]$FfprobePath,
    [int]$PngCompression = 10,
    [ValidateRange(1, 2)][int]$PngHandling = 2,
    [int]$JpegQuality = 90,
    [int]$JpegHandling = 1,
    [ValidateRange(1, 7)][int]$VideoProfile = 3,
    [int]$EncoderMode = 0,
    [switch]$VerifyDestination
)

$ErrorActionPreference = "Stop"
$CopyModeVersion = "1.0.3"
$SourceRoot = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')
$DestinationRoot = [IO.Path]::GetFullPath($DestinationRoot).TrimEnd('\')
$LogsRoot = [IO.Path]::GetFullPath($LogsRoot)
$ManifestPath = Join-Path $DestinationRoot ".syybott-media-optimizer-manifest.jsonl"
$ReportPath = Join-Path $LogsRoot (
    "SYYBOTT-Media-Optimizer-Copy-{0}-Report-{1}.txt" -f
    $Mode,
    (Get-Date -Format "yyyyMMdd-HHmmss")
)
$script:ReportLines = [Collections.Generic.List[string]]::new()
$script:Manifest = @{}
$script:Stats = [ordered]@{
    SourceFiles = 0
    OriginalsCopied = 0
    ConvertedWebPsCopied = 0
    OptimizedVideosCopied = 0
    DuplicateWinners = 0
    ExistingSkipped = 0
    ExistingReplaced = 0
    Failures = 0
    Verified = 0
    VerificationFailures = 0
    SourceBytes = [long]0
    DestinationBytes = [long]0
}

function Write-Status {
    param([string]$Text, [ConsoleColor]$Color = [ConsoleColor]::White)
    Write-Host $Text -ForegroundColor $Color
    [void]$script:ReportLines.Add($Text)
}

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes bytes"
}

function Get-RelativePath {
    param([string]$Path)
    return $Path.Substring($SourceRoot.Length).TrimStart([char[]]@('\', '/'))
}

function Test-PathInside {
    param([string]$Child, [string]$Parent)
    $parentPrefix = $Parent.TrimEnd('\') + '\'
    return $Child.StartsWith($parentPrefix, [StringComparison]::OrdinalIgnoreCase)
}

function Invoke-Native {
    param([string]$FilePath, [string[]]$Arguments)
    $quotedArguments = foreach ($argument in $Arguments) {
        if ($argument -notmatch '[\s"]') { $argument; continue }
        '"' + ($argument -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
    }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $quotedArguments -join " "
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $psi
    if (-not $process.Start()) { throw "Could not start $FilePath." }
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $result = [pscustomobject]@{
        ExitCode = $process.ExitCode
        Output = ($stdout + [Environment]::NewLine + $stderr).Trim()
    }
    $process.Dispose()
    return $result
}

function Test-WebP {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $file = Get-Item -LiteralPath $Path
    if ($file.Length -lt 12) { return $false }
    $stream = [IO.File]::Open($Path, "Open", "Read", "Read")
    try {
        $bytes = New-Object byte[] 12
        if ($stream.Read($bytes, 0, 12) -ne 12) { return $false }
        $riff = [Text.Encoding]::ASCII.GetString($bytes, 0, 4)
        $webp = [Text.Encoding]::ASCII.GetString($bytes, 8, 4)
        $declared = [BitConverter]::ToUInt32($bytes, 4) + 8
        return ($riff -eq "RIFF" -and $webp -eq "WEBP" -and $declared -eq $file.Length)
    }
    finally { $stream.Dispose() }
}

function Test-TransparentPng {
    param([string]$Path)
    try {
        Add-Type -AssemblyName System.Drawing
        $bitmap = New-Object Drawing.Bitmap($Path)
        try {
            if (($bitmap.PixelFormat -band [Drawing.Imaging.PixelFormat]::Alpha) -eq 0) {
                return $false
            }
            for ($y = 0; $y -lt $bitmap.Height; $y++) {
                for ($x = 0; $x -lt $bitmap.Width; $x++) {
                    if ($bitmap.GetPixel($x, $y).A -lt 255) { return $true }
                }
            }
        }
        finally { $bitmap.Dispose() }
    }
    catch { return $true }
    return $false
}

function Get-VideoDuration {
    param([string]$Path)
    $result = Invoke-Native -FilePath $FfprobePath -Arguments @(
        "-v", "error", "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1", $Path
    )
    $duration = 0.0
    if (
        $result.ExitCode -eq 0 -and
        [double]::TryParse(
            $result.Output.Trim(),
            [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$duration
        )
    ) { return $duration }
    return 0.0
}

function Test-Video {
    param([string]$Path, [bool]$RequireAudio, [string]$SourcePath)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $probe = Invoke-Native -FilePath $FfprobePath -Arguments @(
        "-v", "error", "-show_entries", "stream=codec_type,codec_name,pix_fmt",
        "-of", "json", $Path
    )
    if ($probe.ExitCode -ne 0) { return $false }
    try { $json = $probe.Output | ConvertFrom-Json } catch { return $false }
    $video = @($json.streams | Where-Object {
        $_.codec_type -eq "video" -and $_.codec_name -eq "h264" -and $_.pix_fmt -eq "yuv420p"
    })
    if ($video.Count -eq 0) { return $false }
    if ($RequireAudio -and @($json.streams | Where-Object { $_.codec_type -eq "audio" }).Count -eq 0) {
        return $false
    }
    $sourceDuration = Get-VideoDuration $SourcePath
    $outputDuration = Get-VideoDuration $Path
    if ($sourceDuration -le 0 -or $outputDuration -le 0) { return $false }
    $allowedDifference = [math]::Max(0.5, $sourceDuration * 0.01)
    if ([math]::Abs($sourceDuration - $outputDuration) -gt $allowedDifference) {
        return $false
    }
    return $true
}

function Get-SourceHasAudio {
    param([string]$Path)
    $probe = Invoke-Native -FilePath $FfprobePath -Arguments @(
        "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=index",
        "-of", "csv=p=0", $Path
    )
    return ($probe.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($probe.Output))
}

function Read-Manifest {
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { return }
    foreach ($line in [IO.File]::ReadLines($ManifestPath)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $record = $line | ConvertFrom-Json
            $script:Manifest["$($record.SourceKey)"] = $record
        }
        catch { }
    }
}

function Add-ManifestRecord {
    param([string]$SourceKey, [string]$DestinationRelative, [long]$SourceLength, [long]$DestinationLength)
    $record = [ordered]@{
        SourceKey = $SourceKey
        DestinationRelative = $DestinationRelative
        SourceLength = $SourceLength
        DestinationLength = $DestinationLength
        CompletedUtc = [DateTime]::UtcNow.ToString("o")
    }
    Add-Content -LiteralPath $ManifestPath -Value ($record | ConvertTo-Json -Compress) -Encoding UTF8
    $script:Manifest[$SourceKey] = [pscustomobject]$record
}

function Copy-Winner {
    param(
        [string]$CandidatePath,
        [string]$DestinationRelative,
        [string]$SourceKey,
        [long]$SourceLength,
        [switch]$TemporaryCandidate
    )
    $destinationPath = Join-Path $DestinationRoot $DestinationRelative
    $destinationDirectory = Split-Path -Parent $destinationPath
    [void](New-Item -ItemType Directory -Path $destinationDirectory -Force)
    $candidate = Get-Item -LiteralPath $CandidatePath

    if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
        $existing = Get-Item -LiteralPath $destinationPath
        if ($Policy -eq "Skip") {
            $script:Stats.ExistingSkipped++
            Write-Status "SKIPPED EXISTING: $DestinationRelative" DarkYellow
            Add-ManifestRecord -SourceKey $SourceKey -DestinationRelative $DestinationRelative -SourceLength $SourceLength -DestinationLength $existing.Length
            if ($TemporaryCandidate) { Remove-Item -LiteralPath $CandidatePath -Force -ErrorAction SilentlyContinue }
            return
        }
        if ($Policy -eq "ReplaceSmaller" -and $existing.Length -le $candidate.Length) {
            $script:Stats.ExistingSkipped++
            Write-Status "KEPT SMALLER DESTINATION: $DestinationRelative" DarkYellow
            Add-ManifestRecord -SourceKey $SourceKey -DestinationRelative $DestinationRelative -SourceLength $SourceLength -DestinationLength $existing.Length
            if ($TemporaryCandidate) { Remove-Item -LiteralPath $CandidatePath -Force -ErrorAction SilentlyContinue }
            return
        }
        $script:Stats.ExistingReplaced++
    }

    $partPath = "$destinationPath.copy-part"
    Copy-Item -LiteralPath $CandidatePath -Destination $partPath -Force
    Move-Item -LiteralPath $partPath -Destination $destinationPath -Force
    if ($TemporaryCandidate) { Remove-Item -LiteralPath $CandidatePath -Force -ErrorAction SilentlyContinue }
    $written = Get-Item -LiteralPath $destinationPath
    $script:Stats.DestinationBytes += [long]$written.Length
    Add-ManifestRecord -SourceKey $SourceKey -DestinationRelative $DestinationRelative -SourceLength $SourceLength -DestinationLength $written.Length
    Write-Status "COPIED: $DestinationRelative ($(Format-Bytes $written.Length))" Green
}

function Get-SafeFiles {
    param([string[]]$Extensions)
    $excluded = @("Test Images", "Test Videos", "SYYBOTT-JPG-Test", "SYYBOTT-Video-Test")
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($SourceRoot)
    while ($pending.Count -gt 0) {
        $folder = $pending.Pop()
        foreach ($item in @(Get-ChildItem -LiteralPath $folder -Force -ErrorAction SilentlyContinue)) {
            if ($item.PSIsContainer) {
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                if ($excluded -contains $item.Name) { continue }
                $pending.Push($item.FullName)
            }
            elseif ($Extensions -contains $item.Extension.ToLowerInvariant()) { $item }
        }
    }
}

function Get-FreeBytes {
    param([string]$Path)
    $root = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path))
    return [long]([IO.DriveInfo]::new($root).AvailableFreeSpace)
}

if (Test-PathInside -Child $DestinationRoot -Parent $SourceRoot) {
    throw "The Copy Mode destination cannot be inside the source library."
}
if (Test-PathInside -Child $SourceRoot -Parent $DestinationRoot) {
    throw "The source library cannot be inside the Copy Mode destination."
}

[void](New-Item -ItemType Directory -Path $LogsRoot -Force)
if ($Policy -eq "Rebuild" -and (Test-Path -LiteralPath $DestinationRoot -PathType Container)) {
    Get-ChildItem -LiteralPath $DestinationRoot -Force | Remove-Item -Recurse -Force
}
[void](New-Item -ItemType Directory -Path $DestinationRoot -Force)
Read-Manifest

Write-Status "SYYBOTT'S MEDIA OPTIMIZER - $Mode COPY MODE" Magenta
Write-Status "Source: $SourceRoot"
Write-Status "Destination: $DestinationRoot"
Write-Status "Policy: $Policy"
Write-Status "The source library remains unchanged." Green
Write-Status ""

if ($Mode -eq "Image") {
    $allFiles = @(Get-SafeFiles -Extensions @(".png", ".jpg", ".jpeg", ".webp"))
    $groups = @($allFiles | Group-Object {
        "$($_.DirectoryName.ToLowerInvariant())|$([IO.Path]::GetFileNameWithoutExtension($_.Name).ToLowerInvariant())"
    })
    $script:Stats.SourceFiles = $allFiles.Count
    $script:Stats.SourceBytes = [long](($allFiles | Measure-Object Length -Sum).Sum)

    $existingDestinationBytes = [long]((Get-ChildItem -LiteralPath $DestinationRoot -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object Length -Sum).Sum)
    if (((Get-FreeBytes $DestinationRoot) + $existingDestinationBytes) -lt $script:Stats.SourceBytes) {
        throw "The destination does not have enough free space to start Copy Mode safely."
    }

    $index = 0
    foreach ($group in $groups) {
        $index++
        $files = @($group.Group)
        $relativeDirectory = Split-Path -Parent (Get-RelativePath $files[0].FullName)
        $baseName = [IO.Path]::GetFileNameWithoutExtension($files[0].Name)
        Write-Status "[$index/$($groups.Count) | COPY] $relativeDirectory\$baseName" Cyan

        if ($PngHandling -eq 1) {
            $skippedPngFiles = @(
                $files |
                Where-Object { $_.Extension -ieq ".png" }
            )

            foreach ($pngFile in $skippedPngFiles) {
                $pngRelative = Get-RelativePath $pngFile.FullName
                $pngSourceKey = (
                    "Image:SkippedPng|{0}:{1}:{2}" -f
                    $pngRelative,
                    $pngFile.Length,
                    $pngFile.LastWriteTimeUtc.Ticks
                )

                if ($script:Manifest.ContainsKey($pngSourceKey)) {
                    $pngRecord = $script:Manifest[$pngSourceKey]
                    $pngCompletedPath = Join-Path (
                        $DestinationRoot
                    ) $pngRecord.DestinationRelative
                    if (
                        (Test-Path -LiteralPath $pngCompletedPath -PathType Leaf) -and
                        (Get-Item -LiteralPath $pngCompletedPath).Length -eq
                            $pngRecord.DestinationLength
                    ) {
                        $script:Stats.ExistingSkipped++
                        Write-Status "RESUMED / ALREADY COMPLETE: $pngRelative" DarkYellow
                        continue
                    }
                }

                $script:Stats.OriginalsCopied++
                Copy-Winner `
                    -CandidatePath $pngFile.FullName `
                    -DestinationRelative $pngRelative `
                    -SourceKey $pngSourceKey `
                    -SourceLength $pngFile.Length
            }

            $files = @(
                $files |
                Where-Object { $_.Extension -ine ".png" }
            )

            if ($files.Count -eq 0) {
                continue
            }
        }

        if ($JpegHandling -eq 1) {
            $skippedJpegFiles = @(
                $files |
                Where-Object {
                    $_.Extension -iin @(".jpg", ".jpeg")
                }
            )

            foreach ($jpegFile in $skippedJpegFiles) {
                $jpegRelative = Get-RelativePath $jpegFile.FullName
                $jpegSourceKey = (
                    "Image:SkippedJpeg|{0}:{1}:{2}" -f
                    $jpegRelative,
                    $jpegFile.Length,
                    $jpegFile.LastWriteTimeUtc.Ticks
                )

                if ($script:Manifest.ContainsKey($jpegSourceKey)) {
                    $jpegRecord = $script:Manifest[$jpegSourceKey]
                    $jpegCompletedPath = Join-Path (
                        $DestinationRoot
                    ) $jpegRecord.DestinationRelative
                    if (
                        (Test-Path -LiteralPath $jpegCompletedPath -PathType Leaf) -and
                        (Get-Item -LiteralPath $jpegCompletedPath).Length -eq
                            $jpegRecord.DestinationLength
                    ) {
                        $script:Stats.ExistingSkipped++
                        Write-Status "RESUMED / ALREADY COMPLETE: $jpegRelative" DarkYellow
                        continue
                    }
                }

                $script:Stats.OriginalsCopied++
                Copy-Winner `
                    -CandidatePath $jpegFile.FullName `
                    -DestinationRelative $jpegRelative `
                    -SourceKey $jpegSourceKey `
                    -SourceLength $jpegFile.Length
            }

            $files = @(
                $files |
                Where-Object {
                    $_.Extension -inotmatch '^\.jpe?g$'
                }
            )

            if ($files.Count -eq 0) {
                continue
            }

            $relativeDirectory = Split-Path -Parent (
                Get-RelativePath $files[0].FullName
            )
            $baseName = [IO.Path]::GetFileNameWithoutExtension($files[0].Name)
        }

        $sourceKey = "Image:Png=${PngCompression}:PngHandling=${PngHandling}:Jpeg=${JpegQuality}:Handling=${JpegHandling}|" + (($files | Sort-Object FullName | ForEach-Object {
            "{0}:{1}:{2}" -f (Get-RelativePath $_.FullName), $_.Length, $_.LastWriteTimeUtc.Ticks
        }) -join "|")
        if ($script:Manifest.ContainsKey($sourceKey)) {
            $record = $script:Manifest[$sourceKey]
            $completedPath = Join-Path $DestinationRoot $record.DestinationRelative
            if (
                (Test-Path -LiteralPath $completedPath -PathType Leaf) -and
                (Get-Item -LiteralPath $completedPath).Length -eq $record.DestinationLength
            ) {
                $script:Stats.ExistingSkipped++
                Write-Status "RESUMED / ALREADY COMPLETE: $($record.DestinationRelative)" DarkYellow
                continue
            }
        }

        $candidates = [Collections.Generic.List[object]]::new()
        $transparentPng = @($files | Where-Object {
            $_.Extension -ieq ".png" -and (Test-TransparentPng $_.FullName)
        })
        foreach ($file in $files) {
            if ($file.Extension -ieq ".webp" -and (Test-WebP $file.FullName)) {
                [void]$candidates.Add([pscustomobject]@{
                    Path=$file.FullName; Length=[long]$file.Length; Relative=(Join-Path $relativeDirectory "$baseName.webp");
                    Temporary=$false; Type="ExistingWebP"; Lossless=$false
                })
                continue
            }
            if (
                $file.Extension -iin @(".jpg", ".jpeg") -and
                $JpegHandling -eq 1
            ) {
                [void]$candidates.Add([pscustomobject]@{
                    Path=$file.FullName; Length=[long]$file.Length; Relative=(Join-Path $relativeDirectory $file.Name);
                    Temporary=$false; Type="Original"; Lossless=$false
                })
                continue
            }
            $temp = Join-Path ([IO.Path]::GetTempPath()) ("syybott-" + [guid]::NewGuid().ToString("N") + ".webp")
            $arguments = if ($file.Extension -ieq ".png") {
                @("-z", [string]([math]::Max(0, $PngCompression - 1)), "-o", $temp, $file.FullName)
            } else {
                @("-preset", "photo", "-q", [string]$JpegQuality, "-m", "6", "-mt", "-o", $temp, $file.FullName)
            }
            $result = Invoke-Native -FilePath $CwebpPath -Arguments $arguments
            if ($result.ExitCode -eq 0 -and (Test-WebP $temp)) {
                $tempFile = Get-Item -LiteralPath $temp
                [void]$candidates.Add([pscustomobject]@{
                    Path=$temp; Length=[long]$tempFile.Length; Relative=(Join-Path $relativeDirectory "$baseName.webp");
                    Temporary=$true; Type="ConvertedWebP"; Lossless=($file.Extension -ieq ".png")
                })
            } else {
                Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
                $script:Stats.Failures++
            }
            [void]$candidates.Add([pscustomobject]@{
                Path=$file.FullName; Length=[long]$file.Length; Relative=(Join-Path $relativeDirectory $file.Name);
                Temporary=$false; Type="Original"; Lossless=($file.Extension -ieq ".png")
            })
        }

        if ($transparentPng.Count -gt 0) {
            $eligible = @($candidates | Where-Object { $_.Lossless })
        } else {
            $eligible = @($candidates)
        }
        $winner = $eligible | Sort-Object Length, @{Expression={if($_.Lossless){0}else{1}}} | Select-Object -First 1
        if ($null -eq $winner) {
            $script:Stats.Failures++
            Write-Status "NO VALID CANDIDATE: $relativeDirectory\$baseName" Red
            continue
        }
        foreach ($candidate in $candidates) {
            if ($candidate.Temporary -and $candidate.Path -ne $winner.Path) {
                Remove-Item -LiteralPath $candidate.Path -Force -ErrorAction SilentlyContinue
            }
        }
        if ($files.Count -gt 1) { $script:Stats.DuplicateWinners++ }
        if ($winner.Type -eq "ConvertedWebP") { $script:Stats.ConvertedWebPsCopied++ }
        else { $script:Stats.OriginalsCopied++ }
        Copy-Winner -CandidatePath $winner.Path -DestinationRelative $winner.Relative -SourceKey $sourceKey -SourceLength (($files | Measure-Object Length -Sum).Sum) -TemporaryCandidate:$winner.Temporary
    }
}
else {
    $videoFiles = @(Get-SafeFiles -Extensions @(".mp4", ".mkv", ".avi", ".wmv", ".mov", ".webm"))
    $script:Stats.SourceFiles = $videoFiles.Count
    $script:Stats.SourceBytes = [long](($videoFiles | Measure-Object Length -Sum).Sum)
    $existingDestinationBytes = [long]((Get-ChildItem -LiteralPath $DestinationRoot -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object Length -Sum).Sum)
    if (((Get-FreeBytes $DestinationRoot) + $existingDestinationBytes) -lt $script:Stats.SourceBytes) {
        throw "The destination does not have enough free space to start Copy Mode safely."
    }
    $groups = @($videoFiles | Group-Object {
        "$($_.DirectoryName.ToLowerInvariant())|$([IO.Path]::GetFileNameWithoutExtension($_.Name).ToLowerInvariant())"
    })
    $index = 0
    foreach ($group in $groups) {
        $index++
        $files = @($group.Group)
        $source = $files | Sort-Object Length | Select-Object -First 1
        $relative = Get-RelativePath $source.FullName
        $relativeDirectory = Split-Path -Parent $relative
        $baseName = [IO.Path]::GetFileNameWithoutExtension($source.Name)
        $sourceKey = "Video:Profile=$VideoProfile:Encoder=$EncoderMode|${relative}:$($source.Length):$($source.LastWriteTimeUtc.Ticks)"
        Write-Status "[$index/$($groups.Count) | COPY] $relative" Cyan
        if ($script:Manifest.ContainsKey($sourceKey)) {
            $record = $script:Manifest[$sourceKey]
            $completedPath = Join-Path $DestinationRoot $record.DestinationRelative
            if (
                (Test-Path -LiteralPath $completedPath -PathType Leaf) -and
                (Get-Item -LiteralPath $completedPath).Length -eq $record.DestinationLength
            ) {
                $script:Stats.ExistingSkipped++
                Write-Status "RESUMED / ALREADY COMPLETE: $($record.DestinationRelative)" DarkYellow
                continue
            }
        }
        $hasAudio = Get-SourceHasAudio $source.FullName
        $temp = Join-Path ([IO.Path]::GetTempPath()) ("syybott-" + [guid]::NewGuid().ToString("N") + ".mp4")
        $profileSettings = switch ($VideoProfile) {
            1 { @("H.264 CRF 20 / AAC 160k", 0, "20", "160k") }
            2 { @("H.264 CRF 22 / AAC 128k", 1, "22", "128k") }
            3 { @("Default", 2, "24", "96k") }
            4 { @("H.264 CRF 25 / AAC 88k", 3, "25", "88k") }
            5 { @("H.264 CRF 26 / AAC 80k", 4, "26", "80k") }
            6 { @("H.264 CRF 27 / AAC 72k", 5, "27", "72k") }
            7 { @("Super Light", 6, "28", "64k") }
        }
        $profileName = [string]$profileSettings[0]
        $profileRank = [int]$profileSettings[1]
        $profileCrf = [string]$profileSettings[2]
        $audioRate = [string]$profileSettings[3]
        $preset = if ($EncoderMode -eq 1) { "slow" } else { "medium" }
        $encoderModeName = if ($EncoderMode -eq 1) {
            "Maximum Compression"
        } else {
            "Balanced"
        }
        $optimizerMarker = (
            "SYYBOTT'S Video Optimizer v1.0.31 | " +
            "Profile=$profileName | Rank=$profileRank | CRF=$profileCrf | " +
            "EncoderMode=$encoderModeName | Preset=$preset"
        )
        $arguments = [Collections.Generic.List[string]]::new()
        foreach ($value in @("-hide_banner","-loglevel","error","-nostdin","-y","-i",$source.FullName,"-map","0:v:0")) { [void]$arguments.Add($value) }
        if ($hasAudio) { foreach ($value in @("-map","0:a:0","-c:a","aac","-b:a",$audioRate,"-ac","2")) { [void]$arguments.Add($value) } }
        else { [void]$arguments.Add("-an") }
        foreach ($value in @("-sn","-dn","-map_metadata","-1","-map_chapters","-1","-metadata","comment=$optimizerMarker","-vf","scale=w='trunc(iw/2)*2':h='trunc(ih/2)*2',fps='min(source_fps,30)'","-c:v","libx264","-preset",$preset,"-crf",$profileCrf,"-pix_fmt","yuv420p","-movflags","+faststart","-f","mp4",$temp)) { [void]$arguments.Add($value) }
        $result = Invoke-Native -FilePath $FfmpegPath -Arguments $arguments.ToArray()
        $candidate = $source
        $temporary = $false
        $destinationRelative = $relative
        if ($result.ExitCode -eq 0 -and (Test-Video -Path $temp -RequireAudio $hasAudio -SourcePath $source.FullName)) {
            $encoded = Get-Item -LiteralPath $temp
            if ($encoded.Length -lt $source.Length) {
                $candidate = $encoded
                $temporary = $true
                $destinationRelative = Join-Path $relativeDirectory "$baseName.mp4"
                $script:Stats.OptimizedVideosCopied++
            } else {
                Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
                $script:Stats.OriginalsCopied++
            }
        } else {
            Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
            $script:Stats.Failures++
            $script:Stats.OriginalsCopied++
        }
        if ($files.Count -gt 1) { $script:Stats.DuplicateWinners++ }
        Copy-Winner -CandidatePath $candidate.FullName -DestinationRelative $destinationRelative -SourceKey $sourceKey -SourceLength $source.Length -TemporaryCandidate:$temporary
    }
}

if ($VerifyDestination) {
    Write-Status ""
    Write-Status "VERIFYING DESTINATION" Magenta
    foreach ($record in $script:Manifest.Values) {
        $path = Join-Path $DestinationRoot $record.DestinationRelative
        if ((Test-Path -LiteralPath $path -PathType Leaf) -and (Get-Item -LiteralPath $path).Length -eq $record.DestinationLength) {
            $script:Stats.Verified++
        } else {
            $script:Stats.VerificationFailures++
            Write-Status "VERIFY ERROR: $($record.DestinationRelative)" Red
        }
    }
    $manifestDestinations = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    foreach ($record in $script:Manifest.Values) {
        [void]$manifestDestinations.Add([string]$record.DestinationRelative)
    }
    foreach ($file in Get-ChildItem -LiteralPath $DestinationRoot -Recurse -File -ErrorAction SilentlyContinue) {
        if ($file.FullName -eq $ManifestPath) { continue }
        $relative = $file.FullName.Substring($DestinationRoot.Length).TrimStart('\')
        if (-not $manifestDestinations.Contains($relative)) {
            $script:Stats.VerificationFailures++
            Write-Status "UNMATCHED DESTINATION FILE: $relative" Red
        }
    }
}

$destinationFiles = @(Get-ChildItem -LiteralPath $DestinationRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -ne $ManifestPath })
$script:Stats.DestinationBytes = [long](($destinationFiles | Measure-Object Length -Sum).Sum)
$saved = [math]::Max([long]0, $script:Stats.SourceBytes - $script:Stats.DestinationBytes)
$percent = if ($script:Stats.SourceBytes -gt 0) { 100.0 * $saved / $script:Stats.SourceBytes } else { 0.0 }

Write-Status ""
Write-Status "COPY MODE SUMMARY" Magenta
foreach ($entry in $script:Stats.GetEnumerator()) {
    if ($entry.Key -notin @("SourceBytes","DestinationBytes")) {
        Write-Status ("{0}: {1}" -f $entry.Key, $entry.Value)
    }
}
Write-Status "Total source size: $(Format-Bytes $script:Stats.SourceBytes)"
Write-Status "Total destination size: $(Format-Bytes $script:Stats.DestinationBytes)"
Write-Status "Total storage saved: $(Format-Bytes $saved)" Green
Write-Status ("Library size reduction: {0:N2}%" -f $percent) Green
Write-Status "Manifest: $ManifestPath" DarkCyan
Write-Status "Report file: $ReportPath" DarkCyan
$script:ReportLines | Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Host "__COPY_REPORT__=$ReportPath"
exit $(if ($script:Stats.VerificationFailures -gt 0) { 2 } else { 0 })
