# Drive Health for Noctalia Shell

Drive Health is a plugin for **Noctalia Shell v5** that monitors SMART health,
temperature, endurance, integrity counters, mounted storage, and background
self-tests for SSDs and hard drives. It provides a compact bar summary and an
expandable per-drive panel.

The runtime is local-only and makes no network requests. Drive discovery uses
`lsblk`; full SMART data uses `smartctl`. An optional hardened system collector
can provide read-only SMART access without granting Noctalia root privileges.
It is disabled by default for new users; plugin settings explain the additional
health, endurance, integrity, sensor, and self-test data before the user opts in.

## Install from this Git source

Add the repository as a custom source, enable the plugin, and then add its
summary widget in Noctalia's bar settings:

```sh
noctalia msg plugins source add drive-health git https://github.com/gustav0ar/drive-health-plugin
noctalia msg plugins enable gustav0ar/drive-health
```

The bar entry is `gustav0ar/drive-health:summary`. Clicking it opens the
`gustav0ar/drive-health:drives` panel.

Update the source and hot-reload the enabled plugin with:

```sh
noctalia msg plugins update drive-health
```

See the [plugin documentation](drive-health/README.md) for dependencies,
the optional collector, settings, alerts, self-tests, privacy, upgrades, and
uninstallation.

## Local development

From the repository root, register the checkout as a path source and run the
full test suite:

```sh
noctalia msg plugins source add drive-health-dev path "$PWD"
noctalia msg plugins enable gustav0ar/drive-health
make test
```

The repository follows Noctalia's source layout: `catalog.toml` indexes the
self-contained plugin in `drive-health/`. `make test` runs the plugin
harnesses, shell and translation checks, Noctalia lint, and distribution-safety
validation.

## Security and privacy

- Collection and rendering are local; the plugin has no network client.
- Package installation, collector installation, and SMART self-tests always
  require explicit user action and normal system authorization.
- The optional collector is read-only, network-isolated, and writes only its
  runtime cache under `/run`.
- If Full SMART is enabled, plugin updates detect an outdated collector and ask
  the user to approve its separate update; privileged files are never replaced
  silently.
- Exported diagnostic snapshots can include drive model, serial number, and
  mount paths. Review them before sharing.

Licensed under the [MIT License](LICENSE).
