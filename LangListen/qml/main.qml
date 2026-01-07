import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs
import WaveformRenderer 1.0

ApplicationWindow {
    id: root
    visible: true
    width: 1400
    height: 900
    title: "LangListen"
    color: "#f5f7fa"
    
    property string currentAudioPath: ""
    
    FileDialog {
        id: audioFileDialog
        title: "选择音频文件"
        nameFilters: ["音频文件 (*.wav *.mp3 *.m4a *.flac *.ogg *.aac)", "所有文件 (*)"]
        onAccepted: {
            var path = selectedFile.toString()
            path = path.replace(/^file:\/\/\//, "")
            currentAudioPath = path
            appController.audioPath = path
            appController.loadAudioForPlayback()
            
            if (appController.waveformGenerator && !appController.hasSubtitles) {
                appController.waveformGenerator.loadAudio(path)
            }
        }
    }
    
    FileDialog {
        id: srtExportDialog
        title: "导出SRT字幕文件"
        fileMode: FileDialog.SaveFile
        nameFilters: ["SRT字幕文件 (*.srt)"]
        defaultSuffix: "srt"
        onAccepted: {
            var path = selectedFile.toString()
            path = path.replace(/^file:\/\/\//, "")
            appController.exportSRT(path)
        }
    }
    
    FileDialog {
        id: lrcExportDialog
        title: "导出LRC歌词文件"
        fileMode: FileDialog.SaveFile
        nameFilters: ["LRC歌词文件 (*.lrc)"]
        defaultSuffix: "lrc"
        onAccepted: {
            var path = selectedFile.toString()
            path = path.replace(/^file:\/\/\//, "")
            appController.exportLRC(path)
        }
    }
    
    Connections {
        target: appController
        function onSegmentCountChanged() {
            subtitleListView.model = 0
            subtitleListView.model = appController.segmentCount
            loadSegmentsToWaveform()
        }
        function onSegmentUpdated(index) {
            subtitleListView.model = 0
            subtitleListView.model = appController.segmentCount
            loadSegmentsToWaveform()
        }
    
        function onSegmentDeleted(index) {
            if (editModePanel && appController.playbackController.currentSegmentIndex >= 0) {
                editModePanel.loadSegment(appController.playbackController.currentSegmentIndex)
            } else if (editModePanel) {
                editModePanel.clearEdit()
            }
            subtitleListView.model = 0
            subtitleListView.model = appController.segmentCount
            loadSegmentsToWaveform()
        }
    }
    
    Connections {
        target: appController.playbackController
        
        function onSegmentChanged(index, text, startTime, endTime) {
            var isLargeJump = false
        
            var previousIndex = subtitleListView.currentIndex
            if (previousIndex >= 0) {
                var indexDiff = Math.abs(index - previousIndex)
                isLargeJump = indexDiff > 3
            } else {
                isLargeJump = true
            }
        
            if (isLargeJump) {
                subtitleListView.highlightMoveDuration = 0
                subtitleListView.currentIndex = index
                subtitleListView.positionViewAtIndex(index, ListView.Center)
            
                Qt.callLater(function() {
                    subtitleListView.highlightMoveDuration = 250
                })
            } else {
                subtitleListView.highlightMoveDuration = 250
                subtitleListView.currentIndex = index
            }
        }
    }
    
    Connections {
        target: appController.waveformGenerator
        
        function onLoadingCompleted() {
            loadSegmentsToWaveform()
        }
    }
    
    function loadSegmentsToWaveform() {
        if (!appController.waveformGenerator || !appController.waveformGenerator.isLoaded) {
            return
        }
        
        waveformView.clearSentences()
        
        for (var i = 0; i < appController.segmentCount; i++) {
            var startTime = appController.getSegmentStartTime(i)
            var endTime = appController.getSegmentEndTime(i)
            var text = appController.getSegmentText(i)
            waveformView.addSentence(startTime, endTime, text)
        }
    }
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12
        
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            color: "#ffffff"
            radius: 8
            border.color: "#e3f2fd"
            border.width: 1
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16
                
                Label {
                    text: "🎧 LangListen"
                    font.pixelSize: 24
                    font.bold: true
                    color: "#1976d2"
                }
                
                Label {
                    text: currentAudioPath ? "📁 " + currentAudioPath.split('/').pop() : "未加载音频"
                    font.pixelSize: 13
                    color: "#757575"
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                }
                
                Button {
                    text: "打开音频"
                    font.pixelSize: 13
                    Layout.preferredHeight: 36
                    
                    background: Rectangle {
                        color: parent.down ? "#1565c0" : (parent.hovered ? "#1976d2" : "#2196f3")
                        radius: 6
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: {
                        audioFileDialog.open()
                    }
                }
                
                Rectangle {
                    width: 100
                    height: 36
                    radius: 6
                    color: appController.modeType === "dictation" ? "#9c27b0" : (appController.modeType === "practice" ? "#4caf50" : "#ff9800")
                    
                    Label {
                        anchors.centerIn: parent
                        text: appController.modeType === "dictation" ? "听写模式" : (appController.modeType === "practice" ? "精听模式" : "编辑模式")
                        font.pixelSize: 12
                        font.bold: true
                        color: "#ffffff"
                    }
                }
            }
        }
        
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 480
            color: "#ffffff"
            radius: 8
            border.color: "#e3f2fd"
            border.width: 1
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10
                
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    
                    Label {
                        text: "📝 字幕列表"
                        font.pixelSize: 16
                        font.bold: true
                        color: "#424242"
                    }
                    
                    Label {
                        text: "(" + appController.segmentCount + " 句)"
                        font.pixelSize: 13
                        color: "#757575"
                    }
                    
                    Item { Layout.fillWidth: true }
                    
                    Button {
                        text: "导出SRT"
                        font.pixelSize: 11
                        padding: 8
                        enabled: appController.segmentCount > 0
                        
                        background: Rectangle {
                            color: parent.enabled ? 
                                   (parent.down ? "#1565c0" : (parent.hovered ? "#1976d2" : "#2196f3")) :
                                   "#bdbdbd"
                            radius: 4
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#ffffff"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: {
                            srtExportDialog.open()
                        }
                    }
                    
                    Button {
                        text: "导出LRC"
                        font.pixelSize: 11
                        padding: 8
                        enabled: appController.segmentCount > 0

                        background: Rectangle {
                            color: parent.enabled ? 
                                   (parent.down ? "#1565c0" : (parent.hovered ? "#1976d2" : "#2196f3")) :
                                   "#bdbdbd"
                            radius: 4
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#ffffff"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: {
                            lrcExportDialog.open()
                        }
                    }
                }
                
                ListView {
                    id: subtitleListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 8
                    
                    model: appController.segmentCount

                    highlightMoveDuration: 250
                    highlightMoveVelocity: -1
                    
                    delegate: Rectangle {
                        width: subtitleListView.width
                        height: contentColumn.implicitHeight + 24
                        color: {
                            if (appController.playbackController.currentSegmentIndex === index) return "#e3f2fd"
                            if (mouseArea.containsMouse) return "#fafafa"
                            return "#ffffff"
                        }
                        radius: 6
                        border.color: appController.playbackController.currentSegmentIndex === index ? "#2196f3" : "#e0e0e0"
                        border.width: appController.playbackController.currentSegmentIndex === index ? 2 : 1
                        
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                        Behavior on border.color {
                            ColorAnimation { duration: 150 }
                        }
                        
                        MouseArea {
                            id: mouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            
                            onClicked: {
                                if (editModePanel) {
                                    editModePanel.loadSegment(index)
                                }
                                if (appController.playbackController) {
                                    appController.playbackController.seekToSegment(index)
                                }
                            }
                        }
                        
                        ColumnLayout {
                            id: contentColumn
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8
                            
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12
                                
                                Rectangle {
                                    width: 36
                                    height: 36
                                    radius: 18
                                    color: appController.playbackController.currentSegmentIndex === index ? "#2196f3" : "#e0e0e0"
                                    
                                    Label {
                                        anchors.centerIn: parent
                                        text: (index + 1).toString()
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: appController.playbackController.currentSegmentIndex === index ? "#ffffff" : "#616161"
                                    }
                                }

                                ColumnLayout {
                                    spacing: 4
                                    
                                    Label {
                                        text: "⏱️ " + formatTime(appController.getSegmentStartTime(index)) + "→ " + formatTime(appController.getSegmentEndTime(index))
                                        font.family: "monospace"
                                        font.pixelSize: 11
                                        color: "#616161"
                                    }
                                }
                                
                                Item { Layout.fillWidth: true }

                                Row {
                                    spacing: 4
                                    
                                    Rectangle {
                                        width: 60
                                        height: 22
                                        radius: 11
                                        color: "#fff3e0"
                                        visible: false
                                        
                                        Label {
                                            anchors.centerIn: parent
                                            text: "重点"
                                            font.pixelSize: 10
                                            color: "#f57c00"
                                        }
                                    }
                                }
                                
                                Row {
                                    spacing: 4
                                    
                                    Button {
                                        width: 32
                                        height: 32
                                        text: "⭐"
                                        font.pixelSize: 14
                                        
                                        ToolTip.visible: hovered
                                        ToolTip.text: "收藏"
                                        ToolTip.delay: 500
                                        
                                        background: Rectangle {
                                            color: parent.down ? "#fff9c4" : (parent.hovered ? "#fff59d" : "transparent")
                                            radius: 16
                                        }
                                        
                                        onClicked: {
                                        }
                                    }
                                    
                                    Button {
                                        width: 32
                                        height: 32
                                        text: "🏷️"
                                        font.pixelSize: 14
                                        
                                        ToolTip.visible: hovered
                                        ToolTip.text: "标记"
                                        ToolTip.delay: 500
                                        
                                        background: Rectangle {
                                            color: parent.down ? "#e1f5fe" : (parent.hovered ? "#b3e5fc" : "transparent")
                                            radius: 16
                                        }
                                        
                                        onClicked: {
                                        }
                                    }
                                }
                            }
                            
                            Label {
                                Layout.fillWidth: true
                                text: appController.getSegmentText(index)
                                font.pixelSize: 14
                                color: "#212121"
                                wrapMode: Text.Wrap
                                lineHeight: 1.4
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
        
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 360
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 550
                Layout.fillHeight: true
                color: "#ffffff"
                radius: 8
                border.color: "#e3f2fd"
                border.width: 1
                
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0
                    
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        color: "#fafafa"
                        radius: 8
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 4
                            
                            Button {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                text: "✏️ 编辑模式"
                                font.pixelSize: 14
                                font.bold: appController.modeType === "edit"
                                checkable: true
                                checked: appController.modeType === "edit"
                                
                                background: Rectangle {
                                    color: appController.modeType === "edit" ? "#ffffff" : "transparent"
                                    radius: 6
                                    border.color: appController.modeType === "edit" ? "#e0e0e0" : "transparent"
                                    border.width: 1
                                }
                                
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: appController.modeType === "edit" ? "#ff9800" : "#757575"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                
                                onClicked: {
                                    appController.modeType = "edit"
                                }
                            }
                            
                            Button {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                text: "🎧 精听模式"
                                font.pixelSize: 14
                                font.bold: appController.modeType === "practice"
                                checkable: true
                                checked: appController.modeType === "practice"
                                
                                background: Rectangle {
                                    color: appController.modeType === "practice" ? "#ffffff" : "transparent"
                                    radius: 6
                                    border.color: appController.modeType === "practice" ? "#e0e0e0" : "transparent"
                                    border.width: 1
                                }
                                
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: appController.modeType === "practice" ? "#4caf50" : "#757575"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                
                                onClicked: {
                                    appController.modeType = "practice"
                                }
                            }
                            
                            Button {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                text: "✍️ 听写模式"
                                font.pixelSize: 14
                                font.bold: appController.modeType === "dictation"
                                checkable: true
                                checked: appController.modeType === "dictation"
                                
                                background: Rectangle {
                                    color: appController.modeType === "dictation" ? "#ffffff" : "transparent"
                                    radius: 6
                                    border.color: appController.modeType === "dictation" ? "#e0e0e0" : "transparent"
                                    border.width: 1
                                }
                                
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: appController.modeType === "dictation" ? "#9c27b0" : "#757575"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                
                                onClicked: {
                                    appController.modeType = "dictation"
                                }
                            }
                        }
                    }
                    
                    StackLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        currentIndex: appController.modeType === "dictation" ? 2 : (appController.modeType === "practice" ? 1 : 0)
                        
                        Item {
                            EditModePanel {
                                id: editModePanel
                                anchors.fill: parent
                                
                                onSegmentUpdated: function(index) {
                                    subtitleListView.model = 0
                                    subtitleListView.model = appController.segmentCount
                                }
                                
                                onSegmentDeleted: function(index) {
                                    subtitleListView.model = 0
                                    subtitleListView.model = appController.segmentCount
                                }
                                
                                onNewSegmentCreated: function() {
                                    subtitleListView.model = 0
                                    subtitleListView.model = appController.segmentCount
                                }
                            }
                        }
                        
                        Item {
                            PracticeModePanel {
                                anchors.fill: parent
                            }
                        }

                        Item {
                            DictationModePanel {
                                anchors.fill: parent
                            }
                        }
                    }
                }
            }
            
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#ffffff"
                radius: 8
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
                            text: "🌊 波形图"
                            font.pixelSize: 15
                            font.bold: true
                            color: "#424242"
                        }
            
                        Label {
                            text: "提示: 滚轮缩放 | 点击跳转 | 红色波形为当前句"
                            font.pixelSize: 11
                            color: "#9e9e9e"
                        }
            
                        Item { Layout.fillWidth: true }
            
                        CheckBox {
                            text: "边界调整"
                            checked: false
                            font.pixelSize: 11
                            enabled: appController.modeType === "edit"
                
                            onCheckedChanged: {
                                if (waveformView) {
                                    waveformView.enableBoundaryEdit = checked
                                }
                            }
                
                            indicator: Rectangle {
                                implicitWidth: 18
                                implicitHeight: 18
                                radius: 3
                                border.color: parent.checked ? "#4caf50" : "#bdbdbd"
                                border.width: 2
                                color: "transparent"
                    
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 10
                                    height: 10
                                    radius: 2
                                    color: "#4caf50"
                                    visible: parent.parent.checked
                                }
                            }
                
                            ToolTip.visible: hovered
                            ToolTip.text: "在编辑模式下启用后，可在波形图上拖拽当前句子的起止边界"
                            ToolTip.delay: 500
                        }
            
                        CheckBox {
                            text: "句子高亮"
                            checked: true
                            font.pixelSize: 11
                
                            onCheckedChanged: {
                                if (waveformView) {
                                    waveformView.showSentenceHighlight = checked
                                }
                            }
                
                            indicator: Rectangle {
                                implicitWidth: 18
                                implicitHeight: 18
                                radius: 3
                                border.color: parent.checked ? "#2196f3" : "#bdbdbd"
                                border.width: 2
                                color: "transparent"
                    
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 10
                                    height: 10
                                    radius: 2
                                    color: "#2196f3"
                                    visible: parent.parent.checked
                                }
                            }
                        }
            
                        CheckBox {
                            text: "性能信息"
                            checked: false
                            font.pixelSize: 11
                
                            onCheckedChanged: {
                                if (waveformView) {
                                    waveformView.showPerformance = checked
                                }
                            }
                
                            indicator: Rectangle {
                                implicitWidth: 18
                                implicitHeight: 18
                                radius: 3
                                border.color: parent.checked ? "#2196f3" : "#bdbdbd"
                                border.width: 2
                                color: "transparent"
                    
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 10
                                    height: 10
                                    radius: 2
                                    color: "#2196f3"
                                    visible: parent.parent.checked
                                }
                            }
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
                                contentWidth: waveformView ? waveformView.contentWidth : width
                                contentHeight: height
                                clip: true

                                interactive: !appController.playbackController.isPlaying && !isDraggingBoundary
                                boundsBehavior: Flickable.StopAtBounds

                                property bool isDraggingBoundary: false

                                onContentXChanged: {
                                    if (!isDraggingBoundary && waveformView) {
                                        waveformView.scrollPosition = contentX
                                    }
                                }

                                WaveformView {
                                    id: waveformView
                                    width: waveformFlickable.width
                                    height: waveformFlickable.height

                                    x: waveformFlickable.contentX

                                    waveformGenerator: appController.waveformGenerator
                                    viewportWidth: waveformFlickable.width
                                    followPlayback: appController.playbackController.isPlaying
                                    showPerformance: false
                                    showSentenceHighlight: true
                                    enableBoundaryEdit: false

                                    Connections {
                                        target: appController.playbackController
                                        function onPositionChanged() {
                                            if (appController.playbackController.duration > 0) {
                                                waveformView.currentPosition = appController.playbackController.position / appController.playbackController.duration
                                            }
                                        }
                                    }

                                    onBoundaryDragStarted: {
                                        console.log("Boundary drag started - disabling Flickable")
                                        waveformFlickable.isDraggingBoundary = true
                                    }

                                    onBoundaryDragEnded: {
                                        console.log("Boundary drag ended - enabling Flickable")
                                        waveformFlickable.isDraggingBoundary = false
                                    }

                                    onRequestDirectScroll: function(targetX) {
                                        if (!waveformFlickable.isDraggingBoundary) {
                                            waveformFlickable.contentX = targetX
                                        }
                                    }

                                    onClicked: function(normalizedPos, timeMs) {
                                        appController.playbackController.seekTo(timeMs)
                                        if (!appController.playbackController.isPlaying) {
                                            appController.playbackController.play()
                                        }
                                    }

                                    onSentenceClicked: function(index) {
                                        appController.playbackController.playSegment(index)
                                        subtitleListView.positionViewAtIndex(index, ListView.Contain)
                                    }

                                    onSentenceBoundaryChanged: function(index, newStartMs, newEndMs) {
                                        console.log("Sentence boundary changed:", index, "Start:", newStartMs, "End:", newEndMs)

                                        appController.updateSegment(index, newStartMs, newEndMs, 
                                            appController.getSegmentText(index))

                                        if (editModePanel && editModePanel.currentEditIndex === index) {
                                            editModePanel.startTimeField.text = editModePanel.formatTime(newStartMs)
                                            editModePanel.endTimeField.text = editModePanel.formatTime(newEndMs)
                                            editModePanel.hasUnsavedChanges = false
                                        }

                                        subtitleListView.model = 0
                                        subtitleListView.model = appController.segmentCount
                                    }

                                    onHoveredTimeChanged: function(timeMs) {
                                        if (timeMs >= 0) {
                                            hoverTimeLabel.text = "悬停: " + formatTimeMs(timeMs)
                                        } else {
                                            hoverTimeLabel.text = ""
                                        }
                                    }

                                    onCurrentSentenceIndexChanged: {
                                        if (waveformView.currentSentenceIndex >= 0) {
                                            var sentence = waveformView.getSentenceAt(waveformView.currentSentenceIndex)
                                            currentSentenceInfo.text = "当前: 第" + (waveformView.currentSentenceIndex + 1) + "句 - " + sentence.text
                                        } else {
                                            currentSentenceInfo.text = ""
                                        }
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
                            running: appController.waveformGenerator.isProcessing
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
                                        running: appController.waveformGenerator.isProcessing
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
        
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
            
                        Label {
                            id: currentSentenceInfo
                            Layout.fillWidth: true
                            text: ""
                            font.pixelSize: 11
                            color: "#FF9800"
                            elide: Text.ElideRight
                        }
            
                        Label {
                            id: hoverTimeLabel
                            text: ""
                            font.pixelSize: 11
                            color: "#2196f3"
                        }
            
                        Label {
                            text: waveformView ? ("缩放: " + waveformView.pixelsPerSecond.toFixed(1) + " px/s") : ""
                            font.pixelSize: 11
                            color: "#757575"
                        }
                    }
                }
            }
        }
        
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            color: "#ffffff"
            radius: 8
            border.color: "#e3f2fd"
            border.width: 1
            
            RowLayout {
                anchors.fill: parent
                spacing: 12
                
                Button {
                    text: "|◀"
                    font.pixelSize: 14
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 32
                    Layout.leftMargin: 8
                    enabled: appController.segmentCount > 0
                    
                    ToolTip.visible: hovered
                    ToolTip.text: "上一句"
                    ToolTip.delay: 500
                    
                    background: Rectangle {
                        color: parent.enabled ? 
                               (parent.down ? "#e0e0e0" : (parent.hovered ? "#f5f5f5" : "#fafafa")) : 
                               "#f5f5f5"
                        radius: 4
                        border.color: "#e0e0e0"
                        border.width: 1
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: parent.enabled ? "#424242" : "#bdbdbd"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: {
                        appController.playPreviousSegment()
                    }
                }
                
                Button {
                    text: appController.playbackController && appController.playbackController.isPlaying ? "⏸" : "▶"
                    font.pixelSize: 16
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 32
                    enabled: appController.playbackController && appController.playbackController.duration > 0
                    
                    ToolTip.visible: hovered
                    ToolTip.text: appController.playbackController && appController.playbackController.isPlaying ? "暂停" : "播放"
                    ToolTip.delay: 500
                    
                    background: Rectangle {
                        color: parent.enabled ? 
                               (parent.down ? "#1565c0" : (parent.hovered ? "#1976d2" : "#2196f3")) : 
                               "#bdbdbd"
                        radius: 4
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: {
                        appController.playPause()
                    }
                }
                
                Button {
                    text: "▶|"
                    font.pixelSize: 14
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 32
                    enabled: appController.segmentCount > 0
                    
                    ToolTip.visible: hovered
                    ToolTip.text: "下一句"
                    ToolTip.delay: 500
                    
                    background: Rectangle {
                        color: parent.enabled ? 
                               (parent.down ? "#e0e0e0" : (parent.hovered ? "#f5f5f5" : "#fafafa")) : 
                               "#f5f5f5"
                        radius: 4
                        border.color: "#e0e0e0"
                        border.width: 1
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: parent.enabled ? "#424242" : "#bdbdbd"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: {
                        appController.playNextSegment()
                    }
                }
                
                Button {
                    text: "⏹"
                    font.pixelSize: 16
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 32
                    enabled: appController.playbackController && appController.playbackController.duration > 0
                    
                    ToolTip.visible: hovered
                    ToolTip.text: "停止"
                    ToolTip.delay: 500
                    
                    background: Rectangle {
                        color: parent.enabled ? 
                               (parent.down ? "#c62828" : (parent.hovered ? "#d32f2f" : "#f44336")) : 
                               "#bdbdbd"
                        radius: 4
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: {
                        if (appController.playbackController) {
                            appController.playbackController.stop()
                        }
                    }
                }
                
                Rectangle {
                    width: 1
                    Layout.fillHeight: true
                    Layout.topMargin: 8
                    Layout.bottomMargin: 8
                    color: "#e0e0e0"
                }
                
                Button {
                    text: "🔁"
                    font.pixelSize: 14
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 32
                    enabled: appController.segmentCount > 0
                    
                    ToolTip.visible: hovered
                    ToolTip.text: "单句循环"
                    ToolTip.delay: 500
                    
                    background: Rectangle {
                        color: appController.loopSingleSegment ? 
                               (parent.down ? "#388e3c" : (parent.hovered ? "#43a047" : "#4caf50")) :
                               (parent.enabled ? (parent.down ? "#e0e0e0" : (parent.hovered ? "#f5f5f5" : "#fafafa")) : "#f5f5f5")
                        radius: 4
                        border.color: "#e0e0e0"
                        border.width: 1
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: appController.loopSingleSegment ? "#ffffff" : (parent.enabled ? "#424242" : "#bdbdbd")
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: {
                        appController.loopSingleSegment = !appController.loopSingleSegment
                    }
                }
                
                Button {
                    text: "⏸️"
                    font.pixelSize: 14
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 32
                    enabled: appController.segmentCount > 0
                    
                    ToolTip.visible: hovered
                    ToolTip.text: "自动暂停"
                    ToolTip.delay: 500
                    
                    background: Rectangle {
                        color: appController.autoPause ? 
                               (parent.down ? "#ff6f00" : (parent.hovered ? "#ff8f00" : "#ffa726")) :
                               (parent.enabled ? (parent.down ? "#e0e0e0" : (parent.hovered ? "#f5f5f5" : "#fafafa")) : "#f5f5f5")
                        radius: 4
                        border.color: "#e0e0e0"
                        border.width: 1
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: appController.autoPause ? "#ffffff" : (parent.enabled ? "#424242" : "#bdbdbd")
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: {
                        appController.autoPause = !appController.autoPause
                    }
                }
                
                Rectangle {
                    width: 1
                    Layout.fillHeight: true
                    Layout.topMargin: 8
                    Layout.bottomMargin: 8
                    color: "#e0e0e0"
                }
                
                Label {
                    Layout.preferredWidth: 100
                    text: formatTime(appController.playbackController ? appController.playbackController.position : 0)
                    font.family: "monospace"
                    font.pixelSize: 15
                    color: "#212121"
                    horizontalAlignment: Text.AlignHCenter
                }
                
                Slider {
                    id: progressSlider
                    Layout.fillWidth: true
                    from: 0
                    to: appController.playbackController ? appController.playbackController.duration : 100
                    value: appController.playbackController ? appController.playbackController.position : 0
                    
                    onMoved: {
                        if (appController.playbackController) {
                            appController.playbackController.seekTo(value)
                        }
                    }
                    
                    background: Rectangle {
                        x: parent.leftPadding
                        y: parent.topPadding + parent.availableHeight / 2 - height / 2
                        width: parent.availableWidth
                        height: 4
                        radius: 2
                        color: "#e0e0e0"
                        
                        Rectangle {
                            width: parent.parent.visualPosition * parent.width
                            height: parent.height
                            color: "#2196f3"
                            radius: 2
                        }
                    }
                    
                    handle: Rectangle {
                        x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width)
                        y: parent.topPadding + parent.availableHeight / 2 - height / 2
                        width: 16
                        height: 16
                        radius: 8
                        color: parent.pressed ? "#1565c0" : "#2196f3"
                        border.color: "#ffffff"
                        border.width: 2
                    }
                }
                
                Label {
                    Layout.preferredWidth: 100
                    text: formatTime(appController.playbackController ? appController.playbackController.duration : 0)
                    font.family: "monospace"
                    font.pixelSize: 15
                    color: "#757575"
                    horizontalAlignment: Text.AlignHCenter
                }
                
                Rectangle {
                    width: 1
                    Layout.fillHeight: true
                    Layout.topMargin: 8
                    Layout.bottomMargin: 8
                    color: "#e0e0e0"
                }
                
                Label {
                    text: "🔊"
                    font.pixelSize: 18
                }
                
                Slider {
                    id: volumeSlider
                    Layout.preferredWidth: 100
                    Layout.rightMargin: 8
                    from: 0
                    to: 1
                    value: appController.playbackController ? appController.playbackController.volume : 1
                    
                    onMoved: {
                        if (appController.playbackController) {
                            appController.playbackController.setVolume(value)
                        }
                    }
                    
                    background: Rectangle {
                        x: parent.leftPadding
                        y: parent.topPadding + parent.availableHeight / 2 - height / 2
                        width: parent.availableWidth
                        height: 4
                        radius: 2
                        color: "#e0e0e0"
                        
                        Rectangle {
                            width: parent.parent.visualPosition * parent.width
                            height: parent.height
                            color: "#2196f3"
                            radius: 2
                        }
                    }
                    
                    handle: Rectangle {
                        x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width)
                        y: parent.topPadding + parent.availableHeight / 2 - height / 2
                        width: 14
                        height: 14
                        radius: 7
                        color: parent.pressed ? "#1565c0" : "#2196f3"
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
    
    function formatTimeMs(milliseconds) {
        var totalSeconds = Math.floor(milliseconds / 1000)
        var ms = milliseconds % 1000
        var minutes = Math.floor(totalSeconds / 60)
        var seconds = totalSeconds % 60
        return minutes.toString().padStart(2, '0') + ":" + 
               seconds.toString().padStart(2, '0') + "." + 
               ms.toString().padStart(3, '0')
    }
}