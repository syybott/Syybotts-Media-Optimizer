# Building and validation

## Requirements

- 64-bit Windows
- Windows PowerShell 5.1
- Internet access when the pinned PS2EXE module is not installed
- Pester 5.6.1 for the complete automated test suite

## Validate

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Invoke-StaticChecks.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Invoke-SafetyChecks.ps1

Invoke-Pester -Path .\tests -CI
```

The checks parse every PowerShell source file, validate `version.json`, exercise
destructive-path safeguards, and run the Pester suite. The suite covers Copy
Mode path safety, minimum-savings decisions and wiring, scaled Video
optimization layout, and compatibility with current and legacy video optimizer
markers

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

A build without artwork remains functional

## Release checklist

1. Update `version.json` and `CHANGELOG.md`
2. Run the static, safety, and Pester checks
3. Build the EXE and verify its `.sha256` sidecar
4. Merge the validated release branch into `main`
5. Package the EXE and sidecar together at the root of a versioned ZIP
6. Tag the merged commit and attach the ZIP to the GitHub release
