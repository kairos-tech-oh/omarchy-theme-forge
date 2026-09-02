pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "BarStyle.js" as BarStyle

// Theme Forge's own settings — how the tool behaves, not what a theme looks
// like.
//
// It replaces the body rather than floating over it. A panel that dims the
// editor to show four rows would imply the editor is still the subject; it is
// not, and there is nothing here to compare against what is underneath.
//
// Everything on this page is a preference the panel persists to prefs.json,
// which is deliberately a different file from the palette draft: a draft is
// work in progress and gets cleared, while "I have already seen the tour" has
// to survive that.
Item {
  id: settings

  required property var forge

  signal closed()
  signal replayTutorial()

  Flickable {
    id: page
    anchors.fill: parent
    contentWidth: width
    contentHeight: column.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: column
      // Measured against the Flickable itself, not `parent`. A Flickable's
      // children are parented to its contentItem, whose width is not the
      // Flickable's -- reading it here gave the column a width nothing wrapped
      // against, and every paragraph ran off the right edge.
      width: Math.min(Style.space(620), page.width)
      x: Math.round((page.width - width) / 2)
      spacing: Style.spacing.lg

      Item { width: 1; height: Style.space(4) }

      Text {
        text: "SETTINGS"
        textFormat: Text.PlainText
        color: settings.forge.faint
        font.family: settings.forge.uiFont
        font.pixelSize: Style.font.caption
        font.letterSpacing: 2
        font.bold: true
      }

      // ------------------------------------------------------------ the tour

      SettingsGroup {
        width: parent.width
        forge: settings.forge
        title: "Getting started"

        Toggle {
          width: parent.width
          label: "Show the tour when Theme Forge opens"
          description: settings.forge.showTutorialOnOpen
            ? "It will run the next time you open this window."
            : "It runs once, the first time. Turn this on to see it again."
          checked: settings.forge.showTutorialOnOpen
          foreground: settings.forge.ink
          accent: settings.forge.colors.accent
          fontFamily: settings.forge.uiFont
          onClicked: settings.forge.setPref("showTutorialOnOpen", !settings.forge.showTutorialOnOpen)
        }

        Row {
          spacing: Style.spacing.controlGap

          RiceButton {
            text: "Take the tour now"
            foreground: settings.forge.ink
            tint: settings.forge.surface
            tooltipText: "Run it straight away, without waiting for the next open"
            onClicked: settings.replayTutorial()
          }
        }
      }

      // ---------------------------------------------------------- the window

      SettingsGroup {
        width: parent.width
        forge: settings.forge
        title: "This window"

        SliderRow {
          width: parent.width
          forge: settings.forge
          label: "TRANSLUCENCY"
          value: Math.round((1 - settings.forge.surfaceAlpha) * 100)
          minimum: 0
          maximum: 40
          readout: Math.round((1 - settings.forge.surfaceAlpha) * 100) + "%"
          hint: "How much of your wallpaper reads through the window. The preview and "
              + "every swatch stay fully opaque either way, so the colours you are "
              + "judging are never tinted by what is behind the window."
          onMovedTo: function (v) {
            settings.forge.setPref("surfaceAlpha", Math.round((1 - v / 100) * 100) / 100)
          }
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Hyprland applies its own window opacity on top of this — 0.985 focused, "
              + "0.96 unfocused by default — so 0% here is not perfectly opaque."
          textFormat: Text.PlainText
          color: settings.forge.faint
          font.family: settings.forge.uiFont
          font.pixelSize: Style.font.caption
        }
      }

      // ------------------------------------------------------------- rolling

      SettingsGroup {
        width: parent.width
        forge: settings.forge
        title: "Rolling"

        Toggle {
          width: parent.width
          label: "True random roll"
          description: settings.forge.trueRandom
            ? "Every one of the twenty-six is drawn from the whole colour cube, "
              + "with no contrast solving and no relation between them."
            : "Off: every roll is solved for readable contrast, and the sixteen "
              + "terminal colours keep their names. Turn on for pure chance."
          checked: settings.forge.trueRandom
          foreground: settings.forge.ink
          accent: settings.forge.colors.yellow
          fontFamily: settings.forge.uiFont
          onClicked: settings.forge.setPref("trueRandom", !settings.forge.trueRandom)
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "\u26a0 With this on, nothing keeps a roll readable. Text can vanish into "
              + "the ground, the sixteen can land on top of each other, and a red can come "
              + "out green. The grid and the footer still report every colour that is "
              + "outside its band, but nothing stops one from being saved or applied. "
              + "Locked colours are left alone either way."
          textFormat: Text.PlainText
          color: settings.forge.colors.yellow
          font.family: settings.forge.uiFont
          font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Any of the twenty-six can be locked so a roll leaves it alone: the dot "
              + "beside it in the grid, the lock button above the sliders, or a right-click "
              + "on anything in the preview."
          textFormat: Text.PlainText
          color: settings.forge.faint
          font.family: settings.forge.uiFont
          font.pixelSize: Style.font.caption
        }
      }

      // ------------------------------------------------------------ the preview

      SettingsGroup {
        width: parent.width
        forge: settings.forge
        title: "The preview"

        Toggle {
          width: parent.width
          label: "Draw the bar the way mine is set up"
          description: settings.forge.mirrorBar
            ? "Yours right now: " + BarStyle.describe(settings.forge.ownBar) + ". "
              + "Which edge, see-through or solid, and Rice Bar's preset if you use it, "
              + "read from the shell as it changes."
            : "Showing the stock Omarchy bar instead \u2014 what someone without your "
              + "bar settings would see. Yours is " + BarStyle.describe(settings.forge.ownBar) + "."
          checked: settings.forge.mirrorBar
          foreground: settings.forge.ink
          accent: settings.forge.colors.accent
          fontFamily: settings.forge.uiFont
          onClicked: settings.forge.setPref("mirrorBar", !settings.forge.mirrorBar)
        }

        Row {
          width: parent.width
          spacing: Style.spacing.sm

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "WIDGET SIZE"
            textFormat: Text.PlainText
            color: settings.forge.faint
            font.family: settings.forge.uiFont
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
          }

          Repeater {
            model: [
              { label: "\u00bd\u00d7", value: 0.5 },
              { label: "\u00be\u00d7", value: 0.75 },
              { label: "1\u00d7", value: 1 }
            ]
            delegate: RiceButton {
              required property var modelData
              text: modelData.label
              fontSize: Style.font.caption
              verticalPadding: Style.space(2)
              horizontalPadding: Style.space(6)
              selected: settings.forge.barDensity === modelData.value
              foreground: selected ? settings.forge.colors.accent : settings.forge.dim
              accent: settings.forge.colors.accent
              tint: settings.forge.surface
              fillAlpha: settings.forge.surfaceAlpha
              onClicked: settings.forge.setPref("barDensity", modelData.value)
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "how large the bar's widgets are drawn; 1\u00d7 is true to scale"
            textFormat: Text.PlainText
            color: settings.forge.faint
            font.family: settings.forge.uiFont
            font.pixelSize: Style.font.caption
          }
        }
      }

      // ---------------------------------------------------------- where things are

      SettingsGroup {
        width: parent.width
        forge: settings.forge
        title: "Where things are"

        Repeater {
          model: [
            { label: "Themes you make", path: "~/.config/omarchy/themes/<name>/" },
            { label: "Preferences", path: "~/.local/state/kairos.theme-forge/prefs.json" },
            { label: "Work in progress", path: "~/.local/state/kairos.theme-forge/draft.json" },
            { label: "The plugin", path: "~/.config/omarchy/plugins/kairos.theme-forge/" }
          ]
          delegate: Item {
            required property var modelData
            width: column.width
            height: Math.max(pathLabel.implicitHeight, pathValue.implicitHeight)

            Text {
              id: pathLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(150)
              text: modelData.label
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: settings.forge.dim
              font.family: settings.forge.uiFont
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              id: pathValue
              anchors.left: pathLabel.right
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.path
              textFormat: Text.PlainText
              elide: Text.ElideMiddle
              color: settings.forge.faint
              font.family: settings.forge.monoFont
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      Item { width: 1; height: Style.space(4) }

      RiceButton {
        text: "Back to designing"
        foreground: settings.forge.colors.accent
        accent: settings.forge.colors.accent
        selected: true
        tint: settings.forge.surface
        onClicked: settings.closed()
      }

      Item { width: 1; height: Style.space(8) }
    }
  }
}
