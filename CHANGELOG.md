# Changelog

All notable changes to ArgusDesk for macOS are documented in this file.

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
