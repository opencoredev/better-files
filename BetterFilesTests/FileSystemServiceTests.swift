import XCTest
import UniformTypeIdentifiers
@testable import BetterFiles

final class FileSystemServiceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BetterFilesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try super.tearDownWithError()
    }

    func testContentsReturnsFoldersBeforeFiles() throws {
        let folderURL = temporaryDirectory.appendingPathComponent("Projects", isDirectory: true)
        let fileURL = temporaryDirectory.appendingPathComponent("notes.txt")

        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let items = try FileSystemService().contents(of: temporaryDirectory)

        XCTAssertEqual(items.map(\.name), ["Projects", "notes.txt"])
        XCTAssertEqual(items.first?.kind, .folder)
        XCTAssertEqual(items.last?.kind, .file)
        XCTAssertNotNil(items.last?.createdAt)
        XCTAssertNotNil(items.last?.modifiedAt)
        XCTAssertNotNil(items.last?.posixPermissions)
        XCTAssertEqual(items.last?.localizedTypeDescription, UTType.plainText.localizedDescription)
    }

    func testContentsSkipsHiddenFiles() throws {
        let visibleURL = temporaryDirectory.appendingPathComponent("visible.txt")
        let hiddenURL = temporaryDirectory.appendingPathComponent(".hidden.txt")

        try "visible".write(to: visibleURL, atomically: true, encoding: .utf8)
        try "hidden".write(to: hiddenURL, atomically: true, encoding: .utf8)

        let items = try FileSystemService().contents(of: temporaryDirectory)

        XCTAssertEqual(items.map(\.name), ["visible.txt"])
    }

    func testContentsCanIncludeHiddenFiles() throws {
        let visibleURL = temporaryDirectory.appendingPathComponent("visible.txt")
        let hiddenURL = temporaryDirectory.appendingPathComponent(".hidden.txt")

        try "visible".write(to: visibleURL, atomically: true, encoding: .utf8)
        try "hidden".write(to: hiddenURL, atomically: true, encoding: .utf8)

        let items = try FileSystemService().contents(of: temporaryDirectory, includingHidden: true)

        XCTAssertEqual(items.map(\.name), [".hidden.txt", "visible.txt"])
        XCTAssertEqual(items.first?.isHidden, true)
    }

    func testContentsCanDisableFoldersFirstGrouping() throws {
        let folderURL = temporaryDirectory.appendingPathComponent("Zoo", isDirectory: true)
        let fileURL = temporaryDirectory.appendingPathComponent("alpha.txt")

        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let items = try FileSystemService().contents(
            of: temporaryDirectory,
            includingHidden: false,
            foldersFirst: false
        )

        XCTAssertEqual(items.map(\.name), ["alpha.txt", "Zoo"])
    }

    func testContentsTreatsAppAndDocumentPackagesAsPackages() throws {
        let packageNames = [
            "better-files.app",
            "Installer.pkg",
            "Project.xcodeproj",
            "Report.pages",
            "Archive.rtfd"
        ]

        for name in packageNames {
            try FileManager.default.createDirectory(
                at: temporaryDirectory.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        let folderURL = temporaryDirectory.appendingPathComponent("Regular Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let items = try FileSystemService().contents(of: temporaryDirectory)
        let itemsByName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })

        for name in packageNames {
            XCTAssertEqual(itemsByName[name]?.kind, .package)
            XCTAssertFalse(itemsByName[name]?.canOpenAsFolder ?? true)
        }

        XCTAssertEqual(itemsByName["Regular Folder"]?.kind, .folder)
        XCTAssertTrue(itemsByName["Regular Folder"]?.canOpenAsFolder ?? false)
    }

    func testSearchFindsMatchingItemsRecursivelyUnderCurrentDirectory() throws {
        let reportsURL = temporaryDirectory.appendingPathComponent("Reports", isDirectory: true)
        let nestedURL = reportsURL.appendingPathComponent("Archive", isDirectory: true)
        let matchURL = nestedURL.appendingPathComponent("quarterly-report.txt")
        let rootMatchURL = temporaryDirectory.appendingPathComponent("report-summary.md")
        let nonMatchURL = nestedURL.appendingPathComponent("notes.txt")

        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        try "match".write(to: matchURL, atomically: true, encoding: .utf8)
        try "root".write(to: rootMatchURL, atomically: true, encoding: .utf8)
        try "nope".write(to: nonMatchURL, atomically: true, encoding: .utf8)

        let items = try FileSystemService().search(
            in: temporaryDirectory,
            query: "report",
            includingHidden: false,
            foldersFirst: true,
            limit: 20
        )

        XCTAssertEqual(items.map(\.url.standardizedFileURL.path), [
            reportsURL.standardizedFileURL.path,
            rootMatchURL.standardizedFileURL.path,
            matchURL.standardizedFileURL.path
        ])
    }

    func testSearchRespectsHiddenFilesAndLimit() throws {
        let hiddenFolderURL = temporaryDirectory.appendingPathComponent(".Secrets", isDirectory: true)
        let hiddenMatchURL = hiddenFolderURL.appendingPathComponent("target.txt")
        let firstMatchURL = temporaryDirectory.appendingPathComponent("target-a.txt")
        let secondMatchURL = temporaryDirectory.appendingPathComponent("target-b.txt")

        try FileManager.default.createDirectory(at: hiddenFolderURL, withIntermediateDirectories: true)
        try "hidden".write(to: hiddenMatchURL, atomically: true, encoding: .utf8)
        try "one".write(to: firstMatchURL, atomically: true, encoding: .utf8)
        try "two".write(to: secondMatchURL, atomically: true, encoding: .utf8)

        let visibleItems = try FileSystemService().search(
            in: temporaryDirectory,
            query: "target",
            includingHidden: false,
            foldersFirst: true,
            limit: 10
        )

        XCTAssertEqual(visibleItems.map(\.name), ["target-a.txt", "target-b.txt"])

        let limitedItems = try FileSystemService().search(
            in: temporaryDirectory,
            query: "target",
            includingHidden: true,
            foldersFirst: true,
            limit: 1
        )

        XCTAssertEqual(limitedItems.count, 1)
    }

    func testContentsTreatsSymbolicLinksToFoldersAsOpenableFolders() throws {
        let targetURL = temporaryDirectory.appendingPathComponent("Target", isDirectory: true)
        let symlinkURL = temporaryDirectory.appendingPathComponent("Target Link", isDirectory: true)
        let fileURL = temporaryDirectory.appendingPathComponent("notes.txt")

        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: targetURL)
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let items = try FileSystemService().contents(of: temporaryDirectory)

        XCTAssertEqual(items.map(\.name), ["Target", "Target Link", "notes.txt"])
        XCTAssertEqual(items.first { $0.name == "Target Link" }?.kind, .folder)
        XCTAssertTrue(items.first { $0.name == "Target Link" }?.canOpenAsFolder ?? false)
    }

    @MainActor
    func testContentsHandlesFiveThousandFilesWithBenchmarkEvidence() throws {
        let fileManager = FileManager.default

        for index in 0..<5_000 {
            let fileURL = temporaryDirectory.appendingPathComponent("file-\(String(format: "%04d", index)).txt")
            XCTAssertTrue(fileManager.createFile(atPath: fileURL.path, contents: Data("x".utf8)))
        }

        let start = ContinuousClock.now
        let items = try FileSystemService().contents(of: temporaryDirectory)
        let elapsed = start.duration(to: ContinuousClock.now)
        let elapsedSeconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000

        XCTContext.runActivity(named: "Loaded \(items.count) files in \(String(format: "%.3f", elapsedSeconds)) seconds") { _ in
            XCTAssertEqual(items.count, 5_000)
            XCTAssertLessThan(elapsedSeconds, 0.3)
        }
    }

    @MainActor
    func testContentsHandlesFiveThousandMixedHiddenFilesWithBenchmarkEvidence() throws {
        let fileManager = FileManager.default

        for index in 0..<2_500 {
            let visibleURL = temporaryDirectory.appendingPathComponent("visible-\(String(format: "%04d", index)).txt")
            let hiddenURL = temporaryDirectory.appendingPathComponent(".hidden-\(String(format: "%04d", index)).txt")
            XCTAssertTrue(fileManager.createFile(atPath: visibleURL.path, contents: Data("x".utf8)))
            XCTAssertTrue(fileManager.createFile(atPath: hiddenURL.path, contents: Data("x".utf8)))
        }

        let visibleOnlyStart = ContinuousClock.now
        let visibleOnlyItems = try FileSystemService().contents(of: temporaryDirectory)
        let visibleOnlyElapsed = visibleOnlyStart.duration(to: ContinuousClock.now)
        let visibleOnlySeconds = Double(visibleOnlyElapsed.components.seconds)
            + Double(visibleOnlyElapsed.components.attoseconds) / 1_000_000_000_000_000_000

        let includingHiddenStart = ContinuousClock.now
        let includingHiddenItems = try FileSystemService().contents(of: temporaryDirectory, includingHidden: true)
        let includingHiddenElapsed = includingHiddenStart.duration(to: ContinuousClock.now)
        let includingHiddenSeconds = Double(includingHiddenElapsed.components.seconds)
            + Double(includingHiddenElapsed.components.attoseconds) / 1_000_000_000_000_000_000

        XCTContext.runActivity(named: "Loaded hidden toggle folders in \(String(format: "%.3f", includingHiddenSeconds)) seconds") { _ in
            XCTAssertEqual(visibleOnlyItems.count, 2_500)
            XCTAssertEqual(includingHiddenItems.count, 5_000)
            XCTAssertLessThan(visibleOnlySeconds, 0.3)
            XCTAssertLessThan(includingHiddenSeconds, 0.3)
        }
    }

    @MainActor
    func testSearchHandlesFiveThousandFilesWithBenchmarkEvidence() throws {
        let fileManager = FileManager.default

        for index in 0..<5_000 {
            let fileURL = temporaryDirectory.appendingPathComponent("report-\(String(format: "%04d", index)).txt")
            XCTAssertTrue(fileManager.createFile(atPath: fileURL.path, contents: Data("x".utf8)))
        }

        let start = ContinuousClock.now
        let items = try FileSystemService().search(
            in: temporaryDirectory,
            query: "report",
            includingHidden: false,
            foldersFirst: true,
            limit: 5_000
        )
        let elapsed = start.duration(to: ContinuousClock.now)
        let elapsedSeconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000

        XCTContext.runActivity(named: "Searched \(items.count) files in \(String(format: "%.3f", elapsedSeconds)) seconds") { _ in
            XCTAssertEqual(items.count, 5_000)
            XCTAssertLessThan(elapsedSeconds, 0.3)
        }
    }
}
