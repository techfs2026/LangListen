import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: dictationPanel
    
    property bool showAnswer: false
    property string userInput: ""
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16
        
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            
            Label {
                text: "✍️ 听写练习"
                font.pixelSize: 14
                font.bold: true
                color: "#9c27b0"
            }
            
            Label {
                text: "听音频写下你听到的内容"
                font.pixelSize: 11
                color: "#9e9e9e"
            }
            
            Item { Layout.fillWidth: true }
            
            Label {
                text: "第 1 / 50 句"
                font.pixelSize: 11
                font.bold: true
                color: "#9c27b0"
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            color: "#f3e5f5"
            radius: 6
            border.color: "#9c27b0"
            border.width: 1
            
            RowLayout {
                anchors.fill: parent
                spacing: 10
                
                Label {
                    text: "💡"
                    font.pixelSize: 20
                }
                
                Label {
                    Layout.fillWidth: true
                    text: "点击播放按钮听音频，然后在下方输入框输入你听到的内容"
                    font.pixelSize: 12
                    color: "#6a1b9a"
                    wrapMode: Text.Wrap
                }
            }
        }
        
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            
            Label {
                text: "你的听写:"
                font.pixelSize: 12
                font.bold: true
                color: "#424242"
            }
            
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                clip: true
                
                TextArea {
                    id: dictationInput
                    placeholderText: "在此输入你听到的内容..."
                    wrapMode: Text.Wrap
                    font.pixelSize: 13
                    text: userInput
                    onTextChanged: userInput = text
                    
                    background: Rectangle {
                        color: "#ffffff"
                        radius: 4
                        border.color: parent.activeFocus ? "#9c27b0" : "#e0e0e0"
                        border.width: 2
                    }
                }
            }
        }
        
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            
            Button {
                text: "🔊 播放"
                font.pixelSize: 13
                Layout.preferredHeight: 40
                
                background: Rectangle {
                    color: parent.down ? "#7b1fa2" : (parent.hovered ? "#8e24aa" : "#9c27b0")
                    radius: 6
                }
                
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                onClicked: {
                }
            }
            
            Button {
                text: showAnswer ? "隐藏答案" : "显示答案"
                font.pixelSize: 13
                Layout.preferredHeight: 40
                
                background: Rectangle {
                    color: parent.down ? "#e0e0e0" : (parent.hovered ? "#f5f5f5" : "#fafafa")
                    radius: 6
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
                    showAnswer = !showAnswer
                }
            }
            
            Item { Layout.fillWidth: true }
            
            Button {
                text: "上一句"
                font.pixelSize: 13
                Layout.preferredHeight: 40
                
                background: Rectangle {
                    color: parent.down ? "#e0e0e0" : (parent.hovered ? "#f5f5f5" : "#fafafa")
                    radius: 6
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
                    // TODO: 上一句
                }
            }
            
            Button {
                text: "下一句"
                font.pixelSize: 13
                Layout.preferredHeight: 40
                
                background: Rectangle {
                    color: parent.down ? "#7b1fa2" : (parent.hovered ? "#8e24aa" : "#9c27b0")
                    radius: 6
                }
                
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                onClicked: {
                    // TODO: 下一句
                }
            }
        }
        
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            visible: showAnswer
            color: "#e8f5e9"
            radius: 6
            border.color: "#4caf50"
            border.width: 1
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 4
                
                Label {
                    text: "✅ 正确答案:"
                    font.pixelSize: 11
                    font.bold: true
                    color: "#2e7d32"
                }
                
                Label {
                    Layout.fillWidth: true
                    text: "This is a sample sentence for dictation practice."
                    font.pixelSize: 13
                    color: "#424242"
                    wrapMode: Text.Wrap
                }
            }
        }
        
        Item { Layout.fillHeight: true }
        
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            color: "#fafafa"
            radius: 4
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 20
                
                Label {
                    text: "📊 本次练习统计"
                    font.pixelSize: 11
                    font.bold: true
                    color: "#616161"
                }
                
                Label {
                    text: "已完成: 0"
                    font.pixelSize: 11
                    color: "#757575"
                }
                
                Label {
                    text: "正确率: 0%"
                    font.pixelSize: 11
                    color: "#757575"
                }
                
                Item { Layout.fillWidth: true }
                
                Button {
                    text: "重置进度"
                    font.pixelSize: 11
                    Layout.preferredHeight: 28
                    
                    background: Rectangle {
                        color: parent.down ? "#e0e0e0" : (parent.hovered ? "#f5f5f5" : "transparent")
                        radius: 4
                        border.color: "#e0e0e0"
                        border.width: 1
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#757575"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: {
                        // TODO: 重置听写进度
                    }
                }
            }
        }
    }
}