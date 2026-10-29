import Foundation

/// The AI's own re-elaboration of a range of pages: a title, the core idea and a few key points.
/// Short on purpose, so reading it after one's own takes a minute.
public struct AIRecap: Codable, Sendable, Hashable {
    public let title: String
    /// The core of the pages in one or two sentences.
    public let idea: String
    public let points: [String]

    public init(title: String, idea: String, points: [String]) {
        self.title = title
        self.idea = idea
        self.points = points
    }
}

/// "Fissa la lettura": at the end of a reading, the reader re-elaborates a range of pages by hand,
/// then compares it with the AI's version. The handwriting is kept apart, as a PencilKit drawing.
public struct ReadingRecap: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let bookID: UUID
    /// Kept so the recap stays readable after the book is renamed or deleted.
    public var bookTitle: String
    /// Zero-based, like the rest of the reader.
    public let firstPage: Int
    public let lastPage: Int
    public let created: Date
    /// Set when the reader says their own version is done and sees the AI's.
    public var finished: Date?
    public var ai: AIRecap?
    /// When it was offered for rereading at the start of a later session.
    public var offered: Date?

    public init(id: UUID = UUID(), bookID: UUID, bookTitle: String, firstPage: Int, lastPage: Int,
                created: Date, finished: Date? = nil, ai: AIRecap? = nil, offered: Date? = nil) {
        self.id = id
        self.bookID = bookID
        self.bookTitle = bookTitle
        self.firstPage = min(firstPage, lastPage)
        self.lastPage = max(firstPage, lastPage)
        self.created = created
        self.finished = finished
        self.ai = ai
        self.offered = offered
    }

    public var pageCount: Int { lastPage - firstPage + 1 }

    /// "pag. 12" or "pag. 12–18", counted from 1.
    public var pagesLabel: String {
        firstPage == lastPage ? "pag. \(firstPage + 1)" : "pag. \(firstPage + 1)–\(lastPage + 1)"
    }

    /// A recap made at least this long ago belongs to an earlier reading.
    public static let sessionGap: TimeInterval = 15 * 60

    /// The recap to reread before a new session of `book`: the latest finished one, made in an
    /// earlier session and not offered yet.
    public static func toReread(of book: UUID, in recaps: [ReadingRecap], now: Date) -> ReadingRecap? {
        let latest = recaps.filter { $0.bookID == book && $0.finished != nil }.max { $0.created < $1.created }
        guard let latest, latest.offered == nil, now.timeIntervalSince(latest.created) >= sessionGap else { return nil }
        return latest
    }

    /// The range offered when the reader says they have finished: back from the current page over
    /// the pages seen today without gaps, starting after the last recap of the book when that is later.
    public static func suggestedRange(current: Int, pagesSeenToday: Set<Int>, lastRecapEnd: Int?) -> ClosedRange<Int> {
        var first = current
        while first > 0, pagesSeenToday.contains(first - 1) { first -= 1 }
        if let lastRecapEnd, lastRecapEnd >= first, lastRecapEnd < current { first = lastRecapEnd + 1 }
        return first...current
    }
}

/// The prompt for the AI's re-elaboration and the reading of its answer.
public enum RecapWriter {
    /// More pages, a few more points: never a wall of text.
    public static func pointCount(pages: Int) -> Int {
        min(8, 3 + max(pages, 1) / 2)
    }

    /// Words per point.
    public static let wordsPerPoint = 30

    /// The text of all the pages, cut evenly when the whole would be too long for one request.
    public static let textLimit = 60_000

    static let titleKey = "titolo"
    static let ideaKey = "idea"
    static let pointsKey = "punti"

    static var schema: [String: Any] {
        [
            "type": "OBJECT",
            "properties": [
                titleKey: ["type": "STRING"],
                ideaKey: ["type": "STRING"],
                pointsKey: ["type": "ARRAY", "items": ["type": "STRING"]]
            ],
            "required": [titleKey, ideaKey, pointsKey],
            "propertyOrdering": [titleKey, ideaKey, pointsKey]
        ]
    }

    /// `pages` are the zero-based page numbers with their recognized text, in order.
    public static func prompt(pages: [(page: Int, text: String)]) -> AIPrompt {
        AIPrompt(system: systemPrompt, user: promptText(pages: pages), json: true, schema: schema)
    }

    static let systemPrompt = """
        Aiuti uno studente universitario italiano di ingegneria a fissare ciò che ha appena letto in un \
        libro tecnico in inglese. Lo studente ha già scritto a mano la sua rielaborazione: la tua serve a \
        confrontarla, quindi deve essere breve, chiara e facile da ricordare. Rispondi in italiano, senza Markdown.
        Non riassumere pagina per pagina: rielabora. Ricostruisci il ragionamento dell'autore, collega i \
        concetti tra loro (cause, conseguenze, ipotesi, condizioni di validità) e di' perché contano. \
        Usa i termini tecnici italiani corretti e, quando aiuta, il termine inglese tra parentesi. Scrivi \
        formule e simboli in testo semplice con caratteri Unicode (es. Isp = F/(ṁ·g₀)). Non aggiungere \
        nulla che non sia nel testo e non inventare dati. Ignora intestazioni, numeri di pagina, didascalie \
        isolate e residui del riconoscimento del testo.
        """

    static func promptText(pages: [(page: Int, text: String)]) -> String {
        let count = pointCount(pages: pages.count)
        let share = textLimit / max(pages.count, 1)
        let text = pages.map { page in
            let body = page.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return "[Pagina \(page.page + 1)]\n\(body.prefix(share))"
        }.joined(separator: "\n\n")
        let span = pages.count == 1 ? "una pagina" : "\(pages.count) pagine"
        return """
            Testo letto (\(span)):
            \"\"\"
            \(text)
            \"\"\"

            Rispondi con un oggetto json con tre campi:
            - "\(titleKey)": l'argomento, in 2-6 parole;
            - "\(ideaKey)": l'idea centrale, in una o due frasi;
            - "\(pointsKey)": al massimo \(count) punti chiave, ognuno di non più di \(wordsPerPoint) parole, \
            nell'ordine in cui conviene ripassarli.
            """
    }

    /// The model's JSON, tolerating text around it; empty points are dropped.
    public static func recap(fromModelText text: String) throws(ExplanationError) -> AIRecap {
        guard let object = AIRequests.jsonObject(in: text) else { throw .badResponse }
        func clean(_ value: Any?) -> String {
            (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        let idea = clean(object[ideaKey])
        let points = (object[pointsKey] as? [Any] ?? []).map(clean).filter { !$0.isEmpty }
        guard !idea.isEmpty || !points.isEmpty else { throw .badResponse }
        return AIRecap(title: clean(object[titleKey]), idea: idea, points: points)
    }
}
