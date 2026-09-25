# dms-plugins

Personal plugin repository for [Dank Material Shell](https://github.com/AvengeMedia/DankMaterialShell),
structured as a monorepo: each plugin lives in its own subdirectory and is exposed
to the DMS plugin store through the registry entries in `plugins/` (root level, same layout as the official dms-plugin-registry).

## Plugins

| Plugin | Path | Description |
|---|---|---|
| openHAB Hub | `openhab/` | Control an openHAB instance from the DankBar. Auto-populated from the openHAB semantic model. |

## openHAB Hub

A composite plugin (daemon + bar widget):

- **Daemon** polls `GET /rest/items?metadata=semantics` while the popout is
  open, builds the Locations → Equipment → Points tree and publishes it to
  shared global vars. While closed it only checks the connection every 30s.
- **Bar widget** shows a home icon that opens a popout with one card per
  equipment, grouped by location:
  - a power toggle for the equipment's first switch, and toggles for any others;
  - handle-less brightness sliders (percent);
  - color temperature sliders shown in Kelvin over a warm-to-cool gradient,
    with a marker in the light's current color. Items in mireds are converted
    to and from Kelvin; the slider range comes from the item's min/max;
  - read-only values in a footer line.

  Sliders are dimmed (but still usable) while the equipment's power is off, and
  show the value in a bubble on hover or drag. Commands are sent on release;
  controls update optimistically and fall back to the polled state after 6s.
- **Connection awareness**: the daemon maintains the marker file
  `~/.cache/openhab-hub-online`; the pill hides automatically when openHAB is
  unreachable (checked every 30s), e.g. on a laptop away from home.
- **Credentials are never stored in DMS settings.** The token is read at
  runtime from the system keyring (`secret-tool`) or a token file, and held in
  memory only. A failed lookup (e.g. keyring still locked at login) is retried
  with backoff.

### Item model requirements

Only items in the openHAB semantic model are shown: Equipment inside a
Location, with Points as members of the Equipment. Equipment without a
location is listed under *Unassigned*.

- Number items get a slider only if their state description has a minimum and
  maximum (Dimmers always get one, 0-100).
- Color temperature is detected from the Point's semantic property
  (`ColorTemperature`), not from its label. Without it, the item is shown as a
  plain number slider in its own units.
- Items are treated as Kelvin if their state or pattern has a `K` unit or their
  maximum is above 1000; otherwise as mireds.

### Local development install

```bash
ln -sfn ~/src/dms-plugins/openhab ~/.config/DankMaterialShell/plugins/openhabHub
```

Then in DMS: Settings → Plugins → *Scan for Plugins* → enable **openHAB Hub** →
add it to the DankBar layout (Settings → Appearance → DankBar Layout).

If the plugin was installed from the plugin store instead, `openhabHub` is a
symlink into a git clone under `plugins/.repos/`, which only changes when DMS
updates the plugin from GitHub. Replace it with the symlink above to run your
working copy.

Disabling and re-enabling the plugin does not always load changed QML; restart
DMS to be sure.

### Token storage

Keyring (recommended):

```sh
secret-tool store --label='openHAB API' service openhab account oh
# prompts for the secret; paste your openHAB API token
```

Or a file with strict permissions:

```sh
mkdir -p ~/.config/openhab && umask 077
printf 'YOUR_API_TOKEN' > ~/.config/openhab/token
```

The default keyring lookup attributes are `service openhab` (configurable in
the plugin settings).

### Settings

| Key | Default | Meaning |
|---|---|---|
| `baseUrl` | `http://localhost:8080` | openHAB base URL |
| `pollSeconds` | `2` | Refresh interval for item states while the popout is open |
| `tokenSource` | `keyring` | `keyring` or `file` |
| `keyringAttrs` | `service openhab` | `secret-tool lookup` attributes |
| `tokenFile` | `~/.config/openhab/token` | Fallback token file |
| `showUnmodeled` | `false` | Show semantic Points that belong to no Equipment under *Standalone* |

## Registry

Each plugin needs one entry in `plugins/<user>-<plugin>.json`
(see `plugins/avesst-oh-hub.json`), with `repo` pointing at this repository and
`path` at the plugin's subdirectory. Then either:

- point DMS Settings → Plugins → Browse at this repository as a custom
  registry (registry entries are read from `plugins/*.json` in a git repo), or
- copy the entry into a PR against the official
  [dms-plugin-registry](https://github.com/AvengeMedia/dms-plugin-registry).

## Debugging

Run DMS from a terminal (`qs -p <config>/quickshell/dms/shell.qml`) and watch
the log for `OH daemon:` messages. Plugin load errors are also shown in
Settings → Plugins.