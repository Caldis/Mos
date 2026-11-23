//
//  RemovingRegexUTF16RangeTests.swift
//  MosTests
//
//  Regression: Utils.removingRegexMatches must use the UTF-16 length for the
//  NSRegularExpression range, otherwise astral-plane characters (emoji) in an
//  app display name clip the search range and the trailing ".app" is not stripped.
//

import XCTest
@testable import Mos_Debug

final class RemovingRegexUTF16RangeTests: XCTestCase {

    /// `Utils.parseName` strips a trailing ".app" from the display name via
    /// `removingRegexMatches(target:pattern:".app")`. When the name contains an
    /// astral-plane character the grapheme-cluster count is shorter than the
    /// UTF-16 count NSRegularExpression operates on, so the trailing ".app" fell
    /// outside the range and survived. The per-app overrides list would then show
    /// the app with an extra ".app" suffix.
    func testRemovingRegexMatches_stripsTrailingAppSuffixOnEmojiName() {
        // "My App🚀.app" → 11 grapheme clusters, 12 UTF-16 units (🚀 is a surrogate pair).
        // With the grapheme-cluster length the range ended at "...ap", so ".app" never matched.
        let name = "My App🚀.app"
        let stripped = Utils.removingRegexMatches(target: name, pattern: "\\.app$", replaceWith: "")
        XCTAssertEqual(stripped, "My App🚀",
                       "trailing .app must be stripped even when the name contains an astral-plane character")
    }

    /// Pure ASCII names must continue to behave exactly as before.
    func testRemovingRegexMatches_preservesASCIIBehaviour() {
        XCTAssertEqual(
            Utils.removingRegexMatches(target: "Safari.app", pattern: "\\.app$", replaceWith: ""),
            "Safari"
        )
    }

    /// A name made entirely of astral-plane characters plus the suffix.
    func testRemovingRegexMatches_stripsSuffixWhenNameIsMostlyAstral() {
        let name = "🚀🚀🚀.app"
        let stripped = Utils.removingRegexMatches(target: name, pattern: "\\.app$", replaceWith: "")
        XCTAssertEqual(stripped, "🚀🚀🚀")
    }
}
