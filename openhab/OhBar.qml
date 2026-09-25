// openHAB Hub - bar widget + popout panel
// Reads the semantic model published by the daemon via global vars and renders
// it as a bar pill plus a card-based control panel. Sends commands back through
// the ohCommand global var (the daemon executes them).
import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var popoutService: null

    // Pill only when the daemon reports the openHAB connection up (marker file
    // maintained by the daemon on health transitions; no network in the check).
    visibilityCommand: "test -f $HOME/.cache/openhab-hub-online"
    visibilityInterval: 30

    popoutWidth: 480
    // Sized from measured content once the popout instantiates; fixed fallback until then
    property int measuredContentHeight: 0
    popoutHeight: measuredContentHeight > 0 ? Math.max(320, Math.min(820, measuredContentHeight)) : 660

    PluginGlobalVar {
        id: modelVar
        varName: "ohModel"
        defaultValue: "{}"
    }

    PluginGlobalVar {
        id: healthVar
        varName: "ohHealth"
        defaultValue: "{}"
    }

    readonly property var model: {
        try { return JSON.parse(modelVar.value || "{}") } catch (e) { return {} }
    }
    readonly property var health: {
        try { return JSON.parse(healthVar.value || "{}") } catch (e) { return {} }
    }

    readonly property bool connected: health.ok === true
    readonly property int lightsOn: {
        let n = 0
        const locs = root.model.locations || []
        for (let i = 0; i < locs.length; i++)
            for (let j = 0; j < (locs[i].equipment || []).length; j++)
                for (let k = 0; k < (locs[i].equipment[j].points || []).length; k++) {
                    const p = locs[i].equipment[j].points[k]
                    // a Dimmer's state is a percentage, not ON/OFF
                    if ((p.kind === "switch" && p.state === "ON") || (p.kind === "dimmer" && parseFloat(p.state) > 0))
                        n++
                }
        return n
    }

    // Split an equipment's points into: primary power switch, remaining
    // control rows (dimmers first, then ranges), and a read-only info line.
    function partition(points) {
        let power = null
        const rows = []
        const infos = []
        for (let i = 0; i < points.length; i++) {
            const p = points[i]
            if (p.kind === "switch" && power === null) {
                power = p
                continue
            }
            if (p.kind === "switch" || p.kind === "dimmer" || (p.kind === "range" && !p.readOnly))
                rows.push(p)
            else if (/link quality|linkquality|lqi/i.test(p.label))
                ; // network telemetry: not useful in the panel
            else if (p.kind === "text")
                infos.push(p.state === "-" ? p.label : p.label + " " + p.state)
            else
                infos.push(p.label + " " + p.state)
        }
        rows.sort(function (a, b) {
            const rank = function (p) { return p.kind === "dimmer" ? 0 : p.kind === "switch" ? 1 : 2 }
            return rank(a) - rank(b)
        })
        return { power: power, rows: rows, infos: infos }
    }

    // Optimistic state: commands are reflected locally immediately, then
    // overridden by polled reality once it arrives (or after a timeout).
    property var optimistic: ({})

    Timer {
        id: optimisticSweep
        interval: 1500
        repeat: true
        running: true
        onTriggered: {
            const now = Date.now()
            let changed = false
            const next = {}
            for (const k in root.optimistic) {
                if (now - root.optimistic[k].at < 6000)
                    next[k] = root.optimistic[k]
                else
                    changed = true
            }
            if (changed)
                root.optimistic = next
        }
    }

    function effectiveState(p) {
        const o = root.optimistic[p.name]
        if (o && Date.now() - o.at < 6000)
            return o.value
        return p.state
    }

    function sliderLabel(p) {
        if (p.kind === "dimmer")
            return "Brightness"
        if (p.colorTemp)
            return "Color"
        return p.label
    }

    function send(itemName, value) {
        const next = Object.assign({}, root.optimistic)
        next[itemName] = { value: value, at: Date.now() }
        root.optimistic = next
        PluginService.setGlobalVar(root.pluginId, "ohCommand", JSON.stringify({
            item: itemName,
            value: value,
            seq: Date.now()
        }))
    }

    // ---- bar pill ----

    readonly property int pillIconSize: Math.round((Theme.iconSize ? Theme.iconSize : 16) * 0.8)

    horizontalBarPill: Component {
        DankIcon {
            name: root.connected ? "home" : "cloud_off"
            size: root.pillIconSize
            color: root.connected && root.lightsOn > 0 ? Theme.primary : Theme.surfaceVariantText
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: root.connected ? "home" : "cloud_off"
            size: root.pillIconSize
            color: root.connected && root.lightsOn > 0 ? Theme.primary : Theme.surfaceVariantText
        }
    }

    // ---- popout panel ----

    popoutContent: Component {
        PopoutComponent {
            id: popRoot
            headerText: ""
            detailsText: ""

            Item {
                id: flickHost
                width: parent.width
                // PluginPopout sizes the popout from this implicit height, so cap it
                // here and let the flickable scroll the rest.
                readonly property int fullHeight: innerCol.y + innerCol.height + Theme.spacingM
                height: Math.min(fullHeight, 820 - popRoot.headerHeight - popRoot.detailsHeight)

                DankFlickable {
                    id: flick
                    anchors.fill: parent
                    clip: true
                    contentHeight: flickHost.fullHeight

                    Column {
                        id: innerCol
                        x: Theme.spacingM
                        y: Theme.spacingS
                        width: flick.width - Theme.spacingM * 2
                        spacing: Theme.spacingL

                        // size the popout to the content (clamped; scrolls if longer)
                        onHeightChanged: root.measuredContentHeight = Math.round(
                            innerCol.y + innerCol.height + Theme.spacingM
                            + popRoot.headerHeight + popRoot.detailsHeight)

                        Repeater {
                            model: root.model.locations || []

                            delegate: Column {
                                id: locBlock
                                required property var modelData
                                readonly property var loc: modelData
                                width: parent.width
                                spacing: Theme.spacingM

                                StyledText {
                                    text: (locBlock.loc.label || locBlock.loc.name).toUpperCase()
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.DemiBold
                                    color: Theme.surfaceVariantText
                                }

                                Repeater {
                                    model: locBlock.loc.equipment || []

                                    delegate: StyledRect {
                                        id: eqCard
                                        required property var modelData
                                        readonly property var eq: modelData
                                        readonly property var parts: root.partition(eq.points || [])
                                        width: parent.width
                                        height: cardCol.height + Theme.spacingM * 2
                                        color: Theme.surfaceContainerHigh
                                        radius: Theme.cornerRadius

                                        Column {
                                            id: cardCol
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: Theme.spacingM
                                            spacing: 8

                                            // header: equipment name + power toggle
                                            Item {
                                                width: parent.width
                                                height: 34

                                                StyledText {
                                                    anchors.left: parent.left
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: eqCard.eq.label || eqCard.eq.name
                                                    font.pixelSize: Theme.fontSizeMedium
                                                    font.weight: Font.Medium
                                                    color: Theme.surfaceText
                                                    elide: Text.ElideRight
                                                    width: parent.width - (eqCard.parts.power ? 70 : 0)
                                                }

                                                DankToggle {
                                                    visible: eqCard.parts.power !== null
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    checked: eqCard.parts.power ? root.effectiveState(eqCard.parts.power) === "ON" : false
                                                    hideText: true
                                                    onToggled: checked => root.send(eqCard.parts.power.name, checked ? "ON" : "OFF")
                                                }
                                            }

                                            // control rows: switches then sliders, in item order
                                            Repeater {
                                                model: eqCard.parts.rows

                                                delegate: Loader {
                                                    id: rowLoader
                                                    required property var modelData
                                                    readonly property var p: modelData
                                                    width: parent.width
                                                    height: rowLoader.p.kind === "switch" ? 34 : 20
                                                    sourceComponent: rowLoader.p.kind === "switch" ? switchRow : sliderRow

                                                    Component {
                                                        id: switchRow

                                                        Item {
                                                            width: rowLoader.width
                                                            height: 34

                                                            StyledText {
                                                                anchors.left: parent.left
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                text: rowLoader.p.label
                                                                font.pixelSize: Theme.fontSizeSmall
                                                                color: Theme.surfaceVariantText
                                                                elide: Text.ElideRight
                                                                width: parent.width - 70
                                                            }

                                                            DankToggle {
                                                                anchors.right: parent.right
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                checked: root.effectiveState(rowLoader.p) === "ON"
                                                                hideText: true
                                                                onToggled: checked => root.send(rowLoader.p.name, checked ? "ON" : "OFF")
                                                            }
                                                        }
                                                    }

                                                    Component {
                                                        id: sliderRow

                                                        Item {
                                                            id: sliderHost
                                                            width: rowLoader.width
                                                            height: 20

                                                            // Color temperature (from the item's semantic property) is shown in Kelvin.
                                                            // Mired items are converted (K = 1e6 / mired), so their range inverts.
                                                            readonly property bool isColorTemp: rowLoader.p.colorTemp === true
                                                            readonly property bool isMired: isColorTemp && rowLoader.p.ctUnit === "mired"
                                                            readonly property int sliderMin: isMired
                                                                ? Math.round(1000000 / rowLoader.p.max / sliderStep) * sliderStep : Math.round(rowLoader.p.min)
                                                            readonly property int sliderMax: isMired
                                                                ? Math.round(1000000 / Math.max(1, rowLoader.p.min) / sliderStep) * sliderStep : Math.round(rowLoader.p.max)
                                                            readonly property int sliderStep: isColorTemp ? 100 : 1
                                                            readonly property string unit: rowLoader.p.kind === "dimmer" ? "%" : (isColorTemp ? "K" : "")

                                                            function toSlider(raw) {
                                                                const v = parseFloat(raw)
                                                                if (isNaN(v))
                                                                    return sliderMin
                                                                const shown = isMired ? 1000000 / Math.max(1, v) : v
                                                                const stepped = Math.round(shown / sliderStep) * sliderStep
                                                                return isColorTemp ? Math.max(sliderMin, Math.min(sliderMax, stepped)) : stepped
                                                            }

                                                            function fromSlider(shown) {
                                                                if (isMired) {
                                                                    const m = Math.round(1000000 / Math.max(1, shown))
                                                                    return String(Math.max(rowLoader.p.min, Math.min(rowLoader.p.max, m)))
                                                                }
                                                                return String(shown)
                                                            }

                                                            readonly property int baseValue: {
                                                                const o = root.optimistic[rowLoader.p.name]
                                                                if (o && Date.now() - o.at < 6000)
                                                                    return toSlider(o.value)
                                                                return toSlider(rowLoader.p.state)
                                                            }

                                                            property bool dragging: false
                                                            property bool hovering: false
                                                            property int dragValue: 0
                                                            property real pointerX: 0
                                                            readonly property bool showBubble: dragging || hovering
                                                            readonly property int displayValue: dragging ? dragValue : baseValue

                                                            StyledText {
                                                                anchors.left: parent.left
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                text: root.sliderLabel(rowLoader.p)
                                                                font.pixelSize: Theme.fontSizeSmall
                                                                color: Theme.surfaceVariantText
                                                                elide: Text.ElideRight
                                                                width: 110
                                                            }

                                                            Item {
                                                                id: track
                                                                anchors.left: parent.left
                                                                anchors.leftMargin: 122
                                                                anchors.right: parent.right
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                height: 8

                                                                readonly property real ratio: sliderMax > sliderMin
                                                                    ? Math.max(0, Math.min(1, (displayValue - sliderMin) / (sliderMax - sliderMin))) : 0

                                                                StyledRect {
                                                                    anchors.fill: parent
                                                                    radius: height / 2
                                                                    color: Theme.surfaceContainerHighest
                                                                }

                                                                StyledRect {
                                                                    anchors.left: parent.left
                                                                    anchors.top: parent.top
                                                                    anchors.bottom: parent.bottom
                                                                    width: track.ratio * track.width
                                                                    radius: height / 2
                                                                    color: Theme.primary
                                                                }

                                                                MouseArea {
                                                                    id: trackMouse
                                                                    anchors.fill: parent
                                                                    cursorShape: Qt.PointingHandCursor
                                                                    hoverEnabled: true
                                                                    onContainsMouseChanged: sliderHost.hovering = trackMouse.containsMouse

                                                                    function apply(x) {
                                                                        const t = Math.max(0, Math.min(1, x / track.width))
                                                                        let v = sliderMin + t * (sliderMax - sliderMin)
                                                                        v = Math.round(v / sliderStep) * sliderStep
                                                                        sliderHost.dragValue = Math.max(sliderMin, Math.min(sliderMax, v))
                                                                    }

                                                                    onPressed: mouse => {
                                                                        sliderHost.dragging = true
                                                                        sliderHost.pointerX = mouse.x
                                                                        apply(mouse.x)
                                                                    }
                                                                    onPositionChanged: mouse => {
                                                                        sliderHost.pointerX = mouse.x
                                                                        if (sliderHost.dragging)
                                                                            apply(mouse.x)
                                                                    }
                                                                    onReleased: mouse => {
                                                                        apply(mouse.x)
                                                                        sliderHost.dragging = false
                                                                        root.send(rowLoader.p.name, sliderHost.fromSlider(sliderHost.dragValue))
                                                                    }
                                                                    onCanceled: sliderHost.dragging = false
                                                                }

                                                                // tooltip on hover or drag, centered on the pointer
                                                                Item {
                                                                    id: bubble
                                                                    visible: sliderHost.showBubble
                                                                    anchors.bottom: parent.top
                                                                    anchors.bottomMargin: 12
                                                                    x: {
                                                                        const w = bubbleRow.width + 16
                                                                        const cx = Math.max(0, Math.min(track.width, sliderHost.pointerX))
                                                                        return Math.max(0, Math.min(track.width - w, cx - w / 2))
                                                                    }

                                                                    StyledRect {
                                                                        anchors.fill: bubbleRow
                                                                        anchors.leftMargin: -8
                                                                        anchors.rightMargin: -8
                                                                        anchors.topMargin: -3
                                                                        anchors.bottomMargin: -3
                                                                        radius: height / 2
                                                                        color: Theme.primary
                                                                        opacity: 0.9
                                                                    }

                                                                    Row {
                                                                        id: bubbleRow
                                                                        anchors.centerIn: parent

                                                                        StyledText {
                                                                            text: sliderHost.displayValue + sliderHost.unit
                                                                            font.pixelSize: Theme.fontSizeSmall - 1
                                                                            color: Theme.background
                                                                            anchors.verticalCenter: parent.verticalCenter
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            // read-only info footer
                                            StyledText {
                                                visible: eqCard.parts.infos.length > 0
                                                text: eqCard.parts.infos.join("   ·   ")
                                                font.pixelSize: Theme.fontSizeSmall - 2
                                                color: Theme.surfaceVariantText
                                                opacity: 0.7
                                                elide: Text.ElideRight
                                                width: parent.width
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        StyledText {
                            visible: (root.model.locations || []).length === 0
                            text: root.connected ? "No semantic items found yet." : "No data from daemon."
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }
                }
            }
        }
    }
}