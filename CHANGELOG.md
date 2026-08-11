# Changelog

## Unreleased

## 1.0.0 - 2026-08-10

### Changed

- Made hardware-aware maximum cwebp concurrency the standard image-processing behavior
- Added a left-aligned Background mode checkbox below Activity that limits cwebp processing to two workers
- Added bounded parallel cwebp conversion to Modify Mode and Copy Mode while keeping validation, collision handling, file replacement, manifests, and reporting serialized
- Added cwebp multithreading for lossless PNG conversions
- Added physical-core detection with CIM, WMI, and logical-processor fallbacks
- Added application-speed and worker-count details to activity output and reports
- Changed active-run button colors to the application pink for clearer visual state
- Saved the last Image and Video operation modes and restored them at startup
- Reopened folder selection whenever an operation mode is confirmed, defaulting to the previously selected folder
- Made Process JPG/JPEG the default JPG/JPEG handling option
- Added independent minimum-savings controls for JPG/JPEG and video replacements
- Simplified image, video, and diagnostic helper text throughout the interface
- Removed the redundant status line below Activity and tightened the JPG/JPEG Test Batch layout
- Moved Background mode away from the JPG/JPEG Test Batch controls to clarify that it applies to application processing speed

### Release

- Promoted the Windows application from beta to the first stable 1.0.0 release
- Updated component versions to engine 1.0.32 and Copy Mode worker 1.0.4

## 1.0.0-beta.3 - 2026-07-31

### Changed

- Added independent, persisted minimum-savings thresholds for JPG/JPEG and
  videos. Both default to 5%; 0% accepts any strictly smaller valid candidate.
- Applied threshold decisions consistently to Modify Mode, Copy Mode, existing
  image pairs, duplicate image groups, reports, diagnostics, and resume keys.
- Test modes now retain valid samples regardless of savings and report whether
  each sample passes the selected threshold.
- Moved source and build scripts to stable, version-independent paths.
- Centralized product and component versions in `version.json`.
- Made optional artwork non-blocking for local and CI builds.
- Moved settings, logs, and diagnostics to the user's local application-data
  directory.
- Activated the Windows build workflow under `.github/workflows`.
- Added clean-checkout parsing, safety tests, build verification, and artifact
  checks.
- Restored skip compatibility for videos tagged by older releases as
  `SYYBOTT'S Media Optimizer`; explicit profile ranks now take precedence over
  inferred CRF ranks.
- Switched required-tool downloads to streaming HTTPS with live speed and ETA
  reporting, retaining foreground BITS as an automatic fallback
- Corrected overlapping helper text in the Video optimization panel at scaled
  display sizes

### Security

- Added exact-path confirmation, protected-directory rejection, root rejection,
  overlap checks, and reparse-point rejection for Copy Mode Rebuild.
- Added a pinned SHA-256 check for the WebP archive.
- Added unsafe ZIP-entry checks before third-party archives are extracted.

### Documentation

- Added build, recovery, contribution, and security guidance.
- Corrected encoding and obsolete documentation links.
