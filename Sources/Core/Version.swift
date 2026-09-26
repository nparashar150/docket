import Foundation

/// A released version, compared the way versions actually order.
///
/// String comparison gets this wrong the first time a component reaches double
/// digits: "0.1.10" sorts before "0.1.9", so the update that matters most is
/// the one that stops being offered.
public struct Version: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// Anything after a hyphen, as in `1.2.0-beta.1`. Empty for a real release.
    public let prerelease: String

    /// Parses `1.2.3`, `v1.2.3` and `v1.2.3-beta.1`, and tolerates missing
    /// components so `v1` and `v1.2` read as `1.0.0` and `1.2.0`.
    ///
    /// Returns nil rather than guessing when there is no leading number at
    /// all: a tag that is not a version should be ignored, not treated as
    /// 0.0.0, which would make every build look newer than it.
    public init?(_ text: String) {
        var body = text.trimmingCharacters(in: .whitespaces)
        if body.hasPrefix("v") || body.hasPrefix("V") { body.removeFirst() }

        let split = body.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        prerelease = split.count > 1 ? String(split[1]) : ""

        let numbers = split[0].split(separator: ".", omittingEmptySubsequences: false)
        guard let first = numbers.first, let major = Int(first) else { return nil }
        self.major = major
        minor = numbers.count > 1 ? Int(numbers[1]) ?? 0 : 0
        patch = numbers.count > 2 ? Int(numbers[2]) ?? 0 : 0
    }

    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.isEmpty ? core : "\(core)-\(prerelease)"
    }

    public static func < (a: Version, b: Version) -> Bool {
        if a.major != b.major { return a.major < b.major }
        if a.minor != b.minor { return a.minor < b.minor }
        if a.patch != b.patch { return a.patch < b.patch }
        // A prerelease precedes the release it leads to, so 1.2.0-beta is
        // older than 1.2.0. Two prereleases of the same version fall back to
        // comparing the labels, which is right often enough for beta.1 and
        // beta.2 and is never worse than treating them as equal.
        if a.prerelease.isEmpty != b.prerelease.isEmpty { return !a.prerelease.isEmpty }
        return a.prerelease < b.prerelease
    }
}
