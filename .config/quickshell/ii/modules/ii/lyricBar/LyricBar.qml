pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: root

    // ==========================================
    // 1. Theme Configuration (Sync with Dotfiles Theme.qml)
    // ==========================================
    readonly property string fontMain: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "JetBrains Mono"
    readonly property string fontIcon: (typeof Theme !== "undefined" && Theme.iconFont) ? Theme.iconFont : "JetBrainsMono Nerd Font"
    readonly property color colBg: (typeof Theme !== "undefined" && Theme.bg) ? Theme.bg : Qt.rgba(0.04, 0.06, 0.04, 0.82)
    readonly property color colBgCard: (typeof Theme !== "undefined" && Theme.bgCard) ? Theme.bgCard : "#181d18"
    readonly property color colBorder: (typeof Theme !== "undefined" && Theme.border) ? Theme.border : "#414941"
    readonly property color colBorderAccent: (typeof Theme !== "undefined" && Theme.borderAccent) ? Theme.borderAccent : "#414941"
    readonly property color colText: (typeof Theme !== "undefined" && Theme.text) ? Theme.text : "#dfe4dc"
    readonly property color colTextDim: (typeof Theme !== "undefined" && Theme.textDim) ? Theme.textDim : "#c1c9bf"
    readonly property color colTextFaint: (typeof Theme !== "undefined" && Theme.textFaint) ? Theme.textFaint : "#8b938a"
    readonly property color colAccent: (typeof Theme !== "undefined" && Theme.accent) ? Theme.accent : "#97d5a5"
    readonly property color colAccent2: (typeof Theme !== "undefined" && Theme.accent2) ? Theme.accent2 : "#b6ccb8"
    readonly property color colDanger: (typeof Theme !== "undefined" && Theme.danger) ? Theme.danger : "#ffb4ab"
    readonly property int cornerRadius: (typeof Theme !== "undefined" && Theme.radius) ? Theme.radius : 10
    readonly property int animFast: (typeof Theme !== "undefined" && Theme.animFast) ? Theme.animFast : 120
    readonly property int animMed: (typeof Theme !== "undefined" && Theme.animMed) ? Theme.animMed : 220
    readonly property int animSlow: (typeof Theme !== "undefined" && Theme.animSlow) ? Theme.animSlow : 380

    // ==========================================
    // 2. State & Visibility Control
    // ==========================================
    property bool showing: true            // Master toggle: bisa di-hide / di-show
    property bool compact: false            // Mode mini/pill mungil vs bar lengkap
    property bool autoHideOnStop: true      // Sembunyi otomatis jika musik mati
    property real tiltX: 0
    property real tiltY: 0

    // Media & Lyric data
    property string activeLyric: ""
    property string displayedLyric: ""
    property string nextLyric: ""
    property string trackTitle: ""
    property string trackArtist: ""
    property string playbackStatus: "Stopped"
    property bool hasLyrics: false
    property real progress: 0.0

    readonly property bool isPlaying: playbackStatus === "Playing"
    readonly property bool hasMedia: trackTitle !== "" && playbackStatus !== "Stopped"
    readonly property bool effectiveVisible: showing && (!autoHideOnStop || hasMedia)

    // ==========================================
    // 3. Layer Shell Window Positioning
    // ==========================================
    anchors {
        bottom: true
        left: true
        right: true
    }
    margins {
        bottom: 24
    }
    implicitHeight: 52
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:lyricbar"

    // Click mask: Hanya kapsul aktif yang menerima event klik, area lain tembus klik
    mask: Region {
        item: root.effectiveVisible ? (root.compact ? miniPill : lyricCard) : null
    }

    // ==========================================
    // 4. IPC Handler (Keybinding / Terminal Command)
    // ==========================================
    IpcHandler {
        target: "lyricbar"
        function toggle(): void { root.showing = !root.showing; }
        function show(): void { root.showing = true; }
        function hide(): void { root.showing = false; }
        function toggleMini(): void { root.compact = !root.compact; }
    }

    // Process untuk kontrol Playerctl
    Process {
        id: mediaActionProcess
        function run(args) {
            command = args;
            running = true;
        }
    }

    // ==========================================
    // 5. Background Process: Lyric Listener
    // ==========================================
    Process {
        id: lyricProcess
        command: [
            "python3",
            Quickshell.env("HOME") + "/Downloads/dotfiles/.config/quickshell/lyricbar/lyric_listener.py"
        ]
        running: true

        stdout: SplitParser {
            onRead: data => {
                const line = data.trim();
                if (!line) return;
                try {
                    const info = JSON.parse(line);
                    root.activeLyric = info.text || "";
                    root.nextLyric = info.next || "";
                    root.trackTitle = info.title || "";
                    root.trackArtist = info.artist || "";
                    root.playbackStatus = info.status || "Stopped";
                    root.hasLyrics = info.hasLyrics ?? (root.activeLyric.length > 0);
                    root.progress = info.progress || 0.0;
                } catch (e) {
                    root.activeLyric = line;
                }
            }
        }

        onExited: {
            if (root.showing) restartTimer.restart();
        }
    }

    Timer {
        id: restartTimer
        interval: 1500
        repeat: false
        onTriggered: {
            if (!lyricProcess.running) lyricProcess.running = true;
        }
    }

    // Animasi Pergantian Teks Lirik yang Mulus (Cross-fade & Slide)
    onActiveLyricChanged: {
        const target = root.activeLyric !== "" 
            ? root.activeLyric 
            : (root.trackTitle !== "" ? (root.trackArtist ? root.trackArtist + " - " + root.trackTitle : root.trackTitle) : "");

        if (target !== root.displayedLyric) {
            if (root.displayedLyric === "") {
                root.displayedLyric = target;
                lyricLabel.opacity = 1.0;
                lyricLabel.y = 0;
            } else {
                lyricAnim.restart();
            }
        }
    }

    SequentialAnimation {
        id: lyricAnim
        ParallelAnimation {
            NumberAnimation {
                target: lyricLabel
                property: "opacity"
                to: 0.0
                duration: Math.round(root.animFast * 0.9)
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: lyricLabel
                property: "y"
                to: -7
                duration: Math.round(root.animFast * 0.9)
                easing.type: Easing.OutQuad
            }
        }
        ScriptAction {
            script: {
                const target = root.activeLyric !== "" 
                    ? root.activeLyric 
                    : (root.trackTitle !== "" ? (root.trackArtist ? root.trackArtist + " - " + root.trackTitle : root.trackTitle) : "");
                root.displayedLyric = target;
                lyricLabel.y = 7;
            }
        }
        ParallelAnimation {
            NumberAnimation {
                target: lyricLabel
                property: "opacity"
                to: 1.0
                duration: root.animMed
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: lyricLabel
                property: "y"
                to: 0
                duration: root.animMed
                easing.type: Easing.OutCubic
            }
        }
    }

    // ==========================================
    // 6. Komponen Tombol Ikon (Sesuai Standar Dotfiles IconBtn)
    // ==========================================
    component ActionBtn: Rectangle {
        id: abtn
        property string icon: ""
        property color iconColor: root.colTextDim
        property color hoverColor: root.colAccent
        signal clicked()

        implicitWidth: 24
        implicitHeight: 24
        radius: 6
        color: btnArea.containsMouse ? Qt.alpha(root.colText, 0.12) : "transparent"

        Behavior on color { ColorAnimation { duration: root.animFast } }

        Text {
            anchors.centerIn: parent
            text: abtn.icon
            font.family: root.fontIcon
            font.pixelSize: 12
            color: btnArea.containsMouse ? abtn.hoverColor : abtn.iconColor
            Behavior on color { ColorAnimation { duration: root.animFast } }
        }

        MouseArea {
            id: btnArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: abtn.clicked()
        }
    }

    // ==========================================
    // 7. Visual Card Utama: Floating LyricBar Island
    // ==========================================
    Rectangle {
        id: lyricCard
        visible: root.effectiveVisible && !root.compact
        opacity: visible ? 1.0 : 0.0
        scale: visible ? 1.0 : 0.92

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        height: 40

        // Lebar dinamis responsif dengan pembatas min & max
        implicitWidth: Math.max(280, Math.min(680, cardLayout.implicitWidth + 24))
        Behavior on implicitWidth {
            NumberAnimation { duration: root.animMed; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: root.animMed; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: root.animSlow; easing.type: Easing.OutBack }
        }

        color: root.colBg
        radius: root.cornerRadius
        border.color: cardMouseArea.containsMouse ? root.colAccent : root.colBorder
        border.width: 1
        clip: true

        Behavior on border.color {
            ColorAnimation { duration: root.animMed }
        }

        // Efek Parallax Tilt 3D (Identik dengan PerspectivePanel.qml di dotfiles)
        transform: [
            Rotation {
                origin.x: lyricCard.width / 2
                origin.y: lyricCard.height / 2
                axis { x: 1; y: 0; z: 0 }
                angle: root.tiltX
                Behavior on angle { NumberAnimation { duration: root.animMed; easing.type: Easing.OutCubic } }
            },
            Rotation {
                origin.x: lyricCard.width / 2
                origin.y: lyricCard.height / 2
                axis { x: 0; y: 1; z: 0 }
                angle: root.tiltY
                Behavior on angle { NumberAnimation { duration: root.animMed; easing.type: Easing.OutCubic } }
            }
        ]

        // Progress bar mini di bagian bawah pill
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            height: 2
            width: parent.width * Math.max(0.0, Math.min(1.0, root.progress))
            color: root.colAccent
            opacity: 0.75

            Behavior on width { NumberAnimation { duration: 120 } }
        }

        // Mouse Area untuk kontrol interaktif & Parallax Hover
        MouseArea {
            id: cardMouseArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

            onPositionChanged: mouse => {
                var nx = (mouse.x / lyricCard.width) - 0.5;
                var ny = (mouse.y / lyricCard.height) - 0.5;
                root.tiltX = -ny * 6;
                root.tiltY = nx * 6;
            }

            onExited: {
                root.tiltX = 0;
                root.tiltY = 0;
            }

            onClicked: mouse => {
                if (mouse.button === Qt.MiddleButton) {
                    mediaActionProcess.run(["playerctl", "previous"]);
                } else if (mouse.button === Qt.RightButton) {
                    mediaActionProcess.run(["playerctl", "next"]);
                }
            }

            onWheel: wheel => {
                if (wheel.angleDelta.y > 0) {
                    mediaActionProcess.run(["playerctl", "volume", "0.05+"]);
                } else if (wheel.angleDelta.y < 0) {
                    mediaActionProcess.run(["playerctl", "volume", "0.05-"]);
                }
            }
        }

        // Tata Letak Konten di Dalam Kapsul
        RowLayout {
            id: cardLayout
            anchors.centerIn: parent
            spacing: 8

            // 1. Play / Pause & Disc Icon
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 26
                implicitHeight: 26
                radius: 13
                color: Qt.alpha(root.colAccent, playBtnArea.containsMouse ? 0.35 : 0.15)

                Behavior on color { ColorAnimation { duration: root.animFast } }

                Text {
                    anchors.centerIn: parent
                    font.family: root.fontIcon
                    font.pixelSize: 12
                    renderType: Text.NativeRendering
                    color: root.colAccent
                    text: root.isPlaying ? "\udb81\udc0a" : "\udb80\udfe4"
                }

                MouseArea {
                    id: playBtnArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mediaActionProcess.run(["playerctl", "play-pause"])
                }
            }

            // 2. Info Artis / Lagu (Badge Bergaya Dotfiles)
            Rectangle {
                visible: root.trackArtist !== ""
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: 22
                implicitWidth: artistBadgeText.implicitWidth + 14
                radius: 6
                color: root.colBgCard
                border.color: root.colBorder
                border.width: 1

                Text {
                    id: artistBadgeText
                    anchors.centerIn: parent
                    font.family: root.fontMain
                    font.pixelSize: 10
                    font.bold: true
                    renderType: Text.NativeRendering
                    color: root.colTextDim
                    text: root.trackArtist
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            // 3. Titik Pemisah Minimalis
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 3
                implicitHeight: 3
                radius: 1.5
                color: root.colTextFaint
            }

            // 4. Baris Lirik Aktif dengan Animasi Halus
            Item {
                id: lyricContainer
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                implicitHeight: 22
                implicitWidth: Math.min(380, lyricLabel.implicitWidth)
                clip: true

                Text {
                    id: lyricLabel
                    anchors.centerIn: parent
                    renderType: Text.NativeRendering
                    font.family: root.fontMain
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    color: root.activeLyric !== "" ? root.colText : root.colAccent2
                    text: root.displayedLyric !== "" ? root.displayedLyric : (root.isPlaying ? "\u266a \u266a \u266a" : "No media playing")
                    elide: Text.ElideRight
                    maximumLineCount: 1

                    Behavior on color { ColorAnimation { duration: root.animMed } }
                }
            }

            // 5. Indikator Pulsa Lirik Tersinkron
            Rectangle {
                visible: root.hasLyrics && root.isPlaying
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 6
                implicitHeight: 6
                radius: 3
                color: root.colAccent

                SequentialAnimation on opacity {
                    running: root.hasLyrics && root.isPlaying
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.3; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 1.0; to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                }
            }

            // 6. Tombol Aksi Mini (Sembunyikan / Perkecil)
            Row {
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                // Tombol Minimize ke Pill Kapsul Mini
                ActionBtn {
                    icon: "\udb80\udfd4" // Nerd Font: Compress / Minimize
                    onClicked: root.compact = true
                }

                // Tombol Close / Hide Penuh
                ActionBtn {
                    icon: "\udb80\udf5b" // Nerd Font: Close / X
                    hoverColor: root.colDanger
                    onClicked: root.showing = false
                }
            }
        }
    }

    // ==========================================
    // 8. Mode Mini: Pill Kapsul Mungil saat Di-Minimize
    // ==========================================
    Rectangle {
        id: miniPill
        visible: root.effectiveVisible && root.compact
        opacity: visible ? 1.0 : 0.0
        scale: visible ? 1.0 : 0.85

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        height: 32
        implicitWidth: 38

        radius: 16
        color: root.colBg
        border.color: miniArea.containsMouse ? root.colAccent : root.colBorder
        border.width: 1

        Behavior on opacity { NumberAnimation { duration: root.animFast } }
        Behavior on scale { NumberAnimation { duration: root.animMed; easing.type: Easing.OutBack } }
        Behavior on border.color { ColorAnimation { duration: root.animFast } }

        Text {
            anchors.centerIn: parent
            font.family: root.fontIcon
            font.pixelSize: 13
            renderType: Text.NativeRendering
            color: root.isPlaying ? root.colAccent : root.colTextDim
            text: "\udb80\udfe4" // Nerd Font Music Note / Disc
        }

        MouseArea {
            id: miniArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.compact = false // Klik untuk membesarkan kembali
        }
    }
}
