import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs

ApplicationWindow {
    id: root
    visible: true
    width: 1400
    height: 900
    title: "LangListen"
    color: "#f5f7fa"
    
    property string currentAudioPath: ""
    property int currentSegmentIndex: -1
    property bool isPracticeMode: false  // false=编辑模式, true=精听模式
    property bool isDictationMode: false
    
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
        }
        function onSegmentUpdated(index) {
            subtitleListView.model = 0
            subtitleListView.model = appController.segmentCount
        }
    
        function onSegmentDeleted(index) {
            if (currentSegmentIndex >= appController.segmentCount) {
                currentSegmentIndex = appController.segmentCount - 1
            }
            if (currentSegmentIndex >= 0 && editModePanel) {
                editModePanel.loadSegment(currentSegmentIndex)
            } else if (editModePanel) {
                editModePanel.clearEdit()
            }
            subtitleListView.model = 0
            subtitleListView.model = appController.segmentCount
        }
    }
    
    Connections {
        target: appController.playbackController
        function onSegmentChanged(index, text, startTime, endTime) {
            var isLargeJump = false
        
            if (currentSegmentIndex >= 0) {
                var indexDiff = Math.abs(index - currentSegmentIndex)
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
        
            currentSegmentIndex = index
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
                    color: isDictationMode ? "#9c27b0" : (isPracticeMode ? "#4caf50" : "#ff9800")
                    
                    Label {
                        anchors.centerIn: parent
                        text: isDictationMode ? "听写模式" : (isPracticeMode ? "精听模式" : "编辑模式")
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
                            if (currentSegmentIndex === index) return "#e3f2fd"
                            if (mouseArea.containsMouse) return "#fafafa"
                            return "#ffffff"
                        }
                        radius: 6
                        border.color: currentSegmentIndex === index ? "#2196f3" : "#e0e0e0"
                        border.width: currentSegmentIndex === index ? 2 : 1
                        
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
                                currentSegmentIndex = index
                                if (editModePanel) {
                                    editModePanel.loadSegment(index)
                                }
                                if (appController.playbackController) {
                                    appController.playbackController.playSegment(index)
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
                                    color: currentSegmentIndex === index ? "#2196f3" : "#e0e0e0"
                                    
                                    Label {
                                        anchors.centerIn: parent
                                        text: (index + 1).toString()
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: currentSegmentIndex === index ? "#ffffff" : "#616161"
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
                                            // TODO: 收藏功能
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
                                            // TODO: 标记功能
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
                                font.bold: !isPracticeMode && !isDictationMode
                                checkable: true
                                checked: !isPracticeMode && !isDictationMode
                                
                                background: Rectangle {
                                    color: (!isPracticeMode && !isDictationMode) ? "#ffffff" : "transparent"
                                    radius: 6
                                    border.color: (!isPracticeMode && !isDictationMode) ? "#e0e0e0" : "transparent"
                                    border.width: 1
                                }
                                
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: (!isPracticeMode && !isDictationMode) ? "#ff9800" : "#757575"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                
                                onClicked: {
                                    isPracticeMode = false
                                    isDictationMode = false
                                }
                            }
                            
                            Button {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                text: "🎧 精听模式"
                                font.pixelSize: 14
                                font.bold: isPracticeMode && !isDictationMode
                                checkable: true
                                checked: isPracticeMode && !isDictationMode
                                
                                background: Rectangle {
                                    color: (isPracticeMode && !isDictationMode) ? "#ffffff" : "transparent"
                                    radius: 6
                                    border.color: (isPracticeMode && !isDictationMode) ? "#e0e0e0" : "transparent"
                                    border.width: 1
                                }
                                
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: (isPracticeMode && !isDictationMode) ? "#4caf50" : "#757575"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                
                                onClicked: {
                                    isPracticeMode = true
                                    isDictationMode = false
                                }
                            }
                            
                            Button {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                text: "✍️ 听写模式"
                                font.pixelSize: 14
                                font.bold: isDictationMode
                                checkable: true
                                checked: isDictationMode
                                
                                background: Rectangle {
                                    color: isDictationMode ? "#ffffff" : "transparent"
                                    radius: 6
                                    border.color: isDictationMode ? "#e0e0e0" : "transparent"
                                    border.width: 1
                                }
                                
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: isDictationMode ? "#9c27b0" : "#757575"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                
                                onClicked: {
                                    isPracticeMode = false
                                    isDictationMode = true
                                }
                            }
                        }
                    }
                    
                    StackLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        currentIndex: isDictationMode ? 2 : (isPracticeMode ? 1 : 0)
                        
                        Item {
                            EditModePanel {
                                id: editModePanel
                                anchors.fill: parent
                                
                                onSegmentUpdated: function(index) {
                                    subtitleListView.model = 0
                                    subtitleListView.model = appController.segmentCount
                                }
                                
                                onSegmentDeleted: function(index) {
                                    if (currentSegmentIndex === index) {
                                        currentSegmentIndex = -1
                                    } else if (currentSegmentIndex > index) {
                                        currentSegmentIndex--
                                    }
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
                            text: "提示: 滚轮缩放 | 点击跳转 | 黄色为当前句"
                            font.pixelSize: 11
                            color: "#9e9e9e"
                        }
                        
                        Item { Layout.fillWidth: true }
                        
                        CheckBox {
                            text: "句子高亮"
                            checked: true
                            font.pixelSize: 11
                            
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
                        
                        Label {
                            anchors.centerIn: parent
                            text: "波形图区域\n（集成原有 WaveformView 组件）"
                            font.pixelSize: 14
                            color: "#9e9e9e"
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                    
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        
                        Label {
                            id: currentSentenceInfo
                            Layout.fillWidth: true
                            text: "当前: 第1句"
                            font.pixelSize: 11
                            color: "#ff9800"
                            elide: Text.ElideRight
                        }
                        
                        Label {
                            id: hoverTimeLabel
                            text: ""
                            font.pixelSize: 11
                            color: "#2196f3"
                        }
                        
                        Label {
                            text: "缩放: 100.0 px/s"
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
                    color: "#e0e0e0"
                }
                
                Label {
                    text: "🔊"
                    font.pixelSize: 18
                }
                
                Slider {
                    id: volumeSlider
                    Layout.preferredWidth: 100
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
}
