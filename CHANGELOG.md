# Changelog

All notable changes to ArgusDesk for macOS are documented in this file.

## 0.8

- Replaced the desktop overlay with a standard macOS window, Dock icon, and
  App Switcher support; monitoring continues when windows are hidden or closed.
- Added saved vertical and horizontal server layouts, an opaque black background,
  wider metric labels, and window sizes that account for enabled metrics.
- Moved ping and HTTP into server headings and used a dot for SSH connectivity.
  Disabled ping is neutral `off`; irrelevant service rows are hidden.
- Added independent per-server refresh intervals with a global fallback, blank
  fields in Settings, and optional local/server labels with hostname/IP fallback.
- Added configurable GPU utilization and VRAM thresholds for colors and alerts.
- Improved service CPU sampling with cgroup counters and actual elapsed time;
  retained normalized CPU percentages and set PHP-FPM defaults to 50%/90%.
- Added configuration file selection and reload, with a persisted path for
  reliable startup outside the project directory.
- Added configurable per-server checks and optional NVIDIA utilization, VRAM,
  process names/PIDs, allocated memory, and supported process SM utilization.
- Added separate disk capacity/busy and memory/swap rows. Linux disk activity
  samples the root block device; unavailable readings remain `n/a`.
- Added dedicated PHP-FPM CPU warning and critical thresholds, with persisted
  values, threshold validation, and matching notification details.
- Added native launch-at-login and hidden-start preferences.
- Added native per-metric warning, critical, and optional recovery notifications,
  threshold details, repeat suppression, foreground banners, and a test action.
- Fixed dashboard observation so completed monitoring results update the window.
- Fixed notification and menu icon concurrency compatibility across macOS SDKs.
- Added application packaging scripts, metadata, and icons.
- Added a universal Apple silicon/Intel DMG workflow with tag/main/version
  validation, Developer ID signing, notarization, checksums, and release upload.
  Manual workflow runs produce development artifacts without publishing.
- Made test notifications request permission directly and display delivery
  feedback, with a shortcut to macOS Notification Settings.
- Added regression coverage for monitoring presentation, NVIDIA parsing,
  disabled checks, layout sizing, and metric notification transitions.

## 0.7

- Added the MIT license.
- Reorganized user, developer, roadmap, and release documentation.
- Prevented example configuration and demo data from being treated as live
  monitoring state.
- Made `enabled_checks` consistently control displayed results and local
  ping/HTTP execution.
- Added portable PHP-FPM systemd unit discovery.
- Added a clear empty state when no servers are configured.
- Prevented native notification initialization from crashing Swift Package
  Manager executable builds.

## 0.6

- Added native macOS notifications for server warning and error transitions.
- Added optional recovery notifications.
- Added persisted notification controls to Preferences.
- Prevented repeated alerts while server severity remains unchanged.

## 0.5

- Added a native Preferences window.
- Added persisted local and remote refresh interval settings.
- Applied refresh interval changes without restarting ArgusDesk.

## 0.4

- Added a menu bar status item with worst-server status coloring.
- Added overall health, server counts, last refresh, and problematic-server
  summaries.
- Added menu commands for refresh, showing the overlay, Preferences, and quit.

## 0.3

- Added centralized metric and server severity evaluation.
- Added thresholds for ping latency, HTTP status, disk usage, memory usage, and
  selected service CPU.

## 0.2

- Added remote SSH monitoring with timeout-aware command execution.
- Added local ping and HTTP checks.
- Added load, disk, memory, and selected service monitoring.
- Added selected service memory and normalized CPU display.
- Added non-overlapping automatic remote refreshes.

## 0.1

- Added the native macOS application shell and transparent desktop overlay.
- Added the compact SwiftUI status interface.
- Added JSON configuration loading.
- Added live local Mac statistics.
