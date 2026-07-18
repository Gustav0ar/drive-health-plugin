# Drive Health for Noctalia Shell

A plugin for Noctalia Shell v5 that discovers physical SSDs and HDDs and
presents their health in a compact bar widget plus an expandable, per-drive
panel. It is built for Niri installations but does not depend on
compositor-specific APIs.

The panel intentionally separates two often-confused values:

- **Storage used** is occupied space on filesystems currently mounted from the drive.
- **Life remaining** is the endurance estimate reported by SMART/NVMe firmware.

## Installation

From the repository root, add the custom Git source and enable the plugin:

```sh
noctalia msg plugins source add drive-health git https://github.com/gustav0ar/drive-health-plugin
noctalia msg plugins enable gustav0ar/drive-health-plugin
```

Add `gustav0ar/drive-health-plugin:summary` to a bar in Noctalia settings.
Clicking the widget toggles the `gustav0ar/drive-health-plugin:drives` panel.

## Features

- Dynamic SATA, NVMe, and USB drive discovery through `lsblk`
- SMART health, temperature, power-on time, self-tests, mounted folders and storage, and
  media/integrity counters for both SSDs and HDDs
- SSD endurance used/remaining, available spare, reads, writes, and NVMe
  diagnostics
- HDD start/stop and head-load cycles, spin retries, command timeouts, interface
  CRC errors, and reallocated/pending/uncorrectable sectors
- Composite and individual NVMe temperature sensors, with the hottest sensor
  used for display and alerting by default
- Latest SMART self-test result and progress, with an explicit two-step action
  for starting short or long tests
- Mounted-filesystem use aggregated per physical drive
- Theme-aware Noctalia v5 declarative UI
- Compact, expandable drive cards and retained temperature/endurance graphs
- Per-drive aliases, ordering, visibility, alert toggles, missing-drive alerts,
  and temperature/endurance thresholds
- Temperature and endurance status colors with configurable thresholds
- Deduplicated desktop alerts for SMART failure, high temperature, low
  endurance/spare capacity, NVMe critical warnings, media/integrity errors,
  failed self-tests, missing drives, critically full
  mounted storage, and collector failures
- Persistent active-alert state, worsening-counter notifications, unsafe
  shutdown change detection, and optional recovery notifications
- Capability-based dependency checks with a persistent setup warning,
  distro-aware install command, copy action, and user-confirmed terminal
  installer
- Guided install, upgrade, status, and two-step removal controls for the
  optional system collector
- Python-free runtime: one POSIX raw collector plus Luau normalization and
  alert services
- English and Brazilian Portuguese translations
- HDD display and health alerting enabled by default, with independent settings
- No password prompts from the bar

## Project layout

- `plugin.toml` — Noctalia API 3 manifest
- `collector.luau` — device normalization, cache migration, and shared state publisher
- `service.luau` — isolated alert evaluation and persistence service
- `history.luau` — bounded, low-write-rate trend persistence
- `widget.luau` — compact bar summary
- `panel.luau` — expandable drive cards, preferences, lifecycle, and self-tests
- `scripts/collect_raw.sh` — dependency-light raw JSON collector
- `packaging/` — hardened root collector, timer, self-test helper, and uninstaller

The repository root contains the source catalog and distribution checks. This
directory is the self-contained plugin exported by Noctalia.

## Dependencies

The plugin checks both command presence and the required JSON capabilities when
its collector starts and whenever the user requests a recheck. Missing or
incompatible dependencies are shown persistently in the bar tooltip and panel,
and a one-time desktop notification requests installation.
Collection pauses when `lsblk` is missing; without `smartctl`, the plugin keeps
showing its best-effort inventory but explains why full SMART data is missing.

| Command | Common package | Purpose |
| --- | --- | --- |
| `lsblk` | `util-linux` | Discovers physical disks and mounted filesystems |
| `smartctl` | `smartmontools` | Reads SMART/NVMe health data |

When pacman, APT, DNF, Zypper, APK, XBPS, or Portage is detected, the panel
builds a command containing only the missing packages. **Open installer** opens
that command in the configured terminal. Nothing is installed silently: the
user must review the command and approve the `sudo` and package-manager prompts.
The panel also provides **Copy command** and **Recheck** actions. Installation
never starts in the background: the action opens a terminal where the user can
review the command and approve `sudo`.

Manual examples:

```sh
# Arch Linux / CachyOS
sudo pacman -S --needed smartmontools util-linux

# Debian / Ubuntu
sudo apt-get install smartmontools util-linux

# Fedora
sudo dnf install smartmontools util-linux

# openSUSE
sudo zypper install smartmontools util-linux
```

After installation, click **Recheck** or run:

```sh
noctalia msg plugin gustav0ar/drive-health-plugin:collector all check-dependencies
```

## Development install

Register the repository root as a path source, then enable the plugin:

```sh
noctalia msg plugins source add drive-health-dev path "$PWD"
noctalia msg plugins enable gustav0ar/drive-health-plugin
```

Run that command from the repository root, not this exported plugin directory,
so Noctalia can read `catalog.toml` and discover `drive-health-plugin/`.

## Alerts

Desktop alerts are enabled by default. A new issue notifies once; an active
issue does not repeat every refresh. Critical escalation or a growing hardware
error counter notifies again, and recovery notifications can be disabled in
the plugin settings. The panel always lists active alerts and the bar widget
shows their count, even when desktop alerts are disabled.

