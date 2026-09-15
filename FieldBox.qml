import QtQuick 2.0
import QtQuick.Controls 2.1
import "."

// 主题化参数输入框：上方标签 + 下方数值，editable=true 时可编辑
Rectangle {
    id: root

    property string label: ""
    property alias text: textInput.text
    property bool editable: false

    implicitWidth: 96
    implicitHeight: 46
    radius: 6
    color: Theme.cardBg
    border.width: 1
    border.color: Theme.cardBorder

    Text {
        id: labelText
        anchors.top: parent.top
        anchors.topMargin: 3
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.label
        font.pixelSize: 11
        color: Theme.textDim
    }

    TextInput {
        id: textInput
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.pixelSize: 14
        font.bold: true
        color: root.enabled ? Theme.text : Theme.textDisabled
        readOnly: !root.editable
        selectByMouse: true
        validator: DoubleValidator {
            notation: DoubleValidator.StandardNotation
        }
    }
}
