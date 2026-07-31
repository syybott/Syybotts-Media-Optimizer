# SYYBOTT'S Media Optimizer - Advanced Guide

For setup and quick-start instructions, read [README.md](README.md).

## Image processing

Supported sources are `.jpg`, `.jpeg`, `.png`, `.bmp`, `.tiff`, `.tif`, and
`.heic`. Outputs use WebP.

- PNG sources use lossless WebP. In Modify Mode, a validated lossless result
  replaces the PNG even when the WebP is larger
- Other supported images use lossy WebP at the selected quality. JPG/JPEG
  candidates replace the source only when valid, strictly smaller, and at or
  above the configured minimum savings (5% by default)
- A larger JPEG attempt may be recorded in the NTFS alternate data stream
  `SYYBOTT.WebP.LargerAttempt` so later runs can skip the same work
- Image metadata, color profiles, and filesystem timestamps are not guaranteed
  to survive conversion. Preserve originals when those properties matter

Sources such as `image.jpg` and `image.png` compete for the same `image.webp`
name. Review reports carefully until deterministic collision naming is added.

## Video processing

Supported sources are `.mp4`, `.mkv`, `.avi`, `.wmv`, `.mov`, and `.webm`.
Outputs use an MP4 container, H.264 video, and AAC audio.

Before replacement, the output must be a recognized container, satisfy duration
and frame-rate rules, preserve the expected presence of audio, be strictly
smaller than the source, and meet the configured minimum savings (5% by
default).

Generated videos use a comment metadata marker containing the application,
profile, CRF, and profile rank. Editing or remuxing may remove that marker.
Multiple audio tracks, subtitles, attachments, rotation, and color metadata are
not guaranteed to be retained.

Videos carrying a compatible current or legacy optimizer marker are skipped
when their recorded profile rank is already equal to or better than the
selected profile. Explicit marker ranks take precedence over ranks inferred
from older CRF-only markers

## Selection and test outputs

Supported files are enumerated recursively in case-insensitive path order.
Known test-output folders and reparse-point directories are excluded. A
successful Test Mode run advances to the next source whose expected outputs do
not already exist. Valid test samples are retained even when larger than the
source or below the selected threshold; the output reports a Pass or Fail
decision with the actual and required savings percentages.

JPEG and video thresholds are separate, accept values from 0% through 100%,
and are persisted in the application settings. A value of 0% still requires a
candidate to be strictly smaller in Copy and Modify modes.

## Copy Mode

- **Skip** preserves existing destination files
- **Replace if smaller** replaces only when the new candidate is smaller
- **Rebuild** permanently removes the confirmed destination contents first

Converted JPEG and video candidates also have to meet their respective
minimum-savings thresholds. Otherwise Copy Mode copies the original.

The source and destination cannot equal or contain one another. Rebuild also
rejects filesystem roots, protected Windows directories, and a confirmation
that does not exactly match the resolved destination.

## Modify Mode transaction

The candidate is created and validated before source replacement. The source is
moved to a backup, the candidate is installed, and the backup is deleted only
after success. If installation fails, the application attempts to restore the
backup and records critical rollback failures.

Forced termination, power loss, storage failure, or corrupt input can still
leave temporary or backup files. See [Recovery guidance](docs/recovery.md).

## State, reports, and tools

Settings and reports are stored under:

```text
%LOCALAPPDATA%\SYYBOTT\Media Optimizer
```

Reports use names such as
`SYYBOTT-Media-Optimizer-Report-yyyyMMdd-HHmmss.txt`.

The application downloads `cwebp.exe`, `ffmpeg.exe`, and `ffprobe.exe` when
needed. Streaming HTTPS is used first, with live size, speed, and ETA reporting;
foreground BITS is retained as an automatic fallback. The pinned WebP archive
and distributor-published FFmpeg archive are verified with SHA-256 before safe
extraction and atomic installation
