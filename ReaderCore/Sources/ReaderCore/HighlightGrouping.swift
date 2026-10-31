import Foundation

/// The key concepts of a book, as the AI compacts its highlights: separate pieces of text that
/// belong to the same idea, on one page or on nearby pages, become one concept with a name and
/// a short synthesis; the others stay alone. Only pieces of the same kind (the same highlighter
/// color) are joined.
public enum HighlightGrouping {
    /// One highlighted passage: its page, its kind and the words under it.
    public struct Fragment: Sendable, Hashable {
        public let page: Int
        public let kind: String
        public let text: String
        /// Stable while the passage stays the same, whatever else changes on the page: page, kind,
        /// a hash of the words and which repeat of the same words on the page it is.
        public let key: String

        init(page: Int, kind: String, text: String, occurrence: Int) {
            self.page = page
            self.kind = kind
            self.text = text
            key = "\(page):\(kind):\(String(fnv(text), radix: 16)):\(occurrence)"
        }
    }

    /// The passages of one page, in reading order, with their keys.
    public static func fragments(page: Int, passages: [(kind: String, text: String)]) -> [Fragment] {
        var seen: [String: Int] = [:]
        return passages.compactMap { passage in
            let text = passage.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let id = "\(passage.kind)\u{1}\(text)"
            let count = seen[id, default: 0]
            seen[id] = count + 1
            return Fragment(page: page, kind: passage.kind, text: text, occurrence: count)
        }
    }

    /// The page a fragment's key belongs to.
    public static func page(ofKey key: String) -> Int? {
        key.split(separator: ":").first.flatMap { Int($0) }
    }

    /// Passages of one kind that say one thing, possibly on more pages.
    public struct Concept: Codable, Sendable, Hashable {
        public let kind: String
        /// A few words naming the idea, in Italian; may be empty.
        public let title: String
        /// The idea in one or two short sentences, in Italian; may be empty.
        public let summary: String
        /// Fragment keys, in reading order.
        public let keys: [String]

        public init(kind: String, title: String, summary: String, keys: [String]) {
            self.kind = kind
            self.title = title
            self.summary = summary
            self.keys = keys
        }

        public var pages: Set<Int> { Set(keys.compactMap(HighlightGrouping.page(ofKey:))) }
    }

    /// Everything compacted in one book: its concepts of more than one passage, and the signature
    /// of each page's passages when it was last compacted, so an unchanged page is not sent again.
    public struct Book: Codable, Sendable, Hashable {
        public var concepts: [Concept]
        /// Page index → signature.
        public var compacted: [Int: String]

        public init(concepts: [Concept] = [], compacted: [Int: String] = [:]) {
            self.concepts = concepts
            self.compacted = compacted
        }

        /// Whether the page's passages changed since it was last compacted.
        public func needsCompacting(_ page: Int, fragments: [Fragment]) -> Bool {
            compacted[page] != HighlightGrouping.signature(of: fragments)
        }
    }

    /// Bumped when the way of asking changes, so pages compacted before are compacted again.
    static let version = 3

