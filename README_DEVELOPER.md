# ArgusDesk for macOS Developer Guide

## Technology

ArgusDesk is a native macOS Swift Package Manager executable targeting macOS 14
or later. It uses SwiftUI for views and AppKit for application lifecycle,
Preferences, and menu bar integration. The project currently
has no third-party dependencies.

## Architecture

The application is organized into three main areas:

- `App`: application lifecycle and AppKit window/menu controllers.
- `Core`: configuration, models, monitoring services, severity evaluation,
  preferences, and notifications.
- `UI`: SwiftUI views for the main window and dashboard.

The main window is managed by SwiftUI's `WindowGroup` scene, which provides a
standard macOS application window with title bar, traffic lights, and Dock
presence. The menu bar status item provides a compact health summary and quick
access to the main window.

Monitoring and parsing remain separate from UI rendering. Local and remote
refresh loops run independently, and overlapping remote refreshes are skipped per SSH connection.

## Project Structure

```text
Sources/ArgusDesk/
  App/
    AppDelegate.swift
    MenuBarController.swift
    PreferencesWindowController.swift
  Core/
    AppVersion.swift
    Models/
      AppConfig.swift
      DashboardViewModel.swift
      Severity.swift
    Services/
      CommandRunner.swift
      ConfigLoader.swift
      HTTPChecker.swift
      LocalMonitor.swift
      NotificationController.swift
      PingChecker.swift
      PreferencesStore.swift
      RemoteMonitor.swift
      SeverityEngine.swift
  UI/
    ContentView.swift
    LocalStatusView.swift
    MetricRow.swift
    ServerListView.swift
    StatusBadge.swift
  main.swift
```

## Window Management

The main window uses SwiftUI's `WindowGroup` scene, which creates a standard
macOS application window. This replaces the previous overlay panel approach
(via `OverlayWindowController`). The window appears in the Dock, App Switcher,
and Alt-Tab with full standard chrome (title bar, minimize, maximize, close).

The `MenuBarExtra` status icon remains as a secondary entry point. Clicking
"Show ArgusDesk" in the status menu activates the app and brings the main
window to the foreground via `NSApp.activate(ignoringOtherApps: true)`.

The dashboard uses an opaque black background. Preferences offers a saved
vertical or horizontal server layout. Vertical content is 380 points wide and
at least 820 points high; horizontal content uses 360-point columns, 18-point
gaps, 24-point outer padding, and at least 420 points of height. Heights grow
with the enabled rows and GPU process inventory. Four columns use 1518 points.
Very large inventories can exceed the available screen and need further layout
work. Disk and memory use separate rows, each including a secondary reading.
Each heading shows SSH connectivity as a dot, plus colored ping and HTTP
results. These checks remain part of overall health evaluation even though
they are omitted from the metric rows. The menu bar retains overall health.
An observed root view subscribes to the delegate's published dashboard so
completed refreshes appear in the window.

`enabled_checks` gates collection and presentation. NVIDIA monitoring is opt-in
through `gpu`. `NVIDIAMetrics` parses GPU UUID/index mappings, compute process
inventory, and a one-sample `pmon` report, merging records by GPU and PID.
Per-process SM utilization is separate from VRAM allocation; unsupported driver
readings remain `n/a`. Memory reported by NVIDIA in MiB is displayed in GiB.
GPU utilization and VRAM occupancy use separate persisted warning/critical
thresholds. Raw numeric readings are preserved through severity evaluation;
missing utilization is not inferred from VRAM text.
Run `swift test` for parser and disabled-check regression coverage.

## Configuration Loading

`ConfigLoader` loads local `servers.json`. The committed `servers.example.json`
is documentation only and is never treated as live monitoring configuration.
Private server configuration must remain uncommitted. Public examples must use
placeholder hosts and usernames.

## Per-server Refresh

`ServerRefreshSchedule` uses monotonic uptime with a deadline and in-flight guard
per SSH connection (`user@host:port`). A one-second timer dispatches due servers;
results replace only the corresponding card, so slow connections do not hold
up faster ones. Deadlines advance from the start of a refresh; overdue work is
not queued or replayed in a burst. Manual Refresh checks all idle connections.

`refresh_seconds` is optional on each server. Missing, null, or blank values use
the global Settings value; invalid or nonpositive intervals are rejected.
Settings saves just these fields atomically, preserving other JSON content.
Each server can also have an optional `label`; missing/blank labels display its
host. Connection identity remains separate from the friendly name. The optional top-level
`local_label` names the local Mac, with hostname fallback and a Settings editor.

## Remote Monitoring

Each server refresh uses:

- one local `/sbin/ping` check
- one optional local `/usr/bin/curl` check
- one key-only `/usr/bin/ssh` command for internal server metrics

External commands run through `CommandRunner`, which captures standard output
and error, enforces timeouts, and avoids invoking a local shell.

The remote SSH command emits predictable `key=value` lines. Service metrics use
systemd cgroups and `/proc` to calculate memory and CPU usage. CPU sampling
prefers cumulative cgroup CPU time (including exiting workers), uses monotonic
elapsed time, and falls back to process ticks where needed. Counter resets and
invalid intervals produce `n/a`, rather than negative CPU values. Service CPU is
currently normalized against total logical CPU capacity.

