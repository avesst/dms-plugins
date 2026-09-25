// openHAB Hub - daemon surface
// Owns the openHAB REST connection: polls the item model, publishes it via
// PluginService global vars, and executes commands requested by widget surfaces.
import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var popoutService: null

    // ---- settings (persisted by OhSettings.qml) ----
    readonly property string baseUrl: String(pluginData.baseUrl || "http://localhost:8080").replace(/\/+$/, "")
    readonly property int pollSeconds: pluginData.pollSeconds || 5
    readonly property bool useKeyring: (pluginData.tokenSource || "keyring") === "keyring"
    readonly property string keyringAttrs: pluginData.keyringAttrs || "service openhab"
    readonly property string tokenFile: pluginData.tokenFile || "~/.config/openhab/token"
    readonly property bool showUnmodeled: pluginData.showUnmodeled === true

    property string apiToken: ""
    property bool pollBusy: false
    property int lastCmdSeq: 0

    Timer {
        id: pollTimer
        interval: Math.max(1, root.pollSeconds) * 1000
        repeat: true
        running: false
        triggeredOnStart: false
        onTriggered: root.poll()
    }

    // short-delay poll after sending a command so the UI catches up quickly
    Timer {
        id: quickPoll
        interval: 1200
        onTriggered: root.poll()
    }

    Component.onCompleted: {
        console.log("OH daemon: starting, baseUrl=" + root.baseUrl)
        root.refreshToken()
        pollTimer.start()
    }

    onPluginDataChanged: {
        root.refreshToken()
        pollTimer.restart()
    }

    Connections {
        target: PluginService
        function onGlobalVarChanged(pluginId, varName) {
            console.log("OH daemon: globalVarChanged " + pluginId + "/" + varName)
            if (pluginId !== root.pluginId || varName !== "ohCommand")
                return
            try {
                const cmd = JSON.parse(PluginService.getGlobalVar(root.pluginId, "ohCommand", "{}"))
                console.log("OH daemon: command seq=" + cmd.seq + " item=" + cmd.item + " value=" + cmd.value)
                if (cmd && cmd.seq && cmd.seq > root.lastCmdSeq) {
                    root.lastCmdSeq = cmd.seq
                    root.sendCommand(cmd.item, cmd.value)
                }
            } catch (e) {
                console.log("OH daemon: command parse error: " + e)
            }
        }
    }

    // ---- health / shared state ----

    // Marker file lets the bar pill's visibilityCommand (plain `test -f`, no
    // network) show/hide the pill with DMS's built-in mechanism. Only touched
    // on state transitions, not on every poll.
    readonly property string onlineMarker: "/.cache/openhab-hub-online"
    property int lastHealthOk: -1 // -1 unknown, 0 down, 1 up

    function setHealth(ok, detail) {
        PluginService.setGlobalVar(root.pluginId, "ohHealth", JSON.stringify({
            ok: ok,
            detail: detail || "",
            at: Date.now()
        }))
        const nowOk = ok ? 1 : 0
        if (nowOk === root.lastHealthOk)
            return
        root.lastHealthOk = nowOk
        if (ok)
            Proc.runCommand("openhabHub.marker", ["sh", "-c", "mkdir -p $HOME/.cache && date -Is > $HOME" + root.onlineMarker])
        else
            Proc.runCommand("openhabHub.marker", ["sh", "-c", "rm -f $HOME" + root.onlineMarker])
    }

    // ---- credentials ----
    // Token is never stored in DMS settings (settings.json is plaintext).
    // It is fetched at runtime from the keyring (secret-tool) or a user file.

    function refreshToken() {
        console.log("OH daemon: refreshing token (source=" + (root.useKeyring ? "keyring" : "file") + ")")
        if (root.useKeyring) {
            const attrs = root.keyringAttrs.trim().split(/\s+/).filter(a => a.length > 0)
            Proc.runCommand("openhabHub.token", ["secret-tool", "lookup"].concat(attrs), (out, code) => {
                const t = out.trim()
                if (code === 0 && t.length > 0) {
                    root.apiToken = t
                    root.setHealth(true, "")
                    root.poll()
                } else {
                    root.apiToken = ""
                    root.setHealth(false, "No token from keyring. Store it: secret-tool store --label='openHAB API' service openhab account oh")
                }
            }, 0)
        } else {
            Proc.runCommand("openhabHub.token", ["sh", "-c", "cat " + root.tokenFile + " 2>/dev/null"], (out, code) => {
                const t = out.trim()
                if (code === 0 && t.length > 0) {
                    root.apiToken = t
                    root.setHealth(true, "")
                    root.poll()
                } else {
                    root.apiToken = ""
                    root.setHealth(false, "Token file missing/unreadable: " + root.tokenFile)
                }
            }, 0)
        }
    }

    // ---- REST ----

    function api(method, path, body, cb) {
        if (root.apiToken.length === 0) {
            cb("no token loaded yet")
            return
        }
        console.log("OH daemon: api " + method + " " + path)
        const xhr = new XMLHttpRequest()
        xhr.open(method, root.baseUrl + path)
        xhr.setRequestHeader("Authorization", "Bearer " + root.apiToken)
        if (body !== null)
            xhr.setRequestHeader("Content-Type", "text/plain")
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (xhr.status === 0) {
                cb("openHAB unreachable (network error)")
                return
            }
            if (xhr.status >= 200 && xhr.status < 300) {
                cb(null, xhr.responseText)
            } else {
                cb("HTTP " + xhr.status + (xhr.responseText ? ": " + xhr.responseText.slice(0, 160) : ""))
            }
        }
        xhr.send(body === undefined ? null : body)
    }

    function poll() {
        if (root.pollBusy || root.apiToken.length === 0)
            return
        root.pollBusy = true
        api("GET", "/rest/items?metadata=semantics", null, (err, text) => {
            root.pollBusy = false
            if (err) {
                root.setHealth(false, err)
                return
            }
            try {
                root.publishModel(JSON.parse(text))
                root.setHealth(true, "")
            } catch (e) {
                root.setHealth(false, "bad response: " + e)
            }
        })
    }

    function sendCommand(itemName, value) {
        console.log("OH daemon: POST " + itemName + " = " + value)
        root.pendingRetryItem = itemName
        root.pendingRetryValue = value
        api("POST", "/rest/items/" + encodeURIComponent(itemName), value, (err) => {
            if (err) {
                console.log("OH daemon: POST failed: " + err)
                if (String(err).indexOf("401") >= 0 || String(err).indexOf("403") >= 0) {
                    console.log("OH daemon: auth error, refreshing token and retrying once")
                    root.refreshToken()
                    retryTimer.restart()
                } else {
                    setHealth(false, "command failed: " + err)
                }
                return
            }
            console.log("OH daemon: POST ok")
            quickPoll.restart()
        })
    }

    property string pendingRetryItem: ""
    property string pendingRetryValue: ""

    Timer {
        id: retryTimer
        interval: 1500
        onTriggered: {
            if (root.pendingRetryItem.length > 0)
                root.sendCommand(root.pendingRetryItem, root.pendingRetryValue)
            root.pendingRetryItem = ""
        }
    }

    // ---- semantic model ----
    // openHAB semantics values observed:
    //   Location_Indoor_Room_Kitchen / Equipment_LightSource_Lightbulb / Point, Point_Control
    // Points attach to equipment via groupNames; equipment attaches to locations via groupNames.

    function pointInfo(it) {
        const sd = it.stateDescription || {}
        const type = String(it.type || "")
        const readOnly = sd.readOnly === true
        const hasRange = sd.minimum !== undefined && sd.minimum !== null && sd.maximum !== undefined && sd.maximum !== null
        let kind = "text"
        if (type === "Switch" && !readOnly)
            kind = "switch"
        else if (type === "Dimmer" && !readOnly)
            kind = "dimmer"
        else if (type === "Number" && hasRange && !readOnly)
            kind = "range"
        return {
            name: it.name,
            label: it.label || it.name,
            type: type,
            kind: kind,
            state: it.state === null || it.state === undefined ? "-" : String(it.state),
            min: hasRange ? Number(sd.minimum) : 0,
            max: hasRange ? Number(sd.maximum) : 100,
            readOnly: readOnly
        }
    }

    function publishModel(items) {
        const sem = (it) => (it.metadata && it.metadata.semantics && it.metadata.semantics.value)
            ? String(it.metadata.semantics.value) : ""
        const byName = {}
        items.forEach(it => { byName[it.name] = it })

        const locations = []
        const locByName = {}
        const equipmentByName = {}

        items.forEach(function (it) {
            if (sem(it).startsWith("Location")) {
                const loc = { name: it.name, label: it.label || it.name, equipment: [] }
                locations.push(loc)
                locByName[it.name] = loc
            }
        })

        items.forEach(function (it) {
            if (!sem(it).startsWith("Equipment"))
                return
            let loc = null
            const gs = it.groupNames || []
            for (let i = 0; i < gs.length; i++) {
                if (locByName[gs[i]]) { loc = locByName[gs[i]]; break }
            }
            const eq = { name: it.name, label: it.label || it.name, points: [] }
            equipmentByName[it.name] = eq
            if (loc)
                loc.equipment.push(eq)
            else
                locations.push({ name: "Unassigned", label: "Unassigned", equipment: [eq] })
        })

        items.forEach(function (it) {
            if (!sem(it).startsWith("Point"))
                return
            const gs = it.groupNames || []
            for (let i = 0; i < gs.length; i++) {
                const eq = equipmentByName[gs[i]]
                if (eq) { eq.points.push(pointInfo(it)); return }
            }
            if (!root.showUnmodeled)
                return
            // standalone points (e.g. automation gates) grouped under "Standalone"
            let other = null
            for (let i = 0; i < locations.length; i++) {
                if (locations[i].name === "Standalone") { other = locations[i]; break }
            }
            if (!other) {
                other = { name: "Standalone", label: "Standalone", equipment: [{ name: "_standalone", label: "Items", points: [] }] }
                locations.push(other)
            }
            other.equipment[0].points.push(pointInfo(it))
        })

        PluginService.setGlobalVar(root.pluginId, "ohModel", JSON.stringify({ locations: locations }))
    }
}
