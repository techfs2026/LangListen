import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs

Item {
    id: editPanel
    
    property int currentEditIndex: -1
    property bool hasUnsavedChanges: false
    property var originalSegment: null

    property var playbackController: appController.playbackController
    
    signal segmentUpdated(int index)
    signal segmentDeleted(int index)
    signal newSegmentCreated()
    
    function formatTime(milliseconds) {
        var minutes = Math.floor(milliseconds / 60000)
        var seconds = Math.floor((milliseconds % 60000) / 1000)
        var millis = milliseconds % 1000
        return Qt.formatTime(new Date(0, 0, 0, 0, minutes, seconds, millis), "mm:ss.zzz")
    }
    
    function parseTime(timeString) {
        var parts = timeString.split(":")
        if (parts.length !== 2) return 0
        
        var minutes = parseInt(parts[0])
        var secParts = parts[1].split(".")
        var seconds = parseInt(secParts[0])
        var millis = secParts.length > 1 ? parseInt(secParts[1]) : 0
        
        return (minutes * 60000) + (seconds * 1000) + millis
    }
    
    function isValidTimeFormat(timeString) {
        var regex = /^\d{2}:\d{2}\.\d{3}$/
        return regex.test(timeString)
    }
    
    function loadSegment(index) {
        if (index < 0 || index >= appController.segmentCount) {
            clearEdit()
            return
        }
        
        currentEditIndex = index
        var startTime = appController.getSegmentStartTime(index)
        var endTime = appController.getSegmentEndTime(index)
        var text = appController.getSegmentText(index)
        
        originalSegment = {
            startTime: startTime,
            endTime: endTime,
            text: text
        }
        
        startTimeField.text = formatTime(startTime)
        endTimeField.text = formatTime(endTime)
        textEditArea.text = text
        
        segmentIndexLabel.text = "句子 #" + (index + 1)
        hasUnsavedChanges = false
    }
    
    function clearEdit() {
        currentEditIndex = -1
        originalSegment = null
        startTimeField.text = "00:00.000"
        endTimeField.text = "00:00.000"
        textEditArea.text = ""
        segmentIndexLabel.text = "(未选择)"
        hasUnsavedChanges = false
    }
    
    function applyChanges() {
        if (currentEditIndex < 0) {
            messageDialog.showMessage("错误", "没有选择要编辑的句子", true)
            return
        }

        if (!isValidTimeFormat(startTimeField.text)) {
            messageDialog.showMessage("错误", "起始时间格式错误。请使用 mm:ss.SSS 格式", true)
            return
        }
        
        if (!isValidTimeFormat(endTimeField.text)) {
            messageDialog.showMessage("错误", "结束时间格式错误。请使用 mm:ss.SSS 格式", true)
            return
        }
        
        var startTime = parseTime(startTimeField.text)
        var endTime = parseTime(endTimeField.text)
        
        if (startTime >= endTime) {
            messageDialog.showMessage("错误", "起始时间必须小于结束时间", true)
            return
        }
        
        if (textEditArea.text.trim().length === 0) {
            messageDialog.showMessage("错误", "字幕文本不能为空", true)
            return
        }
        
        var success = appController.updateSegment(
            currentEditIndex,
            startTime,
            endTime,
            textEditArea.text.trim()
        )
        
        if (success) {
            hasUnsavedChanges = false
            originalSegment = {
                startTime: startTime,
                endTime: endTime,
                text: textEditArea.text.trim()
            }
            segmentUpdated(currentEditIndex)
            messageDialog.showMessage("成功", "句子已更新", false)
        } else {
            messageDialog.showMessage("错误", "更新句子失败", true)
        }
    }
    
    function resetChanges() {
        if (currentEditIndex < 0 || !originalSegment) {
            return
        }
        
        startTimeField.text = formatTime(originalSegment.startTime)
        endTimeField.text = formatTime(originalSegment.endTime)
        textEditArea.text = originalSegment.text
        hasUnsavedChanges = false
    }
    
    function createNewSegment() {
        var startTime = parseTime(startTimeField.text)
        var endTime = parseTime(endTimeField.text)
        var text = textEditArea.text.trim()
        
        if (!isValidTimeFormat(startTimeField.text) || !isValidTimeFormat(endTimeField.text)) {
            messageDialog.showMessage("错误", "时间格式错误", true)
            return
        }
        
        if (startTime >= endTime) {
            messageDialog.showMessage("错误", "起始时间必须小于结束时间", true)
            return
        }
        
        if (text.length === 0) {
            messageDialog.showMessage("错误", "字幕文本不能为空", true)
            return
        }
        
        appController.addSegment(startTime, endTime, text)
        newSegmentCreated()
        clearEdit()
        messageDialog.showMessage("成功", "新句子已创建", false)
    }
    
    function deleteCurrentSegment() {
        if (currentEditIndex < 0) {
            messageDialog.showMessage("错误", "没有选择要删除的句子", true)
            return
        }
        
        deleteConfirmDialog.open()
    }
    
    Connections {
        target: playbackController
        
        function onSegmentChanged(index, text, startTime, endTime) {
            if (index !== currentEditIndex) {
                loadSegment(index)
            }
        }
    }
    
    Dialog {
        id: messageDialog
        
        property string messageTitle: ""
        property string messageText: ""
        property bool isError: false
        
        function showMessage(title, text, error) {
            messageTitle = title
            messageText = text
            isError = error
            open()
        }
        
        title: messageTitle
        modal: true
        anchors.centerIn: parent
        
        contentItem: Label {
            text: messageDialog.messageText
            wrapMode: Text.Wrap
            color: messageDialog.isError ? "#f44336" : "#4caf50"
        }
        
        standardButtons: Dialog.Ok
    }
    
    Dialog {
        id: deleteConfirmDialog
        
        title: "确认删除"
        modal: true
        anchors.centerIn: parent
        
        contentItem: Label {
            text: "确定要删除这个句子吗？此操作无法撤销。"
            wrapMode: Text.Wrap
        }
        
        standardButtons: Dialog.Yes | Dialog.No
        
        onAccepted: {
            if (appController.deleteSegment(currentEditIndex)) {
                var deletedIndex = currentEditIndex
                clearEdit()
                segmentDeleted(deletedIndex)
                messageDialog.showMessage("成功", "句子已删除", false)
            } else {
                messageDialog.showMessage("错误", "删除句子失败", true)
            }
        }
    }
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 12
        
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            
            Label {
                text: "🤖 智能转写"
                font.pixelSize: 14
                font.bold: true
                color: "#424242"
            }
            
            ComboBox {
                id: modelTypeCombo
                Layout.preferredWidth: 120
                model: ["Base", "Small", "Medium", "Turbo"]
                currentIndex: {
                    if (appController.modelType === "base") return 0
                    if (appController.modelType === "small") return 1
                    if (appController.modelType === "medium") return 2
                    if (appController.modelType === "turbo") return 3
                    return 2
                }
                font.pixelSize: 12
                
                onActivated: {
                    var types = ["base", "small", "medium", "turbo"]
                    appController.modelType = types[currentIndex]
                }
                
                background: Rectangle {
                    color: "#f5f5f5"
                    radius: 4
                    border.color: parent.activeFocus ? "#2196f3" : "#e0e0e0"
                    border.width: 1
                }
            }
            
            Button {
                text: "一键转写"
                font.pixelSize: 12
                Layout.preferredHeight: 32
                enabled: !appController.isProcessing && appController.audioPath !== ""
                
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
                    appController.startOneClickTranscription()
                }
            }
            
            Item { Layout.fillWidth: true }
            
            Label {
                text: "状态: " + appController.currentStatus
                font.pixelSize: 11
                color: {
                    if (appController.currentStatus.indexOf("成功") >= 0 || 
                        appController.currentStatus.indexOf("完成") >= 0) {
                        return "#4caf50"
                    } else if (appController.currentStatus.indexOf("失败") >= 0 || 
                               appController.currentStatus.indexOf("错误") >= 0) {
                        return "#f44336"
                    } else if (appController.currentStatus.indexOf("正在") >= 0) {
                        return "#ff9800"
                    }
                    return "#757575"
                }
            }
            
            Label {
                text: "句子: " + appController.segmentCount
                font.pixelSize: 11
                color: "#757575"
            }
        }
        
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#e0e0e0"
        }
        
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            
            Label {
                text: "当前句子编辑"
                font.pixelSize: 13
                font.bold: true
                color: "#424242"
            }
            
            Label {
                id: segmentIndexLabel
                text: "(未选择)"
                font.pixelSize: 11
                color: currentEditIndex >= 0 ? "#2196f3" : "#9e9e9e"
                font.bold: currentEditIndex >= 0
            }
            
            Item { Layout.fillWidth: true }

            Label {
                text: "● 未保存"
                font.pixelSize: 11
                color: "#ff9800"
                visible: hasUnsavedChanges
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            
            Label {
                text: "起始时间:"
                font.pixelSize: 12
                color: "#616161"
                Layout.preferredWidth: 70
            }
            
            TextField {
                id: startTimeField
                Layout.preferredWidth: 100
                text: "00:00.000"
                font.family: "monospace"
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                
                onTextChanged: {
                    if (currentEditIndex >= 0 && originalSegment) {
                        hasUnsavedChanges = true
                    }
                }
                
                background: Rectangle {
                    color: "#f5f5f5"
                    radius: 4
                    border.color: parent.activeFocus ? "#2196f3" : "#e0e0e0"
                    border.width: 1
                }
            }
            
            Button {
                text: "←"
                font.pixelSize: 16
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                enabled: playbackController && playbackController.duration > 0
                
                ToolTip.visible: hovered
                ToolTip.text: "从当前播放位置设置起点"
                ToolTip.delay: 500
                
                background: Rectangle {
                    color: parent.enabled ?
                           (parent.down ? "#e0e0e0" : (parent.hovered ? "#f5f5f5" : "#fafafa")) :
                           "#f5f5f5"
                    radius: 4
                    border.color: "#e0e0e0"
                    border.width: 1
                }
                
                onClicked: {
                    if (playbackController) {
                        var currentPos = playbackController.position
                        startTimeField.text = formatTime(currentPos)
                        if (currentEditIndex >= 0 && originalSegment) {
                            hasUnsavedChanges = true
                        }
                    }
                }
            }
            
            Item { Layout.preferredWidth: 20 }
            
            Label {
                text: "结束时间:"
                font.pixelSize: 12
                color: "#616161"
                Layout.preferredWidth: 70
            }
            
            TextField {
                id: endTimeField
                Layout.preferredWidth: 100
                text: "00:00.000"
                font.family: "monospace"
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                
                onTextChanged: {
                    if (currentEditIndex >= 0 && originalSegment) {
                        hasUnsavedChanges = true
                    }
                }
                
                background: Rectangle {
                    color: "#f5f5f5"
                    radius: 4
                    border.color: parent.activeFocus ? "#2196f3" : "#e0e0e0"
                    border.width: 1
                }
            }
            
            Button {
                text: "→"
                font.pixelSize: 16
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                enabled: playbackController && playbackController.duration > 0
                
                ToolTip.visible: hovered
                ToolTip.text: "从当前播放位置设置终点"
                ToolTip.delay: 500
                
                background: Rectangle {
                    color: parent.enabled ?
                           (parent.down ? "#e0e0e0" : (parent.hovered ? "#f5f5f5" : "#fafafa")) :
                           "#f5f5f5"
                    radius: 4
                    border.color: "#e0e0e0"
                    border.width: 1
                }
                
                onClicked: {
                    if (playbackController) {
                        var currentPos = playbackController.position
                        endTimeField.text = formatTime(currentPos)
                        if (currentEditIndex >= 0 && originalSegment) {
                            hasUnsavedChanges = true
                        }
                    }
                }
            }
        }
        
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            
            Label {
                text: "字幕文本:"
                font.pixelSize: 12
                color: "#616161"
                Layout.preferredWidth: 70
                Layout.alignment: Qt.AlignTop
            }
            
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 80
                clip: true
                
                TextArea {
                    id: textEditArea
                    placeholderText: "在此编辑字幕文本..."
                    wrapMode: Text.Wrap
                    font.pixelSize: 13
                    selectByMouse: true
                    
                    onTextChanged: {
                        if (currentEditIndex >= 0 && originalSegment) {
                            hasUnsavedChanges = true
                        }
                    }
                    
                    background: Rectangle {
                        color: "#f5f5f5"
                        radius: 4
                        border.color: parent.activeFocus ? "#2196f3" : "#e0e0e0"
                        border.width: 1
                    }
                }
            }
        }
        
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            
            Button {
                text: "新建句子"
                font.pixelSize: 12
                Layout.preferredHeight: 32
                
                background: Rectangle {
                    color: parent.down ? "#0288d1" : (parent.hovered ? "#0097a7" : "#00acc1")
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
                    createNewSegment()
                }
            }
            
            Button {
                text: "删除当前"
                font.pixelSize: 12
                Layout.preferredHeight: 32
                enabled: currentEditIndex >= 0
                
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
                    deleteCurrentSegment()
                }
            }
            
            Item { Layout.fillWidth: true }
            
            Button {
                text: "应用更改"
                font.pixelSize: 12
                Layout.preferredHeight: 32
                enabled: currentEditIndex >= 0 && hasUnsavedChanges
                
                background: Rectangle {
                    color: parent.enabled ?
                           (parent.down ? "#388e3c" : (parent.hovered ? "#43a047" : "#4caf50")) :
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
                    applyChanges()
                }
            }
            
            Button {
                text: "重置"
                font.pixelSize: 12
                Layout.preferredHeight: 32
                enabled: currentEditIndex >= 0 && hasUnsavedChanges
                
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
                    color: parent.enabled ? "#616161" : "#bdbdbd"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                onClicked: {
                    resetChanges()
                }
            }
        }
    }
}