## Severity

`SeverityEngine` assigns metric and server states. Server escalation follows
this order:

1. Any `ERROR` metric makes the server `ERROR`.
2. Otherwise, any `WARNING` metric makes the server `WARNING`.
3. Otherwise, any reliable successful metric makes the server `OK`.
4. Otherwise, the server is `UNKNOWN`.

Threshold defaults are defined in `PreferencesStore.swift` and configurable in
Preferences. PHP-FPM CPU has its own warning/critical pair; other services share
the general CPU pair. PHP-FPM defaults to 50% warning and 90% critical;
other service thresholds remain independent. Service CPU is normalized to all logical CPUs: one fully busy
core on an eight-core server reads approximately 12.5%.

## Preferences And Notifications

Refresh intervals and notification settings are persisted with `UserDefaults`.
Server definitions and SSH details remain in local JSON configuration.

Notifications track each metric independently and suppress unchanged warnings.
Recovery notifications are optional.
Native notifications require a standard macOS application bundle and gracefully
remain unavailable in raw Swift Package Manager executable builds.

## Build Verification

Run before merging changes:

```bash
swift build
jq empty servers.example.json
```

Also verify that public files do not contain private hosts or usernames.

## App Bundle

Build a debug or release bundle with the native Swift toolchain:

```bash
./build_app.sh
./build_app.sh release universal
open build/ArgusDesk.app
```

The script copies prebuilt icons from `Assets`, applies `Info.plist`, and signs
`build/ArgusDesk.app` with an ad-hoc development signature. No third-party
image tools are needed to build. Distribution requires proper Developer ID
signing and notarization; the development signature is not a distribution identity.
Keep an installed bundle at a stable path before enabling launch at login.

## Background Monitoring and Notifications

The app delegate owns timers independently of the dashboard. Closing or hiding
windows leaves monitoring active; Quit exits. Timers run in common run-loop modes,
and a process activity prevents App Nap without preventing system sleep. Monitoring
resumes after wake; ArgusDesk cannot monitor while the Mac is asleep or powered off.

Preferences uses `SMAppService.mainApp` to register or unregister launch at login,
reads the OS registration status, and surfaces errors or required approval.
The hidden-start preference hides the app after launch. The successful config
path is persisted so login launches do not depend on a working directory.

Notifications use `UNUserNotificationCenter` with native banners, sounds, and
per-server grouping. Metric transitions are tracked independently, with thresholds
in messages, repeat suppression, and optional recovery alerts. Unknown readings
preserve the last known state; disabled checks clear it. The first unhealthy
sample can alert. Authorization, Focus, and system notification settings still
control presentation. A test action is available in Preferences.

## Resource Readings

Disk rows show filesystem capacity and root-device sampled busy time. Linux
uses `findmnt` and sysfs block statistics over one second. Filesystems without
an identifiable block device show `n/a`. Device busy time is not throughput or
an aggregate across all physical devices. Native macOS collection currently
reports disk busy as `n/a` rather than substituting a different measurement.
Memory rows show RAM usage and allocated swap in GiB, using `free -b` on Linux
and `vm.swapusage` on macOS. Secondary readings are informational; capacity and
RAM thresholds continue to control resource alerts.

## Release Workflow

`.github/workflows/build-release.yml` runs on `v*` tag pushes or manual dispatch.
Manual runs test and build a universal Apple silicon/Intel release app and upload
an ad-hoc-signed development DMG as a workflow artifact, without publishing.
Tags must match the app and plist versions, have a finalized changelog heading,
and point to a commit reachable from `main`.

Configure these repository Actions secrets before pushing a release tag:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE` | Base64-encoded Developer ID Application certificate/private-key export (`.p12`) |
| `MACOS_CERTIFICATE_PASSWORD` | Password for the `.p12` export |
| `AC_APPLE_ID` | Apple account used for notarization |
| `AC_TEAM_ID` | Apple Developer team identifier |
| `AC_PASSWORD` | Apple app-specific password for notarization |

The workflow imports credentials into a temporary keychain, signs the app with
hardened runtime, creates and signs the DMG, and waits for notarization. Only
an accepted image is stapled, assessed, checksummed, and uploaded to a GitHub
Release. Failures do not publish an unsigned fallback. Signing material is
removed at job completion. Existing release assets are not overwritten.

Local packaging uses only built-in macOS tools:

```bash
./build_app.sh release universal
bash Scripts/package-dmg.sh build/ArgusDesk.app build/ArgusDesk-development.dmg
```

To package without replacing a running development bundle, use
`./build_app.sh release universal build/release/ArgusDesk.app`, then pass that
bundle path to `Scripts/package-dmg.sh`.

The image contains only `ArgusDesk.app` and an Applications shortcut. No private
configuration is included. Move the app into Applications before enabling login
startup; quit the previous app before replacing it during upgrades. Existing
preferences and the selected local config path survive replacement.

## Releases

Keep `Sources/ArgusDesk/Core/AppVersion.swift`, `Info.plist`, release notes,
and the release tag aligned.
For each release milestone:

1. Update `AppVersion.current`.
2. Add a matching entry to `CHANGELOG.md`.
3. Update user and developer documentation when behavior changes.
4. Run the build and configuration checks.
