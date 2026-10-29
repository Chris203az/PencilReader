import Foundation

/// The highlighted passages of a page, as the AI joins them: separate pieces of text that belong
/// to the same idea become one group, the others stay alone. Only pieces of the same kind
/// (the same highlighter color) are joined.
public enum HighlightGrouping {
    /// One highlighted passage: its place among the page's zones, its kind and the words under it.
    public struct Fragment: Sendable, Hashable {
        public let id: Int
        public let kind: String
        public let text: String

        public init(id: Int, kind: String, text: String) {
            self.id = id
            self.kind = kind
            self.text = text
        }
    }

    /// Passages of one kind that say one thing, in reading order.
    public struct Group: Codable, Sendable, Hashable {
        public let kind: String
        /// A few words naming the idea, in Italian; may be empty.
        public let title: String
        public let fragmentIDs: [Int]

        public init(kind: String, title: String, fragmentIDs: [Int]) {
            self.kind = kind
            self.title = title
            self.fragmentIDs = fragmentIDs
        }
    }

    /// The groups of one page, with the signature of the passages they were made from:
    /// when the highlights change, the signature no longer matches and the page is asked again.
    public struct Page: Codable, Sendable, Hashable {
        public let signature: String
        public let groups: [Group]

        public init(signature: String, groups: [Group]) {
            self.signature = signature
            self.groups = groups
        }
    }

    /// Bumped when the way of asking changes, so pages answered before are asked again.
    static let version = 2

