# Building FWPlayer Remote

The Xcode project is committed, so a fresh clone (or a `git pull`) builds with
**no extra tooling**:

```bash
git clone https://github.com/mrnoh99/FWPlayerRemote.git
cd FWPlayerRemote
open FWPlayerRemote.xcodeproj
```

In Xcode: pick an iPhone/iPad or a Simulator, set your signing team on the
target if prompted, and **Run**.

## Adding or removing files

`FWPlayerRemote.xcodeproj` is the project the app is built from, and it is edited
directly. Add a new file in Xcode (**File → Add Files to "FWPlayerRemote"…**,
target ticked) and commit the changed `project.pbxproj` with it. CI builds the
committed project, so a file that was left out shows up as a red build.

`project.yml` is kept only as a readable summary of the settings. **Don't run
`xcodegen generate`**: the committed project has changes that aren't in
`project.yml` (e.g. the Korean localization region), and regenerating would drop
them.

## Version / build number

`scripts/bump-build.sh` bumps the build number in `project.yml` **and** the
committed Xcode project in one step (no xcodegen needed): `scripts/bump-build.sh`
for +1, or `scripts/bump-build.sh 12` to set it. The details below are what it
edits.

Set `MARKETING_VERSION` (CFBundleShortVersionString) and
`CURRENT_PROJECT_VERSION` (CFBundleVersion / build) in `project.yml`. The
Info.plist references these via `$(…)`; `scripts/bump-build.sh` edits both.

> **Protocol note:** the remote and FWPlayer share a wire protocol
> (`Sources/Protocol/RemoteProtocol.swift`, kept byte-identical in both repos).
> Both apps must be built from matching versions to talk to each other.
