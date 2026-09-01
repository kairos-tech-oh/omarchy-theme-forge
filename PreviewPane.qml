pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import "Palette.js" as Palette

// The right column: a small desktop wearing the palette that is currently in
// memory.
//
// Nothing here writes a file or applies a theme. It is drawn from the same 26
// values that would be written, using the same mapping omarchy-theme-set uses
// when it fills in shell.toml.tpl -- the bar takes `background` and
// `foreground`, its alert colour is `red`, popup and window borders are the
// hyprland active-border gradient of `accent` into `bright_foreground`, and a
// selected row is `foreground` at 8% with `accent` text. So what this shows is
// not an impression of the theme; it is the theme, at a smaller size.
//
// That is the whole reason the plugin is worth having. Judging a palette by its
// swatches is guesswork; judging it as a terminal full of text next to a bar
// full of chrome is the actual question, and this answers it in a repaint
// rather than in a theme switch.
Item {
  id: pane

  required property var forge
  readonly property var colors: forge.colors

  // Set when the window is too narrow for two columns and the preview has been
  // stacked above the editor. The mock desktop is the part worth keeping at any
  // size; the heading, the paired ramp and the contrast note are the parts that
  // can wait until there is room, and the twenty-six-swatch grid in the editor
  // already carries the same numbers.
  property bool compact: false

  // Small, fixed sample text. Nothing here comes from outside the plugin, but
  // every Text still pins textFormat: Text.PlainText -- the rule is worth more
  // as a habit that covers the next edit than as a judgement call made per
  // element.
  readonly property var codeLines: [
    { text: "function derive(spec) {", role: "keyword" },
    { text: "  var bg = normHex(spec.background)", role: "plain" },
    { text: "  // solved, not guessed", role: "comment" },
    { text: "  return solve(bg, 9.5)", role: "call" },
    { text: "}", role: "keyword" }
  ]

  Text {
    id: heading
    anchors.top: parent.top
    anchors.left: parent.left
    visible: !pane.compact
    text: "PREVIEW"
    textFormat: Text.PlainText
    color: pane.forge.faint
    font.family: pane.forge.uiFont
    font.pixelSize: Style.font.caption
    font.letterSpacing: 2
    font.bold: true
  }

  // ------------------------------------------------------------ the desktop

  Rectangle {
    id: screen
    anchors.top: pane.compact ? parent.top : heading.bottom
    anchors.topMargin: pane.compact ? 0 : Style.spacing.lg
    anchors.left: parent.left
    anchors.right: parent.right
    // Its natural proportion, or whatever is left once the blocks above and
    // below have taken theirs -- whichever is smaller. Tiled beside another
    // window there is often less room than the proportion would like.
    height: Math.max(Style.space(120),
                     Math.min(Math.round(width * 0.58),
                              parent.height - (pane.compact ? 0 : heading.height + Style.spacing.lg)
                                            - (pane.compact ? 0 : extras.height + Style.spacing.lg)))
    radius: Style.cornerRadius
    clip: true
    color: pane.colors.background

      // --- the wallpaper -----------------------------------------------
      //
      // When no image is chosen this approximates what helper/theme-forge
      // draws: a ground gradient, a corner wash of the accent, and four faint
      // diagonal light traces. It is an approximation and is meant to be --
      // running ImageMagick on every slider frame would make the preview cost
      // seconds instead of nothing.

      Rectangle {
        anchors.fill: parent
        visible: forge.previewImage === ""
        gradient: Gradient {
          GradientStop { position: 0.0; color: pane.colors.darker_background }
          GradientStop { position: 1.0; color: pane.colors.background }
        }
      }

      Rectangle {
        anchors.fill: parent
        visible: forge.previewImage === ""
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop { position: 1.0; color: Qt.rgba(pane.colors.accent.r, pane.colors.accent.g, pane.colors.accent.b, 0.16) }
        }
      }

      Item {
        anchors.fill: parent
        visible: forge.previewImage === ""
        clip: true
        Repeater {
          model: 4
          delegate: Rectangle {
            required property int index
            width: screen.width * 2.4
            height: Math.max(1, Math.round(screen.height * 0.004))
            color: pane.colors.accent
            opacity: 0.16
            rotation: -31
            transformOrigin: Item.Center
            x: -screen.width * 0.7
            y: screen.height * (0.30 + index * 0.17)
          }
        }
      }

      // The one Image in the plugin, and it is pointed only at a file the
      // helper wrote into the private scratch directory it verified -- never at
      // the path the user picked. sourceSize bounds what is *kept* in memory;
      // it does not bound the decode, which for anything but a JPEG happens at
      // the file's full declared size. The decode is bounded upstream instead,
      // by the header probe that refuses an oversized image and by
      // ImageMagick's own -limit flags in a separate process.
      Image {
        anchors.fill: parent
        visible: forge.previewImage !== ""
        source: forge.previewImage === "" ? "" : "file://" + forge.previewImage
        sourceSize.width: 1280
        sourceSize.height: 720
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
      }

      // --- the bar -------------------------------------------------------
      //
      // shell.toml.tpl maps bar.background to `background`, bar.text to
      // `foreground`, and bar.active -- the colour a module uses when it wants
      // attention -- to `red`.

      Rectangle {
        id: mockBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.round(screen.height * 0.062)
        color: pane.colors.background

        Rectangle {
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          height: 1
          color: Qt.rgba(pane.colors.foreground.r, pane.colors.foreground.g, pane.colors.foreground.b, 0.10)
        }

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(7)

          Repeater {
            model: 5
            delegate: Text {
              required property int index
              text: String(index + 1)
              textFormat: Text.PlainText
              color: index === 1 ? pane.colors.accent : Qt.rgba(pane.colors.foreground.r, pane.colors.foreground.g, pane.colors.foreground.b, 0.45)
              font.family: forge.monoFont
              font.pixelSize: Math.max(7, Math.round(mockBar.height * 0.46))
              font.bold: index === 1
            }
          }
        }

        Row {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          Text {
            text: "UPDATES"
            textFormat: Text.PlainText
            color: pane.colors.red
            font.family: forge.monoFont
            font.pixelSize: Math.max(6, Math.round(mockBar.height * 0.40))
            font.letterSpacing: 1
          }
          Text {
            text: "62%"
            textFormat: Text.PlainText
            color: pane.colors.foreground
            font.family: forge.monoFont
            font.pixelSize: Math.max(6, Math.round(mockBar.height * 0.40))
          }
          Text {
            text: "09:24"
            textFormat: Text.PlainText
            color: pane.colors.foreground
            font.family: forge.monoFont
            font.pixelSize: Math.max(6, Math.round(mockBar.height * 0.40))
          }
        }
      }

      // --- the inactive window -------------------------------------------

      MockWindow {
        forge: pane.forge
        active: false
        x: Math.round(screen.width * 0.46)
        y: mockBar.height + Math.round(screen.height * 0.12)
        width: Math.round(screen.width * 0.48)
        height: Math.round(screen.height * 0.60)
        title: "derive.js"

        Column {
          anchors.fill: parent
          anchors.margins: Style.space(7)
          spacing: Style.space(2)

          Repeater {
            model: pane.codeLines
            delegate: Text {
              required property var modelData
              text: modelData.text
              textFormat: Text.PlainText
              elide: Text.ElideRight
              width: parent.width
              color: modelData.role === "comment" ? pane.colors.dark_foreground
                   : modelData.role === "keyword" ? pane.colors.magenta
                   : modelData.role === "call" ? pane.colors.blue
                   : pane.colors.foreground
              font.family: forge.monoFont
              font.pixelSize: Math.max(6, Math.round(screen.height * 0.030))
            }
          }
        }
      }

      // --- the active window ---------------------------------------------

      MockWindow {
        forge: pane.forge
        active: true
        x: Math.round(screen.width * 0.07)
        y: mockBar.height + Math.round(screen.height * 0.17)
        width: Math.round(screen.width * 0.57)
        height: Math.round(screen.height * 0.70)
        title: "alacritty"

        Column {
          id: term
          anchors.fill: parent
          anchors.margins: Style.space(7)
          spacing: Style.space(2)

          // One cell height for the whole terminal mock, named rather than
          // reached through parent.parent -- that chain depended on how deeply
          // each Text happened to be nested and broke whenever one moved.
          readonly property real cell: Math.max(6, Math.round(screen.height * 0.030))

          Row {
            spacing: Style.space(5)
            Text {
              text: "~/themes"
              textFormat: Text.PlainText
              color: pane.colors.cyan
              font.family: forge.monoFont
              font.pixelSize: term.cell
            }
            Text {
              text: ">"
              textFormat: Text.PlainText
              color: pane.colors.green
              font.family: forge.monoFont
              font.pixelSize: term.cell
            }
            Text {
              text: "omarchy theme list"
              textFormat: Text.PlainText
              color: pane.colors.bright_foreground
              font.family: forge.monoFont
              font.pixelSize: term.cell
            }
          }

          Text {
            text: "ordinary output, the colour most of a session is read in"
            textFormat: Text.PlainText
            elide: Text.ElideRight
            width: parent.width
            color: pane.colors.foreground
            font.family: forge.monoFont
            font.pixelSize: term.cell
          }

          Text {
            text: "# a comment, deliberately quieter"
            textFormat: Text.PlainText
            elide: Text.ElideRight
            width: parent.width
            color: pane.colors.dark_foreground
            font.family: forge.monoFont
            font.pixelSize: term.cell
          }

          Row {
            spacing: Style.space(8)
            Text {
              text: "error"
              textFormat: Text.PlainText
              color: pane.colors.red
              font.family: forge.monoFont
              font.pixelSize: term.cell
            }
            Text {
              text: "warning"
              textFormat: Text.PlainText
              color: pane.colors.yellow
              font.family: forge.monoFont
              font.pixelSize: term.cell
            }
            Text {
              text: "ok"
              textFormat: Text.PlainText
              color: pane.colors.green
              font.family: forge.monoFont
              font.pixelSize: term.cell
            }
            Text {
              text: "link"
              textFormat: Text.PlainText
              color: pane.colors.blue
              font.family: forge.monoFont
              font.pixelSize: term.cell
            }
          }

          // A selected row, drawn the way the shell's menu draws one:
          // foreground at 8%, with accent text.
          Rectangle {
            width: parent.width
            height: term.cell + Style.space(5)
            radius: 2
            color: Qt.rgba(pane.colors.foreground.r, pane.colors.foreground.g, pane.colors.foreground.b, 0.08)
            Text {
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: Style.space(4)
              text: "selected row"
              textFormat: Text.PlainText
              color: pane.colors.accent
              font.family: forge.monoFont
              font.pixelSize: term.cell
            }
          }

          Item { width: 1; height: Style.space(3) }

          // `ls --color` is where most people actually read a palette's ANSI
          // colours: several of them at once, small, side by side, against the
          // ground. A ramp of swatches never shows that.
          Row {
            spacing: Style.space(10)
            Repeater {
              model: [
                { name: "colors.toml", key: "foreground" },
                { name: "backgrounds", key: "blue" },
                { name: "build.sh", key: "green" },
                { name: "old.bak", key: "dark_foreground" }
              ]
              delegate: Text {
                required property var modelData
                text: modelData.name
                textFormat: Text.PlainText
                color: pane.colors[modelData.key]
                font.family: forge.monoFont
                font.pixelSize: term.cell
                font.bold: modelData.key === "green"
              }
            }
          }

          Item { width: 1; height: Style.space(3) }

          // The sixteen in a row, the way a terminal colour test prints them --
          // at text size, on the ground, rather than as poster-sized swatches.
          Row {
            spacing: Style.space(1)
            Repeater {
              model: ["red", "orange", "yellow", "green", "cyan", "blue", "magenta",
                      "bright_red", "bright_yellow", "bright_green", "bright_cyan",
                      "bright_blue", "bright_magenta"]
              delegate: Rectangle {
                required property string modelData
                width: term.cell * 1.1
                height: term.cell * 1.1
                color: pane.colors[modelData]
              }
            }
          }
        }
      }
    }

  // -------------------------------------------------- the blocks beneath
  //
  // Anchored to the bottom rather than following the screen, so the screen
  // can be told how much room is left. Hidden entirely when the pane has been
  // stacked above the editor and there is no room to spare.
  Column {
    id: extras
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.spacing.lg
    visible: !pane.compact
    height: visible ? implicitHeight : 0


    // ------------------------------------------------------------ the ramp

    Text {
      text: "THE SIXTEEN"
      textFormat: Text.PlainText
      color: forge.faint
      font.family: forge.uiFont
      font.pixelSize: Style.font.caption
      font.letterSpacing: 2
      font.bold: true
    }

    // The ANSI ramp as a terminal draws it: normals on top, brights beneath,
    // each pair in a column so a bright that is not actually brighter than its
    // base is obvious at a glance.
    Row {
      width: parent.width
      spacing: Style.space(3)

      Repeater {
        model: ["red", "orange", "yellow", "green", "cyan", "blue", "magenta", "brown"]

        delegate: Column {
          required property string modelData
          width: (pane.width - Style.space(3) * 7) / 8
          spacing: Style.space(2)

          Rectangle {
            width: parent.width
            height: Style.space(18)
            radius: 2
            color: pane.colors[modelData]
          }

          Rectangle {
            width: parent.width
            height: Style.space(18)
            radius: 2
            // brown has no bright partner in the colors.toml schema, so the
            // slot below it shows the ground instead of inventing one.
            color: pane.colors["bright_" + modelData] !== undefined
              ? pane.colors["bright_" + modelData]
              : pane.colors.lighter_background
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: modelData.substring(0, 3)
            textFormat: Text.PlainText
            color: forge.faint
            font.family: forge.monoFont
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    // ------------------------------------------------------ what is off-band

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      color: forge.failingCount === 0 ? forge.dim : pane.colors.yellow
      font.family: forge.uiFont
      font.pixelSize: Style.font.caption
      text: {
        if (forge.failingCount === 0) {
          return "Text sits between 6.0 and 13.5 against the ground, and every terminal colour between 4.5 and 9.5. "
               + "The ceilings matter as much as the floors: neon on black at 18:1 is a glare source, not legibility."
        }
        var bad = Palette.failingKeys(pane.colors)
        return "Outside the band: " + bad.join(", ") + ". Roll again, or unpin them and let the solver place them."
      }
    }
  }
}
