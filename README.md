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

- **Daemon** polls `GET /rest/items?metadata=semantics`, builds the
  Locations → Equipment → Points tree and publishes it to shared global vars.
- **Bar widget** shows a lightbulb pill (count of lights on) with a popout
  panel: power toggles for switches/dimmers, handle-less sliders for brightness
  (percent) and color temperature (displayed in Kelvin, converted to/from the
  item's mireds) with a hover/drag value tooltip, and read-only rows for the
  rest. Slider commands are sent on release; values update optimistically and
  revert if openHAB disagrees.
- **Connection awareness**: the daemon maintains the marker file
  `~/.cache/openhab-hub-online`; the pill hides automatically when openHAB is
  unreachable.
- **Credentials are never stored in DMS settings.** The token is read at
  runtime from the system keyring (`secret-tool`) or a token file, and held in
  memory only.

### Local development install

```bash
ln -sfn ~/src/dms-plugins/openhab ~/.config/DankMaterialShell/plugins/openhabHub
```

Then in DMS: Settings → Plugins → *Scan for Plugins* → enable **openHAB Hub** →
add it to the DankBar layout (Settings → Appearance → DankBar Layout).

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
| `pollSeconds` | `5` | Poll interval for item states |
| `tokenSource` | `keyring` | `keyring` or `file` |
| `keyringAttrs` | `service openhab` | `secret-tool lookup` attributes |
| `tokenFile` | `~/.config/openhab/token` | Fallback token file |
| `showUnmodeled` | `false` | Show items outside the semantic model |

## Registry

Each new plugin needs one entry in `plugins/<user>-<plugin>.json`
(see `plugins/avesst-oh-hub.json`). Replace `YOURUSER` with your
GitHub username and the repo URL, then:

- point DMS Settings → Plugins → Browse at this repository as a custom
  registry (registry entries are read from `plugins/*.json` in a git repo), or
- copy the entry into a PR against the official
  [dms-plugin-registry](https://github.com/AvengeMedia/dms-plugin-registry).

## Debugging

Run DMS from a terminal (`qs -p <config>/quickshell/dms/shell.qml`) and watch
the log for `openhabHub` messages. Plugin load errors are also shown in
Settings → Plugins.