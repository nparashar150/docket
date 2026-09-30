import Foundation

/// What a playing page's public version says about it: the name and picture
/// a link preview would show.
///
/// For the pages that tell the player nothing. Measured on a live
/// `netflix.com/watch` tab: no `mediaSession` metadata, no video poster, no
/// `og:image`, and a 16px favicon, so the panel read "Netflix /
/// www.netflix.com" over a placeholder. The public page for the same address
/// does carry both, needs no sign-in, and on Netflix redirects an episode to
/// its show. Nothing here is per site except `address(for:)`, which maps a
/// player URL whose public copy lives somewhere else. Pure, so it is tested.
struct PagePreview: Equatable, Sendable {
    var name: String
    var site: String?
    var image: URL?

    /// Where the public version of `page` lives, or nil for anything that
    /// is not an https page.
    ///
    /// Netflix's player redirects a signed-out request to the sign-in page,
    /// so its id is taken to the title page instead. Every other page is
    /// asked for as it is.
    static func address(for page: String) -> URL? {
        guard let url = URL(string: page), url.scheme == "https", let host = url.host() else {
            return nil
        }
        if host == "netflix.com" || host.hasSuffix(".netflix.com") {
            let parts = url.pathComponents
            if let i = parts.firstIndex(of: "watch"), i + 1 < parts.count,
               parts[i + 1].allSatisfy(\.isNumber) {
                return URL(string: "https://www.netflix.com/title/\(parts[i + 1])")
            }
        }
        return url
    }

    /// From the page's Open Graph tags, with Twitter's as the fallback.
    ///
    /// Titles arrive dressed for a search result, "Watch Beauty in Black |
    /// Netflix Official Site": everything from the first " | " goes, and the
    /// English "Watch " prefix with it. Other locales keep their verb.
    static func parse(_ html: String) -> PagePreview? {
        guard let raw = meta("og:title", in: html) ?? meta("twitter:title", in: html) else {
            return nil
        }
        var name = decoded(raw)
        if let bar = name.range(of: " | ") { name = String(name[..<bar.lowerBound]) }
        if name.hasPrefix("Watch ") { name.removeFirst("Watch ".count) }
        name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        // https only, like every other artwork URL: the picture is decorative
        // and not worth a cleartext request.
        let image = (meta("og:image", in: html) ?? meta("twitter:image", in: html))
            .map(decoded).flatMap(URL.init(string:))
            .flatMap { $0.scheme == "https" ? $0 : nil }
        return PagePreview(name: name, site: meta("og:site_name", in: html).map(decoded),
                           image: image)
    }

    /// The `content` of the `<meta property=…>` or `<meta name=…>` tag,
    /// whatever order its attributes come in.
    private static func meta(_ key: String, in html: String) -> String? {
        for tag in html.matches(of: #/<meta\b[^>]*>/#) {
            let text = tag.output
            guard text.contains("property=\"\(key)\"") || text.contains("name=\"\(key)\"")
            else { continue }
            return text.firstMatch(of: #/content="([^"]*)"/#).map { String($0.output.1) }
        }
        return nil
    }

    /// The entities that turn up in titles: "Grey&#39;s Anatomy", "Love &amp; Death".
    private static func decoded(_ text: String) -> String {
        var out = text
        for (entity, char) in [("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"),
                               ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out
    }
}
