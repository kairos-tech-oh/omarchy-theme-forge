pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import "Palette.js" as Palette
import "BarStyle.js" as BarStyle

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
//
// Two things make it more than a picture. The bar is drawn the way the user's
// own bar is set up -- which edge, see-through or solid, and Rice Bar's preset
// when that is installed -- because a theme is judged against the bar you have,
// not the one the defaults have. And every painted part carries a Hotspot: hover
// it and the key it wears is named; click it and the colour wheel opens on that
// key. Nobody should have to know that a comment is `dark_foreground`.
Item {
  id: pane

  required property var forge
  readonly property var colors: forge.colors
  readonly property var bar: forge.previewBar

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

  // The palette is hex strings; QML wants a colour with an alpha on it.
  function withAlpha(hex, alpha) {
    var rgb = Palette.hexToRgb(hex)
    if (!rgb) return Qt.rgba(0, 0, 0, alpha)
    return Qt.rgba(rgb.r / 255, rgb.g / 255, rgb.b / 255, alpha)
  }

  // ------------------------------------------------------------- the bar
  //
  // Sized the way the real one is: the mock bar is to the mock screen what a
  // 26px bar is to a monitor, and `barScale` carries Rice Bar's pixel settings
  // (radius, gap) down to that size rather than drawing them at full size on a
  // bar a quarter the height.
  readonly property bool barVertical: bar.vertical === true
  readonly property string barPosition: String(bar.position)
  readonly property int barThickness: Math.max(8, Math.round(screen.height * (barVertical ? 0.066 : 0.062)))
  readonly property real barScale: barThickness / Math.max(1, Style.bar.sizeHorizontal)
  // The widget size. True to scale the bar is a crowd at preview size, so the
  // default draws its contents at three quarters and leaves the air between.
  readonly property real barCell: Math.max(5, Math.round(barThickness * 0.46 * forge.barDensity))

  // What is left of the screen once the bar has taken its edge.
  readonly property int deskX: barPosition === "left" ? barThickness : 0
  readonly property int deskY: barPosition === "top" ? barThickness : 0
  readonly property int deskW: screen.width - (barVertical ? barThickness : 0)
  readonly property int deskH: screen.height - (barVertical ? 0 : barThickness)

  // Rice Bar's colours, derived the way its Service.qml derives them: the bar
  // ground unless text would vanish on it, darkened for glow and mono, tinted
  // toward the accent for material, and lifted to an alpha the bar text can
  // still be read at over a black or a white wallpaper.
  readonly property string riceDecoration: bar.rice ? String(bar.rice.decoration) : "none"
  readonly property string riceSurface: Palette.contrastSurface(colors.background, colors.foreground, colors.accent)
  readonly property string riceFill: riceDecoration === "material" ? Palette.mix(riceSurface, colors.accent, 0.15)
                                   : riceDecoration === "glow" ? Palette.mix(riceSurface, "#000000", 0.22)
                                   : riceDecoration === "mono" ? Palette.mix(riceSurface, "#000000", 0.28)
                                   : riceSurface
  readonly property real riceAlpha: bar.rice
    ? Palette.readableAlpha(riceFill, colors.foreground, BarStyle.visibleAlpha(bar.rice.opacity))
    : 1
  readonly property real riceGap: bar.rice ? Math.round(bar.rice.gap * barScale) : 0
  readonly property bool ricePills: bar.rice ? String(bar.rice.geometry) === "widgets" : false

  // A fixed moment rather than a ticking clock, so two looks at the preview
  // are the same picture and the format is the only thing the bar config moves.
  readonly property var sampleTime: new Date(2026, 8, 2, 9, 24, 0)

  // ------------------------------------------------------- the bar's chrome
  //
  // Rice Bar's decoration for one surface, whether that is a whole section or
  // a single widget. Fills whatever it is put in; the section or the widget
  // decides the rect. Follows the paint recipe in Rice Bar's Service.qml, with
  // powerline's angled ends drawn square -- the cut is a shape path there, and
  // at this size a square end reads the same.
  component Chrome: Item {
    id: chrome

    readonly property var rice: pane.bar.rice
    readonly property string deco: pane.riceDecoration
    readonly property bool edgeRule: deco === "rail" || deco === "minimal"
    readonly property bool plated: deco === "rail" || deco === "bracket" || deco === "minimal"
    readonly property bool bordered: rice ? rice.border === true : false
    readonly property real opacityFactor: rice ? rice.opacity / 100 : 1
    readonly property int inset: Math.max(1, Math.round(2 * pane.barScale))
    readonly property real corner: rice ? rice.radius * pane.barScale : 0
    readonly property int rule: Math.max(1, Math.round((deco === "rail" ? 3 : 2) * pane.barScale))

    visible: rice !== null

    // The surface. Inset from the bar's two long edges the way Rice Bar insets
    // its own, so the chrome sits inside the bar rather than filling it.
    Rectangle {
      id: base
      anchors.fill: parent
      anchors.topMargin: pane.barVertical ? 0 : chrome.inset
      anchors.bottomMargin: pane.barVertical ? 0 : chrome.inset
      anchors.leftMargin: pane.barVertical ? chrome.inset : 0
      anchors.rightMargin: pane.barVertical ? chrome.inset : 0
      radius: Math.min(chrome.corner, width / 2, height / 2)
      antialiasing: true
      color: "transparent"
      border.width: chrome.plated || !chrome.bordered ? 0
                  : (chrome.deco === "outline" ? Math.max(1, Math.round(2 * pane.barScale)) : 1)
      border.color: chrome.deco === "mono" ? pane.colors.foreground : pane.colors.accent

      Rectangle {
        anchors.fill: parent
        anchors.margins: base.border.width
        radius: Math.max(0, base.radius - base.border.width)
        antialiasing: true
        color: pane.withAlpha(pane.riceFill, pane.riceAlpha)

        Hotspot { forge: pane.forge; key: "background" }
      }

      // Glow's two fainter rings inside the border, the same recipe the plugin's
      // own controls wear.
      Rectangle {
        anchors.fill: parent
        anchors.margins: Math.max(1, Math.round(2 * pane.barScale))
        visible: chrome.deco === "glow" && chrome.bordered
        radius: Math.max(0, base.radius - anchors.margins)
        antialiasing: true
        color: "transparent"
        border.width: 1
        border.color: pane.withAlpha(pane.colors.accent, 0.34 * chrome.opacityFactor)
      }

      Rectangle {
        anchors.fill: parent
        anchors.margins: Math.max(2, Math.round(4 * pane.barScale))
        visible: chrome.deco === "glow" && chrome.bordered
        radius: Math.max(0, base.radius - anchors.margins)
        antialiasing: true
        color: "transparent"
        border.width: 1
        border.color: pane.withAlpha(pane.colors.accent, 0.14 * chrome.opacityFactor)
      }
    }

    // Rail and minimal: a rule along the bar's inner edge instead of a border.
    Rectangle {
      visible: chrome.edgeRule
      color: pane.colors.accent
      x: pane.barPosition === "left" ? parent.width - chrome.rule : 0
      y: pane.barPosition === "top" ? parent.height - chrome.rule : 0
      width: pane.barVertical ? chrome.rule : parent.width
      height: pane.barVertical ? parent.height : chrome.rule

      Hotspot { forge: pane.forge; key: "accent" }
    }

    // Bracket: eight corner pieces in the border colour.
    Item {
      anchors.fill: base
      visible: chrome.deco === "bracket"
      readonly property int len: Math.max(2, Math.min(Math.round(10 * pane.barScale), Math.floor(Math.min(width, height) / 3)))
      readonly property int thick: Math.max(1, Math.round(2 * pane.barScale))

      Rectangle { x: 0; y: 0; width: parent.len; height: parent.thick; color: pane.colors.accent }
      Rectangle { x: 0; y: 0; width: parent.thick; height: parent.len; color: pane.colors.accent }
      Rectangle { x: parent.width - parent.len; y: 0; width: parent.len; height: parent.thick; color: pane.colors.accent }
      Rectangle { x: parent.width - parent.thick; y: 0; width: parent.thick; height: parent.len; color: pane.colors.accent }
      Rectangle { x: 0; y: parent.height - parent.thick; width: parent.len; height: parent.thick; color: pane.colors.accent }
      Rectangle { x: 0; y: parent.height - parent.len; width: parent.thick; height: parent.len; color: pane.colors.accent }
      Rectangle { x: parent.width - parent.len; y: parent.height - parent.thick; width: parent.len; height: parent.thick; color: pane.colors.accent }
      Rectangle { x: parent.width - parent.thick; y: parent.height - parent.len; width: parent.thick; height: parent.len; color: pane.colors.accent }
    }
  }

  // ------------------------------------------------------- one bar widget
  //
  // The stock widgets have a glyph each; anything else -- a third-party widget
  // the preview cannot know the look of -- is a small chip the width of one,
  // so a bar with twelve things on the right is drawn with twelve things on the
  // right and the sections take up the room they really take up.
  component Mark: Item {
    id: mark

    required property string widgetId
    readonly property bool clock: widgetId === "omarchy.clock"
    readonly property bool workspaces: widgetId === "omarchy.workspaces"
    readonly property bool update: widgetId === "omarchy.system-update"
    readonly property string glyph: {
      if (widgetId === "omarchy.menu") return "◆"
      if (widgetId === "omarchy.system-update") return "↑"
      if (widgetId === "omarchy.tray") return "▪▪"
      if (widgetId === "omarchy.audio") return "♪"
      if (widgetId === "omarchy.network") return "⇅"
      if (widgetId === "omarchy.power") return "▮"
      if (widgetId === "omarchy.monitor") return "◐"
      if (widgetId === "omarchy.bluetooth") return "ß"
      if (widgetId === "omarchy.keyboard-layout") return "us"
      return ""
    }
    readonly property real pad: Math.max(1, Math.round(4 * pane.barScale))

    implicitWidth: content.implicitWidth + pad * 2
    implicitHeight: content.implicitHeight + pad * 2

    // Pills: each widget has its own surface.
    Chrome {
      anchors.fill: parent
      visible: pane.bar.rice !== null && pane.ricePills
    }

    Item {
      id: content
      anchors.centerIn: parent
      implicitWidth: clockText.visible ? clockText.implicitWidth
                   : glyphText.visible ? glyphText.implicitWidth
                   : cells.visible ? cells.implicitWidth : chip.width
      implicitHeight: clockText.visible ? clockText.implicitHeight
                    : glyphText.visible ? glyphText.implicitHeight
                    : cells.visible ? cells.implicitHeight : chip.height

      Text {
        id: clockText
        visible: mark.clock
        text: Qt.formatDateTime(pane.sampleTime, pane.barVertical ? pane.bar.clockFormatVertical : pane.bar.clockFormat)
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        color: pane.colors.foreground
        font.family: pane.forge.monoFont
        font.pixelSize: pane.barCell
        Hotspot { forge: pane.forge; key: "foreground" }
      }

      Text {
        id: glyphText
        visible: !mark.clock && !mark.workspaces && mark.glyph !== ""
        text: mark.glyph
        textFormat: Text.PlainText
        // bar.active: the colour a widget takes when it wants attention, which
        // is what the update indicator does.
        color: mark.update ? pane.colors.red : pane.colors.foreground
        font.family: pane.forge.monoFont
        font.pixelSize: pane.barCell
        Hotspot { forge: pane.forge; key: mark.update ? "red" : "foreground" }
      }

      // Workspaces the way the stock widget draws them: numbers in the bar
      // text, the focused one a filled glyph, the empty ones at half strength.
      Grid {
        id: cells
        visible: mark.workspaces
        columns: pane.barVertical ? 1 : 5
        spacing: Math.max(1, Math.round(3 * pane.barScale))
        Repeater {
          model: 5
          delegate: Text {
            required property int index
            readonly property bool focused: index === 1
            readonly property bool occupied: index === 0 || index === 2
            text: focused ? "●" : String(index + 1)
            textFormat: Text.PlainText
            color: pane.colors.foreground
            opacity: focused || occupied ? 1 : 0.5
            font.family: pane.forge.monoFont
            font.pixelSize: pane.barCell
            Hotspot { forge: pane.forge; key: "foreground" }
          }
        }
      }

      Rectangle {
        id: chip
        visible: !mark.clock && !mark.workspaces && mark.glyph === ""
        width: Math.round(pane.barCell * 1.3)
        height: Math.round(pane.barCell * 0.7)
        radius: height / 2
        color: pane.withAlpha(pane.colors.foreground, 0.4)
        Hotspot { forge: pane.forge; key: "foreground" }
      }
    }
  }

  // ------------------------------------------------------- one bar section
  //
  // Left, centre or right: its widgets in a row (or a column on a side bar),
  // padded by Rice Bar's gap and, unless the preset is pills, on one shared
  // surface.
  component Section: Item {
    id: section

    required property var widgetIds
    readonly property int count: Array.isArray(widgetIds) ? widgetIds.length : 0

    implicitWidth: pane.barVertical ? pane.barThickness : marks.implicitWidth + pane.riceGap * 2
    implicitHeight: pane.barVertical ? marks.implicitHeight + pane.riceGap * 2 : pane.barThickness
    visible: count > 0

    Chrome {
      anchors.fill: parent
      visible: pane.bar.rice !== null && !pane.ricePills
    }

    Grid {
      id: marks
      anchors.centerIn: parent
      columns: pane.barVertical ? 1 : 64
      spacing: Math.max(1, Math.round((pane.ricePills ? 3 : 6) * pane.barScale))
      Repeater {
        model: section.widgetIds
        delegate: Mark {
          required property string modelData
          widgetId: modelData
        }
      }
    }
  }

  Row {
    id: headingRow
    anchors.top: parent.top
    anchors.left: parent.left
    visible: !pane.compact
    spacing: Style.space(8)

    Text {
      id: heading
      text: "PREVIEW"
      textFormat: Text.PlainText
      color: pane.forge.faint
      font.family: pane.forge.uiFont
      font.pixelSize: Style.font.caption
      font.letterSpacing: 2
      font.bold: true
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "click anything to edit its colour"
      textFormat: Text.PlainText
      color: pane.forge.faint
      font.family: pane.forge.uiFont
      font.pixelSize: Style.font.caption
    }
  }

  // ------------------------------------------------------------ the desktop

  Rectangle {
    id: screen
    anchors.top: pane.compact ? parent.top : headingRow.bottom
    anchors.topMargin: pane.compact ? 0 : Style.spacing.lg
    anchors.left: parent.left
    anchors.right: parent.right
    // Its natural proportion, or whatever is left once the blocks above and
    // below have taken theirs -- whichever is smaller. Tiled beside another
    // window there is often less room than the proportion would like.
    height: Math.max(Style.space(120),
                     Math.min(Math.round(width * 0.58),
                              parent.height - (pane.compact ? 0 : headingRow.height + Style.spacing.lg)
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

        // The gradient runs darker_background into background top to bottom,
        // so the half you are over is the key you get.
        Hotspot {
          forge: pane.forge
          keyAt: function (mx, my) { return my < height / 2 ? "darker_background" : "background" }
        }
      }

      Rectangle {
        anchors.fill: parent
        visible: forge.previewImage === ""
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop { position: 1.0; color: pane.withAlpha(pane.colors.accent, 0.16) }
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

      // --- the inactive window -------------------------------------------

      MockWindow {
        forge: pane.forge
        active: false
        x: pane.deskX + Math.round(pane.deskW * 0.46)
        y: pane.deskY + Math.round(pane.deskH * 0.12)
        width: Math.round(pane.deskW * 0.48)
        height: Math.round(pane.deskH * 0.60)
        title: "derive.js"

        Column {
          anchors.fill: parent
          anchors.margins: Style.space(7)
          spacing: Style.space(2)

          Repeater {
            model: pane.codeLines
            delegate: Text {
              id: codeLine
              required property var modelData
              readonly property string key: modelData.role === "comment" ? "dark_foreground"
                                          : modelData.role === "keyword" ? "magenta"
                                          : modelData.role === "call" ? "blue"
                                          : "foreground"
              text: modelData.text
              textFormat: Text.PlainText
              elide: Text.ElideRight
              width: parent.width
              color: pane.colors[key]
              font.family: forge.monoFont
              font.pixelSize: Math.max(6, Math.round(screen.height * 0.030))
              Hotspot { forge: pane.forge; key: codeLine.key }
            }
          }
        }
      }

      // --- the active window ---------------------------------------------

      MockWindow {
        forge: pane.forge
        active: true
        x: pane.deskX + Math.round(pane.deskW * 0.07)
        y: pane.deskY + Math.round(pane.deskH * 0.17)
        width: Math.round(pane.deskW * 0.57)
        height: Math.round(pane.deskH * 0.70)
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
            Repeater {
              model: [
                { text: "~/themes", key: "cyan" },
                { text: ">", key: "green" },
                { text: "omarchy theme list", key: "bright_foreground" }
              ]
              delegate: Text {
                id: promptPart
                required property var modelData
                text: modelData.text
                textFormat: Text.PlainText
                color: pane.colors[modelData.key]
                font.family: forge.monoFont
                font.pixelSize: term.cell
                Hotspot { forge: pane.forge; key: promptPart.modelData.key }
              }
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
            Hotspot { forge: pane.forge; key: "foreground" }
          }

          Text {
            text: "# a comment, deliberately quieter"
            textFormat: Text.PlainText
            elide: Text.ElideRight
            width: parent.width
            color: pane.colors.dark_foreground
            font.family: forge.monoFont
            font.pixelSize: term.cell
            Hotspot { forge: pane.forge; key: "dark_foreground" }
          }

          Row {
            spacing: Style.space(8)
            Repeater {
              model: [
                { text: "error", key: "red" },
                { text: "warning", key: "yellow" },
                { text: "ok", key: "green" },
                { text: "link", key: "blue" }
              ]
              delegate: Text {
                id: statusWord
                required property var modelData
                text: modelData.text
                textFormat: Text.PlainText
                color: pane.colors[modelData.key]
                font.family: forge.monoFont
                font.pixelSize: term.cell
                Hotspot { forge: pane.forge; key: statusWord.modelData.key }
              }
            }
          }

          // A selected row, drawn the way the shell's menu draws one:
          // foreground at 8%, with accent text.
          Rectangle {
            width: parent.width
            height: term.cell + Style.space(5)
            radius: 2
            color: pane.withAlpha(pane.colors.foreground, 0.08)
            Hotspot { forge: pane.forge; key: "foreground" }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: Style.space(4)
              text: "selected row"
              textFormat: Text.PlainText
              color: pane.colors.accent
              font.family: forge.monoFont
              font.pixelSize: term.cell
              Hotspot { forge: pane.forge; key: "accent" }
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
                id: lsEntry
                required property var modelData
                text: modelData.name
                textFormat: Text.PlainText
                color: pane.colors[modelData.key]
                font.family: forge.monoFont
                font.pixelSize: term.cell
                font.bold: modelData.key === "green"
                Hotspot { forge: pane.forge; key: lsEntry.modelData.key }
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
                id: ansiCell
                required property string modelData
                width: term.cell * 1.1
                height: term.cell * 1.1
                color: pane.colors[modelData]
                Hotspot { forge: pane.forge; key: ansiCell.modelData }
              }
            }
          }
        }
      }

      // --- the bar -------------------------------------------------------
      //
      // Drawn last so it sits over the windows the way a real bar does, on
      // whichever edge the user keeps theirs. shell.toml.tpl maps
      // bar.background to `background`, bar.text to `foreground`, and
      // bar.active -- the colour a module uses when it wants attention -- to
      // `red`. A see-through bar (or Rice Bar, which makes the stock bar
      // see-through and paints beneath it) has no ground of its own.

      Item {
        id: mockBar
        x: pane.barPosition === "right" ? screen.width - pane.barThickness : 0
        y: pane.barPosition === "bottom" ? screen.height - pane.barThickness : 0
        width: pane.barVertical ? pane.barThickness : screen.width
        height: pane.barVertical ? screen.height : pane.barThickness

        readonly property int edgePad: Math.max(2, Math.round(6 * pane.barScale))

        Rectangle {
          anchors.fill: parent
          visible: pane.bar.transparent !== true
          color: pane.colors.background
          Hotspot { forge: pane.forge; key: "background" }
        }

        // Rail: one continuous line along the inner edge, under the sections.
        Rectangle {
          visible: pane.riceDecoration === "rail"
          color: pane.colors.accent
          x: pane.barPosition === "left" ? parent.width - 1 : 0
          y: pane.barPosition === "top" ? parent.height - 1 : 0
          width: pane.barVertical ? 1 : parent.width
          height: pane.barVertical ? parent.height : 1
        }

        Section {
          widgetIds: pane.bar.widgets.left
          x: pane.barVertical ? 0 : mockBar.edgePad
          y: pane.barVertical ? mockBar.edgePad : 0
        }

        Section {
          id: centerSection
          widgetIds: pane.bar.widgets.center
          x: pane.barVertical ? 0 : Math.round((mockBar.width - width) / 2)
          y: pane.barVertical ? Math.round((mockBar.height - height) / 2) : 0
        }

        Section {
          widgetIds: pane.bar.widgets.right
          x: pane.barVertical ? 0 : mockBar.width - width - mockBar.edgePad
          y: pane.barVertical ? mockBar.height - height - mockBar.edgePad : 0
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
          id: pair
          required property string modelData
          // brown has no bright partner in the colors.toml schema, so the slot
          // below it shows the ground instead of inventing one.
          readonly property string brightKey: pane.colors["bright_" + modelData] !== undefined
            ? "bright_" + modelData : "lighter_background"
          width: (pane.width - Style.space(3) * 7) / 8
          spacing: Style.space(2)

          Rectangle {
            width: parent.width
            height: Style.space(18)
            radius: 2
            color: pane.colors[pair.modelData]
            Hotspot { forge: pane.forge; key: pair.modelData }
          }

          Rectangle {
            width: parent.width
            height: Style.space(18)
            radius: 2
            color: pane.colors[pair.brightKey]
            Hotspot { forge: pane.forge; key: pair.brightKey }
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
        return "Outside the band: " + bad.join(", ") + ". Roll again, or unlock them and let the solver place them."
      }
    }
  }

  // ---------------------------------------------------- the hover outline
  //
  // One outline and one label for the whole pane rather than one per Hotspot:
  // the screen and every mock window clip their children, and a label drawn
  // inside a clipped terminal would be cut off at its edge. Measured in the
  // pane's own coordinates, so it can sit over a clip boundary.
  Item {
    id: hoverRing
    anchors.fill: parent
    visible: pane.forge.hoverItem !== null && pane.forge.hoverKey !== ""
    z: 30

    readonly property rect box: {
      var tick = pane.forge.hoverTick
      var item = pane.forge.hoverItem
      if (!item || tick < 0) return Qt.rect(0, 0, 0, 0)
      return pane.mapFromItem(item, 0, 0, item.width, item.height)
    }
    readonly property string hex: Palette.normHex(pane.colors[pane.forge.hoverKey]) || ""

    // Two rings, dark then light, so the outline reads on any colour at all.
    Rectangle {
      x: hoverRing.box.x - 3
      y: hoverRing.box.y - 3
      width: hoverRing.box.width + 6
      height: hoverRing.box.height + 6
      radius: 3
      color: "transparent"
      border.width: 1
      border.color: Qt.rgba(0, 0, 0, 0.7)
    }

    Rectangle {
      x: hoverRing.box.x - 2
      y: hoverRing.box.y - 2
      width: hoverRing.box.width + 4
      height: hoverRing.box.height + 4
      radius: 2
      color: "transparent"
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.9)
    }

    // The name, below the element or above it when there is no room below,
    // and never past the pane's edges.
    Rectangle {
      id: tag
      readonly property bool below: hoverRing.box.y + hoverRing.box.height + height + Style.space(8) < pane.height
      x: Math.max(0, Math.min(pane.width - width, hoverRing.box.x))
      y: below ? hoverRing.box.y + hoverRing.box.height + Style.space(6)
               : hoverRing.box.y - height - Style.space(6)
      width: tagRow.implicitWidth + Style.space(12)
      height: tagRow.implicitHeight + Style.space(6)
      radius: Style.space(4)
      color: pane.forge.surface
      border.width: 1
      border.color: pane.forge.hairline

      Row {
        id: tagRow
        anchors.centerIn: parent
        spacing: Style.space(6)

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(9)
          height: Style.space(9)
          radius: 2
          color: hoverRing.hex === "" ? "transparent" : hoverRing.hex
          border.width: 1
          border.color: pane.forge.hairline
        }

        Text {
          text: pane.forge.hoverKey
          textFormat: Text.PlainText
          color: pane.forge.ink
          font.family: pane.forge.monoFont
          font.pixelSize: Style.font.caption
        }

        Text {
          text: hoverRing.hex
          textFormat: Text.PlainText
          color: pane.forge.dim
          font.family: pane.forge.monoFont
          font.pixelSize: Style.font.caption
        }

        Text {
          text: pane.forge.isPinned(pane.forge.hoverKey)
            ? "locked \u00b7 right-click to unlock"
            : "click to edit \u00b7 right-click to lock"
          textFormat: Text.PlainText
          color: pane.forge.faint
          font.family: pane.forge.uiFont
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
