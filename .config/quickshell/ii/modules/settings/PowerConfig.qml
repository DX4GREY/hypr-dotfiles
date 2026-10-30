import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: powerConfigPage
    forceWidth: true

    property var batteryInfo: ({})

    function profileToString(prof) {
        switch(prof) {
            case PowerProfile.PowerSaver: return "power-saver";
            case PowerProfile.Performance: return "performance";
            case PowerProfile.Balanced:
            default: return "balanced";
        }
    }

    function stringToProfile(str) {
        switch(str) {
            case "power-saver": return PowerProfile.PowerSaver;
            case "performance": return PowerProfile.Performance;
            case "balanced":
            default: return PowerProfile.Balanced;
        }
    }

    function applyIdleSettings() {
        Quickshell.execDetached([
            "python3",
            Directories.powerManagerScript,
            "set-idle",
            "--lock", Config.options.power.lockTimeout.toString(),
            "--sleep", Config.options.power.sleepTimeout.toString(),
            "--suspend", Config.options.power.suspendTimeout.toString(),
            "--enable-lock", Config.options.power.enableLock ? "1" : "0",
            "--enable-sleep", Config.options.power.enableSleep ? "1" : "0",
            "--enable-suspend", Config.options.power.enableSuspend ? "1" : "0",
            "--enable-dim", Config.options.power.enableDim ? "1" : "0",
            "--dim-seconds", (Config.options.power.dimBeforeSleepSeconds || 30).toString()
        ]);
    }

    function applyProfile(newProfile) {
        Config.options.power.profile = newProfile;
        try {
            PowerProfiles.profile = stringToProfile(newProfile);
        } catch (e) {
            console.log("Error updating PowerProfiles:", e);
        }
        Quickshell.execDetached([
            "python3",
            Directories.powerManagerScript,
            "set-profile",
            newProfile
        ]);
    }

    function applyChargeLimit(limitVal) {
        Config.options.power.chargeLimit = limitVal;
        Quickshell.execDetached([
            "python3",
            Directories.powerManagerScript,
            "set-charge-threshold",
            limitVal.toString()
        ]);
    }

    // Process to read initial power settings & battery details
    Process {
        id: idleSettingsReader
        command: ["python3", Directories.powerManagerScript, "get"]
        stdout: SplitParser {
            onRead: data => {
                try {
                    let parsed = JSON.parse(data.trim());
                    if (parsed.lock_timeout !== undefined) Config.options.power.lockTimeout = parsed.lock_timeout;
                    if (parsed.sleep_timeout !== undefined) Config.options.power.sleepTimeout = parsed.sleep_timeout;
                    if (parsed.suspend_timeout !== undefined) Config.options.power.suspendTimeout = parsed.suspend_timeout;
                    if (parsed.lock_enabled !== undefined) Config.options.power.enableLock = parsed.lock_enabled;
                    if (parsed.sleep_enabled !== undefined) Config.options.power.enableSleep = parsed.sleep_enabled;
                    if (parsed.suspend_enabled !== undefined) Config.options.power.enableSuspend = parsed.suspend_enabled;
                    if (parsed.dim_enabled !== undefined) Config.options.power.enableDim = parsed.dim_enabled;
                    if (parsed.profile) Config.options.power.profile = parsed.profile;
                    if (parsed.charge_threshold) Config.options.power.chargeLimit = parsed.charge_threshold;
                    if (parsed.battery) powerConfigPage.batteryInfo = parsed.battery;
                } catch(e) {
                    console.log("Could not parse power settings JSON: ", e);
                }
            }
        }
        Component.onCompleted: running = true
    }

    // Periodic telemetry update
    Timer {
        interval: 10000
        repeat: true
        running: true
        onTriggered: {
            batteryPoller.running = true;
        }
    }

    Process {
        id: batteryPoller
        command: ["python3", Directories.powerManagerScript, "get-battery"]
        stdout: SplitParser {
            onRead: data => {
                try {
                    powerConfigPage.batteryInfo = JSON.parse(data.trim());
                } catch(e) {}
            }
        }
    }

    // ==========================================
    // SECTION: Power Profiles / Mode
    // ==========================================
    ContentSection {
        icon: "bolt"
        title: Translation.tr("Power Profiles")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colOnLayer0
            font.pixelSize: Appearance.font.pixelSize.small
            text: Translation.tr("Select a power profile to optimize CPU frequencies, power states, and responsiveness.")
        }

        ConfigSelectionArray {
            currentValue: Config.options.power.profile || profileToString(PowerProfiles.profile)
            onSelected: newValue => {
                applyProfile(newValue);
            }
            options: [
                {
                    displayName: Translation.tr("Battery Saver"),
                    icon: "energy_savings_leaf",
                    value: "power-saver"
                },
                {
                    displayName: Translation.tr("Balanced"),
                    icon: "airwave",
                    value: "balanced"
                },
                {
                    displayName: Translation.tr("Performance"),
                    icon: "local_fire_department",
                    value: "performance"
                }
            ]
        }

        // Active profile explanation card
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: profileDescCol.implicitHeight + 20
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2

            ColumnLayout {
                id: profileDescCol
                anchors {
                    fill: parent
                    margins: 12
                }
                spacing: 4

                RowLayout {
                    spacing: 8
                    MaterialSymbol {
                        iconSize: Appearance.font.pixelSize.larger
                        text: {
                            let prof = Config.options.power.profile || profileToString(PowerProfiles.profile);
                            if (prof === "power-saver") return "energy_savings_leaf";
                            if (prof === "performance") return "local_fire_department";
                            return "airwave";
                        }
                        color: {
                            let prof = Config.options.power.profile || profileToString(PowerProfiles.profile);
                            if (prof === "power-saver") return Appearance.colors.colPositive || "#4caf50";
                            if (prof === "performance") return Appearance.colors.colWarning || "#ff9800";
                            return Appearance.colors.colPrimary;
                        }
                    }
                    StyledText {
                        font.weight: Font.DemiBold
                        font.pixelSize: Appearance.font.pixelSize.normal
                        text: {
                            let prof = Config.options.power.profile || profileToString(PowerProfiles.profile);
                            if (prof === "power-saver") return Translation.tr("Battery Saver Active");
                            if (prof === "performance") return Translation.tr("Performance Mode Active");
                            return Translation.tr("Balanced Mode Active");
                        }
                        color: Appearance.colors.colOnLayer1
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer1
                    text: {
                        let prof = Config.options.power.profile || profileToString(PowerProfiles.profile);
                        if (prof === "power-saver") return Translation.tr("Downscales CPU frequency and forces energy efficiency. Disables aggressive turbo boost to maximize battery life.");
                        if (prof === "performance") return Translation.tr("Maximizes CPU clocks and responsiveness for high-intensity computing and gaming. Increases power draw and fan speeds.");
                        return Translation.tr("Dynamically balances performance and power efficiency. CPU scales frequency smoothly on demand.");
                    }
                }
            }
        }

        // Smart Auto Profile Switching
        ContentSubsection {
            title: Translation.tr("Smart Auto-Switching")
            tooltip: Translation.tr("Automatically switches profile when charger is connected or unplugged")

            ConfigSwitch {
                buttonIcon: "sync"
                text: Translation.tr("Auto-switch profile based on power source")
                checked: Config.options.power.autoSwitchProfile
                onCheckedChanged: {
                    Config.options.power.autoSwitchProfile = checked;
                }
            }

            ColumnLayout {
                enabled: Config.options.power.autoSwitchProfile
                opacity: Config.options.power.autoSwitchProfile ? 1.0 : 0.5
                Layout.fillWidth: true
                spacing: 8

                ContentSubsectionLabel {
                    text: Translation.tr("When plugged in (AC Power)")
                }
                ConfigSelectionArray {
                    currentValue: Config.options.power.profileOnAc || "balanced"
                    onSelected: newValue => {
                        Config.options.power.profileOnAc = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Balanced"),
                            icon: "airwave",
                            value: "balanced"
                        },
                        {
                            displayName: Translation.tr("Performance"),
                            icon: "local_fire_department",
                            value: "performance"
                        }
                    ]
                }

                ContentSubsectionLabel {
                    text: Translation.tr("When on Battery Power")
                }
                ConfigSelectionArray {
                    currentValue: Config.options.power.profileOnBattery || "power-saver"
                    onSelected: newValue => {
                        Config.options.power.profileOnBattery = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Battery Saver"),
                            icon: "energy_savings_leaf",
                            value: "power-saver"
                        },
                        {
                            displayName: Translation.tr("Balanced"),
                            icon: "airwave",
                            value: "balanced"
                        }
                    ]
                }
            }
        }
    }

    // ==========================================
    // SECTION: ASUS Battery Care / Charge Limit
    // ==========================================
    ContentSection {
        visible: Battery.available
        icon: "shield_with_heart"
        title: Translation.tr("Battery Health & Care Limit")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colOnLayer0
            font.pixelSize: Appearance.font.pixelSize.small
            text: Translation.tr("Limit the maximum battery charge level to prolong lithium-ion battery longevity and prevent premature battery degradation.")
        }

        ConfigSelectionArray {
            currentValue: Config.options.power.chargeLimit || 80
            onSelected: newValue => {
                applyChargeLimit(newValue);
            }
            options: [
                {
                    displayName: Translation.tr("Maximum Lifespan (60%)"),
                    icon: "healing",
                    value: 60
                },
                {
                    displayName: Translation.tr("Balanced Care (80%)"),
                    icon: "shield",
                    value: 80
                },
                {
                    displayName: Translation.tr("Full Capacity (100%)"),
                    icon: "battery_charging_full",
                    value: 100
                }
            ]
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: chargeDescCol.implicitHeight + 16
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2

            ColumnLayout {
                id: chargeDescCol
                anchors {
                    fill: parent
                    margins: 10
                }
                spacing: 2

                StyledText {
                    font.weight: Font.DemiBold
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: {
                        let lim = Config.options.power.chargeLimit || 80;
                        if (lim === 60) return Translation.tr("60% Limit - Best for stationary laptops mostly kept plugged into power.");
                        if (lim === 80) return Translation.tr("80% Limit - Recommended for daily productivity. Maximizes lifespan while providing solid runtime.");
                        return Translation.tr("100% Limit - Standard full charge for maximum mobile battery runtime.");
                    }
                    color: Appearance.colors.colOnLayer1
                }
            }
        }
    }

    // ==========================================
    // SECTION: Live Battery Telemetry
    // ==========================================
    ContentSection {
        visible: Battery.available
        icon: "monitor_heart"
        title: Translation.tr("Battery Telemetry & Hardware Status")

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                MaterialSymbol {
                    iconSize: 22
                    text: Battery.isCharging ? "battery_charging_full" : (Battery.isPluggedIn ? "power" : "battery_std")
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    text: Translation.tr("Battery Level")
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
                Item { Layout.fillWidth: true }
                StyledText {
                    text: Math.round(Battery.percentage * 100) + "%" + 
                          (Battery.isCharging ? ` (${Translation.tr("Charging")})` : 
                          (Battery.isPluggedIn ? ` (${Translation.tr("Plugged In")})` : ` (${Translation.tr("Discharging")})`))
                    font.weight: Font.DemiBold
                    color: Battery.isCharging ? Appearance.colors.colPrimary : 
                           (Battery.percentage <= 0.15 ? (Appearance.colors.colError || "#f44336") : Appearance.colors.colOnLayer1)
                }
            }

            StyledProgressBar {
                Layout.fillWidth: true
                value: Battery.percentage
                valueBarHeight: 6
            }

            ConfigRow {
                uniform: true
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 60
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10
                        MaterialSymbol {
                            iconSize: 24
                            text: "favorite"
                            color: Appearance.colors.colPrimary
                        }
                        ColumnLayout {
                            spacing: 2
                            StyledText {
                                text: Translation.tr("Battery Health")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                text: (powerConfigPage.batteryInfo?.health_pct ? (powerConfigPage.batteryInfo.health_pct + "%") : 
                                      (Battery.health > 0 ? (Math.round(Battery.health) + "%") : Translation.tr("Good")))
                                font.weight: Font.DemiBold
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 60
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10
                        MaterialSymbol {
                            iconSize: 24
                            text: "electric_bolt"
                            color: Appearance.colors.colPrimary
                        }
                        ColumnLayout {
                            spacing: 2
                            StyledText {
                                text: Translation.tr("Power Draw Rate")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                text: (powerConfigPage.batteryInfo?.power_w ? powerConfigPage.batteryInfo.power_w : Math.abs(Battery.energyRate)).toFixed(1) + " W"
                                font.weight: Font.DemiBold
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }

            ConfigRow {
                uniform: true
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 60
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10
                        MaterialSymbol {
                            iconSize: 24
                            text: "memory"
                            color: Appearance.colors.colPrimary
                        }
                        ColumnLayout {
                            spacing: 2
                            StyledText {
                                text: Translation.tr("Capacity Full / Design")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                text: (powerConfigPage.batteryInfo?.capacity_full_wh ? `${powerConfigPage.batteryInfo.capacity_full_wh} / ${powerConfigPage.batteryInfo.capacity_design_wh} Wh` : "39.5 / 48.0 Wh")
                                font.weight: Font.DemiBold
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 60
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10
                        MaterialSymbol {
                            iconSize: 24
                            text: "hourglass_top"
                            color: Appearance.colors.colPrimary
                        }
                        ColumnLayout {
                            spacing: 2
                            StyledText {
                                text: Battery.isCharging ? Translation.tr("Time to Full") : Translation.tr("Time Remaining")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                text: {
                                    let secs = Battery.isCharging ? Battery.timeToFull : Battery.timeToEmpty;
                                    if (secs > 0 && secs < 86400) {
                                        let hrs = Math.floor(secs / 3600);
                                        let mins = Math.floor((secs % 3600) / 60);
                                        return `${hrs}h ${mins}m`;
                                    }
                                    return Translation.tr("Calculating...");
                                }
                                font.weight: Font.DemiBold
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }
        }
    }

    // ==========================================
    // SECTION: Screen & Sleep (Hypridle)
    // ==========================================
    ContentSection {
        icon: "bedtime"
        title: Translation.tr("Screen & Sleep Customization")

        ConfigSwitch {
            buttonIcon: "wb_twilight"
            text: Translation.tr("Dim display before sleep")
            checked: Config.options.power.enableDim
            onCheckedChanged: {
                Config.options.power.enableDim = checked;
                applyIdleSettings();
            }
            StyledToolTip {
                text: Translation.tr("Gradually dims screen 30 seconds before sleep as an early warning")
            }
        }

        ConfigSwitch {
            buttonIcon: "tv_off"
            text: Translation.tr("Turn off display when inactive")
            checked: Config.options.power.enableSleep
            onCheckedChanged: {
                Config.options.power.enableSleep = checked;
                applyIdleSettings();
            }
            StyledToolTip {
                text: Translation.tr("Powers down displays after inactivity to save battery and screen life")
            }
        }

        ConfigRow {
            enabled: Config.options.power.enableSleep
            ConfigSpinBox {
                icon: "timer"
                text: Translation.tr("Display sleep timeout (mins)")
                value: Config.options.power.sleepTimeout
                from: 1
                to: 120
                stepSize: 1
                onValueChanged: {
                    Config.options.power.sleepTimeout = value;
                    applyIdleSettings();
                }
            }
        }

        ConfigSwitch {
            buttonIcon: "lock"
            text: Translation.tr("Lock screen before sleep")
            checked: Config.options.power.enableLock
            onCheckedChanged: {
                Config.options.power.enableLock = checked;
                applyIdleSettings();
            }
            StyledToolTip {
                text: Translation.tr("Locks your session when inactive")
            }
        }

        ConfigRow {
            enabled: Config.options.power.enableLock
            ConfigSpinBox {
                icon: "lock_clock"
                text: Translation.tr("Screen lock timeout (mins)")
                value: Config.options.power.lockTimeout
                from: 1
                to: 60
                stepSize: 1
                onValueChanged: {
                    Config.options.power.lockTimeout = value;
                    applyIdleSettings();
                }
            }
        }

        ConfigSwitch {
            buttonIcon: "coffee"
            text: Translation.tr("Keep awake (Idle Inhibitor)")
            checked: Idle.inhibit
            onCheckedChanged: {
                Idle.toggleInhibit(checked);
            }
            StyledToolTip {
                text: Translation.tr("Temporarily blocks screen sleep and automatic locking")
            }
        }
    }

    // ==========================================
    // SECTION: Suspend Customization
    // ==========================================
    ContentSection {
        icon: "power_settings_new"
        title: Translation.tr("Suspend Customization")

        ConfigSwitch {
            buttonIcon: "timelapse"
            text: Translation.tr("Automatic system suspend when idle")
            checked: Config.options.power.enableSuspend
            onCheckedChanged: {
                Config.options.power.enableSuspend = checked;
                applyIdleSettings();
            }
            StyledToolTip {
                text: Translation.tr("Suspends the laptop into low-power sleep state after prolonged inactivity")
            }
        }

        ConfigRow {
            enabled: Config.options.power.enableSuspend
            ConfigSpinBox {
                icon: "hourglass_bottom"
                text: Translation.tr("Idle suspend timeout (mins)")
                value: Config.options.power.suspendTimeout
                from: 2
                to: 240
                stepSize: 5
                onValueChanged: {
                    Config.options.power.suspendTimeout = value;
                    applyIdleSettings();
                }
            }
        }

        ConfigSwitch {
            buttonIcon: "battery_alert"
            text: Translation.tr("Suspend on critical battery level")
            checked: Config.options.battery.automaticSuspend
            onCheckedChanged: {
                Config.options.battery.automaticSuspend = checked;
            }
            StyledToolTip {
                text: Translation.tr("Automatically puts system into sleep when battery drops dangerously low")
            }
        }

        ConfigRow {
            enabled: Config.options.battery.automaticSuspend
            ConfigSpinBox {
                icon: "percent"
                text: Translation.tr("Critical battery suspend threshold (%)")
                value: Config.options.battery.suspend
                from: 1
                to: 20
                stepSize: 1
                onValueChanged: {
                    Config.options.battery.suspend = value;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Battery Warning Thresholds")
            ConfigRow {
                uniform: true
                ConfigSpinBox {
                    icon: "warning"
                    text: Translation.tr("Low warning (%)")
                    value: Config.options.battery.low
                    from: 5
                    to: 50
                    stepSize: 5
                    onValueChanged: {
                        Config.options.battery.low = value;
                    }
                }
                ConfigSpinBox {
                    icon: "dangerous"
                    text: Translation.tr("Critical warning (%)")
                    value: Config.options.battery.critical
                    from: 1
                    to: 30
                    stepSize: 1
                    onValueChanged: {
                        Config.options.battery.critical = value;
                    }
                }
            }
        }
    }

    // ==========================================
    // SECTION: Quick Power Actions
    // ==========================================
    ContentSection {
        icon: "touch_app"
        title: Translation.tr("Quick Power Actions")

        Flow {
            Layout.fillWidth: true
            spacing: 8

            RippleButtonWithIcon {
                materialIcon: "bedtime"
                mainText: Translation.tr("Suspend Now")
                onClicked: {
                    Quickshell.execDetached(["python3", Directories.powerManagerScript, "suspend"]);
                }
                StyledToolTip {
                    text: Translation.tr("Put laptop into suspend immediately")
                }
            }

            RippleButtonWithIcon {
                materialIcon: "display_settings"
                mainText: Translation.tr("Turn Off Screen")
                onClicked: {
                    Quickshell.execDetached(["python3", Directories.powerManagerScript, "sleep"]);
                }
                StyledToolTip {
                    text: Translation.tr("Turn off display immediately")
                }
            }

            RippleButtonWithIcon {
                materialIcon: "lock"
                mainText: Translation.tr("Lock Session")
                onClicked: {
                    Quickshell.execDetached(["python3", Directories.powerManagerScript, "lock"]);
                }
                StyledToolTip {
                    text: Translation.tr("Lock the screen now")
                }
            }

            RippleButtonWithIcon {
                materialIcon: "save"
                mainText: Translation.tr("Hibernate Now")
                onClicked: {
                    Quickshell.execDetached(["python3", Directories.powerManagerScript, "hibernate"]);
                }
                StyledToolTip {
                    text: Translation.tr("Save session to swap disk and power off")
                }
            }
        }
    }
}
