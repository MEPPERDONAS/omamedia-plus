import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Ui
import qs.Commons
import QtQuick.Effects

BarWidget {
  id: root
  moduleName: "famas.media-plus"

  readonly property var mediaService: bar?.shell?.firstPartyServiceFor("famas.media-plus")
  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  readonly property var sourcePlayers: mediaService ? mediaService.sourcePlayers : []

  readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property string playIcon: activePlayer && activePlayer.isPlaying ? "󰏤" : "󰐊"
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""

  property bool popupOpen: false

  // ------------------------------------------------------- audio source
  //
  // The app that currently produces audio (player, browser, ...): used by the
  // source badge in the popup's top-right corner. Clicking the badge focuses
  // that app's window.

  readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []

  readonly property var playbackStreams: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isStream && isPlaybackStream(n) && n.audio) list.push(n)
    }
    return list
  }

  // Source descriptor: { kind, app, label, icon, playing } or null.
  // Follows the media service's active player selection (the same player the
  // source list highlights and the card shows), so the badge never disagrees
  // with the selected source — paused players included. PipeWire streams are
  // only a fallback when no MPRIS player exists at all.
  readonly property var source: {
    var player = mediaService && mediaService.activePlayer && playerHasMetadata(mediaService.activePlayer)
      ? mediaService.activePlayer : null
    var fallback = null
    if (!player) {
      for (var i = 0; i < mprisPlayers.length; i++) {
        var p = mprisPlayers[i]
        if (!p || !p.isPlaying || !playerHasMetadata(p) || isProxyPlayer(p)) continue
        fallback = p
        break
      }
    }

    if (player || fallback) {
      var chosen = player || fallback
      var app = playerAppName(chosen)
      var label = playerLabel(chosen)
      return {
        kind: "player",
        app: app,
        label: label || app || "Player",
        icon: resolveIcon(iconCandidates(app, label)),
        playing: player ? !!player.isPlaying : true
      }
    }

    if (playbackStreams.length > 0) {
      var stream = playbackStreams[0]
      var sLabel = streamLabel(stream)
      var sApp = String(nodeProps(stream)["application.name"] || sLabel)
      return {
        kind: "stream",
        app: sApp,
        label: sLabel || "Audio",
        icon: resolveIcon(iconCandidates(sApp, sLabel)),
        playing: true
      }
    }

    return null
  }

  readonly property bool hasSource: source !== null
  readonly property bool sourcePlaying: source ? source.playing : false

  function isProxyPlayer(player) {
    var dbusName = String(player && player.dbusName || "").toLowerCase()
    var desktopEntry = String(player && player.desktopEntry || "").toLowerCase()
    return dbusName.indexOf("playerctld") !== -1 || desktopEntry === "playerctld"
  }

  function playerHasMetadata(player) {
    return !!(player && (player.trackTitle || player.trackArtist || player.identity || player.desktopEntry))
  }

  function playerAppName(player) {
    return player ? (player.desktopEntry || player.identity || "") : ""
  }

  function playerLabel(player) {
    return player ? (player.identity || player.desktopEntry || "") : ""
  }

  function isPlaybackStream(node) {
    if (!node || !node.isStream) return false
    if (node.isSink === true) return true
    var mediaClass = String(node.type || "")
    return mediaClass.indexOf("Stream/Output/Audio") !== -1
      || mediaClass.indexOf("AudioOutStream") !== -1
      || mediaClass.indexOf("Output") !== -1
  }

  function nodeProps(node) {
    return node && node.ready && node.properties ? node.properties : {}
  }

  function streamLabel(node) {
    if (!node) return ""
    var p = nodeProps(node)
    return p["application.name"]
      || node.description
      || p["media.name"]
      || p["node.name"]
      || node.name
      || ""
  }

  function iconAliases(name) {
    var aliases = {
      "spotify": ["spotify-client"],
      "chrome": ["google-chrome"],
      "google-chrome": ["chrome"],
      "chromium": ["chromium-browser"],
      "firefox": ["firefox-esr"],
      "youtube music": ["youtube-music"],
      "youtube-music": ["youtube-music"]
    }
    return aliases[String(name || "").trim().toLowerCase()] || []
  }

  function iconCandidates(appName, label) {
    var names = []
    var seen = {}
    function push(value) {
      var v = String(value || "").trim().toLowerCase()
      if (!v || seen[v]) return
      seen[v] = true
      names.push(v)
    }
    push(appName)
    push(label)
    var extra = iconAliases(appName)
    for (var i = 0; i < extra.length; i++) push(extra[i])
    return names
  }

  function resolveIcon(names) {
    for (var i = 0; i < names.length; i++) {
      var path = Quickshell.iconPath(names[i], true)
      if (!path || path.length === 0) continue
      if (path.indexOf("file://") === 0 || path.indexOf("image://") === 0) return path
      if (path.charAt(0) === "/") return Util.fileUrl(path)
      return path
    }
    return ""
  }

  function focusSource() {
    var s = source
    if (!s || !s.app) return
    Quickshell.execDetached([
      Quickshell.env("OMARCHY_PATH") + "/bin/omarchy-hyprland-focus-app",
      s.app
    ])
  }

  function close() { popupOpen = false }
  property real maxLabelWidth: 180

  Timer {
    running: root.activePlayer && root.activePlayer.isPlaying
    interval: 1000
    repeat: true
    onTriggered: if (root.activePlayer) root.activePlayer.positionChanged()
  }

  visible: hasMedia
  implicitWidth: hasMedia ? row.implicitWidth + Style.space(14) : 0
  implicitHeight: barSize

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    Text {
      id: glyph
      anchors.verticalCenter: parent.verticalCenter
      text: root.playIcon
      color: activePlayer && activePlayer.isPlaying ? root.bar.barForeground : Qt.darker(root.bar.barForeground, 1.5)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      Behavior on color {
        enabled: !root.bar || root.bar.foregroundAnimationEnabled
        ColorAnimation { duration: 160 }
      }
    }

    Item {
      id: scrollClip
      width: Math.min(root.maxLabelWidth, labelText.implicitWidth)
      height: glyph.height
      clip: true
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.bar.vertical && root.title !== ""

      Text {
        id: labelText
        text: root.title + (root.artist ? " · " + root.artist : "")
        color: root.bar.barForeground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter

        property bool needsScroll: implicitWidth > scrollClip.width

        NumberAnimation on x {
          id: scrollAnim
          running: labelText.needsScroll && !root.popupOpen && !root.bar.vertical
          loops: Animation.Infinite
          duration: Math.max(6000, labelText.implicitWidth * 25)
          from: scrollClip.width
          to: -labelText.implicitWidth
          easing.type: Easing.Linear
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.activePlayer ? Qt.PointingHandCursor : Qt.ArrowCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: function(mouse) {
      if (!root.activePlayer) return
      if (mouse.button === Qt.MiddleButton) {
        if (root.mediaService) root.mediaService.runAction("next", false)
      } else if (mouse.button === Qt.RightButton) {
        root.popupOpen = !root.popupOpen
      } else {
        if (root.mediaService) root.mediaService.runAction("playPause", false)
      }
    }
    onWheel: function(wheel) {
      if (!root.activePlayer) return
      if (wheel.angleDelta.y > 0 && root.mediaService) root.mediaService.runAction("previous", false)
      else if (wheel.angleDelta.y < 0 && root.mediaService) root.mediaService.runAction("next", false)
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, root.hasMedia ? (root.title + (root.artist ? " — " + root.artist : "")) : "")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(320))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(10)

      Item {
        id: bgContainer
        width: parent.width
        height: bgColumn.implicitHeight + Style.space(20)

        Item {
          id: bgSource
          anchors.fill: parent
          visible: false
          layer.enabled: true
          layer.smooth: true

          Image {
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            source: root.activePlayer && root.activePlayer.trackArtUrl ? root.activePlayer.trackArtUrl : ""
            visible: source !== ""
          }

          Text {
            anchors.centerIn: parent
            text: "󰝚"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
            opacity: 0.3
            visible: !root.activePlayer || !root.activePlayer.trackArtUrl
          }

          Rectangle {
            anchors.fill: parent
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.55) }
              GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.25) }
            }
          }

        }

        Item {
          id: bgMask
          anchors.fill: parent
          visible: false
          layer.enabled: true
          layer.smooth: true

          Rectangle {
            anchors.fill: parent
            radius: 9
            color: "white"
          }
        }

        MultiEffect {
          anchors.fill: parent
          source: bgSource
          maskEnabled: true
          maskSource: bgMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 1.0
        }

        Column {
          id: bgColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(10)
          spacing: Style.space(8)

          Column {
            spacing: Style.space(8)
            width: parent.width

            Column {
              spacing: Style.space(4)
              width: parent.width - sourceBadge.width - Style.space(12)

              Text {
                text: root.title || "Nothing playing"
                color: "white"
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft
                width: parent.width
              }

              Text {
                text: root.artist
                color: "#cccccc"
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft
                width: parent.width
                visible: text !== ""
              }

              Text {
                text: root.activePlayer && root.activePlayer.trackAlbum ? root.activePlayer.trackAlbum : ""
                color: "#cccccc"
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft
                width: parent.width
                visible: text !== ""
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: root.activePlayer && root.activePlayer.length > 0
            topPadding: Style.space(6)

            Rectangle {
              width: parent.width
              height: 3
              radius: 2
              color: "#33ffffff"

              Rectangle {
                width: root.activePlayer && root.activePlayer.length > 0
                  ? parent.width * (root.activePlayer.position / root.activePlayer.length)
                  : 0
                height: parent.height
                radius: 2
                color: "white"
              }
            }
          }

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(6)

            Button {
              iconText: "󰒮"
              foreground: "white"
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              enabled: root.activePlayer && root.activePlayer.canGoPrevious
              opacity: enabled ? 1.0 : 0.4
              onClicked: if (root.mediaService) root.mediaService.runAction("previous", false, root.mediaService.playerKey(root.activePlayer))
            }

            Button {
              iconText: root.activePlayer && root.activePlayer.isPlaying ? "󰏤" : "󰐊"
              foreground: "white"
              horizontalPadding: Style.spacing.panelGap
              verticalPadding: Style.spacing.controlPaddingY
              iconSize: Style.font.iconLarge
              enabled: root.activePlayer && (root.activePlayer.canTogglePlaying || root.activePlayer.canPlay || root.activePlayer.canPause)
              opacity: enabled ? 1.0 : 0.4
              onClicked: if (root.mediaService) root.mediaService.runAction("playPause", false, root.mediaService.playerKey(root.activePlayer))
            }

            Button {
              iconText: "󰒭"
              foreground: "white"
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              enabled: root.activePlayer && root.activePlayer.canGoNext
              opacity: enabled ? 1.0 : 0.4
              onClicked: if (root.mediaService) root.mediaService.runAction("next", false, root.mediaService.playerKey(root.activePlayer))
            }
          }
        }

        // Source badge — pill with the audio source's name in the card's
        // top-right corner. Clicking it focuses the source app's window.
        Item {
          id: sourceBadge
          property bool hovered: false
          width: Math.min(Style.space(104), badgeContent.implicitWidth + Style.space(14))
          height: Style.space(26)
          anchors.top: parent.top
          anchors.right: parent.right
          anchors.margins: Style.space(8)
          visible: root.hasSource

          Rectangle {
            anchors.fill: parent
            radius: Style.spacing.labelGap
            color: sourceBadge.hovered ? Qt.rgba(0, 0, 0, 0.35) : Qt.rgba(0, 0, 0, 0)
            // border.color: Qt.rgba(1, 1, 1, 0.18)
            // border.width: 1
            Behavior on color { ColorAnimation { duration: 120 } }
          }

          Row {
            id: badgeContent
            anchors.centerIn: parent
            spacing: Style.space(5)

            Loader {
              id: sourceIcon
              active: root.hasSource && root.source.icon !== ""
              width: Math.round(Style.font.caption * 1.3)
              height: Math.round(Style.font.caption * 1.3)
              anchors.verticalCenter: parent.verticalCenter
              sourceComponent: Image {
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: root.source.icon
                asynchronous: true
                smooth: true
              }
            }

            Text {
              id: badgeText
              text: root.source ? root.source.label : ""
              color: "white"
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 0.4
              elide: Text.ElideRight
              width: Math.min(implicitWidth, Style.space(72))
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: sourceBadge.hovered = containsMouse
            onClicked: root.focusSource()
            onEntered: if (root.bar && root.source) root.bar.showTooltip(root, root.source.label + " · click to focus")
            onExited: if (root.bar) root.bar.hideTooltip(root)
          }
        }
      }

      PanelSeparator {
        visible: root.sourcePlayers.length > 1
        foreground: root.bar.foreground
      }

      Column {
        id: sourceList
        visible: root.sourcePlayers.length > 1
        width: parent.width
        spacing: Style.space(4)

        Repeater {
          model: root.sourcePlayers

          BorderSurface {
            id: sourceRow
            required property var modelData

            readonly property var player: modelData
            readonly property bool selected: root.activePlayer && player
              && root.mediaService.playerKey(root.activePlayer) === root.mediaService.playerKey(player)
            readonly property string sourceTitle: player ? (player.trackTitle || player.identity || player.desktopEntry || "Media source") : "Media source"
            readonly property string sourceDetail: player && player.trackArtist ? player.trackArtist : (player && player.identity ? player.identity : "")

            width: sourceList.width
            height: sourceInner.implicitHeight + Style.space(10)
            radius: Style.spacing.labelGap
            color: selected ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "transparent"
            borderSpec: selected ? Border.controlSpec("normal", root.bar.foreground, Color.accent) : Border.none()

            Row {
              id: sourceInner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: sourceRow.borderLeft + Style.space(8)
              anchors.rightMargin: sourceRow.borderRight + Style.space(8)
              spacing: Style.space(8)

              Text {
                text: sourceRow.player && sourceRow.player.isPlaying ? "󰏤" : "󰐊"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                width: Style.space(18)
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                width: parent.width - Style.space(26)
                spacing: Style.space(1)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  text: sourceRow.sourceTitle
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: sourceRow.selected
                  elide: Text.ElideRight
                  width: parent.width
                }

                Text {
                  text: sourceRow.sourceDetail
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: parent.width
                  visible: text !== ""
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.mediaService) root.mediaService.selectPlayer(root.mediaService.playerKey(sourceRow.player))
            }
          }
        }
      }
    }
  }
}
