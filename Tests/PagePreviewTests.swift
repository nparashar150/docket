import XCTest

/// Tags copied from Netflix's live title page, attribute order and all.
final class PagePreviewTests: XCTestCase {

    private let netflix = """
    <head><meta charset="utf-8"/><title>Beauty in Black | Netflix Official Site</title>
    <meta data-rh="true" property="og:title" content="Watch Beauty in Black | Netflix Official Site"/>
    <meta data-rh="true" property="og:image" content="https://occ-0-3752-3646.1.nflxso.net/dnm/api/v6/6AYY37jfdO6hpXcMjf9Yu5cnmO0/AAAABdBtDwcyOys0.jpg?r=b09"/>
    </head>
    """

    func testReadsTheShowAndItsPicture() {
        let found = PagePreview.parse(netflix)
        XCTAssertEqual(found?.name, "Beauty in Black")
        XCTAssertNil(found?.site)
        XCTAssertEqual(found?.image?.host(), "occ-0-3752-3646.1.nflxso.net")
    }

    func testAttributeOrderEntitiesAndCleartext() {
        let html = """
        <meta content="Watch Grey&#39;s Anatomy | Netflix Official Site" property="og:title">
        <meta content="http://example.com/a.jpg" property="og:image">
        """
        let found = PagePreview.parse(html)
        XCTAssertEqual(found?.name, "Grey's Anatomy")
        XCTAssertNil(found?.image)
    }

    func testTwitterTagsAndSiteName() {
        let html = """
        <meta name="twitter:title" content="Episode 4">
        <meta name="twitter:image" content="https://cdn.example.com/e4.jpg">
        <meta property="og:site_name" content="Some Streamer">
        """
        let found = PagePreview.parse(html)
        XCTAssertEqual(found?.name, "Episode 4")
        XCTAssertEqual(found?.site, "Some Streamer")
        XCTAssertEqual(found?.image?.lastPathComponent, "e4.jpg")
    }

    func testNothingToReadIsNothing() {
        XCTAssertNil(PagePreview.parse("<html><head></head></html>"))
        XCTAssertNil(PagePreview.parse(#"<meta property="og:title" content=" | Netflix">"#))
    }

    func testNetflixPlayerMapsToItsTitlePage() {
        XCTAssertEqual(PagePreview.address(for: "https://www.netflix.com/watch/82026127?trackId=155573558"),
                       URL(string: "https://www.netflix.com/title/82026127"))
        XCTAssertEqual(PagePreview.address(for: "https://www.primevideo.com/detail/0ABC/"),
                       URL(string: "https://www.primevideo.com/detail/0ABC/"))
        XCTAssertEqual(PagePreview.address(for: "https://notnetflix.com/watch/1"),
                       URL(string: "https://notnetflix.com/watch/1"))
        XCTAssertNil(PagePreview.address(for: "http://example.com/video"))
        XCTAssertNil(PagePreview.address(for: "file:///movie.mp4"))
    }
}
