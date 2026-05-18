import AppKit
import Darwin
import XCTest
@testable import BetterFiles

@MainActor
final class BrowserStoreTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var userDefaults: UserDefaults!
    private var userDefaultsSuiteName: String!

    override func setUp() async throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BetterFilesStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        userDefaultsSuiteName = "BetterFilesStoreTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: userDefaultsSuiteName)
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
    }

    override func tearDown() async throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        if let userDefaults {
            userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
        }
    }

    func testBundleDeclaresProtectedFolderUsageDescriptions() {
        let info = Bundle.main.infoDictionary ?? [:]
        let keys = [
            "NSDesktopFolderUsageDescription",
            "NSDocumentsFolderUsageDescription",
            "NSDownloadsFolderUsageDescription",
            "NSNetworkVolumesUsageDescription",
            "NSRemovableVolumesUsageDescription"
        ]

        for key in keys {
            let value = info[key] as? String
            XCTAssertEqual(value?.contains("browse"), true, "\(key) should describe file-manager access")
            XCTAssertEqual(value?.contains("manage"), true, "\(key) should describe file-manager access")
        }
    }

    func testAccessRecoverySuggestsFullDiskAccessForPermissionErrors() {
        XCTAssertTrue(
            FileAccessRecoveryResolver.shouldSuggestFullDiskAccess(
                for: "Could not read /Users/leo/Documents: Operation not permitted"
            )
        )
        XCTAssertTrue(
            FileAccessRecoveryResolver.shouldSuggestFullDiskAccess(
                for: "Could not read /Volumes/Drive: Permission denied"
            )
        )
        XCTAssertFalse(
            FileAccessRecoveryResolver.shouldSuggestFullDiskAccess(
                for: "Path does not exist: /missing/folder"
            )
        )
    }

    func testPreferencesPersistAcrossStoreInstances() {
        let firstStore = makeStore()
        firstStore.showHiddenFiles = true
        firstStore.foldersFirst = false
        firstStore.kindFilter = .files
        firstStore.typeFilter = FileTypeFilter(rawValue: "pdf")
        firstStore.dateFilter = .last7Days
        firstStore.sizeFilter = .oneTo100MB
        firstStore.sortField = .size
        firstStore.sortAscending = false
        firstStore.groupField = .kind
        firstStore.showFileExtensions = false
        firstStore.compactView = true
        firstStore.showsNavigationPane = false
        firstStore.showsDetailPanel = false
        firstStore.showsPreviewPanel = true
        firstStore.showsItemCheckboxes = true
        firstStore.showsKindColumn = false
        firstStore.showsSizeColumn = false
        firstStore.showsModifiedColumn = true
        firstStore.showsCreatedColumn = false
        firstStore.showsAccessedColumn = true
        firstStore.showsPermissionsColumn = true
        firstStore.viewMode = .tiles

        let secondStore = makeStore()

        XCTAssertTrue(secondStore.showHiddenFiles)
        XCTAssertFalse(secondStore.foldersFirst)
        XCTAssertEqual(secondStore.kindFilter, .files)
        XCTAssertEqual(secondStore.typeFilter, FileTypeFilter(rawValue: "pdf"))
        XCTAssertEqual(secondStore.dateFilter, .last7Days)
        XCTAssertEqual(secondStore.sizeFilter, .oneTo100MB)
        XCTAssertEqual(secondStore.sortField, .size)
        XCTAssertFalse(secondStore.sortAscending)
        XCTAssertEqual(secondStore.groupField, .kind)
        XCTAssertFalse(secondStore.showFileExtensions)
        XCTAssertTrue(secondStore.compactView)
        XCTAssertFalse(secondStore.showsNavigationPane)
        XCTAssertFalse(secondStore.showsDetailPanel)
        XCTAssertTrue(secondStore.showsPreviewPanel)
        XCTAssertTrue(secondStore.showsItemCheckboxes)
        XCTAssertFalse(secondStore.showsKindColumn)
        XCTAssertFalse(secondStore.showsSizeColumn)
        XCTAssertTrue(secondStore.showsModifiedColumn)
        XCTAssertFalse(secondStore.showsCreatedColumn)
        XCTAssertTrue(secondStore.showsAccessedColumn)
        XCTAssertTrue(secondStore.showsPermissionsColumn)
        XCTAssertEqual(secondStore.viewMode, .tiles)
    }

    func testFlushPendingPreferencesWritesStickyViewOptionsImmediately() {
        let store = makeStore(service: FileSystemService())
        store.showHiddenFiles = true
        store.showFileExtensions = false
        store.compactView = true
        store.showsNavigationPane = false
        store.viewMode = .tiles

        XCTAssertNil(userDefaults.object(forKey: "BetterFiles.showHiddenFiles"))
        XCTAssertNil(userDefaults.object(forKey: "BetterFiles.viewMode"))
        XCTAssertNil(userDefaults.object(forKey: "BetterFiles.showsNavigationPane"))

        store.flushPendingPreferences()

        XCTAssertTrue(userDefaults.bool(forKey: "BetterFiles.showHiddenFiles"))
        XCTAssertFalse(userDefaults.bool(forKey: "BetterFiles.showFileExtensions"))
        XCTAssertTrue(userDefaults.bool(forKey: "BetterFiles.compactView"))
        XCTAssertFalse(userDefaults.bool(forKey: "BetterFiles.showsNavigationPane"))
        XCTAssertEqual(userDefaults.string(forKey: "BetterFiles.viewMode"), FileViewMode.tiles.rawValue)
    }

    func testSidebarExpandedPathsPersistDeduplicateAndCollapse() {
        let firstStore = makeStore()
        let projectsPath = temporaryDirectory.appendingPathComponent("Projects", isDirectory: true).path
        let downloadsPath = temporaryDirectory.appendingPathComponent("Downloads", isDirectory: true).path

        firstStore.setSidebarExpandedPath(projectsPath, isExpanded: true)
        firstStore.setSidebarExpandedPath(downloadsPath, isExpanded: true)
        firstStore.setSidebarExpandedPath(projectsPath, isExpanded: true)
        firstStore.setSidebarExpandedPath(downloadsPath, isExpanded: false)

        let secondStore = makeStore()

        XCTAssertEqual(secondStore.sidebarExpandedPaths, [projectsPath])
    }

    func testRestoringManySidebarExpandedPathsStaysUnderLaunchBudget() {
        let paths = (0..<200).flatMap { index in
            [
                temporaryDirectory.appendingPathComponent("Folder-\(index)", isDirectory: true).path,
                temporaryDirectory.appendingPathComponent("Folder-\(index)", isDirectory: true).path
            ]
        }
        userDefaults.set(paths, forKey: "BetterFiles.sidebarExpandedPaths")

        var store: BrowserStore?
        let elapsed = elapsedSeconds {
            store = makeStore()
        }

        XCTAssertEqual(store?.sidebarExpandedPaths.count, 80)
        XCTAssertEqual(store?.sidebarExpandedPaths.first, temporaryDirectory.appendingPathComponent("Folder-0", isDirectory: true).path)
        XCTAssertEqual(store?.sidebarExpandedPaths.last, temporaryDirectory.appendingPathComponent("Folder-79", isDirectory: true).path)
        XCTAssertLessThan(elapsed, 0.3)
    }

    func testSavedFolderViewSettingsPersistAndApplyOnlyToThatFolder() throws {
        let otherDirectory = temporaryDirectory.appendingPathComponent("Other", isDirectory: true)
        try FileManager.default.createDirectory(at: otherDirectory, withIntermediateDirectories: true)

        let firstStore = makeStore()
        firstStore.viewMode = .tiles
        firstStore.sortField = .size
        firstStore.sortAscending = false
        firstStore.groupField = .kind
        firstStore.foldersFirst = false
        firstStore.showFileExtensions = false
        firstStore.compactView = true
        firstStore.showsDetailPanel = true
        firstStore.showsPreviewPanel = true
        firstStore.showsItemCheckboxes = true
        firstStore.showsKindColumn = false
        firstStore.showsSizeColumn = false
        firstStore.showsModifiedColumn = false
        firstStore.showsCreatedColumn = false
        firstStore.showsAccessedColumn = false
        firstStore.showsPermissionsColumn = false
        firstStore.saveCurrentFolderViewSettings()

        XCTAssertTrue(firstStore.currentFolderHasSavedView)

        let secondStore = makeStore()
        secondStore.open(otherDirectory)
        secondStore.viewMode = .details
        secondStore.sortField = .name
        secondStore.sortAscending = true
        secondStore.groupField = .none
        secondStore.foldersFirst = true
        secondStore.showFileExtensions = true
        secondStore.compactView = false
        secondStore.showsDetailPanel = false
        secondStore.showsPreviewPanel = false
        secondStore.showsItemCheckboxes = false
        secondStore.showsKindColumn = true
        secondStore.showsSizeColumn = true
        secondStore.showsModifiedColumn = true
        secondStore.showsCreatedColumn = true
        secondStore.showsAccessedColumn = true
        secondStore.showsPermissionsColumn = true

        XCTAssertFalse(secondStore.currentFolderHasSavedView)

        secondStore.open(temporaryDirectory)

        XCTAssertTrue(secondStore.currentFolderHasSavedView)
        XCTAssertEqual(secondStore.viewMode, .tiles)
        XCTAssertEqual(secondStore.sortField, .size)
        XCTAssertFalse(secondStore.sortAscending)
        XCTAssertEqual(secondStore.groupField, .kind)
        XCTAssertFalse(secondStore.foldersFirst)
        XCTAssertFalse(secondStore.showFileExtensions)
        XCTAssertTrue(secondStore.compactView)
        XCTAssertTrue(secondStore.showsDetailPanel)
        XCTAssertTrue(secondStore.showsPreviewPanel)
        XCTAssertTrue(secondStore.showsItemCheckboxes)
        XCTAssertFalse(secondStore.showsKindColumn)
        XCTAssertFalse(secondStore.showsSizeColumn)
        XCTAssertFalse(secondStore.showsModifiedColumn)
        XCTAssertFalse(secondStore.showsCreatedColumn)
        XCTAssertFalse(secondStore.showsAccessedColumn)
        XCTAssertFalse(secondStore.showsPermissionsColumn)
    }

    func testClearSavedFolderViewSettingsRemovesFolderOverride() {
        let firstStore = makeStore()
        firstStore.viewMode = .tiles
        firstStore.groupField = .kind
        firstStore.saveCurrentFolderViewSettings()

        XCTAssertTrue(firstStore.currentFolderHasSavedView)

        firstStore.clearCurrentFolderViewSettings()

        XCTAssertFalse(firstStore.currentFolderHasSavedView)

        let secondStore = makeStore()
        secondStore.viewMode = .details
        secondStore.groupField = .none
        secondStore.open(temporaryDirectory)

        XCTAssertFalse(secondStore.currentFolderHasSavedView)
        XCTAssertEqual(secondStore.viewMode, .details)
        XCTAssertEqual(secondStore.groupField, .none)
    }

    func testDefaultLayoutPrioritizesWorkspaceOverInspector() {
        let store = makeStore(service: FileSystemService())

        XCTAssertFalse(store.showsDetailPanel)
        XCTAssertEqual(store.viewMode, .details)
    }

    func testFileOperationSummaryReportsRunningProgressAndCancellation() {
        let operation = FileOperationSummary(
            id: UUID(),
            label: "Copied",
            itemCount: 4,
            completedItemCount: 1,
            elapsedSeconds: nil,
            isCancelling: false
        )

        XCTAssertEqual(operation.statusLabel, "Copying 1/4 items")
        XCTAssertEqual(operation.progressFraction, 0.25)

        let cancelling = operation.cancelling()
        XCTAssertTrue(cancelling.isCancelling)
        XCTAssertEqual(cancelling.statusLabel, "Cancelling 1/4 items")

        let finished = operation.reportingCompleted(4).finished(elapsedSeconds: 0.012)
        XCTAssertFalse(finished.isRunning)
        XCTAssertEqual(finished.completedItemCount, 4)
        XCTAssertEqual(finished.statusLabel, "Copied 4 items in 12 ms")
    }

    func testCancelActiveFileOperationIsSafeWithoutRunningOperation() {
        let store = makeStore(service: FileSystemService())

        XCTAssertNil(store.activeOperation)
        store.cancelActiveFileOperation()
        XCTAssertNil(store.activeOperation)
    }

    func testShowAllDetailsColumnsRestoresDefaultColumnSet() {
        let store = makeStore(service: FileSystemService())
        store.showsKindColumn = false
        store.showsSizeColumn = false
        store.showsModifiedColumn = false
        store.showsCreatedColumn = false
        store.showsAccessedColumn = false
        store.showsPermissionsColumn = false

        XCTAssertFalse(store.usesDefaultDetailsColumns)

        store.showAllDetailsColumns()

        XCTAssertTrue(store.usesDefaultDetailsColumns)
        XCTAssertTrue(store.showsKindColumn)
        XCTAssertTrue(store.showsSizeColumn)
        XCTAssertTrue(store.showsModifiedColumn)
        XCTAssertTrue(store.showsCreatedColumn)
        XCTAssertTrue(store.showsAccessedColumn)
        XCTAssertTrue(store.showsPermissionsColumn)
    }

    func testFocusCommandsRequestAddressAndSearchFields() {
        let store = makeStore(service: FileSystemService())
        store.pathInput = "/definitely/not/current"

        store.focusAddressBar()

        let addressRequest = store.focusRequest
        XCTAssertEqual(addressRequest?.target, .addressBar)
        XCTAssertEqual(store.pathInput, temporaryDirectory.standardizedFileURL.path)

        store.focusSearchField()

        XCTAssertEqual(store.focusRequest?.target, .searchField)
        XCTAssertNotEqual(store.focusRequest?.id, addressRequest?.id)
    }

    func testClearSearchAndContentFiltersPreservesLayoutPreferences() {
        let store = makeStore(service: FileSystemService())
        store.query = "report"
        store.kindFilter = .files
        store.typeFilter = FileTypeFilter(rawValue: "pdf")
        store.dateFilter = .last7Days
        store.sizeFilter = .over100MB
        store.showHiddenFiles = true
        store.showFileExtensions = false
        store.compactView = true
        store.groupField = .size
        store.foldersFirst = false
        store.showsItemCheckboxes = true
        store.showsNavigationPane = false
        store.showsDetailPanel = true
        store.showsPreviewPanel = true

        XCTAssertTrue(store.hasActiveContentFilters)

        store.clearSearchAndContentFilters()

        XCTAssertFalse(store.hasActiveContentFilters)
        XCTAssertEqual(store.query, "")
        XCTAssertEqual(store.kindFilter, .all)
        XCTAssertEqual(store.typeFilter, .any)
        XCTAssertEqual(store.dateFilter, .any)
        XCTAssertEqual(store.sizeFilter, .any)
        XCTAssertTrue(store.showHiddenFiles)
        XCTAssertFalse(store.showFileExtensions)
        XCTAssertTrue(store.compactView)
        XCTAssertEqual(store.groupField, .size)
        XCTAssertFalse(store.foldersFirst)
        XCTAssertTrue(store.showsItemCheckboxes)
        XCTAssertFalse(store.showsNavigationPane)
        XCTAssertTrue(store.showsDetailPanel)
        XCTAssertTrue(store.showsPreviewPanel)
    }

    func testNavigationPaneToggleDoesNotReloadFilesystem() async {
        let service = CountingFileSystemService()
        let store = makeStore(service: service)
        await waitForTabLoad(store)
        let initialCallCount = service.callCount

        store.showsNavigationPane = false
        store.showsNavigationPane = true
        try? await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(service.callCount, initialCallCount)
    }

    func testFilterSummaryOnlyAppearsForContentFiltersAndGrouping() {
        let store = makeStore()

        XCTAssertFalse(store.hasVisibleFilterSummary)

        store.showHiddenFiles = true

        XCTAssertTrue(store.hasVisibleFilterSummary)

        store.showHiddenFiles = false
        store.showFileExtensions = false

        XCTAssertFalse(store.hasVisibleFilterSummary)

        store.showFileExtensions = true
        store.compactView = true
        store.foldersFirst = false
        store.showsItemCheckboxes = true
        store.showsDetailPanel = true
        store.showsPreviewPanel = true

        XCTAssertFalse(store.hasVisibleFilterSummary)

        store.typeFilter = FileTypeFilter(rawValue: "txt")

        XCTAssertTrue(store.hasVisibleFilterSummary)

        store.typeFilter = .any
        store.groupField = .kind

        XCTAssertTrue(store.hasVisibleFilterSummary)
    }

    func testPropertiesCommandShowsInspectorPanelForSelection() {
        let store = makeStore()
        let file = makeItem(name: "report.txt", kind: .file, byteCount: 42)
        store.tabs[0].items = [file]
        store.selectedItemIDs = [file.id]
        store.showsDetailPanel = false

        store.showPropertiesForSelection()

        XCTAssertTrue(store.showsDetailPanel)
    }

    func testPropertiesCommandDoesNothingWithoutSelection() {
        let store = makeStore()
        store.showsDetailPanel = false

        store.showPropertiesForSelection()

        XCTAssertFalse(store.showsDetailPanel)
    }

    func testTerminalTargetUsesCurrentFolderWithoutSelection() {
        let store = makeStore()

        XCTAssertEqual(store.terminalTargetURLForSelection, temporaryDirectory.standardizedFileURL)
        XCTAssertTrue(store.canOpenSelectionInTerminal)
    }

    func testTerminalTargetUsesSelectedFolderOrFileParent() {
        let store = makeStore()
        let folder = makeItem(name: "Projects", kind: .folder, byteCount: nil)
        let file = makeItem(name: "notes.txt", kind: .file, byteCount: 12)
        store.tabs[0].items = [folder, file]

        store.selectedItemIDs = [folder.id]
        XCTAssertEqual(store.terminalTargetURLForSelection, folder.url.standardizedFileURL)

        store.selectedItemIDs = [file.id]
        XCTAssertEqual(store.terminalTargetURLForSelection, temporaryDirectory.standardizedFileURL)
    }

    func testInspectorSummaryDescribesSingleSelection() throws {
        let store = makeStore()
        let file = makeItem(name: "report.final.pdf", kind: .file, byteCount: 1024, isHidden: true, posixPermissions: 0o444)
        try Data("pdf".utf8).write(to: file.url)
        store.tabs[0].items = [file]
        store.selectedItemIDs = [file.id]

        let summary = store.inspectorSummary

        XCTAssertEqual(summary?.title, "report.final.pdf")
        XCTAssertEqual(summary?.subtitle, "File")
        XCTAssertEqual(summary?.itemCount, 1)
        XCTAssertEqual(summary?.fileCount, 1)
        XCTAssertEqual(summary?.sizeLabel, "1 KB")
        XCTAssertEqual(summary?.hiddenLabel, "Yes")
        XCTAssertEqual(summary?.lockedLabel, "No")
        XCTAssertEqual(summary?.permissionsLabel, "444 (Read only)")
        XCTAssertNotEqual(summary?.accessedLabel, "--")
        XCTAssertEqual(summary?.tagsLabel, "None")
        XCTAssertFalse(summary?.ownerLabel?.isEmpty ?? true)
        XCTAssertFalse(summary?.groupLabel?.isEmpty ?? true)
        XCTAssertTrue(summary?.accessLabel?.contains("Read") ?? false)
        XCTAssertEqual(summary?.pathLabel, file.url.path)
        XCTAssertEqual(summary?.parentPathLabel, temporaryDirectory.path)
        XCTAssertFalse(summary?.defaultApplication?.displayName.isEmpty ?? true)
        XCTAssertEqual(summary?.defaultApplication?.url.pathExtension, "app")
    }

    func testInspectorSummaryShowsFinderTagsForSingleSelection() throws {
        let store = makeStore()
        let taggedURL = temporaryDirectory.appendingPathComponent("tagged.txt")
        try Data("tagged".utf8).write(to: taggedURL)

        try setFinderTags(["Client", "Review"], for: taggedURL)

        let file = makeItem(name: "tagged.txt", kind: .file, byteCount: 6)
        store.tabs[0].items = [file]
        store.selectedItemIDs = [file.id]

        XCTAssertEqual(store.inspectorSummary?.tagsLabel, "Client, Review")
    }

    func testInspectorSummaryShowsExtendedAttributesForSingleSelection() throws {
        let store = makeStore()
        let fileURL = temporaryDirectory.appendingPathComponent("metadata.txt")
        try Data("metadata".utf8).write(to: fileURL)

        let attributeName = "dev.leo.better-files.test"
        let value = Array("present".utf8)
        let setResult = value.withUnsafeBytes { buffer in
            setxattr(fileURL.path, attributeName, buffer.baseAddress, buffer.count, 0, 0)
        }
        XCTAssertEqual(setResult, 0)

        let file = makeItem(name: "metadata.txt", kind: .file, byteCount: 8)
        store.tabs[0].items = [file]
        store.selectedItemIDs = [file.id]

        XCTAssertTrue(store.inspectorSummary?.extendedAttributesLabel?.contains(attributeName) ?? false)
    }

    func testSetSelectedItemsLockedUpdatesFileFlags() async throws {
        let store = makeStore()
        let fileURL = temporaryDirectory.appendingPathComponent("lock-me.txt")
        try Data("lock".utf8).write(to: fileURL)

        store.tabs[0].items = [makeItem(name: "lock-me.txt", kind: .file, byteCount: 4)]
        store.selectedItemIDs = [fileURL.path]

        XCTAssertTrue(store.setSelectedItemsLocked(true))
        await waitForFileOperation(store)
        var lockedStat = stat()
        XCTAssertEqual(lstat(fileURL.path, &lockedStat), 0)
        XCTAssertNotEqual(lockedStat.st_flags & UInt32(UF_IMMUTABLE), 0)
        assertPerformanceEvent(in: store, label: "Locked", itemCount: 1)

        store.tabs[0].items = [makeItem(name: "lock-me.txt", kind: .file, byteCount: 4, isLocked: true)]
        store.selectedItemIDs = [fileURL.path]
        XCTAssertEqual(store.inspectorSummary?.lockedLabel, "Yes")

        XCTAssertTrue(store.setSelectedItemsLocked(false))
        await waitForFileOperation(store)
        var unlockedStat = stat()
        XCTAssertEqual(lstat(fileURL.path, &unlockedStat), 0)
        XCTAssertEqual(unlockedStat.st_flags & UInt32(UF_IMMUTABLE), 0)
        assertPerformanceEvent(in: store, label: "Unlocked", itemCount: 1)
    }

    func testClearSelectedItemsAccessControlRemovesExtendedACL() async throws {
        let store = makeStore(service: FileSystemService())
        let fileURL = temporaryDirectory.appendingPathComponent("acl-protected.txt")
        try Data("acl".utf8).write(to: fileURL)
        try runChmod(["+a", "everyone deny delete", fileURL.path])
        defer {
            try? runChmod(["-N", fileURL.path])
        }

        let file = makeItem(name: "acl-protected.txt", kind: .file, byteCount: 3)
        store.tabs[0].items = [file]
        store.selectedItemIDs = [file.id]

        XCTAssertTrue(extendedACLText(at: fileURL)?.contains("everyone") ?? false)
        XCTAssertTrue(store.inspectorSummary?.accessControlLabel?.contains("everyone") ?? false)

        XCTAssertTrue(store.clearSelectedItemsAccessControl())
        await waitForFileOperation(store)

        XCTAssertNil(extendedACLText(at: fileURL))
        XCTAssertEqual(store.selectedItemIDs, [fileURL.path])
        assertPerformanceEvent(in: store, label: "Cleared Access Control", itemCount: 1)
    }

    func testSetSelectedItemsFinderTagsUpdatesAndClearsTags() async throws {
        let store = makeStore(service: FileSystemService())
        let fileURL = temporaryDirectory.appendingPathComponent("tag-me.txt")
        try Data("tags".utf8).write(to: fileURL)

        store.tabs[0].items = [makeItem(name: "tag-me.txt", kind: .file, byteCount: 4)]
        store.selectedItemIDs = [fileURL.path]

        XCTAssertTrue(store.setSelectedItemsFinderTags([" Client ", "Review", "client", ""]))
        await waitForFileOperation(store)

        XCTAssertEqual(try finderTags(for: fileURL), ["Client", "Review"])
        XCTAssertEqual(store.selectedItemIDs, [fileURL.path])
        XCTAssertEqual(store.lastOperationSummary?.label, "Tagged")
        assertPerformanceEvent(in: store, label: "Tagged", itemCount: 1)

        XCTAssertTrue(store.setSelectedItemsFinderTags([]))
        await waitForFileOperation(store)

        XCTAssertEqual(try finderTags(for: fileURL), [])
        XCTAssertEqual(store.selectedItemIDs, [fileURL.path])
        XCTAssertEqual(store.lastOperationSummary?.label, "Cleared Tags")
        assertPerformanceEvent(in: store, label: "Cleared Tags", itemCount: 1)
    }

    func testSetSelectedItemsFinderTagsReturnsFalseWithoutSelection() {
        let store = makeStore(service: FileSystemService())

        XCTAssertFalse(store.setSelectedItemsFinderTags(["Review"]))
        XCTAssertNil(store.activeOperation)
    }

    func testInspectorSummaryDescribesMultipleSelection() {
        let store = makeStore()
        let folder = makeItem(name: "Assets", kind: .folder, byteCount: nil)
        let package = makeItem(name: "Project.xcodeproj", kind: .package, byteCount: 2048)
        let file = makeItem(name: "notes.txt", kind: .file, byteCount: 1024)
        store.tabs[0].items = [folder, package, file]
        store.selectedItemIDs = [folder.id, package.id, file.id]

        let summary = store.inspectorSummary

        XCTAssertEqual(summary?.title, "3 items")
        XCTAssertEqual(summary?.subtitle, "Multiple selection")
        XCTAssertEqual(summary?.folderCount, 1)
        XCTAssertEqual(summary?.fileCount, 1)
        XCTAssertEqual(summary?.packageCount, 1)
        XCTAssertEqual(summary?.knownByteCount, 3072)
        XCTAssertEqual(summary?.sizeLabel, "3 KB")
        XCTAssertNil(summary?.pathLabel)
        XCTAssertEqual(summary?.parentPathLabel, temporaryDirectory.path)
        XCTAssertNil(summary?.defaultApplication)
    }

    func testInspectorDefaultApplicationLookupIsCachedForSelection() throws {
        let store = makeStore()
        let file = makeItem(name: "brief.pdf", kind: .file, byteCount: 1024)
        try Data("pdf".utf8).write(to: file.url)
        store.tabs[0].items = [file]
        store.selectedItemIDs = [file.id]

        let initialApplication = store.inspectorSummary?.defaultApplication
        XCTAssertFalse(initialApplication?.displayName.isEmpty ?? true)

        let elapsed = elapsedSeconds {
            for _ in 0..<1_000 {
                XCTAssertEqual(store.inspectorSummary?.defaultApplication, initialApplication)
            }
        }

        XCTAssertLessThan(elapsed, 0.15)
    }

    func testOpenWithApplicationsForSelectionUsesCachedApplicationList() throws {
        let store = makeStore()
        let file = makeItem(name: "brief.pdf", kind: .file, byteCount: 1024)
        try Data("pdf".utf8).write(to: file.url)
        store.tabs[0].items = [file]
        store.selectedItemIDs = [file.id]

        let initialApplications = store.openWithApplicationsForSelection(limit: 8)
        XCTAssertFalse(initialApplications.isEmpty)
        XCTAssertTrue(initialApplications.allSatisfy { !$0.displayName.isEmpty })

        let elapsed = elapsedSeconds {
            for _ in 0..<1_000 {
                XCTAssertEqual(store.openWithApplicationsForSelection(limit: 8), initialApplications)
            }
        }

        XCTAssertLessThan(elapsed, 0.15)
    }

    func testDisplayNameCanHideFileExtensionsWithoutChangingFilesystemNames() {
        let store = makeStore()
        let file = makeItem(name: "report.final.pdf", kind: .file, byteCount: 100)
        let folder = makeItem(name: "Project.archive", kind: .folder, byteCount: nil)
        store.tabs[0].items = [file, folder]

        XCTAssertEqual(store.displayName(for: file), "report.final.pdf")
        XCTAssertEqual(store.displayName(for: folder), "Project.archive")

        store.showFileExtensions = false

        XCTAssertEqual(store.displayName(for: file), "report.final")
        XCTAssertEqual(store.displayName(for: folder), "Project.archive")
        XCTAssertEqual(store.visibleItems.map(\.name), ["Project.archive", "report.final.pdf"])
    }

    func testVisibleItemsApplyKindFilterAndSortOrder() {
        let store = makeStore()
        store.tabs[0].items = [
            makeItem(name: "b.txt", kind: .file, byteCount: 200),
            makeItem(name: "z Folder", kind: .folder, byteCount: nil),
            makeItem(name: "a.txt", kind: .file, byteCount: 100)
        ]

        store.kindFilter = .files
        store.sortField = .size
        store.sortAscending = false

        XCTAssertEqual(store.visibleItems.map(\.name), ["b.txt", "a.txt"])
    }

    func testVisibleItemsApplyDynamicTypeFilterWithoutReloadingFilesystem() {
        let store = makeStore()
        store.tabs[0].items = [
            makeItem(name: "report.pdf", kind: .file, byteCount: 200),
            makeItem(name: "notes.txt", kind: .file, byteCount: 100),
            makeItem(name: "README", kind: .file, byteCount: 50),
            makeItem(name: "Project", kind: .folder, byteCount: nil)
        ]
        store.tabs[0].isLoading = false

        XCTAssertEqual(store.availableTypeFilters.map(\.label), ["Any Type", "No Extension", ".pdf", ".txt"])

        store.typeFilter = FileTypeFilter(rawValue: "pdf")

        XCTAssertFalse(store.isLoading)
        XCTAssertEqual(store.visibleItems.map(\.name), ["report.pdf"])

        store.typeFilter = .noExtension

        XCTAssertFalse(store.isLoading)
        XCTAssertEqual(store.visibleItems.map(\.name), ["README"])
    }

    func testAvailableTypeFiltersCacheUpdatesForSelectionAndFolderChanges() {
        let store = makeStore()
        store.tabs[0].items = [
            makeItem(name: "report.pdf", kind: .file, byteCount: 200),
            makeItem(name: "notes.txt", kind: .file, byteCount: 100)
        ]

        XCTAssertEqual(store.availableTypeFilters.map(\.rawValue), ["", "pdf", "txt"])
        XCTAssertEqual(store.availableTypeFilters.map(\.rawValue), ["", "pdf", "txt"])

        store.typeFilter = FileTypeFilter(rawValue: "md")
        XCTAssertEqual(store.availableTypeFilters.map(\.rawValue), ["", "pdf", "txt", "md"])

        store.tabs[0].items = [
            makeItem(name: "clip.mov", kind: .file, byteCount: 200),
            makeItem(name: "scratch", kind: .file, byteCount: 0)
        ]

        XCTAssertEqual(store.availableTypeFilters.map(\.rawValue), ["", FileTypeFilter.noExtension.rawValue, "mov", "md"])
    }

    func testFoldersFirstToggleDoesNotReloadFilesystem() {
        let store = makeStore()
        store.tabs[0].items = [
            makeItem(name: "b.txt", kind: .file, byteCount: 200),
            makeItem(name: "z Folder", kind: .folder, byteCount: nil),
            makeItem(name: "a.txt", kind: .file, byteCount: 100)
        ]
        store.tabs[0].isLoading = false
        store.foldersFirst = true

        XCTAssertEqual(store.visibleItems.map(\.name), ["z Folder", "a.txt", "b.txt"])

        store.foldersFirst = false

        XCTAssertFalse(store.isLoading)
        XCTAssertEqual(store.items.count, 3)
        XCTAssertEqual(store.visibleItems.map(\.name), ["a.txt", "b.txt", "z Folder"])
    }

    func testVisibleItemsApplyDateAndSizeFilters() {
        let store = makeStore()
        let now = Date()
        store.tabs[0].items = [
            makeItem(name: "tiny.txt", kind: .file, byteCount: 20, modifiedAt: now),
            makeItem(name: "report.mov", kind: .file, byteCount: 12_000_000, modifiedAt: now),
            makeItem(name: "old.mov", kind: .file, byteCount: 12_000_000, modifiedAt: Date(timeIntervalSince1970: 1_500_000_000)),
            makeItem(name: "Folder", kind: .folder, byteCount: nil, modifiedAt: now)
        ]

        store.dateFilter = .last7Days
        store.sizeFilter = .oneTo100MB

        XCTAssertEqual(store.visibleItems.map(\.name), ["report.mov"])
    }

    func testVisibleItemsCanSortByCreatedDate() {
        let store = makeStore()
        store.tabs[0].items = [
            makeItem(name: "new.txt", kind: .file, byteCount: 10, createdAt: Date(timeIntervalSince1970: 1_700_000_000)),
            makeItem(name: "old.txt", kind: .file, byteCount: 10, createdAt: Date(timeIntervalSince1970: 1_500_000_000))
        ]

        store.sortField = .created
        store.sortAscending = true

        XCTAssertEqual(store.visibleItems.map(\.name), ["old.txt", "new.txt"])
    }

    func testVisibleItemsCanSortByAccessedDate() {
        let store = makeStore()
        store.tabs[0].items = [
            makeItem(name: "recent.txt", kind: .file, byteCount: 10, accessedAt: Date(timeIntervalSince1970: 1_800_000_000)),
            makeItem(name: "stale.txt", kind: .file, byteCount: 10, accessedAt: Date(timeIntervalSince1970: 1_400_000_000))
        ]

        store.sortField = .accessed
        store.sortAscending = true

        XCTAssertEqual(store.visibleItems.map(\.name), ["stale.txt", "recent.txt"])
    }

    func testMultipleSelectionReturnsSelectedItems() {
        let store = makeStore()
        store.tabs[0].items = [
            makeItem(name: "a.txt", kind: .file, byteCount: 100),
            makeItem(name: "b.txt", kind: .file, byteCount: 200),
            makeItem(name: "c.txt", kind: .file, byteCount: 300)
        ]

        store.selectedItemIDs = [
            temporaryDirectory.appendingPathComponent("a.txt").path,
            temporaryDirectory.appendingPathComponent("c.txt").path
        ]

        XCTAssertEqual(store.selectedItems.map(\.name), ["a.txt", "c.txt"])
        XCTAssertTrue(store.hasSelection)
    }

    func testSelectionStatusSummaryIncludesKnownSize() {
        let store = makeStore()
        let first = makeItem(name: "a.txt", kind: .file, byteCount: 100)
        let second = makeItem(name: "b.txt", kind: .file, byteCount: 300)
        store.tabs[0].items = [first, second]

        XCTAssertNil(store.selectionStatusSummary)

        store.selectedItemIDs = [first.id]

        XCTAssertEqual(store.selectionStatusSummary, "a.txt - 100 bytes")

        store.selectedItemIDs = [first.id, second.id]

        XCTAssertEqual(store.selectionStatusSummary, "2 items selected - 400 bytes")
    }

    func testSelectionCommandsUseVisibleItems() {
        let store = makeStore()
        store.tabs[0].items = [
            makeItem(name: "a.txt", kind: .file, byteCount: 100),
            makeItem(name: "Folder", kind: .folder, byteCount: nil),
            makeItem(name: "b.txt", kind: .file, byteCount: 200)
        ]
        store.kindFilter = .files

        store.selectAllVisibleItems()

        XCTAssertEqual(store.selectedItemIDs, Set(store.visibleItems.map(\.id)))

        let firstVisibleID = store.visibleItems[0].id
        store.selectedItemIDs = [firstVisibleID]
        store.invertSelection()

        XCTAssertEqual(store.selectedItemIDs, Set(store.visibleItems.dropFirst().map(\.id)))

        store.clearSelection()
        XCTAssertTrue(store.selectedItemIDs.isEmpty)
    }

    func testSetItemSelectionUpdatesSelectionSet() {
        let store = makeStore()
        let item = makeItem(name: "a.txt", kind: .file, byteCount: 100)
        store.tabs[0].items = [item]

        store.setItemSelection(item.id, isSelected: true)
        XCTAssertEqual(store.selectedItemIDs, [item.id])

        store.setItemSelection(item.id, isSelected: false)
        XCTAssertTrue(store.selectedItemIDs.isEmpty)
    }

    func testContextSelectionPreservesMultiSelectionWhenClickedItemIsSelected() {
        let store = makeStore()
        let first = makeItem(name: "a.txt", kind: .file, byteCount: 100)
        let second = makeItem(name: "b.txt", kind: .file, byteCount: 200)
        let third = makeItem(name: "c.txt", kind: .file, byteCount: 300)
        store.tabs[0].items = [first, second, third]
        store.selectedItemIDs = [first.id, second.id]

        XCTAssertEqual(store.contextSelectionIDs(for: second.id), [first.id, second.id])

        store.prepareContextSelection(for: second.id)

        XCTAssertEqual(store.selectedItemIDs, [first.id, second.id])
    }

    func testContextSelectionTargetsOnlyClickedItemWhenItIsOutsideSelection() {
        let store = makeStore()
        let first = makeItem(name: "a.txt", kind: .file, byteCount: 100)
        let second = makeItem(name: "b.txt", kind: .file, byteCount: 200)
        let third = makeItem(name: "c.txt", kind: .file, byteCount: 300)
        store.tabs[0].items = [first, second, third]
        store.selectedItemIDs = [first.id, second.id]

        XCTAssertEqual(store.contextSelectionIDs(for: third.id), [third.id])

        store.prepareContextSelection(for: third.id)

        XCTAssertEqual(store.selectedItemIDs, [third.id])
    }

    func testVisibleItemsRepeatedAccessUsesCachedProjectionForLargeFolders() {
        let store = makeStore()
        store.tabs[0].items = makeLargeItemSet()
        store.kindFilter = .all
        store.sortField = .name
        store.sortAscending = true

        XCTAssertEqual(store.visibleItems.count, 5_000)

        let elapsed = elapsedSeconds {
            for _ in 0..<1_000 {
                XCTAssertEqual(store.visibleItems.count, 5_000)
            }
        }

        XCTAssertLessThan(elapsed, 0.15)
    }

    func testSelectedItemsRepeatedAccessUsesCachedProjectionForLargeFolders() {
        let store = makeStore()
        store.tabs[0].items = makeLargeItemSet()
        store.selectedItemIDs = Set(store.items.prefix(2_500).map(\.id))

        XCTAssertEqual(store.selectedItems.count, 2_500)

        let elapsed = elapsedSeconds {
            for _ in 0..<1_000 {
                XCTAssertEqual(store.selectedItems.count, 2_500)
            }
        }

        XCTAssertLessThan(elapsed, 0.15)

        store.selectedItemIDs = Set(store.items.suffix(10).map(\.id))
        XCTAssertEqual(store.selectedItems.count, 10)
    }

    func testVisibleItemsInvalidatesCacheWhenQueryFilterOrSortChangesForLargeFolders() {
        let store = makeStore()
        store.tabs[0].items = makeLargeItemSet()

        _ = store.visibleItems

        let queryElapsed = elapsedSeconds {
            store.query = "Document 049"
            XCTAssertEqual(store.visibleItems.map(\.name), [
                "Document 0491.txt",
                "Document 0492.txt",
                "Document 0493.txt",
                "Document 0494.txt",
                "Document 0495.txt",
                "Document 0496.txt",
                "Document 0497.txt",
                "Document 0498.txt",
                "Document 0499.txt"
            ])
        }

        let filterElapsed = elapsedSeconds {
            store.query = ""
            store.kindFilter = .folders
            XCTAssertEqual(store.visibleItems.count, 500)
            XCTAssertTrue(store.visibleItems.allSatisfy(\.canOpenAsFolder))
        }

        let sortElapsed = elapsedSeconds {
            store.kindFilter = .files
            store.sortField = .size
            store.sortAscending = false
            XCTAssertEqual(store.visibleItems.first?.name, "Document 4999.txt")
            XCTAssertEqual(store.visibleItems.last?.name, "Document 0001.txt")
        }

        let typeElapsed = elapsedSeconds {
            store.typeFilter = FileTypeFilter(rawValue: "txt")
            XCTAssertEqual(store.visibleItems.count, 4_500)
        }

        let dateAndSizeElapsed = elapsedSeconds {
            store.dateFilter = .thisYear
            store.sizeFilter = .under1MB
            XCTAssertEqual(store.visibleItems.count, 4_500)
        }

        XCTAssertLessThan(queryElapsed, 0.30)
        XCTAssertLessThan(filterElapsed, 0.30)
        XCTAssertLessThan(sortElapsed, 0.30)
        XCTAssertLessThan(typeElapsed, 0.30)
        XCTAssertLessThan(dateAndSizeElapsed, 0.30)
    }

    func testLargeFolderFilterMenuChangesStayUnderInteractionBudget() {
        let store = makeStore()
        store.tabs[0].items = makeLargeItemSet()
        store.sortField = .name
        store.sortAscending = true

        XCTAssertEqual(store.visibleItems.count, 5_000)

        var projectedCounts: [Int] = []
        let elapsed = elapsedSeconds {
            for kindFilter in FileKindFilter.allCases {
                for typeFilter in store.availableTypeFilters {
                    for dateFilter in FileDateFilter.allCases {
                        for sizeFilter in FileSizeFilter.allCases {
                            store.kindFilter = kindFilter
                            store.typeFilter = typeFilter
                            store.dateFilter = dateFilter
                            store.sizeFilter = sizeFilter

                            projectedCounts.append(store.visibleItems.count)
                        }
                    }
                }
            }
        }

        XCTAssertEqual(projectedCounts.count, FileKindFilter.allCases.count * store.availableTypeFilters.count * FileDateFilter.allCases.count * FileSizeFilter.allCases.count)
        XCTAssertTrue(projectedCounts.contains(5_000))
        XCTAssertTrue(projectedCounts.contains(4_500))
        XCTAssertTrue(projectedCounts.contains(0))
        XCTAssertLessThan(elapsed, 0.30)
    }

    func testLargeFolderSelectionCommandsStayUnderInteractionBudget() {
        let store = makeStore()
        store.tabs[0].items = makeLargeItemSet()

        let selectAllElapsed = elapsedSeconds {
            store.selectAllVisibleItems()
            XCTAssertEqual(store.selectedItemIDs.count, 5_000)
        }

        let invertElapsed = elapsedSeconds {
            store.invertSelection()
            XCTAssertEqual(store.selectedItemIDs.count, 0)
        }

        let partialInvertElapsed = elapsedSeconds {
            store.selectedItemIDs = Set(store.visibleItems.prefix(2_500).map(\.id))
            store.invertSelection()
            XCTAssertEqual(store.selectedItemIDs.count, 2_500)
        }

        let clearElapsed = elapsedSeconds {
            store.clearSelection()
            XCTAssertTrue(store.selectedItemIDs.isEmpty)
        }

        XCTAssertLessThan(selectAllElapsed, 0.30)
        XCTAssertLessThan(invertElapsed, 0.30)
        XCTAssertLessThan(partialInvertElapsed, 0.30)
        XCTAssertLessThan(clearElapsed, 0.30)
    }

    func testLargeFolderViewPreferenceTogglesStayUnderInteractionBudget() {
        let store = makeStore()
        store.tabs[0].items = makeLargeItemSet()
        XCTAssertEqual(store.visibleItems.count, 5_000)

        let elapsed = elapsedSeconds {
            for _ in 0..<250 {
                let modes = FileViewMode.allCases
                let currentIndex = modes.firstIndex(of: store.viewMode) ?? 0
                store.viewMode = modes[(currentIndex + 1) % modes.count]
                let groupFields = FileGroupField.allCases
                let currentGroupIndex = groupFields.firstIndex(of: store.groupField) ?? 0
                store.groupField = groupFields[(currentGroupIndex + 1) % groupFields.count]
                store.showsItemCheckboxes.toggle()
                store.showsNavigationPane.toggle()
                store.showsDetailPanel.toggle()
                store.showsPreviewPanel.toggle()
                store.showsKindColumn.toggle()
                store.showsSizeColumn.toggle()
                store.showsModifiedColumn.toggle()
                store.showsCreatedColumn.toggle()
                store.showsAccessedColumn.toggle()
                store.showsPermissionsColumn.toggle()
                store.showFileExtensions.toggle()
                store.compactView.toggle()
                XCTAssertEqual(store.visibleItems.count, 5_000)
                XCTAssertFalse(store.visibleSections.isEmpty)
            }
        }

        XCTAssertLessThan(elapsed, 0.30)
    }

    func testLargeFolderStatusInspectorAndAddressStateStayUnderInteractionBudget() {
        let store = makeStore()
        store.tabs[0].items = makeLargeItemSet()
        store.selectedItemIDs = Set(store.items.prefix(2_500).map(\.id))
        store.pinnedDirectories = [
            temporaryDirectory.appendingPathComponent("Pinned", isDirectory: true),
            temporaryDirectory
        ]
        store.recentDirectories = [
            temporaryDirectory.appendingPathComponent("Recent", isDirectory: true),
            temporaryDirectory
        ]

        XCTAssertEqual(store.visibleItems.count, 5_000)
        XCTAssertEqual(store.selectedItems.count, 2_500)

        var selectionStatusSummary: String?
        var inspectorItemCount: Int?
        var pathComponentCount = 0
        var sidebarPathComponentCount = 0
        var addressLocationCount = 0
        let volumeSummary = store.currentVolumeStatusSummary

        let elapsed = elapsedSeconds {
            for _ in 0..<40 {
                selectionStatusSummary = store.selectionStatusSummary
                inspectorItemCount = store.inspectorSummary?.itemCount
                pathComponentCount = store.pathComponents.count
                sidebarPathComponentCount = store.sidebarPathComponents.count
                addressLocationCount = store.addressMenuLocations.count
                _ = store.currentVolumeStatusSummary?.statusLabel
            }
        }

        XCTAssertEqual(selectionStatusSummary, "2500 items selected - 2.8 MB")
        XCTAssertEqual(inspectorItemCount, 2_500)
        XCTAssertGreaterThan(pathComponentCount, 0)
        XCTAssertGreaterThan(sidebarPathComponentCount, 0)
        XCTAssertGreaterThan(addressLocationCount, 0)
        XCTAssertNotNil(volumeSummary)
        XCTAssertLessThan(elapsed, 0.30)
    }

    func testCurrentVolumeStatusSummaryIncludesCapacityForCurrentFolder() {
        let store = makeStore(service: FileSystemService())
        let summary = store.currentVolumeStatusSummary

        XCTAssertNotNil(summary)
        XCTAssertTrue(summary?.availableByteCount != nil || summary?.totalByteCount != nil)
        XCTAssertFalse(summary?.statusLabel.isEmpty ?? true)
    }

    func testVolumeStatusSummaryReportsBoundedUsedFraction() {
        XCTAssertEqual(
            VolumeStatusSummary(name: "Drive", availableByteCount: 25, totalByteCount: 100).usedFraction,
            0.75
        )
        XCTAssertEqual(
            VolumeStatusSummary(name: "Drive", availableByteCount: 150, totalByteCount: 100).usedFraction,
            0
        )
        XCTAssertEqual(
            VolumeStatusSummary(name: "Drive", availableByteCount: -10, totalByteCount: 100).usedFraction,
            1
        )
        XCTAssertNil(VolumeStatusSummary(name: "Drive", availableByteCount: 10, totalByteCount: 0).usedFraction)
    }

    func testVisibleSectionsGroupByKindAndSizeWithoutChangingVisibleItems() {
        let store = makeStore()
        let folder = makeItem(name: "Assets", kind: .folder, byteCount: nil)
        let package = makeItem(name: "App.app", kind: .package, byteCount: 12_000)
        let emptyFile = makeItem(name: "empty.txt", kind: .file, byteCount: 0)
        let smallFile = makeItem(name: "notes.txt", kind: .file, byteCount: 25)
        let largeFile = makeItem(name: "movie.mov", kind: .file, byteCount: 120_000_000)
        store.tabs[0].items = [folder, package, emptyFile, smallFile, largeFile]

        store.groupField = .kind
        XCTAssertEqual(store.visibleSections.map(\.title), ["Folders", "Packages", "Files"])
        XCTAssertEqual(Set(store.visibleSections.flatMap(\.items).map(\.id)), Set(store.visibleItems.map(\.id)))

        store.groupField = .size
        XCTAssertEqual(store.visibleSections.map(\.title), ["Folders", "Empty", "< 1 MB", "> 100 MB"])
        XCTAssertEqual(Set(store.visibleSections.flatMap(\.items).map(\.id)), Set(store.visibleItems.map(\.id)))
    }

    func testGroupedSectionsForLargeFoldersStayUnderInteractionBudget() {
        let store = makeStore()
        store.tabs[0].items = makeLargeItemSet()

        let elapsed = elapsedSeconds {
            for field in FileGroupField.allCases {
                store.groupField = field
                XCTAssertEqual(store.visibleSections.flatMap(\.items).count, 5_000)
            }
        }

        XCTAssertLessThan(elapsed, 0.30)
    }

    func testLargeFolderChromeAndStatusQueriesStayUnderInteractionBudget() throws {
        let parentURL = temporaryDirectory.appendingPathComponent("Projects", isDirectory: true)
        let nestedURL = parentURL.appendingPathComponent("Client", isDirectory: true)
        let pinnedURL = temporaryDirectory.appendingPathComponent("Pinned", isDirectory: true)
        let recentURL = temporaryDirectory.appendingPathComponent("Recent", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pinnedURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: recentURL, withIntermediateDirectories: true)

        let store = makeStore()
        store.tabs[0].currentURL = nestedURL
        store.tabs[0].pathInput = nestedURL.path
        store.tabs[0].items = makeLargeItemSet()
        store.tabs[0].isLoading = false
        store.pinDirectory(pinnedURL)
        store.recentDirectories = [recentURL]
        store.selectedItemIDs = Set(store.items.prefix(1_000).map(\.id))

        XCTAssertEqual(store.visibleItems.count, 5_000)
        XCTAssertFalse(store.pathComponents.isEmpty)
        XCTAssertNotNil(store.selectionStatusSummary)
        XCTAssertNotNil(store.inspectorSummary)

        let elapsed = elapsedSeconds {
            for _ in 0..<250 {
                XCTAssertEqual(store.visibleItems.count, 5_000)
                XCTAssertFalse(store.pathComponents.isEmpty)
                XCTAssertFalse(store.sidebarPathComponents.isEmpty)
                XCTAssertFalse(store.addressMenuLocations.isEmpty)
                XCTAssertNotNil(store.selectionStatusSummary)
                XCTAssertNotNil(store.inspectorSummary)
                store.focusAddressBar()
                store.focusSearchField()
            }
        }

        XCTAssertLessThan(elapsed, 0.30)
    }

    func testCreateFileCreatesUniqueEmptyFileAndSelectsIt() throws {
        let existingURL = temporaryDirectory.appendingPathComponent("New File.txt")
        try "existing".write(to: existingURL, atomically: true, encoding: .utf8)

        let store = makeStore()

        XCTAssertTrue(store.createFile(named: "New File.txt"))

        let createdURL = temporaryDirectory.appendingPathComponent("New File 2.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdURL.path))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: createdURL.path)[.size] as? NSNumber)?.intValue, 0)
        XCTAssertEqual(store.selectedItemIDs, [createdURL.path])
        XCTAssertEqual(store.lastPerformanceEvent?.label, "Created File")
        XCTAssertEqual(store.lastPerformanceEvent?.itemCount, 1)
        XCTAssertEqual(store.lastPerformanceEvent?.path, temporaryDirectory.standardizedFileURL.path)
        XCTAssertLessThan(store.lastPerformanceEvent?.elapsedSeconds ?? .infinity, 0.30)
    }

    func testCreateFileInSidebarTargetCreatesUniqueFileWithoutNavigating() throws {
        let targetDirectory = temporaryDirectory.appendingPathComponent("Target", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        try "existing".write(
            to: targetDirectory.appendingPathComponent("New File.txt"),
            atomically: true,
            encoding: .utf8
        )

        let store = makeStore()

        XCTAssertTrue(store.createFile(named: "New File.txt", in: targetDirectory))

        let createdURL = targetDirectory.appendingPathComponent("New File 2.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdURL.path))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: createdURL.path)[.size] as? NSNumber)?.intValue, 0)
        XCTAssertEqual(store.currentURL?.standardizedFileURL.path, temporaryDirectory.standardizedFileURL.path)
        XCTAssertTrue(store.selectedItemIDs.isEmpty)
        XCTAssertEqual(store.lastPerformanceEvent?.label, "Created File")
        XCTAssertEqual(store.lastPerformanceEvent?.itemCount, 1)
        XCTAssertEqual(store.lastPerformanceEvent?.path, targetDirectory.standardizedFileURL.path)
        XCTAssertLessThan(store.lastPerformanceEvent?.elapsedSeconds ?? .infinity, 0.30)
        XCTAssertEqual(store.undoFileOperationTitle, "Undo New")

        store.undoLastFileOperation()

        XCTAssertFalse(FileManager.default.fileExists(atPath: createdURL.path))

        store.redoLastFileOperation()

        XCTAssertTrue(FileManager.default.fileExists(atPath: createdURL.path))
    }

    func testFailedCreateFilePublishesBenchmarkEvent() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("not-a-folder.txt")
        try "plain file".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.tabs[0].currentURL = fileURL

        XCTAssertFalse(store.createFile(named: "child.txt"))
        XCTAssertEqual(store.lastPerformanceEvent?.label, "Failed Create File")
        XCTAssertEqual(store.lastPerformanceEvent?.itemCount, 1)
        XCTAssertEqual(store.lastPerformanceEvent?.path, fileURL.standardizedFileURL.path)
        XCTAssertLessThan(store.lastPerformanceEvent?.elapsedSeconds ?? .infinity, 0.30)
        XCTAssertNotNil(store.errorMessage)
    }

    func testUndoRedoCreateFileAndFolder() throws {
        let store = makeStore()

        XCTAssertTrue(store.createFile(named: "scratch.txt"))
        let fileURL = temporaryDirectory.appendingPathComponent("scratch.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(store.undoFileOperationTitle, "Undo New")

        store.undoLastFileOperation()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(store.canUndoFileOperation)
        XCTAssertTrue(store.canRedoFileOperation)

        store.redoLastFileOperation()

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(store.selectedItemIDs, [fileURL.path])

        XCTAssertTrue(store.createFolder())
        let folderURL = temporaryDirectory.appendingPathComponent("New Folder", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folderURL.path))
        XCTAssertFalse(store.canRedoFileOperation)
        XCTAssertEqual(store.lastPerformanceEvent?.label, "Created Folder")
        XCTAssertEqual(store.lastPerformanceEvent?.itemCount, 1)
        XCTAssertEqual(store.lastPerformanceEvent?.path, temporaryDirectory.standardizedFileURL.path)
        XCTAssertLessThan(store.lastPerformanceEvent?.elapsedSeconds ?? .infinity, 0.30)

        store.undoLastFileOperation()

        XCTAssertFalse(FileManager.default.fileExists(atPath: folderURL.path))

        store.redoLastFileOperation()

        XCTAssertTrue(FileManager.default.fileExists(atPath: folderURL.path))
        XCTAssertEqual(store.selectedItemIDs, [folderURL.path])
    }

    func testCreateFolderInSidebarTargetCreatesUniqueFolderWithoutNavigating() throws {
        let targetDirectory = temporaryDirectory.appendingPathComponent("Target", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: targetDirectory.appendingPathComponent("New Folder", isDirectory: true),
            withIntermediateDirectories: false
        )

        let store = makeStore()

        XCTAssertTrue(store.createFolder(in: targetDirectory))

        let createdURL = targetDirectory.appendingPathComponent("New Folder 2", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdURL.path))
        XCTAssertEqual(store.currentURL?.standardizedFileURL.path, temporaryDirectory.standardizedFileURL.path)
        XCTAssertTrue(store.selectedItemIDs.isEmpty)
        XCTAssertEqual(store.undoFileOperationTitle, "Undo New")

        store.undoLastFileOperation()

        XCTAssertFalse(FileManager.default.fileExists(atPath: createdURL.path))

        store.redoLastFileOperation()

        XCTAssertTrue(FileManager.default.fileExists(atPath: createdURL.path))
    }

    func testFailedCreateFolderPublishesBenchmarkEvent() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("not-a-folder.txt")
        try "plain file".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = makeStore()

        XCTAssertFalse(store.createFolder(in: fileURL))
        XCTAssertEqual(store.lastPerformanceEvent?.label, "Failed Create Folder")
        XCTAssertEqual(store.lastPerformanceEvent?.itemCount, 1)
        XCTAssertEqual(store.lastPerformanceEvent?.path, fileURL.standardizedFileURL.path)
        XCTAssertLessThan(store.lastPerformanceEvent?.elapsedSeconds ?? .infinity, 0.30)
        XCTAssertNotNil(store.errorMessage)
    }

    func testUndoRedoRenameSelectedItem() throws {
        let sourceURL = temporaryDirectory.appendingPathComponent("draft.txt")
        try "hello".write(to: sourceURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.tabs[0].items = [makeItem(name: "draft.txt", kind: .file, byteCount: 5)]
        store.selectedItemIDs = [sourceURL.path]

        XCTAssertTrue(store.renameSelectedItem(to: "final.txt"))

        let renamedURL = temporaryDirectory.appendingPathComponent("final.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedURL.path))
        XCTAssertEqual(store.undoFileOperationTitle, "Undo Rename")
        XCTAssertEqual(store.lastPerformanceEvent?.label, "Renamed")
        XCTAssertEqual(store.lastPerformanceEvent?.itemCount, 1)
        XCTAssertEqual(store.lastPerformanceEvent?.path, temporaryDirectory.standardizedFileURL.path)
        XCTAssertLessThan(store.lastPerformanceEvent?.elapsedSeconds ?? .infinity, 0.30)

        store.undoLastFileOperation()

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamedURL.path))
        XCTAssertEqual(store.selectedItemIDs, [sourceURL.path])
        XCTAssertEqual(store.redoFileOperationTitle, "Redo Rename")

        store.redoLastFileOperation()

        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedURL.path))
        XCTAssertEqual(store.selectedItemIDs, [renamedURL.path])
    }

    func testFailedRenamePublishesBenchmarkEvent() throws {
        let sourceURL = temporaryDirectory.appendingPathComponent("draft.txt")
        let existingURL = temporaryDirectory.appendingPathComponent("existing.txt")
        try "hello".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "already here".write(to: existingURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.tabs[0].items = [
            makeItem(name: "draft.txt", kind: .file, byteCount: 5),
            makeItem(name: "existing.txt", kind: .file, byteCount: 12)
        ]
        store.selectedItemIDs = [sourceURL.path]

        XCTAssertFalse(store.renameSelectedItem(to: "existing.txt"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: existingURL.path))
        XCTAssertEqual(store.lastPerformanceEvent?.label, "Failed Rename")
        XCTAssertEqual(store.lastPerformanceEvent?.itemCount, 1)
        XCTAssertEqual(store.lastPerformanceEvent?.path, temporaryDirectory.standardizedFileURL.path)
        XCTAssertLessThan(store.lastPerformanceEvent?.elapsedSeconds ?? .infinity, 0.30)
        XCTAssertNotNil(store.errorMessage)
    }

    func testInlineRenameSelectionFlowCommitsRename() throws {
        let sourceURL = temporaryDirectory.appendingPathComponent("draft.txt")
        try "hello".write(to: sourceURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.tabs[0].items = [makeItem(name: "draft.txt", kind: .file, byteCount: 5)]
        store.selectedItemIDs = [sourceURL.path]

        XCTAssertTrue(store.beginInlineRenameSelectedItem())
        XCTAssertEqual(store.inlineRenameItemID, sourceURL.path)
        XCTAssertEqual(store.inlineRenameDraft, "draft.txt")

        store.inlineRenameDraft = "final.txt"

        XCTAssertTrue(store.commitInlineRename())

        let renamedURL = temporaryDirectory.appendingPathComponent("final.txt")
        XCTAssertNil(store.inlineRenameItemID)
        XCTAssertEqual(store.inlineRenameDraft, "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedURL.path))
        XCTAssertEqual(store.selectedItemIDs, [renamedURL.path])
    }

    func testInlineRenameCanCancelWithoutChangingFile() throws {
        let sourceURL = temporaryDirectory.appendingPathComponent("draft.txt")
        try "hello".write(to: sourceURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.tabs[0].items = [makeItem(name: "draft.txt", kind: .file, byteCount: 5)]
        store.selectedItemIDs = [sourceURL.path]

        XCTAssertTrue(store.beginInlineRenameSelectedItem())
        store.inlineRenameDraft = "final.txt"
        store.cancelInlineRename()

        XCTAssertNil(store.inlineRenameItemID)
        XCTAssertEqual(store.inlineRenameDraft, "")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent("final.txt").path))
    }

    func testDuplicateSelectedItemsCreatesUniqueCopy() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("notes.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = makeStore(service: FileSystemService())
        store.tabs[0].items = [makeItem(name: "notes.txt", kind: .file, byteCount: 5)]
        store.selectedItemIDs = [fileURL.path]

        store.duplicateSelectedItems()
        await waitForFileOperation(store)

        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent("notes copy.txt").path))
        XCTAssertTrue(store.performanceEvents.contains { event in
            event.label == "Duplicated"
                && event.itemCount == 1
                && event.path == temporaryDirectory.standardizedFileURL.path
                && event.elapsedSeconds < 0.30
        })
    }

    func testUndoRedoDuplicateSelectedItems() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("notes.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = makeStore(service: FileSystemService())
        store.tabs[0].items = [makeItem(name: "notes.txt", kind: .file, byteCount: 5)]
        store.selectedItemIDs = [fileURL.path]

        store.duplicateSelectedItems()
        await waitForFileOperation(store)

        let copyURL = temporaryDirectory.appendingPathComponent("notes copy.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copyURL.path))
        XCTAssertEqual(store.undoFileOperationTitle, "Undo Duplicate")

        store.undoLastFileOperation()

        XCTAssertFalse(FileManager.default.fileExists(atPath: copyURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        store.redoLastFileOperation()

        XCTAssertTrue(FileManager.default.fileExists(atPath: copyURL.path))
        XCTAssertEqual(store.selectedItemIDs, [copyURL.path])
    }

    func testCreateAliasesForSelectionCreatesFinderAliasFile() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("notes.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = makeStore(service: FileSystemService())
        store.tabs[0].items = [makeItem(name: "notes.txt", kind: .file, byteCount: 5)]
        store.selectedItemIDs = [fileURL.path]

        store.createAliasesForSelection()
        await waitForFileOperation(store)

        let aliasURL = temporaryDirectory.appendingPathComponent("notes alias.txt")
        let resolvedURL = try URL(resolvingAliasFileAt: aliasURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: aliasURL.path))
        XCTAssertEqual(resolvedURL.standardizedFileURL, fileURL.standardizedFileURL)
        XCTAssertEqual(store.selectedItemIDs, [aliasURL.path])
        assertPerformanceEvent(in: store, label: "Created Alias", itemCount: 1)
    }

    func testUndoRedoCreateAliasesForSelection() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("notes.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = makeStore(service: FileSystemService())
        store.tabs[0].items = [makeItem(name: "notes.txt", kind: .file, byteCount: 5)]
        store.selectedItemIDs = [fileURL.path]

        store.createAliasesForSelection()
        await waitForFileOperation(store)

        let aliasURL = temporaryDirectory.appendingPathComponent("notes alias.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: aliasURL.path))
        XCTAssertEqual(store.undoFileOperationTitle, "Undo Make Alias")

        store.undoLastFileOperation()

        XCTAssertFalse(FileManager.default.fileExists(atPath: aliasURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        store.redoLastFileOperation()

        XCTAssertTrue(FileManager.default.fileExists(atPath: aliasURL.path))
        XCTAssertEqual(store.selectedItemIDs, [aliasURL.path])
        XCTAssertEqual(try URL(resolvingAliasFileAt: aliasURL).standardizedFileURL, fileURL.standardizedFileURL)
    }

    func testTransferSelectedItemsCopiesSelectionToDestinationFolder() async throws {
        let destinationDirectory = temporaryDirectory.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let sourceURL = temporaryDirectory.appendingPathComponent("notes.txt")
        try "hello".write(to: sourceURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.tabs[0].items = [makeItem(name: "notes.txt", kind: .file, byteCount: 5)]
        store.selectedItemIDs = [sourceURL.path]

        XCTAssertTrue(store.transferSelectedItems(to: destinationDirectory, operation: .copy))
        await waitForFileOperation(store)

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationDirectory.appendingPathComponent("notes.txt").path))
        XCTAssertTrue(store.performanceEvents.contains { event in
            event.label == "Copied"
                && event.itemCount == 1
                && event.path == temporaryDirectory.standardizedFileURL.path
                && event.elapsedSeconds < 0.30
        })
    }

    func testUndoRedoCopySelectionToDestinationFolder() async throws {
        let destinationDirectory = temporaryDirectory.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let sourceURL = temporaryDirectory.appendingPathComponent("notes.txt")
        try "hello".write(to: sourceURL, atomically: true, encoding: .utf8)
        let destinationURL = destinationDirectory.appendingPathComponent("notes.txt")

        let store = makeStore()
        store.tabs[0].items = [makeItem(name: "notes.txt", kind: .file, byteCount: 5)]
        store.selectedItemIDs = [sourceURL.path]

        XCTAssertTrue(store.transferSelectedItems(to: destinationDirectory, operation: .copy))
        await waitForFileOperation(store)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertEqual(store.undoFileOperationTitle, "Undo Copy")

        store.undoLastFileOperation()

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))

        store.redoLastFileOperation()

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testTransferSelectedItemsMovesSelectionToDestinationFolder() async throws {
        let destinationDirectory = temporaryDirectory.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let sourceURL = temporaryDirectory.appendingPathComponent("move-me.txt")
        try "move".write(to: sourceURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.tabs[0].items = [makeItem(name: "move-me.txt", kind: .file, byteCount: 4)]
        store.selectedItemIDs = [sourceURL.path]

        XCTAssertTrue(store.transferSelectedItems(to: destinationDirectory, operation: .move))
        await waitForFileOperation(store)

        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationDirectory.appendingPathComponent("move-me.txt").path))
        XCTAssertTrue(store.performanceEvents.contains { event in
            event.label == "Moved"
                && event.itemCount == 1
                && event.path == temporaryDirectory.standardizedFileURL.path
                && event.elapsedSeconds < 0.30
        })
    }

    func testUndoRedoMoveSelectionToDestinationFolder() async throws {
        let destinationDirectory = temporaryDirectory.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let sourceURL = temporaryDirectory.appendingPathComponent("move-me.txt")
        try "move".write(to: sourceURL, atomically: true, encoding: .utf8)
        let destinationURL = destinationDirectory.appendingPathComponent("move-me.txt")

        let store = makeStore()
        store.tabs[0].items = [makeItem(name: "move-me.txt", kind: .file, byteCount: 4)]
        store.selectedItemIDs = [sourceURL.path]

        XCTAssertTrue(store.transferSelectedItems(to: destinationDirectory, operation: .move))
        await waitForFileOperation(store)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertEqual(store.undoFileOperationTitle, "Undo Move")

        store.undoLastFileOperation()

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))

        store.redoLastFileOperation()

        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testBatchRenameSelectedItemsPreservesExtensionsAndSelection() throws {
        let firstURL = temporaryDirectory.appendingPathComponent("one.txt")
        let secondURL = temporaryDirectory.appendingPathComponent("two.md")
        try "one".write(to: firstURL, atomically: true, encoding: .utf8)
        try "two".write(to: secondURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.tabs[0].items = [
            makeItem(name: "one.txt", kind: .file, byteCount: 3),
            makeItem(name: "two.md", kind: .file, byteCount: 3)
        ]
        store.selectedItemIDs = [firstURL.path, secondURL.path]

        XCTAssertTrue(store.batchRenameSelectedItems(baseName: "Report"))

        let renamedFirst = temporaryDirectory.appendingPathComponent("Report 1.txt")
        let renamedSecond = temporaryDirectory.appendingPathComponent("Report 2.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedFirst.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedSecond.path))
        XCTAssertEqual(store.selectedItemIDs, [renamedFirst.path, renamedSecond.path])
        XCTAssertEqual(store.lastPerformanceEvent?.label, "Batch Renamed")
        XCTAssertEqual(store.lastPerformanceEvent?.itemCount, 2)
        XCTAssertEqual(store.lastPerformanceEvent?.path, temporaryDirectory.standardizedFileURL.path)
        XCTAssertLessThan(store.lastPerformanceEvent?.elapsedSeconds ?? .infinity, 0.30)
    }

    func testFailedBatchRenamePublishesBenchmarkEvent() {
        let firstURL = temporaryDirectory.appendingPathComponent("missing-one.txt")
        let secondURL = temporaryDirectory.appendingPathComponent("missing-two.md")

        let store = makeStore()
        store.tabs[0].items = [
            makeItem(name: "missing-one.txt", kind: .file, byteCount: 0),
            makeItem(name: "missing-two.md", kind: .file, byteCount: 0)
        ]
        store.selectedItemIDs = [firstURL.path, secondURL.path]

        XCTAssertFalse(store.batchRenameSelectedItems(baseName: "Report"))
        XCTAssertEqual(store.lastPerformanceEvent?.label, "Failed Batch Rename")
        XCTAssertEqual(store.lastPerformanceEvent?.itemCount, 2)
        XCTAssertEqual(store.lastPerformanceEvent?.path, temporaryDirectory.standardizedFileURL.path)
        XCTAssertLessThan(store.lastPerformanceEvent?.elapsedSeconds ?? .infinity, 0.30)
        XCTAssertNotNil(store.errorMessage)
    }

    func testUndoRedoBatchRenameSelection() throws {
        let firstURL = temporaryDirectory.appendingPathComponent("one.txt")
        let secondURL = temporaryDirectory.appendingPathComponent("two.md")
        try "one".write(to: firstURL, atomically: true, encoding: .utf8)
        try "two".write(to: secondURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.tabs[0].items = [
            makeItem(name: "one.txt", kind: .file, byteCount: 3),
            makeItem(name: "two.md", kind: .file, byteCount: 3)
        ]
        store.selectedItemIDs = [firstURL.path, secondURL.path]

        XCTAssertTrue(store.batchRenameSelectedItems(baseName: "Report"))

        let renamedFirst = temporaryDirectory.appendingPathComponent("Report 1.txt")
        let renamedSecond = temporaryDirectory.appendingPathComponent("Report 2.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedFirst.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedSecond.path))
        XCTAssertEqual(store.undoFileOperationTitle, "Undo Batch Rename")

        store.undoLastFileOperation()

        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamedFirst.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamedSecond.path))
        XCTAssertEqual(store.selectedItemIDs, [firstURL.path, secondURL.path])

        store.redoLastFileOperation()

        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedFirst.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedSecond.path))
        XCTAssertEqual(store.selectedItemIDs, [renamedFirst.path, renamedSecond.path])
    }

    func testCompressSelectedItemsCreatesZipArchive() async throws {
        let firstURL = temporaryDirectory.appendingPathComponent("a.txt")
        let secondURL = temporaryDirectory.appendingPathComponent("b.txt")
        try "alpha".write(to: firstURL, atomically: true, encoding: .utf8)
        try "beta".write(to: secondURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.tabs[0].items = [
            makeItem(name: "a.txt", kind: .file, byteCount: 5),
            makeItem(name: "b.txt", kind: .file, byteCount: 4)
        ]
        store.selectedItemIDs = [firstURL.path, secondURL.path]

        XCTAssertTrue(store.compressSelectedItems())
        await waitForFileOperation(store)

        let archiveURL = temporaryDirectory.appendingPathComponent("Archive.zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        XCTAssertGreaterThan((try FileManager.default.attributesOfItem(atPath: archiveURL.path)[.size] as? NSNumber)?.intValue ?? 0, 0)
        XCTAssertEqual(store.lastOperationSummary?.itemCount, 2)
        XCTAssertTrue(store.performanceEvents.contains { event in
            event.label == "Compressed"
                && event.itemCount == 2
                && event.path == temporaryDirectory.standardizedFileURL.path
                && event.elapsedSeconds < 0.30
        })
    }

    func testUndoRedoCompressSelectionCreatesArchiveAgain() async throws {
        let firstURL = temporaryDirectory.appendingPathComponent("a.txt")
        let secondURL = temporaryDirectory.appendingPathComponent("b.txt")
        try "alpha".write(to: firstURL, atomically: true, encoding: .utf8)
        try "beta".write(to: secondURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.tabs[0].items = [
            makeItem(name: "a.txt", kind: .file, byteCount: 5),
            makeItem(name: "b.txt", kind: .file, byteCount: 4)
        ]
        store.selectedItemIDs = [firstURL.path, secondURL.path]

        XCTAssertTrue(store.compressSelectedItems())
        await waitForFileOperation(store)

        let archiveURL = temporaryDirectory.appendingPathComponent("Archive.zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        XCTAssertEqual(store.undoFileOperationTitle, "Undo Zip")

        store.undoLastFileOperation()

        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))

        store.redoLastFileOperation()

        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        XCTAssertEqual(store.selectedItemIDs, [archiveURL.path])
    }

    func testExtractSelectedZipCreatesFolderAndSelectsIt() async throws {
        let archiveURL = try makeZipArchive(named: "Bundle.zip", entries: ["readme.txt": "hello"])

        let store = makeStore(service: FileSystemService())
        store.tabs[0].items = [
            makeItem(name: "Bundle.zip", kind: .file, byteCount: 128)
        ]
        store.selectedItemIDs = [archiveURL.path]

        XCTAssertTrue(store.canExtractSelectedArchives)
        XCTAssertTrue(store.extractSelectedArchives())
        await waitForFileOperation(store)
        await waitForTabLoad(store)

        let destinationURL = temporaryDirectory.appendingPathComponent("Bundle", isDirectory: true)
        let extractedFileURL = destinationURL.appendingPathComponent("readme.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertEqual(try String(contentsOf: extractedFileURL, encoding: .utf8), "hello")
        XCTAssertEqual(store.selectedItemIDs, [destinationURL.path])
        XCTAssertEqual(store.lastOperationSummary?.label, "Extracted")
        XCTAssertEqual(store.lastOperationSummary?.itemCount, 1)
        XCTAssertTrue(store.performanceEvents.contains { event in
            event.label == "Extracted"
                && event.itemCount == 1
                && event.path == temporaryDirectory.standardizedFileURL.path
                && event.elapsedSeconds < 0.30
        })
    }

    func testUndoRedoExtractSelectedZip() async throws {
        let archiveURL = try makeZipArchive(named: "Bundle.zip", entries: ["readme.txt": "hello"])

        let store = makeStore(service: FileSystemService())
        store.tabs[0].items = [
            makeItem(name: "Bundle.zip", kind: .file, byteCount: 128)
        ]
        store.selectedItemIDs = [archiveURL.path]

        XCTAssertTrue(store.extractSelectedArchives())
        await waitForFileOperation(store)
        await waitForTabLoad(store)

        let destinationURL = temporaryDirectory.appendingPathComponent("Bundle", isDirectory: true)
        let extractedFileURL = destinationURL.appendingPathComponent("readme.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: extractedFileURL.path))
        XCTAssertEqual(store.undoFileOperationTitle, "Undo Extract")

        store.undoLastFileOperation()
        await waitForTabLoad(store)

        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        XCTAssertEqual(store.selectedItemIDs, [archiveURL.path])

        store.redoLastFileOperation()
        await waitForTabLoad(store)

        XCTAssertTrue(FileManager.default.fileExists(atPath: extractedFileURL.path))
        XCTAssertEqual(store.selectedItemIDs, [destinationURL.path])
    }

    func testExtractSelectedZipUsesUniqueFolderName() async throws {
        let archiveURL = try makeZipArchive(named: "Bundle.zip", entries: ["readme.txt": "hello"])
        let existingDestinationURL = temporaryDirectory.appendingPathComponent("Bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: existingDestinationURL, withIntermediateDirectories: true)

        let store = makeStore(service: FileSystemService())
        store.tabs[0].items = [
            makeItem(name: "Bundle.zip", kind: .file, byteCount: 128)
        ]
        store.selectedItemIDs = [archiveURL.path]

        XCTAssertTrue(store.extractSelectedArchives())
        await waitForFileOperation(store)
        await waitForTabLoad(store)

        let destinationURL = temporaryDirectory.appendingPathComponent("Bundle 2", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.appendingPathComponent("readme.txt").path))
        XCTAssertEqual(store.selectedItemIDs, [destinationURL.path])
    }

    func testDeleteSelectedItemsPermanentlyRemovesFilesAndFoldersInBackground() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("delete-me.txt")
        let folderURL = temporaryDirectory.appendingPathComponent("Delete Folder", isDirectory: true)
        try "remove".write(to: fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try "nested".write(to: folderURL.appendingPathComponent("nested.txt"), atomically: true, encoding: .utf8)

        let store = makeStore()
        let file = makeItem(name: "delete-me.txt", kind: .file, byteCount: 6)
        let folder = makeItem(name: "Delete Folder", kind: .folder, byteCount: nil)
        store.tabs[0].items = [file, folder]
        store.selectedItemIDs = [file.id, folder.id]

        XCTAssertTrue(store.deleteSelectedItemsPermanently())
        XCTAssertNotNil(store.activeOperation)
        await waitForFileOperation(store)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folderURL.path))
        XCTAssertTrue(store.selectedItemIDs.isEmpty)
        XCTAssertEqual(store.lastOperationSummary?.label, "Deleted")
        XCTAssertEqual(store.lastOperationSummary?.itemCount, 2)
        XCTAssertTrue(store.performanceEvents.contains { event in
            event.label == "Deleted"
                && event.itemCount == 2
                && event.path == temporaryDirectory.standardizedFileURL.path
                && event.elapsedSeconds < 0.30
        })
    }

    func testMoveSelectedItemToTrashPublishesBenchmarkAndSupportsUndoRedo() async throws {
        let fileName = "better-files-trash-\(UUID().uuidString).txt"
        let fileURL = temporaryDirectory.appendingPathComponent(fileName)
        let trashURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash", isDirectory: true)
            .appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: trashURL)
        defer {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: trashURL)
        }

        try "trash".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        let file = makeItem(name: fileName, kind: .file, byteCount: 5)
        store.tabs[0].items = [file]
        store.selectedItemIDs = [file.id]

        XCTAssertTrue(store.moveSelectedItemToTrash())
        await waitForFileOperation(store)
        await waitForTabLoad(store)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashURL.path))
        XCTAssertTrue(store.selectedItemIDs.isEmpty)
        XCTAssertEqual(store.lastOperationSummary?.label, "Moved to Trash")
        XCTAssertEqual(store.lastOperationSummary?.itemCount, 1)
        assertPerformanceEvent(in: store, label: "Moved to Trash", itemCount: 1)
        XCTAssertEqual(store.undoFileOperationTitle, "Undo Move to Trash")

        store.undoLastFileOperation()
        await waitForTabLoad(store)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashURL.path))
        XCTAssertEqual(store.redoFileOperationTitle, "Redo Move to Trash")

        store.redoLastFileOperation()
        await waitForTabLoad(store)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashURL.path))
    }

    func testEmptyTrashDeletesTrashContentsInBackgroundAndPublishesBenchmark() async throws {
        let trashDirectory = temporaryDirectory.appendingPathComponent("Trash Fixture", isDirectory: true)
        let fileURL = trashDirectory.appendingPathComponent("old.txt")
        let hiddenURL = trashDirectory.appendingPathComponent(".hidden-cache")
        let folderURL = trashDirectory.appendingPathComponent("Old Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try "old".write(to: fileURL, atomically: true, encoding: .utf8)
        try "hidden".write(to: hiddenURL, atomically: true, encoding: .utf8)
        try "nested".write(to: folderURL.appendingPathComponent("nested.txt"), atomically: true, encoding: .utf8)

        let store = makeStore(service: FileSystemService())
        store.currentURL = trashDirectory
        store.pathInput = trashDirectory.path
        store.tabs[0].items = [
            stubItem(named: "old.txt", in: trashDirectory),
            stubItem(named: ".hidden-cache", in: trashDirectory),
            FileItem(
                id: folderURL.standardizedFileURL.path,
                url: folderURL,
                name: "Old Folder",
                kind: .folder,
                localizedTypeDescription: nil,
                byteCount: nil,
                createdAt: Date(timeIntervalSince1970: 1_600_000_000),
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                accessedAt: Date(timeIntervalSince1970: 1_800_000_000),
                isHidden: false,
                isLocked: false,
                posixPermissions: 0o755
            )
        ]
        store.selectedItemIDs = [fileURL.standardizedFileURL.path, folderURL.standardizedFileURL.path]

        XCTAssertTrue(store.emptyTrash(at: trashDirectory))
        XCTAssertNotNil(store.activeOperation)
        await waitForFileOperation(store)
        await waitForTabLoad(store)

        XCTAssertTrue(FileManager.default.fileExists(atPath: trashDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: hiddenURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folderURL.path))
        XCTAssertTrue(store.selectedItemIDs.isEmpty)
        XCTAssertEqual(store.lastOperationSummary?.label, "Emptied Trash")
        XCTAssertEqual(store.lastOperationSummary?.itemCount, 3)
        assertPerformanceEvent(
            in: store,
            label: "Emptied Trash",
            itemCount: 3,
            path: trashDirectory.standardizedFileURL.path
        )
    }

    func testEmptyTrashReturnsFalseForMissingOrEmptyTrash() throws {
        let store = makeStore()
        let emptyTrashDirectory = temporaryDirectory.appendingPathComponent("Empty Trash", isDirectory: true)
        let missingTrashDirectory = temporaryDirectory.appendingPathComponent("Missing Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyTrashDirectory, withIntermediateDirectories: true)

        XCTAssertFalse(store.emptyTrash(at: emptyTrashDirectory))
        XCTAssertFalse(store.emptyTrash(at: missingTrashDirectory))
        XCTAssertNil(store.activeOperation)
        XCTAssertNil(store.lastOperationSummary)
    }

    func testDeleteSelectedItemsPermanentlyReturnsFalseWithoutSelection() {
        let store = makeStore()

        XCTAssertFalse(store.deleteSelectedItemsPermanently())
        XCTAssertNil(store.activeOperation)
    }

    func testSetSelectedItemsHiddenUsesFileSystemHiddenFlag() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("visible.txt")
        try "hide".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = makeStore(service: FileSystemService())
        store.showHiddenFiles = true
        let file = makeItem(name: "visible.txt", kind: .file, byteCount: 4)
        store.tabs[0].items = [file]
        store.selectedItemIDs = [file.id]

        XCTAssertTrue(store.setSelectedItemsHidden(true))
        await waitForFileOperation(store)

        var statInfo = stat()
        XCTAssertEqual(lstat(fileURL.path, &statInfo), 0)
        XCTAssertNotEqual(statInfo.st_flags & UInt32(UF_HIDDEN), 0)
        XCTAssertEqual(store.selectedItemIDs, [fileURL.path])
        assertPerformanceEvent(in: store, label: "Hidden", itemCount: 1)

        store.tabs[0].items = [makeItem(name: "visible.txt", kind: .file, byteCount: 4, isHidden: true)]
        store.selectedItemIDs = [fileURL.path]

        XCTAssertTrue(store.setSelectedItemsHidden(false))
        await waitForFileOperation(store)

        XCTAssertEqual(lstat(fileURL.path, &statInfo), 0)
        XCTAssertEqual(statInfo.st_flags & UInt32(UF_HIDDEN), 0)
        assertPerformanceEvent(in: store, label: "Unhidden", itemCount: 1)
    }

    func testFailedBackgroundFileOperationPublishesBenchmarkEvent() async {
        let store = makeStore(service: FileSystemService())
        let missingItem = makeItem(name: "missing.txt", kind: .file, byteCount: 0)
        store.tabs[0].items = [missingItem]
        store.selectedItemIDs = [missingItem.id]

        XCTAssertTrue(store.setSelectedItemsHidden(true))
        await waitForFileOperation(store)

        XCTAssertEqual(store.lastOperationSummary?.label, "Failed Hidden")
        XCTAssertEqual(store.lastOperationSummary?.itemCount, 1)
        XCTAssertEqual(store.lastPerformanceEvent?.label, "Failed Hidden")
        XCTAssertEqual(store.lastPerformanceEvent?.itemCount, 1)
        XCTAssertEqual(store.lastPerformanceEvent?.path, temporaryDirectory.standardizedFileURL.path)
        XCTAssertLessThan(store.lastPerformanceEvent?.elapsedSeconds ?? .infinity, 0.30)
        XCTAssertNotNil(store.errorMessage)
    }

    func testUnhideDotPrefixedFileRenamesWithoutOverwriting() async throws {
        let hiddenURL = temporaryDirectory.appendingPathComponent(".env")
        let existingVisibleURL = temporaryDirectory.appendingPathComponent("env")
        try "secret".write(to: hiddenURL, atomically: true, encoding: .utf8)
        try "visible".write(to: existingVisibleURL, atomically: true, encoding: .utf8)

        let store = makeStore(service: FileSystemService())
        store.showHiddenFiles = true
        let hiddenItem = makeItem(name: ".env", kind: .file, byteCount: 6, isHidden: true)
        store.tabs[0].items = [hiddenItem]
        store.selectedItemIDs = [hiddenItem.id]

        XCTAssertTrue(store.setSelectedItemsHidden(false))
        await waitForFileOperation(store)

        let renamedURL = temporaryDirectory.appendingPathComponent("env 2")
        XCTAssertFalse(FileManager.default.fileExists(atPath: hiddenURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: existingVisibleURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedURL.path))
        XCTAssertEqual(store.selectedItemIDs, [renamedURL.path])
    }

    func testSetSelectedItemsWritableUpdatesPermissionBits() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("permissions.txt")
        try "chmod".write(to: fileURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(fileURL.path, 0o644), 0)

        let store = makeStore(service: FileSystemService())
        let file = makeItem(name: "permissions.txt", kind: .file, byteCount: 5, posixPermissions: 0o644)
        store.tabs[0].items = [file]
        store.selectedItemIDs = [file.id]

        XCTAssertTrue(store.setSelectedItemsWritable(false))
        await waitForFileOperation(store)

        var statInfo = stat()
        XCTAssertEqual(lstat(fileURL.path, &statInfo), 0)
        XCTAssertEqual(statInfo.st_mode & 0o222, 0)
        XCTAssertEqual(store.selectedItemIDs, [fileURL.path])
        assertPerformanceEvent(in: store, label: "Made Read-Only", itemCount: 1)

        store.tabs[0].items = [makeItem(name: "permissions.txt", kind: .file, byteCount: 5, posixPermissions: 0o444)]
        store.selectedItemIDs = [fileURL.path]

        XCTAssertTrue(store.setSelectedItemsWritable(true))
        await waitForFileOperation(store)

        XCTAssertEqual(lstat(fileURL.path, &statInfo), 0)
        XCTAssertNotEqual(statInfo.st_mode & UInt16(S_IWUSR), 0)
        XCTAssertEqual(store.selectedItemIDs, [fileURL.path])
        assertPerformanceEvent(in: store, label: "Made Writable", itemCount: 1)
    }

    func testSetSelectedItemsPermissionBitsUpdatesGroupAndEveryoneBits() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("shared-permissions.txt")
        try "chmod".write(to: fileURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(fileURL.path, 0o640), 0)

        let store = makeStore(service: FileSystemService())
        let file = makeItem(name: "shared-permissions.txt", kind: .file, byteCount: 5, posixPermissions: 0o640)
        store.tabs[0].items = [file]
        store.selectedItemIDs = [file.id]

        XCTAssertTrue(store.setSelectedItemsPermissionBits([.groupExecute, .everyoneRead], enabled: true))
        await waitForFileOperation(store)

        var statInfo = stat()
        XCTAssertEqual(lstat(fileURL.path, &statInfo), 0)
        XCTAssertEqual(statInfo.st_mode & 0o777, 0o654)
        XCTAssertEqual(store.selectedItemIDs, [fileURL.path])
        assertPerformanceEvent(in: store, label: "Added Permissions", itemCount: 1)
    }

    func testSetSelectedItemsPOSIXPermissionsPublishesBenchmarkEvent() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("preset-permissions.txt")
        try "chmod".write(to: fileURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(fileURL.path, 0o600), 0)

        let store = makeStore(service: FileSystemService())
        let file = makeItem(name: "preset-permissions.txt", kind: .file, byteCount: 5, posixPermissions: 0o600)
        store.tabs[0].items = [file]
        store.selectedItemIDs = [file.id]

        XCTAssertTrue(store.setSelectedItemsPOSIXPermissions(0o755))
        await waitForFileOperation(store)

        var statInfo = stat()
        XCTAssertEqual(lstat(fileURL.path, &statInfo), 0)
        XCTAssertEqual(statInfo.st_mode & 0o777, 0o755)
        XCTAssertEqual(store.selectedItemIDs, [fileURL.path])
        assertPerformanceEvent(in: store, label: "Changed Permissions", itemCount: 1)
    }

    func testApplySelectedFolderPermissionsToEnclosedItemsUsesFolderMode() async throws {
        let folderURL = temporaryDirectory.appendingPathComponent("Project", isDirectory: true)
        let childFileURL = folderURL.appendingPathComponent("notes.txt")
        let childFolderURL = folderURL.appendingPathComponent("Nested", isDirectory: true)
        let nestedFileURL = childFolderURL.appendingPathComponent("task.sh")
        try FileManager.default.createDirectory(at: childFolderURL, withIntermediateDirectories: true)
        try "notes".write(to: childFileURL, atomically: true, encoding: .utf8)
        try "echo hi".write(to: nestedFileURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(folderURL.path, 0o750), 0)
        XCTAssertEqual(chmod(childFileURL.path, 0o600), 0)
        XCTAssertEqual(chmod(childFolderURL.path, 0o777), 0)
        XCTAssertEqual(chmod(nestedFileURL.path, 0o644), 0)

        let store = makeStore(service: FileSystemService())
        let folder = makeItem(name: "Project", kind: .folder, byteCount: nil, posixPermissions: 0o750)
        store.tabs[0].items = [folder]
        store.selectedItemIDs = [folder.id]

        XCTAssertTrue(store.canApplySelectedFolderPermissionsToEnclosedItems)
        XCTAssertTrue(store.applySelectedFolderPermissionsToEnclosedItems())
        await waitForFileOperation(store)

        var statInfo = stat()
        XCTAssertEqual(lstat(folderURL.path, &statInfo), 0)
        XCTAssertEqual(statInfo.st_mode & 0o777, 0o750)
        XCTAssertEqual(lstat(childFileURL.path, &statInfo), 0)
        XCTAssertEqual(statInfo.st_mode & 0o777, 0o750)
        XCTAssertEqual(lstat(childFolderURL.path, &statInfo), 0)
        XCTAssertEqual(statInfo.st_mode & 0o777, 0o750)
        XCTAssertEqual(lstat(nestedFileURL.path, &statInfo), 0)
        XCTAssertEqual(statInfo.st_mode & 0o777, 0o750)
        XCTAssertEqual(store.selectedItemIDs, [folderURL.path])
        assertPerformanceEvent(in: store, label: "Applied Enclosed Permissions", itemCount: 1)
    }

    func testApplySelectedFolderPermissionsToEnclosedItemsRequiresFolderSelection() {
        let store = makeStore(service: FileSystemService())
        let file = makeItem(name: "plain.txt", kind: .file, byteCount: 4, posixPermissions: 0o644)
        store.tabs[0].items = [file]
        store.selectedItemIDs = [file.id]

        XCTAssertFalse(store.canApplySelectedFolderPermissionsToEnclosedItems)
        XCTAssertFalse(store.applySelectedFolderPermissionsToEnclosedItems())
        XCTAssertNil(store.activeOperation)
    }

    func testRemovingSelectedPermissionBitsPublishesBenchmarkEvent() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("remove-permissions.txt")
        try "chmod".write(to: fileURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(fileURL.path, 0o777), 0)

        let store = makeStore(service: FileSystemService())
        let file = makeItem(name: "remove-permissions.txt", kind: .file, byteCount: 5, posixPermissions: 0o777)
        store.tabs[0].items = [file]
        store.selectedItemIDs = [file.id]

        XCTAssertTrue(store.setSelectedItemsPermissionBits([.groupWrite, .everyoneWrite], enabled: false))
        await waitForFileOperation(store)

        var statInfo = stat()
        XCTAssertEqual(lstat(fileURL.path, &statInfo), 0)
        XCTAssertEqual(statInfo.st_mode & 0o777, 0o755)
        XCTAssertEqual(store.selectedItemIDs, [fileURL.path])
        assertPerformanceEvent(in: store, label: "Removed Permissions", itemCount: 1)
    }

    func testSetSelectedItemsPermissionBitsReturnsFalseWithoutSelection() {
        let store = makeStore(service: FileSystemService())

        XCTAssertFalse(store.setSelectedItemsPermissionBits(.everyoneExecute, enabled: true))
        XCTAssertNil(store.activeOperation)
    }

    func testOpenSelectedItemsWithApplicationReturnsFalseWithoutSelection() {
        let store = makeStore()

        XCTAssertFalse(store.openSelectedItems(withApplicationAt: URL(fileURLWithPath: "/Applications/TextEdit.app")))
        XCTAssertNil(store.errorMessage)
    }

    func testOpenSelectedItemsReturnsFalseWithoutSelection() {
        let store = makeStore()

        XCTAssertFalse(store.openSelectedItems())
        XCTAssertNil(store.errorMessage)
    }

    func testOpenSelectedFolderNavigatesCurrentTab() throws {
        let folderURL = temporaryDirectory.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let store = makeStore()
        let folder = makeItem(name: "Project", kind: .folder, byteCount: nil)
        store.tabs[0].items = [folder]
        store.selectedItemIDs = [folder.id]

        XCTAssertTrue(store.openSelectedItems())
        XCTAssertEqual(store.currentURL?.standardizedFileURL, folderURL.standardizedFileURL)
        XCTAssertEqual(store.pathInput, folderURL.standardizedFileURL.path)
    }

    func testShowSelectedPackageContentsNavigatesCurrentTab() throws {
        let packageURL = temporaryDirectory.appendingPathComponent("Project.xcodeproj", isDirectory: true)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)

        let store = makeStore()
        let package = makeItem(name: "Project.xcodeproj", kind: .package, byteCount: nil)
        store.tabs[0].items = [package]
        store.selectedItemIDs = [package.id]

        XCTAssertFalse(store.canOpenSelectionInNewTabs)
        XCTAssertTrue(store.canShowPackageContents(package))
        XCTAssertTrue(store.canShowSelectionPackageContents)
        XCTAssertTrue(store.showSelectedPackageContents())
        XCTAssertEqual(store.currentURL?.standardizedFileURL, packageURL.standardizedFileURL)
        XCTAssertEqual(store.pathInput, packageURL.standardizedFileURL.path)
    }

    func testShowSelectedPackageContentsOpensMultiplePackagesInTabs() throws {
        let firstPackageURL = temporaryDirectory.appendingPathComponent("First.app", isDirectory: true)
        let secondPackageURL = temporaryDirectory.appendingPathComponent("Second.pages", isDirectory: true)
        try FileManager.default.createDirectory(at: firstPackageURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondPackageURL, withIntermediateDirectories: true)

        let store = makeStore()
        let firstPackage = makeItem(name: "First.app", kind: .package, byteCount: nil)
        let secondPackage = makeItem(name: "Second.pages", kind: .package, byteCount: nil)
        store.tabs[0].items = [firstPackage, secondPackage]
        store.selectedItemIDs = [firstPackage.id, secondPackage.id]

        XCTAssertTrue(store.showSelectedPackageContents())

        XCTAssertEqual(store.tabs.count, 3)
        XCTAssertEqual(store.tabs.suffix(2).map { $0.currentURL?.standardizedFileURL }, [
            firstPackageURL.standardizedFileURL,
            secondPackageURL.standardizedFileURL
        ])
        XCTAssertEqual(store.currentURL?.standardizedFileURL, secondPackageURL.standardizedFileURL)
    }

    func testShowSelectedPackageContentsReturnsFalseWithoutPackageSelection() throws {
        let folderURL = temporaryDirectory.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let store = makeStore()
        let folder = makeItem(name: "Project", kind: .folder, byteCount: nil)
        store.tabs[0].items = [folder]
        store.selectedItemIDs = [folder.id]

        XCTAssertFalse(store.canShowPackageContents(folder))
        XCTAssertFalse(store.canShowSelectionPackageContents)
        XCTAssertFalse(store.showSelectedPackageContents())
        XCTAssertEqual(store.currentURL?.standardizedFileURL, temporaryDirectory.standardizedFileURL)
    }

    func testOpenSelectedAliasToFolderNavigatesCurrentTab() throws {
        let folderURL = temporaryDirectory.appendingPathComponent("Project", isDirectory: true)
        let aliasURL = temporaryDirectory.appendingPathComponent("Project alias")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let bookmarkData = try folderURL.bookmarkData(
            options: [.suitableForBookmarkFile],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        try URL.writeBookmarkData(bookmarkData, to: aliasURL)

        let store = makeStore()
        let aliasItem = makeItem(name: "Project alias", kind: .file, byteCount: 5)
        store.tabs[0].items = [aliasItem]
        store.selectedItemIDs = [aliasItem.id]

        XCTAssertTrue(store.canOpenSelectionInNewTabs)
        XCTAssertTrue(store.openSelectedItems())
        XCTAssertEqual(store.currentURL?.standardizedFileURL, folderURL.standardizedFileURL)
        XCTAssertEqual(store.pathInput, folderURL.standardizedFileURL.path)
    }

    func testOpenSelectionInNewTabsIncludesAliasToFolder() throws {
        let folderURL = temporaryDirectory.appendingPathComponent("Project", isDirectory: true)
        let aliasURL = temporaryDirectory.appendingPathComponent("Project alias")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let bookmarkData = try folderURL.bookmarkData(
            options: [.suitableForBookmarkFile],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        try URL.writeBookmarkData(bookmarkData, to: aliasURL)

        let store = makeStore()
        let aliasItem = makeItem(name: "Project alias", kind: .file, byteCount: 5)
        store.tabs[0].items = [aliasItem]
        store.selectedItemIDs = [aliasItem.id]

        store.openSelectionInNewTabs()

        XCTAssertEqual(store.tabs.count, 2)
        XCTAssertEqual(store.currentURL?.standardizedFileURL, folderURL.standardizedFileURL)
    }

    func testOpenSelectedFoldersUsesTabsForMultipleFolders() throws {
        let firstURL = temporaryDirectory.appendingPathComponent("Project A", isDirectory: true)
        let secondURL = temporaryDirectory.appendingPathComponent("Project B", isDirectory: true)
        try FileManager.default.createDirectory(at: firstURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondURL, withIntermediateDirectories: true)

        let store = makeStore()
        let firstFolder = makeItem(name: "Project A", kind: .folder, byteCount: nil)
        let secondFolder = makeItem(name: "Project B", kind: .folder, byteCount: nil)
        store.tabs[0].items = [firstFolder, secondFolder]
        store.selectedItemIDs = [firstFolder.id, secondFolder.id]

        XCTAssertTrue(store.openSelectedItems())
        XCTAssertEqual(store.tabs.map { $0.currentURL?.lastPathComponent }, [
            temporaryDirectory.lastPathComponent,
            "Project A",
            "Project B"
        ])
        XCTAssertEqual(store.currentURL?.standardizedFileURL, secondURL.standardizedFileURL)
    }

    func testOpeningManySelectedFoldersIntoTabsStaysUnderInteractionBudget() {
        let store = makeStore()
        let folders = (0..<100).map { index in
            makeItem(
                name: String(format: "Project %03d", index),
                kind: .folder,
                byteCount: nil
            )
        }
        store.tabs[0].items = folders
        store.selectedItemIDs = Set(folders.map(\.id))

        let elapsed = elapsedSeconds {
            XCTAssertTrue(store.openSelectedItems())
        }

        XCTAssertLessThan(elapsed, 0.3)
        XCTAssertEqual(store.tabs.count, 101)
        XCTAssertEqual(store.currentURL?.lastPathComponent, "Project 099")
    }

    func testOpenSelectionInNewTabsOnlyUsesFolders() {
        let store = makeStore()
        let folder = makeItem(name: "Project", kind: .folder, byteCount: nil)
        let file = makeItem(name: "notes.txt", kind: .file, byteCount: 5)
        store.tabs[0].items = [folder, file]
        store.selectedItemIDs = [folder.id, file.id]

        store.openSelectionInNewTabs()

        XCTAssertEqual(store.tabs.count, 2)
        XCTAssertEqual(store.selectedTab.currentURL?.lastPathComponent, "Project")
    }

    func testOpenSelectionParentFoldersInNewTabsDeduplicatesParents() {
        let store = makeStore()
        let sharedDirectory = temporaryDirectory.appendingPathComponent("Shared", isDirectory: true)
        let otherDirectory = temporaryDirectory.appendingPathComponent("Other", isDirectory: true)
        let first = stubItem(named: "a.txt", in: sharedDirectory)
        let second = stubItem(named: "b.txt", in: sharedDirectory)
        let third = stubItem(named: "c.txt", in: otherDirectory)
        store.tabs[0].items = [first, second, third]
        store.selectedItemIDs = [first.id, second.id, third.id]

        XCTAssertTrue(store.canOpenSelectionParentFoldersInNewTabs)

        store.openSelectionParentFoldersInNewTabs()

        XCTAssertEqual(store.tabs.count, 3)
        XCTAssertEqual(store.tabs.map { $0.currentURL?.standardizedFileURL }, [
            temporaryDirectory.standardizedFileURL,
            sharedDirectory.standardizedFileURL,
            otherDirectory.standardizedFileURL
        ])
        XCTAssertEqual(store.currentURL?.standardizedFileURL, otherDirectory.standardizedFileURL)
    }

    func testOpenSelectionLocationNavigatesCurrentTabToParentAndSelectsItem() throws {
        let nestedURL = temporaryDirectory.appendingPathComponent("Nested", isDirectory: true)
        let fileURL = nestedURL.appendingPathComponent("result.txt")
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        try "result".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        let item = stubItem(named: "result.txt", in: nestedURL)
        store.tabs[0].items = [item]
        store.selectedItemIDs = [item.id]

        XCTAssertTrue(store.canOpenSelectionLocation)

        store.openSelectionLocation()

        XCTAssertEqual(store.currentURL?.standardizedFileURL, nestedURL.standardizedFileURL)
        XCTAssertEqual(store.selectedItemIDs, [fileURL.standardizedFileURL.path])
        XCTAssertEqual(store.backHistoryLocations.first?.url.standardizedFileURL, temporaryDirectory.standardizedFileURL)
    }

    func testDuplicateTabOpensSameFolderInNewSelectedTab() {
        let store = makeStore()
        let originalTabID = store.selectedTabID
        let originalURL = store.selectedTab.currentURL

        store.duplicateTab(originalTabID)

        XCTAssertEqual(store.tabs.count, 2)
        XCTAssertNotEqual(store.selectedTabID, originalTabID)
        XCTAssertEqual(store.selectedTab.currentURL, originalURL)
    }

    func testOpenCurrentFolderInNewTabDuplicatesCurrentFolder() {
        let store = makeStore()
        let originalTabID = store.selectedTabID
        let originalURL = store.currentURL

        XCTAssertTrue(store.canOpenCurrentFolderInNewTab)

        store.openCurrentFolderInNewTab()

        XCTAssertEqual(store.tabs.count, 2)
        XCTAssertNotEqual(store.selectedTabID, originalTabID)
        XCTAssertEqual(store.currentURL, originalURL)
        XCTAssertEqual(store.tabs.first?.currentURL, originalURL)
    }

    func testOpenCurrentFolderInNewTabIsSafeWithoutCurrentFolder() {
        let store = makeStore()
        store.currentURL = nil

        XCTAssertFalse(store.canOpenCurrentFolderInNewTab)

        store.openCurrentFolderInNewTab()

        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertNil(store.currentURL)
    }

    func testSelectNextAndPreviousTabWrapAround() {
        let store = makeStore()
        let firstTabID = store.selectedTabID
        store.addTab(opening: temporaryDirectory.appendingPathComponent("Second", isDirectory: true))
        let secondTabID = store.selectedTabID
        store.addTab(opening: temporaryDirectory.appendingPathComponent("Third", isDirectory: true))
        let thirdTabID = store.selectedTabID

        store.selectNextTab()

        XCTAssertEqual(store.selectedTabID, firstTabID)

        store.selectPreviousTab()

        XCTAssertEqual(store.selectedTabID, thirdTabID)

        store.selectPreviousTab()

        XCTAssertEqual(store.selectedTabID, secondTabID)
    }

    func testNewTabDefaultsToHomeDirectoryInsteadOfCurrentFolder() {
        let store = makeStore()
        let originalURL = store.currentURL

        store.addTab()

        XCTAssertEqual(
            store.currentURL?.standardizedFileURL,
            FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        )
        XCTAssertNotEqual(store.currentURL?.standardizedFileURL, originalURL?.standardizedFileURL)
    }

    func testNewTabOpeningLoadedFolderMirrorsBeforeBackgroundRefresh() async throws {
        try "alpha".write(to: temporaryDirectory.appendingPathComponent("alpha.txt"), atomically: true, encoding: .utf8)
        try "beta".write(to: temporaryDirectory.appendingPathComponent("beta.txt"), atomically: true, encoding: .utf8)

        let store = makeStore(service: FileSystemService())
        await waitForTabLoad(store)
        let visibleNames = store.visibleItems.map(\.name)

        XCTAssertEqual(visibleNames, ["alpha.txt", "beta.txt"])

        let elapsed = elapsedSeconds {
            store.addTab(opening: temporaryDirectory)
        }

        XCTAssertLessThan(elapsed, 0.3)
        XCTAssertEqual(store.visibleItems.map(\.name), visibleNames)
        XCTAssertFalse(store.isLoading)
    }

    func testMoveTabAfterSupportsAdjacentRightReorder() {
        let store = makeStore()
        let firstTabID = store.selectedTabID
        let secondURL = temporaryDirectory.appendingPathComponent("Second", isDirectory: true)
        let thirdURL = temporaryDirectory.appendingPathComponent("Third", isDirectory: true)

        store.addTab(opening: secondURL)
        let secondTabID = store.selectedTabID
        store.addTab(opening: thirdURL)

        store.moveTab(firstTabID, after: secondTabID)

        XCTAssertEqual(store.tabs.map(\.title), ["Second", temporaryDirectory.lastPathComponent, "Third"])
    }

    func testSelectTabAtDisplayIndexSelectsRequestedTabAndIgnoresInvalidIndexes() {
        let store = makeStore()
        let firstTabID = store.selectedTabID
        store.addTab(opening: temporaryDirectory.appendingPathComponent("Second", isDirectory: true))
        let secondTabID = store.selectedTabID
        store.addTab(opening: temporaryDirectory.appendingPathComponent("Third", isDirectory: true))
        let thirdTabID = store.selectedTabID

        XCTAssertTrue(store.canSelectTab(atDisplayIndex: 0))
        XCTAssertTrue(store.canSelectTab(atDisplayIndex: 1))
        XCTAssertTrue(store.canSelectTab(atDisplayIndex: 2))
        XCTAssertFalse(store.canSelectTab(atDisplayIndex: 3))
        XCTAssertFalse(store.canSelectTab(atDisplayIndex: -1))

        store.selectTab(atDisplayIndex: 0)
        XCTAssertEqual(store.selectedTabID, firstTabID)

        store.selectTab(atDisplayIndex: 1)
        XCTAssertEqual(store.selectedTabID, secondTabID)

        store.selectTab(atDisplayIndex: 2)
        XCTAssertEqual(store.selectedTabID, thirdTabID)

        store.selectTab(atDisplayIndex: 9)
        XCTAssertEqual(store.selectedTabID, thirdTabID)
    }

    func testMoveTabLeftAndRightReordersTabsWithoutChangingSelection() {
        let store = makeStore()
        let firstTabID = store.selectedTabID
        store.addTab(opening: temporaryDirectory.appendingPathComponent("Second", isDirectory: true))
        let secondTabID = store.selectedTabID
        store.addTab(opening: temporaryDirectory.appendingPathComponent("Third", isDirectory: true))
        let thirdTabID = store.selectedTabID

        XCTAssertFalse(store.canMoveTabLeft(firstTabID))
        XCTAssertTrue(store.canMoveTabLeft(thirdTabID))
        XCTAssertFalse(store.canMoveTabRight(thirdTabID))

        store.moveTabLeft(thirdTabID)

        XCTAssertEqual(store.tabs.map(\.id), [firstTabID, thirdTabID, secondTabID])
        XCTAssertEqual(store.selectedTabID, thirdTabID)
        XCTAssertTrue(store.canMoveTabRight(thirdTabID))

        store.moveTabRight(thirdTabID)

        XCTAssertEqual(store.tabs.map(\.id), [firstTabID, secondTabID, thirdTabID])
        XCTAssertEqual(store.selectedTabID, thirdTabID)

        store.moveTabRight(thirdTabID)
        XCTAssertEqual(store.tabs.map(\.id), [firstTabID, secondTabID, thirdTabID])
    }

    func testMoveTabBeforeReordersTabsForDragDropWithoutChangingSelection() {
        let store = makeStore()
        let firstTabID = store.selectedTabID
        store.addTab(opening: temporaryDirectory.appendingPathComponent("Second", isDirectory: true))
        let secondTabID = store.selectedTabID
        store.addTab(opening: temporaryDirectory.appendingPathComponent("Third", isDirectory: true))
        let thirdTabID = store.selectedTabID

        store.moveTab(thirdTabID, before: firstTabID)

        XCTAssertEqual(store.tabs.map(\.id), [thirdTabID, firstTabID, secondTabID])
        XCTAssertEqual(store.selectedTabID, thirdTabID)

        store.moveTab(firstTabID, before: secondTabID)
        XCTAssertEqual(store.tabs.map(\.id), [thirdTabID, firstTabID, secondTabID])

        store.moveTab(firstTabID, before: thirdTabID)
        XCTAssertEqual(store.tabs.map(\.id), [firstTabID, thirdTabID, secondTabID])
        XCTAssertEqual(store.selectedTabID, thirdTabID)

        store.moveTab(firstTabID, before: firstTabID)
        XCTAssertEqual(store.tabs.map(\.id), [firstTabID, thirdTabID, secondTabID])
    }

    func testMoveTabToEndSupportsTrailingDropTargetWithoutChangingSelection() {
        let store = makeStore()
        let firstTabID = store.selectedTabID
        store.addTab(opening: temporaryDirectory.appendingPathComponent("Second", isDirectory: true))
        let secondTabID = store.selectedTabID
        store.addTab(opening: temporaryDirectory.appendingPathComponent("Third", isDirectory: true))
        let thirdTabID = store.selectedTabID

        store.moveTabToEnd(firstTabID)

        XCTAssertEqual(store.tabs.map(\.id), [secondTabID, thirdTabID, firstTabID])
        XCTAssertEqual(store.selectedTabID, thirdTabID)

        store.moveTabToEnd(firstTabID)
        XCTAssertEqual(store.tabs.map(\.id), [secondTabID, thirdTabID, firstTabID])
        XCTAssertEqual(store.selectedTabID, thirdTabID)
    }

    func testMoveTabToBeginningSupportsMenuCommandWithoutChangingSelection() {
        let store = makeStore()
        let firstTabID = store.selectedTabID
        store.addTab(opening: temporaryDirectory.appendingPathComponent("Second", isDirectory: true))
        let secondTabID = store.selectedTabID
        store.addTab(opening: temporaryDirectory.appendingPathComponent("Third", isDirectory: true))
        let thirdTabID = store.selectedTabID

        store.moveTabToBeginning(thirdTabID)

        XCTAssertEqual(store.tabs.map(\.id), [thirdTabID, firstTabID, secondTabID])
        XCTAssertEqual(store.selectedTabID, thirdTabID)

        store.moveTabToBeginning(thirdTabID)
        XCTAssertEqual(store.tabs.map(\.id), [thirdTabID, firstTabID, secondTabID])
        XCTAssertEqual(store.selectedTabID, thirdTabID)
    }

    func testBackForwardAndUpNavigationUpdateCurrentPath() throws {
        let parentURL = temporaryDirectory.appendingPathComponent("Parent", isDirectory: true)
        let childURL = parentURL.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: childURL, withIntermediateDirectories: true)
        let store = makeStore()

        store.open(parentURL)
        store.open(childURL)

        XCTAssertEqual(store.currentURL?.standardizedFileURL.path, childURL.standardizedFileURL.path)
        XCTAssertTrue(store.canGoBack)

        store.goBack()

        XCTAssertEqual(store.currentURL?.standardizedFileURL.path, parentURL.standardizedFileURL.path)
        XCTAssertTrue(store.canGoForward)

        store.goForward()

        XCTAssertEqual(store.currentURL?.standardizedFileURL.path, childURL.standardizedFileURL.path)

        store.goUp()

        XCTAssertEqual(store.currentURL?.standardizedFileURL.path, parentURL.standardizedFileURL.path)
    }

    func testHomeComputerAndNetworkCommandsNavigateCurrentTabWithHistory() throws {
        let nestedURL = temporaryDirectory.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        let store = makeStore()

        store.open(nestedURL)
        store.openHomeDirectory()

        XCTAssertEqual(
            store.currentURL?.standardizedFileURL,
            FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        )
        XCTAssertEqual(store.backHistoryLocations.first?.url.standardizedFileURL, nestedURL.standardizedFileURL)

        store.openComputerRoot()

        XCTAssertEqual(store.currentURL?.standardizedFileURL.path, "/")
        XCTAssertEqual(
            store.backHistoryLocations.first?.url.standardizedFileURL,
            FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        )

        store.openNetworkRoot()

        XCTAssertEqual(store.currentURL?.standardizedFileURL.path, "/Network")
        XCTAssertEqual(store.backHistoryLocations.first?.url.standardizedFileURL.path, "/")
    }

    func testNavigationHistoryLocationsCanJumpMultipleEntries() throws {
        let firstURL = temporaryDirectory.appendingPathComponent("First", isDirectory: true)
        let secondURL = temporaryDirectory.appendingPathComponent("Second", isDirectory: true)
        let thirdURL = temporaryDirectory.appendingPathComponent("Third", isDirectory: true)
        for url in [firstURL, secondURL, thirdURL] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        let store = makeStore()
        store.open(firstURL)
        store.open(secondURL)
        store.open(thirdURL)

        XCTAssertEqual(Array(store.backHistoryLocations.map(\.url.standardizedFileURL.path).prefix(3)), [
            secondURL.standardizedFileURL.path,
            firstURL.standardizedFileURL.path,
            temporaryDirectory.standardizedFileURL.path
        ])

        store.goBack(to: store.backHistoryLocations[1])

        XCTAssertEqual(store.currentURL?.standardizedFileURL.path, firstURL.standardizedFileURL.path)
        XCTAssertEqual(store.forwardHistoryLocations.map(\.url.standardizedFileURL.path), [
            secondURL.standardizedFileURL.path,
            thirdURL.standardizedFileURL.path
        ])

        store.goForward(to: store.forwardHistoryLocations[1])

        XCTAssertEqual(store.currentURL?.standardizedFileURL.path, thirdURL.standardizedFileURL.path)
        XCTAssertEqual(Array(store.backHistoryLocations.map(\.url.standardizedFileURL.path).prefix(3)), [
            secondURL.standardizedFileURL.path,
            firstURL.standardizedFileURL.path,
            temporaryDirectory.standardizedFileURL.path
        ])
    }

    func testNavigationHistoryLocationsKeepDuplicatePathsDistinct() throws {
        let firstURL = temporaryDirectory.appendingPathComponent("First", isDirectory: true)
        let secondURL = temporaryDirectory.appendingPathComponent("Second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondURL, withIntermediateDirectories: true)

        let store = makeStore()
        store.open(firstURL)
        store.open(secondURL)
        store.open(firstURL)
        store.open(secondURL)

        XCTAssertEqual(store.backHistoryLocations.map(\.url.standardizedFileURL.path), [
            firstURL.standardizedFileURL.path,
            secondURL.standardizedFileURL.path,
            firstURL.standardizedFileURL.path,
            temporaryDirectory.standardizedFileURL.path
        ])
        XCTAssertEqual(Set(store.backHistoryLocations.map(\.id)).count, store.backHistoryLocations.count)

        store.goBack(to: store.backHistoryLocations[2])

        XCTAssertEqual(store.currentURL?.standardizedFileURL.path, firstURL.standardizedFileURL.path)
        XCTAssertEqual(store.forwardHistoryLocations.map(\.url.standardizedFileURL.path), [
            secondURL.standardizedFileURL.path,
            firstURL.standardizedFileURL.path,
            secondURL.standardizedFileURL.path
        ])
    }

    func testRapidDirectoryChangesDebounceToBoundedReloads() async throws {
        let service = CountingFileSystemService()
        let store = makeStore(service: service)

        await waitForContentsCalls(service, atLeast: 1)
        let baseline = service.callCount
        XCTAssertEqual(store.currentURL?.standardizedFileURL, temporaryDirectory.standardizedFileURL)

        for index in 0..<30 {
            let url = temporaryDirectory.appendingPathComponent("created-\(index).txt")
            try "x".write(to: url, atomically: true, encoding: .utf8)
        }

        await waitForContentsCalls(service, atLeast: baseline + 1)
        try await Task.sleep(for: .milliseconds(350))

        XCTAssertLessThanOrEqual(service.callCount, baseline + 2)
    }

    func testFastNavigationDoesNotApplyStaleSlowDirectoryLoad() async throws {
        let slowURL = temporaryDirectory.appendingPathComponent("Slow", isDirectory: true)
        let fastURL = temporaryDirectory.appendingPathComponent("Fast", isDirectory: true)
        try FileManager.default.createDirectory(at: slowURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fastURL, withIntermediateDirectories: true)

        let service = StubbedFileSystemService()
        service.setDelay(.milliseconds(250), for: slowURL)
        service.setItems([stubItem(named: "slow.txt", in: slowURL)], for: slowURL)
        service.setItems([stubItem(named: "fast.txt", in: fastURL)], for: fastURL)

        let store = makeStore(service: service)
        await waitForTabLoad(store)

        store.open(slowURL)
        store.open(fastURL)

        await waitForItems(store, named: ["fast.txt"])

        XCTAssertEqual(store.currentURL?.standardizedFileURL, fastURL.standardizedFileURL)
        XCTAssertEqual(store.items.map(\.name), ["fast.txt"])

        try await Task.sleep(for: .milliseconds(350))

        XCTAssertEqual(store.currentURL?.standardizedFileURL, fastURL.standardizedFileURL)
        XCTAssertEqual(store.items.map(\.name), ["fast.txt"])
        XCTAssertFalse(store.items.contains { $0.name == "slow.txt" })
    }

    func testReopeningWarmDirectoryShowsSnapshotBeforeBackgroundRefresh() async throws {
        let targetURL = temporaryDirectory.appendingPathComponent("Target", isDirectory: true)
        let otherURL = temporaryDirectory.appendingPathComponent("Other", isDirectory: true)
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherURL, withIntermediateDirectories: true)

        let service = StubbedFileSystemService()
        service.setItems([stubItem(named: "cached.txt", in: targetURL)], for: targetURL)
        service.setItems([stubItem(named: "other.txt", in: otherURL)], for: otherURL)

        let store = makeStore(service: service)
        await waitForTabLoad(store)

        store.open(targetURL)
        await waitForItems(store, named: ["cached.txt"])

        service.setDelay(.milliseconds(220), for: targetURL)
        service.setItems([stubItem(named: "fresh.txt", in: targetURL)], for: targetURL)

        store.open(otherURL)
        await waitForItems(store, named: ["other.txt"])

        store.open(targetURL)

        XCTAssertEqual(store.currentURL?.standardizedFileURL, targetURL.standardizedFileURL)
        XCTAssertEqual(store.items.map(\.name), ["cached.txt"])

        await waitForItems(store, named: ["fresh.txt"])
    }

    func testRecursiveSearchRunsInBackgroundAndPublishesMatchingItems() async throws {
        let service = StubbedFileSystemService()
        let currentFolderItem = stubItem(named: "current-report.txt", in: temporaryDirectory)
        let nestedItem = stubItem(named: "nested-report.txt", in: temporaryDirectory.appendingPathComponent("Nested", isDirectory: true))
        service.setItems([currentFolderItem], for: temporaryDirectory)
        service.setSearchDelay(.milliseconds(250), for: temporaryDirectory, query: "report")
        service.setSearchItems([currentFolderItem, nestedItem], for: temporaryDirectory, query: "report")

        let store = makeStore(service: service)
        await waitForTabLoad(store)

        let elapsed = elapsedSeconds {
            store.searchesSubfolders = true
            store.query = "report"
        }

        XCTAssertLessThan(elapsed, 0.30)
        XCTAssertNil(store.searchSummary)
        XCTAssertEqual(store.visibleItems.map(\.name), ["current-report.txt"])

        await waitForSearch(store, query: "report")

        XCTAssertEqual(store.items.map(\.name), ["current-report.txt", "nested-report.txt"])
        XCTAssertEqual(store.searchSummary?.itemCount, 2)
        XCTAssertNil(store.loadSummary)
    }

    func testStaleRecursiveSearchDoesNotReplaceNewerSearchResults() async throws {
        let service = StubbedFileSystemService()
        service.setItems([], for: temporaryDirectory)
        service.setSearchDelay(.milliseconds(300), for: temporaryDirectory, query: "slow")
        service.setSearchItems([stubItem(named: "slow.txt", in: temporaryDirectory)], for: temporaryDirectory, query: "slow")
        service.setSearchItems([stubItem(named: "fast.txt", in: temporaryDirectory)], for: temporaryDirectory, query: "fast")

        let store = makeStore(service: service)
        await waitForTabLoad(store)

        store.searchesSubfolders = true
        store.query = "slow"
        try await Task.sleep(for: .milliseconds(300))
        store.query = "fast"

        await waitForSearch(store, query: "fast")

        XCTAssertEqual(store.items.map(\.name), ["fast.txt"])

        try await Task.sleep(for: .milliseconds(350))

        XCTAssertEqual(store.query, "fast")
        XCTAssertEqual(store.items.map(\.name), ["fast.txt"])
        XCTAssertFalse(store.items.contains { $0.name == "slow.txt" })
    }

    func testClearingRecursiveSearchReloadsCurrentFolderContents() async throws {
        let service = StubbedFileSystemService()
        let currentItem = stubItem(named: "current.txt", in: temporaryDirectory)
        let nestedItem = stubItem(named: "nested-report.txt", in: temporaryDirectory.appendingPathComponent("Nested", isDirectory: true))
        service.setItems([currentItem], for: temporaryDirectory)
        service.setSearchItems([nestedItem], for: temporaryDirectory, query: "report")

        let store = makeStore(service: service)
        await waitForTabLoad(store)

        store.searchesSubfolders = true
        store.query = "report"
        await waitForSearch(store, query: "report")

        XCTAssertEqual(store.items.map(\.name), ["nested-report.txt"])

        store.clearSearchAndContentFilters()
        await waitForTabLoad(store)

        XCTAssertFalse(store.searchesSubfolders)
        XCTAssertEqual(store.query, "")
        XCTAssertEqual(store.items.map(\.name), ["current.txt"])
        XCTAssertNil(store.searchSummary)
    }

    func testInitialSlowFolderReadDoesNotBlockStoreLaunch() async throws {
        let service = StubbedFileSystemService()
        service.setDelay(.seconds(1), for: temporaryDirectory)
        service.setItems(makeLargeItemSet(), for: temporaryDirectory)

        var launchedStore: BrowserStore?
        let elapsed = elapsedSeconds {
            launchedStore = makeStore(service: service)
            XCTAssertTrue(launchedStore?.isLoading ?? false)
        }

        XCTAssertLessThan(elapsed, 0.30)

        let store = try XCTUnwrap(launchedStore)
        await waitForTabLoad(store)
        XCTAssertEqual(store.items.count, 5_000)
        XCTAssertEqual(store.loadSummary?.itemCount, 5_000)
    }

    func testInitialLargeFolderLoadPublishesBenchmarkSummary() async {
        let service = StubbedFileSystemService()
        service.setItems(makeLargeItemSet(), for: temporaryDirectory)

        let store = makeStore(service: service)
        await waitForTabLoad(store)

        let elapsed = store.loadSummary?.elapsedSeconds ?? .infinity
        XCTContext.runActivity(named: "Store loaded \(store.items.count) items in \(String(format: "%.3f", elapsed)) seconds") { _ in
            XCTAssertEqual(store.items.count, 5_000)
            XCTAssertEqual(store.loadSummary?.itemCount, 5_000)
            XCTAssertLessThan(elapsed, 0.30)
        }

        XCTAssertEqual(store.lastPerformanceEvent?.label, "Loaded")
        XCTAssertEqual(store.lastPerformanceEvent?.itemCount, 5_000)
        XCTAssertEqual(store.lastPerformanceEvent?.path, temporaryDirectory.standardizedFileURL.path)
        XCTAssertLessThan(store.lastPerformanceEvent?.elapsedSeconds ?? .infinity, 0.30)
    }

    func testPerformanceEventTrailKeepsRecentLoadEventsOnly() async {
        let service = StubbedFileSystemService()
        service.setItems(makeLargeItemSet(count: 12), for: temporaryDirectory)

        let store = makeStore(service: service)
        await waitForTabLoad(store)

        for _ in 0..<30 {
            store.reload()
            await waitForTabLoad(store)
        }

        XCTAssertEqual(store.performanceEvents.count, 24)
        XCTAssertEqual(store.performanceEvents.first?.label, "Loaded")
        XCTAssertEqual(store.performanceEvents.last?.label, "Loaded")
        XCTAssertEqual(store.performanceEvents.last?.itemCount, 12)
        XCTAssertEqual(store.performanceEvents.last?.path, temporaryDirectory.standardizedFileURL.path)
    }

    func testCopyPerformanceReportWritesRecentBenchmarkEventsToPasteboard() async {
        let service = StubbedFileSystemService()
        service.setItems(makeLargeItemSet(count: 12), for: temporaryDirectory)

        let store = makeStore(service: service)
        await waitForTabLoad(store)

        store.copyPerformanceReport()

        let report = NSPasteboard.general.string(forType: .string) ?? ""
        XCTAssertTrue(report.hasPrefix("Action\tItems\tElapsed\tSeconds\tPath"))
        XCTAssertTrue(report.contains("Loaded\t12\t"))
        XCTAssertTrue(report.contains(temporaryDirectory.standardizedFileURL.path))
    }

    func testReloadingLargeFolderWithSmallSelectionStaysUnderInteractionBudget() async {
        let service = StubbedFileSystemService()
        let items = makeLargeItemSet()
        service.setItems(items, for: temporaryDirectory)

        let store = makeStore(service: service)
        await waitForTabLoad(store)

        let selectedID = items[4_321].id
        store.selectedItemIDs = [selectedID]
        store.reload()
        await waitForTabLoad(store)

        let elapsed = store.loadSummary?.elapsedSeconds ?? .infinity
        XCTContext.runActivity(named: "Reloaded 5,000 items while preserving a small selection in \(String(format: "%.3f", elapsed)) seconds") { _ in
            XCTAssertEqual(store.items.count, 5_000)
            XCTAssertEqual(store.selectedItemIDs, [selectedID])
            XCTAssertLessThan(elapsed, 0.30)
        }
    }

    func testRecursiveSearchLargeResultWithSmallSelectionStaysUnderInteractionBudget() async {
        let service = StubbedFileSystemService()
        let items = makeLargeItemSet()
        service.setItems(items, for: temporaryDirectory)
        service.setSearchItems(items, for: temporaryDirectory, query: "Document")

        let store = makeStore(service: service)
        await waitForTabLoad(store)

        store.searchesSubfolders = true
        store.query = "Document"
        await waitForSearch(store, query: "Document")

        let selectedID = items[3_777].id
        store.selectedItemIDs = [selectedID]
        store.reload()
        await waitForTabLoad(store)

        let elapsed = store.searchSummary?.elapsedSeconds ?? .infinity
        XCTContext.runActivity(named: "Searched 5,000 items while preserving a small selection in \(String(format: "%.3f", elapsed)) seconds") { _ in
            XCTAssertEqual(store.items.count, 5_000)
            XCTAssertEqual(store.selectedItemIDs, [selectedID])
            XCTAssertEqual(store.searchSummary?.query, "Document")
            XCTAssertLessThan(elapsed, 0.30)
        }

        XCTAssertEqual(store.lastPerformanceEvent?.label, "Searched")
        XCTAssertEqual(store.lastPerformanceEvent?.itemCount, 5_000)
        XCTAssertEqual(store.lastPerformanceEvent?.path, temporaryDirectory.standardizedFileURL.path)
        XCTAssertLessThan(store.lastPerformanceEvent?.elapsedSeconds ?? .infinity, 0.30)
    }

    func testTabSessionPersistsAcrossStoreInstances() throws {
        let firstURL = temporaryDirectory.appendingPathComponent("One", isDirectory: true)
        let secondURL = temporaryDirectory.appendingPathComponent("Two", isDirectory: true)
        try FileManager.default.createDirectory(at: firstURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondURL, withIntermediateDirectories: true)

        let firstStore = makeStore()
        firstStore.open(firstURL)
        firstStore.addTab(opening: secondURL)

        let secondStore = makeStore()

        XCTAssertEqual(secondStore.tabs.map { $0.currentURL?.standardizedFileURL.path }, [
            firstURL.standardizedFileURL.path,
            secondURL.standardizedFileURL.path
        ])
        XCTAssertEqual(secondStore.selectedTab.currentURL?.standardizedFileURL.path, secondURL.standardizedFileURL.path)
    }

    func testNewWindowStoreUsesRequestedFolderWithoutOverwritingMainTabSession() throws {
        let restoredURL = temporaryDirectory.appendingPathComponent("Restored", isDirectory: true)
        let targetURL = temporaryDirectory.appendingPathComponent("Target", isDirectory: true)
        let extraURL = temporaryDirectory.appendingPathComponent("Extra", isDirectory: true)
        try FileManager.default.createDirectory(at: restoredURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: extraURL, withIntermediateDirectories: true)

        userDefaults.set([restoredURL.path], forKey: "BetterFiles.tabPaths")
        userDefaults.set(restoredURL.path, forKey: "BetterFiles.selectedTabPath")

        let windowStore = BrowserStore(
            service: EmptyFileSystemService(),
            userDefaults: userDefaults,
            initialURL: targetURL,
            restoresTabSession: false,
            persistsTabSession: false
        )

        XCTAssertEqual(windowStore.tabs.map { $0.currentURL?.standardizedFileURL.path }, [targetURL.standardizedFileURL.path])
        XCTAssertEqual(windowStore.selectedTab.currentURL?.standardizedFileURL.path, targetURL.standardizedFileURL.path)

        windowStore.addTab(opening: extraURL)

        XCTAssertEqual(userDefaults.stringArray(forKey: "BetterFiles.tabPaths"), [restoredURL.path])
        XCTAssertEqual(userDefaults.string(forKey: "BetterFiles.selectedTabPath"), restoredURL.path)
    }

    func testRestoredTabsSkipMissingPathsAndDuplicates() throws {
        let existingURL = temporaryDirectory.appendingPathComponent("Existing", isDirectory: true)
        let missingURL = temporaryDirectory.appendingPathComponent("Missing", isDirectory: true)
        try FileManager.default.createDirectory(at: existingURL, withIntermediateDirectories: true)

        userDefaults.set(
            [existingURL.path, missingURL.path, existingURL.path],
            forKey: "BetterFiles.tabPaths"
        )
        userDefaults.set(existingURL.path, forKey: "BetterFiles.selectedTabPath")

        let store = makeStore()

        XCTAssertEqual(store.tabs.map { $0.currentURL?.standardizedFileURL.path }, [existingURL.standardizedFileURL.path])
        XCTAssertEqual(store.selectedTab.currentURL?.standardizedFileURL.path, existingURL.standardizedFileURL.path)
    }

    func testRestoringMaximumTabSessionStaysUnderLaunchBudget() throws {
        let directories = try (0..<12).map { index in
            let url = temporaryDirectory.appendingPathComponent("Restored-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        userDefaults.set(directories.map(\.path), forKey: "BetterFiles.tabPaths")
        userDefaults.set(directories[8].path, forKey: "BetterFiles.selectedTabPath")

        let elapsed = elapsedSeconds {
            let store = makeStore()
            XCTAssertEqual(store.tabs.count, 12)
            XCTAssertEqual(store.selectedTab.currentURL?.standardizedFileURL.path, directories[8].standardizedFileURL.path)
            XCTAssertEqual(store.tabs.flatMap(\.items).count, 0)
        }

        XCTAssertLessThan(elapsed, 0.30)
    }

    func testSwitchingBetweenCachedLargeTabsStaysUnderInteractionBudget() {
        let store = makeStore()
        let firstTabID = store.selectedTabID
        store.addTab(opening: temporaryDirectory.appendingPathComponent("Second", isDirectory: true))
        let secondTabID = store.selectedTabID
        store.addTab(opening: temporaryDirectory.appendingPathComponent("Third", isDirectory: true))
        let thirdTabID = store.selectedTabID

        store.tabs[0].items = makeLargeItemSet(prefix: "One")
        store.tabs[1].items = makeLargeItemSet(prefix: "Two")
        store.tabs[2].items = makeLargeItemSet(prefix: "Three")

        let elapsed = elapsedSeconds {
            for tabID in [firstTabID, secondTabID, thirdTabID].cycled(prefix: 300) {
                store.selectTab(tabID)
                XCTAssertEqual(store.visibleItems.count, 5_000)
            }
        }

        XCTAssertLessThan(elapsed, 0.30)
    }

    func testRecentDirectoriesPersistDeduplicateAndClear() throws {
        let firstURL = temporaryDirectory.appendingPathComponent("First", isDirectory: true)
        let secondURL = temporaryDirectory.appendingPathComponent("Second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondURL, withIntermediateDirectories: true)

        let firstStore = makeStore()
        firstStore.open(firstURL)
        firstStore.open(secondURL)
        firstStore.open(firstURL)

        XCTAssertEqual(firstStore.recentDirectories.map(\.standardizedFileURL.path), [
            firstURL.standardizedFileURL.path,
            secondURL.standardizedFileURL.path
        ])

        let secondStore = makeStore()
        XCTAssertEqual(secondStore.recentDirectories.map(\.standardizedFileURL.path), [
            firstURL.standardizedFileURL.path,
            secondURL.standardizedFileURL.path
        ])

        secondStore.clearRecentDirectories()

        XCTAssertTrue(secondStore.recentDirectories.isEmpty)
        XCTAssertTrue(makeStore().recentDirectories.isEmpty)
    }

    func testRecentFilesPersistDeduplicateAndClear() throws {
        let firstURL = temporaryDirectory.appendingPathComponent("first.txt")
        let secondURL = temporaryDirectory.appendingPathComponent("second.txt")
        try Data("first".utf8).write(to: firstURL)
        try Data("second".utf8).write(to: secondURL)

        let firstStore = makeStore()
        firstStore.recordRecentFile(firstURL)
        firstStore.recordRecentFile(secondURL)
        firstStore.recordRecentFile(firstURL)

        XCTAssertEqual(firstStore.recentFiles.map(\.standardizedFileURL.path), [
            firstURL.standardizedFileURL.path,
            secondURL.standardizedFileURL.path
        ])

        let secondStore = makeStore()
        XCTAssertEqual(secondStore.recentFiles.map(\.standardizedFileURL.path), [
            firstURL.standardizedFileURL.path,
            secondURL.standardizedFileURL.path
        ])

        secondStore.clearRecentFiles()

        XCTAssertTrue(secondStore.recentFiles.isEmpty)
        XCTAssertTrue(makeStore().recentFiles.isEmpty)
    }

    func testOpenRecentFileLocationNavigatesToParentAndSelectsFile() throws {
        let nestedURL = temporaryDirectory.appendingPathComponent("Recent", isDirectory: true)
        let fileURL = nestedURL.appendingPathComponent("brief.pdf")
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        try Data("brief".utf8).write(to: fileURL)

        let store = makeStore()
        store.openRecentFileLocation(fileURL)

        XCTAssertEqual(store.currentURL?.standardizedFileURL, nestedURL.standardizedFileURL)
        XCTAssertEqual(store.selectedItemIDs, [fileURL.standardizedFileURL.path])
        XCTAssertEqual(store.recentFiles.first?.standardizedFileURL, fileURL.standardizedFileURL)
    }

    func testOpenMissingRecentFileLocationRemovesStaleEntryAndReportsError() {
        let missingURL = temporaryDirectory.appendingPathComponent("missing.pdf")
        let store = makeStore()
        store.recentFiles = [missingURL]

        store.openRecentFileLocation(missingURL)

        XCTAssertTrue(store.recentFiles.isEmpty)
        XCTAssertEqual(store.currentURL?.standardizedFileURL, temporaryDirectory.standardizedFileURL)
        XCTAssertEqual(store.errorMessage, "Recent file is no longer available: \(missingURL.standardizedFileURL.path)")
    }

    func testRestoredRecentDirectoriesSkipMissingPathsAndStayUnderLaunchBudget() throws {
        let directories = try (0..<8).map { index in
            let url = temporaryDirectory.appendingPathComponent("Recent-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let missingURL = temporaryDirectory.appendingPathComponent("Missing", isDirectory: true)
        userDefaults.set(
            directories.map(\.path) + [missingURL.path, directories[0].path],
            forKey: "BetterFiles.recentDirectoryPaths"
        )

        let elapsed = elapsedSeconds {
            let store = makeStore()
            XCTAssertEqual(store.recentDirectories.map(\.standardizedFileURL.path), directories.map(\.standardizedFileURL.path))
        }

        XCTAssertLessThan(elapsed, 0.30)
    }

    func testRestoredRecentFilesSkipMissingPathsDirectoriesAndStayUnderLaunchBudget() throws {
        let files = try (0..<12).map { index in
            let url = temporaryDirectory.appendingPathComponent("Recent-\(index).txt")
            try Data("recent-\(index)".utf8).write(to: url)
            return url
        }
        let directoryURL = temporaryDirectory.appendingPathComponent("NotAFile", isDirectory: true)
        let missingURL = temporaryDirectory.appendingPathComponent("Missing.txt")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        userDefaults.set(
            files.map(\.path) + [directoryURL.path, missingURL.path, files[0].path],
            forKey: "BetterFiles.recentFilePaths"
        )

        let elapsed = elapsedSeconds {
            let store = makeStore()
            XCTAssertEqual(store.recentFiles.map(\.standardizedFileURL.path), files.map(\.standardizedFileURL.path))
        }

        XCTAssertLessThan(elapsed, 0.30)
    }

    func testPinnedDirectoriesPersistDeduplicateAndDoNotDuplicateInRecents() throws {
        let firstURL = temporaryDirectory.appendingPathComponent("Pinned", isDirectory: true)
        let secondURL = temporaryDirectory.appendingPathComponent("Second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondURL, withIntermediateDirectories: true)

        let firstStore = makeStore()
        firstStore.open(firstURL)
        firstStore.open(secondURL)
        firstStore.pinDirectory(firstURL)
        firstStore.pinDirectory(firstURL)

        XCTAssertEqual(firstStore.pinnedDirectories.map(\.standardizedFileURL.path), [firstURL.standardizedFileURL.path])
        XCTAssertEqual(firstStore.recentDirectories.map(\.standardizedFileURL.path), [secondURL.standardizedFileURL.path])
        XCTAssertTrue(firstStore.isPinnedDirectory(firstURL))

        let secondStore = makeStore()
        XCTAssertEqual(secondStore.pinnedDirectories.map(\.standardizedFileURL.path), [firstURL.standardizedFileURL.path])

        secondStore.unpinDirectory(firstURL)

        XCTAssertFalse(secondStore.isPinnedDirectory(firstURL))
        XCTAssertTrue(makeStore().pinnedDirectories.isEmpty)
    }

    func testPinSelectedFoldersToSidebarIgnoresFilesAndPersists() throws {
        let folderURL = temporaryDirectory.appendingPathComponent("Folder To Pin", isDirectory: true)
        let fileURL = temporaryDirectory.appendingPathComponent("notes.txt")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try "notes".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.tabs[0].items = [
            makeItem(name: "Folder To Pin", kind: .folder, byteCount: nil),
            makeItem(name: "notes.txt", kind: .file, byteCount: 5)
        ]
        store.selectedItemIDs = Set(store.tabs[0].items.map(\.id))

        XCTAssertTrue(store.canPinSelectionToSidebar)
        XCTAssertFalse(store.canUnpinSelectionFromSidebar)
        XCTAssertTrue(store.pinSelectedFoldersToSidebar())
        XCTAssertEqual(store.pinnedDirectories.map(\.standardizedFileURL.path), [folderURL.standardizedFileURL.path])
        XCTAssertFalse(store.pinnedDirectories.contains(fileURL.standardizedFileURL))

        let restoredStore = makeStore()
        XCTAssertEqual(restoredStore.pinnedDirectories.map(\.standardizedFileURL.path), [folderURL.standardizedFileURL.path])
    }

    func testPinSelectedFolderAliasToSidebarResolvesTargetAndState() throws {
        let folderURL = temporaryDirectory.appendingPathComponent("Aliased Folder", isDirectory: true)
        let aliasURL = temporaryDirectory.appendingPathComponent("Aliased Folder Alias")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let bookmarkData = try folderURL.bookmarkData(
            options: [.suitableForBookmarkFile],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        try URL.writeBookmarkData(bookmarkData, to: aliasURL)

        let store = makeStore()
        let aliasItem = makeItem(name: "Aliased Folder Alias", kind: .file, byteCount: 5)
        store.tabs[0].items = [aliasItem]
        store.selectedItemIDs = [aliasItem.id]

        XCTAssertTrue(store.canPinSelectionToSidebar)
        XCTAssertFalse(store.isPinnedFolderTarget(aliasItem))
        XCTAssertTrue(store.pinSelectedFoldersToSidebar())
        XCTAssertEqual(store.pinnedDirectories.map(\.standardizedFileURL.path), [folderURL.standardizedFileURL.path])
        XCTAssertTrue(store.isPinnedFolderTarget(aliasItem))
        XCTAssertFalse(store.canPinSelectionToSidebar)
        XCTAssertTrue(store.canUnpinSelectionFromSidebar)
        XCTAssertTrue(store.unpinSelectedFoldersFromSidebar())
        XCTAssertFalse(store.isPinnedFolderTarget(aliasItem))
        XCTAssertTrue(store.pinnedDirectories.isEmpty)
    }

    func testUnpinSelectedFoldersFromSidebarOnlyRemovesPinnedSelection() throws {
        let pinnedURL = temporaryDirectory.appendingPathComponent("Pinned Folder", isDirectory: true)
        let otherURL = temporaryDirectory.appendingPathComponent("Other Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: pinnedURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherURL, withIntermediateDirectories: true)

        let store = makeStore()
        store.pinDirectory(pinnedURL)
        store.pinDirectory(otherURL)
        store.tabs[0].items = [
            makeItem(name: "Pinned Folder", kind: .folder, byteCount: nil)
        ]
        store.selectedItemIDs = [store.tabs[0].items[0].id]

        XCTAssertFalse(store.canPinSelectionToSidebar)
        XCTAssertTrue(store.canUnpinSelectionFromSidebar)
        XCTAssertTrue(store.unpinSelectedFoldersFromSidebar())
        XCTAssertEqual(store.pinnedDirectories.map(\.standardizedFileURL.path), [otherURL.standardizedFileURL.path])
    }

    func testRestoredPinnedDirectoriesSkipMissingPathsAndStayUnderLaunchBudget() throws {
        let directories = try (0..<8).map { index in
            let url = temporaryDirectory.appendingPathComponent("Pinned-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let missingURL = temporaryDirectory.appendingPathComponent("MissingPinned", isDirectory: true)
        userDefaults.set(
            directories.map(\.path) + [missingURL.path, directories[0].path],
            forKey: "BetterFiles.pinnedDirectoryPaths"
        )

        let elapsed = elapsedSeconds {
            let store = makeStore()
            XCTAssertEqual(store.pinnedDirectories.map(\.standardizedFileURL.path), directories.map(\.standardizedFileURL.path))
        }

        XCTAssertLessThan(elapsed, 0.30)
    }

    func testCloseOtherTabsKeepsRequestedTab() {
        let store = makeStore()
        let firstTabID = store.selectedTabID
        store.addTab(opening: temporaryDirectory.appendingPathComponent("Second", isDirectory: true))
        store.addTab(opening: temporaryDirectory.appendingPathComponent("Third", isDirectory: true))

        store.closeOtherTabs(keeping: firstTabID)

        XCTAssertEqual(store.tabs.map(\.id), [firstTabID])
        XCTAssertEqual(store.selectedTabID, firstTabID)
    }

    func testCloseTabsToRightKeepsLeftTabsAndSelection() {
        let store = makeStore()
        let firstTabID = store.selectedTabID
        store.addTab(opening: temporaryDirectory.appendingPathComponent("Second", isDirectory: true))
        let secondTabID = store.selectedTabID
        store.addTab(opening: temporaryDirectory.appendingPathComponent("Third", isDirectory: true))

        store.selectTab(firstTabID)
        store.closeTabsToRight(of: secondTabID)

        XCTAssertEqual(store.tabs.map(\.id), [firstTabID, secondTabID])
        XCTAssertEqual(store.selectedTabID, firstTabID)
    }

    func testCloseTabsToRightFallsBackToRequestedTabWhenSelectionIsRemoved() {
        let store = makeStore()
        let firstTabID = store.selectedTabID
        store.addTab(opening: temporaryDirectory.appendingPathComponent("Second", isDirectory: true))
        store.addTab(opening: temporaryDirectory.appendingPathComponent("Third", isDirectory: true))

        store.closeTabsToRight(of: firstTabID)

        XCTAssertEqual(store.tabs.map(\.id), [firstTabID])
        XCTAssertEqual(store.selectedTabID, firstTabID)
    }

    func testMoveSelectedTabToNewWindowRemovesTabAndReturnsFolder() {
        let store = makeStore()
        let firstTabID = store.selectedTabID
        let secondURL = temporaryDirectory.appendingPathComponent("Second", isDirectory: true)

        store.addTab(opening: secondURL)
        let secondTabID = store.selectedTabID

        let movedURL = store.moveTabToNewWindow(secondTabID)

        XCTAssertEqual(movedURL?.standardizedFileURL.path, secondURL.standardizedFileURL.path)
        XCTAssertEqual(store.tabs.map(\.id), [firstTabID])
        XCTAssertEqual(store.selectedTabID, firstTabID)
        XCTAssertFalse(store.canReopenClosedTab)
    }

    func testMoveBackgroundTabToNewWindowPreservesSelectedTab() {
        let store = makeStore()
        let firstTabID = store.selectedTabID
        let secondURL = temporaryDirectory.appendingPathComponent("Second", isDirectory: true)
        let thirdURL = temporaryDirectory.appendingPathComponent("Third", isDirectory: true)

        store.addTab(opening: secondURL)
        let secondTabID = store.selectedTabID
        store.addTab(opening: thirdURL)
        let thirdTabID = store.selectedTabID

        let movedURL = store.moveTabToNewWindow(secondTabID)

        XCTAssertEqual(movedURL?.standardizedFileURL.path, secondURL.standardizedFileURL.path)
        XCTAssertEqual(store.tabs.map(\.id), [firstTabID, thirdTabID])
        XCTAssertEqual(store.selectedTabID, thirdTabID)
        XCTAssertTrue(store.closedTabURLs.isEmpty)
    }

    func testMoveOnlyTabToNewWindowReturnsNil() {
        let store = makeStore()

        XCTAssertNil(store.moveTabToNewWindow(store.selectedTabID))
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertTrue(store.tabs.contains { $0.id == store.selectedTabID })
    }

    func testReopenClosedTabRestoresMostRecentlyClosedFolders() {
        let store = makeStore()
        let secondURL = temporaryDirectory.appendingPathComponent("Second", isDirectory: true)
        let thirdURL = temporaryDirectory.appendingPathComponent("Third", isDirectory: true)

        store.addTab(opening: secondURL)
        let secondTabID = store.selectedTabID
        store.addTab(opening: thirdURL)
        let thirdTabID = store.selectedTabID

        store.closeTab(thirdTabID)
        store.closeTab(secondTabID)

        XCTAssertTrue(store.canReopenClosedTab)
        XCTAssertEqual(store.closedTabURLs.map(\.standardizedFileURL.path), [
            thirdURL.standardizedFileURL.path,
            secondURL.standardizedFileURL.path
        ])

        store.reopenClosedTab()

        XCTAssertEqual(store.selectedTab.currentURL?.standardizedFileURL.path, secondURL.standardizedFileURL.path)

        store.reopenClosedTab()

        XCTAssertEqual(store.selectedTab.currentURL?.standardizedFileURL.path, thirdURL.standardizedFileURL.path)
        XCTAssertFalse(store.canReopenClosedTab)
    }

    func testReopenClosedTabRestoresOriginalPosition() {
        let store = makeStore()
        let firstURL = store.currentURL
        let secondURL = temporaryDirectory.appendingPathComponent("Second", isDirectory: true)
        let thirdURL = temporaryDirectory.appendingPathComponent("Third", isDirectory: true)

        store.addTab(opening: secondURL)
        let secondTabID = store.selectedTabID
        store.addTab(opening: thirdURL)

        store.closeTab(secondTabID)
        XCTAssertEqual(store.tabs.map { $0.currentURL?.standardizedFileURL.path }, [
            firstURL?.standardizedFileURL.path,
            thirdURL.standardizedFileURL.path
        ])

        store.reopenClosedTab()

        XCTAssertEqual(store.tabs.map { $0.currentURL?.standardizedFileURL.path }, [
            firstURL?.standardizedFileURL.path,
            secondURL.standardizedFileURL.path,
            thirdURL.standardizedFileURL.path
        ])
        XCTAssertEqual(store.selectedTab.currentURL?.standardizedFileURL.path, secondURL.standardizedFileURL.path)
    }

    func testClosedTabHistoryIsBounded() {
        let store = makeStore()

        for index in 0..<14 {
            let url = temporaryDirectory.appendingPathComponent("Closed-\(index)", isDirectory: true)
            store.addTab(opening: url)
            store.closeTab(store.selectedTabID)
        }

        XCTAssertEqual(store.closedTabURLs.count, 12)
        XCTAssertEqual(store.closedTabURLs.first?.lastPathComponent, "Closed-2")
        XCTAssertEqual(store.closedTabURLs.last?.lastPathComponent, "Closed-13")
    }

    func testCopySelectedPathsWritesNewlineSeparatedPathsToPasteboard() {
        let store = makeStore()
        let first = makeItem(name: "a.txt", kind: .file, byteCount: 1)
        let second = makeItem(name: "b.txt", kind: .file, byteCount: 1)
        store.tabs[0].items = [first, second]
        store.selectedItemIDs = [first.id, second.id]

        store.copySelectedPaths()

        let pasteboardValue = NSPasteboard.general.string(forType: .string) ?? ""
        XCTAssertTrue(pasteboardValue.contains(first.url.path))
        XCTAssertTrue(pasteboardValue.contains(second.url.path))
    }

    func testCopySelectedPathsAsQuotedPathsWritesWindowsStyleQuotedPathsWithoutChangingSelection() {
        let store = makeStore()
        let sharedDirectory = temporaryDirectory.appendingPathComponent("Shared Folder", isDirectory: true)
        let first = stubItem(named: "alpha file.txt", in: sharedDirectory)
        let second = stubItem(named: "quote \" file.txt", in: sharedDirectory)
        store.tabs[0].items = [first, second]
        store.selectedItemIDs = [first.id, second.id]

        store.copySelectedPathsAsQuotedPaths()

        let expected = [
            quotedPathExpectation(first.url.standardizedFileURL.path),
            quotedPathExpectation(second.url.standardizedFileURL.path)
        ].joined(separator: "\n")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), expected)
        XCTAssertEqual(store.selectedItemIDs, [first.id, second.id])
    }

    func testCopySelectedNamesWritesNewlineSeparatedNamesToPasteboard() {
        let store = makeStore()
        let first = makeItem(name: "a.txt", kind: .file, byteCount: 1)
        let second = makeItem(name: "b.txt", kind: .file, byteCount: 1)
        store.tabs[0].items = [first, second]
        store.selectedItemIDs = [first.id, second.id]

        store.copySelectedNames()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "a.txt\nb.txt")
    }

    func testCopySelectedParentFolderPathsDeduplicatesParentsWithoutChangingSelection() {
        let store = makeStore()
        let sharedDirectory = temporaryDirectory.appendingPathComponent("Shared", isDirectory: true)
        let otherDirectory = temporaryDirectory.appendingPathComponent("Other", isDirectory: true)
        let first = stubItem(named: "a.txt", in: sharedDirectory)
        let second = stubItem(named: "b.txt", in: sharedDirectory)
        let third = stubItem(named: "c.txt", in: otherDirectory)
        store.tabs[0].items = [first, second, third]
        store.selectedItemIDs = [first.id, second.id, third.id]

        store.copySelectedParentFolderPaths()

        XCTAssertEqual(
            NSPasteboard.general.string(forType: .string),
            "\(sharedDirectory.standardizedFileURL.path)\n\(otherDirectory.standardizedFileURL.path)"
        )
        XCTAssertEqual(store.selectedItemIDs, [first.id, second.id, third.id])
    }

    func testCopyPathWritesSingleLocationToPasteboardWithoutChangingSelection() {
        let store = makeStore()
        let first = makeItem(name: "a.txt", kind: .file, byteCount: 1)
        let sidebarURL = temporaryDirectory.appendingPathComponent("Sidebar", isDirectory: true)
        store.tabs[0].items = [first]
        store.selectedItemIDs = [first.id]

        store.copyPath(of: sidebarURL)

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), sidebarURL.standardizedFileURL.path)
        XCTAssertEqual(store.selectedItemIDs, [first.id])
    }

    func testCopyPathAsQuotedPathWritesSingleLocationWithoutChangingSelection() {
        let store = makeStore()
        let first = makeItem(name: "a.txt", kind: .file, byteCount: 1)
        let sidebarURL = temporaryDirectory.appendingPathComponent("Sidebar Folder", isDirectory: true)
        store.tabs[0].items = [first]
        store.selectedItemIDs = [first.id]

        store.copyPathAsQuotedPath(of: sidebarURL)

        XCTAssertEqual(
            NSPasteboard.general.string(forType: .string),
            quotedPathExpectation(sidebarURL.standardizedFileURL.path)
        )
        XCTAssertEqual(store.selectedItemIDs, [first.id])
    }

    func testPathComponentsEndAtCurrentFolder() {
        let store = makeStore()
        let nestedURL = temporaryDirectory
            .appendingPathComponent("Projects", isDirectory: true)
            .appendingPathComponent("Client", isDirectory: true)

        store.open(nestedURL)

        XCTAssertEqual(store.pathComponents.last?.name, "Client")
        XCTAssertEqual(store.pathComponents.last?.url.standardizedFileURL, nestedURL.standardizedFileURL)
        XCTAssertEqual(store.pathComponents.first?.url.path, "/")
    }

    func testSidebarPathComponentsShowCurrentFolderTrailWithoutRoot() {
        let store = makeStore()
        let nestedURL = temporaryDirectory
            .appendingPathComponent("Projects", isDirectory: true)
            .appendingPathComponent("Client", isDirectory: true)
            .appendingPathComponent("Release", isDirectory: true)

        store.open(nestedURL)

        let sidebarTrail = store.sidebarPathComponents

        XCTAssertFalse(sidebarTrail.isEmpty)
        XCTAssertLessThanOrEqual(sidebarTrail.count, 5)
        XCTAssertFalse(sidebarTrail.contains { $0.url.standardizedFileURL.path == "/" })
        XCTAssertEqual(sidebarTrail.last?.name, "Release")
        XCTAssertEqual(sidebarTrail.last?.url.standardizedFileURL, nestedURL.standardizedFileURL)
        XCTAssertEqual(
            sidebarTrail.map(\.url.standardizedFileURL.path),
            Array(store.pathComponents.filter { $0.url.path != "/" }.suffix(5)).map(\.url.standardizedFileURL.path)
        )
    }

    func testSidebarRevealTargetPrefersDeepestQuickAccessMatchOverRootVolume() {
        let rootVolume = URL(fileURLWithPath: "/", isDirectory: true)
        let pinnedURL = temporaryDirectory.appendingPathComponent("Projects", isDirectory: true)
        let recentURL = pinnedURL.appendingPathComponent("Client", isDirectory: true)
        let currentURL = recentURL.appendingPathComponent("Release", isDirectory: true)

        let revealURL = SidebarRevealTarget.bestCandidateURL(
            for: currentURL,
            in: [
                SidebarRevealCandidate(url: rootVolume, includesRootDescendants: true),
                SidebarRevealCandidate(url: pinnedURL),
                SidebarRevealCandidate(url: recentURL)
            ]
        )

        XCTAssertEqual(revealURL, recentURL.standardizedFileURL)
    }

    func testSidebarRevealTargetUsesRootVolumeOnlyWhenNoSpecificLocationMatches() {
        let rootVolume = URL(fileURLWithPath: "/", isDirectory: true)
        let unrelatedPinnedURL = temporaryDirectory.appendingPathComponent("Pinned", isDirectory: true)
        let currentURL = URL(fileURLWithPath: "/private/tmp/BetterFilesRootOnly", isDirectory: true)

        let revealURL = SidebarRevealTarget.bestCandidateURL(
            for: currentURL,
            in: [
                SidebarRevealCandidate(url: rootVolume, includesRootDescendants: true),
                SidebarRevealCandidate(url: unrelatedPinnedURL)
            ]
        )

        XCTAssertEqual(revealURL, rootVolume.standardizedFileURL)
    }

    func testSidebarRevealPathExpandsAncestorChainToCurrentLocation() {
        let projectsURL = temporaryDirectory.appendingPathComponent("Projects", isDirectory: true)
        let clientURL = projectsURL.appendingPathComponent("Client", isDirectory: true)
        let releaseURL = clientURL.appendingPathComponent("Release", isDirectory: true)

        let expandedURLs = SidebarRevealPath.ancestorURLsToExpand(
            for: releaseURL,
            from: projectsURL
        )

        XCTAssertEqual(
            expandedURLs.map(\.standardizedFileURL.path),
            [
                projectsURL.standardizedFileURL.path,
                clientURL.standardizedFileURL.path
            ]
        )
    }

    func testSidebarRevealPathExpandsRootVolumeTowardCurrentLocation() {
        let currentURL = URL(fileURLWithPath: "/Users/leo/Projects/better-files", isDirectory: true)

        let expandedURLs = SidebarRevealPath.ancestorURLsToExpand(
            for: currentURL,
            from: URL(fileURLWithPath: "/", isDirectory: true)
        )

        XCTAssertEqual(
            expandedURLs.map(\.standardizedFileURL.path),
            [
                "/",
                "/Users",
                "/Users/leo",
                "/Users/leo/Projects"
            ]
        )
    }

    func testSidebarRevealPathRepeatedResolutionStaysUnderInteractionBudget() {
        let rootURL = temporaryDirectory.appendingPathComponent("Root", isDirectory: true)
        let currentURL = rootURL
            .appendingPathComponent("One", isDirectory: true)
            .appendingPathComponent("Two", isDirectory: true)
            .appendingPathComponent("Three", isDirectory: true)
            .appendingPathComponent("Four", isDirectory: true)
            .appendingPathComponent("Five", isDirectory: true)
            .appendingPathComponent("Current", isDirectory: true)

        let elapsed = elapsedSeconds {
            for _ in 0..<1_000 {
                let expandedURLs = SidebarRevealPath.ancestorURLsToExpand(
                    for: currentURL,
                    from: rootURL
                )

                XCTAssertEqual(expandedURLs.count, 6)
            }
        }

        XCTAssertLessThan(elapsed, 0.08)
    }

    func testSidebarChildListKeepsCurrentBranchVisibleWhenFolderListIsCapped() {
        let rootURL = temporaryDirectory.appendingPathComponent("Root", isDirectory: true)
        let preferredURL = rootURL.appendingPathComponent("Zebra", isDirectory: true)
        let currentURL = preferredURL
            .appendingPathComponent("Deep", isDirectory: true)
            .appendingPathComponent("Current", isDirectory: true)

        let folders = (0..<60).map { index in
            let name = String(format: "Alpha-%02d", index)
            return BrowserPathComponent(
                name: name,
                url: rootURL.appendingPathComponent(name, isDirectory: true)
            )
        } + [
            BrowserPathComponent(name: "Zebra", url: preferredURL)
        ]

        let visibleFolders = SidebarChildListResolver.visibleFolders(
            folders,
            inside: rootURL,
            limit: 12,
            preferredDescendantURL: currentURL
        )

        XCTAssertEqual(visibleFolders.count, 12)
        XCTAssertTrue(visibleFolders.contains { $0.url.standardizedFileURL == preferredURL.standardizedFileURL })
        XCTAssertFalse(visibleFolders.contains { $0.name == "Alpha-11" })
    }

    func testSidebarChildListDirectChildResolvesRootAndNonRootPaths() {
        let projectsURL = temporaryDirectory.appendingPathComponent("Projects", isDirectory: true)
        let clientURL = projectsURL.appendingPathComponent("Client", isDirectory: true)
        let releaseURL = clientURL.appendingPathComponent("Release", isDirectory: true)

        XCTAssertEqual(
            SidebarChildListResolver.directChildURL(inside: projectsURL, toward: releaseURL),
            clientURL.standardizedFileURL
        )
        XCTAssertEqual(
            SidebarChildListResolver.directChildURL(
                inside: URL(fileURLWithPath: "/", isDirectory: true),
                toward: URL(fileURLWithPath: "/Users/leo/Projects", isDirectory: true)
            ),
            URL(fileURLWithPath: "/Users", isDirectory: true).standardizedFileURL
        )
        XCTAssertNil(SidebarChildListResolver.directChildURL(inside: projectsURL, toward: projectsURL))
        XCTAssertNil(SidebarChildListResolver.directChildURL(inside: clientURL, toward: projectsURL))
    }

    func testSidebarScopeResolverPrefersDeepestActiveSectionRoot() {
        let rootVolume = URL(fileURLWithPath: "/", isDirectory: true)
        let projectsURL = temporaryDirectory.appendingPathComponent("Projects", isDirectory: true)
        let clientURL = projectsURL.appendingPathComponent("Client", isDirectory: true)
        let currentURL = clientURL.appendingPathComponent("Release", isDirectory: true)

        let activeRootPath = SidebarScopeResolver.primaryActiveRootPath(
            for: currentURL,
            mountedVolumes: [rootVolume],
            pinnedDirectories: [projectsURL],
            recentDirectories: [clientURL],
            favorites: []
        )

        XCTAssertEqual(activeRootPath, clientURL.standardizedFileURL.path)
        XCTAssertFalse(SidebarScopeResolver.sectionContains(activeRootPath, urls: [rootVolume]))
        XCTAssertFalse(SidebarScopeResolver.sectionContains(activeRootPath, urls: [projectsURL]))
        XCTAssertTrue(SidebarScopeResolver.sectionContains(activeRootPath, urls: [clientURL]))
    }

    func testSidebarScopeResolverFallsBackToRootVolumeSection() {
        let rootVolume = URL(fileURLWithPath: "/", isDirectory: true)
        let currentURL = URL(fileURLWithPath: "/private/tmp/BetterFilesRootScope", isDirectory: true)

        let activeRootPath = SidebarScopeResolver.primaryActiveRootPath(
            for: currentURL,
            mountedVolumes: [rootVolume],
            pinnedDirectories: [],
            recentDirectories: [],
            favorites: []
        )

        XCTAssertEqual(activeRootPath, rootVolume.standardizedFileURL.path)
        XCTAssertTrue(SidebarScopeResolver.sectionContains(activeRootPath, urls: [rootVolume]))
    }

    func testLocationScopeResolverPrefersHomeNetworkThenThisMac() {
        let homeURL = temporaryDirectory.appendingPathComponent("Home", isDirectory: true)
        let networkURL = temporaryDirectory.appendingPathComponent("Network", isDirectory: true)
        let desktopURL = homeURL.appendingPathComponent("Desktop", isDirectory: true)
        let serverURL = networkURL.appendingPathComponent("Server", isDirectory: true)
        let systemURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        XCTAssertEqual(
            LocationScopeResolver.scope(for: desktopURL, homeURL: homeURL, networkURL: networkURL),
            .home
        )
        XCTAssertEqual(
            LocationScopeResolver.scope(for: serverURL, homeURL: homeURL, networkURL: networkURL),
            .network
        )
        XCTAssertEqual(
            LocationScopeResolver.scope(for: systemURL, homeURL: homeURL, networkURL: networkURL),
            .thisMac
        )
    }

    func testLocationScopeResolverGivesExclusiveSidebarAnchorState() {
        let homeURL = temporaryDirectory.appendingPathComponent("Home", isDirectory: true)
        let networkURL = temporaryDirectory.appendingPathComponent("Network", isDirectory: true)
        let documentURL = homeURL.appendingPathComponent("Documents", isDirectory: true)

        XCTAssertTrue(
            LocationScopeResolver.isScopeActive(.home, for: documentURL, homeURL: homeURL, networkURL: networkURL)
        )
        XCTAssertFalse(
            LocationScopeResolver.isScopeActive(.thisMac, for: documentURL, homeURL: homeURL, networkURL: networkURL)
        )
        XCTAssertFalse(
            LocationScopeResolver.isScopeActive(.network, for: documentURL, homeURL: homeURL, networkURL: networkURL)
        )
    }

    func testVisibleIconWarmupPolicyCapsPreloadByLayoutDensity() {
        XCTAssertEqual(VisibleIconWarmupPolicy.limit(for: .details, compactView: false), 96)
        XCTAssertEqual(VisibleIconWarmupPolicy.limit(for: .details, compactView: true), 128)
        XCTAssertEqual(VisibleIconWarmupPolicy.limit(for: .list, compactView: false), 112)
        XCTAssertEqual(VisibleIconWarmupPolicy.limit(for: .list, compactView: true), 144)
        XCTAssertEqual(VisibleIconWarmupPolicy.limit(for: .tiles, compactView: false), 144)
        XCTAssertEqual(VisibleIconWarmupPolicy.limit(for: .tiles, compactView: true), 180)
        XCTAssertEqual(VisibleIconWarmupPolicy.limit(for: .icons, compactView: false), 180)
        XCTAssertEqual(VisibleIconWarmupPolicy.limit(for: .icons, compactView: true), 220)

        XCTAssertLessThan(
            VisibleIconWarmupPolicy.limit(for: .details, compactView: false),
            VisibleIconWarmupPolicy.limit(for: .icons, compactView: true)
        )
        XCTAssertFalse(VisibleIconWarmupPolicy.prefersFileSpecificIcons(for: .details))
        XCTAssertFalse(VisibleIconWarmupPolicy.prefersFileSpecificIcons(for: .list))
        XCTAssertTrue(VisibleIconWarmupPolicy.prefersFileSpecificIcons(for: .tiles))
        XCTAssertTrue(VisibleIconWarmupPolicy.prefersFileSpecificIcons(for: .icons))
    }

    func testFolderTypeLogoResolverSamplesUniqueVisibleFileExtensions() {
        let items = [
            makeItem(name: "notes.txt", kind: .file, byteCount: 1),
            makeItem(name: "copy.txt", kind: .file, byteCount: 1),
            makeItem(name: "draft.md", kind: .file, byteCount: 1),
            makeItem(name: "Projects", kind: .folder, byteCount: nil),
            makeItem(name: "invoice.pdf", kind: .file, byteCount: 1),
            makeItem(name: "main.swift", kind: .file, byteCount: 1)
        ]

        let logoItems = FolderTypeLogoResolver.logoItems(
            from: items,
            maxLogos: 3,
            sampleLimit: 5
        )

        XCTAssertEqual(logoItems.map(\.name), ["notes.txt", "draft.md", "invoice.pdf"])
        XCTAssertEqual(logoItems.map(\.normalizedFileExtension), ["txt", "md", "pdf"])
    }

    func testFolderTypeLogoItemsStayBoundedAndIndependentOfVisibleProjection() {
        let store = makeStore()
        store.tabs[0].items = [
            makeItem(name: "notes.txt", kind: .file, byteCount: 1),
            makeItem(name: "copy.txt", kind: .file, byteCount: 1),
            makeItem(name: "draft.md", kind: .file, byteCount: 1),
            makeItem(name: "Projects", kind: .folder, byteCount: nil),
            makeItem(name: "invoice.pdf", kind: .file, byteCount: 1),
            makeItem(name: "main.swift", kind: .file, byteCount: 1),
            makeItem(name: "screen.png", kind: .file, byteCount: 1)
        ]

        store.kindFilter = .folders
        store.query = "does-not-match"

        XCTAssertTrue(store.visibleItems.isEmpty)
        XCTAssertEqual(store.folderTypeLogoItems.map(\.normalizedFileExtension), ["txt", "md", "pdf", "swift"])

        store.tabs[0].items = [
            makeItem(name: "clip.mov", kind: .file, byteCount: 1),
            makeItem(name: "mix.wav", kind: .file, byteCount: 1)
        ]

        XCTAssertEqual(store.folderTypeLogoItems.map(\.normalizedFileExtension), ["mov", "wav"])
    }

    func testFolderTypeLogoItemsCanBeReadForInactiveTabs() {
        let store = makeStore()
        let secondURL = temporaryDirectory.appendingPathComponent("Second", isDirectory: true)
        let secondTab = BrowserTab(url: secondURL)

        store.tabs[0].items = [
            makeItem(name: "active.txt", kind: .file, byteCount: 1)
        ]
        store.tabs.append(secondTab)
        store.tabs[1].items = [
            makeItem(name: "image.png", kind: .file, byteCount: 1),
            makeItem(name: "movie.mov", kind: .file, byteCount: 1)
        ]
        store.selectedTabID = store.tabs[0].id

        XCTAssertEqual(store.folderTypeLogoItems.map(\.normalizedFileExtension), ["txt"])
        XCTAssertEqual(store.folderTypeLogoItems(for: store.tabs[1]).map(\.normalizedFileExtension), ["png", "mov"])

        store.tabs[1].items = [
            makeItem(name: "main.swift", kind: .file, byteCount: 1)
        ]

        XCTAssertEqual(store.folderTypeLogoItems(for: store.tabs[1]).map(\.normalizedFileExtension), ["swift"])
    }

    func testSidebarCurrentRouteShowsWhenCurrentLocationIsOneFolderInsideActiveRoot() {
        let rootURL = temporaryDirectory.appendingPathComponent("Projects", isDirectory: true)
        let currentURL = rootURL.appendingPathComponent("Client", isDirectory: true)

        XCTAssertTrue(
            SidebarCurrentRouteResolver.shouldShowCurrentRoute(
                from: rootURL,
                to: currentURL,
                isPrimaryActive: true
            )
        )
        XCTAssertEqual(
            SidebarCurrentRouteResolver.visibleRouteComponents(from: rootURL, to: currentURL).map(\.name),
            ["Client"]
        )
    }

    func testSidebarCurrentRouteHidesForInactiveOrExactRootLocations() {
        let rootURL = temporaryDirectory.appendingPathComponent("Projects", isDirectory: true)
        let currentURL = rootURL.appendingPathComponent("Client", isDirectory: true)

        XCTAssertFalse(
            SidebarCurrentRouteResolver.shouldShowCurrentRoute(
                from: rootURL,
                to: currentURL,
                isPrimaryActive: false
            )
        )
        XCTAssertFalse(
            SidebarCurrentRouteResolver.shouldShowCurrentRoute(
                from: rootURL,
                to: rootURL,
                isPrimaryActive: true
            )
        )
    }

    func testChildFolderComponentsReturnVisibleFoldersForBreadcrumbMenus() throws {
        let store = makeStore()
        let parentURL = temporaryDirectory.appendingPathComponent("Parent", isDirectory: true)
        let alphaURL = parentURL.appendingPathComponent("Alpha", isDirectory: true)
        let zetaURL = parentURL.appendingPathComponent("Zeta", isDirectory: true)
        let hiddenURL = parentURL.appendingPathComponent(".Hidden", isDirectory: true)
        try FileManager.default.createDirectory(at: alphaURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: zetaURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: hiddenURL, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: parentURL.appendingPathComponent("note.txt").path, contents: Data()))

        let component = BrowserPathComponent(name: "Parent", url: parentURL)

        XCTAssertEqual(store.childFolderComponents(for: component).map(\.name), ["Alpha", "Zeta"])

        store.showHiddenFiles = true

        XCTAssertEqual(store.childFolderComponents(for: component).map(\.name), [".Hidden", "Alpha", "Zeta"])
    }

    func testChildFolderComponentsRepeatedLargeBreadcrumbMenusStayUnderInteractionBudget() throws {
        let store = makeStore()
        let parentURL = temporaryDirectory.appendingPathComponent("Large Parent", isDirectory: true)
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)

        for index in 0..<5_000 {
            let folderURL = parentURL.appendingPathComponent(String(format: "Folder %04d", index), isDirectory: true)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }

        let component = BrowserPathComponent(name: "Large Parent", url: parentURL)

        XCTAssertEqual(store.childFolderComponents(for: component, limit: 6_000).count, 5_000)

        let elapsed = elapsedSeconds {
            for _ in 0..<250 {
                XCTAssertEqual(store.childFolderComponents(for: component, limit: 6_000).count, 5_000)
            }
        }

        XCTAssertLessThan(elapsed, 0.30)
    }

    func testAddressMenuLocationsCombineCurrentPathPinnedAndRecentWithoutDuplicates() throws {
        let parentURL = temporaryDirectory.appendingPathComponent("Projects", isDirectory: true)
        let nestedURL = parentURL.appendingPathComponent("Client", isDirectory: true)
        let typedURL = temporaryDirectory.appendingPathComponent("Typed", isDirectory: true)
        let pinnedURL = temporaryDirectory.appendingPathComponent("Pinned", isDirectory: true)
        let recentURL = temporaryDirectory.appendingPathComponent("Recent", isDirectory: true)
        for url in [nestedURL, typedURL, pinnedURL, recentURL] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        userDefaults.set([typedURL.path, pinnedURL.path], forKey: "BetterFiles.typedPathHistoryPaths")

        let store = makeStore()
        store.open(nestedURL)
        store.pinnedDirectories = [pinnedURL, nestedURL]
        store.recentDirectories = [recentURL, pinnedURL]

        let locations = store.addressMenuLocations
        let currentPathLocations = locations.filter { $0.group == .currentPath }
        let typedHistoryLocations = locations.filter { $0.group == .typedHistory }
        let quickAccessLocations = locations.filter { $0.group == .quickAccess }
        let pinnedLocations = locations.filter { $0.group == .pinned }
        let recentLocations = locations.filter { $0.group == .recent }

        XCTAssertEqual(currentPathLocations.first?.url.standardizedFileURL, nestedURL.standardizedFileURL)
        XCTAssertTrue(currentPathLocations.contains { $0.url.standardizedFileURL == parentURL.standardizedFileURL })
        XCTAssertEqual(typedHistoryLocations.map(\.url.standardizedFileURL), [typedURL.standardizedFileURL])
        XCTAssertTrue(quickAccessLocations.contains { $0.name == "Home" && $0.url.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL })
        XCTAssertTrue(quickAccessLocations.contains { $0.name == "This Mac" && $0.url.standardizedFileURL.path == "/" })
        XCTAssertTrue(quickAccessLocations.contains { $0.name == "Trash" && $0.url.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true).standardizedFileURL })
        XCTAssertTrue(quickAccessLocations.contains { $0.name == "Network" && $0.url.standardizedFileURL.path == "/Network" })
        XCTAssertEqual(pinnedLocations.map(\.url.standardizedFileURL), [pinnedURL.standardizedFileURL])
        XCTAssertEqual(recentLocations.map(\.url.standardizedFileURL), [recentURL.standardizedFileURL])
        XCTAssertEqual(Set(pinnedLocations.map(\.url.standardizedFileURL.path)).count, pinnedLocations.count)
        XCTAssertEqual(Set(recentLocations.map(\.url.standardizedFileURL.path)).count, recentLocations.count)
    }

    func testOpenPathInputPersistsTypedFolderHistory() throws {
        let firstURL = temporaryDirectory.appendingPathComponent("Typed First", isDirectory: true)
        let secondURL = temporaryDirectory.appendingPathComponent("Typed Second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondURL, withIntermediateDirectories: true)

        let firstStore = makeStore()
        firstStore.pathInput = firstURL.path
        firstStore.openPathInput()
        firstStore.pathInput = secondURL.path
        firstStore.openPathInput()
        firstStore.pathInput = firstURL.path
        firstStore.openPathInput()

        XCTAssertEqual(firstStore.typedPathHistory.map(\.standardizedFileURL.path), [
            firstURL.standardizedFileURL.path,
            secondURL.standardizedFileURL.path
        ])

        let secondStore = makeStore()

        XCTAssertEqual(secondStore.typedPathHistory.map(\.standardizedFileURL.path), [
            firstURL.standardizedFileURL.path,
            secondURL.standardizedFileURL.path
        ])
    }

    func testOpenPathInputRecordsFileParentInTypedHistory() throws {
        let folderURL = temporaryDirectory.appendingPathComponent("Typed File Parent", isDirectory: true)
        let fileURL = folderURL.appendingPathComponent("notes.txt")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.pathInput = fileURL.path

        store.openPathInput()

        XCTAssertEqual(store.currentURL?.standardizedFileURL, folderURL.standardizedFileURL)
        XCTAssertEqual(store.selectedItemIDs, [fileURL.path])
        XCTAssertEqual(store.typedPathHistory.map(\.standardizedFileURL.path), [folderURL.standardizedFileURL.path])
    }

    func testOpenPathInputInNewTabOpensTypedFolderAndRecordsHistory() throws {
        let originalURL = temporaryDirectory!
        let folderURL = temporaryDirectory.appendingPathComponent("Typed New Tab", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let store = makeStore()
        let originalTabID = store.selectedTabID
        store.pathInput = folderURL.path

        store.openPathInputInNewTab()

        XCTAssertEqual(store.tabs.count, 2)
        XCTAssertNotEqual(store.selectedTabID, originalTabID)
        XCTAssertEqual(store.tabs.first?.currentURL?.standardizedFileURL, originalURL.standardizedFileURL)
        XCTAssertEqual(store.currentURL?.standardizedFileURL, folderURL.standardizedFileURL)
        XCTAssertEqual(store.typedPathHistory.map(\.standardizedFileURL.path), [folderURL.standardizedFileURL.path])
    }

    func testOpenPathInputInNewTabSelectsTypedFileInParentFolder() throws {
        let originalURL = temporaryDirectory!
        let folderURL = temporaryDirectory.appendingPathComponent("Typed File New Tab", isDirectory: true)
        let fileURL = folderURL.appendingPathComponent("notes.txt")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.pathInput = fileURL.path

        store.openPathInputInNewTab()

        XCTAssertEqual(store.tabs.count, 2)
        XCTAssertEqual(store.tabs.first?.currentURL?.standardizedFileURL, originalURL.standardizedFileURL)
        XCTAssertEqual(store.currentURL?.standardizedFileURL, folderURL.standardizedFileURL)
        XCTAssertEqual(store.selectedItemIDs, [fileURL.path])
        XCTAssertEqual(store.typedPathHistory.map(\.standardizedFileURL.path), [folderURL.standardizedFileURL.path])
    }

    func testOpenDroppedFolderURLInNewTabOpensFolder() throws {
        let originalURL = temporaryDirectory!
        let folderURL = temporaryDirectory.appendingPathComponent("Dropped Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let store = makeStore()
        let opened = store.openDroppedURLsInNewTabs([folderURL])

        XCTAssertTrue(opened)
        XCTAssertEqual(store.tabs.count, 2)
        XCTAssertEqual(store.tabs.first?.currentURL?.standardizedFileURL, originalURL.standardizedFileURL)
        XCTAssertEqual(store.currentURL?.standardizedFileURL, folderURL.standardizedFileURL)
    }

    func testOpenDroppedFileURLInNewTabOpensParentAndSelectsFile() throws {
        let originalURL = temporaryDirectory!
        let folderURL = temporaryDirectory.appendingPathComponent("Dropped File Parent", isDirectory: true)
        let fileURL = folderURL.appendingPathComponent("dropped.txt")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try "dropped".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        let opened = store.openDroppedURLsInNewTabs([fileURL])

        XCTAssertTrue(opened)
        XCTAssertEqual(store.tabs.count, 2)
        XCTAssertEqual(store.tabs.first?.currentURL?.standardizedFileURL, originalURL.standardizedFileURL)
        XCTAssertEqual(store.currentURL?.standardizedFileURL, folderURL.standardizedFileURL)
        XCTAssertEqual(store.selectedItemIDs, [fileURL.standardizedFileURL.path])
    }

    func testOpenDroppedMissingURLInNewTabsReturnsFalse() {
        let missingURL = temporaryDirectory.appendingPathComponent("Missing Dropped Folder", isDirectory: true)

        let store = makeStore()
        let opened = store.openDroppedURLsInNewTabs([missingURL])

        XCTAssertFalse(opened)
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertEqual(store.currentURL?.standardizedFileURL, temporaryDirectory.standardizedFileURL)
    }

    func testOpenDroppedFolderURLOnExistingTabNavigatesThatTab() throws {
        let targetURL = temporaryDirectory.appendingPathComponent("Target Tab", isDirectory: true)
        let droppedFolderURL = temporaryDirectory.appendingPathComponent("Dropped Onto Tab", isDirectory: true)
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: droppedFolderURL, withIntermediateDirectories: true)

        let store = makeStore()
        let targetTabID = store.selectedTabID
        store.addTab(opening: targetURL)

        let opened = store.openDroppedURLs([droppedFolderURL], inTab: targetTabID)

        XCTAssertTrue(opened)
        XCTAssertEqual(store.tabs.count, 2)
        XCTAssertEqual(store.selectedTabID, targetTabID)
        XCTAssertEqual(store.currentURL?.standardizedFileURL, droppedFolderURL.standardizedFileURL)
    }

    func testOpenDroppedFileURLOnExistingTabOpensParentAndSelectsFile() throws {
        let targetURL = temporaryDirectory.appendingPathComponent("Target File Tab", isDirectory: true)
        let droppedParentURL = temporaryDirectory.appendingPathComponent("Dropped File Onto Tab", isDirectory: true)
        let droppedFileURL = droppedParentURL.appendingPathComponent("dropped-on-tab.txt")
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: droppedParentURL, withIntermediateDirectories: true)
        try "dropped".write(to: droppedFileURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        let targetTabID = store.selectedTabID
        store.addTab(opening: targetURL)

        let opened = store.openDroppedURLs([droppedFileURL], inTab: targetTabID)

        XCTAssertTrue(opened)
        XCTAssertEqual(store.tabs.count, 2)
        XCTAssertEqual(store.selectedTabID, targetTabID)
        XCTAssertEqual(store.currentURL?.standardizedFileURL, droppedParentURL.standardizedFileURL)
        XCTAssertEqual(store.selectedItemIDs, [droppedFileURL.standardizedFileURL.path])
    }

    func testOpenMultipleDroppedURLsOnExistingTabNavigatesTargetThenOpensNewTabs() throws {
        let targetURL = temporaryDirectory.appendingPathComponent("Target Multi Drop Tab", isDirectory: true)
        let firstDroppedURL = temporaryDirectory.appendingPathComponent("First Dropped Onto Tab", isDirectory: true)
        let secondDroppedURL = temporaryDirectory.appendingPathComponent("Second Dropped Onto Tab", isDirectory: true)
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: firstDroppedURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDroppedURL, withIntermediateDirectories: true)

        let store = makeStore()
        let targetTabID = store.selectedTabID
        store.addTab(opening: targetURL)

        let opened = store.openDroppedURLs([firstDroppedURL, secondDroppedURL], inTab: targetTabID)

        XCTAssertTrue(opened)
        XCTAssertEqual(store.tabs.count, 3)
        XCTAssertEqual(store.tabs.first?.id, targetTabID)
        XCTAssertEqual(store.tabs.first?.currentURL?.standardizedFileURL, firstDroppedURL.standardizedFileURL)
        XCTAssertEqual(store.currentURL?.standardizedFileURL, secondDroppedURL.standardizedFileURL)
    }

    func testOpenDroppedMissingURLOnExistingTabReturnsFalse() {
        let missingURL = temporaryDirectory.appendingPathComponent("Missing Dropped On Tab", isDirectory: true)

        let store = makeStore()
        let targetTabID = store.selectedTabID
        let opened = store.openDroppedURLs([missingURL], inTab: targetTabID)

        XCTAssertFalse(opened)
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertEqual(store.selectedTabID, targetTabID)
        XCTAssertEqual(store.currentURL?.standardizedFileURL, temporaryDirectory.standardizedFileURL)
    }

    func testRestoredTypedPathHistorySkipsMissingPathsAndStaysUnderLaunchBudget() throws {
        let directories = try (0..<16).map { index in
            let url = temporaryDirectory.appendingPathComponent("Typed-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let missingURL = temporaryDirectory.appendingPathComponent("Missing", isDirectory: true)
        userDefaults.set(
            directories.map(\.path) + [missingURL.path, directories[0].path],
            forKey: "BetterFiles.typedPathHistoryPaths"
        )

        var store: BrowserStore?
        let elapsed = elapsedSeconds {
            store = makeStore()
        }

        XCTAssertEqual(store?.typedPathHistory.count, 12)
        XCTAssertEqual(store?.typedPathHistory.first?.lastPathComponent, "Typed-0")
        XCTAssertEqual(store?.typedPathHistory.last?.lastPathComponent, "Typed-11")
        XCTAssertLessThan(elapsed, 0.30)
    }

    func testClearTypedPathHistoryClearsMenuAndPersistsRemoval() throws {
        let typedURL = temporaryDirectory.appendingPathComponent("Typed Clear", isDirectory: true)
        try FileManager.default.createDirectory(at: typedURL, withIntermediateDirectories: true)
        userDefaults.set([typedURL.path], forKey: "BetterFiles.typedPathHistoryPaths")

        let store = makeStore()
        XCTAssertTrue(store.canClearTypedPathHistory)
        XCTAssertEqual(
            store.addressMenuLocations.filter { $0.group == .typedHistory }.map(\.url.standardizedFileURL),
            [typedURL.standardizedFileURL]
        )

        store.clearTypedPathHistory()

        XCTAssertFalse(store.canClearTypedPathHistory)
        XCTAssertTrue(store.typedPathHistory.isEmpty)
        XCTAssertNil(userDefaults.array(forKey: "BetterFiles.typedPathHistoryPaths"))
        XCTAssertTrue(store.addressMenuLocations.filter { $0.group == .typedHistory }.isEmpty)
        XCTAssertTrue(makeStore().typedPathHistory.isEmpty)
    }

    func testClearTypedPathHistoryDoesNotTouchPinnedOrRecentDirectories() throws {
        let typedURL = temporaryDirectory.appendingPathComponent("Typed Keep Others", isDirectory: true)
        let pinnedURL = temporaryDirectory.appendingPathComponent("Pinned Keep", isDirectory: true)
        let recentURL = temporaryDirectory.appendingPathComponent("Recent Keep", isDirectory: true)
        for url in [typedURL, pinnedURL, recentURL] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        userDefaults.set([typedURL.path], forKey: "BetterFiles.typedPathHistoryPaths")

        let store = makeStore()
        store.pinnedDirectories = [pinnedURL]
        store.recentDirectories = [recentURL]

        store.clearTypedPathHistory()

        XCTAssertEqual(store.pinnedDirectories.map(\.standardizedFileURL), [pinnedURL.standardizedFileURL])
        XCTAssertEqual(store.recentDirectories.map(\.standardizedFileURL), [recentURL.standardizedFileURL])
        XCTAssertEqual(store.addressMenuLocations.filter { $0.group == .pinned }.map(\.url.standardizedFileURL), [pinnedURL.standardizedFileURL])
        XCTAssertEqual(store.addressMenuLocations.filter { $0.group == .recent }.map(\.url.standardizedFileURL), [recentURL.standardizedFileURL])
    }

    func testClearTypedPathHistoryIsSafeWhenAlreadyEmpty() {
        let store = makeStore()

        XCTAssertFalse(store.canClearTypedPathHistory)

        store.clearTypedPathHistory()

        XCTAssertFalse(store.canClearTypedPathHistory)
        XCTAssertTrue(store.typedPathHistory.isEmpty)
        XCTAssertNil(userDefaults.array(forKey: "BetterFiles.typedPathHistoryPaths"))
    }

    func testOpenPathInputOpensExistingFolderPath() throws {
        let nestedURL = temporaryDirectory.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)

        let store = makeStore()
        store.pathInput = nestedURL.path

        store.openPathInput()

        XCTAssertEqual(store.currentURL?.standardizedFileURL, nestedURL.standardizedFileURL)
        XCTAssertNil(store.errorMessage)
    }

    func testOpenPathInputSelectsExistingFilePathParent() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("notes.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.pathInput = fileURL.path

        store.openPathInput()

        XCTAssertEqual(store.currentURL?.standardizedFileURL, temporaryDirectory.standardizedFileURL)
        XCTAssertEqual(store.selectedItemIDs, [fileURL.path])
    }

    func testOpenPathInputAcceptsFileURLString() throws {
        let nestedURL = temporaryDirectory.appendingPathComponent("File URL Target", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)

        let store = makeStore()
        store.pathInput = nestedURL.absoluteString

        store.openPathInput()

        XCTAssertEqual(store.currentURL?.standardizedFileURL, nestedURL.standardizedFileURL)
        XCTAssertNil(store.errorMessage)
    }

    func testOpenPathInputAcceptsRelativeFolderPath() throws {
        let nestedURL = temporaryDirectory.appendingPathComponent("Relative Target", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)

        let store = makeStore()
        store.pathInput = "Relative Target"

        store.openPathInput()

        XCTAssertEqual(store.currentURL?.standardizedFileURL, nestedURL.standardizedFileURL)
        XCTAssertNil(store.errorMessage)
    }

    func testOpenPathInputTrimsQuotedPath() throws {
        let nestedURL = temporaryDirectory.appendingPathComponent("Quoted Target", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)

        let store = makeStore()
        store.pathInput = "\"\(nestedURL.path)\""

        store.openPathInput()

        XCTAssertEqual(store.currentURL?.standardizedFileURL, nestedURL.standardizedFileURL)
        XCTAssertNil(store.errorMessage)
    }

    func testOpenPathInputReportsMissingPathWithoutNavigating() {
        let store = makeStore()
        let originalURL = store.currentURL
        let missingURL = temporaryDirectory.appendingPathComponent("missing")
        store.pathInput = missingURL.path

        store.openPathInput()

        XCTAssertEqual(store.currentURL, originalURL)
        XCTAssertEqual(store.errorMessage, "Path does not exist: \(missingURL.path)")
    }

    func testPathInputCompletionsSuggestMatchingAbsolutePaths() throws {
        let applicationsURL = temporaryDirectory.appendingPathComponent("Applications", isDirectory: true)
        let archiveURL = temporaryDirectory.appendingPathComponent("Archive", isDirectory: true)
        let notesURL = temporaryDirectory.appendingPathComponent("Notes.txt")
        try FileManager.default.createDirectory(at: applicationsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archiveURL, withIntermediateDirectories: true)
        try "notes".write(to: notesURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.pathInput = temporaryDirectory.appendingPathComponent("Ap").path

        let completions = store.pathInputCompletions

        XCTAssertEqual(completions.map(\.name), ["Applications"])
        XCTAssertEqual(completions.first?.url.standardizedFileURL, applicationsURL.standardizedFileURL)
        XCTAssertEqual(completions.first?.isDirectory, true)
    }

    func testPathInputCompletionsSuggestRelativePathsAndOpenCompletion() throws {
        let targetURL = temporaryDirectory.appendingPathComponent("Reports", isDirectory: true)
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)

        let store = makeStore()
        store.pathInput = "Rep"

        let completion = try XCTUnwrap(store.pathInputCompletions.first)
        store.openPathInputCompletion(completion)

        XCTAssertEqual(store.currentURL?.standardizedFileURL, targetURL.standardizedFileURL)
        XCTAssertEqual(store.pathInput, targetURL.standardizedFileURL.path)
    }

    func testPathInputCompletionsRespectHiddenFilePreference() throws {
        let hiddenURL = temporaryDirectory.appendingPathComponent(".Secrets", isDirectory: true)
        try FileManager.default.createDirectory(at: hiddenURL, withIntermediateDirectories: true)

        let store = makeStore()
        store.pathInput = ".S"
        XCTAssertTrue(store.pathInputCompletions.isEmpty)

        store.showHiddenFiles = true
        XCTAssertEqual(store.pathInputCompletions.map(\.name), [".Secrets"])
    }

    func testRepeatedPathInputCompletionsInLargeFolderStayUnderInteractionBudget() throws {
        let parentURL = temporaryDirectory.appendingPathComponent("Large Completion Parent", isDirectory: true)
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)

        for index in 0..<5_000 {
            let fileURL = parentURL.appendingPathComponent(String(format: "Item %04d.txt", index))
            XCTAssertTrue(FileManager.default.createFile(atPath: fileURL.path, contents: Data()))
        }

        let store = makeStore()
        store.pathInput = parentURL.appendingPathComponent("Item 0").path
        XCTAssertEqual(store.pathInputCompletions.count, 10)

        let elapsed = elapsedSeconds {
            for index in 0..<250 {
                let prefix = String(format: "Item 0%d", index % 10)
                let input = parentURL.appendingPathComponent(prefix).path
                XCTAssertEqual(store.completionsForPathInput(input, relativeTo: temporaryDirectory, limit: 10).count, 10)
            }
        }

        XCTAssertLessThan(elapsed, 0.30)
    }

    func testColdPathInputCompletionForLargeFolderStaysUnderInteractionBudget() throws {
        let parentURL = temporaryDirectory.appendingPathComponent("Cold Completion Parent", isDirectory: true)
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)

        for index in 0..<5_000 {
            let fileURL = parentURL.appendingPathComponent(String(format: "Report %04d.txt", index))
            XCTAssertTrue(FileManager.default.createFile(atPath: fileURL.path, contents: Data()))
        }

        let store = makeStore()
        let input = parentURL.appendingPathComponent("Report 01").path

        var completions: [PathInputCompletion] = []
        let elapsed = elapsedSeconds {
            completions = store.completionsForPathInput(input, relativeTo: temporaryDirectory, limit: 10)
        }

        XCTAssertEqual(completions.count, 10)
        XCTAssertEqual(completions.first?.name, "Report 0100.txt")
        XCTAssertLessThan(elapsed, 0.30)
    }

    func testPasteItemsUsesFileURLsCopiedFromFinderPasteboard() async throws {
        let externalDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BetterFilesExternalPaste-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: externalDirectory)
        }

        let sourceURL = externalDirectory.appendingPathComponent("outside.txt")
        try "from finder".write(to: sourceURL, atomically: true, encoding: .utf8)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([sourceURL as NSURL]))

        let store = makeStore()
        XCTAssertTrue(store.canPasteItems)

        store.pasteItems()
        await waitForFileOperation(store)

        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent("outside.txt").path))
        XCTAssertTrue(store.performanceEvents.contains { event in
            event.label == "Copied"
                && event.itemCount == 1
                && event.path == temporaryDirectory.standardizedFileURL.path
                && event.elapsedSeconds < 0.30
        })
    }

    func testPasteItemsCanTargetSpecificFolderWithoutNavigating() async throws {
        let externalDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BetterFilesExternalTargetPaste-\(UUID().uuidString)", isDirectory: true)
        let targetDirectory = temporaryDirectory.appendingPathComponent("Paste Target", isDirectory: true)
        try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: externalDirectory)
        }

        let sourceURL = externalDirectory.appendingPathComponent("outside.txt")
        try "from finder".write(to: sourceURL, atomically: true, encoding: .utf8)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([sourceURL as NSURL]))

        let store = makeStore()
        XCTAssertTrue(store.canPasteItems)

        store.pasteItems(to: targetDirectory)
        await waitForFileOperation(store)

        let pastedURL = targetDirectory.appendingPathComponent("outside.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pastedURL.path))
        XCTAssertEqual(store.currentURL?.standardizedFileURL.path, temporaryDirectory.standardizedFileURL.path)
        XCTAssertFalse(store.selectedItemIDs.contains(pastedURL.path))
        XCTAssertTrue(store.performanceEvents.contains { event in
            event.label == "Copied"
                && event.itemCount == 1
                && event.path == temporaryDirectory.standardizedFileURL.path
                && event.elapsedSeconds < 0.30
        })
    }

    func testPasteItemsCanMoveCutSelectionIntoSpecificFolderAndClearClipboard() async throws {
        let sourceURL = temporaryDirectory.appendingPathComponent("cut-me.txt")
        let targetDirectory = temporaryDirectory.appendingPathComponent("Paste Target", isDirectory: true)
        try "move".write(to: sourceURL, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let store = makeStore(service: FileSystemService())
        store.tabs[0].items = [
            makeItem(name: "cut-me.txt", kind: .file, byteCount: 4),
            makeItem(name: "Paste Target", kind: .folder, byteCount: nil)
        ]
        store.selectedItemIDs = [sourceURL.path]

        store.cutSelectedItems()
        XCTAssertTrue(store.hasClipboardItems)
        XCTAssertTrue(store.canPasteItems)

        store.pasteItems(to: targetDirectory)
        await waitForFileOperation(store)

        let pastedURL = targetDirectory.appendingPathComponent("cut-me.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pastedURL.path))
        XCTAssertFalse(store.hasClipboardItems)
        XCTAssertEqual(store.currentURL?.standardizedFileURL.path, temporaryDirectory.standardizedFileURL.path)
        XCTAssertFalse(store.selectedItemIDs.contains(pastedURL.path))
        XCTAssertTrue(store.performanceEvents.contains { event in
            event.label == "Moved"
                && event.itemCount == 1
                && event.path == temporaryDirectory.standardizedFileURL.path
                && event.elapsedSeconds < 0.30
        })
    }

    func testImportItemsCanMoveExternalFilesIntoCurrentFolder() async throws {
        let externalDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BetterFilesExternalMove-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: externalDirectory)
        }

        let sourceURL = externalDirectory.appendingPathComponent("move-me.txt")
        try "move".write(to: sourceURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        XCTAssertTrue(store.importItems([sourceURL], operation: .move))
        await waitForFileOperation(store)

        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent("move-me.txt").path))
        XCTAssertTrue(store.performanceEvents.contains { event in
            event.label == "Moved"
                && event.itemCount == 1
                && event.path == temporaryDirectory.standardizedFileURL.path
                && event.elapsedSeconds < 0.30
        })
    }

    func testImportItemsCanCopyExternalFilesIntoSpecificFolder() async throws {
        let externalDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BetterFilesExternalFolderDrop-\(UUID().uuidString)", isDirectory: true)
        let targetDirectory = temporaryDirectory.appendingPathComponent("Target", isDirectory: true)
        try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: externalDirectory)
        }

        let sourceURL = externalDirectory.appendingPathComponent("drop-me.txt")
        try "drop".write(to: sourceURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        XCTAssertTrue(store.importItems([sourceURL], to: targetDirectory, operation: .copy))
        await waitForFileOperation(store)

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetDirectory.appendingPathComponent("drop-me.txt").path))
        XCTAssertFalse(store.selectedItemIDs.contains(targetDirectory.appendingPathComponent("drop-me.txt").path))
        XCTAssertTrue(store.performanceEvents.contains { event in
            event.label == "Copied"
                && event.itemCount == 1
                && event.path == temporaryDirectory.standardizedFileURL.path
                && event.elapsedSeconds < 0.30
        })
    }

    func testDropItemsMovesCurrentFolderFilesIntoFolder() async throws {
        let sourceURL = temporaryDirectory.appendingPathComponent("drag-me.txt")
        let targetDirectory = temporaryDirectory.appendingPathComponent("Target", isDirectory: true)
        try "move".write(to: sourceURL, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

        let store = makeStore(service: FileSystemService())

        XCTAssertEqual(store.defaultDropOperation(for: [sourceURL], to: targetDirectory), .move)
        XCTAssertTrue(store.dropItems([sourceURL], to: targetDirectory))
        await waitForFileOperation(store)

        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetDirectory.appendingPathComponent("drag-me.txt").path))
        XCTAssertEqual(store.lastOperationSummary?.label, "Moved")
    }

    func testDropItemsMovesEntireCurrentSelectionWhenDraggingOneSelectedFileIntoFolder() async throws {
        let firstURL = temporaryDirectory.appendingPathComponent("first.txt")
        let secondURL = temporaryDirectory.appendingPathComponent("second.txt")
        let targetDirectory = temporaryDirectory.appendingPathComponent("Target", isDirectory: true)
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

        let store = makeStore(service: FileSystemService())
        store.tabs[0].items = [
            makeItem(name: "first.txt", kind: .file, byteCount: 5),
            makeItem(name: "second.txt", kind: .file, byteCount: 6),
            makeItem(name: "Target", kind: .folder, byteCount: nil)
        ]
        store.selectedItemIDs = [firstURL.path, secondURL.path]

        XCTAssertEqual(store.expandedDropURLs(from: [firstURL]).map(\.lastPathComponent), ["first.txt", "second.txt"])
        XCTAssertTrue(store.dropItems([firstURL], to: targetDirectory))
        await waitForFileOperation(store)

        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetDirectory.appendingPathComponent("first.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetDirectory.appendingPathComponent("second.txt").path))
        XCTAssertEqual(store.lastOperationSummary?.label, "Moved")
        XCTAssertEqual(store.lastOperationSummary?.itemCount, 2)
    }

    func testDropItemsCopiesExternalFilesIntoCurrentFolder() async throws {
        let externalDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BetterFilesExternalDropCopy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: externalDirectory)
        }

        let sourceURL = externalDirectory.appendingPathComponent("import-me.txt")
        try "copy".write(to: sourceURL, atomically: true, encoding: .utf8)

        let store = makeStore(service: FileSystemService())

        XCTAssertEqual(store.defaultDropOperation(for: [sourceURL], to: temporaryDirectory), .copy)
        XCTAssertTrue(store.dropItems([sourceURL], to: temporaryDirectory))
        await waitForFileOperation(store)

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent("import-me.txt").path))
        XCTAssertEqual(store.lastOperationSummary?.label, "Copied")
        XCTAssertTrue(store.performanceEvents.contains { event in
            event.label == "Copied"
                && event.itemCount == 1
                && event.path == temporaryDirectory.standardizedFileURL.path
        })
    }

    func testImportItemsSchedulesLargeCopyWithoutBlockingCaller() async throws {
        let externalDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BetterFilesExternalLargeCopy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: externalDirectory)
        }

        let sourceURL = externalDirectory.appendingPathComponent("large.bin")
        try Data(repeating: 7, count: 16 * 1024 * 1024).write(to: sourceURL)

        let store = makeStore()
        let start = ContinuousClock.now
        XCTAssertTrue(store.importItems([sourceURL], operation: .copy))
        let elapsed = start.duration(to: ContinuousClock.now)
        let elapsedSeconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000

        XCTAssertLessThan(elapsedSeconds, 0.3)
        XCTAssertNotNil(store.activeOperation)

        await waitForFileOperation(store)

        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent("large.bin").path))
        XCTAssertEqual(store.lastOperationSummary?.itemCount, 1)
        XCTAssertTrue(store.performanceEvents.contains { event in
            event.label == "Copied"
                && event.itemCount == 1
                && event.elapsedSeconds < 30
        })
    }

    private func makeStore(service: FileSystemServicing = EmptyFileSystemService()) -> BrowserStore {
        BrowserStore(
            service: service,
            userDefaults: userDefaults,
            initialURL: temporaryDirectory
        )
    }

    private func assertPerformanceEvent(
        in store: BrowserStore,
        label: String,
        itemCount: Int,
        path: String? = nil,
        maxElapsedSeconds: TimeInterval = 0.30,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectedPath = path ?? temporaryDirectory.standardizedFileURL.path
        XCTAssertTrue(
            store.performanceEvents.contains { event in
                event.label == label
                    && event.itemCount == itemCount
                    && event.path == expectedPath
                    && event.elapsedSeconds < maxElapsedSeconds
            },
            "Expected performance event \(label) for \(itemCount) item(s) at \(expectedPath)",
            file: file,
            line: line
        )
    }

    private func makeItem(
        name: String,
        kind: FileItem.Kind,
        byteCount: Int64?,
        isHidden: Bool? = nil,
        isLocked: Bool = false,
        createdAt: Date? = Date(timeIntervalSince1970: 1_600_000_000),
        modifiedAt: Date? = Date(timeIntervalSince1970: 1_700_000_000),
        accessedAt: Date? = Date(timeIntervalSince1970: 1_800_000_000),
        posixPermissions: UInt16? = 0o644
    ) -> FileItem {
        let url = temporaryDirectory.appendingPathComponent(name, isDirectory: kind == .folder)
        return FileItem(
            id: url.path,
            url: url,
            name: name,
            kind: kind,
            localizedTypeDescription: nil,
            byteCount: byteCount,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            accessedAt: accessedAt,
            isHidden: isHidden ?? name.hasPrefix("."),
            isLocked: isLocked,
            posixPermissions: posixPermissions
        )
    }

    private func stubItem(named name: String, in directory: URL) -> FileItem {
        FileItem(
            id: directory.appendingPathComponent(name).standardizedFileURL.path,
            url: directory.appendingPathComponent(name),
            name: name,
            kind: .file,
            localizedTypeDescription: nil,
            byteCount: 1,
            createdAt: Date(timeIntervalSince1970: 1_600_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            accessedAt: Date(timeIntervalSince1970: 1_800_000_000),
            isHidden: false,
            isLocked: false,
            posixPermissions: 0o644
        )
    }

    private func quotedPathExpectation(_ path: String) -> String {
        "\"\(path.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private func makeLargeItemSet(prefix: String = "Document", count: Int = 5_000) -> [FileItem] {
        (0..<count).map { index in
            if index.isMultiple(of: 10) {
                makeItem(
                    name: String(format: "\(prefix) Folder %04d", index),
                    kind: .folder,
                    byteCount: nil,
                    modifiedAt: Date()
                )
            } else {
                makeItem(
                    name: String(format: "\(prefix) %04d.txt", index),
                    kind: .file,
                    byteCount: Int64(index),
                    modifiedAt: Date()
                )
            }
        }
    }

    private func makeZipArchive(named archiveName: String, entries: [String: String]) throws -> URL {
        let sourceDirectory = temporaryDirectory.appendingPathComponent("ZipSource-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

        for (name, contents) in entries {
            let url = sourceDirectory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }

        let archiveURL = temporaryDirectory.appendingPathComponent(archiveName)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = sourceDirectory
        process.arguments = ["-qry", archiveURL.path, "--"] + entries.keys.sorted()
        try process.run()
        process.waitUntilExit()

        try? FileManager.default.removeItem(at: sourceDirectory)

        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }

        return archiveURL
    }

    private func elapsedSeconds(_ work: () -> Void) -> TimeInterval {
        let start = Date()
        work()
        return Date().timeIntervalSince(start)
    }

    private func waitForFileOperation(
        _ store: BrowserStore,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while store.activeOperation != nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertNil(store.activeOperation, file: file, line: line)
        XCTAssertNotNil(store.lastOperationSummary, file: file, line: line)
    }

    private func runChmod(
        _ arguments: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let process = try Process.run(URL(fileURLWithPath: "/bin/chmod"), arguments: arguments)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, file: file, line: line)
    }

    private func extendedACLText(at url: URL) -> String? {
        guard let acl = acl_get_file(url.path, ACL_TYPE_EXTENDED) else {
            return nil
        }
        defer {
            acl_free(UnsafeMutableRawPointer(acl))
        }

        var length: ssize_t = 0
        guard let text = acl_to_text(acl, &length), length > 0 else {
            return nil
        }
        defer {
            acl_free(UnsafeMutableRawPointer(text))
        }

        let value = String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func waitForContentsCalls(
        _ service: CountingFileSystemService,
        atLeast expectedCount: Int,
        timeout: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while service.callCount < expectedCount, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertGreaterThanOrEqual(service.callCount, expectedCount, file: file, line: line)
    }

    private func waitForTabLoad(
        _ store: BrowserStore,
        timeout: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while store.isLoading, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertFalse(store.isLoading, file: file, line: line)
    }

    private func waitForItems(
        _ store: BrowserStore,
        named expectedNames: [String],
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while store.items.map(\.name) != expectedNames, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(store.items.map(\.name), expectedNames, file: file, line: line)
    }

    private func waitForSearch(
        _ store: BrowserStore,
        query: String,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while store.searchSummary?.query != query, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(store.searchSummary?.query, query, file: file, line: line)
        XCTAssertFalse(store.isLoading, file: file, line: line)
    }
}

