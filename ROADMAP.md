# ArgusDesk for macOS Roadmap

This roadmap tracks work beyond the current 0.8.2 release. Implemented changes
and release history are documented in [CHANGELOG.md](CHANGELOG.md); technical
details are in [README_DEVELOPER.md](README_DEVELOPER.md).

## Distribution

- Check installation, upgrades, login startup, and notification authorization
  using a downloaded release on a clean Mac.

## Configuration

- Allow systemd service unit mappings to be configured per server.
- Add an editor for server connections, labels, and enabled checks in Preferences.
- Improve configuration error presentation and preserve the active dashboard
  when a replacement configuration cannot be loaded.
- Consider automatic configuration reload when the selected file changes.

## Monitoring

- Evaluate load average using remote CPU-count information.
- Improve partial-result reporting and include actionable command diagnostics.
- Review remote command portability and cgroup accounting across supported
  Linux distributions.
- Investigate a comparable native disk-activity reading for macOS.
- Consider configurable sustained-duration alerts and hysteresis to reduce
  notifications caused by brief resource spikes.
- Consider additional opt-in checks without introducing a server-side agent.

## Interface

- Make background and font colors configurable.
- Persist window position and allow more flexible sizing.
- Handle larger server lists and GPU process inventories on smaller displays.
- Improve accessibility, VoiceOver labels, and keyboard navigation.
- Refine menu bar summaries for larger server lists.
- Consider an optional desktop-overlay mode and click-through behavior.

## Future Platforms

- Evaluate an iOS companion.
- Evaluate an Android companion.
- Define shared monitoring concepts only when another client is actively being
  developed.
