# Kedot 2.2.0 — Test report

[简体中文](TEST_REPORT.md) | **English**

Date: 2026-10-28. Local environment: Apple Silicon Mac, Swift 6.3.3, minimum deployment target macOS 14. Validation used native AppKit/SwiftUI, simulated Chrome extension contexts, and real loopback HTTP integration.

## Implemented

1. Group parts of the same BV video; show current part, total, and course position. Totals come from complete public page metadata and remain unknown when unavailable.
2. System, light, and dark appearance with six accent themes.
3. Manual part/time editing, protection against automatic overwrites, and resuming automatic sync.
4. Resizable windows with proportional content scaling and saved size/position.
5. Playback-event sync, background/Low Power Mode throttling, deduplication, offline backoff and coalescing, deferred disk writes, immediate save attempts on normal quit/sleep, and reduced blur in Low Power Mode.

## Passed checks

- **14 native core check groups:** authentication, malformed input, corrupt-file preservation, permissions, persistence, legacy migration, grouping, metadata validation, course-position calculations, manual protection/resume, invalid manual input, and preserving data after rejected metadata.
- **Write coalescing:** 20 updates immediately changed memory with zero disk writes; an explicit flush wrote once; repeated flush did not write again; pause triggered an immediate write. Ten real HTTP updates also deferred disk writes and persisted the latest value after about 10 seconds.
- **Extension playback logic:** no `setInterval` player polling; foreground, background, and Low Power Mode throttling; immediate pause flush even for an unchanged position; no uploads for 100 paused `timeupdate` events; old-player progress was not attributed to a newly navigated part.
- **Offline recovery and status:** 20 offline progress messages caused one network attempt, with subsequent attempts held by backoff. Important events cached the latest position; a rebuilt worker delivered and cleared the queue. Successful status updates did not write Chrome storage on every playback tick.
- **Simulated metadata bridge:** complete `pages` array length, BV matching, preserved history-method return values, and rejection of metadata for a different BV. Current live Bilibili page state has not been validated.
- **Process integration:** extension worker `fetch` → Swift HTTP service → saved `videos` and `courses`; total 60, current part 2, and elapsed time 42 seconds matched. Confirmed loopback-only binding, rejected bad authentication/JSON/non-finite or boolean progress, detected port conflicts and duplicate instances, and preserved data/token across restarts.
- **Appearance logic:** simulated system appearance changes, explicit overrides, preference persistence, and scaling bounds. The user's actual system appearance setting was not changed for testing.
- **Native rendering:** light/dark previews at 282×310, 354×430, and 520×620; programmatic checks of always-on-top, compact mode, enlargement, and the management window.
- **Actual UI interaction:** displayed P12/60; edited elapsed time to 600 seconds, displayed 10:00, and enabled manual protection; incoming automatic progress could not overwrite it; resuming automatic sync worked. Mouse resizing from 354×430 to 478×521 scaled text/controls and saved dimensions. Progress of 620 seconds survived normal quit.
- **Options page and packaging:** validation, success/error recovery, icon dimensions, manifest paths, app signature integrity, and ZIP extraction followed by signature/version/communication/persistence checks.

Core validation uses the bundled `TrackerChecks` executable. The local environment lacked XCTest; these results do not claim a successful `swift test` run.

## Verification limits

- The extension was not installed into the user's live Chrome profile. Real history, current Bilibili ads, single-page part changes, background freezing, and autoplay have not been checked end to end. MAIN-world metadata collection was tested with simulated page state; unknown totals can be entered manually.
- System appearance observation uses `NSApplication.effectiveAppearance`. Logic and explicit light/dark rendering passed; a whole-system theme switch was not performed.
- Battery life, Energy Impact, and long-running CPU performance were not measured. Efficiency claims are limited to the verified mechanisms and operation counts; no battery-saving percentage is claimed.
- The original local test did not run on physical macOS 14/15 or Intel machines and did not cover every Spaces/fullscreen/multiple-display arrangement. The delivered app is ARM64 only. Subsequent GitHub CI is distinct from physical-device UI coverage.
- The app is ad-hoc signed, without Developer ID signing or Apple notarization; Gatekeeper approval is not claimed. The data format adds `courses`; deleting old installation packages does not delete user data.

## GitHub automation

The initial public-source workflow passed compilation, native core checks, extension/options-page checks, and real HTTP integration on GitHub's `macos-15` runner. See the repository's [Actions page](https://github.com/matthewsu73/kedot/actions) for individual run results.

## Official references

- [Apple: NSApplication effectiveAppearance](https://developer.apple.com/documentation/appkit/nsapplication/effectiveappearance)
- [Chrome: Content scripts](https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts)
- [Chrome: Migrating to service workers](https://developer.chrome.com/docs/extensions/develop/migrate/to-service-workers)
