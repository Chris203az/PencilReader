import CoreGraphics
import Foundation
import ReaderCore
import Vision

/// Runs Vision text recognition on a whole page, once; the result is cached by the caller.
struct OCRService: Sendable {
    /// Terms the language correction would otherwise "fix" into common words.
    private static let technicalWords = [
        "airfoil", "aerofoil", "aeroelastic", "aeroelasticity", "supersonic", "hypersonic",
        "transonic", "subsonic", "Reynolds", "Mach", "Prandtl", "Bernoulli", "Navier", "Stokes",
        "Kutta", "Joukowski", "vorticity", "downwash", "upwash", "camber", "empennage",
        "aileron", "ailerons", "nacelle", "spoilers", "isentropic", "adiabatic", "enthalpy",
        "entropy", "thrust", "turbofan", "turbojet", "ramjet", "scramjet", "nozzle", "apogee",
        "perigee", "ephemeris", "quaternion", "quaternions"
    ]

    func recognize(_ image: CGImage) async throws -> PageText {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        // The books' language when Vision reads it, English otherwise; English also covers formulas and units.
        let source = Locale.Language(identifier: TranslationLanguages.current.source)
        let readable = request.supportedRecognitionLanguages.contains { $0.languageCode == source.languageCode }
        request.recognitionLanguages = readable && source.languageCode != "en"
            ? [source, Locale.Language(identifier: "en-US")] : [Locale.Language(identifier: "en-US")]
        request.usesLanguageCorrection = true
        request.customWords = Self.technicalWords

        let observations = try await request.perform(on: image)
        var lines: [RawLine] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let string = candidate.string
            var words: [RawWord] = []
            for range in Self.wordRanges(in: string) {
                guard let box = candidate.boundingBox(for: range) else { continue }
                words.append(RawWord(text: String(string[range]), rect: Self.topLeft(box.boundingBox.cgRect)))
            }
            lines.append(RawLine(text: string, rect: Self.topLeft(observation.boundingBox.cgRect), words: words))
        }
        return PageText(lines: lines)
    }

    /// Whitespace-separated tokens, so "trailing-edge" and "aircraft's" stay whole.
    private static func wordRanges(in s: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        for i in s.indices {
            if s[i].isWhitespace {
                if let st = start { ranges.append(st..<i); start = nil }
            } else if start == nil {
                start = i
            }
        }
        if let st = start { ranges.append(st..<s.endIndex) }
        return ranges
    }

    /// Vision rects are normalized with a bottom-left origin.
    private static func topLeft(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
    }
}
