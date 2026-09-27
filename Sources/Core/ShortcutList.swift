import Foundation

/// Turns `/usr/bin/shortcuts list` output into names.
///
/// Pure, and here rather than beside the service that runs the tool, because
/// the test target compiles the core instead of hosting the app. Parsing that
/// lived in Sources/Services could not be tested at all, and this is the part
/// with the edge cases.
public enum ShortcutList {
    /// One name per line, in the order the tool printed them.
    ///
    /// Having no shortcuts at all is an ordinary state rather than a failure:
    /// a Mac nobody has opened Shortcuts on has none, and the tool reports
    /// that as zero bytes with exit 0. It arrives here as an empty array, and
    /// the caller is expected to say so in words rather than draw an empty
    /// menu.
    ///
    /// Duplicates are dropped, keeping the first. Shortcuts.app allows two
    /// shortcuts to share a name, and running one by name cannot tell them
    /// apart, so listing the name twice would offer a choice that does not
    /// exist. The second is unreachable from here either way; dropping it at
    /// least stops the picker from looking like it works.
    /// Split on `isNewline` rather than on `"\n"`, because Swift treats
    /// `"\r\n"` as one Character and a `"\n"` separator therefore never
    /// matches it. The tool emits plain newlines, so nothing here would have
    /// noticed, and two names would have quietly become one the day anything
    /// upstream changed. The test for it found this.
    public static func parse(_ output: String) -> [String] {
        var seen = Set<String>()
        return output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
