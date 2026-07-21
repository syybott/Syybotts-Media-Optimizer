# SYYBOTT’S Media Optimizer — Advanced Guide

*For basic setup and quick-start instructions, please read [README-SIMPLE.md](README.md) first.*

## Mode Operations
**Copy Mode Policies**: Destination behavior depends on the configured policy: Skip existing, Replace existing if smaller, or Rebuild (overwrite all).
**Modify Mode Triggers**: The original source is permanently deleted and replaced only when an operation successfully generates an output that passes all validation checks and format-specific size rules.

## Image Processing Rules
**Supported Sources**: `.jpg`, `.jpeg`, `.png`, `.bmp`, `.tiff`, `.tif`, `.heic`
**Output Format**: WebP (`.webp`)
**PNG Files**: Converted to lossless WebP. In Modify Mode, a successfully generated lossless WebP replaces the source PNG **regardless of whether the final file size is smaller**.
**Other Formats**: Converted to lossy WebP at the selected quality. The generated WebP only replaces the source if its file size in bytes is **strictly smaller** than the original.
**Failed or Larger Outputs**: If an output is equal in size, larger, invalid, or unsuccessful, the original image is preserved and the WebP is discarded.
**Larger JPEG Tagging**: If a generated WebP is larger than a source JPEG, an NTFS Alternate Data Stream (ADS) tag (`SYYBOTT.WebP.LargerAttempt`) is written to the source JPEG. Future runs read this tag and skip the file without re-converting it.
**Duplicate Base Filenames**: If a source folder contains `image.jpg` and `image.png`, the application processes both into `image.webp`. Resolution of clashing filenames relies on OS-level overwrite behavior during the final move operation.

## Video Processing Rules
**Supported Sources**: `.mp4`, `.mkv`, `.avi`, `.wmv`, `.mov`, `.webm`
**Output Format**: `.mp4` container using H.264 video (`libx264`) and AAC audio (`aac`). `ffmpeg.exe` handles encoding and `ffprobe.exe` gathers metadata.
**Validation**: Before a video is replaced, the output must pass strict checks:
  - Recognized as a valid MP4/MOV container.
  - Duration matches the source duration within a small tolerance.
  - Frame rate does not exceed the profile's maximum limit.
  - If the source contained audio, the output must contain AAC audio. (If the source was silent, the output must not unexpectedly contain audio).
**Size Requirement**: The output must be **strictly smaller** in bytes than the source. Otherwise, it is discarded.

## Processed-Video Tagging
To avoid needlessly re-transcoding optimized videos, the application embeds a marker inside the generated video's internal metadata.

**Storage**: The marker is written to the MP4 file's `comment` metadata tag using FFmpeg.
**Format**: The comment contains the application identifier (`SYYBOTT'S Video Optimizer`), Profile Name, CRF value, and an internal Profile Rank integer.
**Skip Logic**: Before encoding, the application extracts `format.tags.comment`. Higher rank integers correspond to more aggressive compression profiles (e.g., "Default" is Rank 2, "Super Light" is Rank 6). If the integer stored in the video's marker is **greater than or equal to** the currently selected optimization profile's rank, the file is skipped.
**Re-Processing**: If the user selects a higher-quality (less aggressive, lower rank) profile than previously used, the file will be processed again.
**Invalidation**: Any external editing, remuxing, or metadata removal tool that strips the `comment` tag will silently invalidate the marker. Missing or unreadable markers cause the application to assume the file is untreated.

## File Selection and Ordering
The application recursively enumerates supported files from the selected folder and its subdirectories.
The list of eligible files is sorted and processed in **case-insensitive alphabetical order** by their full file paths.
Each Test Mode execution locates the next eligible source whose outputs do not completely already exist, skipping past sources that were successfully tested in earlier runs.
Existing output sets from prior tests apply only to their specific source and do not globally block other eligible files in the folder.
A failed or cancelled test does not fulfill the output criteria, meaning the source is not treated as successfully completed.

## Process Tracking and Cleanup
**Controls**: The application locks the start and settings controls during an active run to prevent interruption. Controls are fully restored upon completion.
**Cancellation**: Gracefully aborts after the current file operation finishes or errors out, abandoning the remainder of the queue.
**Temporary Run Data**: The application uses `.part` or `.tmp` extensions for files currently being written. These are deleted automatically upon success, failure, or cancellation.
**Output Naming**: Successful optimizations retain the source's exact base filename with the new extension. Test Mode files append quality strings or profile names (e.g., `filename_90.webp` or `filename_CRF24_AAC96k.mp4`).
**Reports**: Plain text operation reports are generated and saved to the application's local `Logs` directory, following patterns like `SYYBOTT-Media-Optimizer-Report-yyyyMMdd-HHmmss.txt` or `SYYBOTT-Media-Optimizer-Copy-<Mode>-Report-<timestamp>.txt`.

## Technical Troubleshooting
**Processing interruptions**: Power loss, forced closure, storage failure, or highly corrupt source inputs can impact file handling and leave partial outputs.
**Output not smaller**: If the optimized file is not smaller, the source was already highly compressed and is therefore preserved.
**Cancelled processing**: Check the logs to see exactly which file was active when cancellation occurred.
**Previously tagged video skipped**: The video already possesses an internal marker indicating it was optimized at an equal or more aggressive profile.

## External Binaries
The application delegates its processing to external tools:
`cwebp.exe`
`ffmpeg.exe`
`ffprobe.exe`
These tools are not statically bundled inside the executable. The application features a dedicated download process that fetches official copies and places them directly beside the application executable to be used locally.
