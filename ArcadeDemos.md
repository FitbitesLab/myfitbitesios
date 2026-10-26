# MyFitbites arcade

My Arcade offers **Too Beat Them All (Demo)** and **Puzzle**. The temporary Tiel Adventure preview was removed on October 21, 2026. The official Tiel demo will be integrated separately later.

- Too opens its Press Start screen and runs stage 1 with three waves. The existing stage cap, credit display, life charging, replay, and return controls remain.
- Puzzle retains its existing gameplay and daily reward integration.
- Too requests landscape while presented and restores portrait on leaving. Scene teardown pauses rendering and clears input; title audio stops when leaving.
- Tiel’s picker entry, details, presentation route, completion callback, debug launch route, and platformer source/resources are excluded. Its picker icon is preserved outside the app in `Archive/TielPreview`.

## Dependency ownership

`ArcadeShared` pins only the dependencies needed by Too: 16 Swift files and 52 resources (approximately 37 MiB of resources). MyFitbites no longer builds against a moving sibling game checkout. The standalone Tiel project is unchanged.

`ArcadeDemoManifest.json` records membership, checksums, provenance, and the four adapted host/input files. Shared audio helpers retain their existing `TielSound…` names, and Too’s jump control retains its existing silhouette asset; these do not include the Tiel platformer. Do not automatically sync this snapshot with the standalone game. A future update must deliberately update the manifest, Xcode membership, and checksums and repeat validation.

The earlier break was caused by live Xcode references into the sibling game: 29 files had moved into its retired assets, and newer source dependencies had not been added to MyFitbites.

## Release identity

- Bundle ID: `vn.com.fitbites.MyFitbites` (unchanged).
- Organization: FITBITES COMPANY LIMITED, team `9V3UZFAA66`.
- The explicit App ID is registered under that organization. Both Debug and Release use this team.
- Do not switch back to Personal Team `CN4547Z998` or create a new Personal Team provisioning profile. The migration depends on leaving the expired development identity behind.
- Version/build remain `0.1` / `1`. App Store Connect setup and a signed distribution archive/upload are separate steps.

## Validation

Run `python3 Scripts/validate_arcade.py` from this repository to validate dependency hashes, Xcode membership, removed preview routes, game lineup, and release identity without building.

Compile checks must use `CODE_SIGNING_ALLOWED=NO` while preparing the release, without `-allowProvisioningUpdates`. For example:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project MyFitbites.xcodeproj -scheme MyFitbites -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/myfitbites-validation CODE_SIGNING_ALLOWED=NO build
```

Use `-configuration Release -sdk iphoneos -destination 'generic/platform=iOS'` and a separate derived-data directory for an unsigned device compile check. These compile checks do not produce a signed TestFlight archive and must not install a development app on the physical iPhone.

Debug-only launch arguments: `--arcade-preview` opens the picker; `--arcade-too-preview` opens Too’s title; adding `--arcade-demo-smoke` checks landscape orientation, scene startup, the stage cap, and scene release after return to title. Results are written to Documents/too-demo-smoke.json. These routes are excluded from Release builds.

## Local trials and TestFlight milestones

Use the simulator for everyday changes. Local source edits and simulator runs do not update TestFlight. Keep organization team `9V3UZFAA66`; the earlier Personal Team expiry was a one-time migration issue, not a waiting period required between releases.

A development install on an iPhone using the same Bundle ID can replace its TestFlight app. Use a separate development Bundle ID if both copies need to coexist; no separate identifier has been configured here.

For a selected milestone, increment `CURRENT_PROJECT_VERSION` to an unused build number, archive Release for a generic iOS device, and upload through App Store Connect with automatic organization signing. An upload is an explicit release action, never part of the local build commands. Version 0.1 build 1 is the first upload prepared on October 21, 2026.

App Store Connect record: [MyFitbites](https://appstoreconnect.apple.com/apps/6825317229/testflight), app ID `6825317229`, SKU `myfitbites-ios`. Uploading to TestFlight does not submit the app for public App Store release.

The export-compliance flag is `ITSAppUsesNonExemptEncryption = NO`: this version uses OS-provided networking and a SHA-256 image-cache filename hash, with no app-implemented non-exempt encryption. Reassess this declaration if encryption dependencies change.

To retire an old TestFlight version, expire its build after the replacement is available. Apple retains build history; do not remove the production App ID, revoke shared certificates, or recreate the app record to tidy the list. No older MyFitbites TestFlight build existed when this app record was created.
