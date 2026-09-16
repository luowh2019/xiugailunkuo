import QtQuick 2.0
import QtQuick.Controls 2.1
import "."

// 主题化参数输入框：标签与数值同一行横排，editable=true 时可编辑
Rectangle {
    id: root

    property string label: ""
    property alias text: textInput.text
    property bool editable: false

    implicitWidth: 132
    implicitHeight: 30
    radius: 6
    color: Theme.cardBg
    border.width: 1
    border.color: Theme.cardBorder

    Text {
        id: labelText
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        font.pixelSize: 11
        color: Theme.textDim
    }

    TextInput {
        id: textInput
        anchors.left: labelText.right
        anchors.leftMargin: 6
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        verticalAlignment: Text.AlignVCenter
        font.pixelSize: 13
        font.bold: true
        color: root.enabled ? Theme.text : Theme.textDisabled
        readOnly: !root.editable
        selectByMouse: true
        validator: DoubleValidator {
            notation: DoubleValidator.StandardNotation
        }
    }
}
