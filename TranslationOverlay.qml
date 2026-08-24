pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property bool hovered: false
  property bool copied: false
  property string requestId: ""
  property string dismissedRequestId: ""
  property string requestState: "loading"
  property string sourceText: ""
  property string translation: ""
  property string errorText: ""
  property string direction: ""
  property string provider: "Bing"
  property string monitorName: ""
  property real cursorX: Style.gapsOut
  property real cursorY: Style.gapsOut
  property real reservedLeft: 0
  property real reservedTop: 0
  property real reservedRight: 0
  property real reservedBottom: 0
  property int remainingMs: resultDurationMs

  readonly property string pluginId: (manifest && manifest.id) || "io.github.legibet.popup-translator"
  readonly property int cardGap: Style.space(14)
  readonly property int cardPadding: Style.spacing.popupPadding
  readonly property int resultDurationMs: 12000
  readonly property int requestTimeoutMs: 48000
  readonly property int ipcPayloadLimitBytes: 262144
  readonly property int sourceLimitCharacters: 5000
  readonly property int sourceLimitBytes: 20000
  readonly property int translationLimitBytes: 65536
  readonly property int errorLimitBytes: 4096
  readonly property int metadataLimitBytes: 512

  function withinTextLimits(text, byteLimit, characterLimit) {
    var bytes = 0
    var characters = 0

    for (var i = 0; i < text.length; ++i) {
      var code = text.charCodeAt(i)
      ++characters

      if (code <= 0x7f) bytes += 1
      else if (code <= 0x7ff) bytes += 2
      else if (code >= 0xd800 && code <= 0xdbff
          && i + 1 < text.length
          && text.charCodeAt(i + 1) >= 0xdc00
          && text.charCodeAt(i + 1) <= 0xdfff) {
        bytes += 4
        ++i
      } else bytes += 3

      if (bytes > byteLimit || characters > characterLimit) return false
    }

    return true
  }

  function boundedText(value, byteLimit, characterLimit) {
    if (typeof value !== "string" || value.length > byteLimit) return null
    return withinTextLimits(value, byteLimit, characterLimit) ? value : null
  }

  function finiteNumber(value, fallback) {
    var number = Number(value)
    return isFinite(number) ? number : fallback
  }

  function open(payloadJson) {
    if (typeof payloadJson !== "string"
        || payloadJson.length > ipcPayloadLimitBytes
        || !withinTextLimits(payloadJson, ipcPayloadLimitBytes, ipcPayloadLimitBytes)) return

    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") || ({}) } catch (e) {}

    var incomingId = boundedText(payload.requestId, 128, 128)
    var incomingState = boundedText(payload.state, 16, 16)
    var incomingSource = boundedText(payload.source, sourceLimitBytes, sourceLimitCharacters)
    var incomingTranslation = boundedText(payload.translation, translationLimitBytes, translationLimitBytes)
    var incomingError = boundedText(payload.error, errorLimitBytes, errorLimitBytes)
    var incomingDirection = boundedText(payload.direction, metadataLimitBytes, metadataLimitBytes)
    var incomingProvider = boundedText(payload.provider, metadataLimitBytes, metadataLimitBytes)
    var incomingMonitor = boundedText(payload.monitor, metadataLimitBytes, metadataLimitBytes)
    if (incomingId === null || incomingState === null || incomingSource === null
        || incomingTranslation === null || incomingError === null || incomingDirection === null
        || incomingProvider === null || incomingMonitor === null
        || ["loading", "streaming", "ready", "error"].indexOf(incomingState) < 0) return

    var begins = payload.begin === true
    if (!incomingId) return

    // A new begin supersedes the request currently shown. Updates from any
    // older request are ignored, so slow responses cannot overwrite new text.
    if (!begins && incomingId !== requestId) return

    if (begins) {
      requestId = incomingId
      dismissedRequestId = ""
      sourceText = incomingSource
      translation = ""
      errorText = ""
      direction = incomingDirection
      provider = incomingProvider
      monitorName = incomingMonitor
      cursorX = finiteNumber(payload.x, Style.gapsOut)
      cursorY = finiteNumber(payload.y, Style.gapsOut)
      reservedLeft = Math.max(0, finiteNumber(payload.reservedLeft, 0))
      reservedTop = Math.max(0, finiteNumber(payload.reservedTop, 0))
      reservedRight = Math.max(0, finiteNumber(payload.reservedRight, 0))
      reservedBottom = Math.max(0, finiteNumber(payload.reservedBottom, 0))
      hovered = false
      opened = true
    }

    if (dismissedRequestId === incomingId) return

    requestState = incomingState
    direction = incomingDirection
    provider = incomingProvider
    if (requestState === "streaming" || requestState === "ready") translation = incomingTranslation
    if (requestState === "error") errorText = incomingError || "Translation failed."

    copied = false
    if (requestState === "loading" || requestState === "streaming") {
      remainingMs = 0
      if (requestState === "loading") loadingTimeout.restart()
    } else {
      loadingTimeout.stop()
      remainingMs = resultDurationMs
    }
  }

  function close() {
    dismissedRequestId = requestId
    opened = false
    hovered = false
    loadingTimeout.stop()
  }

  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  function copyTranslation() {
    if (!translation) return
    Quickshell.execDetached(["wl-copy", "--", translation])
    copied = true
    copiedReset.restart()
    remainingMs = Math.max(remainingMs, 4000)
  }

  Timer {
    interval: 100
    repeat: true
    running: root.opened
      && root.requestState !== "loading"
      && root.requestState !== "streaming"
      && !root.hovered
    onTriggered: {
      root.remainingMs -= interval
      if (root.remainingMs <= 0) root.dismiss()
    }
  }

  Timer {
    id: loadingTimeout
    interval: root.requestTimeoutMs
    onTriggered: {
      if (!root.opened || (root.requestState !== "loading" && root.requestState !== "streaming")) return
      root.requestState = "error"
      root.errorText = "Translation timed out. Check your network connection."
      root.remainingMs = root.resultDurationMs
    }
  }

  Timer {
    id: copiedReset
    interval: 1600
    onTriggered: root.copied = false
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      readonly property bool targetScreen: root.monitorName === ""
        ? modelData === Quickshell.screens[0]
        : String(modelData.name) === root.monitorName

      screen: modelData
      visible: targetScreen && (root.opened || card.opacity > 0)
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "omarchy-popup-translator"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      // The transparent remainder of the full-screen layer stays click-through.
      mask: Region { item: card }

      BorderSurface {
        id: card

        readonly property real minX: root.reservedLeft + Style.gapsOut
        readonly property real minY: root.reservedTop + Style.gapsOut
        readonly property real maxX: panel.width - root.reservedRight - Style.gapsOut - width
        readonly property real maxY: panel.height - root.reservedBottom - Style.gapsOut - height
        readonly property real belowY: root.cursorY + root.cardGap
        readonly property real aboveY: root.cursorY - height - root.cardGap
        readonly property real availableHeight: panel.height - root.reservedTop - root.reservedBottom - Style.gapsOut * 2
        readonly property real translationHeightLimit: Math.max(0,
          availableHeight - contentTopInset - contentBottomInset
          - titleArea.height - sourceLabel.implicitHeight - divider.height - resultFooter.height
          - contentColumn.spacing * 4)

        width: Math.min(Style.space(440), panel.width - root.reservedLeft - root.reservedRight - Style.gapsOut * 2)
        height: Math.min(
          contentColumn.implicitHeight + contentTopInset + contentBottomInset,
          panel.height - root.reservedTop - root.reservedBottom - Style.gapsOut * 2)
        x: Math.round(Math.max(minX, Math.min(root.cursorX + root.cardGap, maxX)))
        y: Math.round(Math.max(minY, Math.min(
          belowY + height <= panel.height - root.reservedBottom - Style.gapsOut ? belowY : aboveY,
          maxY)))

        color: Color.popups.background
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
        radius: Style.cornerRadius
        padding: root.cardPadding
        opacity: root.opened ? 1 : 0

        Behavior on opacity {
          NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        HoverHandler {
          onHoveredChanged: root.hovered = hovered
        }

        Column {
          id: contentColumn
          x: card.contentLeftInset
          y: card.contentTopInset
          width: card.width - card.contentLeftInset - card.contentRightInset
          spacing: Style.space(10)

          Item {
            id: titleArea
            width: parent.width
            height: Math.max(titleRow.implicitHeight, closeButton.implicitHeight)

            Row {
              id: titleRow
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(9)

              Text {
                text: "󰗊"
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.icon
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                text: "Translate"
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.title
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                visible: root.direction !== ""
                text: "·  " + root.direction
                textFormat: Text.PlainText
                color: Color.popups.text
                opacity: 0.48
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Button {
              id: closeButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: ""
              tooltipText: "Close"
              foreground: Color.popups.text
              horizontalPadding: Style.space(7)
              verticalPadding: Style.space(5)
              onClicked: root.dismiss()
            }
          }

          Text {
            id: sourceLabel
            width: parent.width
            text: root.sourceText
            textFormat: Text.PlainText
            color: Color.popups.text
            opacity: 0.62
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
          }

          PanelSeparator {
            id: divider
            width: parent.width
            foreground: Color.popups.text
          }

          Row {
            id: loadingRow
            visible: root.requestState === "loading"
            width: parent.width
            spacing: Style.space(9)

            Rectangle {
              width: Style.space(7)
              height: width
              radius: width / 2
              color: Color.accent
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: "Translating…"
              color: Color.popups.text
              opacity: 0.68
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Flickable {
            id: translationView
            visible: root.requestState === "streaming" || root.requestState === "ready"
            width: parent.width
            height: Math.min(translationText.implicitHeight, card.translationHeightLimit)
            contentWidth: width
            contentHeight: translationText.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height

            Controls.ScrollBar.vertical: Controls.ScrollBar {
              policy: Controls.ScrollBar.AsNeeded
            }

            Text {
              id: translationText
              width: translationView.width - (translationView.interactive ? Style.space(10) : 0)
              text: root.translation
              textFormat: Text.PlainText
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
              lineHeight: 1.18
              wrapMode: Text.Wrap
            }
          }

          Text {
            visible: root.requestState === "error"
            width: parent.width
            text: root.errorText
            textFormat: Text.PlainText
            color: Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            lineHeight: 1.15
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
          }

          Item {
            id: resultFooter
            visible: root.requestState === "streaming" || root.requestState === "ready"
            width: parent.width
            height: Math.max(engineLabel.implicitHeight, copyButton.implicitHeight)

            Text {
              id: engineLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: root.provider
              textFormat: Text.PlainText
              color: Color.popups.text
              opacity: 0.42
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Button {
              id: copyButton
              visible: root.requestState === "ready"
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.copied ? "Copied" : "Copy"
              iconText: root.copied ? "" : "󰆏"
              foreground: root.copied ? Color.accent : Color.popups.text
              horizontalPadding: Style.space(9)
              verticalPadding: Style.space(5)
              onClicked: root.copyTranslation()
            }
          }
        }
      }
    }
  }
}
