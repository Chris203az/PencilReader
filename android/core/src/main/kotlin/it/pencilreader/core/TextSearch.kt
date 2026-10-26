package it.pencilreader.core

/// Un'occorrenza della ricerca su una pagina.
data class SearchMatch(
    /// Le parole coperte dall'occorrenza, da evidenziare sulla pagina.
    val wordIDs: List<Int>,
    /// Il testo attorno, accorciato con "…".
    val snippet: String,
    /// L'occorrenza dentro `snippet`.
    val highlight: Span,
)

/// Ricerca che ignora maiuscole e accenti nel testo continuo di ogni blocco, così si trovano
/// anche le parole spezzate a fine riga e le frasi che passano da una riga all'altra.
fun PageText.search(query: String, snippetRadius: Int = 60): List<SearchMatch> {
    val needle = query.trim()
    if (needle.isEmpty()) return emptyList()
    val matches = mutableListOf<SearchMatch>()
    for (block in blocks) {
        for (found in TextFolding.findAll(needle, block.text)) {
            val ids = block.wordRanges.filter { it.value.overlaps(found) }.keys.sorted()
            matches.add(snippet(found, block.text, snippetRadius, ids))
        }
    }
    return matches
}

private fun snippet(found: Span, text: String, radius: Int, wordIDs: List<Int>): SearchMatch {
    var lower = maxOf(0, found.start - radius)
    var upper = minOf(text.length, found.end + radius)
    // Non tagliare le parole a metà.
    if (lower > 0) {
        val space = text.substring(lower, found.start).indexOf(' ')
        if (space >= 0) lower += space + 1
    }
    if (upper < text.length) {
        val space = text.substring(found.end, upper).lastIndexOf(' ')
        if (space >= 0) upper = found.end + space
    }
    val prefix = if (lower > 0) "…" else ""
    val suffix = if (upper < text.length) "…" else ""
    val snippet = prefix + text.substring(lower, upper) + suffix
    val start = prefix.length + (found.start - lower)
    return SearchMatch(wordIDs, snippet, Span(start, start + found.length))
}
