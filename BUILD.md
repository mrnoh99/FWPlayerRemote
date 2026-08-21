# Building FWPlayer Remote

Once the Xcode project has been committed (see the one-time step below), you can
clone and build with **no extra tooling**:

```bash
git clone https://github.com/mrnoh99/FWPlayerRemote.git
cd FWPlayerRemote
open FWPlayerRemote.xcodeproj
```

In Xcode: pick an iPhone/iPad or a Simulator, set your signing team on the
target if prompted, and **Run**.

---

## One-time: commit the Xcode project (do this on a Mac that has xcodegen)

The project (and its `Support/Info.plist`) are generated from `project.yml` by
[XcodeGen](https://github.com/yonaskolb/XcodeGen). Generate **once** and commit;
after that nobody needs xcodegen to build.

```bash
brew install xcodegen        # if you don't have it
cd FWPlayerRemote
xcodegen generate            # creates FWPlayerRemote.xcodeproj + Support/Info.plist
git add -A
git commit -m "Commit generated Xcode project (clone-and-build)"
git push origin main
```

`.gitignore` is already set up to track the project and `Support/Info.plist`
while ignoring user-specific state.

---

## When do I need xcodegen again?

Only when the **project structure** changes: adding/removing a source file, or
changing Info.plist keys / entitlements / build settings in `project.yml`. Then
re-run `xcodegen generate` and commit the result. Everyday code edits need no
regeneration.

## Version / build number

Set `MARKETING_VERSION` (CFBundleShortVersionString) and
`CURRENT_PROJECT_VERSION` (CFBundleVersion / build) in `project.yml`. The
Info.plist references these via `$(…)`, so bump, regenerate, and rebuild.

> **Protocol note:** the remote and FWPlayer share a wire protocol
> (`Sources/Protocol/RemoteProtocol.swift`, kept byte-identical in both repos).
> Both apps must be built from matching versions to talk to each other.
