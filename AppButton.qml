import QtQuick 2.0
import QtQuick.Controls 2.1
import "."

// 主题化按钮：primary=true 时使用强调色填充，否则为描边卡片式
Button {
    id: control

    property bool primary: false
    property color accentColor: Theme.accent

    implicitWidth: Math.max(92, contentItem.implicitWidth + 28)
    implicitHeight: 34

    contentItem: Text {
        text: control.text
        font.pixelSize: 13
        font.bold: control.primary
        color: {
            if (!control.enabled) return Theme.textDisabled
            if (control.primary) return Theme.onAccent
            return Theme.text
        }
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    background: Rectangle {
        radius: 6
        color: {
            if (!control.enabled) return Theme.cardBg
            if (control.pressed) return control.primary ? Qt.darker(control.accentColor, 1.15) : Theme.pressed
            if (control.hovered) return control.primary ? Qt.lighter(control.accentColor, 1.08) : Theme.hover
            return control.primary ? control.accentColor : Theme.cardBg
        }
        border.width: control.primary ? 0 : 1
        border.color: Theme.cardBorder
    }
}
