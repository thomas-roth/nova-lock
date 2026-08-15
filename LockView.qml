import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

// Lock face for this plugin. Same property/signal contract as the stock
// Omarchy LockView, so Service.qml drives it unchanged: only the presentation
// differs. Every colour comes from the Color singleton, which is repopulated
// on `omarchy theme set`, so the face follows the active theme.
Item {
  id: root

  property string backgroundPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property bool loadBackground: true
  property string passwordText: ""
  property bool syncingPasswordText: false

  // Size the centre column against a 1440p reference so the clock does not
  // swallow a shorter screen.
  readonly property real centerScale: Math.min(1, height > 0 ? height / 1440 : 1)
  readonly property int centerWidth: Math.round(560 * centerScale)
  // ponytail: clock size is eyeballed for a monospace nerd font, which cannot
  // be condensed the way a variable face can. Turn this knob if the clock
  // crowds the column.
  readonly property int clockFontSize: Math.round(centerWidth / 2.9)
  readonly property int avatarSize: Math.round(centerWidth * 0.46)
  readonly property int fieldHeight: Math.round(64 * Math.max(0.8, centerScale))
  readonly property int dotSize: Math.round(fieldHeight * 0.22)

  readonly property bool errorState: failureMessage.length > 0
  readonly property string statusText: authenticatingPassword ? "Checking…" : ""

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal clearFailureRequested()
  signal wakeRequested()

  // Cache-busts the lock background by appending `?v=`. Adding a query string
  // keeps Image's loader happy while forcing a reload when the background
  // changes mid-session.
  function fileUrl(path) {
    if (!path) return ""
    var encoded = String(path).split("/").map(encodeURIComponent).join("/")
    return "file://" + encoded + "?v=" + backgroundVersion
  }

  function forcePasswordFocus() {
    passwordInput.forceActiveFocus()
  }

  function clearPassword() {
    passwordTextEdited("")
  }

  function syncPasswordText() {
    if (passwordInput.text === passwordText) return
    syncingPasswordText = true
    passwordInput.text = passwordText
    syncingPasswordText = false
  }

  function submitCurrent() {
    var submitted = root.passwordText
    if (submitted.length === 0) return
    root.passwordTextEdited("")
    root.submitPassword(submitted)
  }

  onPasswordTextChanged: syncPasswordText()
  onInputEnabledChanged: {
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }
  Component.onCompleted: {
    syncPasswordText()
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  Rectangle {
    anchors.fill: parent
    color: Color.background

    Image {
      id: wallpaper
      anchors.fill: parent
      source: root.loadBackground ? root.fileUrl(root.backgroundPath) : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      sourceSize.width: width
      sourceSize.height: height
    }

    MultiEffect {
      anchors.fill: wallpaper
      source: wallpaper
      autoPaddingEnabled: false
      blurEnabled: root.loadBackground && wallpaper.status === Image.Ready
      blur: 0.2
      blurMax: 128
      blurMultiplier: 1.25
      contrast: -0.08
    }

    // Scrim: the caelestia face is text-heavy, and an unlucky wallpaper eats
    // the clock without a wash behind it.
    Rectangle {
      anchors.fill: parent
      color: Color.background
      opacity: 0.35
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: { root.wakeRequested(); root.forcePasswordFocus() }
      onPositionChanged: root.wakeRequested()
    }

    ColumnLayout {
      id: center
      anchors.centerIn: parent
      width: root.centerWidth
      spacing: Math.round(14 * root.centerScale)

      // ---- Clock. Hours and minutes sit side by side in two theme colours.
      RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Math.round(root.clockFontSize * 0.18)

        Text {
          text: Qt.formatDateTime(clock.date, "HH")
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: root.clockFontSize
          font.weight: Font.DemiBold
        }

        Text {
          text: Qt.formatDateTime(clock.date, "mm")
          color: Util.alpha(Color.foreground, 0.72)
          font.family: Style.font.family
          font.pixelSize: root.clockFontSize
          font.weight: Font.DemiBold
        }
      }

      Text {
        Layout.alignment: Qt.AlignHCenter
        text: Qt.formatDateTime(clock.date, "dddd • d MMM").toUpperCase()
        color: Color.lock.text
        font.family: Style.font.family
        font.pixelSize: Math.round(Style.font.title * 1.1)
        font.weight: Font.DemiBold
        font.letterSpacing: 2
      }

      // ---- Password pill.
      Rectangle {
        id: field
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Math.round(26 * root.centerScale)
        implicitWidth: Math.round(root.centerWidth * 0.86)
        implicitHeight: root.fieldHeight
        radius: height / 2
        color: Color.lock.background
        border.width: 2
        border.color: root.errorState
          ? Color.lock.borderError
          : Util.alpha(Color.lock.borderActive, passwordInput.activeFocus ? 0.9 : 0.35)

        Behavior on border.color { ColorAnimation { duration: 140 } }

        // The real input, kept invisible: it owns focus, key handling and the
        // buffer, while the dots below are what the user actually sees.
        TextInput {
          id: passwordInput
          anchors.fill: parent
          opacity: 0
          activeFocusOnPress: true
          enabled: root.inputEnabled && !root.authenticatingPassword
          readOnly: root.authenticatingPassword
          echoMode: TextInput.Password
          passwordMaskDelay: 0

          onTextChanged: {
            if (!root.syncingPasswordText) root.passwordTextEdited(text)
            if (text.length > 0) {
              root.wakeRequested()
              if (root.failureMessage.length > 0) root.clearFailureRequested()
            }
          }

          onAccepted: root.submitCurrent()

          Keys.onPressed: function(event) {
            root.wakeRequested()
            if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
              root.passwordTextEdited("")
              event.accepted = true
            }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: root.passwordText.length === 0
          text: root.errorState ? root.failureMessage : root.statusText
          color: root.errorState
            ? Color.lock.textError
            : (root.authenticatingPassword ? Color.lock.text : Color.lock.placeholder)
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.italic: root.errorState
          elide: Text.ElideRight
        }

        // Fingerprint circle. Hidden if no fingerprint is configured.
        Rectangle {
          id: fingerprintCircle
          visible: root.fingerprintConfigured
          anchors.left: parent.left
          anchors.leftMargin: Math.round(root.fieldHeight * 0.14)
          anchors.verticalCenter: parent.verticalCenter
          width: Math.round(root.fieldHeight * 0.72)
          height: width
          radius: width / 2
          color: Color.accent

          Text {
            anchors.centerIn: parent
            text: "󰈷"
            color: Color.lock.background
            font.family: Style.font.family
            font.pixelSize: Math.round(root.fieldHeight * 0.34)
            font.weight: Font.Bold
          }
        }

        // One dot per typed character, popping in as it is typed. The row is
        // clipped rather than scaled: scaling it against its own width made
        // every keystroke re-solve the binding and jump.
        Item {
          id: dotsClip
          anchors.centerIn: parent
          width: field.width - enterButton.width - (root.fingerprintConfigured ? root.fieldHeight + 2 : -15)
          height: field.height
          clip: true
          visible: root.passwordText.length > 0

          Row {
            id: dots
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(root.dotSize * 0.75)
            // Centred while the dots fit; once they outgrow the pill the row
            // slides left so the newest dot stays in view.
            x: width <= dotsClip.width ? (dotsClip.width - width) / 2 : dotsClip.width - width

            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            // A Repeater over a plain int count rebuilds every delegate when
            // the count changes, so animating on creation replayed the pop on
            // the whole row each keystroke. Only the newest dot animates; the
            // rebuilt ones come back already at rest.
            Repeater {
              model: root.passwordText.length

              Rectangle {
                id: dot
                required property int index

                width: root.dotSize
                height: root.dotSize
                radius: width / 2
                color: Color.lock.text

                Component.onCompleted: {
                  if (index === root.passwordText.length - 1) popIn.start()
                }

                NumberAnimation {
                  id: popIn
                  target: dot
                  property: "scale"
                  from: 0
                  to: 1
                  duration: 180
                  easing.type: Easing.OutBack
                }
              }
            }
          }
        }

        // Trailing submit. Fills with the accent once there is something to
        // send, which doubles as "your keystrokes landed".
        Rectangle {
          id: enterButton
          anchors.right: parent.right
          anchors.rightMargin: Math.round(root.fieldHeight * 0.14)
          anchors.verticalCenter: parent.verticalCenter
          width: Math.round(root.fieldHeight * 0.72)
          height: width
          radius: width / 2
          color: root.passwordText.length > 0
            ? Color.accent
            : Util.alpha(Color.foreground, 0.12)

          Behavior on color { ColorAnimation { duration: 140 } }

          Text {
            anchors.centerIn: parent
            text: "󰁔"
            color: root.passwordText.length > 0 ? Color.lock.background : Util.alpha(Color.foreground, 0.5)
            font.family: Style.font.family
            font.pixelSize: Math.round(root.fieldHeight * 0.34)
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: root.passwordText.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.submitCurrent()
          }
        }
      }

      // ---- Attempt counter. The failure text itself lives in the pill; this
      // keeps the running count visible without crowding it.
      Text {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Math.round(6 * root.centerScale)
        visible: root.failedAttempts > 0
        text: root.failedAttempts + (root.failedAttempts === 1 ? " failed attempt" : " failed attempts")
        color: Util.alpha(Color.lock.textError, 0.85)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
