import QtQuick 2.0
import QtQuick.Controls 2.1
import Qt5Compat.GraphicalEffects 6.0//解决DrowShadow不能用的问题
import "."
Canvas {
    id: canvas
    // 存储点击的点
    property point point1: Qt.point(-1, -1)  // 初始为无效坐标  // 第一个点
    property point point2: Qt.point(-1, -1)  // 初始为无效坐标  // 第二个点
    property real lineWidth: 0 // 水平像素（宽度）
    property real lineHeight: 0// 垂直像素（高度）
    property bool hasStartPoint: false
    property string url: ""
    property bool showImage: false
    property bool dialog_out: false
    property alias img_bd:backgroundImage.source
    signal pix_xiebianChanged(real var1,real var2)
    property alias tip_box_text:tipBox_text.text
    Image {
        id: backgroundImage
        visible: false // 隐藏原图，仅用于数据源
        onStatusChanged:{
            if (backgroundImage.status === Image.Ready) {
                canvas.requestPaint()
                }
            }
        }
    onPaint: {

        const ctx = canvas.getContext("2d")
        ctx.clearRect(0, 0, canvas.width, canvas.height)
        ctx.drawImage(backgroundImage, 0, 0, canvas.width, canvas.height)

        canvas.draw_circle_1(ctx)

        canvas.draw_line(ctx)
        }
    MouseArea {
        id:mouseArea
        cursorShape:Qt.CrossCursor
        anchors.fill: parent
        hoverEnabled: true  // 必须开启，才能检测鼠标悬停
        onEntered:ToolTip.show("点击鼠标左键两次绘制直线：第一次选起点，第二次选终点，右键退出")
        onExited:ToolTip.hide()
        acceptedButtons:Qt.LeftButton|Qt.RightButton

        onClicked: (mouse)=>{
            // 获取鼠标在画布内的坐标（修正偏移）
            const x = mouseX
            const y = mouseY
            const ctx = canvas.getContext("2d")

            if (mouse.button == Qt.LeftButton) {
                // 记录第一个点
                if (!canvas.hasStartPoint) {
                    canvas.point1 = Qt.point(x, y)
                    canvas.hasStartPoint = true
                    canvas.requestPaint()
                    }
                // 记录第二个点并绘制连线
                else {
                    canvas.point2 = Qt.point(x, y)
                    canvas.hasStartPoint = false  // 重置，准备下一次绘制
                    canvas.requestPaint()
                    }
                }
            if(mouse.button == Qt.RightButton){
                canvas.dialog_out = !canvas.dialog_out
                canvas.showImage = !canvas.showImage

                }

            }
         Rectangle {
                id: tipBox
                // 核心：绑定鼠标位置，偏移10px避免遮挡鼠标
                x: mouseArea.mouseX + 10
                y: mouseArea.mouseY + 10
                z:1
                width: 120
                height: 40
                radius: 6 // 圆角
                color: Theme.cardBg // 背景色
                border.width: 1
                border.color: Theme.cardBorder
                onXChanged:{
                    //防止越界
                    tipBox.x = Math.min(Math.max(tipBox.x, 0), parent.width - tipBox.width)

                    tip_box_text =  "X: " + mouseArea.mouseX.toFixed(0) + "  Y: " + mouseArea.mouseY.toFixed(0)
                    }
                onYChanged:{
                    //防止越界
                    tipBox.y = Math.min(Math.max(tipBox.y, 0), parent.height - tipBox.height)

                    tip_box_text =  "X: " + mouseArea.mouseX.toFixed(0) + "  Y: " + mouseArea.mouseY.toFixed(0)
                    }

                // 提示文本（显示当前鼠标坐标）
                Text {
                    id:tipBox_text
                    anchors.centerIn: parent
                    color: Theme.text
                    font.pixelSize: 14
                }

                // 可选：添加阴影效果
                layer.enabled: true
                layer.effect: DropShadow {
                    color: "#88000000"
                    radius: 5
                    x: 2
                    y: 2
                }

            }

        }


    // 重置所有状态
    function resetCanvas() {
        canvas.point1 = Qt.point(-1, -1)
        canvas.point2 = Qt.point(-1, -1)
        canvas.lineWidth = 0
        canvas.lineHeight = 0
        canvas.requestPaint()
    }

    function draw_circle_1(ctx) {
        // 绘制第一个点
        ctx.beginPath()
        ctx.arc(canvas.point1.x, canvas.point1.y, 5, 0, Math.PI * 2)
        ctx.fillStyle = Theme.danger
        ctx.fill()
    }


    // 绘制两点连线
    function draw_line(ctx) {
        if (canvas.point1.x !== -1 && canvas.point2.x !== -1) {

            // 计算宽高像素
            canvas.lineWidth = Math.abs(canvas.point2.x - canvas.point1.x)
            canvas.lineHeight = Math.abs(canvas.point2.y - canvas.point1.y)


            // 绘制第二个点
            ctx.beginPath()
            ctx.arc(canvas.point2.x, canvas.point2.y, 5, 0, Math.PI * 2)
            ctx.fillStyle = Theme.danger
            ctx.fill()

            // 绘制连线
            ctx.beginPath()
            ctx.moveTo(canvas.point1.x, canvas.point1.y)
            ctx.lineTo(canvas.point2.x, canvas.point2.y)
            ctx.strokeStyle = Theme.success
            ctx.lineWidth = 2
            ctx.stroke()
            pix_xiebianChanged(canvas.lineWidth,canvas.lineHeight)
        }
    }
}
