# Contributing

Before submitting a change:

1. Run `tests\Invoke-StaticChecks.ps1`.
2. Run the Pester tests under `tests`.
3. Build from a clean checkout.
4. Exercise all four modes with disposable fixtures.
5. Confirm no tools, generated media, logs, settings, or diagnostics are added.

Changes to replacement, rollback, deletion, path resolution, extraction, or
checksum validation require corresponding safety tests.
