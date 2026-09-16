// Copyright (C) 2021 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial

import QtQuick 2.0
import QtQuick.Layouts 1.11
import QtQuick.Controls 2.1
import QtQuick.Window 2.1
import QtQuick.Dialogs
import Qt5Compat.GraphicalEffects 6.0//解决DrowShadow不能用的问题
import "."

ApplicationWindow {

    // 轮廓参数调整防抖：拖动滑杆后延迟 250ms 重新提取
    Timer {
        id: paramTimer
        interval: 250
        repeat: false
        onTriggered: {
            if (!page.pendingKey) return
            var uri = areaCalculator.set_contour_param(page.pendingKey, page.pendingValue)
            page.pendingKey = ""
            if (uri) {
                page.img_url = uri
                page.resetContourNav()
            }
        }
    }

    id: page
    width: 1000
    height: 750
    minimumWidth: 400
    minimumHeight: 300
    visible: true
    color: Theme.windowBg
    title: "图像轮廓处理工具 · tImg"
    Material.theme: Theme.isDark ? Material.Dark : Material.Light
    Material.accent: Theme.accent


    // url:存储图像路径的变量
    property string url: ""
    property alias img_url: imgCanvas.url

    // 底部状态栏：是否展开历史消息面板
    property bool bot_expanded: false

    property bool showBiaoding: false
    property bool showCrop: false
    property bool showContour: true
    property bool showXiugai: false

    property int contour_index:-1
    property bool hasStartPoint: false  // 是否已选择起点
    property double pix_xiebian_0:1.0

    property int img_w:0  //像素宽度
    property int img_h:0
    property int com_w: imgCanvas.width  // 组件宽度
    property int com_h: imgCanvas.height
    property real scale_w:img_w/com_w
    property real scale_h:img_h/com_h

    property var crop_array:[0,0,0,0]
    property bool croped:false
    property var points_of_contour:[]

    // 轮廓参数滑杆防抖缓存
    property string pendingKey: ""
    property real pendingValue: 0


    function set_5(num) {
        // 参数说明：
        // num: 要格式化的数字
        // "00000": 格式字符串，5个0表示固定5位，不足补0
        // 'f': 浮点数格式，0表示小数位数为0（只显示整数部分）
        return num.toString().padStart(5,"0")
    }
    function set_10(num) {
        // 参数说明：
        // num: 要格式化的数字
        // "00000": 格式字符串，10个0表示固定10位，不足补0
        // 'f': 浮点数格式，0表示小数位数为0（只显示整数部分）
        return num.toString().padStart(10,"0")
    }
    // 重置轮廓导航状态（导入/裁剪/变换/重算后调用），返回当前轮廓数量
    function resetContourNav() {
        page.contour_index = -1
        areaCalculator.get_i(-1)
        var n = areaCalculator.get_contour_count()
        fore_contour.enabled = n > 0
        next_contour.enabled = n > 0
        change_contour.enabled = n > 0
        return n
    }

    // 从 Python 拉取当前方法的参数，重建参数滑杆
    function refreshParamPanel() {
        contourParamModel.clear()
        var params = areaCalculator.get_contour_params()
        for (var i = 0; i < params.length; i++)
            contourParamModel.append(params[i])
    }

    Component.onCompleted: {
        page.refreshParamPanel()
    }

    // 底部状态栏：直接显示一条消息（不进入历史）
    function set_msg(text) {
        bot_text.text = String(text)
    }
    // 底部状态栏：追加一条消息（折叠行显示最新一条，历史入列表可展开查看）
    function append_msg(text) {
        var t = String(text)
        if (bot_list_model.count >= 100)
            bot_list_model.remove(0)
        bot_list_model.append({text: t})
        bot_text.text = t
        if (bot_expanded)
            bot_list.positionViewAtEnd()
    }

    // 统一导入入口：文件对话框 / 拖拽文件都走这里
    function load_image(src) {
        var path = String(src)
        if (path.indexOf("file:///") === 0)
            path = path.replace("file:///", "")
        if (!path)
            return

        page.url = path
        page.set_msg("导入文件" + path)
        // 只加载图像，不做任何轮廓处理
        areaCalculator.get_file(path)
        // 同步图片尺寸，确保缩放比例非零（img1 异步加载前先用真实尺寸）
        var sz = areaCalculator.get_img_size()
        if (sz && sz.length === 2 && sz[0] > 0 && sz[1] > 0) {
            page.img_w = sz[0]
            page.img_h = sz[1]
        }
        // 记录缩放比例与像素距离（供编辑模式使用），不触发轮廓处理
        areaCalculator.get_canshu(page.croped, page.crop_array,
            page.scale_w, page.scale_h, spt_pix_input.text)
        // 导入后仅显示原图
        page.img_url = areaCalculator.get_img("img")
        page.append_msg("图像已导入，点击「显示轮廓」提取轮廓")

        // 启用图像操作，禁用轮廓操作
        imgcv_vertical.enabled = true
        imgcv_90.enabled = true
        imgcv_crop.enabled = true
        distance_ini.enabled = true
        img_save.enabled = true
        spt_pix_input.enabled = true
        show_contour_btn.enabled = true
        page.resetContourNav()
    }

    // 从 Python 侧同步图像原始像素尺寸（镜像/旋转/裁剪后尺寸会变化）
    function refreshImgSize() {
        var sz = areaCalculator.get_img_size()
        if (sz && sz.length === 2 && sz[0] > 0 && sz[1] > 0) {
            page.img_w = sz[0]
            page.img_h = sz[1]
        }
    }

    FileDialog {
        id: fileSave
        title: '保存文件'
        nameFilters: [ "Image files (*.jpg *.png)", "All files (*)" ]

        fileMode: FileDialog.SaveFile
        onAccepted: {
            let path = fileSave.selectedFile.toString().replace("file:///", "")
            areaCalculator.save_img(path)  // 传给Python
        }
    }

    FileDialog {
        id: fileDialog
        nameFilters: [ "Image files (*.jpg *.png *.mp4)", "All files (*)" ]

        onAccepted: {
            page.load_image(fileDialog.selectedFile)
        }
    }
    Dialog {
        id: inputDialog
        implicitWidth: 420
        implicitHeight: 190
        title: "输入距离"
        modal: true
        focus: true
        standardButtons: Dialog.Ok | Dialog.Cancel

        background: Rectangle {
            color: Theme.panelBg
            radius: 8
            border.color: Theme.cardBorder
            border.width: 1
        }

        header: Label {
            text: "输入距离"
            color: Theme.text
            font.pixelSize: 15
            font.bold: true
            padding: 12
            background: Rectangle {
                color: Theme.cardBg
                radius: 8
            }
        }

        // 必须用 contentItem 放内容，否则会遮挡按键
        contentItem: Rectangle {
            color: Theme.panelBg
            TextInput {
                id: input_inpy
                anchors.fill: parent
                font.pixelSize: 20
                color: Theme.text
                horizontalAlignment: Qt.AlignHCenter
                verticalAlignment: Qt.AlignVCenter
                validator: DoubleValidator {
                notation: DoubleValidator.StandardNotation
            }

                // 把回车绑定在【输入框】上
                Keys.onReturnPressed: inputDialog.accept()
                Keys.onEnterPressed: inputDialog.accept()
                Keys.onEscapePressed: inputDialog.reject()
            }
        }

        // 弹窗打开时自动聚焦输入框
        onOpened: {
            input_inpy.focus = true
        }

        onAccepted: {
            spt_pix_input.text = set_pix_text()
        }

        onRejected: {
            close()
        }

        function set_pix_text(){
            let text1 = input_inpy.text.trim()
            let num1 = parseFloat(text1)
            if (isNaN(num1)) {
                return ""
            }
            let calculateResult = num1 / page.pix_xiebian_0
            return calculateResult.toFixed(3)
        }
    }

    // ==================== 顶部工具栏 ====================
    Rectangle{
        id:top_rect
        width: page.width
        height: 176
        color: Theme.panelBg
        z: 20

        ColumnLayout {
            anchors.fill: parent
            anchors.topMargin: 8
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.bottomMargin: 8
            spacing: 6

            // ---- 标题行：应用名 + 主题选择 ----
            RowLayout {
                Layout.preferredHeight: 30
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "图像轮廓处理工具"
                    font.pixelSize: 16
                    font.bold: true
                    color: Theme.text
                }
                Text {
                    text: "导入图像 → 裁剪 / 标定 → 显示轮廓 → 修改轮廓"
                    font.pixelSize: 11
                    color: Theme.textDim
                    Layout.topMargin: 4
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "🎨 界面主题"
                    font.pixelSize: 12
                    color: Theme.textDim
                    verticalAlignment: Text.AlignVCenter
                }
                ComboBox {
                    id: themeSelector
                    implicitWidth: 138
                    implicitHeight: 30
                    font.pixelSize: 13
                    model: ["深空暗色", "极简浅色", "科技深蓝", "暖阳米色"]
                    currentIndex: Theme.currentTheme
                    onActivated: (index) => Theme.currentTheme = index

                    // 弹出列表项：统一 13px 字号
                    delegate: ItemDelegate {
                        width: themeSelector.width
                        height: 30
                        text: modelData                    // 关键：显示列表项文字
                        // highlighted: themeSelector.highlightedIndex === index   // 顺带补上选中高亮，否则当前项不高亮
                        font.pixelSize: 13
                    }

                    background: Rectangle {
                        implicitWidth: 138
                        implicitHeight: 30
                        radius: 6
                        color: themeSelector.hovered ? Theme.hover : Theme.cardBg
                        border.width: 1
                        border.color: Theme.cardBorder
                    }
                }
            }

            // ---- 第一行：图像操作 ----
            RowLayout {
                Layout.preferredHeight: 36
                Layout.fillWidth: true
                spacing: 8

                AppButton {
                    id: img_import
                    text: "📂 导入图像"
                    primary: true
                    onClicked: fileDialog.open()
                }

                AppButton {
                    id: imgcv_vertical
                    text: "⚒️ 镜像"
                    enabled:false
                    onClicked: {
                        areaCalculator.get_jx()
                        page.refreshImgSize()
                        page.img_url = areaCalculator.get_img("img")
                        page.resetContourNav()
                        page.append_msg("图像已镜像，点击「显示轮廓」重新提取轮廓")
                    }
                }
                AppButton {
                    id: imgcv_90
                    text: "🔄 旋转90°"
                    enabled:false
                    onClicked: {
                        areaCalculator.get_90()
                        page.refreshImgSize()
                        page.img_url = areaCalculator.get_img("img")
                        page.resetContourNav()
                        page.append_msg("图像已旋转，点击「显示轮廓」重新提取轮廓")
                    }
                }
                AppButton {
                    id: imgcv_crop
                    text: "✂️ 图像裁剪"
                    enabled:true
                    onClicked: {
                        if(!page.url){
                            return
                        }
                        page.showBiaoding=false
                        page.showContour=true
                        page.showXiugai=false
                        page.showCrop=true
                        imgCanvas.isEnabled = true
                        show_contour_btn.enabled = false
                    }
                }
                AppButton {
                    id: distance_ini
                    text: "📏 两点标定"
                    enabled:false
                    onClicked: {
                        page.showCrop=false
                        page.showContour=false
                        page.showXiugai=false
                        page.showBiaoding=true
                        canvas_comp.img_bd = areaCalculator.get_img("img")
                        show_contour_btn.enabled = false
                    }
                }
                AppButton {
                    id: img_save
                    text: "💾 保存图像"
                    enabled:false
                    onClicked: {
                        fileSave.open()
                    }
                }

                Item { Layout.fillWidth: true }
            }



            // ---- 第三行：轮廓操作 + 参数 ----
            RowLayout {
                Layout.preferredHeight: 40
                Layout.fillWidth: true
                spacing: 8
                AppButton {
                    id: show_contour_btn
                    text: "🔍 显示轮廓"
                    enabled: false
                    onClicked: {
                        if (!page.url) {
                            page.append_msg("请先导入图像")
                            return
                        }
                        var uri = areaCalculator.run_contours()
                        if (!uri) {
                            page.append_msg("提取轮廓失败：请检查图像是否有效")
                            return
                        }
                        page.img_url = uri
                        var n = page.resetContourNav()
                        page.append_msg("已提取 " + n + " 个轮廓，点击「下一个轮廓」定位要修改的轮廓")
                    }
                }
                AppButton {
                    id: fore_contour
                    text: "◀️ 上一个轮廓"
                    enabled:false
                    onClicked: {
                        let w = areaCalculator.index_cal(page.contour_index,false)
                        page.contour_index = w[0]
                        if(!w[1]){
                            fore_contour.enabled = false
                            next_contour.enabled = true
                        }
                        else{
                            fore_contour.enabled = true
                            next_contour.enabled = true
                        }
                        page.img_url = areaCalculator.get_img("contour"+String(contour_index))
                        page.append_msg("第" + page.contour_index + "个轮廓")
                    }
                }
                AppButton {
                    id: next_contour
                    text: "▶️ 下一个轮廓"
                    enabled:false
                    onClicked: {
                        let w = areaCalculator.index_cal(page.contour_index,true)
                        page.contour_index = w[0]
                        if(!w[1]){
                            fore_contour.enabled = true
                            next_contour.enabled = false
                        }
                        else{
                            fore_contour.enabled = true
                            next_contour.enabled = true
                        }
                        page.img_url = areaCalculator.get_img("contour"+String(contour_index))
                        page.append_msg("第" + page.contour_index + "个轮廓")
                    }
                }
                AppButton {
                    id: change_contour
                    text: "✏️ 修改轮廓"
                    primary: true
                    enabled:false
                    onClicked: {
                        // 必须先通过「下一个轮廓」定位到具体轮廓
                        if (page.contour_index < 0) {
                            page.append_msg("尚未定位轮廓：请先点击「下一个轮廓」选择要修改的轮廓")
                            return
                        }
                        page.showXiugai = true
                        page.showContour = false
                        areaCalculator.get_canshu(page.croped,page.crop_array,
                            page.scale_w,page.scale_h,spt_pix_input.text)

                        // 编辑模式使用原图作为画布底图
                        imgCanvas.url = areaCalculator.get_img("img")

                        change_contour.enabled = false

                        next_contour.enabled = false
                        fore_contour.enabled = false
                        imgcv_vertical.enabled = false
                        imgcv_90.enabled = false
                        imgcv_crop.enabled = false
                        distance_ini.enabled=false
                        show_contour_btn.enabled = false
                    }
                }

                Item { Layout.preferredWidth: 20 }

                FieldBox {
                    id: spt_width_input
                    label: "宽(px)"
                    text: String(page.img_w)
                }
                FieldBox {
                    id: spt_height_input
                    label: "高(px)"
                    text: String(page.img_h)
                }
                FieldBox {
                    id: spt_pix_input
                    label: "像素距离"
                    editable: true
                    text: "1"
                    enabled:false

                    onTextChanged: {
                        areaCalculator.get_pix(spt_pix_input.text)
                        if (areaCalculator.has_contours())
                            page.img_url = areaCalculator.get_img("all")
                    }
                }
            }
            // ---- 第二行：轮廓参数（方法选择 + 动态参数滑杆） ----
            RowLayout {
                Layout.preferredHeight: 34
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "轮廓方法"
                    font.pixelSize: 12
                    color: Theme.textDim
                    verticalAlignment: Text.AlignVCenter
                }
                ComboBox {
                    id: methodSelector
                    implicitWidth: 150
                    implicitHeight: 30
                    font.pixelSize: 13
                    enabled: !page.showXiugai
                    model: areaCalculator.get_contour_methods()

                    delegate: ItemDelegate {
                        width: methodSelector.width
                        height: 30
                        text: modelData.split("|")[1]
                        font.pixelSize: 13
                    }

                    background: Rectangle {
                        implicitWidth: 150
                        implicitHeight: 30
                        radius: 6
                        color: methodSelector.hovered ? Theme.hover : Theme.cardBg
                        border.width: 1
                        border.color: Theme.cardBorder
                    }

                    onActivated: (index) => {
                        var key = methodSelector.model[index].split("|")[0]
                        var uri = areaCalculator.set_contour_method(key)
                        page.refreshParamPanel()
                        if (uri) {
                            page.img_url = uri
                            page.resetContourNav()
                            page.append_msg("已切换轮廓方法，参数已重置")
                        }
                    }
                }

                Repeater {
                    id: paramRepeater
                    model: ListModel {
                        id: contourParamModel
                    }

                    RowLayout {
                        Layout.preferredWidth: 200
                        spacing: 4

                        Text {
                            Layout.preferredWidth: 48
                            text: model.label
                            font.pixelSize: 11
                            color: Theme.textDim
                            horizontalAlignment: Text.AlignLeft
                            elide: Text.ElideRight
                        }
                        Slider {
                            id: pSlider
                            Layout.fillWidth: true
                            from: model.min
                            to: model.max
                            stepSize: model.step
                            value: model.value
                            enabled: !page.showXiugai
                            onValueChanged: {
                                if (!pSlider.pressed) return
                                page.pendingKey = model.key
                                page.pendingValue = value
                                paramTimer.restart()
                            }
                        }
                        Text {
                            Layout.preferredWidth: 26
                            text: Math.round(pSlider.value)
                            font.pixelSize: 11
                            color: Theme.text
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }
    }

    // ==================== 中部图像区 ====================
    Rectangle {
        id:mid_rect
        width: page.width-10
        anchors.left: parent.left
        anchors.top: top_rect.bottom
        anchors.bottom: bot_rect.top
        anchors.margins: 5
        color: Theme.windowBg
        border.width: 1
        border.color: Theme.cardBorder
        clip: true

        ImageCanvas{
            id:imgCanvas
            visible: page.showContour || page.showCrop || page.showXiugai
            mode: page.showXiugai ? "edit"
                : (page.showCrop ? "crop" : "display")

            // img_w/img_h 以 Python 侧 get_img_size() 原始像素为准，
            // 不再由 imgSource.sourceSize 覆盖（其受 2048 上限缩放，会破坏坐标换算）
            onCan_addChanged:{
                next_contour.enabled = false
                fore_contour.enabled = true
            }
            onCanvasStateChanged:{
                // 按返回键/完成按钮后保存轮廓，恢复其余按钮可用功能
                page.showXiugai = false
                page.showContour = true

                change_contour.enabled = true
                next_contour.enabled = true
                fore_contour.enabled = true
                imgcv_vertical.enabled = true
                imgcv_90.enabled = true
                imgcv_crop.enabled = true
                distance_ini.enabled = true
                img_save.enabled = true
                show_contour_btn.enabled = true

                page.img_url = areaCalculator.draw_contour()
                page.append_msg("轮廓信息已保存")
                // 完成后计算并显示面积（触发 onAreaUpdated -> 状态栏消息）
                areaCalculator.get_contour_area()
            }
            onWidthChanged:{
                areaCalculator.get_scalew(page.scale_w)
            }
            onHeightChanged:{
                areaCalculator.get_scaleh(page.scale_h)
            }
            points:page.points_of_contour
            onPointDeleteSingle:(x,y)=>{
                areaCalculator.delete_nearest_point(x, y)
            }
            onPointsBatchDelete:(x1,y1,x2,y2)=>{
                areaCalculator.delete_batch_by_rect(x1,y1,x2,y2)
            }
            onPointAdd: (x,y)=>{
                // 通知Python添加点
                areaCalculator.addPoint(x, y)
            }
            onUndoRequested: {
                areaCalculator.undo_edit()
                // 撤销后同步面积
                areaCalculator.get_contour_area()
            }
            onFinishRequested: {
                imgCanvas.canvasState = !imgCanvas.canvasState
            }
            onPosChanged:(x1,y1,x2,y2)=>{
                page.showCrop = false
                page.crop_array[0] = Math.floor(x1*page.scale_w)
                page.crop_array[1] = Math.floor(y1*page.scale_h)
                page.crop_array[2] = Math.floor(x2*page.scale_w)
                page.crop_array[3] = Math.floor(y2*page.scale_h)

                // 裁剪后仅显示原图，轮廓需重新点击「显示轮廓」
                areaCalculator.get_crop(page.crop_array)
                page.refreshImgSize()
                page.img_url = areaCalculator.get_img("img")
                page.resetContourNav()
                imgcv_crop.enabled = true
                page.croped = true
                show_contour_btn.enabled = true
                page.append_msg("裁剪完成，点击「显示轮廓」重新提取轮廓")
            }

            Connections {
                target: areaCalculator
                function onAreaUpdated(area) {
                    page.append_msg("轮廓面积：" + area)
                }
            }

            // 接收Python传来的点坐标更新
            Connections {
                target: areaCalculator
                function onPointsUpdated(points) {
                    page.points_of_contour = points
                }
            }
        }

        Canvas_biaoding{
            id:canvas_comp
            anchors.fill: parent
            visible: page.showBiaoding  // 关键：仅当 showBiaoding 为 true 时显示
            url:page.url
            img_bd:""

            onShowImageChanged:{
                page.showBiaoding = false
                page.showContour = true
                show_contour_btn.enabled = true
            }
            onPix_xiebianChanged:(draw_width,draw_height)=>{

                page.pix_xiebian_0 = cal_xiebian(draw_width,draw_height)
            }

            function cal_xiebian(var_w,var_h){
                return Math.sqrt((var_w*page.scale_w)**2+(var_h*page.scale_h)**2)
            }
            onDialog_outChanged:{
                inputDialog.open()
            }
        }

        // 空背景提示：未导入图片时显示
        Text {
            anchors.centerIn: parent
            visible: page.showContour && page.url === ""
            text: "📂 将图片拖入此处，或点击「导入图像」"
            font.pixelSize: 18
            font.bold: true
            color: Theme.textDim
        }

        // 文件拖拽导入
        DropArea {
            id: dropArea
            anchors.fill: parent
            keys: ["text/uri-list"]
            onEntered: (drag) => { drag.accept() }
            onDropped: (drop) => {
                if (drop.hasUrls && drop.urls.length > 0)
                    page.load_image(drop.urls[0])
                drop.accept()
            }
        }

        // 拖拽高亮反馈
        Rectangle {
            id: dropHint
            anchors.fill: parent
            visible: dropArea.containsDrag
            z: 2000
            color: Theme.isDark ? "#5522d3ee" : "#553b82f6"
            border.width: 2
            border.color: Theme.accent
            Text {
                anchors.centerIn: parent
                text: "松开鼠标导入图像"
                font.pixelSize: 20
                font.bold: true
                color: Theme.text
            }
        }
    }

    // ==================== 底部状态栏（可展开消息面板） ====================
    Rectangle {
        id: bot_rect
        width: page.width
        height: bot_expanded ? 150 : 40
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 5
        color: Theme.panelBg
        radius: 6
        border.width: 1
        border.color: Theme.cardBorder
        z: 30

        Behavior on height {
            NumberAnimation { duration: 160; easing.type: Easing.OutQuad }
        }

        // 折叠行：状态点 + 最新一条消息 + 展开指示
        RowLayout {
            id: bot_bar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 20
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            // 状态指示点
            Rectangle {
                id: statusDot
                width: 10
                height: 10
                radius: 5
                color: Theme.success
            }

            // 最新一条消息（单行省略）
            Text {
                id: bot_text
                Layout.fillWidth: true
                text: "就绪：导入图像 → 裁剪 / 标定 → 点击「显示轮廓」"
                color: Theme.textDim
                font.pixelSize: 13
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }

            // 展开/折叠指示
            Text {
                text: bot_expanded ? "▼" : "▲"
                color: Theme.textDim
                font.pixelSize: 11
                verticalAlignment: Text.AlignVCenter
            }
        }

        // 展开区：历史消息列表（面积、轮廓切换、操作提示等）
        Rectangle {
            id: bot_panel
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: bot_bar.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.bottomMargin: 6
            visible: bot_expanded
            clip: true
            color: "transparent"

            ListView {
                id: bot_list
                anchors.fill: parent
                model: ListModel {
                    id: bot_list_model
                }
                spacing: 3
                clip: true

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                delegate: Text {
                    width: bot_list.width
                    text: model.text
                    color: Theme.textDim
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }
            }
        }

        // 点击折叠行切换展开/折叠（不遮挡列表区域，保证列表可滚动）
        MouseArea {
            id: bot_click
            anchors.fill: bot_bar
            onClicked: {
                bot_expanded = !bot_expanded
                if (bot_expanded)
                    bot_list.positionViewAtEnd()
            }
        }
    }

    // 进入修改轮廓时的操作提示
    Connections {
        target: areaCalculator
        function onCanshuUpdated() {
            page.append_msg("操作提示：左键添加点，点击已有顶点删除，右键拖拽平移图像，Shift+左键框选删除，滚轮缩放，Esc 完成。")
        }
    }
}
