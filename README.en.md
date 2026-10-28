# 课点 · Kedot

[简体中文](README.md) | **English**

Keep your course progress on your Mac desktop, ready for your next study session.

![Kedot desktop widget in dark mode](docs/widget-dark.png)

Kedot is a native SwiftUI + AppKit floating desktop widget with a local sync service. It tracks Bilibili course playback through a Chrome extension. It supports Apple Silicon, macOS 14+, and Chrome 111+. Python, Node.js, and Xcode are not required for everyday use of a built app. This is a standalone floating window, not a WidgetKit system widget. The current app and extension interfaces are in Chinese; this repository provides Chinese and English documentation.

## Features

### 1. Course progress across video parts

- Groups parts of the same Bilibili BV video into one course. Shows the current part and total, such as **P12 / 60 parts**, course position, elapsed time, and progress within the current part.
- Reads the full part list from the video's public `__INITIAL_STATE__.videoData.pages` metadata. It does not infer the total from the highest part found in browser history. If unavailable, the total remains unknown and can be entered manually.
- Course position is `(current part − 1 + current part playback fraction) / total parts`. It describes your position, not proof that every preceding part was watched. It is not weighted by the duration of each part.
- Collections spanning different BV identifiers are not merged. Existing selected parts of the same BV are grouped while individual playback records are retained.

### 2. System, light, and dark appearance

- Use the widget's `…` → **深浅色模式** (Appearance), or **管理课程** (Manage courses) → **外观模式** (Appearance mode), to select system, light, or dark mode.
- Six accent themes support both appearances. Accent and appearance preferences are saved separately. System mode observes application appearance changes without periodic polling.

### 3. Manual progress editing

- Click the sliders icon on a course card, or **调整进度** (Adjust progress) in the management window.
- Edit the current part, total parts, duration, and elapsed seconds, or use the progress slider. If only the part number is known, duration and elapsed time can both be zero.
- Saving enables **手动记录** (Manual record), protecting that course from automatic overwrites by an active browser player.
- Choose **恢复自动** (Resume automatic) in the management window, or right-click a card and select **恢复自动同步** (Resume automatic sync), to follow playback again.
- Editing changes the desktop record only; it does not seek the browser player. Total parts must be at least the current part, and elapsed time cannot exceed duration.

### 4. Resizable window and controls

- Drag the bottom-right resize handle or window edge. Text, controls, and spacing scale proportionally; additional courses scroll.
- Window sizes range from 282×310 to 850×1050 points. Width and height can change independently while content maintains its proportions.
- Drag the top-left icon/title area to move the widget. Size, position, always-on-top, and compact preferences are saved.

### 5. Responsive sync with fewer background operations

- Playback events drive updates; there is no per-second player polling. During playback, uploads are throttled to about every 2 seconds in the foreground and 10 seconds in the background. Low Power Mode increases these intervals to about 5 and 15 seconds.
- Pause, playback end, and completed seeks attempt immediate sync and saving. Paused `timeupdate` events do not continuously upload; duplicate positions are skipped.
- The desktop UI updates on receipt. Continuous playback updates are coalesced to disk about every 10 seconds; pause, manual edits, normal quit, and system sleep trigger immediate save attempts. Low Power Mode disables background blur, and hidden windows reduce list rebuilding.
- Offline retries use exponential backoff from 5 to 60 seconds, coalescing up to 50 latest records. Important events are cached immediately. Recovery sends the latest values instead of replaying every stale update.
- Full history scans occur initially, on request, or at roughly 30-minute intervals. History events discover new visits, with a five-minute fallback check.
- These mechanisms reduce wakeups, transfers, and writes. Battery-life gains have not been measured.

## Install or upgrade

When starting from this GitHub repository, first build `BiliWidget.app` using the development instructions below. A source ZIP is not a runnable app.

1. Quit the old version. Move the built `BiliWidget.app` into Applications or another permanent location, then open it.
2. In **管理课程** (Manage courses), choose **显示扩展文件夹** (Show extension folder). Open `chrome://extensions`, enable Developer mode, and load the `extension` folder. Copy it to a permanent location first, such as `Documents/BiliWidgetExtension`, and replace files there when upgrading.
3. For an existing installation, replace the contents of the folder Chrome already uses, then click Reload. Pairing settings are retained if the extension ID stays the same. Pair again if it changes, and enable only one copy.
4. Click **复制配对码** (Copy pairing code) in the desktop app. Paste it into the extension's options page and select **保存并同步历史** (Save and sync history). **Refresh existing Bilibili tabs** to activate the updated playback and metadata scripts.
5. Select courses in the management window. Play a video to check the part number, total, and elapsed time. Drag the bottom-right handle to try resizing.

