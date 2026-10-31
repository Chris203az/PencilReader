import AVFoundation

/// Reads a circled word or phrase aloud, with a voice of the books' language.
@MainActor
enum Pronouncer {
    private static let synthesizer = AVSpeechSynthesizer()

    static func speak(_ text: String) {
        // Plays even with the silent switch on, lowering music while it speaks.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: TranslationLanguages.current.source)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }
}
