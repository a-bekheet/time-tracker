# Time Tracker

A local-first macOS menu bar time tracker. Requires macOS 14 or later.

## Install

Download the ZIP from the [latest GitHub release](https://github.com/a-bekheet/time-tracker/releases/latest), extract it, and move **Time Tracker.app** to Applications. The release runs on Apple silicon and Intel Macs.

To install with Homebrew, use the project's tap:

```sh
brew install --cask a-bekheet/tap/time-tracker
```

The release build is ad hoc signed and unnotarized. If macOS blocks the downloaded app, see [Apple's instructions for opening an app from an unidentified developer](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unidentified-developer-mh40616/mac). You can also build the app locally using the instructions below.

## Start using it

Open **Time Tracker.app**, then select its clock icon in the menu bar and choose **Open dashboard**. Create a project, then start it from the menu bar. Switch projects by selecting another one; use Stop when you are done. The dashboard contains reports, history, project settings, manual entry, and CSV export.

Each project can continue tracking while the Mac sleeps. With that setting off, the app ends the current session when macOS reports that it is going to sleep. The timer stops when the app quits normally. If the app or Mac is interrupted unexpectedly, an unfinished session is marked for review on the next launch. Set its end time in History to include it in reports.

Manual entries can use a time range or a daily duration. Overlapping time ranges are flagged before saving. Duration-only entries have no known start or end time. The dashboard counts both types as tracked time; overlaps that you choose to save count in full. The timesheet project name opens its history.

Data is saved locally to `~/Library/Application Support/TimeTracker/data.json`. Export CSV from the dashboard for a portable copy. The app does not import or modify the old spreadsheet. Exported interrupted entries have an empty duration until reviewed.

## Build

With the macOS Swift command-line tools installed, run `./build-app.sh` from this directory. It produces `Time Tracker.app` here. Use `./build-app.sh --universal` to include both Apple silicon and Intel builds in one app bundle.

After rebuilding, quit any running copy of Time Tracker and open the rebuilt app from this folder. macOS keeps the old interface running until the app quits. Check **Time Tracker → About Time Tracker** for the version number.

To run the core checks without Xcode or XCTest:

```sh
mkdir -p /tmp/timetracker-swift-cache
CLANG_MODULE_CACHE_PATH=/tmp/timetracker-swift-cache swiftc -parse-as-library Sources/TimeTracker/Models.swift Sources/TimeTracker/Store.swift checks/CoreChecks.swift -o /tmp/timetracker-core-checks
/tmp/timetracker-core-checks
```
