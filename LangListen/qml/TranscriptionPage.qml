import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs

Item {
    id: transcriptionPage
    
    signal navigateToListening()
    
    FileDialog {
        id: audioFileDialog
        title: "选择音频文件"
        nameFilters: ["音频文件 (*.wav *.mp3 *.m4a *.flac *.ogg)"]
        onAccepted: {
            var path = selectedFile.toString()
            path = path.replace(/^file:\/\/\//, "")
            appController.audioPath = path
            appController.startOneClickTranscription()
        }
    }
    
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
            text: "选择音频文件后自动开始转写"
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
                    text: "模型设置"
                    font.pixelSize: 16
                    font.bold: true
                    color: "#424242"
                }
                
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    
                    Label {
                        text: "模型类型:"
                        font.pixelSize: 13
                        color: "#616161"
                    }
                    
                    ButtonGroup {
                        id: modelTypeGroup
                    }
                    
                    RadioButton {
                        text: "Base (基础)"
                        font.pixelSize: 13
                        checked: appController.modelType === "base"
                        ButtonGroup.group: modelTypeGroup
                        onClicked: appController.modelType = "base"
                    }
                    
                    RadioButton {
                        text: "Small (小)"
                        font.pixelSize: 13
                        checked: appController.modelType === "small"
                        ButtonGroup.group: modelTypeGroup
                        onClicked: appController.modelType = "small"
                    }
                    
                    RadioButton {
                        text: "Medium (中)"
                        font.pixelSize: 13
                        checked: appController.modelType === "medium"
                        ButtonGroup.group: modelTypeGroup
                        onClicked: appController.modelType = "medium"
                    }

                    RadioButton {
                        text: "Turbo (大)"
                        font.pixelSize: 13
                        checked: appController.modelType === "turbo"
                        ButtonGroup.group: modelTypeGroup
                        onClicked: appController.modelType = "turbo"
                    }
                    
                    Item { Layout.fillWidth: true }
                    
                    Label {
                        text: "目录: " + appController.modelBasePath
                        font.pixelSize: 11
                        color: "#9e9e9e"
                        elide: Text.ElideMiddle
                        Layout.maximumWidth: 350
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
                    text: "音频文件"
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
                        placeholderText: "选择音频文件 (WAV, MP3, M4A, FLAC, OGG)..."
                        readOnly: true
                        font.pixelSize: 13
                        
                        background: Rectangle {
                            color: "#f5f5f5"
                            radius: 6
                            border.color: parent.activeFocus ? "#1976d2" : "#e0e0e0"
                            border.width: parent.activeFocus ? 2 : 1
                        }
                    }
                    
                    Button {
                        text: "一键转写"
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
                        
                        onClicked: audioFileDialog.open()
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
                
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 20
                    
                    Label {
                        text: "状态: " + appController.currentStatus
                        font.pixelSize: 14
                        font.bold: true
                        color: {
                            if (appController.currentStatus.indexOf("成功") >= 0 || 
                                appController.currentStatus.indexOf("完成") >= 0) {
                                return "#4caf50"
                            } else if (appController.currentStatus.indexOf("失败") >= 0 || 
                                       appController.currentStatus.indexOf("错误") >= 0) {
                                return "#f44336"
                            } else if (appController.currentStatus.indexOf("正在") >= 0) {
                                return "#ff9800"
                            }
                            return "#616161"
                        }
                    }
                    
                    Label {
                        text: "计算模式: " + appController.computeMode
                        font.pixelSize: 13
                        color: "#616161"
                        visible: appController.computeMode !== "Unknown"
                    }
                    
                    Label {
                        text: "已识别句子: " + appController.segmentCount
                        font.pixelSize: 13
                        color: "#616161"
                    }
                    
                    Item { Layout.fillWidth: true }
                    
                    Label {
                        text: "进度: " + Math.round(appController.progress) + "%"
                        font.pixelSize: 12
                        color: "#9e9e9e"
                    }
                }
                
                ProgressBar {
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    value: appController.progress
                    
                    background: Rectangle {
                        implicitHeight: 10
                        color: "#e0e0e0"
                        radius: 5
                    }
                    
                    contentItem: Item {
                        Rectangle {
                            width: parent.width * (appController.progress / 100.0)
                            height: parent.height
                            radius: 5
                            
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#2196f3" }
                                GradientStop { position: 1.0; color: "#1976d2" }
                            }
                            
                            Behavior on width {
                                NumberAnimation { duration: 200 }
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
                        text: "转写结果（实时显示）"
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
                        
                        placeholderText: "转写结果将在此实时显示...\n\n使用步骤：\n1. 选择模型类型（Base/Small/Medium/Turbo，默认Medium）\n2. 点击\"浏览\"选择音频文件，自动开始转写！\n\n支持的音频格式：WAV, MP3, M4A, FLAC, OGG\n\n模型文件位置（优先级）：\n• 程序目录/models（推荐）\n• D:/models"
                        
                        onTextChanged: {
                            Qt.callLater(function() {
                                resultScrollView.ScrollBar.vertical.position = 1.0 - resultScrollView.ScrollBar.vertical.size
                            })
                        }
                    }
                }
            }
        }
    }
}