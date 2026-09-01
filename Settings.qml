pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

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
