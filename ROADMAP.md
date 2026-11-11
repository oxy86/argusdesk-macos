# ArgusDesk for macOS Roadmap

This roadmap tracks work beyond the current 1.1 release. Implemented changes
and release history are documented in [CHANGELOG.md](CHANGELOG.md); technical
details are in [README_DEVELOPER.md](README_DEVELOPER.md).

## Distribution

- Check installation, upgrades, login startup, and notification authorization
  using a downloaded release on a clean Mac.

## Configuration

- Add a Preferences editor for per-server service unit names.
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
- Support package managers other than `apt` for the updates check, and report
  when a reboot is required.
- Consider configurable pending-update limits.

## Interface

- Make background and font colors configurable.
- Allow the dashboard window to be resized by dragging, not only from the
  height setting in Preferences.
- Color the local CPU, GPU, memory, and disk readings with the usage limits.
- Remember which server rows are open between launches.
- Offer a custom, thinner scroll bar styled to the app.
- Improve accessibility, VoiceOver labels, and keyboard navigation.
- Consider an optional desktop-overlay mode and click-through behavior.

## Future Platforms

- Evaluate an iOS companion.
- Evaluate an Android companion.
- Define shared monitoring concepts only when another client is actively being
  developed.
