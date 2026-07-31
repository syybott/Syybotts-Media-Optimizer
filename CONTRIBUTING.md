# Contributing

Before submitting a change:

1. Run `tests\Invoke-StaticChecks.ps1`
2. Run `tests\Invoke-SafetyChecks.ps1`
3. Run the Pester 5.6.1 suite under `tests`
4. Build from a clean checkout
5. Exercise all four modes with disposable fixtures
6. Confirm no tools, generated media, logs, settings, or diagnostics are added

Changes to replacement, rollback, deletion, path resolution, extraction, or
checksum validation require corresponding safety tests.