Panel alerts can be dismissed individually or all at once. Dismissals persist
across Noctalia restarts and can be restored from the alert card. A dismissed
alert returns automatically if it becomes critical, its underlying hardware
counter grows, or the condition clears and later recurs.

Historical NVMe/ATA error-log entries and pre-existing unsafe-shutdown totals
are shown as diagnostics but are not treated as current failures. Growth after
the plugin establishes its baseline does trigger a notification. Removable and
USB drives are excluded from disappearance alerts by default; this can be
overridden per drive.

Test the notification route without creating a fake drive issue:

```sh
noctalia msg plugin gustav0ar/drive-health-plugin:collector all test-alert
```

## Full SMART access

Linux normally restricts raw SMART ioctls to root. Without extra privileges,
the plugin still shows drive inventory, mounted space, and temperatures exposed
through sysfs, but endurance and full health fields may be unavailable.

For full data, the project includes a systemd timer that runs a fixed,
root-owned copy of the raw collector and atomically writes JSON to
`/run/noctalia-smart-monitor/raw.json`. Luau performs normalization inside
Noctalia. Noctalia itself never receives root privileges; the explicit
installer action opens a terminal where the user reviews and authorizes `sudo`:

```sh
sudo ./packaging/install-system-collector.sh
```

The panel detects whether this collector is absent, stale, healthy, or from an
older plugin version. Its install/upgrade button opens the command in a terminal
and requires the user's normal `sudo` approval. The service is hardened with a
read-only system/home view, no network access, no new privileges, restricted
namespaces, and write access limited to its runtime cache directory.

To remove only the optional system collector while leaving the plugin and its
settings intact:

```sh
sudo ./packaging/uninstall-system-collector.sh
```

The panel requires two clicks before it opens that command in a terminal.

## SMART self-tests

Expand a drive and select **Short test** or **Long test**. The plugin first asks
for confirmation, then uses the desktop Polkit agent to request administrator
approval. Once approved, a fixed, root-owned helper starts the test and exits;
the drive firmware continues the test in the background. No terminal is opened.
The helper accepts only `short` or `long`, validates that the target is an NVMe
controller or whole block disk, and then calls `smartctl`. Merely opening the
panel never starts a test.

The panel immediately shows authorization/startup state, then reports the
firmware's current progress and final result on subsequent refreshes (normally
within the collector's 30-second polling interval). Long tests can take hours
and may affect device performance. Background self-tests require
`pkexec` (normally provided by the distribution's `polkit` package) and a
running graphical Polkit authentication agent; the panel explains when this
optional capability is unavailable.

## History and drive preferences

History is stored as bounded JSON in Noctalia's plugin data directory. The
default sampling interval is one hour and retention is 30 days; both are
configurable. Files are written atomically and samples are added only when the
configured interval has elapsed.

Expand a drive and choose **Customize** to set an alias, reorder or hide it,
change its thresholds, or disable health/disappearance alerts for that drive.
Hidden drives can be restored from the panel. Preferences are also stored
atomically and are keyed by stable serial number when available.

## Settings

Noctalia's plugin settings control the refresh interval, global temperature and
SSD-life thresholds, desktop and recovery alerts, HDD visibility and alerting,
missing-drive grace scans, hotspot selection, and history sampling/retention.
Per-drive customization adds aliases, ordering, visibility, thresholds, and
health or disappearance alert toggles without changing global defaults.

## Updates and migration

Update the Git source and hot-reload the enabled plugin with:

```sh
noctalia msg plugins update drive-health
```

Version 1.0.0 expects the 1.0.0 optional system collector. If the panel reports
that an older collector needs an upgrade, use its explicit **Upgrade** action or
rerun `sudo ./packaging/install-system-collector.sh` from this directory.

Noctalia keys settings, history, and other plugin data by plugin ID. A
pre-release installation that used a different ID is treated as a separate
plugin, and its data does not migrate automatically. Keep the previous source
until the new plugin has been enabled and verified.

## Privacy

Drive Health collects and renders data locally and has no network client. Its
runtime files remain in Noctalia's plugin data directory and, when installed,
the system collector cache under `/run`. The `export-snapshot` diagnostic can
contain drive models, serial numbers, and mounted paths; inspect every export
before sharing it.

## Uninstall

First remove the optional system collector if it is installed:

```sh
sudo ./packaging/uninstall-system-collector.sh
```

Then disable the plugin. If this repository is the only plugin using the custom
source, remove that source as well:

```sh
noctalia msg plugins disable gustav0ar/drive-health-plugin
noctalia msg plugins source remove drive-health
```

Disabling or removing the source does not silently delete ID-scoped plugin data.

## Validation

```sh
make test
```

The test target covers collector normalization and failure modes, alert
deduplication/escalation/disappearance behavior, history retention and atomic
writes and retry behavior, panel and bar-widget rendering and interactions, the
raw shell collector, translation parity, shell syntax/static analysis,
Noctalia lint (when available), and whitespace errors. From the repository
root, `make test` additionally runs catalog parity and distribution-safety
checks. The same root target runs in GitHub Actions.

Live verification after installing the system collector:

```sh
sudo systemctl start noctalia-smart-monitor.service
systemctl --no-pager --full status noctalia-smart-monitor.timer
jq '{schema, collector_version, drive_count: (.smart | length)}' \
  /run/noctalia-smart-monitor/raw.json
noctalia msg plugin gustav0ar/drive-health-plugin:collector all export-snapshot
```
