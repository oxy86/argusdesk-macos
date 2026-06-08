# ArgusDesk for macOS

ArgusDesk is a compact native macOS desktop companion for monitoring the local
Mac and remote Linux servers.

It provides a transparent desktop overlay, a menu bar health summary, and
optional notifications. Remote monitoring uses existing SSH keys and read-only
commands; no server-side agent or stored SSH password is required.

## Features

- Local Mac hostname, macOS version, uptime, battery, CPU, memory, disk, and
  network status.
- Remote SSH reachability, ping latency, HTTP status, load average, root disk,
  and memory checks.
- nginx, MariaDB, PHP-FPM, and memcached status with service memory and
  normalized CPU usage.
- `OK`, `WARNING`, `ERROR`, and `UNKNOWN` severity states.
- Menu bar summary with refresh, overlay, Preferences, and quit actions.
- Configurable refresh intervals and optional state-change notifications.

Notifications require a standard macOS application bundle. They remain disabled
when ArgusDesk is run directly through Swift Package Manager.

## Requirements

- macOS 14 or later.
- Swift 6 toolchain for source builds.
- Existing key-based SSH access for each monitored server.
- Standard remote Linux utilities used by the configured checks, including
  `systemctl`, `/proc`, `awk`, `df`, and `free`.

ArgusDesk uses key-only, noninteractive SSH. It does not store or prompt for SSH
passwords.

## Configuration

Copy `servers.example.json` to `servers.json`, then replace the placeholder
values with local server details. `servers.json` is ignored by git.

```json
{
  "remote_refresh_seconds": 60,
  "local_refresh_seconds": 5,
  "servers": [
    {
      "name": "example",
      "host": "example.com",
      "ssh_user": "username",
      "ssh_port": 22,
      "http_url": "https://example.com",
      "http_user_agent": "ArgusDesk/0.7",
      "enabled_checks": [
        "ssh",
        "ping",
        "http",
        "load",
        "disk",
        "memory",
        "nginx",
        "mariadb",
        "php_fpm",
        "memcached"
      ]
    }
  ]
}
```

Defaults:

- `ssh_port`: `22`
- `remote_refresh_seconds`: `60`
- `local_refresh_seconds`: `5`
- `http_user_agent`: curl default when omitted

Refresh intervals can also be changed in Preferences. Preferences override the
JSON refresh intervals and are stored by macOS.

## Install From Source

Clone the repository, create local configuration, then build and run ArgusDesk:

```bash
git clone https://github.com/oxy86/argusdesk-macos.git
cd argusdesk-macos
cp servers.example.json servers.json

# Edit servers.json with your local server details.
swift build
swift run ArgusDesk
```

ArgusDesk runs as a Swift Package Manager executable. Keep the terminal session
open while the app is running. Stop it with `Control-C` or choose Quit from the
menu bar item.

## Security

- Remote commands are read-only and run through `/usr/bin/ssh`.
- SSH uses `BatchMode=yes`, `PasswordAuthentication=no`, and a connection
  timeout.
- HTTP checks run locally through `/usr/bin/curl`.
- Private hosts, usernames, and credentials belong only in local configuration.
- ArgusDesk does not require a remote monitoring agent or health endpoint.

## Documentation

- [Developer Guide](README_DEVELOPER.md)
- [Roadmap](ROADMAP.md)
- [Changelog](CHANGELOG.md)

## License

ArgusDesk is available under the [MIT License](LICENSE).
