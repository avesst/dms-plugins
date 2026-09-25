// openHAB Hub - settings
// Note: the API token is intentionally NOT a setting here. It is read at
// runtime from the keyring (secret-tool) or a token file, so it never lands
// in DMS's plaintext settings.json.
import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "openhabHub"

    PluginGlobalVar {
        id: healthVar
        varName: "ohHealth"
        defaultValue: "{}"
    }

    // Live connection status (readable even while the pill is hidden offline)
    readonly property var health: {
        try { return JSON.parse(healthVar.value || "{}") } catch (e) { return {} }
    }

    StyledText {
        width: parent.width
        text: "openHAB Hub"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Items are discovered automatically from the openHAB semantic model (Locations → Equipment → Points)."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "baseUrl"
        label: "openHAB URL"
        description: "Base URL of your openHAB instance (no trailing slash)"
        placeholder: "https://openhab.example.com"
        defaultValue: "http://localhost:8080"
    }

    SliderSetting {
        settingKey: "pollSeconds"
        label: "Refresh interval"
        description: "Seconds between item refreshes while the panel is open (connection is checked every 30s otherwise)"
        defaultValue: 2
        minimum: 1
        maximum: 30
    }

    SelectionSetting {
        settingKey: "tokenSource"
        label: "Token source"
        description: "Where the API token is read from at runtime"
        defaultValue: "keyring"
        options: [
            { label: "System keyring (secret-tool)", value: "keyring" },
            { label: "File", value: "file" }
        ]
    }

    StringSetting {
        settingKey: "keyringAttrs"
        label: "Keyring attributes"
        description: "Attribute pairs passed to secret-tool lookup (space separated)"
        placeholder: "service openhab"
        defaultValue: "service openhab"
    }

    StringSetting {
        settingKey: "tokenFile"
        label: "Token file"
        description: "Path to a file containing the token (used when source is File)"
        placeholder: "~/.config/openhab/token"
        defaultValue: "~/.config/openhab/token"
    }

    ToggleSetting {
        settingKey: "showUnmodeled"
        label: "Show standalone items"
        description: "Display items without location/equipment grouping under a 'Standalone' section"
        defaultValue: false
    }

    Column {
        width: parent.width
        spacing: 2

        StyledText {
            text: "Connection status"
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.DemiBold
            color: Theme.surfaceText
        }

        StyledText {
            text: {
                const h = root.health
                if (h.ok === undefined)
                    return "Waiting for daemon…"
                if (h.ok === false)
                    return "Offline: " + (h.detail || "openHAB unreachable")
                const at = new Date(h.at || 0)
                return "Online (last check " + at.toLocaleTimeString(Qt.locale(), "HH:mm:ss") + ")"
            }
            font.pixelSize: Theme.fontSizeSmall
            color: root.health.ok === true ? Theme.primary : Theme.surfaceVariantText
            wrapMode: Text.WordWrap
            width: parent.width
        }
    }

    StyledText {
        width: parent.width
        text: "Store your token in the keyring:\n  secret-tool store --label='openHAB API' service openhab account oh\n(it will prompt for the secret). The token is held in memory only and never written to DMS settings."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }
}