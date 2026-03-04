import Foundation

struct CommandProcessor {
    func apply(to text: String) -> String {
        var output = text

        let directReplacements: [(pattern: String, replacement: String)] = [
            (#"(?i)\bneuer absatz\b"#, "\n\n"),
            (#"(?i)\bneue zeile\b"#, "\n"),
            (#"(?i)\bpunkt\b"#, ". "),
            (#"(?i)\bkomma\b"#, ", ")
        ]

        for item in directReplacements {
            output = output.replacingOccurrences(
                of: item.pattern,
                with: item.replacement,
                options: .regularExpression
            )
        }

        output = transformSimpleLists(in: output)
        output = output.replacingOccurrences(of: #"(?m)[ \t]+\n"#, with: "\n", options: .regularExpression)
        output = output.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        output = output.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func transformSimpleLists(in text: String) -> String {
        var output = text

        output = output.replacingOccurrences(
            of: #"(?i)\bnummerierte liste[:\s]*"#,
            with: "\n1. ",
            options: .regularExpression
        )

        output = output.replacingOccurrences(
            of: #"(?i)\bstichpunkte[:\s]*"#,
            with: "\n• ",
            options: .regularExpression
        )

        output = output.replacingOccurrences(
            of: #"(?i)\bformell\b"#,
            with: "",
            options: .regularExpression
        )

        return output
    }
}