private extension Array {
    func cycled(prefix count: Int) -> [Element] {
        guard !isEmpty else {
            return []
        }

        return (0..<count).map { self[$0 % self.count] }
    }
}

private struct EmptyFileSystemService: FileSystemServicing {
    func contents(
        of directory: URL,
        includingHidden: Bool,
        foldersFirst: Bool
    ) throws -> [FileItem] {
        []
    }

    func search(
        in directory: URL,
        query: String,
        includingHidden: Bool,
        foldersFirst: Bool,
        limit: Int
    ) throws -> [FileItem] {
        []
    }
}

private final class CountingFileSystemService: FileSystemServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCallCount = 0

    var callCount: Int {
        lock.withLock {
            storedCallCount
        }
    }

    func contents(
        of directory: URL,
        includingHidden: Bool,
        foldersFirst: Bool
    ) throws -> [FileItem] {
        lock.withLock {
            storedCallCount += 1
        }
        return []
    }

    func search(
        in directory: URL,
        query: String,
        includingHidden: Bool,
        foldersFirst: Bool,
        limit: Int
    ) throws -> [FileItem] {
        []
    }
}

private func setFinderTags(_ tagNames: [String], for url: URL) throws {
    let attributeName = "com.apple.metadata:_kMDItemUserTags"
    let storedValues = tagNames.map { "\($0)\n0" }
    let data = try PropertyListSerialization.data(
        fromPropertyList: storedValues,
        format: .binary,
        options: 0
    )
    let result = data.withUnsafeBytes { buffer in
        setxattr(url.path, attributeName, buffer.baseAddress, buffer.count, 0, 0)
    }
    if result != 0 {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

private func finderTags(for url: URL) throws -> [String] {
    let attributeName = "com.apple.metadata:_kMDItemUserTags"
    let length = getxattr(url.path, attributeName, nil, 0, 0, 0)

    guard length > 0 else {
        return []
    }

    var data = Data(count: length)
    let readLength = data.withUnsafeMutableBytes { buffer in
        getxattr(url.path, attributeName, buffer.baseAddress, buffer.count, 0, 0)
    }
    guard readLength > 0,
          let storedValues = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String]
    else {
        return []
    }

    return storedValues.compactMap { value in
        value.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)
    }
}

