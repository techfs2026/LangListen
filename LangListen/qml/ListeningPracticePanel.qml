import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import AudioPlayer 1.0

Rectangle {
    id: root
    color: "#f8fbff"
    
    property var playback: appController.playbackController
    property var waveform: appController.waveformGenerator
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
            
                            Qt.callLater(function() {
                                if (appController.audioPath) {
                                    var duration = playback.duration
                    
                                    if (duration > 0) {
                                        var targetSamples = Math.floor(duration)
                        
                                        targetSamples = Math.max(1000, targetSamples)
                                        targetSamples = Math.min(600000, targetSamples)
                        
                                        console.log("Loading waveform: duration=" + duration + "ms, targetSamples=" + targetSamples)
                        
                                        waveform.loadAudio(appController.audioPath, targetSamples)
                                    } else {
                                        console.log("Warning: audio duration is 0, using default samples")
                                        waveform.loadAudio(appController.audioPath, 5000)
                                    }
                                }
                            })
            
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
            Layout.preferredHeight: 180
            color: "#ffffff"
            radius: 12
            border.color: "#e3f2fd"
            border.width: 1
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8
                
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    
                    Label {
                        text: "波形图"
                        font.pixelSize: 14
                        font.bold: true
                        color: "#1976d2"
                    }
                    
                    Item { Layout.fillWidth: true }
                    
                    Button {
                        text: "放大"
                        font.pixelSize: 11
                        padding: 6
                        enabled: waveform.isLoaded
                        
                        background: Rectangle {
                            color: parent.enabled ? (parent.down ? "#e0e0e0" : "#f5f5f5") : "#fafafa"
                            radius: 4
                            border.color: "#e0e0e0"
                            border.width: 1
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: parent.enabled ? "#424242" : "#9e9e9e"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: waveformRenderer.zoomIn()
                    }
                    
                    Button {
                        text: "缩小"
                        font.pixelSize: 11
                        padding: 6
                        enabled: waveform.isLoaded
                        
                        background: Rectangle {
                            color: parent.enabled ? (parent.down ? "#e0e0e0" : "#f5f5f5") : "#fafafa"
                            radius: 4
                            border.color: "#e0e0e0"
                            border.width: 1
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: parent.enabled ? "#424242" : "#9e9e9e"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: waveformRenderer.zoomOut()
                    }
                    
                    Button {
                        text: "适应窗口"
                        font.pixelSize: 11
                        padding: 6
                        enabled: waveform.isLoaded
                        
                        background: Rectangle {
                            color: parent.enabled ? (parent.down ? "#e0e0e0" : "#f5f5f5") : "#fafafa"
                            radius: 4
                            border.color: "#e0e0e0"
                            border.width: 1
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: parent.enabled ? "#424242" : "#9e9e9e"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: waveformRenderer.fitToView()
                    }
                }
                
                Item {
                    id: waveformContainer
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    
                    Rectangle {
                        anchors.fill: parent
                        color: "#212936"
                        radius: 4
                        
                        WaveformRenderer {
                            id: waveformRenderer
                            anchors.fill: parent
                            
                            waveformData: waveform.waveformData
                            duration: waveform.duration
                            currentPosition: playback.duration > 0 ? playback.position / playback.duration : 0
                            
                            segments: {
                                var segs = []
                                for (var i = 0; i < appController.segmentCount; i++) {
                                    segs.push({
                                        startTime: appController.getSegmentStartTime(i),
                                        endTime: appController.getSegmentEndTime(i),
                                        text: appController.getSegmentText(i)
                                    })
                                }
                                return segs
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                
                                onClicked: function(mouse) {
                                    if (waveform.duration > 0 && isInPracticeMode) {
                                        var relX = mouse.x + waveformRenderer.scrollPosition
                                        var clickPos = relX / waveformRenderer.contentWidth
                                        var targetMs = clickPos * waveform.duration
                                        playback.seekTo(targetMs)
                                    }
                                }
                            }
                        }
                        
                        ScrollBar {
                            id: horizontalScrollBar
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            orientation: Qt.Horizontal
                            policy: ScrollBar.AsNeeded
                            
                            size: waveformRenderer.contentWidth > 0 ? 
                                  waveformContainer.width / waveformRenderer.contentWidth : 1.0
                            position: waveformRenderer.contentWidth > 0 ? 
                                     waveformRenderer.scrollPosition / waveformRenderer.contentWidth : 0.0
                            
                            onPositionChanged: {
                                if (pressed) {
                                    waveformRenderer.scrollPosition = position * waveformRenderer.contentWidth
                                }
                            }
                            
                            contentItem: Rectangle {
                                implicitWidth: 6
                                implicitHeight: 6
                                radius: 3
                                color: parent.pressed ? "#1976d2" : "#bdbdbd"
                            }
                        }
                    }
                    
                    Rectangle {
                        anchors.fill: parent
                        visible: !waveform.isLoaded && isInPracticeMode
                        color: "transparent"
                        
                        Label {
                            anchors.centerIn: parent
                            text: "正在加载波形数据..."
                            font.pixelSize: 13
                            color: "#757575"
                        }
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
                        Layout.preferredWidth: 60
                        Layout.preferredHeight: 60
                        text: playback.isPlaying ? "⏸" : "▶"
                        enabled: isInPracticeMode
                        font.pixelSize: 24
                        
                        ToolTip.visible: hovered
                        ToolTip.text: playback.isPlaying ? "暂停" : "播放"
                        ToolTip.delay: 500
                        
                        background: Rectangle {
                            color: parent.enabled ? (parent.down ? "#1565c0" : "#1976d2") : "#e0e0e0"
                            radius: 30
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: parent.enabled ? "#ffffff" : "#9e9e9e"
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
                        Layout.preferredWidth: 50
                        Layout.preferredHeight: 50
                        text: "⏹"
                        enabled: isInPracticeMode
                        font.pixelSize: 20
                        
                        ToolTip.visible: hovered
                        ToolTip.text: "停止"
                        ToolTip.delay: 500
                        
                        background: Rectangle {
                            color: parent.enabled ? (parent.down ? "#d32f2f" : "#f44336") : "#e0e0e0"
                            radius: 25
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: parent.enabled ? "#ffffff" : "#9e9e9e"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: {
                            playback.stop()
                            savedSegmentIndexForLoop = -1
                        }
                    }
                    
                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 40
                        color: "#e0e0e0"
                    }
                    
                    Button {
                        Layout.preferredWidth: 50
                        Layout.preferredHeight: 50
                        text: "⏮"
                        enabled: isInPracticeMode && playback.currentSegmentIndex > 0
                        font.pixelSize: 20
                        
                        ToolTip.visible: hovered
                        ToolTip.text: "上一句"
                        ToolTip.delay: 500
                        
                        background: Rectangle {
                            color: parent.enabled ? (parent.down ? "#0277bd" : "#03a9f4") : "#e0e0e0"
                            radius: 25
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: parent.enabled ? "#ffffff" : "#9e9e9e"
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
                        Layout.preferredWidth: 50
                        Layout.preferredHeight: 50
                        text: "⟲"
                        enabled: isInPracticeMode && playback.currentSegmentIndex >= 0
                        font.pixelSize: 20
                        
                        ToolTip.visible: hovered
                        ToolTip.text: "重播当前句"
                        ToolTip.delay: 500
                        
                        background: Rectangle {
                            color: parent.enabled ? (parent.down ? "#388e3c" : "#4caf50") : "#e0e0e0"
                            radius: 25
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: parent.enabled ? "#ffffff" : "#9e9e9e"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: {
                            playback.replayCurrentSegment()
                        }
                    }
                    
                    Button {
                        Layout.preferredWidth: 50
                        Layout.preferredHeight: 50
                        text: "⏭"
                        enabled: isInPracticeMode && playback.currentSegmentIndex < appController.segmentCount - 1
                        font.pixelSize: 20
                        
                        ToolTip.visible: hovered
                        ToolTip.text: "下一句"
                        ToolTip.delay: 500
                        
                        background: Rectangle {
                            color: parent.enabled ? (parent.down ? "#0277bd" : "#03a9f4") : "#e0e0e0"
                            radius: 25
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: parent.enabled ? "#ffffff" : "#9e9e9e"
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
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 40
                        color: "#e0e0e0"
                    }
                    
                    Switch {
                        id: loopSwitch
                        checked: loopEnabled
                        enabled: isInPracticeMode
                        
                        ToolTip.visible: hovered
                        ToolTip.text: "开启后当前句会循环播放"
                        ToolTip.delay: 500
                        
                        onCheckedChanged: {
                            loopEnabled = checked
                            if (checked && playback.currentSegmentIndex >= 0) {
                                savedSegmentIndexForLoop = playback.currentSegmentIndex
                            } else {
                                savedSegmentIndexForLoop = -1
                            }
                        }
                        
                        indicator: Rectangle {
                            implicitWidth: 48
                            implicitHeight: 24
                            radius: 12
                            color: loopSwitch.checked ? "#ff9800" : "#bdbdbd"
                            
                            Rectangle {
                                x: loopSwitch.checked ? parent.width - width - 2 : 2
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
                            text: "单句循环"
                            color: loopSwitch.enabled ? "#424242" : "#9e9e9e"
                            font.pixelSize: 13
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: loopSwitch.indicator.width + 8
                        }
                    }
                    
                    Item { Layout.fillWidth: true }
                }
                
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    
                    Label {
                        text: formatTime(playback.position)
                        font.pixelSize: 12
                        font.family: "monospace"
                        color: "#757575"
                    }
                    
                    Slider {
                        Layout.fillWidth: true
                        from: 0
                        to: playback.duration
                        value: userDraggingProgress ? value : playback.position
                        enabled: isInPracticeMode && playback.duration > 0
                        
                        property bool userDraggingProgress: false

                        onMoved: {
                            userDraggingProgress = true
                        }

                        onPressedChanged: {
                            if (!pressed && userDraggingProgress) {
                                playback.seekTo(value)
                                userDraggingProgress = false
                            }
                        }
                        
                        background: Rectangle {
                            x: parent.leftPadding
                            y: parent.topPadding + parent.availableHeight / 2 - height / 2
                            implicitWidth: 200
                            implicitHeight: 4
                            width: parent.availableWidth
                            height: implicitHeight
                            radius: 2
                            color: "#e0e0e0"
                            
                            Rectangle {
                                width: parent.enabled ? parent.parent.visualPosition * parent.width : 0
                                height: parent.height
                                color: "#1976d2"
                                radius: 2
                            }
                        }
                        
                        handle: Rectangle {
                            x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width)
                            y: parent.topPadding + parent.availableHeight / 2 - height / 2
                            implicitWidth: 16
                            implicitHeight: 16
                            radius: 8
                            color: parent.pressed ? "#1565c0" : "#1976d2"
                            border.color: "#ffffff"
                            border.width: 2
                        }
                    }
                    
                    Label {
                        text: formatTime(playback.duration)
                        font.pixelSize: 12
                        font.family: "monospace"
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
                        Layout.preferredWidth: 120
                        from: 0
                        to: 1
                        value: playback.volume
                        
                        onMoved: {
                            playback.volume = value
                        }
                        
                        background: Rectangle {
                            x: parent.leftPadding
                            y: parent.topPadding + parent.availableHeight / 2 - height / 2
                            implicitWidth: 120
                            implicitHeight: 4
                            width: parent.availableWidth
                            height: implicitHeight
                            radius: 2
                            color: "#e0e0e0"
                            
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
                            implicitWidth: 12
                            implicitHeight: 12
                            radius: 6
                            color: parent.pressed ? "#1565c0" : "#1976d2"
                        }
                    }
                    
                    Item { Layout.fillWidth: true }
                    
                    Label {
                        text: "速度"
                        font.pixelSize: 12
                        color: "#757575"
                    }
                    
                    SpinBox {
                        Layout.preferredWidth: 100
                        from: 50
                        to: 200
                        stepSize: 10
                        value: playback.playbackRate * 100
                        editable: true
                        
                        onValueModified: {
                            playback.playbackRate = value / 100.0
                        }
                        
                        textFromValue: function(value) {
                            return (value / 100).toFixed(2) + "x"
                        }
                        
                        valueFromText: function(text) {
                            return parseFloat(text) * 100
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
                
                RowLayout {
                    Layout.fillWidth: true
                    
                    Label {
                        text: "句子列表"
                        font.pixelSize: 14
                        font.bold: true
                        color: "#1976d2"
                    }
                    
                    Item { Layout.fillWidth: true }
                    
                    Label {
                        text: "共 " + appController.segmentCount + " 句"
                        font.pixelSize: 12
                        color: "#757575"
                    }
                }
                
                ListView {
                    id: segmentListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8
                    clip: true
                    
                    model: appController.segmentCount
                    currentIndex: playback.currentSegmentIndex
                    
                    onCurrentIndexChanged: {
                        positionViewAtIndex(currentIndex, ListView.Center)
                    }
                    
                    delegate: Rectangle {
                        width: segmentListView.width - 16
                        height: Math.max(70, contentLayout.implicitHeight + 24)
                        
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
                            onClicked: function(mouse) {
                                // 检查是否点击了播放按钮区域（右侧约 50px）
                                if (mouse.x > width - 50) {
                                    return  // 让按钮处理点击
                                }
                                
                                playback.playSegment(index)
                                if (loopEnabled) {
                                    savedSegmentIndexForLoop = index
                                }
                            }
                        }
                        
                        RowLayout {
                            id: contentLayout
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10
                            
                            Rectangle {
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 40
                                Layout.alignment: Qt.AlignTop
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
                                spacing: 4
                                
                                Label {
                                    Layout.fillWidth: true
                                    text: appController.getSegmentText(index)
                                    wrapMode: Text.Wrap
                                    font.pixelSize: 13
                                    color: "#212121"
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
                                Layout.alignment: Qt.AlignTop
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
        interval: 20
        repeat: true
        
        property int targetEndTime: 0
        
        onTriggered: {
            if (!autoPauseEnabled || loopEnabled) {
                stop()
                return
            }
            
            if (playback.position >= targetEndTime - 50) {
                stop()
                if (playback.isPlaying) {
                    playback.pause()
                }
            }
        }
    }
    
    Timer {
        id: loopTimer
        interval: 20
        repeat: true
        running: loopEnabled && isInPracticeMode && savedSegmentIndexForLoop >= 0
        onTriggered: {
            if (savedSegmentIndexForLoop >= 0 && savedSegmentIndexForLoop < appController.segmentCount) {
                var startTime = appController.getSegmentStartTime(savedSegmentIndexForLoop)
                var endTime = appController.getSegmentEndTime(savedSegmentIndexForLoop)
                
                if (playback.position >= endTime - 50) {
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