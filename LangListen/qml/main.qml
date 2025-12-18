import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

ApplicationWindow {
    id: root
    visible: true
    width: 1200
    height: 800
    title: "Whisper Transcription with Subtitle Export & Listening Practice"

    SplitView {
        anchors.fill: parent
        orientation: Qt.Horizontal

        Item {
            SplitView.fillWidth: true
            SplitView.minimumWidth: 600

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                GroupBox {
                    title: "Model & Audio"
                    Layout.fillWidth: true

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 5

                        Row {
                            spacing: 10
                            Label { text: "Model:"; width: 60 }
                            TextField {
                                id: modelPathField
                                width: 350
                                text: appController.modelPath
                                onTextChanged: appController.modelPath = text
                            }
                            Button {
                                text: "Browse"
                                onClicked: modelFileDialog.open()
                            }
                            Button {
                                text: "Load Model"
                                enabled: !appController.isProcessing
                                onClicked: appController.loadModel()
                            }
                        }

                        Row {
                            spacing: 10
                            Label { text: "Audio:"; width: 60 }
                            TextField {
                                id: audioPathField
                                width: 350
                                text: appController.audioPath
                                onTextChanged: appController.audioPath = text
                            }
                            Button {
                                text: "Browse"
                                onClicked: audioFileDialog.open()
                            }
                            Button {
                                text: "Transcribe"
                                enabled: appController.modelLoaded && !appController.isProcessing
                                onClicked: appController.startTranscription()
                            }
                        }

                        Row {
                            spacing: 10
                            Label { text: "Mode: " + appController.computeMode }
                            Label { text: "Segments: " + appController.segmentCount }
                        }

                        ProgressBar {
                            Layout.fillWidth: true
                            from: 0
                            to: 100
                            value: appController.progress
                        }
                    }
                }

                GroupBox {
                    title: "Transcription Result"
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 5

                        RowLayout {
                            Button {
                                text: "Export SRT"
                                enabled: appController.segmentCount > 0
                                onClicked: srtExportDialog.open()
                            }
                            Button {
                                text: "Export LRC"
                                enabled: appController.segmentCount > 0
                                onClicked: lrcExportDialog.open()
                            }
                            Button {
                                text: "Export Text"
                                enabled: appController.segmentCount > 0
                                onClicked: txtExportDialog.open()
                            }
                            Button {
                                text: "Clear"
                                onClicked: appController.clearResult()
                            }
                        }

                        ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            TextArea {
                                text: appController.resultText
                                readOnly: true
                                wrapMode: Text.Wrap
                                selectByMouse: true
                            }
                        }
                    }
                }

                GroupBox {
                    title: "Log"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150

                    ColumnLayout {
                        anchors.fill: parent

                        Button {
                            text: "Clear Log"
                            onClicked: appController.clearLog()
                        }

                        ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            TextArea {
                                text: appController.logText
                                readOnly: true
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }
            }
        }

        Item {
            SplitView.preferredWidth: 550
            SplitView.minimumWidth: 400

            ListeningPracticePanel {
                anchors.fill: parent
                anchors.margins: 10
            }
        }
    }

    FileDialog {
        id: modelFileDialog
        title: "Select Whisper Model"
        nameFilters: ["Model files (*.bin)"]
        onAccepted: {
            var path = selectedFile.toString()
            path = path.replace(/^file:\/\/\//, "")
            appController.modelPath = path
        }
    }

    FileDialog {
        id: audioFileDialog
        title: "Select Audio File"
        nameFilters: ["Audio files (*.wav *.mp3 *.m4a *.flac *.ogg)"]
        onAccepted: {
            var path = selectedFile.toString()
            path = path.replace(/^file:\/\/\//, "")
            appController.audioPath = path
        }
    }

    FileDialog {
        id: srtExportDialog
        title: "Export SRT"
        fileMode: FileDialog.SaveFile
        nameFilters: ["SRT files (*.srt)"]
        defaultSuffix: "srt"
        onAccepted: {
            var path = selectedFile.toString()
            path = path.replace(/^file:\/\/\//, "")
            appController.exportSRT(path)
        }
    }

    FileDialog {
        id: lrcExportDialog
        title: "Export LRC"
        fileMode: FileDialog.SaveFile
        nameFilters: ["LRC files (*.lrc)"]
        defaultSuffix: "lrc"
        onAccepted: {
            var path = selectedFile.toString()
            path = path.replace(/^file:\/\/\//, "")
            appController.exportLRC(path)
        }
    }

    FileDialog {
        id: txtExportDialog
        title: "Export Text"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Text files (*.txt)"]
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
    }
}
