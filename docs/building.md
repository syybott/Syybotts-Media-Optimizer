# Building and validation

## Requirements

- 64-bit Windows
- Windows PowerShell 5.1
- Internet access when the pinned PS2EXE module is not installed

## Validate

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Invoke-StaticChecks.ps1
```

The check parses every PowerShell source file and validates `version.json`.
The Pester suite covers Copy Mode path safety, minimum-savings decisions and
wiring, and compatibility with current and legacy video optimizer markers.

## Build

Run `build\Build-MediaOptimizer.cmd`, or:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\build\Build-MediaOptimizer.ps1
```

The builder reads `version.json`, validates inputs, embeds the workers, compiles
a 64-bit STA/DPI-aware executable, and writes the executable plus SHA-256 file
to `dist`.

Optional artwork:

- `assets\app.ico`
- `assets\fight-mode-mascot.png`

A build without artwork remains functional.
