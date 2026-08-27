import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "io.github.legibet.popup-translator"

  property string selectedProvider: "bing"
  property string selectedTargetLanguage: "zh-CN"
  property string selectedAiBaseUrl: "https://api.openai.com/v1"
  property string selectedAiModel: "gpt-5.6"
  property bool apiKeyConfigured: false
  property string apiKeyAction: "keep"
  property string loadStdout: ""
  property string loadStderr: ""
  property string saveStdout: ""
  property string saveStderr: ""
  property string pendingPayload: ""
  property string errorText: ""
  property string statusText: ""
  property bool loading: false
  property bool saving: false

  readonly property var targetLanguageOptions: [
    { value: "zh-CN", label: "Chinese (Simplified)" },
    { value: "en", label: "English" },
    { value: "ja", label: "Japanese" },
    { value: "ko", label: "Korean" },
    { value: "fr", label: "French" },
    { value: "de", label: "German" },
    { value: "es", label: "Spanish" }
  ]

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string settingsCommand: decodeURIComponent(
    String(Qt.resolvedUrl("bin/settings")).replace(/^file:\/\//, ""))
  readonly property bool aiSelected: selectedProvider === "ai"
  readonly property bool canSave: !loading && !saving
    && (!aiSelected
      || (selectedAiBaseUrl.trim() !== "" && selectedAiModel.trim() !== ""))

  function loadSettings() {
    if (loadProcess.running || saveProcess.running) return
    loading = true
    errorText = ""
    statusText = ""
    loadStdout = ""
    loadStderr = ""
    loadProcess.running = true
  }

  function restoreForm(values) {
    selectedProvider = values.provider === "ai" ? "ai" : "bing"
    selectedTargetLanguage = targetLanguageOptions.some(function(option) {
      return option.value === values.targetLanguage
    }) ? values.targetLanguage : "zh-CN"
    selectedAiBaseUrl = String(values.aiBaseUrl || "https://api.openai.com/v1")
    selectedAiModel = String(values.aiModel || "gpt-5.6")

    providerDropdown.value = selectedProvider
    targetLanguageDropdown.value = selectedTargetLanguage
    baseUrlField.text = selectedAiBaseUrl
    modelField.text = selectedAiModel
  }

  function finishLoad(exitCode) {
    loading = false
    if (exitCode !== 0) {
      errorText = loadStderr.trim() || "Unable to load settings."
      return
    }

    try {
      var values = JSON.parse(loadStdout)
      restoreForm(values)
      apiKeyConfigured = values.apiKeyConfigured === true
      apiKeyAction = "keep"
      apiKeyField.text = ""
    } catch (e) {
      errorText = "Settings returned invalid data."
    }
  }

  function saveSettings() {
    if (!canSave) return

    saving = true
    errorText = ""
    statusText = ""
    saveStdout = ""
    saveStderr = ""
    pendingPayload = JSON.stringify({
      provider: selectedProvider,
      targetLanguage: selectedTargetLanguage,
      aiBaseUrl: selectedAiBaseUrl.trim(),
      aiModel: selectedAiModel.trim(),
      apiKeyAction: apiKeyAction,
      apiKey: apiKeyAction === "set" ? apiKeyField.text.trim() : ""
    })
    saveProcess.running = true
  }

  function finishSave(exitCode) {
    saving = false
    var result = ({})
    try { result = JSON.parse(saveStdout) } catch (e) {}
    if (exitCode !== 0 || result.ok !== true) {
      errorText = saveStderr.trim() || "Unable to save settings."
      return
    }

    apiKeyConfigured = result.apiKeyConfigured === true
    apiKeyField.text = ""
    apiKeyAction = "keep"
    statusText = "Settings saved."
  }

  function scrubSecret() {
    pendingPayload = ""
    apiKeyField.text = ""
    apiKeyAction = "keep"
  }

  function apiKeyStatus() {
    if (apiKeyAction === "set") return "A new key will be stored for this Base URL."
    if (apiKeyAction === "clear") return "The stored key will be removed."
    if (apiKeyConfigured) return "A local key is configured for this Base URL."
    return "No API key configured."
  }

  implicitWidth: barButton.implicitWidth
  implicitHeight: barButton.implicitHeight

  onSettingsChanged: {
    if (!opened) restoreForm(settings || ({}))
  }

  onOpenedChanged: {
    if (opened) {
      loadSettings()
      Qt.callLater(function() { panelFocus.forceActiveFocus() })
    } else {
      restoreForm(settings || ({}))
      scrubSecret()
    }
  }

  Process {
    id: loadProcess
    running: false
    command: [root.settingsCommand, "show"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadStdout = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadStderr = text
    }
    onExited: function(exitCode) { Qt.callLater(function() { root.finishLoad(exitCode) }) }
  }

  Process {
    id: saveProcess
    running: false
    command: [root.settingsCommand, "apply"]
    stdinEnabled: true

    onStarted: {
      write(root.pendingPayload + "\n")
      root.pendingPayload = ""
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.saveStdout = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.saveStderr = text
    }
    onExited: function(exitCode) { Qt.callLater(function() { root.finishSave(exitCode) }) }
  }

  BarIconButton {
    id: barButton
    anchors.fill: parent
    bar: root.bar
    text: "󰗊"
    active: root.opened
    tooltipText: "Popup Translator · Click to configure"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton || buttonCode === Qt.RightButton) root.toggle()
    }
  }

  KeyboardPanel {
    id: settingsPanel
    anchorItem: barButton
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panelFocus
    contentWidth: settingsPanel.fittedContentWidth(Style.space(360))
    contentHeight: settingsPanel.fittedContentHeight(settingsColumn.implicitHeight, Style.space(560))

    Item {
      id: panelFocus
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.close()

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: settingsColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: settingsColumn
          width: parent.width
          spacing: Style.space(12)

          Text {
            width: parent.width
            text: "Popup Translator"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "LANGUAGE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Dropdown {
              id: targetLanguageDropdown
              width: parent.width
              label: "Target language"
              value: root.selectedTargetLanguage
              options: root.targetLanguageOptions
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: !root.loading && !root.saving
              onChanged: function(value) {
                root.selectedTargetLanguage = value
                root.statusText = ""
              }
            }
          }

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "PROVIDER"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Dropdown {
              id: providerDropdown
              width: parent.width
              label: "Translation provider"
              value: root.selectedProvider
              options: [
                { value: "bing", label: "Bing" },
                { value: "ai", label: "AI (OpenAI-compatible)" }
              ]
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: !root.loading && !root.saving
              onChanged: function(value) {
                root.selectedProvider = value
                root.statusText = ""
              }
            }

            Column {
              visible: root.aiSelected
              width: parent.width
              spacing: Style.space(8)

              Text {
                width: parent.width
                text: "Base URL"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              TextField {
                id: baseUrlField
                width: parent.width
                text: root.selectedAiBaseUrl
                maximumLength: 2048
                placeholderText: "https://api.openai.com/v1"
                foreground: root.foreground
                enabled: !root.loading && !root.saving
                onTextEdited: {
                  root.selectedAiBaseUrl = text
                  root.statusText = ""
                }
              }

              Text {
                width: parent.width
                text: "Model"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              TextField {
                id: modelField
                width: parent.width
                text: root.selectedAiModel
                maximumLength: 256
                placeholderText: "gpt-5.6"
                foreground: root.foreground
                enabled: !root.loading && !root.saving
                onTextEdited: {
                  root.selectedAiModel = text
                  root.statusText = ""
                }
              }

              Text {
                width: parent.width
                text: "API key"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              TextField {
                id: apiKeyField
                width: parent.width
                password: true
                maximumLength: 8192
                placeholderText: root.apiKeyConfigured ? "Replace stored API key" : "API key (optional)"
                foreground: root.foreground
                enabled: !root.loading && !root.saving
                onTextEdited: {
                  root.apiKeyAction = text.trim() === "" ? "keep" : "set"
                  root.statusText = ""
                }
              }

              Item {
                width: parent.width
                height: Math.max(apiKeyStatus.implicitHeight, removeKeyButton.visible ? removeKeyButton.implicitHeight : 0)

                Text {
                  id: apiKeyStatus
                  anchors.left: parent.left
                  anchors.right: removeKeyButton.visible ? removeKeyButton.left : parent.right
                  anchors.rightMargin: removeKeyButton.visible ? Style.space(8) : 0
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.apiKeyStatus()
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                Button {
                  id: removeKeyButton
                  visible: root.apiKeyConfigured && root.apiKeyAction !== "clear"
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Remove"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  focusable: true
                  enabled: !root.saving
                  onClicked: {
                    apiKeyField.text = ""
                    root.apiKeyAction = "clear"
                    root.statusText = ""
                  }
                }
              }
            }
          }

          Text {
            visible: root.errorText !== "" || root.statusText !== ""
            width: parent.width
            text: root.errorText !== "" ? root.errorText : root.statusText
            textFormat: Text.PlainText
            color: root.errorText !== "" ? Color.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Item {
            width: parent.width
            height: saveButton.implicitHeight

            Button {
              id: saveButton
              anchors.right: parent.right
              text: "Save"
              bordered: true
              focusable: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: root.canSave
              onClicked: root.saveSettings()
            }
          }
        }
      }
    }
  }
}
