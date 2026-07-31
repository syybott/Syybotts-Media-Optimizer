# Changelog

## Unreleased

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
