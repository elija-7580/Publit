import AVFoundation

/// Spoken directions in the trip guide ("Turn left onto Ludwigstraße", "Next stop: Odeonsplatz.
/// Get off there."). Other audio is turned down while speaking. Only while the guide is open.
@MainActor
final class GuideVoice: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = GuideVoice()
    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    func say(_ text: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let u = AVSpeechUtterance(string: text)
        // The app's language (it can differ from the phone's).
        u.voice = AVSpeechSynthesisVoice(language: Bundle.main.preferredLocalizations.first)
        // A newer instruction replaces one still being spoken.
        if synth.isSpeaking { synth.stopSpeaking(at: .word) }
        synth.speak(u)
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard !self.synth.isSpeaking else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
