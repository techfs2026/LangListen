import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

GroupBox {
    id: root
    title: "Listening Practice"

    property var playback: appController.playbackController

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        Button {
            Layout.fillWidth: true
            text: "Load Audio for Practice"
            enabled: appController.segmentCount > 0
            onClicked: appController.loadAudioForPlayback()
        }

        GroupBox {
            title: "Playback Controls"
            Layout.fillWidth: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 5

                RowLayout {
                    Layout.fillWidth: true

                    Button {
                        text: "⏮"
                        ToolTip.text: "Previous Segment"
                        onClicked: playback.playPreviousSegment()
                    }

                    Button {
                        text: playback.isPlaying ? "⏸" : "▶"
                        ToolTip.text: playback.isPlaying ? "Pause" : "Play"
                        onClicked: playback.isPlaying ? playback.pause() : playback.play()
                    }

                    Button {
                        text: "⏹"
                        ToolTip.text: "Stop"
                        onClicked: playback.stop()
                    }

                    Button {
                        text: "🔁"
                        ToolTip.text: "Replay Current Segment"
                        onClicked: playback.replayCurrentSegment()
                    }

                    Button {
                        text: "⏭"
                        ToolTip.text: "Next Segment"
                        onClicked: playback.playNextSegment()
                    }

                    Item { Layout.fillWidth: true }

                    Button {
                        text: "⏪ 5s"
                        onClicked: playback.skipBackward(5000)
                    }

                    Button {
                        text: "5s ⏩"
                        onClicked: playback.skipForward(5000)
                    }
                }

                Slider {
                    id: progressSlider
                    Layout.fillWidth: true
                    from: 0
                    to: playback.duration
                    value: playback.position
                    onMoved: playback.seekTo(value)
                }

                RowLayout {
                    Label {
                        text: formatTime(playback.position)
                        font.family: "monospace"
                    }
                    Item { Layout.fillWidth: true }
                    Label {
                        text: formatTime(playback.duration)
                        font.family: "monospace"
                    }
                }

                RowLayout {
                    Label { text: "Volume:" }
                    Slider {
                        Layout.fillWidth: true
                        from: 0
                        to: 1
                        value: playback.volume
                        onMoved: playback.volume = value
                    }
                    Label { text: Math.round(playback.volume * 100) + "%" }
                }

                RowLayout {
                    Label { text: "Speed:" }
                    Slider {
                        Layout.fillWidth: true
                        from: 0.5
                        to: 2.0
                        stepSize: 0.25
                        value: playback.playbackRate
                        onMoved: playback.playbackRate = value
                    }
                    Label { text: playback.playbackRate.toFixed(2) + "x" }
                }
            }
        }

        GroupBox {
            title: "Current Segment"
            Layout.fillWidth: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 5

                Label {
                    text: "Segment " + (playback.currentSegmentIndex + 1) + " / " + appController.segmentCount
                    font.bold: true
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 80

                    TextArea {
                        text: playback.currentSegmentText
                        readOnly: true
                        wrapMode: Text.Wrap
                        font.pixelSize: 16
                        selectByMouse: true
                    }
                }
            }
        }

        GroupBox {
            title: "Segment List"
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: segmentListView
                anchors.fill: parent
                clip: true
                model: appController.segmentCount
                spacing: 2

                delegate: Rectangle {
                    width: segmentListView.width
                    height: 60
                    color: playback.currentSegmentIndex === index ? "#e3f2fd" : "transparent"
                    border.color: playback.currentSegmentIndex === index ? "#2196f3" : "#e0e0e0"
                    border.width: 1
                    radius: 4

                    MouseArea {
                        anchors.fill: parent
                        onClicked: playback.playSegment(index)
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 5
                        spacing: 2

                        RowLayout {
                            Label {
                                text: "#" + (index + 1)
                                font.bold: true
                                color: "#2196f3"
                            }

                            Label {
                                text: formatTime(appController.getSegmentStartTime(index)) + 
                                      " → " + 
                                      formatTime(appController.getSegmentEndTime(index))
                                font.family: "monospace"
                                font.pixelSize: 11
                                color: "#666"
                            }

                            Item { Layout.fillWidth: true }

                            Button {
                                text: "▶"
                                flat: true
                                onClicked: playback.playSegment(index)
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            text: appController.getSegmentText(index)
                            wrapMode: Text.Wrap
                            font.pixelSize: 12
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }
                }

                ScrollBar.vertical: ScrollBar {}
            }
        }
    }

    function formatTime(milliseconds) {
        var totalSeconds = Math.floor(milliseconds / 1000)
        var minutes = Math.floor(totalSeconds / 60)
        var seconds = totalSeconds % 60
        return minutes.toString().padStart(2, '0') + ":" + 
               seconds.toString().padStart(2, '0')
    }
}
