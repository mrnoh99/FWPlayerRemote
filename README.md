# FWPlayerRemote

A companion **remote control** for [FWPlayer](https://github.com/mrnoh99/FWPlayer),
the lossless FLAC/WAV player. FWPlayerRemote is a universal **iPhone + iPad** app
that discovers FWPlayer instances on your local network and drives their playback
— play/pause, next/previous, seek, and tap-to-play any track in the queue.

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
  state, elapsed/duration) pushed on every change.
- **Remote → Player:** `RemoteCommand` transport messages (`togglePlayPause`,
  `next`, `previous`, `seek`, `playIndex`, …).

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
project.yml                 XcodeGen project definition (single iOS app target)
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

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
so it isn't committed (see `.gitignore`).

```bash
brew install xcodegen          # one-time
xcodegen generate              # creates FWPlayerRemote.xcodeproj
open FWPlayerRemote.xcodeproj
```

Select the **FWPlayerRemote** scheme and run on an iPhone or iPad (simulator or
device). Set your signing team in Xcode (or `DEVELOPMENT_TEAM` in `project.yml`)
before running on a device. Make sure FWPlayer is open on the device you want to
control and connected to the same network.
