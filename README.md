# FWPlayerRemote

A companion **remote control** for [FWPlayer](https://github.com/mrnoh99/FWPlayer),
the lossless FLAC/WAV player. FWPlayerRemote is a universal **iPhone + iPad** app
that discovers FWPlayer instances on your local network and drives their playback
— play/pause, next/previous, seek, and tap-to-play any track in the queue.

You can also **build the player's queue from the remote**: tap ＋ to browse the
player's sources (on-device folder, added folders, SMB shares) and playlists,
then play a folder/playlist as a new queue or add individual tracks to the
current one.

Playlists can be managed from the remote too: **New Playlist…** in the Library
(or from any track's *Add to Playlist* menu, which creates it with that track),
swipe to rename or delete, and add or remove tracks. **Favorites** and **Played**
(every track the player has played) are built in and can't be renamed or deleted.

If the player runs a different protocol version than this app, a notice at the top
explains that some features may not work until both are updated.

It covers both of the intended scenarios with a single app:

- **Control the Mac's FWPlayer** from an iPhone or iPad.
- **Control an iPad's FWPlayer** from an iPhone.

FWPlayerRemote simply connects to whichever FWPlayer it finds advertised on the
network, so the controller device and the player device are interchangeable.

## How it works

FWPlayer advertises a Bonjour service (`_fwplayer._tcp`) and hosts a small
TCP control endpoint (see `RemoteControlServer` in the FWPlayer project).
FWPlayerRemote browses for that service, connects, and exchanges
length‑prefixed JSON messages:

- **Player → Remote:** a `PlaybackState` snapshot (queue, current track, play
  state, elapsed/duration) pushed on every change, plus `RemoteLibrary` and
  `RemoteListing` replies when the remote browses.
- **Remote → Player:** `RemoteCommand` messages — transport (`togglePlayPause`,
  `next`, `previous`, `seek`, `playIndex`) and queue construction
  (`requestLibrary`, `browse`, `setQueue`, `enqueue`).

The wire types live in `Sources/Protocol/RemoteProtocol.swift` and the framing
in `Sources/Protocol/RemoteLink.swift`. **These two files are identical to the
copies in the FWPlayer repository** — if you change one side, copy the change to
the other so the protocol stays in sync.

## Requirements

| Target        | Minimum OS |
|---------------|------------|
| iPhone / iPad | iOS 17.0   |

The controller and the FWPlayer being controlled must be on the **same Wi‑Fi /
local network**. On first launch iOS will ask for **Local Network** permission —
allow it so discovery works.

## Project layout

```
scripts/bump-build.sh       Bumps the build number in project.yml and the Xcode project
project.yml                 Settings summary (XcodeGen format; not used to build)
Support/
  FWPlayerRemote.entitlements  Network client entitlement
Sources/
  App/                      App entry point
  Protocol/                 Shared wire protocol + length-prefixed framing
  Net/                      Bonjour browser + per-player connection session
  Views/                    Device list + remote control UI
  Resources/                Assets.xcassets (app icon + accent color)
```

## Building

The generated Xcode project (`FWPlayerRemote.xcodeproj`) is committed, so you can clone
and build with no extra tooling (see [BUILD.md](BUILD.md)):

```bash
open FWPlayerRemote.xcodeproj
```

The committed Xcode project is what the app is built from; add new files to it in
Xcode and commit `project.pbxproj`. `project.yml` is only a summary of the
settings — don't regenerate the project from it (see [BUILD.md](BUILD.md)).

Select the **FWPlayerRemote** scheme and run on an iPhone or iPad (simulator or
device). Set your signing team in Xcode before running on a device. Make sure FWPlayer is open on the device you want to
control and connected to the same network.
