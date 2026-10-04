import Foundation
import AVFoundation

/// 老虎机音效播放(程序合成的 WAV,ambient 类别:跟随静音拨片、不打断音乐)
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()
    private var players: [String: AVAudioPlayer] = [:]

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        for name in ["slot_lever", "slot_spin", "slot_print", "slot_stamp"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "wav"),
               let player = try? AVAudioPlayer(contentsOf: url) {
                player.prepareToPlay()
                players[name] = player
            }
        }
    }

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "slotSoundOn") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "slotSoundOn") }
    }

    func play(_ name: String) {
        guard enabled, let player = players[name] else { return }
        player.currentTime = 0
        player.play()
    }

    func stopAll() {
        for player in players.values { player.stop() }
    }
}
