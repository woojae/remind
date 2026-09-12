import Foundation

/// Splits "Call the vet tomorrow at 2pm" into a title and a due date. The
/// longest trailing phrase that parses as a date wins; anything else stays
/// in the title. Only the explicit date grammar is used, so a title that
/// merely mentions a number never gets a due date by accident.
enum QuickAdd {
    struct Result: Equatable {
        var title: String
        var due: ParsedDate?
        var phrase: String?

        static func == (a: Result, b: Result) -> Bool {
            a.title == b.title && a.phrase == b.phrase
                && a.due?.date == b.due?.date && a.due?.hasTime == b.due?.hasTime
        }
    }

    private static let connectors: Set<String> = ["at", "on", "by", "due", "@", "-", "—", ","]

    static func parse(_ text: String, now: Date = Date()) -> Result {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = cleaned.split(whereSeparator: { $0 == " " }).map(String.init)
        guard words.count >= 2 else { return Result(title: cleaned, due: nil, phrase: nil) }

        let longest = min(words.count - 1, 6)
        for n in stride(from: longest, through: 1, by: -1) {
            let suffix = Array(words.suffix(n))
            var phraseWords = suffix
            if n > 1, connectors.contains(suffix[0].lowercased()) {
                phraseWords = Array(suffix.dropFirst())
            }
            let phrase = phraseWords.joined(separator: " ")
            guard let parsed = DateParse.parse(phrase, now: now, useDetector: false) else { continue }

            var titleWords = Array(words.dropLast(n))
            while let last = titleWords.last, connectors.contains(last.lowercased()) {
                titleWords.removeLast()
            }
            let title = titleWords.joined(separator: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,-—"))
            guard !title.isEmpty else { continue }
            return Result(title: title, due: parsed, phrase: phrase)
        }
        return Result(title: cleaned, due: nil, phrase: nil)
    }
}
