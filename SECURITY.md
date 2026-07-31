# Security

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub's security-advisory feature.
Do not include private media, full personal paths, or diagnostic archives in a
public issue.

## Destructive operations

Modify Mode replaces source files only after validating a generated candidate.
Copy Mode's Rebuild policy permanently removes the selected destination's
contents. Back up important media and review the resolved paths shown by the
application before approving either operation.

## External tools

The application downloads FFmpeg, ffprobe, and cwebp when they are unavailable.
Downloaded archives must be obtained over HTTPS and validated before binaries are
installed. Tool versions and download sources are recorded in diagnostic output.
