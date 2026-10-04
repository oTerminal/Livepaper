import AVFoundation
import Foundation

/// A scene's sound objects, played as the scene is drawn: at the scene's own
/// volume for each, times the wallpaper's, which starts muted; looping when the
/// scene says so, once otherwise. A sound that starts silent (for a script to
/// start, which is not run) or is not visible stays silent.
///
/// Nothing is decoded while the wallpaper is muted: the players are made the
/// first time it is heard. Used from one actor at a time, the engine's owner's.
public final class SceneSoundtrack {
    private struct Track {
        let sound: SceneSound
        let data: Data
        var player: AVAudioPlayer?
    }

    private var tracks: [Track]
    private var volume: Float = 0
    private var isPlaying = false

    /// The sounds the scene plays, or nil when it has none.
    public init?(document: SceneDocument) {
        var tracks: [Track] = []
        for case .sound(let sound) in document.objects where sound.isVisible && !sound.startsSilent {
            guard let file = sound.files.first, let data = document.files.data(file) else { continue }
            tracks.append(Track(sound: sound, data: data))
        }
        guard !tracks.isEmpty else { return nil }
        self.tracks = tracks
    }

    /// The files it plays, for the log.
    public var files: [String] { tracks.compactMap(\.sound.files.first) }

    /// The volume each sound plays at now, 0 to 1, by file; nil for one not playing.
    var playing: [String: Float] {
        var playing: [String: Float] = [:]
        for track in tracks {
            guard let file = track.sound.files.first, let player = track.player, player.isPlaying else { continue }
            playing[file] = player.volume
        }
        return playing
    }

    /// Whether a sound's player has been made, which it is only once the wallpaper is heard.
    var hasPlayers: Bool { tracks.contains { $0.player != nil } }

    /// The wallpaper's volume, 0 to 1.
    public func setVolume(_ volume: Double) {
        self.volume = Float(min(max(volume, 0), 1))
        for index in tracks.indices { tracks[index].player?.volume = tracks[index].sound.volume * self.volume }
        if isPlaying { play() }
    }

    /// Plays from where it paused, making the players when first heard.
    public func play() {
        isPlaying = true
        guard volume > 0 else {
            for track in tracks { track.player?.pause() }
            return
        }
        for index in tracks.indices {
            if tracks[index].player == nil {
                let player = try? AVAudioPlayer(data: tracks[index].data)
                player?.numberOfLoops = tracks[index].sound.playback == "loop" ? -1 : 0
                player?.prepareToPlay()
                tracks[index].player = player
            }
            tracks[index].player?.volume = tracks[index].sound.volume * volume
            if tracks[index].player?.isPlaying == false { tracks[index].player?.play() }
        }
    }

    public func pause() {
        isPlaying = false
        for track in tracks { track.player?.pause() }
    }

    /// Stops and lets the players go; the next `play` starts from the beginning.
    public func stop() {
        isPlaying = false
        for index in tracks.indices {
            tracks[index].player?.stop()
            tracks[index].player = nil
        }
    }
}