    /// Stable across launches (unlike `Hasher`): FNV-1a.
    static func fnv(_ text: String, from start: UInt64 = 0xcbf29ce484222325) -> UInt64 {
        var hash = start
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    /// Of one page's passages, and the version.
    public static func signature(of fragments: [Fragment]) -> String {
        var hash = fnv("v\(version)\u{2}")
        for fragment in fragments {
            hash = fnv("\(fragment.key)\u{1}\(fragment.text)\u{2}", from: hash)
        }
        return String(hash, radix: 16)
    }

    /// Only passages with at least two of one kind have anything to join.
    public static func needsAsking(_ fragments: [Fragment]) -> Bool {
        Dictionary(grouping: fragments, by: \.kind).values.contains { $0.count > 1 }
    }

    // MARK: Scope

    /// The pages outside `pages` that concepts touching `pages` reach into: their passages are
    /// sent too, so a concept that continues there is not cut in two.
    public static func linkedPages(of pages: Set<Int>, in book: Book) -> Set<Int> {
        book.concepts.filter { !$0.pages.isDisjoint(with: pages) }
            .reduce(into: Set<Int>()) { $0.formUnion($1.pages) }
            .subtracting(pages)
    }

    /// What is sent when `pages` are compacted: all their passages, and the passages of other
    /// pages that belong to a concept touching them. `fragments` holds every page needed.
    public static func scope(of pages: Set<Int>, fragments: [Int: [Fragment]], book: Book) -> [Fragment] {
        let linked = Set(book.concepts.filter { !$0.pages.isDisjoint(with: pages) }.flatMap(\.keys))
        return fragments.keys.sorted().flatMap { page in
            pages.contains(page) ? fragments[page] ?? [] : (fragments[page] ?? []).filter { linked.contains($0.key) }
        }
    }

    /// The book with the concepts touching `pages` replaced by `answer`, and `pages` marked compacted
    /// with their current passages.
    public static func merging(_ answer: [Concept], compacted pages: Set<Int>, fragments: [Int: [Fragment]],
                               into book: Book) -> Book {
        var book = book
        let answered = Set(answer.flatMap(\.keys))
        book.concepts.removeAll { !$0.pages.isDisjoint(with: pages) || !answered.isDisjoint(with: $0.keys) }
        book.concepts += answer.filter { $0.keys.count > 1 }
        for page in pages {
            book.compacted[page] = signature(of: fragments[page] ?? [])
        }
        return book
    }

    // MARK: Request

    static let groupsKey = "gruppi"
    static let idsKey = "frammenti"
    static let titleKey = "titolo"
    static let summaryKey = "sintesi"

    /// Enough for a few dense pages; longer text is cut, page by page.
    static let pageTextLimit = 24000

    /// The question for any provider. `kindNames` gives the meaning of each kind to the model,
    /// e.g. "key" → "Concetto chiave". `pageTexts` are the whole pages, so the model sees how the
    /// pieces sit in them (a list, a definition).
    public static func prompt(fragments: [Fragment], kindNames: [String: String], pageTexts: [Int: String],
                              languages: LanguagePair = .default) -> AIPrompt {
        AIPrompt(system: systemPrompt(languages), user: promptText(fragments: fragments, kindNames: kindNames, pageTexts: pageTexts),
                 json: true, schema: responseSchema)
    }

    /// In Gemini's format.
    public static var responseSchema: [String: Any] {
        [
            "type": "OBJECT",
            "properties": [
                groupsKey: [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "properties": [
                            idsKey: ["type": "ARRAY", "items": ["type": "INTEGER"]],
                            titleKey: ["type": "STRING"],
                            summaryKey: ["type": "STRING"]
                        ],
                        "required": [idsKey, titleKey, summaryKey],
                        "propertyOrdering": [idsKey, titleKey, summaryKey]
                    ]
                ]
            ],
            "required": [groupsKey]
        ]
    }

