import AVFoundation

/// Reads a circled English word or phrase aloud, with an English voice.
@MainActor
enum Pronouncer {
    private static let synthesizer = AVSpeechSynthesizer()

    static func speak(_ text: String) {
        // Plays even with the silent switch on, lowering music while it speaks.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }
}
