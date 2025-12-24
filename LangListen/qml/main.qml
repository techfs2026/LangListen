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
    
    property int currentPage: 0
    property string sharedAudioPath: ""
    property string sharedSrtContent: ""
    
    StackLayout {
        id: pageStack
        anchors.fill: parent
        currentIndex: currentPage
        
        TranscriptionPage {
            id: transcriptionPage
            onNavigateToListening: {
                sharedAudioPath = appController.audioPath
                sharedSrtContent = appController.generateSRT()
                
                currentPage = 1
                
                listeningPage.loadData(sharedAudioPath, sharedSrtContent)
            }
        }
        
        ListeningPracticePage {
            id: listeningPage
            onNavigateBack: {
                currentPage = 0
            }
        }
    }
    
    Item {
        anchors.fill: parent
        
        Button {
            id: prevButton
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            visible: currentPage > 0
            width: 48
            height: 48
            opacity: enabled ? 1.0 : 0.3
            
            Behavior on opacity {
                NumberAnimation { duration: 200 }
            }
            
            background: Rectangle {
                color: parent.down ? "#1565c0" : (parent.hovered ? "#1976d2" : "#2196f3")
                radius: 24
                border.color: "#ffffff"
                border.width: 2
                
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    color: "transparent"
                    radius: 22
                    border.color: "#ffffff"
                    border.width: 1
                    opacity: 0.3
                }
                
                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
            }
            
            contentItem: Text {
                text: "‹"
                font.pixelSize: 32
                font.bold: true
                color: "#ffffff"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            
            onClicked: {
                if (currentPage === 1) {
                    listeningPage.navigateBack()
                }
            }
            
            ToolTip.visible: hovered
            ToolTip.text: "返回转写页面"
            ToolTip.delay: 500
        }
        
        Button {
            id: nextButton
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            visible: currentPage === 0
            enabled: appController.segmentCount > 0
            width: 48
            height: 48
            opacity: enabled ? 1.0 : 0.3
            
            Behavior on opacity {
                NumberAnimation { duration: 200 }
            }
            
            background: Rectangle {
                color: parent.enabled ? (parent.down ? "#1565c0" : (parent.hovered ? "#1976d2" : "#2196f3")) : "#bdbdbd"
                radius: 24
                border.color: "#ffffff"
                border.width: 2
                
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    color: "transparent"
                    radius: 22
                    border.color: "#ffffff"
                    border.width: 1
                    opacity: 0.3
                }
                
                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
            }
            
            contentItem: Text {
                text: "›"
                font.pixelSize: 32
                font.bold: true
                color: "#ffffff"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            
            onClicked: {
                transcriptionPage.navigateToListening()
            }
            
            ToolTip.visible: hovered
            ToolTip.text: enabled ? "前往精听练习" : "请先完成转写"
            ToolTip.delay: 500
        }
    }
    
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
        spacing: 12
        
        Repeater {
            model: 2
            
            Rectangle {
                width: currentPage === index ? 32 : 10
                height: 10
                radius: 5
                color: currentPage === index ? "#1976d2" : "#e0e0e0"
                
                Behavior on width {
                    NumberAnimation { duration: 200 }
                }
                
                Behavior on color {
                    ColorAnimation { duration: 200 }
                }
                
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    enabled: index === 0 || (index === 1 && appController.segmentCount > 0)
                    
                    onClicked: {
                        if (index === 1 && currentPage === 0) {
                            transcriptionPage.navigateToListening()
                        } else if (index === 0 && currentPage === 1) {
                            listeningPage.navigateBack()
                        }
                    }
                }
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
    
    function openModelFileDialog() {
        modelFileDialog.open()
    }
    
    function openAudioFileDialog() {
        audioFileDialog.open()
    }
}
