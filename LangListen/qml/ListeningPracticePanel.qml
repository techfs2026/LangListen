import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#f8fbff"
    
    property var playback: appController.playbackController
    property bool autoPauseEnabled: true
    property bool isInPracticeMode: false
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16
        
        Rectangle {
            Layout.fillWidth: true
            height: 60
            color: "#ffffff"
            radius: 12
            border.color: "#e3f2fd"
            border.width: 1
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: 15
                spacing: 12
                
                Label {
                    text: "精听练习"
                    font.pixelSize: 20
                    font.bold: true
                    color: "#1976d2"
                }
                
                Item { Layout.fillWidth: true }
                
                Button {
                    text: isInPracticeMode ? "练习模式" : "加载音频"
                    enabled: appController.segmentCount > 0
                    font.pixelSize: 13
                    padding: 10
                    background: Rectangle {
                        color: parent.enabled ? (parent.down ? "#1565c0" : "#1976d2") : "#e0e0e0"
                        radius: 8
                    }
                    contentItem: Text {
                        text: parent.text
                        color: parent.enabled ? "#ffffff" : "#9e9e9e"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font: parent.font
                    }
                    onClicked: {
                        if (!isInPracticeMode) {
                            appController.loadAudioForPlayback()
                            isInPracticeMode = true
                        }
                    }
                }
                
                Switch {
                    id: autoPauseSwitch
                    checked: autoPauseEnabled
                    onCheckedChanged: autoPauseEnabled = checked
                    
                    indicator: Rectangle {
                        implicitWidth: 48
                        implicitHeight: 24
                        radius: 12
                        color: autoPauseSwitch.checked ? "#1976d2" : "#bdbdbd"
                        
                        Rectangle {
                            x: autoPauseSwitch.checked ? parent.width - width - 2 : 2
                            y: 2
                            width: 20
                            height: 20
                            radius: 10
                            color: "#ffffff"
                            
                            Behavior on x {
                                NumberAnimation { duration: 200 }
                            }
                        }
                    }
                    
                    contentItem: Text {
                        text: "自动暂停"
                        color: "#424242"
                        font.pixelSize: 13
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: autoPauseSwitch.indicator.width + 8
                    }
                }
            }
        }
        
        Rectangle {
            Layout.fillWidth: true
            height: 200
            color: "#ffffff"
            radius: 12
            border.color: "#e3f2fd"
            border.width: 1
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 15
                spacing: 10
                
                Label {
                    text: "播放控制"
                    font.pixelSize: 14
                    font.bold: true
                    color: "#1976d2"
                }
                
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    
                    Button {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        text: "⏮"
                        font.pixelSize: 18
                        enabled: playback.currentSegmentIndex > 0
                        background: Rectangle {
                            color: parent.enabled ? (parent.down ? "#e3f2fd" : "#f5f5f5") : "#fafafa"
                            radius: 22
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
                        onClicked: playback.playPreviousSegment()
                    }
                    
                    Button {
                        Layout.preferredWidth: 56
                        Layout.preferredHeight: 56
                        text: playback.isPlaying ? "⏸" : "▶"
                        font.pixelSize: 22
                        background: Rectangle {
                            color: parent.down ? "#1565c0" : "#1976d2"
                            radius: 28
                        }
                        contentItem: Text {
                            text: parent.text
                            color: "#ffffff"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font: parent.font
                        }
                        onClicked: playback.isPlaying ? playback.pause() : playback.play()
                    }
                    
                    Button {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        text: "⏹"
                        font.pixelSize: 18
                        background: Rectangle {
                            color: parent.down ? "#e3f2fd" : "#f5f5f5"
                            radius: 22
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
                        onClicked: {
                            playback.stop()
                            isInPracticeMode = false
                        }
                    }
                    
                    Rectangle {
                        width: 1
                        height: 40
                        color: "#e0e0e0"
                    }
                    
                    Button {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        text: "🔁"
                        font.pixelSize: 18
                        background: Rectangle {
                            color: parent.down ? "#e8f5e9" : "#f5f5f5"
                            radius: 22
                            border.color: "#e0e0e0"
                            border.width: 1
                        }
                        contentItem: Text {
                            text: parent.text
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font: parent.font
                        }
                        onClicked: playback.replayCurrentSegment()
                    }
                    
                    Button {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        text: "⏭"
                        font.pixelSize: 18
                        enabled: playback.currentSegmentIndex < appController.segmentCount - 1
                        background: Rectangle {
                            color: parent.enabled ? (parent.down ? "#e3f2fd" : "#f5f5f5") : "#fafafa"
                            radius: 22
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
                        onClicked: playback.playNextSegment()
                    }
                    
                    Item { Layout.fillWidth: true }
                    
                    Button {
                        text: "⏪ 5s"
                        font.pixelSize: 12
                        padding: 8
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
                        onClicked: playback.skipBackward(5000)
                    }
                    
                    Button {
                        text: "5s ⏩"
                        font.pixelSize: 12
                        padding: 8
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
                    
                    background: Rectangle {
                        x: progressSlider.leftPadding
                        y: progressSlider.topPadding + progressSlider.availableHeight / 2 - height / 2
                        implicitWidth: 200
                        implicitHeight: 4
                        width: progressSlider.availableWidth
                        height: implicitHeight
                        radius: 2
                        color: "#e3f2fd"
                        
                        Rectangle {
                            width: progressSlider.visualPosition * parent.width
                            height: parent.height
                            color: "#1976d2"
                            radius: 2
                        }
                    }
                    
                    handle: Rectangle {
                        x: progressSlider.leftPadding + progressSlider.visualPosition * (progressSlider.availableWidth - width)
                        y: progressSlider.topPadding + progressSlider.availableHeight / 2 - height / 2
                        implicitWidth: 16
                        implicitHeight: 16
                        radius: 8
                        color: progressSlider.pressed ? "#1565c0" : "#1976d2"
                        border.color: "#ffffff"
                        border.width: 2
                    }
                }
                
                RowLayout {
                    Layout.fillWidth: true
                    
                    Label {
                        text: formatTime(playback.position)
                        font.family: "monospace"
                        font.pixelSize: 12
                        color: "#757575"
                    }
                    Item { Layout.fillWidth: true }
                    Label {
                        text: formatTime(playback.duration)
                        font.family: "monospace"
                        font.pixelSize: 12
                        color: "#757575"
                    }
                }
                
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    
                    Label {
                        text: "音量"
                        font.pixelSize: 12
                        color: "#757575"
                    }
                    Slider {
                        Layout.fillWidth: true
                        from: 0
                        to: 1
                        value: playback.volume
                        onMoved: playback.volume = value
                        
                        background: Rectangle {
                            x: parent.leftPadding
                            y: parent.topPadding + parent.availableHeight / 2 - height / 2
                            implicitWidth: 200
                            implicitHeight: 4
                            width: parent.availableWidth
                            height: implicitHeight
                            radius: 2
                            color: "#e3f2fd"
                            
                            Rectangle {
                                width: parent.parent.visualPosition * parent.width
                                height: parent.height
                                color: "#1976d2"
                                radius: 2
                            }
                        }
                        
                        handle: Rectangle {
                            x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width)
                            y: parent.topPadding + parent.availableHeight / 2 - height / 2
                            implicitWidth: 14
                            implicitHeight: 14
                            radius: 7
                            color: parent.pressed ? "#1565c0" : "#1976d2"
                        }
                    }
                    Label {
                        text: Math.round(playback.volume * 100) + "%"
                        font.pixelSize: 12
                        color: "#757575"
                        Layout.preferredWidth: 40
                    }
                    
                    Rectangle {
                        width: 1
                        height: 20
                        color: "#e0e0e0"
                    }
                    
                    Label {
                        text: "速度"
                        font.pixelSize: 12
                        color: "#757575"
                    }
                    Slider {
                        Layout.preferredWidth: 120
                        from: 0.5
                        to: 2.0
                        stepSize: 0.25
                        value: playback.playbackRate
                        onMoved: playback.playbackRate = value
                        
                        background: Rectangle {
                            x: parent.leftPadding
                            y: parent.topPadding + parent.availableHeight / 2 - height / 2
                            implicitWidth: 200
                            implicitHeight: 4
                            width: parent.availableWidth
                            height: implicitHeight
                            radius: 2
                            color: "#e3f2fd"
                            
                            Rectangle {
                                width: parent.parent.visualPosition * parent.width
                                height: parent.height
                                color: "#1976d2"
                                radius: 2
                            }
                        }
                        
                        handle: Rectangle {
                            x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width)
                            y: parent.topPadding + parent.availableHeight / 2 - height / 2
                            implicitWidth: 14
                            implicitHeight: 14
                            radius: 7
                            color: parent.pressed ? "#1565c0" : "#1976d2"
                        }
                    }
                    Label {
                        text: playback.playbackRate.toFixed(2) + "x"
                        font.pixelSize: 12
                        color: "#757575"
                        Layout.preferredWidth: 40
                    }
                }
            }
        }
        
        Rectangle {
            Layout.fillWidth: true
            height: 120
            color: "#ffffff"
            radius: 12
            border.color: "#e3f2fd"
            border.width: 1
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 15
                spacing: 8
                
                RowLayout {
                    Layout.fillWidth: true
                    
                    Label {
                        text: "当前句子"
                        font.pixelSize: 14
                        font.bold: true
                        color: "#1976d2"
                    }
                    
                    Label {
                        text: "第 " + (playback.currentSegmentIndex + 1) + " / " + appController.segmentCount + " 句"
                        font.pixelSize: 12
                        color: "#757575"
                    }
                    
                    Item { Layout.fillWidth: true }
                }
                
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    
                    TextArea {
                        text: playback.currentSegmentText
                        readOnly: true
                        wrapMode: Text.Wrap
                        font.pixelSize: 16
                        color: "#212121"
                        selectByMouse: true
                        background: Rectangle {
                            color: "transparent"
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
                anchors.margins: 15
                spacing: 10
                
                Label {
                    text: "句子列表"
                    font.pixelSize: 14
                    font.bold: true
                    color: "#1976d2"
                }
                
                ListView {
                    id: segmentListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: appController.segmentCount
                    spacing: 8
                    
                    delegate: Rectangle {
                        width: segmentListView.width
                        height: 70
                        color: playback.currentSegmentIndex === index ? "#e3f2fd" : "#fafafa"
                        radius: 8
                        border.color: playback.currentSegmentIndex === index ? "#1976d2" : "#e0e0e0"
                        border.width: playback.currentSegmentIndex === index ? 2 : 1
                        
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            
                            onEntered: parent.color = playback.currentSegmentIndex === index ? "#e3f2fd" : "#f5f5f5"
                            onExited: parent.color = playback.currentSegmentIndex === index ? "#e3f2fd" : "#fafafa"
                            onClicked: playback.playSegment(index)
                        }
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10
                            
                            Rectangle {
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 40
                                radius: 20
                                color: playback.currentSegmentIndex === index ? "#1976d2" : "#e3f2fd"
                                
                                Label {
                                    anchors.centerIn: parent
                                    text: index + 1
                                    font.bold: true
                                    font.pixelSize: 14
                                    color: playback.currentSegmentIndex === index ? "#ffffff" : "#1976d2"
                                }
                            }
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                
                                Label {
                                    Layout.fillWidth: true
                                    text: appController.getSegmentText(index)
                                    wrapMode: Text.Wrap
                                    font.pixelSize: 13
                                    color: "#212121"
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                                
                                Label {
                                    text: formatTime(appController.getSegmentStartTime(index)) + " → " + formatTime(appController.getSegmentEndTime(index))
                                    font.family: "monospace"
                                    font.pixelSize: 11
                                    color: "#757575"
                                }
                            }
                            
                            Button {
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 36
                                text: "▶"
                                font.pixelSize: 14
                                background: Rectangle {
                                    color: parent.down ? "#1565c0" : "#1976d2"
                                    radius: 18
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: "#ffffff"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font: parent.font
                                }
                                onClicked: playback.playSegment(index)
                            }
                        }
                    }
                    
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        
                        contentItem: Rectangle {
                            implicitWidth: 6
                            radius: 3
                            color: parent.pressed ? "#1976d2" : "#bdbdbd"
                        }
                    }
                }
            }
        }
    }
    
    Connections {
        target: playback
        
        function onSegmentChanged(index, text, startTime, endTime) {
            if (autoPauseEnabled && isInPracticeMode) {
                segmentEndTimer.interval = endTime - startTime
                segmentEndTimer.restart()
            }
        }
    }
    
    Timer {
        id: segmentEndTimer
        repeat: false
        onTriggered: {
            if (autoPauseEnabled && playback.isPlaying) {
                playback.pause()
            }
        }
    }
    
    function formatTime(milliseconds) {
        var totalSeconds = Math.floor(milliseconds / 1000)
        var minutes = Math.floor(totalSeconds / 60)
        var seconds = totalSeconds % 60
        return minutes.toString().padStart(2, '0') + ":" + seconds.toString().padStart(2, '0')
    }
}
