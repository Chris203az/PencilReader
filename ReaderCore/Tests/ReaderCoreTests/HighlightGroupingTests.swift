import Foundation
import Testing
@testable import ReaderCore

/// The model's text, inside a code fence as some models write it.
private func response(_ object: Any) -> String {
    "```json\n" + String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self) + "\n```"
}

private let page4 = HighlightGrouping.fragments(page: 4, passages: [
    ("key", "Specific impulse is the thrust"),
    ("formula", "Isp = F / (mdot g0)"),
    ("key", "per unit weight flow of propellant"),
    ("review", "frozen flow")
])
private let page5 = HighlightGrouping.fragments(page: 5, passages: [("key", "and is measured in seconds")])
private let fragments = page4 + page5

struct HighlightGroupingTests {
    @Test func promptListsFragmentsWithPageKindAndPageTexts() throws {
        let prompt = HighlightGrouping.prompt(fragments: fragments, kindNames: ["key": "Concetto chiave"],
                                              pageTexts: [4: "1. Specific impulse is the thrust", 5: "  "])
        let text = prompt.user
        #expect(text.contains("0. [p. 5] [Concetto chiave] Specific impulse is the thrust"))
        #expect(text.contains("1. [p. 5] [formula] Isp = F / (mdot g0)"))
        #expect(text.contains("4. [p. 6] [Concetto chiave] and is measured in seconds"))
        // The pages go first, so the model sees the list the pieces belong to; empty ones are left out.
        #expect(text.hasPrefix("Testo della pagina 5:"))
        #expect(!text.contains("Testo della pagina 6"))
        // DeepSeek answers in JSON only when the prompt says "json".
        #expect(prompt.json && text.contains("json"))
        #expect(prompt.schema?["required"] as? [String] == ["gruppi"])
    }

    @Test func joinsAcrossPagesAndKeepsOnlyRealGroups() throws {
        let data = response(["gruppi": [["frammenti": [0, 2, 4], "titolo": "Impulso specifico", "sintesi": "Spinta per peso."],
                                        ["frammenti": [1], "titolo": "Formula", "sintesi": ""],
                                        ["frammenti": [3], "titolo": "Flusso congelato", "sintesi": ""]]])
        let concepts = try HighlightGrouping.concepts(fromModelText: data, fragments: fragments)
        #expect(concepts == [.init(kind: "key", title: "Impulso specifico", summary: "Spinta per peso.",
                                   keys: [page4[0].key, page4[2].key, page5[0].key])])
        #expect(concepts[0].pages == [4, 5])
    }

    @Test func splitsMixedKindsAndDropsUnknownOrRepeated() throws {
        let data = response(["gruppi": [["frammenti": [2, 1, 0, 9], "titolo": "Tutto", "sintesi": "S"],
                                        ["frammenti": [0, 4], "titolo": "Doppio", "sintesi": "D"]]])
        let concepts = try HighlightGrouping.concepts(fromModelText: data, fragments: fragments)
        // 1 (formula) is alone after the split; 0 was already used, so "Doppio" keeps only 4.
        #expect(concepts == [.init(kind: "key", title: "Tutto", summary: "", keys: [page4[0].key, page4[2].key])])
    }

    @Test func unreadableAnswerIsABadResponse() {
        #expect(throws: ExplanationError.badResponse) {
            try HighlightGrouping.concepts(fromModelText: response(["altro": 1]), fragments: fragments)
        }
    }

    @Test func keysSurviveOtherChangesOnThePage() {
        let more = HighlightGrouping.fragments(page: 4, passages: [
            ("key", "A new passage above"),
            ("key", "Specific impulse is the thrust"),
            ("key", ""),
            ("key", "per unit weight flow of propellant")
        ])
        #expect(more.count == 3)
        #expect(more[1].key == page4[0].key)
        #expect(more[2].key == page4[2].key)
        #expect(HighlightGrouping.page(ofKey: more[0].key) == 4)
        let twice = HighlightGrouping.fragments(page: 4, passages: [("key", "same"), ("key", "same")])
        #expect(twice[0].key != twice[1].key)
    }

    @Test func signatureIsStableAndFollowsTheText() {
        let same = HighlightGrouping.signature(of: page4)
        #expect(same == HighlightGrouping.signature(of: page4))
        let changed = HighlightGrouping.fragments(page: 4, passages: [("key", "Specific impulse")])
        #expect(HighlightGrouping.signature(of: changed) != same)
        let book = HighlightGrouping.Book(compacted: [4: same])
        #expect(!book.needsCompacting(4, fragments: page4))
        #expect(book.needsCompacting(4, fragments: changed))
        #expect(book.needsCompacting(5, fragments: page5))
    }

    @Test func scopeTakesLinkedPassagesOfOtherPages() {
        let page3 = HighlightGrouping.fragments(page: 3, passages: [("key", "the thrust is"), ("key", "unrelated")])
        let linked = HighlightGrouping.Concept(kind: "key", title: "", summary: "", keys: [page3[0].key, page4[0].key])
        let elsewhere = HighlightGrouping.Concept(kind: "key", title: "", summary: "", keys: ["1:key:a:0", "2:key:b:0"])
        let book = HighlightGrouping.Book(concepts: [linked, elsewhere])
        #expect(HighlightGrouping.linkedPages(of: [4, 5], in: book) == [3])
        let scope = HighlightGrouping.scope(of: [4, 5], fragments: [3: page3, 4: page4, 5: page5], book: book)
        #expect(scope == [page3[0]] + page4 + page5)
    }

    @Test func mergingReplacesTheConceptsOfThePages() {
        let old = HighlightGrouping.Concept(kind: "key", title: "Vecchio", summary: "", keys: [page4[0].key, page4[2].key])
        let elsewhere = HighlightGrouping.Concept(kind: "key", title: "Altro", summary: "", keys: ["1:key:a:0", "2:key:b:0"])
        let new = HighlightGrouping.Concept(kind: "key", title: "Nuovo", summary: "",
                                            keys: [page4[0].key, page4[2].key, page5[0].key])
        let merged = HighlightGrouping.merging([new], compacted: [4, 5], fragments: [4: page4, 5: page5],
                                               into: .init(concepts: [old, elsewhere]))
        #expect(merged.concepts == [elsewhere, new])
        #expect(!merged.needsCompacting(4, fragments: page4))
        #expect(!merged.needsCompacting(5, fragments: page5))
        // An empty answer removes the page's concepts: its passages no longer belong together.
        let emptied = HighlightGrouping.merging([], compacted: [4], fragments: [4: page4], into: merged)
        #expect(emptied.concepts == [elsewhere])
    }

    @Test func withoutPageTextOnlyTheFragmentsAreSent() {
        let text = HighlightGrouping.promptText(fragments: fragments, kindNames: [:], pageTexts: [4: "  "])
        #expect(text.hasPrefix("Frammenti evidenziati"))
    }

    @Test func asksOnlyWhenTwoPassagesShareAKind() {
        #expect(HighlightGrouping.needsAsking(fragments))
        #expect(!HighlightGrouping.needsAsking([page4[1], page4[3], page5[0]]))
    }
}
