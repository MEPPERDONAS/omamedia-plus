function isProxyPlayer(player) {
  var dbusName = String(player && player.dbusName || "").toLowerCase()
  var desktopEntry = String(player && player.desktopEntry || "").toLowerCase()
  return dbusName.indexOf("playerctld") !== -1 || desktopEntry === "playerctld"
}

function hasMetadata(player) {
  return !!(player && (player.trackTitle || player.trackArtist || player.identity || player.desktopEntry))
}

function hasTrackMetadata(player) {
  return !!(player && (player.trackTitle || player.trackArtist || player.trackAlbum || player.trackArtUrl))
}

function playerCanControl(player) {
  return !!(player && (player.canTogglePlaying || player.canPlay || player.canPause || player.canGoNext || player.canGoPrevious))
}

function canHandleAction(player, action) {
  if (!player) return false
  if (action === "next") return !!player.canGoNext
  if (action === "previous") return !!player.canGoPrevious
  if (action === "play") return !!(player.canPlay || player.canTogglePlaying)
  if (action === "pause") return !!(player.canPause || player.canTogglePlaying)
  if (action === "playPause") return !!(player.canTogglePlaying || player.canPlay || player.canPause)
  if (action === "shuffle") return !!player.shuffleSupported
  if (action === "loop") return !!player.loopSupported
  return false
}

// MprisLoopState: 0 None, 1 Track, 2 Playlist.
// None -> Playlist -> Track -> None. Matches how Spotify's own control cycles.
function nextLoopState(loopState) {
  if (loopState === 0) return 2
  if (loopState === 2) return 1
  return 0
}

function loopLabel(loopState) {
  if (loopState === 1) return "Repeat track"
  if (loopState === 2) return "Repeat playlist"
  return "Repeat off"
}

function canCycleSource(player) {
  return !!(player && hasMetadata(player) && (player.isPlaying || player.canPlay))
}

function nodeProps(node) {
  return node && node.ready && node.properties ? node.properties : {}
}

function isPlaybackStream(node) {
  if (!node || !node.isStream) return false
  if (node.isSink === true) return true

  var mediaClass = String(node.type || "")
  return mediaClass.indexOf("Stream/Output/Audio") !== -1
    || mediaClass.indexOf("AudioOutStream") !== -1
    || mediaClass.indexOf("Output") !== -1
}

