import Foundation
import Testing
@testable import ReaderCore

private func response(_ object: Any) -> Data {
    let text = String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    return try! JSONSerialization.data(withJSONObject:
        ["candidates": [["content": ["role": "model", "parts": [["text": text]]], "finishReason": "STOP"]]])
}

private let fragments = [
    HighlightGrouping.Fragment(id: 0, kind: "key", text: "Specific impulse is the thrust"),
    HighlightGrouping.Fragment(id: 1, kind: "formula", text: "Isp = F / (mdot g0)"),
    HighlightGrouping.Fragment(id: 3, kind: "key", text: "per unit weight flow of propellant"),
    HighlightGrouping.Fragment(id: 4, kind: "review", text: "frozen flow")
]

struct HighlightGroupingTests {
    @Test func requestListsFragmentsWithTheirKindAndKeyInHeader() throws {
        let request = HighlightGrouping.request(fragments: fragments, kindNames: ["key": "Concetto chiave"],
                                                pageText: "1. Specific impulse is the thrust\n2. frozen flow",
                                                apiKey: "SECRET")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "SECRET")
        #expect(request.url?.absoluteString.contains("SECRET") == false)
        let body = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        let contents = body["contents"] as? [[String: Any]]
        let text = (contents?.first?["parts"] as? [[String: Any]])?.first?["text"] as? String ?? ""
        #expect(text.contains("0. [Concetto chiave] Specific impulse is the thrust"))
        #expect(text.contains("1. [formula] Isp = F / (mdot g0)"))
        // The whole page goes first, so the model sees the list the pieces belong to.
        #expect(text.hasPrefix("Testo completo della pagina:"))
        #expect(text.contains("2. frozen flow"))
        let config = body["generationConfig"] as? [String: Any]
        #expect(config?["responseMimeType"] as? String == "application/json")
    }

    @Test func joinsWhatTheModelJoins() throws {
        let data = response(["gruppi": [["frammenti": [0, 3], "titolo": "Impulso specifico"],
                                        ["frammenti": [1], "titolo": "Formula"],
                                        ["frammenti": [4], "titolo": "Flusso congelato"]]])
        let groups = try HighlightGrouping.parse(data, fragments: fragments)
        #expect(groups == [
            .init(kind: "key", title: "Impulso specifico", fragmentIDs: [0, 3]),
            .init(kind: "formula", title: "Formula", fragmentIDs: [1]),
            .init(kind: "review", title: "Flusso congelato", fragmentIDs: [4])
        ])
    }

    @Test func splitsMixedKindsAddsForgottenAndDropsUnknownOrRepeated() throws {
        let data = response(["gruppi": [["frammenti": [3, 1, 0, 9], "titolo": "Tutto"],
                                        ["frammenti": [0], "titolo": "Doppio"]]])
        let groups = try HighlightGrouping.parse(data, fragments: fragments)
        #expect(groups == [
            .init(kind: "key", title: "Tutto", fragmentIDs: [0, 3]),
            .init(kind: "formula", title: "Tutto", fragmentIDs: [1]),
            .init(kind: "review", title: "", fragmentIDs: [4])
        ])
    }

    @Test func unreadableAnswerIsABadResponse() {
        #expect(throws: ExplanationError.badResponse) {
            try HighlightGrouping.parse(response(["altro": 1]), fragments: fragments)
        }
    }

    @Test func signatureIsStableAndFollowsTheText() {
        let same = HighlightGrouping.signature(of: fragments)
        #expect(same == HighlightGrouping.signature(of: fragments))
        var changed = fragments
        changed[3] = .init(id: 4, kind: "review", text: "frozen flows")
        #expect(HighlightGrouping.signature(of: changed) != same)
    }

    @Test func withoutPageTextOnlyTheFragmentsAreSent() {
        let text = HighlightGrouping.prompt(fragments: fragments, kindNames: [:], pageText: "  ")
        #expect(text.hasPrefix("Frammenti evidenziati"))
    }

    @Test func asksOnlyWhenTwoPassagesShareAKind() {
        #expect(HighlightGrouping.needsAsking(fragments))
        #expect(!HighlightGrouping.needsAsking(Array(fragments.dropFirst())))
    }
}
