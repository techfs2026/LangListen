import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#f8fbff"
    
    property var playback: appController.playbackController
    property bool autoPauseEnabled: true
    property bool isInPracticeMode: false
    property bool loopEnabled: false
    property int savedSegmentIndexForLoop: -1
    
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
                    
                    ToolTip.visible: hovered
                    ToolTip.text: isInPracticeMode ? "当前处于练习模式" : "点击加载音频开始练习"
                    ToolTip.delay: 500
                    
                    background: Rectangle {
                        color: parent.enabled ? (parent.down ? "#1565c0" : "#1976d2") : "#e0e0e0"
                        radius: 8
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: parent.enabled ? "#ffffff" : "#9e9e9e"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
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
                    
                    ToolTip.visible: hovered
                    ToolTip.text: "开启后每个句子播放完毕会自动暂停"
                    ToolTip.delay: 500
                    
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
                        
                        ToolTip.visible: hovered
                        ToolTip.text: "上一句"
                        ToolTip.delay: 500
                        
                        background: Rectangle {
                            color: parent.enabled ? (parent.down ? "#e3f2fd" : "#f5f5f5") : "#fafafa"
                            radius: 22
                            border.color: "#e0e0e0"
                            border.width: 1
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: parent.enabled ? "#1976d2" : "#bdbdbd"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: {
                            playback.playPreviousSegment()
                            if (loopEnabled) {
                                savedSegmentIndexForLoop = playback.currentSegmentIndex
                            }
                        }
                    }
                    
                    Button {
                        Layout.preferredWidth: 56
                        Layout.preferredHeight: 56
                        text: playback.isPlaying ? "⏸" : "▶"
                        font.pixelSize: 22
                        
                        ToolTip.visible: hovered
                        ToolTip.text: playback.isPlaying ? "暂停" : "播放"
                        ToolTip.delay: 500
                        
                        background: Rectangle {
                            color: parent.down ? "#1565c0" : "#1976d2"
                            radius: 28
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#ffffff"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: {
                            if (playback.isPlaying) {
                                playback.pause()
                            } else {
                                playback.play()
                            }
                        }
                    }
                    
                    Button {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        text: "⏹"
                        font.pixelSize: 18
                        
                        ToolTip.visible: hovered
                        ToolTip.text: "停止"
                        ToolTip.delay: 500
                        
                        background: Rectangle {
                            color: parent.down ? "#e3f2fd" : "#f5f5f5"
                            radius: 22
                            border.color: "#e0e0e0"
                            border.width: 1
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#1976d2"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: {
                            playback.stop()
                            isInPracticeMode = false
                            loopEnabled = false
                            savedSegmentIndexForLoop = -1
                        }
                    }

                    Button {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        text: "⏭"
                        font.pixelSize: 18
                        enabled: playback.currentSegmentIndex < appController.segmentCount - 1
                        
                        ToolTip.visible: hovered
                        ToolTip.text: "下一句"
                        ToolTip.delay: 500
                        
                        background: Rectangle {
                            color: parent.enabled ? (parent.down ? "#e3f2fd" : "#f5f5f5") : "#fafafa"
                            radius: 22
                            border.color: "#e0e0e0"
                            border.width: 1
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: parent.enabled ? "#1976d2" : "#bdbdbd"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: {
                            playback.playNextSegment()
                            if (loopEnabled) {
                                savedSegmentIndexForLoop = playback.currentSegmentIndex
                            }
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
                        
                        ToolTip.visible: hovered
                        ToolTip.text: loopEnabled ? "关闭循环播放当前句子" : "开启循环播放当前句子"
                        ToolTip.delay: 500
                        
                        background: Rectangle {
                            color: loopEnabled ? "#e8f5e9" : (parent.down ? "#e8f5e9" : "#f5f5f5")
                            radius: 22
                            border.color: loopEnabled ? "#4caf50" : "#e0e0e0"
                            border.width: loopEnabled ? 2 : 1
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: loopEnabled ? "#2e7d32" : "#757575"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: {
                            loopEnabled = !loopEnabled
                            if (loopEnabled) {
                                savedSegmentIndexForLoop = playback.currentSegmentIndex
                            }
                        }
                    }
                    
                    Button {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        text: "↻"
                        font.pixelSize: 18
                        
                        ToolTip.visible: hovered
                        ToolTip.text: "重播当前句子"
                        ToolTip.delay: 500
                        
                        background: Rectangle {
                            color: parent.down ? "#e8f5e9" : "#f5f5f5"
                            radius: 22
                            border.color: "#e0e0e0"
                            border.width: 1
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#4caf50"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: {
                            playback.replayCurrentSegment()
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
                        text: "⏪"
                        font.pixelSize: 18
                        
                        ToolTip.visible: hovered
                        ToolTip.text: "后退5秒"
                        ToolTip.delay: 500
                        
                        background: Rectangle {
                            color: parent.down ? "#e3f2fd" : "#f5f5f5"
                            radius: 22
                            border.color: "#e0e0e0"
                            border.width: 1
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#1976d2"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: playback.skipBackward(5000)
                    }
                    
                    Button {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        text: "⏩"
                        font.pixelSize: 18
                        
                        ToolTip.visible: hovered
                        ToolTip.text: "前进5秒"
                        ToolTip.delay: 500
                        
                        background: Rectangle {
                            color: parent.down ? "#e3f2fd" : "#f5f5f5"
                            radius: 22
                            border.color: "#e0e0e0"
                            border.width: 1
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#1976d2"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: playback.skipForward(5000)
                    }
                    
                    Item { Layout.fillWidth: true }
                }
                
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    
                    Label {
                        text: "音量"
                        font.pixelSize: 12
                        color: "#757575"
                        Layout.preferredWidth: 40
                    }
                    Slider {
                        Layout.fillWidth: true
                        from: 0
                        to: 1
                        value: playback.volume
                        onValueChanged: playback.volume = value
                        
                        ToolTip.visible: hovered
                        ToolTip.text: "音量: " + Math.round(value * 100) + "%"
                        ToolTip.delay: 500
                        
                        background: Rectangle {
                            x: parent.leftPadding
                            y: parent.topPadding + parent.availableHeight / 2 - height / 2
                            width: parent.availableWidth
                            height: 4
                            radius: 2
                            color: "#e0e0e0"
                            
                            Rectangle {
                                width: parent.width * parent.parent.visualPosition
                                height: parent.height
                                color: "#1976d2"
                                radius: 2
                            }
                        }
                        
                        handle: Rectangle {
                            x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width)
                            y: parent.topPadding + parent.availableHeight / 2 - height / 2
                            width: 16
                            height: 16
                            radius: 8
                            color: parent.pressed ? "#1565c0" : "#1976d2"
                            border.color: "#ffffff"
                            border.width: 2
                        }
                    }
                    Label {
                        text: Math.round(playback.volume * 100) + "%"
                        font.pixelSize: 12
                        font.family: "monospace"
                        color: "#757575"
                        Layout.preferredWidth: 40
                    }
                }
                
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    
                    Label {
                        text: "速度"
                        font.pixelSize: 12
                        color: "#757575"
                        Layout.preferredWidth: 40
                    }
                    Slider {
                        Layout.fillWidth: true
                        from: 0.5
                        to: 2.0
                        value: playback.playbackRate
                        stepSize: 0.25
                        onValueChanged: playback.playbackRate = value
                        
                        ToolTip.visible: hovered
                        ToolTip.text: "播放速度: " + value.toFixed(2) + "x"
                        ToolTip.delay: 500
                        
                        background: Rectangle {
                            x: parent.leftPadding
                            y: parent.topPadding + parent.availableHeight / 2 - height / 2
                            width: parent.availableWidth
                            height: 4
                            radius: 2
                            color: "#e0e0e0"
                            
                            Rectangle {
                                width: parent.width * parent.parent.visualPosition
                                height: parent.height
                                color: "#4caf50"
                                radius: 2
                            }
                        }
                        
                        handle: Rectangle {
                            x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width)
                            y: parent.topPadding + parent.availableHeight / 2 - height / 2
                            width: 16
                            height: 16
                            radius: 8
                            color: parent.pressed ? "#388e3c" : "#4caf50"
                            border.color: "#ffffff"
                            border.width: 2
                        }
                    }
                    Label {
                        text: playback.playbackRate.toFixed(2) + "x"
                        font.pixelSize: 12
                        font.family: "monospace"
                        color: "#757575"
                        Layout.preferredWidth: 40
                    }
                }
            }
        }
        
        Rectangle {
            Layout.fillWidth: true
            height: 80
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
                        text: "进度"
                        font.pixelSize: 14
                        font.bold: true
                        color: "#1976d2"
                    }
                    
                    Label {
                        text: formatTime(playback.position) + " / " + formatTime(playback.duration)
                        font.pixelSize: 12
                        font.family: "monospace"
                        color: "#757575"
                    }
                    
                    Item { Layout.fillWidth: true }
                }
                
                Slider {
                    Layout.fillWidth: true
                    from: 0
                    to: playback.duration
                    value: playback.position
                    onMoved: playback.seekTo(value)
                    
                    background: Rectangle {
                        x: parent.leftPadding
                        y: parent.topPadding + parent.availableHeight / 2 - height / 2
                        width: parent.availableWidth
                        height: 6
                        radius: 3
                        color: "#e0e0e0"
                        
                        Rectangle {
                            width: parent.width * parent.parent.visualPosition
                            height: parent.height
                            color: "#1976d2"
                            radius: 3
                        }
                    }
                    
                    handle: Rectangle {
                        x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width)
                        y: parent.topPadding + parent.availableHeight / 2 - height / 2
                        width: 18
                        height: 18
                        radius: 9
                        color: parent.pressed ? "#1565c0" : "#1976d2"
                        border.color: "#ffffff"
                        border.width: 2
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
                        text: playback.currentSegmentIndex >= 0 ? 
                              ("第 " + (playback.currentSegmentIndex + 1) + " / " + appController.segmentCount + " 句") : 
                              "未选择"
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
                    currentIndex: playback.currentSegmentIndex
                    
                    onCurrentIndexChanged: {
                        positionViewAtIndex(currentIndex, ListView.Center)
                    }
                    
                    delegate: Rectangle {
                        width: segmentListView.width - 16
                        height: 70
                        
                        color: segmentListView.currentIndex === index ? "#e3f2fd" : "#fafafa"
                        radius: 8
                        border.color: segmentListView.currentIndex === index ? "#1976d2" : "#e0e0e0"
                        border.width: segmentListView.currentIndex === index ? 2 : 1
                        
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            
                            ToolTip.visible: containsMouse
                            ToolTip.text: "点击播放第 " + (index + 1) + " 句"
                            ToolTip.delay: 500
                            
                            onEntered: {
                                if (segmentListView.currentIndex !== index) {
                                    parent.color = "#f5f5f5"
                                }
                            }
                            onExited: {
                                if (segmentListView.currentIndex !== index) {
                                    parent.color = "#fafafa"
                                }
                            }
                            onClicked: {
                                playback.playSegment(index)
                                if (loopEnabled) {
                                    savedSegmentIndexForLoop = index
                                }
                            }
                        }
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10
                            
                            Rectangle {
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 40
                                radius: 20
                                color: segmentListView.currentIndex === index ? "#1976d2" : "#e3f2fd"
                                
                                Label {
                                    anchors.centerIn: parent
                                    text: index + 1
                                    font.bold: true
                                    font.pixelSize: 14
                                    color: segmentListView.currentIndex === index ? "#ffffff" : "#1976d2"
                                }
                            }
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
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
                                
                                ToolTip.visible: hovered
                                ToolTip.text: "播放"
                                ToolTip.delay: 500
                                
                                background: Rectangle {
                                    color: parent.down ? "#1565c0" : "#1976d2"
                                    radius: 18
                                }
                                
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: "#ffffff"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                
                                onClicked: {
                                    playback.playSegment(index)
                                    if (loopEnabled) {
                                        savedSegmentIndexForLoop = index
                                    }
                                }
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
            segmentListView.currentIndex = index
            
            if (autoPauseEnabled && !loopEnabled) {
                segmentEndTimer.stop()
                segmentEndTimer.targetEndTime = endTime
                segmentEndTimer.start()
            } else {
                segmentEndTimer.stop()
            }
        }
    }
    
    Timer {
        id: segmentEndTimer
        interval: 50
        repeat: true
        
        property int targetEndTime: 0
        
        onTriggered: {
            if (!autoPauseEnabled || loopEnabled) {
                stop()
                return
            }
            
            if (playback.position >= targetEndTime - 100) {
                stop()
                if (playback.isPlaying) {
                    playback.pause()
                }
            }
        }
    }
    
    Timer {
        id: loopTimer
        interval: 50
        repeat: true
        running: loopEnabled && isInPracticeMode && savedSegmentIndexForLoop >= 0
        onTriggered: {
            if (savedSegmentIndexForLoop >= 0 && savedSegmentIndexForLoop < appController.segmentCount) {
                var startTime = appController.getSegmentStartTime(savedSegmentIndexForLoop)
                var endTime = appController.getSegmentEndTime(savedSegmentIndexForLoop)
                
                if (playback.position >= endTime) {
                    playback.seekTo(startTime)
                    if (!playback.isPlaying) {
                        playback.play()
                    }
                }
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