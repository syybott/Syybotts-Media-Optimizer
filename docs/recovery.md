# Recovery guidance

## Modify Mode interruption

Do not rerun optimization immediately after an interruption. Review the latest
report under `%LOCALAPPDATA%\SYYBOTT\Media Optimizer\Logs`.

If a backup or temporary file remains beside an affected source, copy it to a
separate safe location before attempting restoration. When both an output and a
backup exist, retain both until they have been validated independently.

## Copy Mode interruption

Copy Mode does not alter the source library. A forced termination can leave
`.copy-part` files in the destination. Preserve the report, remove only
confirmed partial files, and rerun with Skip or Replace-if-smaller.

## Rebuild

Rebuild permanently erases the confirmed destination. Recovery depends on
external backups or filesystem recovery; the application has no undelete
facility.
