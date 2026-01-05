import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: practicePanel
    
    property bool autoPauseEnabled: true
    property bool loopEnabled: false
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16
        
        // 标题和说明
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            
            Label {
                text: "🎧 精听练习"
                font.pixelSize: 14
                font.bold: true
                color: "#4caf50"
            }
            
            Label {
                text: "逐句精听，提升语言理解能力"
                font.pixelSize: 11
                color: "#9e9e9e"
            }
            
            Item { Layout.fillWidth: true }
        }
        
        // 当前句子信息
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            color: "#e8f5e9"
            radius: 6
            border.color: "#4caf50"
            border.width: 1
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12
                
                Label {
                    text: "📌"
                    font.pixelSize: 24
                }
                
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    
                    Label {
                        text: "当前句子: 第 1 句"
                        font.pixelSize: 13
                        font.bold: true
                        color: "#2e7d32"
                    }
                    
                    Label {
                        Layout.fillWidth: true
                        text: "This is a sample sentence for intensive listening practice."
                        font.pixelSize: 12
                        color: "#424242"
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
        
        // 播放控制按钮组
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            
            Button {
                Layout.preferredWidth: 60
                Layout.preferredHeight: 50
                text: "⏮"
                font.pixelSize: 20
                
                ToolTip.visible: hovered
                ToolTip.text: "上一句 (←)"
                ToolTip.delay: 500
                
                background: Rectangle {
                    color: parent.down ? "#e0e0e0" : (parent.hovered ? "#f5f5f5" : "#fafafa")
                    radius: 8
                    border.color: "#e0e0e0"
                    border.width: 1
                }
                
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: "#424242"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                onClicked: {
                    // TODO: 上一句
                }
            }
            
            Button {
                Layout.preferredWidth: 60
                Layout.preferredHeight: 50
                text: "▶"
                font.pixelSize: 22
                
                ToolTip.visible: hovered
                ToolTip.text: "播放/暂停 (Space)"
                ToolTip.delay: 500
                
                background: Rectangle {
                    color: parent.down ? "#388e3c" : (parent.hovered ? "#43a047" : "#4caf50")
                    radius: 8
                }
                
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                onClicked: {
                    // TODO: 播放/暂停
                }
            }
            
            Button {
                Layout.preferredWidth: 60
                Layout.preferredHeight: 50
                text: "⏭"
                font.pixelSize: 20
                
                ToolTip.visible: hovered
                ToolTip.text: "下一句 (→)"
                ToolTip.delay: 500
                
                background: Rectangle {
                    color: parent.down ? "#e0e0e0" : (parent.hovered ? "#f5f5f5" : "#fafafa")
                    radius: 8
                    border.color: "#e0e0e0"
                    border.width: 1
                }
                
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: "#424242"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                onClicked: {
                    // TODO: 下一句
                }
            }
            
            Rectangle {
                width: 1
                Layout.preferredHeight: 40
                color: "#e0e0e0"
            }
            
            Button {
                Layout.preferredWidth: 60
                Layout.preferredHeight: 50
                text: loopEnabled ? "🔁" : "➡"
                font.pixelSize: 20
                
                ToolTip.visible: hovered
                ToolTip.text: loopEnabled ? "关闭单句循环" : "开启单句循环"
                ToolTip.delay: 500
                
                background: Rectangle {
                    color: loopEnabled ? "#4caf50" : (parent.down ? "#e0e0e0" : (parent.hovered ? "#f5f5f5" : "#fafafa"))
                    radius: 8
                    border.color: loopEnabled ? "#43a047" : "#e0e0e0"
                    border.width: 1
                }
                
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: loopEnabled ? "#ffffff" : "#424242"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                onClicked: {
                    loopEnabled = !loopEnabled
                }
            }
            
            Item { Layout.fillWidth: true }
        }
        
        // 功能选项
        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            
            Switch {
                id: autoPauseSwitch
                checked: autoPauseEnabled
                onCheckedChanged: autoPauseEnabled = checked
                
                ToolTip.visible: hovered
                ToolTip.text: "开启后每句播放完会自动暂停"
                ToolTip.delay: 500
                
                indicator: Rectangle {
                    implicitWidth: 44
                    implicitHeight: 24
                    radius: 12
                    color: autoPauseSwitch.checked ? "#4caf50" : "#bdbdbd"
                    
                    Rectangle {
                        x: autoPauseSwitch.checked ? parent.width - width - 2 : 2
                        y: 2
                        width: 20
                        height: 20
                        radius: 10
                        color: "#ffffff"
                        
                        Behavior on x {
                            NumberAnimation { duration: 150 }
                        }
                    }
                }
                
                contentItem: Text {
                    text: "自动暂停"
                    color: "#424242"
                    font.pixelSize: 12
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: autoPauseSwitch.indicator.width + 8
                }
            }
            
            Item { Layout.fillWidth: true }
            
            // 播放速度控制
            RowLayout {
                spacing: 8
                
                Label {
                    text: "播放速度:"
                    font.pixelSize: 12
                    color: "#616161"
                }
                
                ComboBox {
                    Layout.preferredWidth: 80
                    model: ["0.5x", "0.75x", "1.0x", "1.25x", "1.5x"]
                    currentIndex: 2
                    font.pixelSize: 11
                    
                    background: Rectangle {
                        color: "#f5f5f5"
                        radius: 4
                        border.color: parent.activeFocus ? "#4caf50" : "#e0e0e0"
                        border.width: 1
                    }
                }
            }
        }
        
        Item { Layout.fillHeight: true }
    }
}