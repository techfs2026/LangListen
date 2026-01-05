import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: editPanel
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 12
        
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            
            Label {
                text: "🤖 智能转写"
                font.pixelSize: 14
                font.bold: true
                color: "#424242"
            }
            
            ComboBox {
                Layout.preferredWidth: 120
                model: ["Base", "Small", "Medium", "Turbo"]
                currentIndex: 2
                font.pixelSize: 12
                
                background: Rectangle {
                    color: "#f5f5f5"
                    radius: 4
                    border.color: parent.activeFocus ? "#2196f3" : "#e0e0e0"
                    border.width: 1
                }
            }
            
            Button {
                text: "一键转写"
                font.pixelSize: 12
                Layout.preferredHeight: 32
                
                background: Rectangle {
                    color: parent.down ? "#1565c0" : (parent.hovered ? "#1976d2" : "#2196f3")
                    radius: 4
                }
                
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                onClicked: {
                    // TODO: 调用转写功能
                    appController.startOneClickTranscription()
                }
            }
            
            Item { Layout.fillWidth: true }
            
            Label {
                text: "状态: 就绪"
                font.pixelSize: 11
                color: "#757575"
            }
        }
        
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#e0e0e0"
        }
        
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            
            Label {
                text: "当前句子编辑"
                font.pixelSize: 13
                font.bold: true
                color: "#424242"
            }
            
            Label {
                text: "(未选择)"
                font.pixelSize: 11
                color: "#9e9e9e"
            }
        }
        
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            
            Label {
                text: "起始时间:"
                font.pixelSize: 12
                color: "#616161"
                Layout.preferredWidth: 70
            }
            
            TextField {
                id: startTimeField
                Layout.preferredWidth: 100
                text: "00:00.000"
                font.family: "monospace"
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                
                background: Rectangle {
                    color: "#f5f5f5"
                    radius: 4
                    border.color: parent.activeFocus ? "#2196f3" : "#e0e0e0"
                    border.width: 1
                }
            }
            
            Button {
                text: "←"
                font.pixelSize: 16
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                
                ToolTip.visible: hovered
                ToolTip.text: "从波形设置起点"
                ToolTip.delay: 500
                
                background: Rectangle {
                    color: parent.down ? "#e0e0e0" : (parent.hovered ? "#f5f5f5" : "#fafafa")
                    radius: 4
                    border.color: "#e0e0e0"
                    border.width: 1
                }
                
                onClicked: {
                    // TODO: 从当前播放位置设置起点
                }
            }
            
            Item { Layout.preferredWidth: 20 }
            
            Label {
                text: "结束时间:"
                font.pixelSize: 12
                color: "#616161"
                Layout.preferredWidth: 70
            }
            
            TextField {
                id: endTimeField
                Layout.preferredWidth: 100
                text: "00:00.000"
                font.family: "monospace"
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                
                background: Rectangle {
                    color: "#f5f5f5"
                    radius: 4
                    border.color: parent.activeFocus ? "#2196f3" : "#e0e0e0"
                    border.width: 1
                }
            }
            
            Button {
                text: "→"
                font.pixelSize: 16
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                
                ToolTip.visible: hovered
                ToolTip.text: "从波形设置终点"
                ToolTip.delay: 500
                
                background: Rectangle {
                    color: parent.down ? "#e0e0e0" : (parent.hovered ? "#f5f5f5" : "#fafafa")
                    radius: 4
                    border.color: "#e0e0e0"
                    border.width: 1
                }
                
                onClicked: {
                    // TODO: 从当前播放位置设置终点
                }
            }
        }
        
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            
            Label {
                text: "字幕文本:"
                font.pixelSize: 12
                color: "#616161"
                Layout.preferredWidth: 70
                Layout.alignment: Qt.AlignTop
            }
            
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 60
                clip: true
                
                TextArea {
                    id: textEditArea
                    placeholderText: "在此编辑字幕文本..."
                    wrapMode: Text.Wrap
                    font.pixelSize: 13
                    
                    background: Rectangle {
                        color: "#f5f5f5"
                        radius: 4
                        border.color: parent.activeFocus ? "#2196f3" : "#e0e0e0"
                        border.width: 1
                    }
                }
            }
        }
        
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            
            Item { Layout.fillWidth: true }
            
            Button {
                text: "应用更改"
                font.pixelSize: 12
                Layout.preferredHeight: 32
                
                background: Rectangle {
                    color: parent.down ? "#388e3c" : (parent.hovered ? "#43a047" : "#4caf50")
                    radius: 4
                }
                
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                onClicked: {
                    // TODO: 保存编辑
                }
            }
            
            Button {
                text: "重置"
                font.pixelSize: 12
                Layout.preferredHeight: 32
                
                background: Rectangle {
                    color: parent.down ? "#e0e0e0" : (parent.hovered ? "#f5f5f5" : "#fafafa")
                    radius: 4
                    border.color: "#e0e0e0"
                    border.width: 1
                }
                
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: "#616161"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                onClicked: {
                    // TODO: 重置编辑
                }
            }
        }
    }
}