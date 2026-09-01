pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

// The first-run tour: a few cards, each one pointing at the part of the window
// it is talking about.
//
// It is a tour rather than a slideshow because the thing worth explaining here
// is not a list of features, it is *where they are*. A card that says "the
// twenty-six swatches are on the left" while dimming everything except the left
// column has done the job; the same sentence over a flat scrim has not.
//
// Nothing here changes a palette, writes a file, or applies anything. Closing
// it — by finishing, skipping, or pressing Escape — is the only thing it does
// besides paint, and that is reported upward so the panel can record it.
Item {
  id: tour

  required property var forge

  // Rects, in this item's coordinates, that a step can point at. The panel
  // hands these over because it is what owns the layout; a step names one and
  // the spotlight follows it, so the tour keeps working when the window is
  // resized or the layout folds.
  property rect editorRect: Qt.rect(0, 0, 0, 0)
  property rect previewRect: Qt.rect(0, 0, 0, 0)
  property rect footerRect: Qt.rect(0, 0, 0, 0)

  property int step: 0
  property bool dontShowAgain: false

  signal finished(bool suppress)

  readonly property var steps: [
    {
      title: "This is Theme Forge",
      body: "It builds a real Omarchy theme: twenty-six colours in a colors.toml, "
          + "which is all Omarchy needs to retheme your terminal, editor, bar, "
          + "browser and window borders at once.\n\n"
          + "Nothing you do here touches your desktop until you press a button that says so.",
      target: "none"
    },
    {
      title: "Roll until something catches your eye",
      body: "Ctrl+R, or the Roll button. Every colour is solved for a target contrast "
          + "ratio against the background rather than picked at random, and a roll that "
          + "cannot make the bands is thrown away before you ever see it.\n\n"
          + "So you can press it as often as you like: none of them will be unreadable.",
      target: "editor"
    },
    {
      title: "Three colours drive the other twenty-three",
      body: "Background, foreground and accent. Click any swatch to bring it under the "
          + "sliders, or type a hex.\n\n"
          + "Edit anything else and it becomes pinned — it survives every later roll "
          + "until you unpin it. That is what lets you keep rolling after you have fixed "
          + "one colour by hand.",
      target: "editor"
    },
    {
      title: "The preview is the real thing",
      body: "A small desktop drawn from the palette in memory, using the same mapping "
          + "Omarchy uses when it generates your configs. The bar, the window borders, a "
          + "terminal with all sixteen colours in it.\n\n"
          + "Judging a palette by swatches is guesswork. Judging it as a screen full of "
          + "text is the actual question.",
      target: "preview"
    },
    {
      title: "Then keep it",
      body: "Name it, and Save writes the theme. Save and apply hands it to Omarchy and "
          + "your desktop changes.\n\n"
          + "Revert puts back whichever theme you were wearing when you opened this "
          + "window, so trying one on costs you nothing.",
      target: "footer"
    }
  ]

  readonly property var current: steps[Math.max(0, Math.min(step, steps.length - 1))]
  readonly property bool onLastStep: step >= steps.length - 1

  function next() {
    if (tour.onLastStep) tour.close()
    else tour.step = tour.step + 1
  }

  function back() {
    if (tour.step > 0) tour.step = tour.step - 1
  }

  function close() {
    tour.finished(tour.dontShowAgain)
  }

  readonly property rect spotlight: {
    switch (tour.current.target) {
      case "editor": return tour.editorRect
      case "preview": return tour.previewRect
      case "footer": return tour.footerRect
      default: return Qt.rect(0, 0, 0, 0)
    }
  }
  readonly property bool hasSpotlight: spotlight.width > 0 && spotlight.height > 0

  focus: true
  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Escape) { tour.close(); event.accepted = true }
    else if (event.key === Qt.Key_Right || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      tour.next(); event.accepted = true
    } else if (event.key === Qt.Key_Left) { tour.back(); event.accepted = true }
    else if (event.key === Qt.Key_Space) {
      // The checkbox, without a pointer. The tour holds the keyboard while it
      // is up and has no text input, so Space is free and means the only
      // checkable thing on screen.
      tour.dontShowAgain = !tour.dontShowAgain
      event.accepted = true
    }
  }

  // --------------------------------------------------------------- the dim
  //
  // Four rectangles around the spotlight rather than one with a hole cut in it:
  // QML has no subtractive fill, and four plain Rectangles are cheaper and
  // sharper than any mask would be. With no spotlight the first one covers
  // everything and the other three collapse.

  readonly property color scrimColor: Qt.rgba(0, 0, 0, 0.62)

  Rectangle {
    color: tour.scrimColor
    x: 0; y: 0
    width: tour.width
    height: tour.hasSpotlight ? Math.max(0, tour.spotlight.y) : tour.height
    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
  }
  Rectangle {
    visible: tour.hasSpotlight
    color: tour.scrimColor
    x: 0
    y: tour.spotlight.y + tour.spotlight.height
    width: tour.width
    height: Math.max(0, tour.height - y)
  }
  Rectangle {
    visible: tour.hasSpotlight
    color: tour.scrimColor
    x: 0
    y: tour.spotlight.y
    width: Math.max(0, tour.spotlight.x)
    height: tour.spotlight.height
  }
  Rectangle {
    visible: tour.hasSpotlight
    color: tour.scrimColor
    x: tour.spotlight.x + tour.spotlight.width
    y: tour.spotlight.y
    width: Math.max(0, tour.width - x)
    height: tour.spotlight.height
  }

  // The lit edge around what is being pointed at, in the same colour Hyprland
  // outlines the focused window with.
  Rectangle {
    visible: tour.hasSpotlight
    x: tour.spotlight.x - 2
    y: tour.spotlight.y - 2
    width: tour.spotlight.width + 4
    height: tour.spotlight.height + 4
    color: "transparent"
    radius: Style.cornerRadius > 0 ? Style.cornerRadius + 2 : 3
    border.width: 1
    border.color: Qt.rgba(tour.forge.colors.accent.r, tour.forge.colors.accent.g,
                          tour.forge.colors.accent.b, 0.75)
    antialiasing: true
    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
  }

  // Swallows every click that is not on the card, so a half-read tour cannot be
  // clicked through into the editor underneath.
  MouseArea { anchors.fill: parent; onClicked: {} }

  // --------------------------------------------------------------- the card

  RiceSurface {
    id: card
    width: Math.min(Style.space(440), tour.width - Style.space(48))
    height: cardBody.implicitHeight + Style.space(36)
    // Vertically centred, always.
    //
    // It used to place itself above or below whatever was lit, which meant it
    // sat in the middle on the first step and slid to the very bottom of the
    // window on the last. A card that travels that far between steps costs more
    // in re-finding it than it saves in not overlapping, so the card holds still
    // and the spotlight does the moving.
    y: Math.round((tour.height - height) / 2)

    // Horizontally it moves only when it would otherwise sit on the thing it is
    // pointing at -- and only sideways, so it stays on the same line of sight.
    x: {
      var gap = Style.space(20)
      var centred = Math.round((tour.width - width) / 2)
      if (!tour.hasSpotlight) return centred
      // A spotlight spanning most of the window cannot be dodged. Centre it and
      // accept the overlap; the lit edge still reads around it.
      if (tour.spotlight.width > tour.width * 0.72) return centred
      // Overlapping vertically is what makes the dodge necessary at all.
      var clash = tour.spotlight.y < y + height && tour.spotlight.y + tour.spotlight.height > y
      if (!clash) return centred
      if (tour.spotlight.x + tour.spotlight.width / 2 < tour.width / 2)
        return Math.min(tour.width - width - gap, tour.spotlight.x + tour.spotlight.width + gap)
      return Math.max(gap, tour.spotlight.x - width - gap)
    }
    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    tint: tour.forge.surface
    fillAlpha: 0.97
    cornerRadius: 18

    Column {
      id: cardBody
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(20)
      anchors.rightMargin: Style.space(20)
      spacing: Style.space(10)

      Text {
        text: (tour.step + 1) + " OF " + tour.steps.length
        textFormat: Text.PlainText
        color: tour.forge.faint
        font.family: tour.forge.uiFont
        font.pixelSize: Style.font.caption
        font.letterSpacing: 2
        font.bold: true
      }

      Text {
        width: parent.width
        text: tour.current.title
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: tour.forge.ink
        font.family: tour.forge.uiFont
        font.pixelSize: Style.font.heading
        font.bold: true
      }

      Text {
        width: parent.width
        text: tour.current.body
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        lineHeight: 1.25
        color: tour.forge.dim
        font.family: tour.forge.uiFont
        font.pixelSize: Style.font.bodySmall
      }

      Item { width: 1; height: Style.space(2) }

      // The checkbox. A square that fills in, rather than the kit's toggle
      // switch: "don't show this again" is a one-off decision inside a dialog,
      // which is what a checkbox means, and a switch would suggest a setting
      // being flipped in place. The same value does appear as a switch in
      // Settings, where it *is* a setting.
      // The box, its label, and one click target covering both -- a 15px square
      // is not something to ask anyone to hit.
      Item {
        width: parent.width
        height: checkRow.implicitHeight

        Row {
          id: checkRow
          spacing: Style.space(8)

          Rectangle {
            id: box
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(15)
            height: Style.space(15)
            radius: 3
            antialiasing: true
            color: tour.dontShowAgain
              ? tour.forge.colors.accent
              : Qt.rgba(tour.forge.ink.r, tour.forge.ink.g, tour.forge.ink.b, 0.06)
            border.width: 1
            border.color: tour.dontShowAgain
              ? tour.forge.colors.accent
              : Qt.rgba(tour.forge.ink.r, tour.forge.ink.g, tour.forge.ink.b, 0.35)
            Behavior on color { ColorAnimation { duration: 120 } }

            Text {
              anchors.centerIn: parent
              visible: tour.dontShowAgain
              text: "\u2713"
              textFormat: Text.PlainText
              color: tour.forge.colors.background
              font.family: tour.forge.uiFont
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Don't show this again"
            textFormat: Text.PlainText
            color: tour.forge.dim
            font.family: tour.forge.uiFont
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "SPACE"
            textFormat: Text.PlainText
            color: tour.forge.faint
            font.family: tour.forge.uiFont
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
          }
        }

        MouseArea {
          x: -Style.space(4)
          y: -Style.space(4)
          width: checkRow.width + Style.space(8)
          height: checkRow.height + Style.space(8)
          cursorShape: Qt.PointingHandCursor
          onClicked: tour.dontShowAgain = !tour.dontShowAgain
        }
      }

      Item { width: 1; height: Style.space(4) }

      Item {
        width: parent.width
        height: navRow.implicitHeight

        Row {
          spacing: Style.space(5)
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter

          Repeater {
            model: tour.steps.length
            delegate: Rectangle {
              required property int index
              anchors.verticalCenter: parent.verticalCenter
              width: index === tour.step ? Style.space(14) : Style.space(5)
              height: Style.space(5)
              radius: height / 2
              color: index === tour.step
                ? tour.forge.colors.accent
                : Qt.rgba(tour.forge.ink.r, tour.forge.ink.g, tour.forge.ink.b, 0.22)
              Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }
          }
        }

        Row {
          id: navRow
          anchors.right: parent.right
          spacing: Style.spacing.controlGap

          RiceButton {
            text: "Skip"
            foreground: tour.forge.dim
            tint: tour.forge.surface
            tooltipText: "Close the tour and get on with it"
            onClicked: tour.close()
          }

          RiceButton {
            visible: tour.step > 0
            text: "Back"
            foreground: tour.forge.ink
            tint: tour.forge.surface
            onClicked: tour.back()
          }

          RiceButton {
            text: tour.onLastStep ? "Start designing" : "Next"
            foreground: tour.forge.colors.accent
            accent: tour.forge.colors.accent
            selected: true
            tint: tour.forge.surface
            onClicked: tour.next()
          }
        }
      }
    }
  }
}