private final class StubbedFileSystemService: FileSystemServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var itemsByPath: [String: [FileItem]] = [:]
    private var searchItemsByPathAndQuery: [String: [FileItem]] = [:]
    private var delaysByPath: [String: Duration] = [:]
    private var searchDelaysByPathAndQuery: [String: Duration] = [:]

    func setItems(_ items: [FileItem], for directory: URL) {
        lock.withLock {
            itemsByPath[directory.standardizedFileURL.path] = items
        }
    }

    func setDelay(_ delay: Duration, for directory: URL) {
        lock.withLock {
            delaysByPath[directory.standardizedFileURL.path] = delay
        }
    }

    func setSearchItems(_ items: [FileItem], for directory: URL, query: String) {
        lock.withLock {
            searchItemsByPathAndQuery[searchKey(directory: directory, query: query)] = items
        }
    }

    func setSearchDelay(_ delay: Duration, for directory: URL, query: String) {
        lock.withLock {
            searchDelaysByPathAndQuery[searchKey(directory: directory, query: query)] = delay
        }
    }

    func contents(
        of directory: URL,
        includingHidden: Bool,
        foldersFirst: Bool
    ) throws -> [FileItem] {
        let path = directory.standardizedFileURL.path
        let delay: Duration?
        let items: [FileItem]
        lock.lock()
        delay = delaysByPath[path]
        items = itemsByPath[path] ?? []
        lock.unlock()

        if let delay {
            Thread.sleep(forTimeInterval: delay.timeInterval)
        }

        return items
    }

    func search(
        in directory: URL,
        query: String,
        includingHidden: Bool,
        foldersFirst: Bool,
        limit: Int
    ) throws -> [FileItem] {
        let key = searchKey(directory: directory, query: query)
        let delay: Duration?
        let items: [FileItem]
        lock.lock()
        delay = searchDelaysByPathAndQuery[key]
        items = searchItemsByPathAndQuery[key] ?? []
        lock.unlock()

        if let delay {
            Thread.sleep(forTimeInterval: delay.timeInterval)
        }

        return Array(items.prefix(limit))
    }

    private func searchKey(directory: URL, query: String) -> String {
        "\(directory.standardizedFileURL.path)|\(query)"
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