    public static func systemPrompt(_ languages: LanguagePair) -> String {
        """
        Aiuti uno studente universitario di ingegneria a compattare ciò che ha evidenziato in un libro \
        tecnico in \(languages.sourceName). Ogni frammento evidenziato ha una pagina e una categoria (il colore \
        dell'evidenziatore). Lo studente evidenzia a pezzi: una frase che annuncia qualcosa e poi, più \
        sotto o nella pagina dopo, le parti di ciò che ha annunciato. Il tuo compito è ricostruire i \
        concetti: unire i frammenti che insieme formano un'unica idea da studiare e lasciare separati \
        quelli che parlano di cose diverse.
        Ricevi anche il testo delle pagine: usalo per capire la struttura (elenchi, definizioni, ipotesi, \
        condizioni) e il ruolo di ogni frammento.
        Unisci sempre:
        - una frase introduttiva che annuncia un elenco o un numero di elementi (es. "si adottano due \
        ipotesi:", "characterized by:", "the advantages are") con TUTTI gli elementi evidenziati di \
        quell'elenco, anche se sono lontani o continuano nella pagina successiva;
        - i punti di uno stesso elenco numerato o puntato, anche senza frase introduttiva evidenziata;
        - il nome di un elemento (es. "Steady state:") con la sua spiegazione evidenziata;
        - una definizione con le sue precisazioni, condizioni di validità o conseguenze;
        - una frase spezzata su più righe, interrotta o che continua a inizio della pagina dopo.
        Lascia separati i frammenti che riguardano concetti diversi, anche se vicini: un gruppo deve \
        poter essere studiato come una sola idea. Non unire tutto per argomento generale del capitolo.
        Regole: unisci solo frammenti della stessa categoria; ogni frammento deve comparire in \
        esattamente un gruppo.
        Per ogni gruppo scrivi in \(languages.targetName), senza Markdown:
        - un titolo di 2-6 parole che nomina il concetto (es. "Ipotesi del modello Q1D");
        - una sintesi: il concetto riformulato in modo compatto, in una o due frasi brevi (al massimo \
        35 parole), con i dati essenziali (simboli, condizioni, valori) e senza ripetere il titolo. \
        Per un gruppo di un solo frammento la sintesi può essere vuota.
        Rispondi solo in JSON.
        """
    }

    public static func promptText(fragments: [Fragment], kindNames: [String: String], pageTexts: [Int: String] = [:]) -> String {
        let list = fragments.enumerated().map { id, fragment in
            let kind = kindNames[fragment.kind] ?? fragment.kind
            let text = fragment.text.replacingOccurrences(of: "\n", with: " ")
            return "\(id). [p. \(fragment.page + 1)] [\(kind)] \(text)"
        }.joined(separator: "\n")
        let pages = pageTexts.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.value.isEmpty }
        let share = pages.isEmpty ? 0 : pageTextLimit / pages.count
        let context = pages.keys.sorted().map { page in
            """
            Testo della pagina \(page + 1):
            \"\"\"
            \(pages[page]!.prefix(share))
            \"\"\"


            """
        }.joined()
        return context + """
            Frammenti evidenziati, nell'ordine di lettura (numero. [pagina] [categoria] testo):
            \(list)

            Rispondi in formato json: "\(groupsKey)" è l'elenco dei gruppi; per ognuno "\(idsKey)" sono i numeri \
            dei frammenti che contiene, "\(titleKey)" il titolo del concetto e "\(summaryKey)" la sintesi.
            """
    }

    // MARK: Response

    /// The model's JSON, made safe: unknown or repeated numbers are dropped, a group mixing kinds
    /// is split by kind, and fragments left alone are not kept. Fragments follow the reading order,
    /// and so do the concepts, by their first fragment.
    public static func concepts(fromModelText text: String, fragments: [Fragment]) throws(ExplanationError) -> [Concept] {
        guard let answered = AIRequests.jsonObject(in: text)?[groupsKey] as? [[String: Any]] else { throw .badResponse }
        var used = Set<Int>()
        var concepts: [(first: Int, concept: Concept)] = []
        for item in answered {
            let ids = (item[idsKey] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.intValue }
            let fresh = ids.filter { fragments.indices.contains($0) && used.insert($0).inserted }
            let title = (item[titleKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let summary = (item[summaryKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let byKind = Dictionary(grouping: fresh, by: { fragments[$0].kind })
            for (kind, members) in byKind where members.count > 1 {
                let ordered = members.sorted()
                // A split group keeps the name, but its synthesis spoke of all the pieces.
                concepts.append((ordered[0], Concept(kind: kind, title: title, summary: byKind.count > 1 ? "" : summary,
                                                     keys: ordered.map { fragments[$0].key })))
            }
        }
        return concepts.sorted { $0.first < $1.first }.map(\.concept)
    }
}