    /// Stable across launches (unlike `Hasher`): FNV-1a over the kinds and texts, and the version.
    public static func signature(of fragments: [Fragment]) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "v\(version)\u{2}".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        for fragment in fragments {
            for byte in "\(fragment.id)\u{1}\(fragment.kind)\u{1}\(fragment.text)\u{2}".utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x100000001b3
            }
        }
        return String(hash, radix: 16)
    }

    /// Only a page with at least two passages of one kind has anything to join.
    public static func needsAsking(_ fragments: [Fragment]) -> Bool {
        Dictionary(grouping: fragments, by: \.kind).values.contains { $0.count > 1 }
    }

    /// Every passage alone, when there is nothing to ask.
    public static func separate(_ fragments: [Fragment]) -> [Group] {
        fragments.map { Group(kind: $0.kind, title: "", fragmentIDs: [$0.id]) }
    }

    // MARK: Request

    static let groupsKey = "gruppi"
    static let idsKey = "frammenti"
    static let titleKey = "titolo"

    /// `kindNames` gives the meaning of each kind to the model, e.g. "key" → "Concetto chiave".
    /// `pageText` is the whole page, so the model sees how the pieces sit in it (a list, a definition).
    public static func request(fragments: [Fragment], kindNames: [String: String], pageText: String?,
                               apiKey: String, model: String = GeminiExplainer.model) -> URLRequest {
        GeminiExplainer.request(prompt(fragments: fragments, kindNames: kindNames, pageText: pageText),
                                apiKey: apiKey, model: model)
    }

    /// The question for any provider.
    public static func prompt(fragments: [Fragment], kindNames: [String: String], pageText: String?) -> AIPrompt {
        AIPrompt(system: systemPrompt, user: prompt(fragments: fragments, kindNames: kindNames, pageText: pageText),
                 json: true, schema: schema)
    }

    /// Enough for a dense page; longer text is cut.
    static let pageTextLimit = 8000

    static func body(fragments: [Fragment], kindNames: [String: String], pageText: String? = nil) -> [String: Any] {
        GeminiExplainer.body(prompt(fragments: fragments, kindNames: kindNames, pageText: pageText))
    }

    static var schema: [String: Any] {
        [
            "type": "OBJECT",
            "properties": [
                groupsKey: [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "properties": [
                            idsKey: ["type": "ARRAY", "items": ["type": "INTEGER"]],
                            titleKey: ["type": "STRING"]
                        ],
                        "required": [idsKey, titleKey],
                        "propertyOrdering": [idsKey, titleKey]
                    ]
                ]
            ],
            "required": [groupsKey]
        ]
    }

    static let systemPrompt = """
        Aiuti uno studente universitario di ingegneria a ordinare ciò che ha evidenziato in una pagina \
        di un libro tecnico. Ogni frammento evidenziato ha una categoria (il colore dell'evidenziatore). \
        Lo studente evidenzia a pezzi: una frase che annuncia qualcosa e poi, più sotto, le parti di \
        ciò che ha annunciato. Il tuo compito è ricostruire i concetti: unire i frammenti che insieme \
        formano un'unica idea da studiare e lasciare separati quelli che parlano di cose diverse.
        Ricevi anche il testo completo della pagina: usalo per capire la struttura (elenchi, \
        definizioni, ipotesi, condizioni) e il ruolo di ogni frammento.
        Unisci sempre:
        - una frase introduttiva che annuncia un elenco o un numero di elementi (es. "si adottano due \
        ipotesi:", "caratterizzate da:", "i vantaggi sono") con TUTTI gli elementi evidenziati di \
        quell'elenco, anche se sono lontani nella pagina o in fondo all'elenco;
        - i punti di uno stesso elenco numerato o puntato, anche senza frase introduttiva evidenziata;
        - il nome di un elemento (es. "Regime stazionario:") con la sua spiegazione evidenziata;
        - una definizione con le sue precisazioni, condizioni di validità o conseguenze;
        - una frase spezzata su più righe o interrotta.
        Lascia separati i frammenti che riguardano concetti diversi, anche se vicini.
        Regole: unisci solo frammenti della stessa categoria; ogni frammento deve comparire in \
        esattamente un gruppo.
        Per ogni gruppo scrivi un titolo in italiano di 2-6 parole che nomina il concetto (es. \
        "Ipotesi del modello Q1D"), senza Markdown.
        """

    static func prompt(fragments: [Fragment], kindNames: [String: String], pageText: String? = nil) -> String {
        let list = fragments.map { fragment in
            let kind = kindNames[fragment.kind] ?? fragment.kind
            let text = fragment.text.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(fragment.id). [\(kind)] \(text)"
        }.joined(separator: "\n")
        let page = (pageText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let context = page.isEmpty ? "" : """
            Testo completo della pagina:
            \"\"\"
            \(page.prefix(pageTextLimit))
            \"\"\"


            """
        return context + """
            Frammenti evidenziati, nell'ordine di lettura (numero. [categoria] testo):
            \(list)

            Rispondi in JSON: "\(groupsKey)" è l'elenco dei gruppi; per ognuno "\(idsKey)" sono i numeri \
            dei frammenti che contiene e "\(titleKey)" il titolo del concetto.
            """
    }

    // MARK: Response

    /// Reads a successful (HTTP 200) answer into groups that cover every fragment exactly once.
    public static func parse(_ data: Data, fragments: [Fragment]) throws(ExplanationError) -> [Group] {
        try groups(fromModelText: GeminiExplainer.answerText(data), fragments: fragments)
    }

    /// The model's JSON, made safe: unknown or repeated numbers are dropped, a group mixing kinds
    /// is split by kind, and fragments the model forgot are added alone. Groups follow the page's
    /// reading order, by their first fragment.
    public static func groups(fromModelText text: String, fragments: [Fragment]) throws(ExplanationError) -> [Group] {
        guard let answered = AIRequests.jsonObject(in: text)?[groupsKey] as? [[String: Any]]
        else { throw .badResponse }
        let order = Dictionary(uniqueKeysWithValues: fragments.enumerated().map { ($1.id, $0) })
        let kinds = Dictionary(uniqueKeysWithValues: fragments.map { ($0.id, $0.kind) })
        var used = Set<Int>()
        var groups: [Group] = []
        for item in answered {
            let ids = (item[idsKey] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.intValue }
            let fresh = ids.filter { kinds[$0] != nil && used.insert($0).inserted }
            let title = (item[titleKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            for (kind, members) in Dictionary(grouping: fresh, by: { kinds[$0]! }) {
                groups.append(Group(kind: kind, title: title,
                                    fragmentIDs: members.sorted { order[$0]! < order[$1]! }))
            }
        }
        for fragment in fragments where !used.contains(fragment.id) {
            groups.append(Group(kind: fragment.kind, title: "", fragmentIDs: [fragment.id]))
        }
        return groups.sorted { order[$0.fragmentIDs[0]]! < order[$1.fragmentIDs[0]]! }
    }
}
