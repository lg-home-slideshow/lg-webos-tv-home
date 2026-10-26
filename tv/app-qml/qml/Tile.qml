// Tile.qml - one app or input: its colour, its icon, a lift when focused, the
// name underneath, a wobble while being moved.
import QtQuick 2.12
import QtGraphicalEffects 1.0

Item {
    id: tile

    property var item: null            // { name, color, icon, ... } from server.js
    property string server: ""
    property bool focused: false
    property bool lifted: false
    property bool dimmed: false        // hidden apps
    property string label: item ? item.name : ""
    property real radius: 26
    property string fontFamily: ""
    property int labelGap: 22          // from the tile's bottom to its name

    signal hovered()
    signal clicked()
    signal held()

    z: focused || lifted ? 3 : 0

    // Lift: a little up and a little bigger; more while being moved.
    transform: Translate { y: tile.lifted ? -12 : tile.focused ? -8 : 0
        Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } } }
    scale: lifted ? 1.1 : focused ? 1.08 : 1
    Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

    SequentialAnimation on rotation {
        running: tile.lifted
        loops: Animation.Infinite
        NumberAnimation { from: -1.4; to: 1.4; duration: 320; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1.4; to: -1.4; duration: 320; easing.type: Easing.InOutSine }
        onStopped: tile.rotation = 0
    }

    RectangularGlow {
        anchors.fill: face
        anchors.topMargin: tile.focused ? 14 : 6
        anchors.bottomMargin: tile.focused ? -14 : -6
        glowRadius: tile.focused ? 26 : 12
        spread: 0.08
        cornerRadius: tile.radius + glowRadius
        color: "black"
        opacity: tile.focused ? 0.55 : 0.3
        Behavior on opacity { NumberAnimation { duration: 280 } }
    }

    Rectangle {
        id: face
        anchors.fill: parent
        radius: tile.radius
        // an icon with its own background (Emby, Spotify) fills the tile, in that colour
        property bool fill: !!(tile.item && tile.item.fill)
        color: fill ? tile.item.fill : tile.item && tile.item.color ? tile.item.color : "#2a2a30"
        opacity: tile.dimmed && !tile.focused ? 0.45 : 1

        Image {
            id: icon
            anchors.centerIn: parent
            width: parent.fill ? parent.width : parent.width * 0.64
            height: parent.fill ? parent.height : parent.height * 0.74
            source: tile.item && tile.item.icon ? tile.server + tile.item.icon : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            mipmap: true
            visible: status === Image.Ready
        }
        Text {
            anchors.centerIn: parent
            visible: !icon.visible
            text: tile.item && tile.item.name ? tile.item.name.charAt(0) : "?"
            color: "#ebffffff"
            font.pixelSize: parent.height * 0.4
            font.family: tile.fontFamily
            font.bold: true
        }
        // the focus frame, over the icon (an icon filling the tile's height
        // would otherwise cover it)
        Rectangle {
            anchors.fill: parent
            radius: tile.radius
            color: "transparent"
            border.width: tile.lifted ? 4 : tile.focused ? 3 : 0
            border.color: tile.lifted ? "#ffd34d" : "white"
        }
    }

    Text {
        anchors.top: face.bottom
        anchors.topMargin: tile.labelGap
        anchors.horizontalCenter: face.horizontalCenter
        text: tile.label
        color: "white"
        font.pixelSize: 25
        font.family: tile.fontFamily
        font.weight: Font.DemiBold
        opacity: tile.focused ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 220 } }
        style: Text.Raised
        styleColor: "#66000000"
    }

    // Magic Remote pointer: hover focuses, click opens, a long press = options.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        pressAndHoldInterval: 650
        onEntered: tile.hovered()
        onClicked: tile.clicked()
        onPressAndHold: tile.held()
    }
}
