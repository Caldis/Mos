import XCTest

final class LogiBoundaryEnforcementTests: XCTestCase {

    func testBoundaryLint_passes() throws {
        let process = Process()
        process.launchPath = "/bin/bash"
        process.arguments = ["scripts/lint-logi-boundary.sh"]
        process.currentDirectoryPath = SourceRoot.path

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        process.launch()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, "Logi boundary lint failed:\n\(output)")
    }
}

private enum SourceRoot {
    /// Walks up from MosTests/LogiBoundaryEnforcementTests.swift to the project root.
    static var path: String {
        return URL(fileURLWithPath: #file)
            .deletingLastPathComponent()       // MosTests/
            .deletingLastPathComponent()       // project root
            .path
    }
}