function streamLabelKey(label) {
  var key = String(label || "").toLowerCase()
  key = key.replace(/^pipewire alsa \[/, "")
  key = key.replace(/\]$/, "")
  key = key.replace(/^alsa playback \[/, "")
  key = key.replace(/[^a-z0-9]+/g, "")
  return key
}

function rawStreamLabel(node) {
  if (!node) return ""
  var p = nodeProps(node)
  return p["application.name"]
    || node.description
    || p["media.name"]
    || p["node.name"]
    || node.name
}

function playerAppLabel(player) {
  if (!player) return ""
  var dbus = String(player.dbusName || "")
  dbus = dbus.replace(/^org\.mpris\.MediaPlayer2\./, "")
  dbus = dbus.replace(/\.instance[0-9]+$/, "")
  return player.desktopEntry || player.identity || dbus
}

function browserKey(value) {
  var key = String(value || "").toLowerCase().trim()
  key = key.replace(/[^a-z0-9]+/g, "")
  if (key === "brave" || key === "bravebrowser" || key === "braveorigin") return "brave"
  if (key === "chrome" || key === "googlechrome" || key === "chromium" || key === "chromiumbrowser") return "chromium"
  if (key === "firefox" || key === "firefoxesr") return "firefox"
  if (key === "vivaldi" || key === "vivaldisnapshot") return "vivaldi"
  if (key === "microsoftedge" || key === "edge" || key === "edgedev") return "edge"
  if (key === "zen") return "zen"
  return ""
}

function browserServiceFromTitle(title) {
  var value = String(title || "").trim()
  var separator = value.lastIndexOf(" - ")
  if (separator <= 0 || separator + 3 >= value.length) return ""
  var browser = browserKey(value.substring(separator + 3))
  if (!browser) return ""

  var tabTitle = value.substring(0, separator).trim()
  var services = [
    { name: "YouTube Music", pattern: /\byoutube\s+music\b/i },
    { name: "YouTube", pattern: /\byoutube\b/i },
    { name: "Spotify", pattern: /\bspotify\b/i },
    { name: "SoundCloud", pattern: /\bsoundcloud\b/i },
    { name: "Tidal", pattern: /\btidal\b/i },
    { name: "Apple Music", pattern: /\bapple\s+music\b/i },
    { name: "Deezer", pattern: /\bdeezer\b/i }
  ]
  for (var i = 0; i < services.length; i++)
    if (services[i].pattern.test(tabTitle)) return services[i].name

  return ""
}

function browserSourceFromTitle(title) {
  var value = String(title || "").trim()
  var separator = value.lastIndexOf(" - ")
  if (separator <= 0 || separator + 3 >= value.length) return ""
  var browser = browserKey(value.substring(separator + 3))
  if (!browser) return ""

  return browserServiceFromTitle(title) || value.substring(0, separator).trim()
}

function isBrowserClientForPlayer(client, player) {
  if (!client || !player) return false
  var playerBrowser = browserKey(playerAppLabel(player)) || browserKey(player.identity)
  if (!playerBrowser) return false
  return playerBrowser === (browserKey(client.class) || browserKey(client.initialClass))
}

function browserClientForPlayer(player, clients) {
  if (!player || !Array.isArray(clients)) return null
  var best = null
  var bestScore = 0
  var trackTitle = String(player.trackTitle || "").toLowerCase().trim()
  var trackArtist = String(player.trackArtist || "").toLowerCase().trim()
  for (var i = 0; i < clients.length; i++) {
    var client = clients[i]
    if (!isBrowserClientForPlayer(client, player)) continue
    var title = String(client.title || "").toLowerCase()
    var source = browserSourceFromTitle(client.title)
    var service = browserServiceFromTitle(client.title)
    var score = service ? 10 : (source ? 1 : 0)
    if (trackTitle && title.indexOf(trackTitle) !== -1) score += 100
    if (trackArtist && title.indexOf(trackArtist) !== -1) score += 50
    if (score > bestScore) {
      best = client
      bestScore = score
    }
  }
  return best
}

function browserSourceInfo(player, clients) {
  var client = browserClientForPlayer(player, clients)
  if (!client) return null
  var service = browserServiceFromTitle(client.title)
  return {
    label: service,
    app: String(client.class || client.initialClass || "")
  }
}

function browserSourceLabel(player, clients) {
  var info = browserSourceInfo(player, clients)
  return info ? info.label : ""
}

function friendlyDeviceLabel(text) {
  var label = String(text || "").trim()
  label = label.replace(/^sof-soundwire\s+/i, "")
  label = label.replace(/^built-?in audio\s+/i, "")
  label = label.replace(/\s+Output$/i, "")
  label = label.replace(/\s+Input$/i, "")
  label = label.replace(/\bMicrophones\b/g, "Microphone")
  return label
}

function sinkLabel(node) {
  if (!node) return "Unknown"
  var p = nodeProps(node)
  var nickname = friendlyDeviceLabel(
    node.nickname || node.nick || p["node.nick"] || p["device.profile.description"] || "")
  if (nickname) return nickname
  return friendlyDeviceLabel(node.description || p["node.description"] || node.name || "Unknown")
}

function isHeadphones(node) {
  if (!node) return false
  var p = nodeProps(node)
  var blob = String([
    node.name, node.description, node.nickname,
    p["device.icon-name"] || "",
    p["device.product.name"] || "",
    p["node.description"] || "",
    p["node.nick"] || ""
  ].join(" ")).toLowerCase()
  return blob.indexOf("headphone") !== -1
    || blob.indexOf("headset") !== -1
    || blob.indexOf("earbud") !== -1
    || blob.indexOf("earphone") !== -1
    || blob.indexOf("airpod") !== -1
}

function sinkGlyph(node) {
  if (!node) return "󰓃"
  if (isHeadphones(node)) return "󰋋"
  var p = nodeProps(node)
  var blob = String([
    node.name, node.description, node.nickname,
    p["device.icon-name"] || "",
    p["device.product.name"] || ""
  ].join(" ")).toLowerCase()
  if (blob.indexOf("bluetooth") !== -1) return "󰂯"
  if (blob.indexOf("hdmi") !== -1 || blob.indexOf("display") !== -1) return "󰍹"
  return "󰓃"
}

function playerHasPlaybackStream(player, playbackStreams) {
  var playerKey = streamLabelKey(playerAppLabel(player))
  if (!playerKey) return false

  var streams = Array.isArray(playbackStreams) ? playbackStreams : []
  for (var i = 0; i < streams.length; i++) {
    var streamKey = streamLabelKey(rawStreamLabel(streams[i]))
    if (!streamKey) continue
    if (streamKey === playerKey
        || streamKey.indexOf(playerKey) !== -1
        || playerKey.indexOf(streamKey) !== -1)
      return true
  }

  return false
}

function playerKey(player) {
  if (!player) return ""
  return String(player.dbusName || player.desktopEntry || player.identity || "")
}

function trackSignature(player) {
  if (!player) return ""
  return [
    player.trackTitle || "",
    player.trackArtist || "",
    player.trackAlbum || "",
    player.trackArtUrl || ""
  ].join("\u001f")
}

function trackChanged(previousSignature, player) {
  return trackSignature(player) !== String(previousSignature || "")
}

function labelFor(player) {
  if (!player) return ""
  return player.trackTitle || player.identity || player.desktopEntry || ""
}

function osdMessage(player, fallback) {
  if (!player) return fallback
  var label = labelFor(player)
  if (label && player.trackArtist) return label + " - " + player.trackArtist
  return label || fallback
}

if (typeof module !== "undefined") {
  module.exports = {
    isProxyPlayer: isProxyPlayer,
    hasMetadata: hasMetadata,
    hasTrackMetadata: hasTrackMetadata,
    playerCanControl: playerCanControl,
    canHandleAction: canHandleAction,
    nextLoopState: nextLoopState,
    loopLabel: loopLabel,
    canCycleSource: canCycleSource,
    nodeProps: nodeProps,
    isPlaybackStream: isPlaybackStream,
    streamLabelKey: streamLabelKey,
    rawStreamLabel: rawStreamLabel,
    playerAppLabel: playerAppLabel,
    browserKey: browserKey,
    browserSourceFromTitle: browserSourceFromTitle,
    isBrowserClientForPlayer: isBrowserClientForPlayer,
    browserClientForPlayer: browserClientForPlayer,
    browserSourceInfo: browserSourceInfo,
    browserSourceLabel: browserSourceLabel,
    friendlyDeviceLabel: friendlyDeviceLabel,
    sinkLabel: sinkLabel,
    isHeadphones: isHeadphones,
    sinkGlyph: sinkGlyph,
    playerHasPlaybackStream: playerHasPlaybackStream,
    playerKey: playerKey,
    trackSignature: trackSignature,
    trackChanged: trackChanged,
    labelFor: labelFor,
    osdMessage: osdMessage
  }
}
