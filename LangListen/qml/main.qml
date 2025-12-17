import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Dialogs

ApplicationWindow {
    id: root
    width: 1000
    height: 750
    visible: true
    title: "LangListen"
    color: "#ffffff"
    
    Dialog {
        id: messageDialog
        modal: true
        anchors.centerIn: parent
        standardButtons: Dialog.Ok
        
        property bool isError: false
        
        contentItem: Rectangle {
            implicitWidth: 400
            implicitHeight: 150
            color: "#ffffff"
            border.color: "#e0e0e0"
            border.width: 1
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 15
                
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 3
                    color: messageDialog.isError ? "#dc3545" : "#28a745"
                }
                
                Text {
                    id: messageText
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    wrapMode: Text.WordWrap
                    font.pixelSize: 14
                    color: "#000000"
                }
            }
        }
    }
    
    FileDialog {
        id: modelFileDialog
        title: "选择Whisper模型文件"
        nameFilters: ["模型文件 (*.bin)", "所有文件 (*)"]
        onAccepted: {
            appController.modelPath = selectedFile.toString().replace("file:///", "")
        }
    }
    
    FileDialog {
        id: audioFileDialog
        title: "选择音频文件"
        nameFilters: ["音频文件 (*.wav)", "所有文件 (*)"]
        onAccepted: {
            appController.audioPath = selectedFile.toString().replace("file:///", "")
        }
    }
    
    Connections {
        target: appController
        function onShowMessage(title, message, isError) {
            messageDialog.title = title
            messageText.text = message
            messageDialog.isError = isError
            messageDialog.open()
        }
    }
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 15
        
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 70
            color: "#000000"
            radius: 4
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: 15
                spacing: 15
                
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5
                    
                    Text {
                        text: "LangListen"
                        font.pixelSize: 20
                        font.bold: true
                        color: "#ffffff"
                    }
                    
                    Text {
                        text: "计算模式: " + appController.computeMode
                        font.pixelSize: 12
                        color: "#cccccc"
                    }
                }
                
                Rectangle {
                    Layout.preferredWidth: 120
                    Layout.preferredHeight: 36
                    color: appController.modelLoaded ? "#28a745" : "#6c757d"
                    radius: 4
                    
                    Text {
                        anchors.centerIn: parent
                        text: appController.modelLoaded ? "✓ 已加载" : "未加载"
                        color: "#ffffff"
                        font.pixelSize: 13
                        font.bold: true
                    }
                }
            }
        }
        
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 50 : 0
            visible: appController.modelLoaded && appController.computeMode === "CPU模式"
            color: "#fff8e1"
            border.color: "#ffc107"
            border.width: 1
            radius: 4
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10
                
                Text {
                    text: "⚠"
                    font.pixelSize: 20
                    color: "#000000"
                }
                
                Text {
                    Layout.fillWidth: true
                    text: "正在使用CPU模式（速度较慢）- 如需GPU加速请查看日志"
                    font.pixelSize: 12
                    color: "#000000"
                    wrapMode: Text.WordWrap
                }
            }
        }
        
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 50 : 0
            visible: appController.modelLoaded && appController.computeMode === "GPU加速"
            color: "#e8f5e9"
            border.color: "#28a745"
            border.width: 1
            radius: 4
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10
                
                Text {
                    text: "⚡"
                    font.pixelSize: 20
                }
                
                Text {
                    text: "GPU加速已启用"
                    font.pixelSize: 12
                    font.bold: true
                    color: "#000000"
                }
            }
        }
        
        GroupBox {
            Layout.fillWidth: true
            Layout.preferredHeight: 90
            padding: 15
            topPadding: 35
            
            background: Rectangle {
                y: 20
                width: parent.width
                height: parent.height - 20
                color: "#ffffff"
                border.color: "#cccccc"
                border.width: 1
                radius: 4
            }
            
            label: Rectangle {
                x: 10
                width: labelText.width + 20
                height: 25
                color: "#ffffff"
                
                Text {
                    id: labelText
                    anchors.centerIn: parent
                    text: "模型配置"
                    font.pixelSize: 13
                    font.bold: true
                    color: "#000000"
                }
            }
            
            RowLayout {
                width: parent.width
                spacing: 10
                
                Text {
                    text: "模型文件:"
                    font.pixelSize: 13
                    color: "#000000"
                    Layout.preferredWidth: 70
                }
                
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    color: "#f5f5f5"
                    radius: 4
                    border.color: "#cccccc"
                    border.width: 1
                    
                    TextInput {
                        anchors.fill: parent
                        anchors.margins: 8
                        text: appController.modelPath
                        readOnly: true
                        verticalAlignment: Text.AlignVCenter
                        color: "#000000"
                        clip: true
                    }
                }
                
                Button {
                    text: "选择"
                    Layout.preferredWidth: 80
                    Layout.preferredHeight: 36
                    enabled: !appController.isProcessing
                    
                    background: Rectangle {
                        color: parent.enabled ? (parent.hovered ? "#0056b3" : "#007bff") : "#6c757d"
                        radius: 4
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 13
                    }
                    
                    onClicked: modelFileDialog.open()
                }
                
                Button {
                    text: "加载"
                    Layout.preferredWidth: 80
                    Layout.preferredHeight: 36
                    enabled: !appController.isProcessing && appController.modelPath !== ""
                    
                    background: Rectangle {
                        color: parent.enabled ? (parent.hovered ? "#0056b3" : "#007bff") : "#6c757d"
                        radius: 4
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 13
                    }
                    
                    onClicked: appController.loadModel()
                }
            }
        }

        GroupBox {
            Layout.fillWidth: true
            Layout.preferredHeight: 90
            padding: 15
            topPadding: 35
            
            background: Rectangle {
                y: 20
                width: parent.width
                height: parent.height - 20
                color: "#ffffff"
                border.color: "#cccccc"
                border.width: 1
                radius: 4
            }
            
            label: Rectangle {
                x: 10
                width: audioLabelText.width + 20
                height: 25
                color: "#ffffff"
                
                Text {
                    id: audioLabelText
                    anchors.centerIn: parent
                    text: "音频文件"
                    font.pixelSize: 13
                    font.bold: true
                    color: "#000000"
                }
            }
            
            RowLayout {
                width: parent.width
                spacing: 10
                
                Text {
                    text: "音频文件:"
                    font.pixelSize: 13
                    color: "#000000"
                    Layout.preferredWidth: 70
                }
                
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    color: "#f5f5f5"
                    radius: 4
                    border.color: "#cccccc"
                    border.width: 1
                    
                    TextInput {
                        anchors.fill: parent
                        anchors.margins: 8
                        text: appController.audioPath
                        readOnly: true
                        verticalAlignment: Text.AlignVCenter
                        color: "#000000"
                        clip: true
                    }
                }
                
                Button {
                    text: "选择"
                    Layout.preferredWidth: 80
                    Layout.preferredHeight: 36
                    enabled: !appController.isProcessing
                    
                    background: Rectangle {
                        color: parent.enabled ? (parent.hovered ? "#0056b3" : "#007bff") : "#6c757d"
                        radius: 4
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 13
                    }
                    
                    onClicked: audioFileDialog.open()
                }
            }
        }

        GroupBox {
            Layout.fillWidth: true
            Layout.preferredHeight: 130
            padding: 15
            topPadding: 35
            
            background: Rectangle {
                y: 20
                width: parent.width
                height: parent.height - 20
                color: "#ffffff"
                border.color: "#cccccc"
                border.width: 1
                radius: 4
            }
            
            label: Rectangle {
                x: 10
                width: controlLabelText.width + 20
                height: 25
                color: "#ffffff"
                
                Text {
                    id: controlLabelText
                    anchors.centerIn: parent
                    text: "转写控制"
                    font.pixelSize: 13
                    font.bold: true
                    color: "#000000"
                }
            }
            
            ColumnLayout {
                width: parent.width
                spacing: 10
                
                Button {
                    text: appController.isProcessing ? "处理中..." : "开始转写"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 45
                    enabled: !appController.isProcessing && appController.modelLoaded && appController.audioPath !== ""
                    
                    background: Rectangle {
                        color: {
                            if (!parent.enabled) return "#6c757d"
                            return parent.hovered ? "#0056b3" : "#007bff"
                        }
                        radius: 4
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 15
                        font.bold: true
                    }
                    
                    onClicked: appController.startTranscription()
                }
                
                ProgressBar {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 25
                    value: appController.progress / 100.0
                    
                    background: Rectangle {
                        color: "#f5f5f5"
                        radius: 4
                        border.color: "#cccccc"
                        border.width: 1
                    }
                    
                    contentItem: Item {
                        Rectangle {
                            width: parent.parent.visualPosition * parent.width
                            height: parent.height
                            color: "#28a745"
                            radius: 4
                        }
                        
                        Text {
                            anchors.centerIn: parent
                            text: appController.progress + "%"
                            color: appController.progress > 50 ? "#ffffff" : "#000000"
                            font.pixelSize: 12
                            font.bold: true
                        }
                    }
                }
            }
        }
        
        GroupBox {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 150
            padding: 15
            topPadding: 35
            
            background: Rectangle {
                y: 20
                width: parent.width
                height: parent.height - 20
                color: "#ffffff"
                border.color: "#cccccc"
                border.width: 1
                radius: 4
            }
            
            label: Rectangle {
                x: 10
                width: resultLabelText.width + 20
                height: 25
                color: "#ffffff"
                
                Text {
                    id: resultLabelText
                    anchors.centerIn: parent
                    text: "转写结果"
                    font.pixelSize: 13
                    font.bold: true
                    color: "#000000"
                }
            }
            
            ScrollView {
                anchors.fill: parent
                clip: true
                
                TextArea {
                    id: resultTextArea
                    text: appController.resultText
                    readOnly: true
                    wrapMode: Text.WordWrap
                    font.pixelSize: 13
                    font.family: "Consolas, Courier New, monospace"
                    color: "#000000"
                    background: Rectangle {
                        color: "#fafafa"
                    }
                    placeholderText: "转写结果将显示在这里..."
                    
                    onTextChanged: {
                        if (appController.isProcessing) {
                            resultTextArea.cursorPosition = resultTextArea.length
                        }
                    }
                }
            }
        }

        GroupBox {
            Layout.fillWidth: true
            Layout.preferredHeight: 150
            padding: 15
            topPadding: 35
            
            background: Rectangle {
                y: 20
                width: parent.width
                height: parent.height - 20
                color: "#ffffff"
                border.color: "#cccccc"
                border.width: 1
                radius: 4
            }
            
            label: RowLayout {
                x: 10
                spacing: 10
                
                Rectangle {
                    width: logLabelText.width + clearButton.width + 30
                    height: 25
                    color: "#ffffff"
                    
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 10
                        
                        Text {
                            id: logLabelText
                            text: "日志"
                            font.pixelSize: 13
                            font.bold: true
                            color: "#000000"
                        }
                        
                        Button {
                            id: clearButton
                            text: "清除"
                            implicitWidth: 60
                            implicitHeight: 22
                            
                            background: Rectangle {
                                color: parent.hovered ? "#c82333" : "#dc3545"
                                radius: 3
                            }
                            
                            contentItem: Text {
                                text: parent.text
                                color: "#ffffff"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font.pixelSize: 11
                            }
                            
                            onClicked: appController.clearLog()
                        }
                    }
                }
            }
            
            ScrollView {
                anchors.fill: parent
                clip: true
                
                TextArea {
                    text: appController.logText
                    readOnly: true
                    wrapMode: Text.NoWrap
                    font.pixelSize: 11
                    font.family: "Consolas, Courier New, monospace"
                    color: "#00ff00"
                    background: Rectangle {
                        color: "#1a1a1a"
                    }
                    textFormat: TextEdit.PlainText
                }
            }
        }
    }
}
