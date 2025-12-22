import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs
import WaveformRenderer 1.0

Item {
    id: listeningPage
    
    signal navigateBack()
    
    property var playback: appController.playbackController
    property var waveform: appController.waveformGenerator
    property bool audioLoaded: false
    property bool autoPauseEnabled: true
    property bool loopEnabled: false
    property int savedSegmentIndexForLoop: -1
    property int lastClickedSegment: -1
    property var segmentData: []
    
    // 🔧 调试定时器：每秒输出关键状态
    Timer {
        id: debugTimer
        interval: 1000
        repeat: true
        running: audioLoaded && playback.isPlaying
        onTriggered: {
            console.log("🔍 DEBUG STATE:",
                       "| pos:", playback.position,
                       "| dur:", waveform.duration,
                       "| ratio:", (playback.position / Math.max(waveform.duration, 1)).toFixed(4),
                       "| contentW:", waveformView.contentWidth.toFixed(1),
                       "| scrollPos:", waveformFlickable ? waveformFlickable.contentX.toFixed(1) : "N/A",
                       "| follow:", waveformView.followPlayback)
        }
    }
    
    function loadData(audioPath, srtContent) {
        if (!audioPath || audioPath === "") {
            console.log("Error: No audio path provided")
            return
        }
        
        parseAndLoadSrtData(srtContent)
        appController.loadAudioForPlayback()
        
        Qt.callLater(function() {
            if (appController.audioPath) {
                var duration = playback.duration
                
                if (duration > 0) {
                    console.log("Loading waveform: duration=" + duration + "ms")
                    waveform.loadAudio(appController.audioPath)
                } else {
                    console.log("Warning: audio duration is 0")
                    waveform.loadAudio(appController.audioPath)
                }
            }
        })
        
        audioLoaded = true
    }
    
    function parseAndLoadSrtData(srtContent) {
        console.log("SRT data loaded, segments count:", appController.segmentCount)
    }
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 40
        anchors.leftMargin: 80
        anchors.rightMargin: 80
        spacing: 20
        
        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            
            Label {
                Layout.fillWidth: true
                text: "精听练习"
                font.pixelSize: 32
                font.bold: true
                color: "#1976d2"
            }
            
            Switch {
                id: autoPauseSwitch
                checked: autoPauseEnabled
                onCheckedChanged: autoPauseEnabled = checked
                
                ToolTip.visible: hovered
                ToolTip.text: "开启后每句播放完会自动暂停"
                ToolTip.delay: 500
                
                indicator: Rectangle {
                    implicitWidth: 52
                    implicitHeight: 28
                    radius: 14
                    color: autoPauseSwitch.checked ? "#2196f3" : "#bdbdbd"
                    
                    Rectangle {
                        x: autoPauseSwitch.checked ? parent.width - width - 3 : 3
                        y: 3
                        width: 22
                        height: 22
                        radius: 11
                        color: "#ffffff"
                        
                        Behavior on x {
                            NumberAnimation { duration: 200 }
                        }
                    }
                }
                
                contentItem: Text {
                    text: "自动暂停"
                    color: "#424242"
                    font.pixelSize: 14
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: autoPauseSwitch.indicator.width + 10
                }
            }
        }
        
        Label {
            Layout.fillWidth: true
            text: "逐句精听，提升语言理解能力"
            font.pixelSize: 14
            color: "#757575"
        }
        
        Item { Layout.preferredHeight: 5 }
        
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 200
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
                    spacing: 10
                    
                    Label {
                        text: "波形图"
                        font.pixelSize: 15
                        font.bold: true
                        color: "#424242"
                    }
                    
                    Item { Layout.fillWidth: true }
                    
                    Button {
                        text: "放大"
                        font.pixelSize: 11
                        padding: 6
                        enabled: waveform.isLoaded
                        
                        background: Rectangle {
                            color: parent.enabled ? (parent.down ? "#e0e0e0" : (parent.hovered ? "#f5f5f5" : "#fafafa")) : "#f5f5f5"
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
                        
                        onClicked: waveformView.zoomIn()
                    }
                    
                    Button {
                        text: "缩小"
                        font.pixelSize: 11
                        padding: 6
                        enabled: waveform.isLoaded
                        
                        background: Rectangle {
                            color: parent.enabled ? (parent.down ? "#e0e0e0" : (parent.hovered ? "#f5f5f5" : "#fafafa")) : "#f5f5f5"
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
                        
                        onClicked: waveformView.zoomOut()
                    }
                    
                    Button {
                        text: "重置"
                        font.pixelSize: 11
                        padding: 6
                        enabled: waveform.isLoaded
                        
                        background: Rectangle {
                            color: parent.enabled ? (parent.down ? "#e0e0e0" : (parent.hovered ? "#f5f5f5" : "#fafafa")) : "#f5f5f5"
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
                        
                        onClicked: waveformView.resetZoom()
                    }
                    
                    Button {
                        text: "适应"
                        font.pixelSize: 11
                        padding: 6
                        enabled: waveform.isLoaded
                        
                        background: Rectangle {
                            color: parent.enabled ? (parent.down ? "#e0e0e0" : (parent.hovered ? "#f5f5f5" : "#fafafa")) : "#f5f5f5"
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
                        
                        onClicked: waveformView.fitToView()
                    }
                }
                
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "#202124"  // 深色背景匹配C++端
                    radius: 8
                    clip: true
                    
                    Flickable {
                        id: waveformFlickable
                        anchors.fill: parent
                        contentWidth: waveformView.contentWidth
                        contentHeight: height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: true
                        
                        // 平滑滚动动画
                        Behavior on contentX {
                            enabled: !waveformFlickable.moving && !waveformFlickable.dragging
                            SmoothedAnimation {
                                velocity: 2000
                                duration: 200
                            }
                        }
                        
                        onContentXChanged: {
                            if (waveform.isLoaded) {
                                waveformView.scrollPosition = contentX
                                console.log("📊 Flickable.contentX changed:", contentX.toFixed(1))
                            }
                        }
                        
                        // 检测用户手动滚动
                        onMovingChanged: {
                            console.log("👆 User moving:", moving)
                            if (moving) {
                                waveformView.followPlayback = false
                                reEnableFollowTimer.restart()
                                console.log("🚫 Auto-follow DISABLED (user scrolling)")
                            }
                        }
                        
                        onDraggingChanged: {
                            console.log("✋ User dragging:", dragging)
                            if (dragging) {
                                waveformView.followPlayback = false
                                reEnableFollowTimer.restart()
                                console.log("🚫 Auto-follow DISABLED (user dragging)")
                            }
                        }
                        
                        // 3秒后重新启用自动跟随
                        Timer {
                            id: reEnableFollowTimer
                            interval: 3000
                            onTriggered: {
                                waveformView.followPlayback = true
                                console.log("✅ Auto-follow ENABLED")
                            }
                        }
                        
                        WaveformView {
                            id: waveformView
                            width: waveformFlickable.width  // 修复：移除Math.max避免binding loop
                            height: waveformFlickable.height
                            
                            level1Data: waveform.level1Data
                            level2Data: waveform.level2Data
                            level3Data: waveform.level3Data
                            level4Data: waveform.level4Data
                            
                            duration: waveform.duration
                            currentPosition: {
                                var pos = playback.position / Math.max(waveform.duration, 1)
                                console.log("📍 CurrentPosition binding updated:", 
                                           "playback.position=", playback.position,
                                           "waveform.duration=", waveform.duration,
                                           "currentPosition=", pos.toFixed(4))
                                return pos
                            }
                            
                            scrollPosition: waveformFlickable.contentX
                            
                            showPerformance: false
                            
                            // 监听contentWidth变化
                            onContentWidthChanged: {
                                console.log("📐 ContentWidth changed:", contentWidth.toFixed(1))
                            }
                            
                            // 监听currentPosition变化（这个应该会触发C++日志）
                            onCurrentPositionChanged: {
                                console.log("🔄 CurrentPosition changed in QML:", currentPosition.toFixed(4))
                            }

                            onRequestScrollTo: function(targetX) {
                                console.log("🎯 RequestScrollTo called:", targetX.toFixed(1), 
                                           "| moving:", waveformFlickable.moving, 
                                           "| dragging:", waveformFlickable.dragging,
                                           "| followPlayback:", waveformView.followPlayback)
                                // 只在非用户滚动时更新位置
                                if (!waveformFlickable.moving && !waveformFlickable.dragging) {
                                    waveformFlickable.contentX = targetX
                                    console.log("✅ Scroll applied to:", targetX.toFixed(1))
                                } else {
                                    console.log("⏸️  Scroll IGNORED (user interaction)")
                                }
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                onClicked: function(mouse) {
                                    if (waveform.isLoaded && waveform.duration > 0) {
                                        var clickX = mouse.x + waveformFlickable.contentX
                                        var ratio = clickX / waveformView.contentWidth
                                        var targetPosition = Math.floor(ratio * waveform.duration)
                                        playback.seekTo(targetPosition)
                                    }
                                }
                            }
                        }
                        
                        ScrollBar.horizontal: ScrollBar {
                            policy: ScrollBar.AsNeeded
                            
                            contentItem: Rectangle {
                                implicitHeight: 6
                                radius: 3
                                color: parent.pressed ? "#2196f3" : "#bdbdbd"
                            }
                        }
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
                anchors.margins: 20
                spacing: 16
                
                Label {
                    text: "播放控制"
                    font.pixelSize: 15
                    font.bold: true
                    color: "#424242"
                }
                
                RowLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 12
                    
                    Button {
                        Layout.preferredWidth: 50
                        Layout.preferredHeight: 50
                        text: "◄◄"
                        font.pixelSize: 14
                        enabled: playback.currentSegmentIndex > 0
                        
                        ToolTip.visible: hovered
                        ToolTip.text: "上一句"
                        ToolTip.delay: 500
                        
                        background: Rectangle {
                            color: parent.enabled ? (parent.down ? "#1565c0" : (parent.hovered ? "#1976d2" : "#2196f3")) : "#e0e0e0"
                            radius: 25
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: parent.enabled ? "#ffffff" : "#9e9e9e"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: playback.playPreviousSegment()
                    }
                    
                    Button {
                        Layout.preferredWidth: 50
                        Layout.preferredHeight: 50
                        text: "◄"
                        font.pixelSize: 16
                        enabled: audioLoaded
                        
                        ToolTip.visible: hovered
                        ToolTip.text: "后退5秒"
                        ToolTip.delay: 500
                        
                        background: Rectangle {
                            color: parent.enabled ? (parent.down ? "#1565c0" : (parent.hovered ? "#1976d2" : "#2196f3")) : "#e0e0e0"
                            radius: 25
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: parent.enabled ? "#ffffff" : "#9e9e9e"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: playback.skipBackward(5000)
                    }
                    
                    Button {
                        Layout.preferredWidth: 70
                        Layout.preferredHeight: 70
                        text: playback.isPlaying ? "❚❚" : "▶"
                        font.pixelSize: 24
                        enabled: audioLoaded
                        
                        ToolTip.visible: hovered
                        ToolTip.text: playback.isPlaying ? "暂停" : "播放"
                        ToolTip.delay: 500
                        
                        background: Rectangle {
                            color: parent.enabled ? (parent.down ? "#1565c0" : (parent.hovered ? "#1976d2" : "#2196f3")) : "#e0e0e0"
                            radius: 35
                            
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 3
                                color: "transparent"
                                radius: 32
                                border.color: "#ffffff"
                                border.width: 2
                                opacity: 0.3
                            }
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
                        text: "►"
                        font.pixelSize: 16
                        enabled: audioLoaded
                        
                        ToolTip.visible: hovered
                        ToolTip.text: "前进5秒"
                        ToolTip.delay: 500
                        
                        background: Rectangle {
                            color: parent.enabled ? (parent.down ? "#1565c0" : (parent.hovered ? "#1976d2" : "#2196f3")) : "#e0e0e0"
                            radius: 25
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: parent.enabled ? "#ffffff" : "#9e9e9e"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: playback.skipForward(5000)
                    }
                    
                    Button {
                        Layout.preferredWidth: 50
                        Layout.preferredHeight: 50
                        text: "►►"
                        font.pixelSize: 14
                        enabled: playback.currentSegmentIndex < appController.segmentCount - 1
                        
                        ToolTip.visible: hovered
                        ToolTip.text: "下一句"
                        ToolTip.delay: 500
                        
                        background: Rectangle {
                            color: parent.enabled ? (parent.down ? "#1565c0" : (parent.hovered ? "#1976d2" : "#2196f3")) : "#e0e0e0"
                            radius: 25
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: parent.enabled ? "#ffffff" : "#9e9e9e"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: playback.playNextSegment()
                    }
                    
                    Button {
                        Layout.preferredWidth: 50
                        Layout.preferredHeight: 50
                        text: "⟲"
                        font.pixelSize: 20
                        enabled: playback.currentSegmentIndex >= 0
                        
                        ToolTip.visible: hovered
                        ToolTip.text: "重播当前句"
                        ToolTip.delay: 500
                        
                        background: Rectangle {
                            color: parent.enabled ? (parent.down ? "#1565c0" : (parent.hovered ? "#1976d2" : "#2196f3")) : "#e0e0e0"
                            radius: 25
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: parent.enabled ? "#ffffff" : "#9e9e9e"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: playback.replayCurrentSegment()
                    }
                    
                    Item { Layout.preferredWidth: 30 }
                    
                    RowLayout {
                        spacing: 10
                        
                        Label {
                            text: "速度:"
                            font.pixelSize: 14
                            color: "#616161"
                        }
                        
                        ComboBox {
                            id: speedComboBox
                            Layout.preferredWidth: 90
                            currentIndex: 2
                            font.pixelSize: 13
                            
                            model: ListModel {
                                ListElement { text: "0.5x"; value: 0.5 }
                                ListElement { text: "0.75x"; value: 0.75 }
                                ListElement { text: "1.0x"; value: 1.0 }
                                ListElement { text: "1.25x"; value: 1.25 }
                                ListElement { text: "1.5x"; value: 1.5 }
                                ListElement { text: "2.0x"; value: 2.0 }
                            }
                            
                            textRole: "text"
                            
                            delegate: ItemDelegate {
                                width: speedComboBox.width
                                
                                contentItem: Text {
                                    text: model.text
                                    color: "#212121"
                                    font: speedComboBox.font
                                    elide: Text.ElideRight
                                    verticalAlignment: Text.AlignVCenter
                                }
                                
                                highlighted: speedComboBox.highlightedIndex === index
                                
                                background: Rectangle {
                                    color: highlighted ? "#e3f2fd" : (parent.hovered ? "#f5f5f5" : "#ffffff")
                                }
                            }
                            
                            background: Rectangle {
                                color: parent.down ? "#e0e0e0" : "#f5f5f5"
                                radius: 6
                                border.color: parent.activeFocus ? "#2196f3" : "#e0e0e0"
                                border.width: parent.activeFocus ? 2 : 1
                            }
                            
                            contentItem: Text {
                                leftPadding: 12
                                rightPadding: speedComboBox.indicator.width + speedComboBox.spacing
                                text: speedComboBox.displayText
                                font: speedComboBox.font
                                color: "#212121"
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                            
                            indicator: Text {
                                x: speedComboBox.width - width - 8
                                y: speedComboBox.topPadding + (speedComboBox.availableHeight - height) / 2
                                text: "▼"
                                font.pixelSize: 10
                                color: "#616161"
                            }
                            
                            popup: Popup {
                                y: speedComboBox.height + 2
                                width: speedComboBox.width
                                implicitHeight: contentItem.implicitHeight
                                padding: 4
                                
                                contentItem: ListView {
                                    clip: true
                                    implicitHeight: contentHeight
                                    model: speedComboBox.popup.visible ? speedComboBox.delegateModel : null
                                    currentIndex: speedComboBox.highlightedIndex
                                    
                                    ScrollIndicator.vertical: ScrollIndicator { }
                                }
                                
                                background: Rectangle {
                                    color: "#ffffff"
                                    border.color: "#e0e0e0"
                                    border.width: 1
                                    radius: 6
                                }
                            }
                            
                            onActivated: function(index) {
                                var speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                                playback.setPlaybackRate(speeds[index])
                            }
                        }
                    }
                }
                
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    
                    Label {
                        text: formatTime(playback.position)
                        font.family: "monospace"
                        font.pixelSize: 13
                        font.bold: true
                        color: "#2196f3"
                        Layout.preferredWidth: 55
                    }
                    
                    Slider {
                        Layout.fillWidth: true
                        from: 0
                        to: playback.duration
                        value: playback.position
                        enabled: audioLoaded
                        
                        onMoved: {
                            playback.seekTo(value)
                        }
                        
                        background: Rectangle {
                            x: parent.leftPadding
                            y: parent.topPadding + parent.availableHeight / 2 - height / 2
                            implicitWidth: 200
                            implicitHeight: 8
                            width: parent.availableWidth
                            height: implicitHeight
                            radius: 4
                            color: "#e0e0e0"
                            
                            Rectangle {
                                width: parent.width * (playback.position / (playback.duration || 1))
                                height: parent.height
                                color: "#2196f3"
                                radius: 4
                            }
                        }
                        
                        handle: Rectangle {
                            x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width)
                            y: parent.topPadding + parent.availableHeight / 2 - height / 2
                            implicitWidth: 20
                            implicitHeight: 20
                            radius: 10
                            color: parent.pressed ? "#1565c0" : "#2196f3"
                            border.color: "#ffffff"
                            border.width: 3
                            
                            Rectangle {
                                anchors.centerIn: parent
                                width: 8
                                height: 8
                                radius: 4
                                color: "#ffffff"
                            }
                        }
                    }
                    
                    Label {
                        text: formatTime(playback.duration)
                        font.family: "monospace"
                        font.pixelSize: 13
                        color: "#757575"
                        Layout.preferredWidth: 55
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
                spacing: 12
                
                RowLayout {
                    Layout.fillWidth: true
                    
                    Label {
                        text: "句子列表 (" + appController.segmentCount + ")"
                        font.pixelSize: 15
                        font.bold: true
                        color: "#424242"
                    }
                    
                    Item { Layout.fillWidth: true }
                    
                    Button {
                        text: "导出 SRT"
                        font.pixelSize: 12
                        padding: 8
                        enabled: appController.segmentCount > 0
                        
                        background: Rectangle {
                            color: parent.enabled ? (parent.down ? "#1565c0" : (parent.hovered ? "#1976d2" : "#2196f3")) : "#e0e0e0"
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
                        font.pixelSize: 12
                        padding: 8
                        enabled: appController.segmentCount > 0
                        
                        background: Rectangle {
                            color: parent.enabled ? (parent.down ? "#1565c0" : (parent.hovered ? "#1976d2" : "#2196f3")) : "#e0e0e0"
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
                        text: "导出 TXT"
                        font.pixelSize: 12
                        padding: 8
                        enabled: appController.segmentCount > 0
                        
                        background: Rectangle {
                            color: parent.enabled ? (parent.down ? "#1565c0" : (parent.hovered ? "#1976d2" : "#2196f3")) : "#e0e0e0"
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
                }
                
                Rectangle {
                    Layout.fillWidth: true
                    height: 40
                    color: "#f5f5f5"
                    radius: 6
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10
                        
                        Label {
                            Layout.preferredWidth: 50
                            text: "序号"
                            font.pixelSize: 13
                            font.bold: true
                            color: "#616161"
                        }
                        
                        Label {
                            Layout.preferredWidth: 100
                            text: "起始时间"
                            font.pixelSize: 13
                            font.bold: true
                            color: "#616161"
                        }
                        
                        Label {
                            Layout.preferredWidth: 100
                            text: "结束时间"
                            font.pixelSize: 13
                            font.bold: true
                            color: "#616161"
                        }
                        
                        Label {
                            Layout.fillWidth: true
                            text: "文本内容"
                            font.pixelSize: 13
                            font.bold: true
                            color: "#616161"
                        }
                        
                        Item {
                            Layout.preferredWidth: 50
                        }
                    }
                }
                
                ListView {
                    id: segmentListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 8
                    
                    model: appController.segmentCount
                    
                    delegate: Rectangle {
                        width: segmentListView.width
                        height: Math.max(60, contentRow.implicitHeight + 16)
                        color: {
                            if (playback.currentSegmentIndex === index) return "#e3f2fd"
                            if (segmentMouseArea.containsMouse) return "#f5f5f5"
                            return "#fafafa"
                        }
                        radius: 8
                        border.color: playback.currentSegmentIndex === index ? "#2196f3" : "#e0e0e0"
                        border.width: playback.currentSegmentIndex === index ? 2 : 1
                        
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                        
                        MouseArea {
                            id: segmentMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            
                            onClicked: {
                                if (lastClickedSegment !== index || !playback.isPlaying) {
                                    lastClickedSegment = index
                                    playback.playSegment(index)
                                    if (loopEnabled) {
                                        savedSegmentIndexForLoop = index
                                    }
                                }
                            }
                        }
                        
                        RowLayout {
                            id: contentRow
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10
                            
                            Label {
                                Layout.preferredWidth: 50
                                text: (index + 1).toString()
                                font.pixelSize: 13
                                font.bold: true
                                color: playback.currentSegmentIndex === index ? "#2196f3" : "#616161"
                                horizontalAlignment: Text.AlignHCenter
                            }
                            
                            Label {
                                Layout.preferredWidth: 100
                                text: formatTime(appController.getSegmentStartTime(index))
                                font.family: "monospace"
                                font.pixelSize: 12
                                color: "#616161"
                            }
                            
                            Label {
                                Layout.preferredWidth: 100
                                text: formatTime(appController.getSegmentEndTime(index))
                                font.family: "monospace"
                                font.pixelSize: 12
                                color: "#616161"
                            }
                            
                            Label {
                                Layout.fillWidth: true
                                text: appController.getSegmentText(index)
                                wrapMode: Text.Wrap
                                font.pixelSize: 13
                                color: "#212121"
                            }
                            
                            Button {
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 40
                                text: "▶"
                                font.pixelSize: 16
                                
                                ToolTip.visible: hovered
                                ToolTip.text: "播放"
                                ToolTip.delay: 500
                                
                                background: Rectangle {
                                    color: parent.down ? "#1565c0" : (parent.hovered ? "#1976d2" : "#2196f3")
                                    radius: 20
                                }
                                
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: "#ffffff"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                
                                onClicked: {
                                    lastClickedSegment = index
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
                            implicitWidth: 8
                            radius: 4
                            color: parent.pressed ? "#2196f3" : "#bdbdbd"
                        }
                    }
                }
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
        running: loopEnabled && audioLoaded && savedSegmentIndexForLoop >= 0
        
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
    
    Connections {
        target: playback
        
        // 添加位置监听
        function onPositionChanged() {
            console.log("⏱️  Playback position changed:", playback.position, "ms")
        }
        
        // 添加播放状态监听
        function onIsPlayingChanged() {
            console.log("▶️/⏸️  Playback isPlaying:", playback.isPlaying)
        }
        
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
    
    function formatTime(milliseconds) {
        var totalSeconds = Math.floor(milliseconds / 1000)
        var minutes = Math.floor(totalSeconds / 60)
        var seconds = totalSeconds % 60
        return minutes.toString().padStart(2, '0') + ":" + seconds.toString().padStart(2, '0')
    }
}