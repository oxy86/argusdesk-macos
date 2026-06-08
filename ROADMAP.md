# ArgusDesk for macOS Roadmap

This roadmap tracks planned work beyond the current `0.7` release. Completed
work is documented in [CHANGELOG.md](CHANGELOG.md).

## Distribution

- Create a standard macOS application bundle.
- Add application metadata and icons.
- Document signing, notarization, installation, and upgrade workflows.
- Prepare stable release builds outside the Swift Package Manager development
  workflow.
- Add a GitHub Actions release workflow that produces a downloadable executable
  or application bundle, preferably packaged as a DMG when signing,
  notarization, and CI tooling permit.

## Configuration

- Allow service unit mappings to be configured per server.
- Add validation with clear configuration error messages.
- Support reloading configuration without restarting the app.
- Consider editing non-sensitive server settings from Preferences while keeping
  credentials and private host details local.

## Monitoring

- Make severity thresholds configurable.
- Improve load-average evaluation using remote CPU-count information.
- Expand partial-result reporting and command diagnostics.
- Improve error reporting and diagnostic logging.
- Review remote command portability across supported Linux distributions.
- Consider additional opt-in checks without introducing a server-side agent.

## Interface

- Add optional click-through behavior for the desktop overlay.
- Validate the interface with multiple servers, long values, and different
  display sizes.
- Persist overlay position and size.
- Improve accessibility and VoiceOver labels.
- Add controls for overlay visibility, placement, and appearance.
- Refine menu bar summaries for larger server lists.

## Future Platforms

- Evaluate an iOS companion.
- Evaluate an Android companion.
- Define shared monitoring concepts only when another client is actively being
  developed.
