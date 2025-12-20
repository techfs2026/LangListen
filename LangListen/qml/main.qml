import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs

ApplicationWindow {
    id: root
    visible: true
    width: 1280
    height: 820
    title: "LangListen"
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
                            }
                            Button {
                                text: "浏览"
                                font.pixelSize: 12
                                padding: 10
                                
                                background: Rectangle {
                                    color: parent.down ? "#1565c0" : "#1976d2"
                                    radius: 6
                                }
                                
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: "#ffffff"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
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
                                    font: parent.font
                                    color: parent.enabled ? "#ffffff" : "#9e9e9e"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
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
                            }
                            Button {
                                text: "浏览"
                                font.pixelSize: 12
                                padding: 10
                                
                                background: Rectangle {
                                    color: parent.down ? "#1565c0" : "#1976d2"
                                    radius: 6
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
                            Button {
                                text: "开始转写"
                                enabled: appController.modelLoaded && !appController.isProcessing
                                font.pixelSize: 12
                                padding: 10
                                
                                background: Rectangle {
                                    color: parent.enabled ? (parent.down ? "#1565c0" : "#1976d2") : "#e0e0e0"
                                    radius: 6
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
                                text: "转写结果"
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
                                    color: parent.enabled ? (parent.down ? "#1565c0" : "#1976d2") : "#e0e0e0"
                                    radius: 6
                                }
                                
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: parent.enabled ? "#ffffff" : "#9e9e9e"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                
                                onClicked: srtExportDialog.open()
                            }
                            Button {
                                text: "导出 LRC"
                                enabled: appController.segmentCount > 0
                                font.pixelSize: 12
                                padding: 8
                                
                                background: Rectangle {
                                    color: parent.enabled ? (parent.down ? "#1565c0" : "#1976d2") : "#e0e0e0"
                                    radius: 6
                                }
                                
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: parent.enabled ? "#ffffff" : "#9e9e9e"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                
                                onClicked: lrcExportDialog.open()
                            }
                            Button {
                                text: "导出文本"
                                enabled: appController.segmentCount > 0
                                font.pixelSize: 12
                                padding: 8
                                
                                background: Rectangle {
                                    color: parent.enabled ? (parent.down ? "#1565c0" : "#1976d2") : "#e0e0e0"
                                    radius: 6
                                }
                                
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: parent.enabled ? "#ffffff" : "#9e9e9e"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                
                                onClicked: txtExportDialog.open()
                            }
                            Button {
                                text: "清除"
                                font.pixelSize: 12
                                padding: 8
                                
                                background: Rectangle {
                                    color: parent.down ? "#ef5350" : "#f44336"
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
                            
                            TextArea {
                                id: resultTextArea
                                text: appController.resultText
                                readOnly: true
                                wrapMode: Text.Wrap
                                selectByMouse: true
                                font.pixelSize: 13
                                color: "#212121"
                                
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
                                    color: parent.down ? "#ef5350" : "#f44336"
                                    radius: 6
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
                        }
                        
                        ScrollView {
                            id: logScrollView
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
            messageDialog.informativeText = message
            messageDialog.open()
        }
    }
    
    Dialog {
        id: messageDialog
        modal: true
        standardButtons: Dialog.Ok
        anchors.centerIn: parent
        
        property alias informativeText: messageLabel.text
        
        Label {
            id: messageLabel
            wrapMode: Text.Wrap
            width: Math.min(400, root.width * 0.8)
        }
    }
}