The supplied ARM64 app uses ad-hoc signing and has no Developer ID signature or Apple notarization. If macOS blocks it, follow the system's instructions under System Settings → Privacy & Security to allow this app. Do not disable system security features.

## Data and permissions

- Data stays in `~/.bili_course_tracker/data.json` and `token.txt`, with compatibility for older video records. The `courses` data stores totals, current part, selection, and manual protection for each BV video.
- Removing old app packages does not remove learning records, pairing codes, or preferences. Back up the data directory before upgrading.
- The service listens only on `127.0.0.1:8765`. It validates the bearer pairing code, Host/Origin, request bodies, and numeric values. Chrome permissions are `history`, `alarms`, `storage`, and the Bilibili/local host permissions declared in the manifest.
- The main-world script reads public part metadata and passes it to the isolated script. It cannot access the pairing code or Chrome APIs. The local service validates incoming page data again.
- The app does not read Chrome cookies, Bilibili passwords, or account-level cloud history, and does not upload records to a cloud service. Corrupt data produces an error and is preserved.

## Limitations and troubleshooting

- History import covers at most 500 recent matching entries and cannot recover playback times from before extension installation. BV videos and their parts are supported; livestreams, anime episodes, and collections spanning multiple BV identifiers are outside this version's scope.
- Bilibili page structure, player events, ads, or single-page navigation may affect detection. Enter totals manually when metadata is unavailable. Full live Chrome/Bilibili acceptance testing remains outstanding.
- Background throttling, frozen tabs, and system sleep can delay sync. Closing or force-quitting Chrome may lose the last unsent seconds. Force-quitting the app or losing power may lose up to roughly 10 seconds of coalesced playback updates.
- During offline backoff, cache writes are normally coalesced every 15 seconds; important events are cached immediately. A forced browser exit between writes may lose recent changes. With no new playback events, reconnection may wait for the five-minute fallback; retry manually from the extension options page if needed.
- If multiple tabs play the same course, the latest received automatic update wins. Manual protection prevents those updates from replacing your chosen position.
- For HTTP 401, copy the pairing code again. For connection failures, check that the app is running, another instance has exited, and port 8765 is available. Refresh metadata or correct the total manually if the current part exceeds the known total.
- Spaces and fullscreen auxiliary-window behavior are configured, but not every macOS version, display arrangement, or scaling combination has been tested.

## Build and test

This repository contains the complete source. Install Xcode Command Line Tools with Swift 5.9 or newer. There are no external Swift dependencies. Node.js 18+ and Python 3 are needed only for the tests shown below; icon regeneration additionally uses Pillow.

```sh
swift build
swift run TrackerChecks
node Tests/test_extension.cjs
node Tests/test_options.cjs
python3 Tests/integration.py
python3 Tests/features.py
SIGNING_MODE=adhoc bash Scripts/package_app.sh release
```

The packaging command creates `BiliWidget.app` in the repository root. Tests use temporary course data and isolated preference domains. Environment overrides are `BILI_TRACKER_DATA_DIR`, `BILI_TRACKER_PORT`, and `BILI_TRACKER_PREFERENCES_SUITE`.

Diagnostic options include `--headless` and `--preview --theme mint --appearance dark --size 520x620 --snapshot /absolute/path/preview.png`. Preview courses are demo data and do not overwrite real records.

## Naming and compatibility

The project is called 课点 (Kedot). The app filename remains `BiliWidget.app` for compatibility with existing installations, along with its application identifier and data directory. This is an independent project, unaffiliated with Bilibili.

## License and contributions

Released under the [MIT license](LICENSE). See [THIRD_PARTY.md](THIRD_PARTY.md) for third-party notices. Issues and pull requests are welcome. Remove pairing codes and personal browsing records from bug reports, and run the core and extension checks before contributing.

## Test reports

[中文测试报告](TEST_REPORT.md) · [English test report](TEST_REPORT.en.md)
