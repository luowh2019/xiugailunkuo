# -*- coding: utf-8 -*-

#-----------------------------------------
# For deploy: pyside6-deploy ./main.py
#-----------------------------------------

# Copyright (C) 2022 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial

import os
import sys
from pathlib import Path

# from PySide6.QtCore import QObject, Slot
from PySide6.QtGui import QGuiApplication, QFont
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle



# To be used on the @QmlElement decorator
# (QML_IMPORT_MINOR_VERSION is optional)
QML_IMPORT_NAME = "io.qt.textproperties"
QML_IMPORT_MAJOR_VERSION = 1

# import webbrowser
from area_calculator import AreaCalculator
from image_provider import OpenCVImageProvider
# 在v2的基础上将中间的窗口合并，
# 按钮不可用时置为灰色
# 在v3的基础上完善mid_rect,使标定、裁剪、显示轮廓、修改轮廓均在该部件中进行。 -- 20260425
# v5:完成修改轮廓，显示轮廓，标定距离三大模块的功能 -- 20260427
# v6：v5的图片继承性差，改写img_provider
# vv1：迁移QQuickImageProvider，threshold尚未修改 -- 220260514

if __name__ == '__main__':
    # 屏蔽 Qt 在 Windows 启动期字体回退探测的无害告警（DirectWrite ... failed），
    # 仅过滤默认分类的 warning，QML 错误（qt.qml.*）仍然正常输出。
    # os.environ.setdefault("QT_LOGGING_RULES",
    #                       "default.warning=false;qt.qml.warning=true")
    app = QGuiApplication(sys.argv)
    # 统一默认字体，避免字体回退（Fixedsys/System/Terminal）
    # app.setFont(QFont("Microsoft YaHei UI", 9))
    QQuickStyle.setStyle("Material")

    engine = QQmlApplicationEngine()
    
    # 创建面积计算实例并暴露给QML
    provider = OpenCVImageProvider()
    engine.addImageProvider("opencv", provider)

    calculator = AreaCalculator(provider)
    engine.rootContext().setContextProperty("areaCalculator", calculator)

    qml_file = Path(__file__).parent / 'main.qml'
    engine.load(qml_file)

    if not engine.rootObjects():
        sys.exit(-1)

    sys.exit(app.exec())

