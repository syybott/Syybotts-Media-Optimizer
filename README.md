## Download

The current Windows release is
[v1.0.0-beta.4](https://github.com/syybott/Syybotts-Media-Optimizer/releases/tag/v1.0.0-beta.4).
The application is portable and does not require a separate installer. The ZIP
contains the EXE and its SHA-256 file at the archive root

- [Download the Windows ZIP package](https://github.com/syybott/Syybotts-Media-Optimizer/releases/download/v1.0.0-beta.3/SYYBOTTS-Media-Optimizer-1.0.0-beta.3.zip)

On first use, select **Download Tools** to install verified copies of cwebp,
FFmpeg, and ffprobe beside the application. Tool downloads use streaming HTTPS
with live size, speed, and ETA reporting, with foreground BITS available as an
automatic fallback

## Quick start

1. Download the ZIP package
2. Use **Extract All** so Windows creates the application folder
3. Run the EXE and choose the media library folder
4. Select **Download Tools** if the required tools are not already available
5. Use a Test mode before processing a full library

## Modes

- **Copy Mode** writes optimized media to a separate destination and leaves the
  source library unchanged
- **Modify Mode** validates an optimized candidate and then replaces the source
  through a backup-and-rollback transaction
- **Image Test** generates sample image outputs without replacing the source
- **Video Test** generates sample video outputs without replacing the source

JPG/JPEG and video processing each have an independent minimum-savings setting.
Both default to 5%. A production candidate must be valid, strictly smaller, and
meet the selected percentage before it can replace or be copied instead of the
original. Setting a threshold to 0% restores the previous
"any strictly smaller candidate" behavior. Test modes always retain valid
samples and label whether each sample passes the threshold.

## Safety warning

Modify Mode permanently replaces source files after successful validation.
Copy Mode's Rebuild policy permanently removes everything inside the confirmed
destination before recreating it. Keep an independent backup of important media
and use the test modes before processing a library.

The Rebuild worker rejects filesystem roots, protected operating-system
directories, source/destination overlap, and any destination that does not
exactly match the path confirmed by the GUI.

## Running from source

Requirements:

- 64-bit Windows
- Windows PowerShell 5.1

Run `src\MediaOptimizer.Gui.ps1`. The application can download its pinned WebP
tools and FFmpeg dependencies when they are not already beside the application.
Both archives are verified with SHA-256 before extraction and atomic
installation

User settings and logs are stored under:

```text
%LOCALAPPDATA%\SYYBOTT\Media Optimizer
```

## Building

Run `build\Build-MediaOptimizer.cmd`. The build reads all version information
from `version.json`, embeds the engine and Copy Mode worker, creates a SHA-256
file, and writes artifacts to `dist`.

Custom artwork is optional:

```text
assets\app.ico
assets\fight-mode-mascot.png
```

Without these assets, the executable uses the default PS2EXE icon and Fight
Mode uses its text-only presentation. See [Building](docs/building.md) for the
full process.

## Documentation

- [Advanced behavior](README-ADVANCED.md)
- [Building and validation](docs/building.md)
- [Recovery guidance](docs/recovery.md)
- [Security policy](SECURITY.md)

## License

See [LICENSE](LICENSE).
