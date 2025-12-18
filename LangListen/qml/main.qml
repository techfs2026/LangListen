import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

ApplicationWindow {
    id: root
    visible: true
    width: 1280
    height: 820
    title: "Whisper 语音转录 & 精听练习系统"
    color: "#f8fbff"
    
    SplitView {
        anchors.fill: parent
        orientation: Qt.Horizontal
        
        Item {
            SplitView.fillWidth: true
            SplitView.minimumWidth: 600
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16
                
                Rectangle {
                    Layout.fillWidth: true
                    height: 160
                    color: "#ffffff"
                    radius: 12
                    border.color: "#e3f2fd"
                    border.width: 1
                    
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12
                        
                        Label {
                            text: "模型 & 音频"
                            font.pixelSize: 16
                            font.bold: true
                            color: "#1976d2"
                        }
                        
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            
                            Label {
                                text: "模型："
                                font.pixelSize: 13
                                color: "#616161"
                                Layout.preferredWidth: 50
                            }
                            TextField {
                                id: modelPathField
                                Layout.fillWidth: true
                                text: appController.modelPath
                                onTextChanged: appController.modelPath = text
                                placeholderText: "选择 Whisper 模型文件..."
                                font.pixelSize: 12
                                
                                background: Rectangle {
                                    color: parent.enabled ? "#fafafa" : "#f5f5f5"
                                    radius: 6
                                    border.color: parent.activeFocus ? "#1976d2" : "#e0e0e0"
                                    border.width: parent.activeFocus ? 2 : 1
                                }
                            }
                            Button {
                                text: "浏览"
                                font.pixelSize: 12
                                padding: 10
                                background: Rectangle {
                                    color: parent.down ? "#e3f2fd" : "#f5f5f5"
                                    radius: 6
                                    border.color: "#e0e0e0"
                                    border.width: 1
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: "#1976d2"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font: parent.font
                                }
                                onClicked: modelFileDialog.open()
                            }
                            Button {
                                text: "加载模型"
                                enabled: !appController.isProcessing
                                font.pixelSize: 12
                                padding: 10
                                background: Rectangle {
                                    color: parent.enabled ? (parent.down ? "#1565c0" : "#1976d2") : "#e0e0e0"
                                    radius: 6
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: parent.enabled ? "#ffffff" : "#9e9e9e"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font: parent.font
                                }
                                onClicked: appController.loadModel()
                            }
                        }
                        
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            
                            Label {
                                text: "音频："
                                font.pixelSize: 13
                                color: "#616161"
                                Layout.preferredWidth: 50
                            }
                            TextField {
                                id: audioPathField
                                Layout.fillWidth: true
                                text: appController.audioPath
                                onTextChanged: appController.audioPath = text
                                placeholderText: "选择音频文件..."
                                font.pixelSize: 12
                                
                                background: Rectangle {
                                    color: parent.enabled ? "#fafafa" : "#f5f5f5"
                                    radius: 6
                                    border.color: parent.activeFocus ? "#1976d2" : "#e0e0e0"
                                    border.width: parent.activeFocus ? 2 : 1
                                }
                            }
                            Button {
                                text: "浏览"
                                font.pixelSize: 12
                                padding: 10
                                background: Rectangle {
                                    color: parent.down ? "#e3f2fd" : "#f5f5f5"
                                    radius: 6
                                    border.color: "#e0e0e0"
                                    border.width: 1
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: "#1976d2"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font: parent.font
                                }
                                onClicked: audioFileDialog.open()
                            }
                            Button {
                                text: "开始转录"
                                enabled: appController.modelLoaded && !appController.isProcessing
                                font.pixelSize: 12
                                padding: 10
                                background: Rectangle {
                                    color: parent.enabled ? (parent.down ? "#2e7d32" : "#43a047") : "#e0e0e0"
                                    radius: 6
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: parent.enabled ? "#ffffff" : "#9e9e9e"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font: parent.font
                                }
                                onClicked: appController.startTranscription()
                            }
                        }
                        
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 16
                            
                            Label {
                                text: "模式: " + appController.computeMode
                                font.pixelSize: 12
                                color: "#757575"
                            }
                            Label {
                                text: "句子数: " + appController.segmentCount
                                font.pixelSize: 12
                                color: "#757575"
                            }
                            Item { Layout.fillWidth: true }
                        }
                        
                        ProgressBar {
                            Layout.fillWidth: true
                            from: 0
                            to: 100
                            value: appController.progress
                            
                            background: Rectangle {
                                implicitWidth: 200
                                implicitHeight: 6
                                color: "#e3f2fd"
                                radius: 3
                            }
                            
                            contentItem: Item {
                                implicitWidth: 200
                                implicitHeight: 6
                                
                                Rectangle {
                                    width: parent.parent.visualPosition * parent.width
                                    height: parent.height
                                    radius: 3
                                    color: "#1976d2"
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
                        anchors.margins: 16
                        spacing: 10
                        
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            
                            Label {
                                text: "转录结果"
                                font.pixelSize: 16
                                font.bold: true
                                color: "#1976d2"
                            }
                            
                            Item { Layout.fillWidth: true }
                            
                            Button {
                                text: "导出 SRT"
                                enabled: appController.segmentCount > 0
                                font.pixelSize: 12
                                padding: 8
                                background: Rectangle {
                                    color: parent.enabled ? (parent.down ? "#e3f2fd" : "#f5f5f5") : "#fafafa"
                                    radius: 6
                                    border.color: "#e0e0e0"
                                    border.width: 1
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: parent.enabled ? "#1976d2" : "#bdbdbd"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font: parent.font
                                }
                                onClicked: srtExportDialog.open()
                            }
                            Button {
                                text: "导出 LRC"
                                enabled: appController.segmentCount > 0
                                font.pixelSize: 12
                                padding: 8
                                background: Rectangle {
                                    color: parent.enabled ? (parent.down ? "#e3f2fd" : "#f5f5f5") : "#fafafa"
                                    radius: 6
                                    border.color: "#e0e0e0"
                                    border.width: 1
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: parent.enabled ? "#1976d2" : "#bdbdbd"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font: parent.font
                                }
                                onClicked: lrcExportDialog.open()
                            }
                            Button {
                                text: "导出文本"
                                enabled: appController.segmentCount > 0
                                font.pixelSize: 12
                                padding: 8
                                background: Rectangle {
                                    color: parent.enabled ? (parent.down ? "#e3f2fd" : "#f5f5f5") : "#fafafa"
                                    radius: 6
                                    border.color: "#e0e0e0"
                                    border.width: 1
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: parent.enabled ? "#1976d2" : "#bdbdbd"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font: parent.font
                                }
                                onClicked: txtExportDialog.open()
                            }
                            Button {
                                text: "清除"
                                font.pixelSize: 12
                                padding: 8
                                background: Rectangle {
                                    color: parent.down ? "#ffebee" : "#f5f5f5"
                                    radius: 6
                                    border.color: "#e0e0e0"
                                    border.width: 1
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: "#d32f2f"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font: parent.font
                                }
                                onClicked: appController.clearResult()
                            }
                        }
                        
                        ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            
                            TextArea {
                                text: appController.resultText
                                readOnly: true
                                wrapMode: Text.Wrap
                                selectByMouse: true
                                font.pixelSize: 13
                                color: "#212121"
                                background: Rectangle {
                                    color: "#fafafa"
                                    radius: 6
                                }
                            }
                        }
                    }
                }
                
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 140
                    color: "#ffffff"
                    radius: 12
                    border.color: "#e3f2fd"
                    border.width: 1
                    
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 8
                        
                        RowLayout {
                            Layout.fillWidth: true
                            
                            Label {
                                text: "运行日志"
                                font.pixelSize: 14
                                font.bold: true
                                color: "#1976d2"
                            }
                            
                            Item { Layout.fillWidth: true }
                            
                            Button {
                                text: "清除日志"
                                font.pixelSize: 11
                                padding: 6
                                background: Rectangle {
                                    color: parent.down ? "#ffebee" : "#f5f5f5"
                                    radius: 6
                                    border.color: "#e0e0e0"
                                    border.width: 1
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: "#d32f2f"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font: parent.font
                                }
                                onClicked: appController.clearLog()
                            }
                        }
                        
                        ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            
                            TextArea {
                                text: appController.logText
                                readOnly: true
                                wrapMode: Text.Wrap
                                font.family: "monospace"
                                font.pixelSize: 11
                                color: "#424242"
                                background: Rectangle {
                                    color: "#fafafa"
                                    radius: 6
                                }
                            }
                        }
                    }
                }
            }
        }
        
        Item {
            SplitView.preferredWidth: 580
            SplitView.minimumWidth: 450
            
            ListeningPracticePanel {
                anchors.fill: parent
                anchors.margins: 16
            }
        }
    }
    
    FileDialog {
        id: modelFileDialog
        title: "选择 Whisper 模型"
        nameFilters: ["模型文件 (*.bin)"]
        onAccepted: {
            var path = selectedFile.toString()
            path = path.replace(/^file:\/\/\//, "")
            appController.modelPath = path
        }
    }
    
    FileDialog {
        id: audioFileDialog
        title: "选择音频文件"
        nameFilters: ["音频文件 (*.wav *.mp3 *.m4a *.flac *.ogg)"]
        onAccepted: {
            var path = selectedFile.toString()
            path = path.replace(/^file:\/\/\//, "")
            appController.audioPath = path
        }
    }
    
    FileDialog {
        id: srtExportDialog
        title: "导出 SRT"
        fileMode: FileDialog.SaveFile
        nameFilters: ["SRT 文件 (*.srt)"]
        defaultSuffix: "srt"
        onAccepted: {
            var path = selectedFile.toString()
            path = path.replace(/^file:\/\/\//, "")
            appController.exportSRT(path)
        }
    }
    
    FileDialog {
        id: lrcExportDialog
        title: "导出 LRC"
        fileMode: FileDialog.SaveFile
        nameFilters: ["LRC 文件 (*.lrc)"]
        defaultSuffix: "lrc"
        onAccepted: {
            var path = selectedFile.toString()
            path = path.replace(/^file:\/\/\//, "")
            appController.exportLRC(path)
        }
    }
    
    FileDialog {
        id: txtExportDialog
        title: "导出文本"
        fileMode: FileDialog.SaveFile
        nameFilters: ["文本文件 (*.txt)"]
        defaultSuffix: "txt"
        onAccepted: {
            var path = selectedFile.toString()
            path = path.replace(/^file:\/\/\//, "")
            appController.exportPlainText(path)
        }
    }
    
    Connections {
        target: appController
        function onShowMessage(title, message, isError) {
            messageDialog.title = title
            messageDialog.text = message
            messageDialog.open()
        }
    }
    
    Dialog {
        id: messageDialog
        modal: true
        standardButtons: Dialog.Ok
        anchors.centerIn: parent
        
        background: Rectangle {
            color: "#ffffff"
            radius: 8
            border.color: "#e3f2fd"
            border.width: 1
        }
    }
}
