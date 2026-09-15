pragma Singleton
import QtQuick 2.0

// ============================================================
// 全局主题单例：四套配色方案，所有 QML 组件统一从 Theme 取色
// 0 深空暗色 | 1 极简浅色 | 2 科技深蓝 | 3 暖阳米色
// ============================================================
Item {
    id: theme

    // 默认主题：1 = 极简浅色
    property int currentTheme: 1

    readonly property var themeList: [
        {
            name: "深空暗色",
            isDark: true,
            windowBg: "#1b1d27",
            panelBg: "#232634",
            cardBg: "#2c2f3e",
            cardBorder: "#3a3f52",
            text: "#e8eaf0",
            textDim: "#9aa0b0",
            textDisabled: "#6a7080",
            accent: "#22d3ee",
            accent2: "#818cf8",
            onAccent: "#0b1220",
            success: "#34d399",
            danger: "#f87171",
            hover: "#343849",
            pressed: "#3f4458"
        },
        {
            name: "极简浅色",
            isDark: false,
            windowBg: "#eef0f5",
            panelBg: "#ffffff",
            cardBg: "#f6f7fb",
            cardBorder: "#dde1ea",
            text: "#262a36",
            textDim: "#6b7280",
            textDisabled: "#b6bac6",
            accent: "#3b82f6",
            accent2: "#8b5cf6",
            onAccent: "#ffffff",
            success: "#10b981",
            danger: "#ef4444",
            hover: "#eef1f7",
            pressed: "#e2e6f0"
        },
        {
            name: "科技深蓝",
            isDark: true,
            windowBg: "#0b1220",
            panelBg: "#111a2e",
            cardBg: "#16213a",
            cardBorder: "#243450",
            text: "#dbe6ff",
            textDim: "#8fa3c8",
            textDisabled: "#5c6f94",
            accent: "#38bdf8",
            accent2: "#6366f1",
            onAccent: "#06121f",
            success: "#4ade80",
            danger: "#f87171",
            hover: "#1c2a47",
            pressed: "#223355"
        },
        {
            name: "暖阳米色",
            isDark: false,
            windowBg: "#efe7d5",
            panelBg: "#fbf6ea",
            cardBg: "#f4ecdb",
            cardBorder: "#e0d3b6",
            text: "#3d3629",
            textDim: "#7a6f5c",
            textDisabled: "#b3a68e",
            accent: "#e07b39",
            accent2: "#b98a2f",
            onAccent: "#ffffff",
            success: "#4c9a62",
            danger: "#d9534f",
            hover: "#eee4ce",
            pressed: "#e4d7ba"
        }
    ]

    readonly property var current: themeList[currentTheme]
    readonly property string name: current.name
    readonly property bool isDark: current.isDark
    readonly property string windowBg: current.windowBg
    readonly property string panelBg: current.panelBg
    readonly property string cardBg: current.cardBg
    readonly property string cardBorder: current.cardBorder
    readonly property string text: current.text
    readonly property string textDim: current.textDim
    readonly property string textDisabled: current.textDisabled
    readonly property string accent: current.accent
    readonly property string accent2: current.accent2
    readonly property string onAccent: current.onAccent
    readonly property string success: current.success
    readonly property string danger: current.danger
    readonly property string hover: current.hover
    readonly property string pressed: current.pressed
}
