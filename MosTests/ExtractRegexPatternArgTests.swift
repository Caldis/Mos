//
//  ExtractRegexPatternArgTests.swift
//  MosTests
//
//  Regression: Utils.extractRegexMatches must honor its `pattern` argument.
//

import XCTest
@testable import Mos_Debug

final class ExtractRegexPatternArgTests: XCTestCase {

    /// `extractRegexMatches` declares a `pattern` parameter, so callers expect it
    /// to drive the regex. Passing a non-`.app` pattern must extract accordingly.
    func testExtractRegexMatches_honorsPassedPattern() {
        // A digit run: only matchable when the caller-supplied pattern is used.
        let target = "abc123def"
        let extracted = Utils.extractRegexMatches(target: target, pattern: "[0-9]+")
        XCTAssertEqual(extracted, "123",
                       "extractRegexMatches must use the passed pattern; before the fix a hardcoded `.app` literal shadowed the parameter and returned the whole target unchanged.")
    }

    /// The existing in-tree call sites pass an `.app` pattern; that behaviour must be preserved.
    func testExtractRegexMatches_preservesAppPathBehaviour() {
        let target = "/Applications/Safari.app"
        let extracted = Utils.extractRegexMatches(target: target, pattern: #"\/?.*\.app"#)
        XCTAssertEqual(extracted, "/Applications/Safari.app")
    }

    /// When the supplied pattern does not match, the whole target is returned (documented fallback).
    func testExtractRegexMatches_noMatch_returnsTarget() {
        let target = "/Applications/Safari.app"
        let extracted = Utils.extractRegexMatches(target: target, pattern: "[0-9]+")
        XCTAssertEqual(extracted, target)
    }
}
