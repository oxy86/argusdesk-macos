# ArgusDesk for macOS Developer Guide

## Technology

ArgusDesk is a native macOS Swift Package Manager executable targeting macOS 14
or later. It uses SwiftUI for views and AppKit for application lifecycle,
desktop overlay, Preferences, and menu bar integration. The project currently
has no third-party dependencies.

## Architecture

The application is organized into three main areas:

- `App`: application lifecycle and AppKit window/menu controllers.
- `Core`: configuration, models, monitoring services, severity evaluation,
  preferences, and notifications.
- `UI`: SwiftUI views for the desktop overlay.

Monitoring and parsing remain separate from UI rendering. Local and remote
refresh loops run independently, and overlapping remote refreshes are skipped.

## Project Structure

```text
Sources/ArgusDesk/
  App/
    AppDelegate.swift
    MenuBarController.swift
    OverlayWindowController.swift
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

## Configuration Loading

`ConfigLoader` loads local `servers.json`. The committed `servers.example.json`
is documentation only and is never treated as live monitoring configuration.
Private server configuration must remain uncommitted. Public examples must use
placeholder hosts and usernames.

## Remote Monitoring

Each server refresh uses:

- one local `/sbin/ping` check
- one optional local `/usr/bin/curl` check
- one key-only `/usr/bin/ssh` command for internal server metrics

External commands run through `CommandRunner`, which captures standard output
and error, enforces timeouts, and avoids invoking a local shell.

The remote SSH command emits predictable `key=value` lines. Service metrics use
systemd cgroups and `/proc` to calculate memory and CPU usage. Service CPU is
normalized against total logical CPU capacity.

## Severity

`SeverityEngine` assigns metric and server states. Server escalation follows
this order:

1. Any `ERROR` metric makes the server `ERROR`.
2. Otherwise, any `WARNING` metric makes the server `WARNING`.
3. Otherwise, any reliable successful metric makes the server `OK`.
4. Otherwise, the server is `UNKNOWN`.

Thresholds are currently defined in `SeverityEngine.swift`.

## Preferences And Notifications

Refresh intervals and notification settings are persisted with `UserDefaults`.
Server definitions and SSH details remain in local JSON configuration.

Notifications establish the first completed remote refresh as a baseline, then
notify only on severity transitions. Recovery notifications are optional.
Native notifications require a standard macOS application bundle and gracefully
remain unavailable in raw Swift Package Manager executable builds.

## Build Verification

Run before merging changes:

```bash
swift build
jq empty servers.example.json
```

Also verify that public files do not contain private hosts or usernames.

## Releases

The app version has a single source in `Sources/ArgusDesk/Core/AppVersion.swift`.
For each release milestone:

1. Update `AppVersion.current`.
2. Add a matching entry to `CHANGELOG.md`.
3. Update user and developer documentation when behavior changes.
4. Run the build and configuration checks.
