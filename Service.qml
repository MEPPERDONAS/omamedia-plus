import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "MediaModel.js" as MediaModel

Item {
  id: root

  property var shell: null
  property string preferredPlayerKey: ""
  property var playerStartedAt: ({})
  property var pendingTrackOsd: null
  property int playSerial: 0

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var links: Pipewire.links ? Pipewire.links.values : []
  readonly property var playbackStreams: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isStream && isPlaybackStream(n) && n.audio) list.push(n)
    }
    return list
  }
  readonly property var sinks: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isSink && !n.isStream && n.audio && list.indexOf(n) < 0) list.push(n)
    }
    var defaultSink = Pipewire.defaultAudioSink
    if (defaultSink && list.indexOf(defaultSink) < 0) list.unshift(defaultSink)
    return list
  }
  readonly property var sourcePlayers: orderedSourcePlayers()
  readonly property var sourceCyclePlayers: orderedCycleSourcePlayers()
  readonly property var activePlayer: selectActivePlayer()
  readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
  readonly property string album: activePlayer && activePlayer.trackAlbum ? activePlayer.trackAlbum : ""
  readonly property string artUrl: activePlayer && activePlayer.trackArtUrl ? activePlayer.trackArtUrl : ""
  readonly property string identity: activePlayer ? (activePlayer.identity || activePlayer.desktopEntry || "") : ""

  function isProxyPlayer(player) {
    return MediaModel.isProxyPlayer(player)
  }

  function hasMetadata(player) {
    return MediaModel.hasMetadata(player)
  }

  function hasTrackMetadata(player) {
    return MediaModel.hasTrackMetadata(player)
  }

  function playerCanControl(player) {
    return MediaModel.playerCanControl(player)
  }

  function canHandleAction(player, action) {
    return MediaModel.canHandleAction(player, action)
  }

  function nextLoopState(loopState) {
    return MediaModel.nextLoopState(loopState)
  }

  function loopLabel(loopState) {
    return MediaModel.loopLabel(loopState)
  }

  function canCycleSource(player) {
    return MediaModel.canCycleSource(player)
  }

  function nodeProps(node) {
    return MediaModel.nodeProps(node)
  }

  function isPlaybackStream(node) {
    return MediaModel.isPlaybackStream(node)
  }

  function streamLabelKey(label) {
    return MediaModel.streamLabelKey(label)
  }

  function rawStreamLabel(node) {
    return MediaModel.rawStreamLabel(node)
  }

  function playerAppLabel(player) {
    return MediaModel.playerAppLabel(player)
  }

  function playerHasPlaybackStream(player) {
    return MediaModel.playerHasPlaybackStream(player, playbackStreams)
  }

  function sinkLabel(node) {
    return MediaModel.sinkLabel(node)
  }

  function sinkGlyph(node) {
    return MediaModel.sinkGlyph(node)
  }

  // All PipeWire playback streams that represent the given MPRIS player.
  // Label matching first (e.g. "chromium" for a browser with several tabs);
  // generic streams (Spotify publishes its stream as "audio-src") fall back
  // to the player that no other non-generic stream already represents.
  function playbackStreamsForPlayer(player) {
    var list = []
    var playerKey = MediaModel.streamLabelKey(MediaModel.playerAppLabel(player))
    if (!playerKey) return list

    for (var i = 0; i < playbackStreams.length; i++) {
      var stream = playbackStreams[i]
      var streamKey = MediaModel.streamLabelKey(MediaModel.rawStreamLabel(stream))
      if (!streamKey) continue
      if (streamKey === playerKey
          || streamKey.indexOf(playerKey) !== -1
          || playerKey.indexOf(streamKey) !== -1)
        list.push(stream)
    }
    if (list.length > 0) return list

    var generic = []
    for (var j = 0; j < playbackStreams.length; j++) {
      var key = MediaModel.streamLabelKey(MediaModel.rawStreamLabel(playbackStreams[j]))
      if (key === "audiosrc") generic.push(playbackStreams[j])
    }
    if (generic.length === 0) return list

    var owned = {}
    for (var k = 0; k < players.length; k++) {
      var other = players[k]
      if (MediaModel.playerKey(other) === MediaModel.playerKey(player)) continue
      var otherKey = MediaModel.streamLabelKey(MediaModel.playerAppLabel(other))
      if (!otherKey) continue
      for (var m = 0; m < playbackStreams.length; m++) {
        var streamKey2 = MediaModel.streamLabelKey(MediaModel.rawStreamLabel(playbackStreams[m]))
        if (!streamKey2 || streamKey2 === "audiosrc") continue
        if (streamKey2 === otherKey
            || streamKey2.indexOf(otherKey) !== -1
            || otherKey.indexOf(streamKey2) !== -1)
          owned[otherKey] = true
      }
    }

    return owned[playerKey] ? [] : generic
  }

  // The sink a playback stream is currently routed to, resolved from the
  // active PipeWire link (link.source is the stream, link.target the sink).
  function sinkForStream(stream) {
    if (!stream) return null
    var fallback = null
    for (var i = 0; i < links.length; i++) {
      var link = links[i]
      if (!link || link.source !== stream) continue
      var target = link.target
      if (!target || !target.isSink) continue
      if (link.state === 6) return target
      if (!fallback) fallback = target
    }
    return fallback || Pipewire.defaultAudioSink || null
  }

  function sinkByName(name) {
    if (!name) return null
    for (var i = 0; i < sinks.length; i++)
      if (String(sinks[i].name) === name) return sinks[i]
    return null
  }

  function playerKey(player) {
    return MediaModel.playerKey(player)
  }

  function playerForKey(key) {
    if (!key) return null
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (playerKey(p) === key) return p
    }
    return null
  }

  function playerOrder(player, fallback) {
    var key = playerKey(player)
    var value = key ? playerStartedAt[key] : undefined
    return value === undefined ? fallback : value
  }

  function syncPlayingOrder() {
    var next = {}
    var alive = {}
    var serial = playSerial

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      var key = playerKey(p)
      if (!key) continue

      alive[key] = true
      if (!p.isPlaying) continue

      if (playerStartedAt[key] === undefined) {
        serial += 1
        next[key] = serial
      } else {
        next[key] = playerStartedAt[key]
      }
    }

    if (preferredPlayerKey && !alive[preferredPlayerKey]) preferredPlayerKey = ""

    playSerial = serial
    playerStartedAt = next
  }

  function orderedSourcePlayers() {
    var list = []
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (hasMetadata(p)) list.push(p)
    }

    list.sort(function(a, b) {
      if (!!a.isPlaying !== !!b.isPlaying) return a.isPlaying ? -1 : 1
      if (isProxyPlayer(a) !== isProxyPlayer(b)) return isProxyPlayer(a) ? 1 : -1
      if (a.isPlaying && b.isPlaying) {
        var orderDelta = playerOrder(a, 1000) - playerOrder(b, 1000)
        if (orderDelta !== 0) return orderDelta
      }
      return labelFor(a).localeCompare(labelFor(b))
    })

    return list
  }

  function orderedCycleSourcePlayers() {
    var list = []
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (canCycleSource(p)) list.push(p)
    }

    list.sort(function(a, b) {
      if (isProxyPlayer(a) !== isProxyPlayer(b)) return isProxyPlayer(a) ? 1 : -1
      return labelFor(a).localeCompare(labelFor(b))
    })

    return list
  }

  function oldestPlayingPlayer(requirePlaybackStream) {
    var oldest = null
    var oldestOrder = 0
    var playingProxy = null
    var proxyOrder = 0

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p) continue

      var proxyPlayer = isProxyPlayer(p)
      if (p.isPlaying) {
        if (requirePlaybackStream && !playerHasPlaybackStream(p)) continue

        var order = playerOrder(p, i + 1000)
        if (!proxyPlayer && (!oldest || order < oldestOrder)) {
          oldest = p
          oldestOrder = order
        } else if (proxyPlayer && (!playingProxy || order < proxyOrder)) {
          playingProxy = p
          proxyOrder = order
        }
      }
    }

    return oldest || playingProxy || null
  }

  function selectActivePlayer() {
    var preferred = null
    var trackPlayer = null
    var trackProxy = null
    var streamPlayer = null
    var streamProxy = null
    var controllablePlayer = null
    var controllableProxy = null
    var identityPlayer = null
    var identityProxy = null

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p) continue

      var proxy = isProxyPlayer(p)

      if (preferredPlayerKey && playerKey(p) === preferredPlayerKey && hasMetadata(p)) preferred = p

      if (playerHasPlaybackStream(p)) {
        if (!proxy && !streamPlayer) streamPlayer = p
        else if (proxy && !streamProxy) streamProxy = p
      } else if (hasTrackMetadata(p)) {
        if (!proxy && !trackPlayer) trackPlayer = p
        else if (proxy && !trackProxy) trackProxy = p
      } else if (playerCanControl(p)) {
        if (!proxy && !controllablePlayer) controllablePlayer = p
        else if (proxy && !controllableProxy) controllableProxy = p
      } else if (hasMetadata(p)) {
        if (!proxy && !identityPlayer) identityPlayer = p
        else if (proxy && !identityProxy) identityProxy = p
      }
    }

    if (preferred && (preferred.isPlaying || hasTrackMetadata(preferred))) return preferred
    var streamCandidate = streamPlayer || streamProxy
    var streamPreferred = preferred && playerHasPlaybackStream(preferred) ? preferred : null
    return oldestPlayingPlayer(true) || oldestPlayingPlayer(false) || streamPreferred || streamCandidate || preferred || trackPlayer || trackProxy || controllablePlayer || controllableProxy || identityPlayer || identityProxy || null
  }

  function labelFor(player) {
    return MediaModel.labelFor(player)
  }

  function osdMessage(player, fallback) {
    return MediaModel.osdMessage(player, fallback)
  }

  function trackSignature(player) {
    return MediaModel.trackSignature(player)
  }

  function showOsd(actionLabel, iconName, player) {
    if (!shell) return
    shell.summon("omarchy.osd", JSON.stringify({
      icon: iconName || "media",
      message: osdMessage(player || activePlayer, actionLabel)
    }))
  }

  function scheduleOsd(actionLabel, iconName, player, waitForTrackChange, beforeTrackSignature) {
    if (waitForTrackChange) {
      pendingTrackOsd = {
        actionLabel: actionLabel,
        iconName: iconName,
        player: player,
        playerKey: playerKey(player),
        before: beforeTrackSignature,
        attempts: 0
      }
      trackOsdTimer.restart()
    } else {
      Qt.callLater(function() { root.showOsd(actionLabel, iconName, player) })
    }
  }

  function flushPendingTrackOsd(force) {
    var pending = pendingTrackOsd
    if (!pending) return

    var player = playerForKey(pending.playerKey) || pending.player
    if (force || MediaModel.trackChanged(pending.before, player) || pending.attempts >= 10) {
      pendingTrackOsd = null
      trackOsdTimer.stop()
      root.showOsd(pending.actionLabel, pending.iconName, player)
      return
    }

    pending.attempts = pending.attempts + 1
    pendingTrackOsd = pending
    trackOsdTimer.restart()
  }

  function selectPlayer(key) {
    var player = playerForKey(key)
    if (!player || !hasMetadata(player)) return false
    preferredPlayerKey = playerKey(player)
    return true
  }

  function playPlayer(player) {
    if (!player) return false
    if (player.canPlay) {
      player.play()
      return true
    }
    return false
  }

  function pausePlayer(player) {
    if (!player) return false
    if (player.canPause) {
      player.pause()
      return true
    }
    if (player.canTogglePlaying && player.isPlaying) {
      player.togglePlaying()
      return true
    }
    return false
  }

  function switchSource(delta, transferPlayback, showFeedback) {
    var list = sourceCyclePlayers
    if (!list || list.length === 0) return false

    var activeKey = playerKey(activePlayer)
    var index = 0
    for (var i = 0; i < list.length; i++) {
      if (playerKey(list[i]) === activeKey) {
        index = i
        break
      }
    }

    index = (index + delta + list.length) % list.length
    var current = activePlayer
    var next = list[index]
    var currentWasPlaying = current && current.isPlaying
    var currentKey = playerKey(current)
    var nextKey = playerKey(next)

    preferredPlayerKey = nextKey

    if (transferPlayback && currentWasPlaying && next && nextKey !== currentKey) {
      var nextWasPlaying = next.isPlaying
      var nextStarted = nextWasPlaying || playPlayer(next)
      if (nextStarted) pausePlayer(current)
    }

    if (showFeedback !== false) Qt.callLater(function() {
      root.showOsd("Source", "media-source", next)
    })

    return true
  }

  // ---- per-source output routing ----

  // A source's output device can only be changed when it actually has a
  // PipeWire playback stream to route; Quickshell's Pipewire service exposes
  // no stream-routing API, so this goes through pipewire-pulse the same way
  // omarchy's own audio panel does.
  property var pendingMove: null

  function moveStreamsToSink(player, sinkName) {
    var sink = sinkByName(String(sinkName || ""))
    var streams = playbackStreamsForPlayer(player)
    if (!sink || !sink.name || streams.length === 0) return false

    var matches = []
    for (var i = 0; i < streams.length; i++) {
      var p = nodeProps(streams[i])
      matches.push({
        pid: String(p["application.process.id"] || ""),
        nodeName: String(p["node.name"] || ""),
        appName: String(p["application.name"] || "")
      })
    }

    pendingMove = { sinkName: sink.name, matches: matches }
    if (!sinkInputsProc.running) sinkInputsProc.running = true

    if (shell) shell.summon("omarchy.osd", JSON.stringify({
      icon: sinkGlyph(sink),
      message: "Output · " + sinkLabel(sink)
    }))
    return true
  }

  function moveSinkInputs(move, text) {
    var lines = String(text || "").split("\n")
    var currentId = ""
    var currentPid = ""
    var currentNode = ""
    var currentApp = ""

    function flush() {
      if (!currentId) return
      for (var i = 0; i < move.matches.length; i++) {
        var m = move.matches[i]
        if ((m.pid && m.pid === currentPid)
            || (m.nodeName && m.nodeName === currentNode)
            || (m.appName && m.appName === currentApp)) {
          Quickshell.execDetached(["pactl", "move-sink-input", currentId, move.sinkName])
          return
        }
      }
    }

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      var idMatch = /^Sink Input #(\d+)/.exec(line)
      if (idMatch) {
        flush()
        currentId = idMatch[1]
        currentPid = ""
        currentNode = ""
        currentApp = ""
        continue
      }
      var pidMatch = /^application\.process\.id = "([^"]*)"/.exec(line)
      if (pidMatch) { currentPid = pidMatch[1]; continue }
      var nodeMatch = /^node\.name = "([^"]*)"/.exec(line)
      if (nodeMatch) { currentNode = nodeMatch[1]; continue }
      var appMatch = /^application\.name = "([^"]*)"/.exec(line)
      if (appMatch) { currentApp = appMatch[1]; continue }
    }
    flush()
  }

  function playerForAction(action, targetKey) {
    var targeted = playerForKey(targetKey)
    if (targeted) return targeted

    if (action === "pause" || action === "playPause") {
      var oldest = oldestPlayingPlayer(true) || oldestPlayingPlayer(false)
      if (oldest) return oldest
    }

    if (canHandleAction(activePlayer, action)) return activePlayer

    var list = sourcePlayers
    for (var i = 0; i < list.length; i++) {
      if (canHandleAction(list[i], action)) return list[i]
    }

    return activePlayer
  }

  function runAction(action, showFeedback, targetKey) {
    var player = playerForAction(action, targetKey)
    var key = playerKey(player)
    var actionLabel = "Play/pause"
    var iconName = "media"
    var beforeTrackSignature = trackSignature(player)
    var handled = false

    if (action === "next") {
      actionLabel = "Next"
      iconName = "media-next"
      if (player && player.canGoNext) {
        player.next()
        handled = true
      }
    } else if (action === "previous") {
      actionLabel = "Previous"
      iconName = "media-previous"
      if (player && player.canGoPrevious) {
        player.previous()
        handled = true
      }
    } else if (action === "play") {
      actionLabel = "Play"
      iconName = "media-play"
      if (player && player.canPlay) {
        player.play()
        handled = true
      } else if (player && player.canTogglePlaying && !player.isPlaying) {
        player.togglePlaying()
        handled = true
      }
    } else if (action === "pause") {
      actionLabel = "Pause"
      iconName = "media-pause"
      if (player && player.canPause) {
        player.pause()
        handled = true
      } else if (player && player.canTogglePlaying && player.isPlaying) {
        player.togglePlaying()
        handled = true
      }
    } else if (action === "playPause") {
      actionLabel = player && player.isPlaying ? "Pause" : "Play"
      iconName = player && player.isPlaying ? "media-pause" : "media-play"
      if (player && player.isPlaying && player.canPause) {
        player.pause()
        handled = true
      } else if (player && !player.isPlaying && player.canPlay) {
        player.play()
        handled = true
      } else if (player && player.canTogglePlaying) {
        player.togglePlaying()
        handled = true
      }
    } else if (action === "shuffle") {
      actionLabel = player && player.shuffle ? "Shuffle off" : "Shuffle on"
      iconName = player && player.shuffle ? "media-shuffle-off" : "media-shuffle"
      if (player && player.shuffleSupported) {
        player.shuffle = !player.shuffle
        handled = true
      }
    } else if (action === "loop") {
      var nextLoop = player ? MediaModel.nextLoopState(player.loopState) : 0
      actionLabel = MediaModel.loopLabel(nextLoop)
      iconName = nextLoop === 1 ? "media-repeat-one" : nextLoop === 2 ? "media-repeat" : "media-repeat-off"
      if (player && player.loopSupported) {
        player.loopState = nextLoop
        handled = true
      }
    }

    if (handled && key) preferredPlayerKey = key
    if (showFeedback !== false)
      scheduleOsd(actionLabel, iconName, player, handled && (action === "next" || action === "previous"), beforeTrackSignature)
    return handled
  }

  // Recompute play-order reactively instead of polling every 500ms.
  // syncPlayingOrder only depends on the set of players and each player's
  // isPlaying state: onPlayersChanged covers players appearing/disappearing,
  // and the Instantiator wires isPlayingChanged for each live player.
  Component.onCompleted: root.syncPlayingOrder()
  onPlayersChanged: root.syncPlayingOrder()

  Instantiator {
    model: root.players
    delegate: Connections {
      required property var modelData
      target: modelData
      function onIsPlayingChanged() { root.syncPlayingOrder() }
    }
  }

  Timer {
    id: trackOsdTimer
    interval: 120
    repeat: false
    onTriggered: root.flushPendingTrackOsd(false)
  }

  PwObjectTracker { objects: root.playbackStreams }
  PwObjectTracker { objects: root.links }

  Process {
    id: sinkInputsProc
    command: ["pactl", "list", "sink-inputs"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var move = root.pendingMove
        if (!move) return
        root.pendingMove = null
        root.moveSinkInputs(move, text)
      }
    }
  }

  function statusJson() {
    var p = activePlayer
    return JSON.stringify({
      hasPlayer: p !== null,
      hasMedia: root.hasMedia,
      playing: p ? !!p.isPlaying : false,
      identity: p ? (p.identity || "") : "",
      desktopEntry: p ? (p.desktopEntry || "") : "",
      title: p ? (p.trackTitle || "") : "",
      artist: p ? (p.trackArtist || "") : "",
      album: p && p.trackAlbum ? p.trackAlbum : "",
      artUrl: p && p.trackArtUrl ? p.trackArtUrl : "",
      canGoNext: p ? !!p.canGoNext : false,
      canGoPrevious: p ? !!p.canGoPrevious : false,
      canTogglePlaying: p ? !!p.canTogglePlaying : false,
      shuffle: p ? !!p.shuffle : false,
      shuffleSupported: p ? !!p.shuffleSupported : false,
      loopState: p ? Number(p.loopState || 0) : 0,
      loopSupported: p ? !!p.loopSupported : false
    })
  }

  IpcHandler {
    target: "media"

    function status(): string {
      return root.statusJson()
    }

    function playPause(): string {
      return root.runAction("playPause", true) ? "ok" : "unhandled"
    }

    function next(): string {
      return root.runAction("next", true) ? "ok" : "unhandled"
    }

    function previous(): string {
      return root.runAction("previous", true) ? "ok" : "unhandled"
    }

    function play(): string {
      return root.runAction("play", true) ? "ok" : "unhandled"
    }

    function pause(): string {
      return root.runAction("pause", true) ? "ok" : "unhandled"
    }

    function shuffle(): string {
      return root.runAction("shuffle", true) ? "ok" : "unhandled"
    }

    function loop(): string {
      return root.runAction("loop", true) ? "ok" : "unhandled"
    }

    function sourceNext(): string {
      return root.switchSource(1, false, true) ? "ok" : "unhandled"
    }

    function sourcePrevious(): string {
      return root.switchSource(-1, false, true) ? "ok" : "unhandled"
    }

    function sourceSwitch(): string {
      return root.switchSource(1, true, true) ? "ok" : "unhandled"
    }

    function sourceSwitchPrevious(): string {
      return root.switchSource(-1, true, true) ? "ok" : "unhandled"
    }

    function ping(): string {
      return "ok"
    }
  }
}
