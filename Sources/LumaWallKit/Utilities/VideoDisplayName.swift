import Foundation

/// Formats video filenames and slugs into clean, human-readable display titles:
/// e.g. "Aurora_Loop" -> "Aurora Loop", "Cyberpunk-City-4K" -> "Cyberpunk City 4K".
public enum VideoDisplayName {
    private static let siteSuffixes = [
        "-moewalls-com", "-moewalls",
        "_moewalls_com", "_moewalls",
        "-motionbgs-com", "-motionbgs",
        "-4k", "-1080p", "_4k", "_1080p"
    ]

    public static func pretty(from raw: String) -> String {
        var name = raw
        let lowered = name.lowercased()
        for suffix in siteSuffixes where lowered.hasSuffix(suffix) {
            name.removeLast(suffix.count)
            break
        }

        // Already a human name: has spaces and no slug separators
        if name.contains(" "), !name.contains("-"), !name.contains("_") {
            return name
        }

        let words = name
            .split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        let joined = words.joined(separator: " ")
        return joined.isEmpty ? raw : joined
    }
}
