import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: transcriptionPage
    
    signal navigateToListening()
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 40
        anchors.leftMargin: 80
        anchors.rightMargin: 80
        spacing: 20
        
        Label {
            Layout.fillWidth: true
            text: "语音转写"
            font.pixelSize: 32
            font.bold: true
            color: "#1976d2"
            horizontalAlignment: Text.AlignHCenter
        }
        
        Label {
            Layout.fillWidth: true
            text: "将音频文件转换为带时间轴的文本"
            font.pixelSize: 14
            color: "#757575"
            horizontalAlignment: Text.AlignHCenter
        }
        
        Item { Layout.preferredHeight: 10 }
        
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 100
            color: "#ffffff"
            radius: 12
            border.color: "#e3f2fd"
            border.width: 1
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12
                
                Label {
                    text: "1. 选择 Whisper 模型"
                    font.pixelSize: 16
                    font.bold: true
                    color: "#424242"
                }
                
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    
                    TextField {
                        id: modelPathField
                        Layout.fillWidth: true
                        text: appController.modelPath
                        onTextChanged: appController.modelPath = text
                        placeholderText: "选择 Whisper 模型文件 (.bin)..."
                        font.pixelSize: 13
                        
                        background: Rectangle {
                            color: "#f5f5f5"
                            radius: 6
                            border.color: parent.activeFocus ? "#1976d2" : "#e0e0e0"
                            border.width: parent.activeFocus ? 2 : 1
                        }
                    }
                    
                    Button {
                        text: "浏览"
                        font.pixelSize: 13
                        padding: 12
                        
                        background: Rectangle {
                            color: parent.down ? "#1565c0" : (parent.hovered ? "#1976d2" : "#2196f3")
                            radius: 8
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#ffffff"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: root.openModelFileDialog()
                    }
                    
                    Button {
                        text: appController.modelLoaded ? "✓ 已加载" : "加载模型"
                        enabled: !appController.isProcessing && !appController.modelLoaded && appController.modelPath !== ""
                        font.pixelSize: 13
                        padding: 12
                        
                        background: Rectangle {
                            color: {
                                if (appController.modelLoaded) return "#4caf50"
                                if (!parent.enabled) return "#e0e0e0"
                                return parent.down ? "#1565c0" : (parent.hovered ? "#1976d2" : "#2196f3")
                            }
                            radius: 8
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: parent.enabled || appController.modelLoaded ? "#ffffff" : "#9e9e9e"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: appController.loadModel()
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 100
            color: "#ffffff"
            radius: 12
            border.color: "#e3f2fd"
            border.width: 1
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12
                
                Label {
                    text: "2. 选择音频文件"
                    font.pixelSize: 16
                    font.bold: true
                    color: "#424242"
                }
                
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    
                    TextField {
                        id: audioPathField
                        Layout.fillWidth: true
                        text: appController.audioPath
                        onTextChanged: appController.audioPath = text
                        placeholderText: "选择音频文件 (WAV, MP3, M4A, FLAC, OGG)..."
                        font.pixelSize: 13
                        
                        background: Rectangle {
                            color: "#f5f5f5"
                            radius: 6
                            border.color: parent.activeFocus ? "#1976d2" : "#e0e0e0"
                            border.width: parent.activeFocus ? 2 : 1
                        }
                    }
                    
                    Button {
                        text: "浏览"
                        font.pixelSize: 13
                        padding: 12
                        
                        background: Rectangle {
                            color: parent.down ? "#1565c0" : (parent.hovered ? "#1976d2" : "#2196f3")
                            radius: 8
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#ffffff"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: root.openAudioFileDialog()
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 120
            color: "#ffffff"
            radius: 12
            border.color: "#e3f2fd"
            border.width: 1
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 16
                
                Label {
                    text: "3. 开始转写"
                    font.pixelSize: 16
                    font.bold: true
                    color: "#424242"
                }
                
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    
                    Button {
                        Layout.preferredWidth: 160
                        Layout.preferredHeight: 50
                        text: "开始转写"
                        enabled: appController.modelLoaded && !appController.isProcessing && appController.audioPath !== ""
                        font.pixelSize: 16
                        font.bold: true
                        
                        background: Rectangle {
                            color: {
                                if (!parent.enabled) return "#e0e0e0"
                                return parent.down ? "#1565c0" : (parent.hovered ? "#1976d2" : "#2196f3")
                            }
                            radius: 10
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: parent.enabled ? "#ffffff" : "#9e9e9e"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: appController.startTranscription()
                    }
                    
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 20
                            
                            Label {
                                text: "计算模式: " + appController.computeMode
                                font.pixelSize: 13
                                color: "#616161"
                            }
                            
                            Label {
                                text: "已识别句子: " + appController.segmentCount
                                font.pixelSize: 13
                                color: "#616161"
                            }
                        }
                        
                        ProgressBar {
                            Layout.fillWidth: true
                            from: 0
                            to: 100
                            value: appController.progress
                            
                            background: Rectangle {
                                implicitHeight: 8
                                color: "#e0e0e0"
                                radius: 4
                            }
                            
                            contentItem: Item {
                                Rectangle {
                                    width: parent.width * (appController.progress / 100.0)
                                    height: parent.height
                                    radius: 4
                                    color: "#2196f3"
                                    
                                    Behavior on width {
                                        NumberAnimation { duration: 200 }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#ffffff"
            radius: 12
            border.color: "#e3f2fd"
            border.width: 1
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12
                
                RowLayout {
                    Layout.fillWidth: true
                    
                    Label {
                        text: "转写结果"
                        font.pixelSize: 16
                        font.bold: true
                        color: "#424242"
                    }
                    
                    Item { Layout.fillWidth: true }
                    
                    Button {
                        text: "清除"
                        font.pixelSize: 12
                        padding: 8
                        
                        background: Rectangle {
                            color: parent.down ? "#ef5350" : (parent.hovered ? "#f44336" : "#ff5252")
                            radius: 6
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#ffffff"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: appController.clearResult()
                    }
                }
                
                ScrollView {
                    id: resultScrollView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    
                    background: Rectangle {
                        color: "#fafafa"
                        radius: 8
                    }
                    
                    TextArea {
                        id: resultTextArea
                        text: appController.resultText
                        readOnly: true
                        wrapMode: Text.Wrap
                        selectByMouse: true
                        font.pixelSize: 13
                        color: "#212121"
                        padding: 12
                        
                        background: Rectangle {
                            color: "transparent"
                        }
                        
                        placeholderText: "转写结果将在此显示..."
                        
                        onTextChanged: {
                            Qt.callLater(function() {
                                resultScrollView.ScrollBar.vertical.position = 1.0 - resultScrollView.ScrollBar.vertical.size
                            })
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: logExpander.expanded ? 160 : 40
            color: "#ffffff"
            radius: 12
            border.color: "#e3f2fd"
            border.width: 1
            
            Behavior on Layout.preferredHeight {
                NumberAnimation { duration: 200 }
            }
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8
                
                RowLayout {
                    Layout.fillWidth: true
                    
                    Label {
                        text: "运行日志"
                        font.pixelSize: 14
                        font.bold: true
                        color: "#424242"
                    }
                    
                    Item { Layout.fillWidth: true }
                    
                    Button {
                        text: "清除"
                        font.pixelSize: 11
                        padding: 6
                        visible: logExpander.expanded
                        
                        background: Rectangle {
                            color: parent.down ? "#ef5350" : (parent.hovered ? "#f44336" : "#ff5252")
                            radius: 4
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#ffffff"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: appController.clearLog()
                    }
                    
                    Button {
                        id: logExpander
                        property bool expanded: false
                        
                        text: expanded ? "▼" : "▶"
                        font.pixelSize: 12
                        padding: 6
                        
                        background: Rectangle {
                            color: parent.down ? "#e0e0e0" : (parent.hovered ? "#f5f5f5" : "transparent")
                            radius: 4
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#616161"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: expanded = !expanded
                    }
                }
                
                ScrollView {
                    id: logScrollView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: logExpander.expanded
                    clip: true
                    
                    background: Rectangle {
                        color: "#fafafa"
                        radius: 6
                    }
                    
                    TextArea {
                        text: appController.logText
                        readOnly: true
                        wrapMode: Text.Wrap
                        font.family: "monospace"
                        font.pixelSize: 11
                        color: "#424242"
                        padding: 8
                        
                        background: Rectangle {
                            color: "transparent"
                        }
                        
                        onTextChanged: {
                            Qt.callLater(function() {
                                logScrollView.ScrollBar.vertical.position = 1.0 - logScrollView.ScrollBar.vertical.size
                            })
                        }
                    }
                }
            }
        }
    }
}
