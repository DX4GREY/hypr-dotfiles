import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: mouseConfigPage
    forceWidth: true

    property var connectedDevices: []
    property var perDeviceMap: ({})
    property string selectedDeviceName: ""
    property var availableCursorThemes: ["Bibata-Modern-Classic", "breeze_cursors", "Breeze_Light", "Adwaita"]
    property bool hardwareTuningAvailable: false
    property var hardwareDevices: []
    property bool hasExternalMouse: false
    property bool touchpadAutoDisabled: false

    // Testing Playground state
    property int testLeftClicks: 0
    property int testRightClicks: 0
    property int testMiddleClicks: 0
    property int testScrollCount: 0
    property string lastScrollDirection: "-"
    property real lastClickTime: 0
    property int lastDoubleDuration: 0
    property int estimatedPollingRate: 0
    property real lastMoveTime: 0

    function updateField(key, value) {
        if (Config.options.mouse && Config.options.mouse[key] !== undefined) {
            Config.options.mouse[key] = value;
        }
        Quickshell.execDetached([
            "python3",
            Directories.mouseManagerScript,
            "update-field",
            key,
            value.toString()
        ]);
    }

    function updateDeviceTuning(devName, key, value) {
        if (!devName) return;
        Quickshell.execDetached([
            "python3",
            Directories.mouseManagerScript,
            "set-device-tuning",
            devName,
            key,
            value.toString()
        ]);
        let currentMap = Object.assign({}, mouseConfigPage.perDeviceMap);
        if (!currentMap[devName]) currentMap[devName] = {};
        currentMap[devName][key] = value;
        mouseConfigPage.perDeviceMap = currentMap;
    }

    function resetDeviceTuning(devName) {
        if (!devName) return;
        let currentMap = Object.assign({}, mouseConfigPage.perDeviceMap);
        delete currentMap[devName];
        mouseConfigPage.perDeviceMap = currentMap;

        updateDeviceTuning(devName, "sensitivity", Config.options.mouse.sensitivity || 0.0);
        updateDeviceTuning(devName, "accelProfile", Config.options.mouse.accelProfile || "flat");
        updateDeviceTuning(devName, "naturalScroll", Config.options.mouse.naturalScroll || false);
        updateDeviceTuning(devName, "enabled", true);
    }

    function getDeviceConfigVal(devName, key, fallback) {
        if (mouseConfigPage.perDeviceMap && mouseConfigPage.perDeviceMap[devName] && mouseConfigPage.perDeviceMap[devName][key] !== undefined) {
            return mouseConfigPage.perDeviceMap[devName][key];
        }
        return fallback;
    }

    // Process to read initial settings
    Process {
        id: settingsReader
        command: ["python3", Directories.mouseManagerScript, "get"]
        stdout: SplitParser {
            onRead: data => {
                try {
                    let parsed = JSON.parse(data.trim());
                    if (parsed.connectedDevices) {
                        mouseConfigPage.connectedDevices = parsed.connectedDevices;
                        if (!mouseConfigPage.selectedDeviceName && parsed.connectedDevices.length > 0) {
                            mouseConfigPage.selectedDeviceName = parsed.connectedDevices[0].name;
                        }
                    }
                    if (parsed.perDevice) mouseConfigPage.perDeviceMap = parsed.perDevice;
                    if (parsed.availableCursorThemes) mouseConfigPage.availableCursorThemes = parsed.availableCursorThemes;
                    if (parsed.hardwareTuningAvailable !== undefined) mouseConfigPage.hardwareTuningAvailable = parsed.hardwareTuningAvailable;
                    if (parsed.hardwareDevices) mouseConfigPage.hardwareDevices = parsed.hardwareDevices;
                    if (parsed.hasExternalMouse !== undefined) mouseConfigPage.hasExternalMouse = parsed.hasExternalMouse;
                    if (parsed.touchpadAutoDisabled !== undefined) mouseConfigPage.touchpadAutoDisabled = parsed.touchpadAutoDisabled;

                    if (Config.options.mouse) {
                        if (parsed.sensitivityPercent !== undefined) Config.options.mouse.sensitivityPercent = parsed.sensitivityPercent;
                        if (parsed.accelProfile !== undefined) Config.options.mouse.accelProfile = parsed.accelProfile;
                        if (parsed.naturalScroll !== undefined) Config.options.mouse.naturalScroll = parsed.naturalScroll;
                        if (parsed.leftHanded !== undefined) Config.options.mouse.leftHanded = parsed.leftHanded;
                        if (parsed.middleEmulation !== undefined) Config.options.mouse.middleEmulation = parsed.middleEmulation;
                        if (parsed.scrollFactorPercent !== undefined) Config.options.mouse.scrollFactorPercent = parsed.scrollFactorPercent;

                        if (parsed.touchpadEnabled !== undefined) Config.options.mouse.touchpadEnabled = parsed.touchpadEnabled;
                        if (parsed.autoDisableTouchpad !== undefined) Config.options.mouse.autoDisableTouchpad = parsed.autoDisableTouchpad;
                        if (parsed.touchpadSensitivityPercent !== undefined) Config.options.mouse.touchpadSensitivityPercent = parsed.touchpadSensitivityPercent;
                        if (parsed.touchpadNaturalScroll !== undefined) Config.options.mouse.touchpadNaturalScroll = parsed.touchpadNaturalScroll;
                        if (parsed.tapToClick !== undefined) Config.options.mouse.tapToClick = parsed.tapToClick;
                        if (parsed.tapAndDrag !== undefined) Config.options.mouse.tapAndDrag = parsed.tapAndDrag;
                        if (parsed.dragLock !== undefined) Config.options.mouse.dragLock = parsed.dragLock;
                        if (parsed.disableWhileTyping !== undefined) Config.options.mouse.disableWhileTyping = parsed.disableWhileTyping;
                        if (parsed.clickfingerBehavior !== undefined) Config.options.mouse.clickfingerBehavior = parsed.clickfingerBehavior;
                        if (parsed.touchpadScrollFactorPercent !== undefined) Config.options.mouse.touchpadScrollFactorPercent = parsed.touchpadScrollFactorPercent;
                        if (parsed.touchpadMiddleEmulation !== undefined) Config.options.mouse.touchpadMiddleEmulation = parsed.touchpadMiddleEmulation;

                        if (parsed.cursorSize !== undefined) Config.options.mouse.cursorSize = parsed.cursorSize;
                        if (parsed.cursorTheme !== undefined) Config.options.mouse.cursorTheme = parsed.cursorTheme;
                        if (parsed.inactiveTimeout !== undefined) Config.options.mouse.inactiveTimeout = parsed.inactiveTimeout;
                        if (parsed.followMouse !== undefined) Config.options.mouse.followMouse = parsed.followMouse;
                        if (parsed.mouseMoveEnablesDpms !== undefined) Config.options.mouse.mouseMoveEnablesDpms = parsed.mouseMoveEnablesDpms;
                        if (parsed.noWarps !== undefined) Config.options.mouse.noWarps = parsed.noWarps;
                        if (parsed.hideOnKeyPress !== undefined) Config.options.mouse.hideOnKeyPress = parsed.hideOnKeyPress;
                        if (parsed.zoomFactor !== undefined) Config.options.mouse.zoomFactor = parsed.zoomFactor;
                        if (parsed.mouseRefocus !== undefined) Config.options.mouse.mouseRefocus = parsed.mouseRefocus;
                        if (parsed.workspaceSwipeInvert !== undefined) Config.options.mouse.workspaceSwipeInvert = parsed.workspaceSwipeInvert;
                        if (parsed.workspaceSwipeDistance !== undefined) Config.options.mouse.workspaceSwipeDistance = parsed.workspaceSwipeDistance;
                    }
                } catch(e) {
                    console.log("Error parsing mouse settings JSON:", e);
                }
            }
        }
        Component.onCompleted: running = true
    }

    // Refresh devices list periodically
    Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: {
            devicePoller.running = true;
        }
    }

    Process {
        id: devicePoller
        command: ["python3", Directories.mouseManagerScript, "get"]
        stdout: SplitParser {
            onRead: data => {
                try {
                    let parsed = JSON.parse(data.trim());
                    if (parsed.connectedDevices) mouseConfigPage.connectedDevices = parsed.connectedDevices;
                    if (parsed.hasExternalMouse !== undefined) mouseConfigPage.hasExternalMouse = parsed.hasExternalMouse;
                    if (parsed.touchpadAutoDisabled !== undefined) mouseConfigPage.touchpadAutoDisabled = parsed.touchpadAutoDisabled;
                } catch(e) {}
            }
        }
    }

    // ==========================================
    // SECTION 1: Connected Devices & Tuning
    // ==========================================
    ContentSection {
        icon: "devices"
        title: Translation.tr("Connected Input Devices & Tuning")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colOnLayer0
            font.pixelSize: Appearance.font.pixelSize.small
            text: Translation.tr("Automatically detects connected mice, touchpads, and pointer hardware. Select a device to adjust custom sensitivity, acceleration, and specific hardware overrides.")
        }

        // External mouse indicator badge
        Rectangle {
            visible: mouseConfigPage.hasExternalMouse
            Layout.fillWidth: true
            implicitHeight: 38
            radius: Appearance.rounding.small
            color: mouseConfigPage.touchpadAutoDisabled ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8
                MaterialSymbol {
                    iconSize: 20
                    text: "sensors"
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    text: mouseConfigPage.touchpadAutoDisabled 
                        ? Translation.tr("External mouse connected • Touchpad is automatically disabled")
                        : Translation.tr("External mouse connected and active")
                    font.weight: Font.DemiBold
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer1
                }
            }
        }

        // Detected Devices Cards List
        Flow {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: mouseConfigPage.connectedDevices
                delegate: Rectangle {
                    required property var modelData
                    implicitWidth: Math.max(160, devRow.implicitWidth + 20)
                    implicitHeight: 46
                    radius: Appearance.rounding.small
                    color: (mouseConfigPage.selectedDeviceName === modelData.name) 
                        ? Appearance.colors.colPrimaryContainer 
                        : Appearance.colors.colLayer2
                    border.width: (mouseConfigPage.selectedDeviceName === modelData.name) ? 1.5 : 0
                    border.color: Appearance.colors.colPrimary

                    RowLayout {
                        id: devRow
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        MaterialSymbol {
                            iconSize: 22
                            text: modelData.type === "touchpad" ? "touchpad_mouse" : "mouse"
                            color: (mouseConfigPage.selectedDeviceName === modelData.name) 
                                ? Appearance.colors.colOnPrimaryContainer 
                                : Appearance.colors.colPrimary
                        }

                        ColumnLayout {
                            spacing: 1
                            Layout.fillWidth: true
                            StyledText {
                                text: modelData.displayName
                                font.weight: Font.DemiBold
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: (mouseConfigPage.selectedDeviceName === modelData.name) 
                                    ? Appearance.colors.colOnPrimaryContainer 
                                    : Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                                Layout.maximumWidth: 190
                            }
                            StyledText {
                                text: (modelData.type === "touchpad" ? Translation.tr("Touchpad") : Translation.tr("Mouse")) + (modelData.isExternal ? " • " + Translation.tr("External") : "")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colOnLayer2
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            mouseConfigPage.selectedDeviceName = modelData.name;
                        }
                    }
                }
            }
        }

        // Per-device tuning panel
        Rectangle {
            visible: mouseConfigPage.selectedDeviceName.length > 0
            Layout.fillWidth: true
            implicitHeight: tuningCol.implicitHeight + 24
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2

            ColumnLayout {
                id: tuningCol
                anchors {
                    fill: parent
                    margins: 12
                }
                spacing: 10

                RowLayout {
                    spacing: 8
                    MaterialSymbol {
                        iconSize: 24
                        text: "tune"
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        font.weight: Font.DemiBold
                        font.pixelSize: Appearance.font.pixelSize.normal
                        text: Translation.tr("Device Tuning:") + " " + mouseConfigPage.selectedDeviceName
                        color: Appearance.colors.colOnLayer1
                    }
                    Item { Layout.fillWidth: true }
                    RippleButtonWithIcon {
                        materialIcon: "restart_alt"
                        mainText: Translation.tr("Reset Device")
                        onClicked: {
                            resetDeviceTuning(mouseConfigPage.selectedDeviceName);
                        }
                    }
                }

                ConfigSwitch {
                    buttonIcon: "power_settings_new"
                    text: Translation.tr("Enable this device")
                    checked: getDeviceConfigVal(mouseConfigPage.selectedDeviceName, "enabled", true)
                    onCheckedChanged: {
                        updateDeviceTuning(mouseConfigPage.selectedDeviceName, "enabled", checked);
                    }
                }

                ConfigRow {
                    ConfigSpinBox {
                        icon: "speed"
                        text: Translation.tr("Device Speed Override (%)")
                        value: Math.round(getDeviceConfigVal(mouseConfigPage.selectedDeviceName, "sensitivity", 0.0) * 100)
                        from: -100
                        to: 100
                        stepSize: 5
                        onValueChanged: {
                            updateDeviceTuning(mouseConfigPage.selectedDeviceName, "sensitivity", value / 100.0);
                        }
                    }
                    ConfigSpinBox {
                        icon: "unfold_more"
                        text: Translation.tr("Scroll Speed Factor (%)")
                        value: Math.round(getDeviceConfigVal(mouseConfigPage.selectedDeviceName, "scrollFactor", 1.0) * 100)
                        from: 20
                        to: 300
                        stepSize: 10
                        onValueChanged: {
                            updateDeviceTuning(mouseConfigPage.selectedDeviceName, "scrollFactor", value / 100.0);
                        }
                    }
                }

                ConfigRow {
                    uniform: true
                    ConfigSwitch {
                        buttonIcon: "swap_vert"
                        text: Translation.tr("Device Natural Scrolling")
                        checked: getDeviceConfigVal(mouseConfigPage.selectedDeviceName, "naturalScroll", false)
                        onCheckedChanged: {
                            updateDeviceTuning(mouseConfigPage.selectedDeviceName, "naturalScroll", checked);
                        }
                    }
                }
            }
        }
    }

    // ==========================================
    // SECTION 2: Mouse Settings
    // ==========================================
    ContentSection {
        icon: "mouse"
        title: Translation.tr("Mouse Settings")

        ConfigRow {
            ConfigSpinBox {
                icon: "speed"
                text: Translation.tr("Pointer Speed / Sensitivity (%)")
                value: Config.options.mouse.sensitivityPercent || 0
                from: -100
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.mouse.sensitivityPercent = value;
                    Config.options.mouse.sensitivity = value / 100.0;
                    updateField("sensitivity", value / 100.0);
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Speed Presets")
            ConfigSelectionArray {
                currentValue: Config.options.mouse.sensitivityPercent || 0
                onSelected: newValue => {
                    Config.options.mouse.sensitivityPercent = newValue;
                    Config.options.mouse.sensitivity = newValue / 100.0;
                    updateField("sensitivity", newValue / 100.0);
                }
                options: [
                    { displayName: Translation.tr("Slow (-50%)"), icon: "slow_motion_video", value: -50 },
                    { displayName: Translation.tr("Default (0%)"), icon: "adjust", value: 0 },
                    { displayName: Translation.tr("Fast (+30%)"), icon: "trending_up", value: 30 },
                    { displayName: Translation.tr("Gaming (+50%)"), icon: "sports_esports", value: 50 }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Acceleration Profile (Accel Profile)")
            tooltip: Translation.tr("Flat provides raw 1:1 consistent mouse movement ideal for gaming. Adaptive increases pointer speed when flicking quickly.")

            ConfigSelectionArray {
                currentValue: Config.options.mouse.accelProfile || "flat"
                onSelected: newValue => {
                    Config.options.mouse.accelProfile = newValue;
                    updateField("accelProfile", newValue);
                }
                options: [
                    { displayName: Translation.tr("Flat (Raw 1:1 / Gaming)"), icon: "timeline", value: "flat" },
                    { displayName: Translation.tr("Adaptive (Accelerated)"), icon: "trending_up", value: "adaptive" }
                ]
            }
        }

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "swap_vert"
                text: Translation.tr("Natural scrolling (Reverse direction)")
                checked: Config.options.mouse.naturalScroll
                onCheckedChanged: {
                    Config.options.mouse.naturalScroll = checked;
                    updateField("naturalScroll", checked);
                }
                StyledToolTip {
                    text: Translation.tr("Inverts scroll wheel direction to match natural touchscreen behavior")
                }
            }

            ConfigSwitch {
                buttonIcon: "pan_tool"
                text: Translation.tr("Left-handed mode")
                checked: Config.options.mouse.leftHanded
                onCheckedChanged: {
                    Config.options.mouse.leftHanded = checked;
                    updateField("leftHanded", checked);
                }
                StyledToolTip {
                    text: Translation.tr("Swaps left and right mouse buttons for left-handed ergonomics")
                }
            }
        }

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "mouse"
                text: Translation.tr("Middle click emulation")
                checked: Config.options.mouse.middleEmulation
                onCheckedChanged: {
                    Config.options.mouse.middleEmulation = checked;
                    updateField("middleEmulation", checked);
                }
                StyledToolTip {
                    text: Translation.tr("Pressing left and right mouse buttons together triggers middle click")
                }
            }

            ConfigSpinBox {
                icon: "unfold_more"
                text: Translation.tr("Scroll Speed Factor (%)")
                value: Config.options.mouse.scrollFactorPercent || 100
                from: 20
                to: 300
                stepSize: 10
                onValueChanged: {
                    Config.options.mouse.scrollFactorPercent = value;
                    Config.options.mouse.scrollFactor = value / 100.0;
                    updateField("scrollFactor", value / 100.0);
                }
            }
        }
    }

    // ==========================================
    // SECTION 3: Touchpad Settings
    // ==========================================
    ContentSection {
        icon: "touchpad_mouse"
        title: Translation.tr("Touchpad Settings")

        ConfigSwitch {
            buttonIcon: "touch_app"
            text: Translation.tr("Enable Touchpad")
            checked: Config.options.mouse.touchpadEnabled
            onCheckedChanged: {
                Config.options.mouse.touchpadEnabled = checked;
                updateField("touchpadEnabled", checked);
            }
            StyledToolTip {
                text: Translation.tr("Master toggle to enable or disable laptop touchpad")
            }
        }

        ConfigSwitch {
            buttonIcon: "mouse"
            text: Translation.tr("Auto-disable touchpad when external mouse is connected")
            checked: Config.options.mouse.autoDisableTouchpad
            onCheckedChanged: {
                Config.options.mouse.autoDisableTouchpad = checked;
                updateField("autoDisableTouchpad", checked);
            }
            StyledToolTip {
                text: Translation.tr("Automatically turns off touchpad whenever a USB or wireless mouse is plugged in")
            }
        }

        ColumnLayout {
            enabled: Config.options.mouse.touchpadEnabled && !mouseConfigPage.touchpadAutoDisabled
            opacity: (Config.options.mouse.touchpadEnabled && !mouseConfigPage.touchpadAutoDisabled) ? 1.0 : 0.4
            Layout.fillWidth: true
            spacing: 8

            ConfigRow {
                ConfigSpinBox {
                    icon: "speed"
                    text: Translation.tr("Touchpad Speed / Sensitivity (%)")
                    value: Config.options.mouse.touchpadSensitivityPercent || 0
                    from: -100
                    to: 100
                    stepSize: 5
                    onValueChanged: {
                        Config.options.mouse.touchpadSensitivityPercent = value;
                        Config.options.mouse.touchpadSensitivity = value / 100.0;
                        updateField("touchpadSensitivity", value / 100.0);
                    }
                }
                ConfigSpinBox {
                    icon: "unfold_more"
                    text: Translation.tr("Touchpad Scroll Speed (%)")
                    value: Config.options.mouse.touchpadScrollFactorPercent || 70
                    from: 20
                    to: 200
                    stepSize: 10
                    onValueChanged: {
                        Config.options.mouse.touchpadScrollFactorPercent = value;
                        Config.options.mouse.touchpadScrollFactor = value / 100.0;
                        updateField("touchpadScrollFactor", value / 100.0);
                    }
                }
            }

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "touch_app"
                    text: Translation.tr("Tap to click")
                    checked: Config.options.mouse.tapToClick
                    onCheckedChanged: {
                        Config.options.mouse.tapToClick = checked;
                        updateField("tapToClick", checked);
                    }
                }

                ConfigSwitch {
                    buttonIcon: "drag_pan"
                    text: Translation.tr("Tap and drag")
                    checked: Config.options.mouse.tapAndDrag
                    onCheckedChanged: {
                        Config.options.mouse.tapAndDrag = checked;
                        updateField("tapAndDrag", checked);
                    }
                }
            }

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "lock"
                    text: Translation.tr("Drag lock")
                    checked: Config.options.mouse.dragLock
                    onCheckedChanged: {
                        Config.options.mouse.dragLock = checked;
                        updateField("dragLock", checked);
                    }
                }

                ConfigSwitch {
                    buttonIcon: "keyboard"
                    text: Translation.tr("Disable while typing (DWT)")
                    checked: Config.options.mouse.disableWhileTyping
                    onCheckedChanged: {
                        Config.options.mouse.disableWhileTyping = checked;
                        updateField("disableWhileTyping", checked);
                    }
                }
            }

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "swap_vert"
                    text: Translation.tr("Touchpad Natural Scrolling")
                    checked: Config.options.mouse.touchpadNaturalScroll
                    onCheckedChanged: {
                        Config.options.mouse.touchpadNaturalScroll = checked;
                        updateField("touchpadNaturalScroll", checked);
                    }
                }

                ConfigSwitch {
                    buttonIcon: "pan_tool"
                    text: Translation.tr("Clickfinger Behavior")
                    checked: Config.options.mouse.clickfingerBehavior
                    onCheckedChanged: {
                        Config.options.mouse.clickfingerBehavior = checked;
                        updateField("clickfingerBehavior", checked);
                    }
                }
            }
        }
    }

    // ==========================================
    // SECTION 4: Touchpad Gestures
    // ==========================================
    ContentSection {
        icon: "swipe"
        title: Translation.tr("Touchpad Gestures")

        ConfigSwitch {
            buttonIcon: "swap_horiz"
            text: Translation.tr("Invert workspace swipe direction")
            checked: Config.options.mouse.workspaceSwipeInvert
            onCheckedChanged: {
                Config.options.mouse.workspaceSwipeInvert = checked;
                updateField("workspaceSwipeInvert", checked);
            }
            StyledToolTip {
                text: Translation.tr("Reverses 4-finger horizontal workspace switching direction")
            }
        }

        ContentSubsection {
            title: Translation.tr("Workspace Swipe Distance (Sensitivity)")
            tooltip: Translation.tr("Lower distance requires shorter swipe; higher distance offers more precision")

            ConfigSelectionArray {
                currentValue: Config.options.mouse.workspaceSwipeDistance || 700
                onSelected: newValue => {
                    Config.options.mouse.workspaceSwipeDistance = newValue;
                    updateField("workspaceSwipeDistance", newValue);
                }
                options: [
                    { displayName: Translation.tr("Quick Swipe (400px)"), icon: "bolt", value: 400 },
                    { displayName: Translation.tr("Balanced (700px)"), icon: "tune", value: 700 },
                    { displayName: Translation.tr("Long Precision (1000px)"), icon: "straighten", value: 1000 }
                ]
            }
        }
    }

    // ==========================================
    // SECTION 5: Pointer & Cursor Appearance
    // ==========================================
    ContentSection {
        icon: "near_me"
        title: Translation.tr("Pointer & Cursor Appearance")

        ContentSubsection {
            title: Translation.tr("Cursor Size")
            tooltip: Translation.tr("Adjusts pointer scale across Wayland, GTK, and Qt applications")

            ConfigSelectionArray {
                currentValue: Config.options.mouse.cursorSize || 24
                onSelected: newValue => {
                    Config.options.mouse.cursorSize = newValue;
                    updateField("cursorSize", newValue);
                }
                options: [
                    { displayName: "16 px", value: 16 },
                    { displayName: "20 px", value: 20 },
                    { displayName: "24 px (Default)", value: 24 },
                    { displayName: "28 px", value: 28 },
                    { displayName: "32 px", value: 32 },
                    { displayName: "48 px (Large)", value: 48 }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Cursor Theme")
            tooltip: Translation.tr("Select installed cursor theme")

            ConfigSelectionArray {
                currentValue: Config.options.mouse.cursorTheme || "Bibata-Modern-Classic"
                onSelected: newValue => {
                    Config.options.mouse.cursorTheme = newValue;
                    updateField("cursorTheme", newValue);
                }
                options: mouseConfigPage.availableCursorThemes.map(t => ({
                    displayName: t,
                    value: t,
                    icon: "mouse"
                }))
            }
        }

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "keyboard"
                text: Translation.tr("Hide cursor while typing")
                checked: Config.options.mouse.hideOnKeyPress
                onCheckedChanged: {
                    Config.options.mouse.hideOnKeyPress = checked;
                    updateField("hideOnKeyPress", checked);
                }
                StyledToolTip {
                    text: Translation.tr("Hides pointer when typing in text editors and terminals to prevent obstruction")
                }
            }

            ConfigSwitch {
                buttonIcon: "lock_open"
                text: Translation.tr("Prevent cursor warping (No Warps)")
                checked: Config.options.mouse.noWarps
                onCheckedChanged: {
                    Config.options.mouse.noWarps = checked;
                    updateField("noWarps", checked);
                }
                StyledToolTip {
                    text: Translation.tr("Prevents cursor from automatically jumping to window center on focus changes")
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Automatically Hide Cursor (Inactive Timeout)")
            tooltip: Translation.tr("Hides cursor when mouse hasn't moved for specified duration")

            ConfigSelectionArray {
                currentValue: Config.options.mouse.inactiveTimeout || 0
                onSelected: newValue => {
                    Config.options.mouse.inactiveTimeout = newValue;
                    updateField("inactiveTimeout", newValue);
                }
                options: [
                    { displayName: Translation.tr("Never (0s)"), value: 0 },
                    { displayName: "3s", value: 3 },
                    { displayName: "5s", value: 5 },
                    { displayName: "10s", value: 10 },
                    { displayName: "30s", value: 30 }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Window Focus on Pointer Hover (Follow Mouse)")
            tooltip: Translation.tr("Controls how window focus follows cursor movement")

            ConfigSelectionArray {
                currentValue: Config.options.mouse.followMouse || 1
                onSelected: newValue => {
                    Config.options.mouse.followMouse = newValue;
                    updateField("followMouse", newValue);
                }
                options: [
                    { displayName: Translation.tr("Click to Focus (0)"), icon: "ads_click", value: 0 },
                    { displayName: Translation.tr("Focus Follows Cursor (1)"), icon: "near_me", value: 1 },
                    { displayName: Translation.tr("Focus Detached Hover (2)"), icon: "open_in_browser", value: 2 }
                ]
            }
        }

        ConfigSwitch {
            buttonIcon: "wb_sunny"
            text: Translation.tr("Mouse movement wakes screen from sleep")
            checked: Config.options.mouse.mouseMoveEnablesDpms
            onCheckedChanged: {
                Config.options.mouse.mouseMoveEnablesDpms = checked;
                updateField("mouseMoveEnablesDpms", checked);
            }
            StyledToolTip {
                text: Translation.tr("Wakes monitors immediately when mouse or touchpad is moved")
            }
        }
    }

    // ==========================================
    // SECTION 6: Live Testing & Benchmark Playground
    // ==========================================
    ContentSection {
        icon: "sports_esports"
        title: Translation.tr("Live Testing & Benchmark Playground")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colOnLayer0
            font.pixelSize: Appearance.font.pixelSize.small
            text: Translation.tr("Test click latency, polling rate estimate, and cursor tracking smoothness below:")
        }

        // Click latency & buttons row
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 110
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2

            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                // Left Click
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.small
                    color: leftClickArea.pressed ? Appearance.colors.colPositive : Appearance.colors.colLayer3

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            iconSize: 24
                            text: "mouse"
                            color: leftClickArea.pressed ? "#ffffff" : Appearance.colors.colOnLayer3
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("Left Click")
                            font.weight: Font.DemiBold
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: leftClickArea.pressed ? "#ffffff" : Appearance.colors.colOnLayer3
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: mouseConfigPage.testLeftClicks.toString()
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: leftClickArea.pressed ? "#ffffff" : Appearance.colors.colOnLayer3
                        }
                    }

                    MouseArea {
                        id: leftClickArea
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        onClicked: {
                            mouseConfigPage.testLeftClicks++;
                            let now = Date.now();
                            if (mouseConfigPage.lastClickTime > 0) {
                                let diff = now - mouseConfigPage.lastClickTime;
                                if (diff < 600) mouseConfigPage.lastDoubleDuration = diff;
                            }
                            mouseConfigPage.lastClickTime = now;
                        }
                    }
                }

                // Middle Click
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.small
                    color: midClickArea.pressed ? (Appearance.colors.colWarning || "#ff9800") : Appearance.colors.colLayer3

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            iconSize: 24
                            text: "radio_button_checked"
                            color: midClickArea.pressed ? "#ffffff" : Appearance.colors.colOnLayer3
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("Middle Click")
                            font.weight: Font.DemiBold
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: midClickArea.pressed ? "#ffffff" : Appearance.colors.colOnLayer3
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: mouseConfigPage.testMiddleClicks.toString()
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: midClickArea.pressed ? "#ffffff" : Appearance.colors.colOnLayer3
                        }
                    }

                    MouseArea {
                        id: midClickArea
                        anchors.fill: parent
                        acceptedButtons: Qt.MiddleButton
                        onClicked: mouseConfigPage.testMiddleClicks++
                    }
                }

                // Right Click
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.small
                    color: rightClickArea.pressed ? Appearance.colors.colPrimary : Appearance.colors.colLayer3

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            iconSize: 24
                            text: "mouse"
                            color: rightClickArea.pressed ? "#ffffff" : Appearance.colors.colOnLayer3
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("Right Click")
                            font.weight: Font.DemiBold
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: rightClickArea.pressed ? "#ffffff" : Appearance.colors.colOnLayer3
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: mouseConfigPage.testRightClicks.toString()
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: rightClickArea.pressed ? "#ffffff" : Appearance.colors.colOnLayer3
                        }
                    }

                    MouseArea {
                        id: rightClickArea
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        onClicked: mouseConfigPage.testRightClicks++
                    }
                }

                // Scroll wheel test
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer3

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            iconSize: 24
                            text: "swap_vert"
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("Scroll Test")
                            font.weight: Font.DemiBold
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer3
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: `${mouseConfigPage.lastScrollDirection} (${mouseConfigPage.testScrollCount})`
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colPrimary
                        }
                    }

                    WheelHandler {
                        onWheel: event => {
                            mouseConfigPage.testScrollCount++;
                            mouseConfigPage.lastScrollDirection = event.angleDelta.y > 0 ? "Up ↑" : "Down ↓";
                        }
                    }
                }

                // Double Click Latency
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer3

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            iconSize: 24
                            text: "timer"
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("Double Click")
                            font.weight: Font.DemiBold
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer3
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: mouseConfigPage.lastDoubleDuration > 0 ? (mouseConfigPage.lastDoubleDuration + " ms") : "-"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }
        }

        // Live Cursor Tracking & Smoothness Test Canvas
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 120
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2
            clip: true

            StyledText {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.margins: 10
                text: Translation.tr("Tracking Canvas: Move or drag mouse here to test smoothness & polling rate")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOnLayer2
            }

            StyledText {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 10
                text: (mouseConfigPage.estimatedPollingRate > 0 ? `${mouseConfigPage.estimatedPollingRate} Hz • ` : "") + Translation.tr("Live")
                font.weight: Font.DemiBold
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colPrimary
            }

            // Tracking visual circle
            Rectangle {
                id: trackingCursor
                width: 24
                height: 24
                radius: 12
                color: Appearance.colors.colPrimary
                opacity: 0.75
                x: parent.width / 2 - 12
                y: parent.height / 2 - 12

                Behavior on x {
                    NumberAnimation { duration: 15 }
                }
                Behavior on y {
                    NumberAnimation { duration: 15 }
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.CrossCursor
                onPositionChanged: mouse => {
                    trackingCursor.x = mouse.x - 12;
                    trackingCursor.y = mouse.y - 12;

                    let now = Date.now();
                    if (mouseConfigPage.lastMoveTime > 0) {
                        let dt = now - mouseConfigPage.lastMoveTime;
                        if (dt > 0 && dt < 100) {
                            let hz = Math.round(1000 / dt);
                            mouseConfigPage.estimatedPollingRate = Math.min(1000, hz);
                        }
                    }
                    mouseConfigPage.lastMoveTime = now;
                }
            }
        }
    }
}
