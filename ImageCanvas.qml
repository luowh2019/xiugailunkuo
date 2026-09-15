import QtQuick 2.0
import QtQuick.Layouts 1.11
import QtQuick.Controls 2.1
import Qt5Compat.GraphicalEffects 6.0
import "."

// ============================================================
// 统一图像画布组件（替代 Canvas_contour / Canvas_crop / Canvas_xiugai）
//   mode = "display"  显示图像：中键/右键拖拽平移，滚轮缩放
//   mode = "crop"     框选裁剪：左键拖拽选区，右键确认裁剪
//   mode = "edit"     修改轮廓：左键加点 / 点击顶点删除，右键拖拽平移，
//                     Shift+左键框选删除，滚轮缩放，Esc/完成 保存退出
// 三种模式共用同一图片源与同一套平移/缩放变换，仅交互逻辑不同。
// ============================================================
Canvas {
    id: imgCanvas
    anchors.fill: parent
    antialiasing: true

    // ---------- 公共 ----------
    property string mode: "display"          // display | crop | edit
    property alias url: imgSource.source     // 图片源（display 显示图 / crop 底层图 / edit 原图）
    property alias img_xg: imgSource.source  // 兼容旧接口

    property real canvasScale: 1.0
    property real canvasOffsetX: 0
    property real canvasOffsetY: 0

    // 图片尺寸与状态（display 模式使用）
    property real spt_w: 0.0
    property real spt_h: 0.0
    property bool can_add: true

    // 裁剪开关（crop 模式：由外部控制是否可框选）
    property bool isEnabled: true

    // ---------- crop ----------
    property point startPos: Qt.point(0, 0)
    property point endPos: Qt.point(0, 0)
    property bool isDragging: false
    signal posChanged(real x1, real y1, real x2, real y2)

    // ---------- edit ----------
    property var points: []
    property bool canvasState: false
    signal pointAdd(real x, real y)
    signal pointDeleteSingle(real x, real y)
    signal pointsBatchDelete(real x1, real y1, real x2, real y2)
    signal undoRequested()
    signal finishRequested()

    property bool shiftSelect: false
    property real selStartX: 0
    property real selStartY: 0
    property real selEndX: 0
    property real selEndY: 0
    property bool panning: false
    property real lastPanX: 0
    property real lastPanY: 0
    property int hoverIndex: -1

    // 模式切换时重置视图，避免跨模式残留缩放/平移
    onModeChanged: {
        canvasScale = 1.0
        canvasOffsetX = 0
        canvasOffsetY = 0
        panning = false
        shiftSelect = false
        isDragging = false
        hoverIndex = -1
        requestPaint()
    }

    // 数据源图片（隐藏，仅作为绘制源）
    Image {
        id: imgSource
        visible: false
        onStatusChanged: {
            if (imgSource.status === Image.Loading) {
                busy.running = true
                stateLabel.visible = false
            } else if (imgSource.status === Image.Ready) {
                busy.running = false
                if (url) {
                    spt_w = imgSource.sourceSize.width
                    spt_h = imgSource.sourceSize.height
                }
                imgCanvas.requestPaint()
            } else if (imgSource.status === Image.Error) {
                busy.running = false
                stateLabel.visible = true
                stateLabel.text = "ERROR"
                can_add = !can_add
            }
        }
    }

    // 加载指示（display 模式）
    BusyIndicator {
        id: busy
        running: false
        anchors.centerIn: parent
        z: 5
        visible: imgCanvas.mode === "display"
    }

    Text {
        id: stateLabel
        visible: false
        anchors.centerIn: parent
        z: 5
        color: Theme.danger
        font.pixelSize: 16
    }

    // 裁剪遮罩（crop 模式：外深内浅挖空选区）
    Item {
        id: selectMask
        anchors.fill: parent
        visible: imgCanvas.mode === "crop"
        clip: true

        Rectangle {
            id: darkMask
            anchors.fill: parent
            color: "#c89b9b9b"
            layer.enabled: true
            layer.effect: OpacityMask {
                invert: true
                maskSource: Item {
                    width: darkMask.width
                    height: darkMask.height
                    Rectangle {
                        x: imgCanvas.startPos.x
                        y: imgCanvas.startPos.y
                        width: Math.abs(imgCanvas.endPos.x - imgCanvas.startPos.x)
                        height: Math.abs(imgCanvas.endPos.y - imgCanvas.startPos.y)
                        color: Theme.success
                    }
                }
            }
        }
    }

    // 编辑模式操作条（edit）
    Rectangle {
        id: hintBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 8
        height: 36
        radius: 6
        color: Theme.panelBg
        border.width: 1
        border.color: Theme.cardBorder
        z: 10
        opacity: 0.94
        visible: imgCanvas.mode === "edit"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 6
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: "左键添加点 · 点击顶点删除 · 右键拖拽平移 · Shift+左键框选删除 · 滚轮缩放 · Esc 完成"
                color: Theme.textDim
                font.pixelSize: 12
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
            AppButton {
                text: "🔍 重置视图"
                onClicked: {
                    imgCanvas.canvasScale = 1
                    imgCanvas.canvasOffsetX = 0
                    imgCanvas.canvasOffsetY = 0
                    imgCanvas.requestPaint()
                }
            }
            AppButton {
                text: "↩️ 撤销"
                onClicked: imgCanvas.undoRequested()
            }
            AppButton {
                text: "✅ 完成"
                primary: true
                onClicked: imgCanvas.finishRequested()
            }
        }
    }

    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.save()
        ctx.translate(canvasOffsetX, canvasOffsetY)
        ctx.scale(canvasScale, canvasScale)

        // 底层图像
        if (imgSource.width > 0)
            ctx.drawImage(imgSource, 0, 0, width, height)

        // 编辑模式：绘制轮廓线与顶点
        if (mode === "edit" && points.length > 0) {
            ctx.strokeStyle = Theme.accent
            ctx.lineWidth = 2 / canvasScale
            ctx.beginPath()
            ctx.moveTo(points[0][0][0], points[0][0][1])
            for (var i = 1; i < points.length; i++) {
                ctx.lineTo(points[i][0][0], points[i][0][1])
            }
            ctx.closePath()
            ctx.stroke()

            var r = 4 / canvasScale
            for (var j = 0; j < points.length; j++) {
                ctx.beginPath()
                ctx.arc(points[j][0][0], points[j][0][1], r, 0, Math.PI * 2)
                ctx.fillStyle = Theme.danger
                ctx.fill()
                // 悬停顶点高亮
                if (j === hoverIndex) {
                    ctx.beginPath()
                    ctx.arc(points[j][0][0], points[j][0][1], r + 4 / canvasScale, 0, Math.PI * 2)
                    ctx.strokeStyle = Theme.accent2
                    ctx.lineWidth = 2 / canvasScale
                    ctx.stroke()
                }
            }
        }
        ctx.restore()

        // 编辑模式：框选区域（屏幕坐标系）
        if (mode === "edit" && shiftSelect) {
            ctx.save()
            ctx.resetTransform()
            ctx.strokeStyle = Theme.accent2
            ctx.lineWidth = 2
            ctx.fillStyle = Theme.isDark ? "rgba(129,140,248,0.22)" : "rgba(99,102,241,0.15)"
            ctx.beginPath()
            ctx.rect(selStartX, selStartY, selEndX - selStartX, selEndY - selStartY)
            ctx.fill()
            ctx.stroke()
            ctx.restore()
        }
    }

    function screenToCanvas(x, y) {
        var cx = (x - canvasOffsetX) / canvasScale
        var cy = (y - canvasOffsetY) / canvasScale
        return {x: cx, y: cy}
    }

    // 命中测试：返回距离光标最近的顶点索引，未命中返回 -1（edit 模式）
    function hitTestVertex(sx, sy) {
        var pt = screenToCanvas(sx, sy)
        var hitR = 9 / canvasScale
        for (var i = 0; i < points.length; i++) {
            var dx = points[i][0][0] - pt.x
            var dy = points[i][0][1] - pt.y
            if (Math.sqrt(dx * dx + dy * dy) < hitR)
                return i
        }
        return -1
    }

    // 鼠标 + 键盘交互
    Item {
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: {
            if (imgCanvas.mode === "edit")
                imgCanvas.finishRequested()
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            hoverEnabled: true
            // 裁剪模式由 isEnabled 控制，其他模式始终可用
            enabled: imgCanvas.isEnabled || imgCanvas.mode !== "crop"
            property bool batchDeleted: false

            cursorShape: {
                if (imgCanvas.mode === "crop") return Qt.CrossCursor
                if (imgCanvas.panning) return Qt.ClosedHandCursor
                if (imgCanvas.mode === "edit") {
                    if (imgCanvas.shiftSelect) return Qt.CrossCursor
                    if (imgCanvas.hitTestVertex(mouseX, mouseY) >= 0) return Qt.PointingHandCursor
                    return Qt.CrossCursor
                }
                return Qt.OpenHandCursor
            }

            onWheel: (wheel) => {
                if (imgCanvas.mode === "display" || imgCanvas.mode === "edit")
                    handleWheelEvent(wheel)
            }

            onPressed: (mouse) => {
                parent.forceActiveFocus()

                if (imgCanvas.mode === "crop") {
                    if (mouse.button === Qt.LeftButton) {
                        // 左键按下：记录选区起点
                        imgCanvas.startPos = Qt.point(mouse.x, mouse.y)
                        imgCanvas.endPos = imgCanvas.startPos
                        imgCanvas.isDragging = true
                    } else if (mouse.button === Qt.RightButton) {
                        // 右键：确认裁剪
                        imgCanvas.isDragging = false
                        if (imgCanvas.isEnabled) {
                            imgCanvas.isEnabled = false
                            imgCanvas.posChanged(imgCanvas.startPos.x, imgCanvas.startPos.y,
                                                 imgCanvas.endPos.x, imgCanvas.endPos.y)
                        }
                    }
                }
                else if (imgCanvas.mode === "edit") {
                    if (mouse.button === Qt.RightButton) {
                        // 右键按下 -> 进入平移
                        imgCanvas.panning = true
                        imgCanvas.lastPanX = mouse.x
                        imgCanvas.lastPanY = mouse.y
                    } else if (mouse.button === Qt.LeftButton &&
                               (mouse.modifiers & Qt.ShiftModifier) !== 0) {
                        // Shift + 左键 -> 开始框选
                        imgCanvas.shiftSelect = true
                        batchDeleted = false
                        imgCanvas.selStartX = mouse.x
                        imgCanvas.selStartY = mouse.y
                        imgCanvas.selEndX = mouse.x
                        imgCanvas.selEndY = mouse.y
                        imgCanvas.requestPaint()
                    }
                }
                else if (imgCanvas.mode === "display") {
                    // 中键 / 右键 -> 平移
                    if (mouse.button === Qt.MiddleButton || mouse.button === Qt.RightButton) {
                        imgCanvas.panning = true
                        imgCanvas.lastPanX = mouse.x
                        imgCanvas.lastPanY = mouse.y
                    }
                }
            }

            onPositionChanged: (mouse) => {
                if (imgCanvas.mode === "crop") {
                    if (imgCanvas.isDragging) {
                        imgCanvas.endPos.x = Math.max(0, Math.min(mouse.x, parent.width))
                        imgCanvas.endPos.y = Math.max(0, Math.min(mouse.y, parent.height))
                    }
                }
                else if (imgCanvas.mode === "edit") {
                    if (imgCanvas.panning) {
                        var dx = mouse.x - imgCanvas.lastPanX
                        var dy = mouse.y - imgCanvas.lastPanY
                        imgCanvas.canvasOffsetX += dx
                        imgCanvas.canvasOffsetY += dy
                        imgCanvas.lastPanX = mouse.x
                        imgCanvas.lastPanY = mouse.y
                        imgCanvas.requestPaint()
                    } else if (imgCanvas.shiftSelect) {
                        imgCanvas.selEndX = mouse.x
                        imgCanvas.selEndY = mouse.y
                        imgCanvas.requestPaint()
                    } else {
                        var hi = imgCanvas.hitTestVertex(mouse.x, mouse.y)
                        if (hi !== imgCanvas.hoverIndex) {
                            imgCanvas.hoverIndex = hi
                            imgCanvas.requestPaint()
                        }
                    }
                }
                else if (imgCanvas.mode === "display" && imgCanvas.panning) {
                    var dx2 = mouse.x - imgCanvas.lastPanX
                    var dy2 = mouse.y - imgCanvas.lastPanY
                    imgCanvas.canvasOffsetX += dx2
                    imgCanvas.canvasOffsetY += dy2
                    imgCanvas.lastPanX = mouse.x
                    imgCanvas.lastPanY = mouse.y
                    imgCanvas.requestPaint()
                }
            }

            onReleased: (mouse) => {
                if (imgCanvas.mode === "crop") {
                    if (imgCanvas.isDragging)
                        imgCanvas.isDragging = false
                }
                else if (imgCanvas.mode === "edit") {
                    if (imgCanvas.panning) {
                        imgCanvas.panning = false
                    } else if (imgCanvas.shiftSelect && mouse.button === Qt.LeftButton) {
                        var p1 = imgCanvas.screenToCanvas(imgCanvas.selStartX, imgCanvas.selStartY)
                        var p2 = imgCanvas.screenToCanvas(imgCanvas.selEndX, imgCanvas.selEndY)
                        imgCanvas.pointsBatchDelete(p1.x, p1.y, p2.x, p2.y)
                        imgCanvas.shiftSelect = false
                        batchDeleted = true
                        imgCanvas.requestPaint()
                    }
                }
                else if (imgCanvas.mode === "display") {
                    if (imgCanvas.panning)
                        imgCanvas.panning = false
                }
            }

            onClicked: (mouse) => {
                if (imgCanvas.mode === "crop") {
                    // 裁剪确认在 onPressed 右键处理
                    return
                }
                if (imgCanvas.mode === "edit") {
                    if (batchDeleted) {
                        batchDeleted = false
                        return
                    }
                    if (imgCanvas.panning || imgCanvas.shiftSelect)
                        return
                    if (mouse.button === Qt.LeftButton) {
                        var idx = imgCanvas.hitTestVertex(mouse.x, mouse.y)
                        var pt = imgCanvas.screenToCanvas(mouse.x, mouse.y)
                        if (idx >= 0)
                            imgCanvas.pointDeleteSingle(pt.x, pt.y)
                        else
                            imgCanvas.pointAdd(pt.x, pt.y)
                        imgCanvas.requestPaint()
                    }
                }
            }

            function handleWheelEvent(wheel) {
                var mouseX = wheel.x
                var mouseY = wheel.y
                var scaleDelta = wheel.angleDelta.y > 0 ? 1.1 : 0.9
                var newScale = imgCanvas.canvasScale * scaleDelta
                if (newScale < 0.2) newScale = 0.2
                if (newScale > 5) newScale = 5
                imgCanvas.canvasOffsetX = mouseX - (mouseX - imgCanvas.canvasOffsetX) * (newScale / imgCanvas.canvasScale)
                imgCanvas.canvasOffsetY = mouseY - (mouseY - imgCanvas.canvasOffsetY) * (newScale / imgCanvas.canvasScale)
                imgCanvas.canvasScale = newScale
                imgCanvas.requestPaint()
            }
        }
    }
}
