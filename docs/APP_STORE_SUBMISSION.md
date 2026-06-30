# FWPlayer Remote — App Store submission guide

Checklist for shipping **FWPlayer Remote** (iPhone / iPad companion that
controls FWPlayer over the local network) to the App Store. Repo-side items are
done; the rest is portal/Xcode work.

---

## 1. What the repo already configures ✅

| Item | Where | Value |
|---|---|---|
| Bundle identifier | `project.yml` | `com.fwplayer.remote` |
| Marketing version | `project.yml` | `1.0` (`CFBundleShortVersionString`) |
| Build number | `project.yml` | `1` (`CFBundleVersion`) |
| App Store category | `project.yml` | `LSApplicationCategoryType = public.app-category.music` |
| Export compliance | `project.yml` | `ITSAppUsesNonExemptEncryption = false` (TLS only → exempt) |
| Privacy manifest | `Sources/Resources/PrivacyInfo.xcprivacy` | no tracking, no data collected, UserDefaults reason declared |
| Usage string | `project.yml` | `NSLocalNetworkUsageDescription`, `NSBonjourServices = [_fwplayer._tcp]` |
| App icon | `Sources/Resources/Assets.xcassets/AppIcon.appiconset` | 1024×1024 marketing icon present |
| Deployment target | `project.yml` | iOS 17.0 |
| Device family | `project.yml` | `1,2` (iPhone + iPad) |

> **Regenerate after pulling these changes:** `xcodegen generate`. The remote
> has **no committed `Info.plist` or `.xcodeproj`** — both are produced from
> `project.yml`, so a generate is mandatory before archiving. Confirm
> afterward that **PrivacyInfo.xcprivacy is in _Copy Bundle Resources_**.

---

## 2. Apple Developer prerequisites (one-time)

1. **Apple Developer Program membership** ($99/yr), same paid team as FWPlayer
   (Team ID `9AWEB9NYHH`).
2. **App ID** `com.fwplayer.remote` registered under
   [Identifiers](https://developer.apple.com/account/resources/identifiers/list).
   No special capabilities are required — local networking on iOS needs only
   the `NSLocalNetworkUsageDescription` + `NSBonjourServices` keys (already
   present), not an entitlement.
3. **Signing**: Automatic signing with the paid team (`CODE_SIGN_STYLE =
   Automatic`). Set `DEVELOPMENT_TEAM` in Xcode (it is intentionally blank in
   `project.yml`).

---

## 3. Create the App Store Connect record

- **Platform**: iOS.
- **Name**: `FWPlayer Remote` (have a backup name ready in case it's taken).
- **Bundle ID**: `com.fwplayer.remote`, **SKU** e.g. `fwplayer-remote-001`.
- **Category**: Music.

---

## 4. Privacy "nutrition label" (App Store Connect → App Privacy)

- **Data collection**: **No, we do not collect data from this app.** The remote
  only exchanges playback commands/state with the FWPlayer the user selects on
  their own local network.
- **Tracking**: No.

---

## 5. Build & upload

```bash
xcodegen generate            # REQUIRED — no project is committed
open FWPlayerRemote.xcodeproj
```

In Xcode: select *Any iOS Device (arm64)* → Product ▸ Archive ▸ Distribute App
▸ App Store Connect. Bump `CFBundleVersion` for each new upload.

---

## 6. Screenshots (required)

Capture the device list and a now-playing/control screen:

- **iPhone 6.9"** — required.
- **iPad 13"** — required (app supports iPad).

---

## 7. Review information

- **Sign-in**: none.
- **Notes for reviewer**: "FWPlayer Remote discovers and controls the FWPlayer
  app over the local network (Bonjour `_fwplayer._tcp`). **To review it you need
  FWPlayer running on a Mac/iPad/iPhone on the same Wi‑Fi network.** If a test
  device isn't available, please refer to the attached demo video. The app
  collects no data and requires no account."
- Consider attaching a short **demo video** (App Review often can't reproduce a
  local-network pairing flow), and grant the Local Network permission prompt
  when launching.

---

## 8. Pre-submit sanity checklist

- [ ] `xcodegen generate` run; `PrivacyInfo.xcprivacy` in Copy Bundle Resources.
- [ ] Archive validates clean (Xcode Organizer ▸ Validate App).
- [ ] App icon is square 1024², opaque, no alpha.
- [ ] Version/build incremented vs. any prior TestFlight upload.
- [ ] Privacy answers = "no data collected".
- [ ] Reviewer notes explain the local-network requirement (+ demo video).
