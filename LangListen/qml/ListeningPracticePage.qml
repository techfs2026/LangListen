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
        anchors.topMargin: 16
        anchors.bottomMargin: 40
        anchors.leftMargin: 80
        anchors.rightMargin: 80
        spacing: 16
        
        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            
            Label {
                text: "精听练习"
                font.pixelSize: 32
                font.bold: true
                color: "#1976d2"
            }
            
            Item { Layout.fillWidth: true }
            
            Button {
                text: "导出 SRT"
                font.pixelSize: 12
                padding: 8
                enabled: appController.segmentCount > 0
                
                background: Rectangle {
                    color: parent.enabled ? (parent.down ? "#1565c0" : (parent.hovered ? "#1976d2" : "#2196f3")) : "#e0e0e0"
                    radius: 4
                }
                
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: "#ffffff"
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
                    radius: 4
                }
                
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                onClicked: lrcExportDialog.open()
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
        
        Item { Layout.preferredHeight: 0 }
        
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 260
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
                        enabled: waveform.isLoaded && waveformView.canZoomIn()
                        
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
                        enabled: waveform.isLoaded && waveformView.canZoomOut()
                        
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
                        text: "适配"
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
                    color: "#f5f5f5"
                    radius: 8
                    clip: true
                    
                    Item {
                        anchors.fill: parent
                        
                            Flickable {
                                id: waveformFlickable
                                anchors.fill: parent
                                contentWidth: waveformView.contentWidth
                                contentHeight: height
                                clip: true

                                interactive: !playback.isPlaying
                                boundsBehavior: Flickable.StopAtBounds

                                onContentXChanged: {
                                    waveformView.scrollPosition = contentX
                                }

                                WaveformView {
                                    id: waveformView
                                    width: waveformFlickable.width
                                    height: waveformFlickable.height
                                    x: waveformFlickable.contentX

                                    waveformGenerator: waveform
                                    viewportWidth: waveformFlickable.width
                                    followPlayback: playback.isPlaying
                                    showPerformance: true

                                    Connections {
                                        target: playback
                                        function onPositionChanged() {
                                            if (playback.duration > 0) {
                                                waveformView.currentPosition = playback.position / playback.duration
                                            }
                                        }
                                    }

                                    onRequestDirectScroll: function(targetX) {
                                        waveformFlickable.contentX = targetX
                                    }
                                }
                            }
                        
                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            border.color: "#e0e0e0"
                            border.width: 1
                            radius: 8
                        }
                    }
                    
                    BusyIndicator {
                        anchors.centerIn: parent
                        running: waveform.isProcessing
                        visible: running
                        
                        contentItem: Item {
                            implicitWidth: 48
                            implicitHeight: 48
                            
                            Rectangle {
                                width: parent.width
                                height: parent.height
                                radius: width / 2
                                color: "transparent"
                                border.width: 3
                                border.color: "#2196f3"
                                
                                RotationAnimator on rotation {
                                    from: 0
                                    to: 360
                                    duration: 1000
                                    loops: Animation.Infinite
                                    running: waveform.isProcessing
                                }
                                
                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: "#2196f3"
                                }
                            }
                        }
                    }
                }
            }
        }
        
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            color: "#ffffff"
            radius: 12
            border.color: "#e3f2fd"
            border.width: 1
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12
                
                Button {
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    text: "⏮"
                    font.pixelSize: 20
                    enabled: audioLoaded && playback.currentSegmentIndex > 0
                    
                    ToolTip.visible: hovered
                    ToolTip.text: "上一句"
                    ToolTip.delay: 500
                    
                    background: Rectangle {
                        color: parent.enabled ? (parent.down ? "#e0e0e0" : (parent.hovered ? "#f5f5f5" : "#fafafa")) : "#f5f5f5"
                        radius: 24
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
                    
                    onClicked: {
                        if (playback.currentSegmentIndex > 0) {
                            playback.playSegment(playback.currentSegmentIndex - 1)
                            lastClickedSegment = playback.currentSegmentIndex - 1
                            if (loopEnabled) {
                                savedSegmentIndexForLoop = lastClickedSegment
                            }
                        }
                    }
                }
                
                Button {
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    text: playback.isPlaying ? "⏸" : "▶"
                    font.pixelSize: 20
                    enabled: audioLoaded
                    
                    background: Rectangle {
                        color: parent.enabled ? (parent.down ? "#1565c0" : (parent.hovered ? "#1976d2" : "#2196f3")) : "#e0e0e0"
                        radius: 24
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
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    text: "⏹"
                    font.pixelSize: 20
                    enabled: audioLoaded
                    
                    background: Rectangle {
                        color: parent.enabled ? (parent.down ? "#e0e0e0" : (parent.hovered ? "#f5f5f5" : "#fafafa")) : "#f5f5f5"
                        radius: 24
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
                    
                    onClicked: {
                        playback.stop()
                        lastClickedSegment = -1
                    }
                }
                
                Button {
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    text: "⏭"
                    font.pixelSize: 20
                    enabled: audioLoaded && playback.currentSegmentIndex < appController.segmentCount - 1
                    
                    ToolTip.visible: hovered
                    ToolTip.text: "下一句"
                    ToolTip.delay: 500
                    
                    background: Rectangle {
                        color: parent.enabled ? (parent.down ? "#e0e0e0" : (parent.hovered ? "#f5f5f5" : "#fafafa")) : "#f5f5f5"
                        radius: 24
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
                    
                    onClicked: {
                        if (playback.currentSegmentIndex < appController.segmentCount - 1) {
                            playback.playSegment(playback.currentSegmentIndex + 1)
                            lastClickedSegment = playback.currentSegmentIndex + 1
                            if (loopEnabled) {
                                savedSegmentIndexForLoop = lastClickedSegment
                            }
                        }
                    }
                }
                
                Label {
                    Layout.preferredWidth: 100
                    text: formatTime(playback.position)
                    font.family: "monospace"
                    font.pixelSize: 15
                    color: "#212121"
                    horizontalAlignment: Text.AlignHCenter
                }
                
                Slider {
                    id: progressSlider
                    Layout.fillWidth: true
                    from: 0
                    to: playback.duration
                    value: playback.position
                    enabled: audioLoaded
                    
                    onPressedChanged: {
                        if (!pressed && audioLoaded) {
                            playback.seekTo(value)
                        }
                    }
                    
                    background: Rectangle {
                        x: progressSlider.leftPadding
                        y: progressSlider.topPadding + progressSlider.availableHeight / 2 - height / 2
                        width: progressSlider.availableWidth
                        height: 4
                        radius: 2
                        color: "#e0e0e0"
                        
                        Rectangle {
                            width: progressSlider.visualPosition * parent.width
                            height: parent.height
                            color: "#2196f3"
                            radius: 2
                        }
                    }
                    
                    handle: Rectangle {
                        x: progressSlider.leftPadding + progressSlider.visualPosition * (progressSlider.availableWidth - width)
                        y: progressSlider.topPadding + progressSlider.availableHeight / 2 - height / 2
                        width: 16
                        height: 16
                        radius: 8
                        color: progressSlider.pressed ? "#1565c0" : "#2196f3"
                        border.color: "#ffffff"
                        border.width: 2
                    }
                }
                
                Label {
                    Layout.preferredWidth: 100
                    text: formatTime(playback.duration)
                    font.family: "monospace"
                    font.pixelSize: 15
                    color: "#757575"
                    horizontalAlignment: Text.AlignHCenter
                }
                
                Button {
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    text: loopEnabled ? "🔁" : "➡"
                    font.pixelSize: 18
                    enabled: audioLoaded
                    
                    ToolTip.visible: hovered
                    ToolTip.text: loopEnabled ? "循环播放已开启" : "循环播放已关闭"
                    ToolTip.delay: 500
                    
                    background: Rectangle {
                        color: loopEnabled ? "#2196f3" : (parent.down ? "#e0e0e0" : (parent.hovered ? "#f5f5f5" : "#fafafa"))
                        radius: 24
                        border.color: loopEnabled ? "#1976d2" : "#e0e0e0"
                        border.width: 1
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: loopEnabled ? "#ffffff" : "#424242"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: {
                        loopEnabled = !loopEnabled
                        if (loopEnabled && lastClickedSegment >= 0) {
                            savedSegmentIndexForLoop = lastClickedSegment
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
                
                Label {
                    Layout.fillWidth: true
                    text: "字幕列表"
                    font.pixelSize: 15
                    font.bold: true
                    color: "#424242"
                }
                
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "#f5f5f5"
                    radius: 8
                    
                    ListView {
                        id: segmentListView
                        anchors.fill: parent
                        anchors.margins: 8
                        model: appController.segmentCount
                        spacing: 8
                        clip: true
                        
                        delegate: Rectangle {
                            width: segmentListView.width
                            height: contentRow.implicitHeight + 24
                            color: playback.currentSegmentIndex === index ? "#e3f2fd" : "#ffffff"
                            radius: 6
                            border.color: playback.currentSegmentIndex === index ? "#2196f3" : "#e0e0e0"
                            border.width: 1
                            
                            Behavior on color {
                                ColorAnimation { duration: 200 }
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