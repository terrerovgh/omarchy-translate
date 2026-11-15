import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Overlay card that shows the Spanish translation of the selected text.
// Summoned by ~/.local/bin/omarchy-translate-selection with {"source": "selection"}:
// translate.py reads the selection itself through wl-paste, and every text
// goes to a process on stdin, never as an argument (other local accounts can
// read process arguments in /proc). {"text": "..."} payloads still work.
// All displayed text is untrusted, so every Text uses PlainText.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string scriptPath: String(Qt.resolvedUrl("translate.py")).replace(/^file:\/\//, "")
  readonly property string targetLang: "es"
  readonly property string altLang: "en"
  readonly property int maxChars: 5000

  property bool opened: false
  property string phase: "idle"            // idle | loading | done | error | empty
  property string original: ""
  property string translation: ""
  property string sourceLang: ""
  property string resultLang: ""
  property string errorText: ""
  property var queuedRequest: null

  property string fontFamily: Style.font.menuFamily
  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Commons.Color.menu.scrim
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int gap: Style.spacing.rowGap

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    var fromSelection = payload.source === "selection"
    var text = typeof payload.text === "string" ? payload.text.trim().slice(0, root.maxChars) : ""

    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    flick.contentY = 0

    if (!fromSelection && !text) {
      root.original = ""
      root.translation = ""
      root.phase = "empty"
      return
    }
    root.start(fromSelection ? { source: "selection" } : { text: text })
  }

  function start(request) {
    request.to = root.targetLang
    request.alt = root.altLang
    root.original = typeof request.text === "string" ? request.text : ""
    root.translation = ""
    root.sourceLang = ""
    root.resultLang = ""
    root.errorText = ""
    root.phase = "loading"

    if (translateProcess.running) {
      // Let the running request finish, then translate the newest selection.
      root.queuedRequest = request
      return
    }
    translateProcess.request = request
    translateProcess.running = true
  }

  function handleOutput(output) {
    if (root.queuedRequest !== null) {
      var next = root.queuedRequest
      root.queuedRequest = null
      Qt.callLater(function() { root.start(next) })
      return
    }
    var result = null
    try { result = JSON.parse(String(output || "").trim()) } catch (e) { result = null }
    if (result && typeof result.original === "string") root.original = result.original.slice(0, root.maxChars)
    if (result && result.error === "empty text") {
      root.phase = "empty"
    } else if (result && result.ok && typeof result.text === "string") {
      root.translation = result.text
      root.sourceLang = String(result.source || "").slice(0, 16)
      root.resultLang = String(result.target || root.targetLang).slice(0, 16)
      root.phase = "done"
    } else {
      root.errorText = result && typeof result.error === "string" ? result.error.slice(0, 200) : "?"
      root.phase = "error"
    }
  }

  function copyTranslation() {
    if (root.phase !== "done" || !root.translation) return
    // Through translate.py's stdin to wl-copy's stdin: never a process argument.
    copyProcess.request = { text: root.translation }
    if (!copyProcess.running) copyProcess.running = true
    root.dismiss()
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "io.github.terrerovgh.translate-selection")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  Process {
    id: translateProcess
    property var request: null
    command: ["python3", "-I", root.scriptPath, "--stdin"]
    running: false
    stdinEnabled: true
    onStarted: {
      write(JSON.stringify(request || {}) + "\n")
      request = null
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleOutput(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("io.github.terrerovgh.translate-selection", text.trim())
    }
  }

  Process {
    id: copyProcess
    property var request: null
    command: ["python3", "-I", root.scriptPath, "--copy"]
    running: false
    stdinEnabled: true
    onStarted: {
      write(JSON.stringify(request || {}) + "\n")
      request = null
    }
    onExited: function(exitCode, exitStatus) {
      if (exitCode === 0)
        Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-notification-send", "-t", "2000", strings.t("copied")])
    }
  }

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "omarchy-translate"

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      readonly property real chromeHeight: contentTopInset + contentBottomInset
      readonly property real maxHeight: panel.height * 0.7
      width: Math.min(Style.space(520), panel.width - Style.gapsOut * 2)
      height: Math.min(content.implicitHeight + chromeHeight, maxHeight)
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
          if (event.key === Qt.Key_Escape || (ctrl && event.key === Qt.Key_W)) {
            root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || (ctrl && event.key === Qt.Key_C)) {
            root.copyTranslation()
            event.accepted = true
          } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
            flick.scrollBy(Style.space(40))
            event.accepted = true
          } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
            flick.scrollBy(-Style.space(40))
            event.accepted = true
          }
        }
      }

      Column {
        id: content
        x: card.contentLeftInset
        y: card.contentTopInset
        width: card.width - card.contentLeftInset - card.contentRightInset
        spacing: root.gap

        Text {
          id: header
          textFormat: Text.PlainText
          width: parent.width
          text: {
            var title = strings.t("title")
            if (root.phase !== "done") return title
            var from = root.sourceLang ? root.sourceLang.toUpperCase() : "?"
            return title + " · " + from + " → " + root.resultLang.toUpperCase()
          }
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          id: originalText
          textFormat: Text.PlainText
          visible: root.original !== ""
          width: parent.width
          text: root.original
          color: root.foreground
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
          maximumLineCount: 3
          elide: Text.ElideRight
        }

        Rectangle {
          id: separator
          visible: root.original !== ""
          width: parent.width
          height: Math.max(1, Style.spacing.hairline)
          color: root.foreground
          opacity: 0.15
        }

        Flickable {
          id: flick
          readonly property real othersHeight: header.height + hint.height + content.spacing * 2
            + (originalText.visible ? originalText.height + separator.height + content.spacing * 2 : 0)
          width: parent.width
          height: Math.max(Style.space(20), Math.min(body.implicitHeight, card.maxHeight - card.chromeHeight - othersHeight))
          contentWidth: width
          contentHeight: body.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          function scrollBy(delta) {
            contentY = Math.max(0, Math.min(contentHeight - height, contentY + delta))
          }

          Text {
            id: body
            textFormat: Text.PlainText
            width: flick.width
            text: {
              if (root.phase === "done") return root.translation
              if (root.phase === "loading") return strings.t("loading")
              if (root.phase === "empty") return strings.t("empty")
              if (root.phase === "error") return strings.t("error").arg(root.errorText)
              return ""
            }
            color: root.foreground
            opacity: root.phase === "done" ? 1 : 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            wrapMode: Text.Wrap
          }
        }

        Text {
          id: hint
          textFormat: Text.PlainText
          width: parent.width
          text: strings.t("hint")
          color: root.foreground
          opacity: 0.4
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignRight
        }
      }
    }
  }
}
