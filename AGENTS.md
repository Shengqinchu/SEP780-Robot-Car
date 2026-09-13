# Project instructions

- Read README.md and DEVLOG.md before making changes.
- Keep vendor/freenove byte-identical to vendor/freenove-manifest.json. Put project changes in firmware/ and document their origin.
- Pin tool and library versions. Do not upgrade the bundled legacy RF24 or IRremote libraries casually.
- Record actual problems, fixes and verification in DEVLOG.md on every substantial development turn.
- Distinguish implemented, compiled, flashed and hardware-tested. Never infer successful motion or sensor operation from compilation.
- Do not flash a board or actuate hardware automatically. Require an explicitly confirmed physical setup and serial port from the user before upload.
- Do not upload course files, unredacted personal images, credentials, local paths in raw logs, or binaries to GitHub.
- Keep this repository independent of AutoRC; reusing any code requires provenance and a documented hardware adaptation.
- Run tests/Check-Repository.ps1 and appropriate scripts/Build.ps1 checks before committing. A full build is scripts/Build.ps1 -All.
