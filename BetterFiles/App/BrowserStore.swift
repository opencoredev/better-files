import AppKit
import Darwin
import Foundation
import Observation
import UniformTypeIdentifiers

struct BrowserTab: Identifiable, Equatable, Sendable {
    let id: UUID
    var currentURL: URL?
    var pathInput: String
    var query: String
    var searchesSubfolders: Bool
    var items: [FileItem] {
        didSet {
            itemsVersion &+= 1
        }
    }
    var selectedItemIDs: Set<FileItem.ID> {
        didSet {
            if selectedItemIDs != oldValue {
                selectionVersion &+= 1
            }
        }
    }
    var selectionVersion: Int
    var errorMessage: String?
    var isLoading: Bool
    var loadSummary: DirectoryLoadSummary?
    var searchSummary: RecursiveSearchSummary?
    var backStack: [URL]
    var forwardStack: [URL]
    var itemsVersion: Int

    init(id: UUID = UUID(), url: URL) {
        let standardizedURL = url.standardizedFileURL

        self.id = id
        self.currentURL = standardizedURL
        self.pathInput = standardizedURL.path
        self.query = ""
        self.searchesSubfolders = false
        self.items = []
        self.selectedItemIDs = []
        self.selectionVersion = 0
        self.errorMessage = nil
        self.isLoading = false
        self.loadSummary = nil
        self.searchSummary = nil
        self.backStack = []
        self.forwardStack = []
        self.itemsVersion = 0
    }

    var title: String {
        guard let currentURL else {
            return "Untitled"
        }

        if currentURL.path == "/" {
            return "Macintosh HD"
        }

        return currentURL.lastPathComponent.isEmpty ? currentURL.path : currentURL.lastPathComponent
    }
}

private struct ClosedTabInsertion: Sendable {
    let index: Int
}

private struct DirectoryContentSnapshot: Sendable {
    let items: [FileItem]
    let loadSummary: DirectoryLoadSummary?
}

struct BrowserPathComponent: Identifiable, Equatable, Sendable {
    let name: String
    let url: URL

    var id: String {
        url.standardizedFileURL.path
    }
}

struct AddressMenuLocation: Identifiable, Equatable, Sendable {
    enum Group: String, CaseIterable, Sendable {
        case currentPath
        case typedHistory
        case quickAccess
        case pinned
        case recent

        var label: String {
            switch self {
            case .currentPath:
                return "Current Path"
            case .typedHistory:
                return "Typed Paths"
            case .quickAccess:
                return "Quick Access"
            case .pinned:
                return "Pinned"
            case .recent:
                return "Recent"
            }
        }
    }

    let group: Group
    let name: String
    let detail: String
    let url: URL

    var id: String {
        "\(group.rawValue):\(url.standardizedFileURL.path)"
    }
}

struct PathInputCompletion: Identifiable, Equatable, Sendable {
    let name: String
    let detail: String
    let url: URL
    let isDirectory: Bool

    var id: String {
        url.standardizedFileURL.path
    }
}

struct NavigationHistoryLocation: Identifiable, Equatable, Sendable {
    enum Direction: String, Sendable {
        case back
        case forward
    }

    let direction: Direction
    let stackIndex: Int
    let name: String
    let detail: String
    let url: URL

    var id: String {
        "\(direction.rawValue):\(stackIndex):\(url.standardizedFileURL.path)"
    }
}

struct OpenWithApplication: Identifiable, Equatable, Sendable {
    let url: URL
    let displayName: String

    var id: String {
        url.standardizedFileURL.path
    }
}

struct FileMetadataDetails: Equatable, Sendable {
    let ownerName: String?
    let groupName: String?
    let accessModes: [String]
    let accessControlEntries: [String]
    let extendedAttributeNames: [String]

    var ownerLabel: String? {
        ownerName
    }

    var groupLabel: String? {
        groupName
    }

    var accessLabel: String? {
        accessModes.isEmpty ? nil : accessModes.joined(separator: ", ")
    }

    var accessControlLabel: String? {
        guard !accessControlEntries.isEmpty else {
            return nil
        }

        if accessControlEntries.count <= 2 {
            return accessControlEntries.joined(separator: "; ")
        }

        let visibleEntries = accessControlEntries.prefix(2).joined(separator: "; ")
        return "\(visibleEntries) +\(accessControlEntries.count - 2) more"
    }

    var extendedAttributesLabel: String? {
        guard !extendedAttributeNames.isEmpty else {
            return nil
        }

        if extendedAttributeNames.count <= 3 {
            return extendedAttributeNames.joined(separator: ", ")
        }

        let visibleNames = extendedAttributeNames.prefix(3).joined(separator: ", ")
        return "\(visibleNames) +\(extendedAttributeNames.count - 3) more"
    }
}

enum BrowserFocusTarget: Equatable, Sendable {
    case addressBar
    case searchField
}

struct BrowserFocusRequest: Equatable, Sendable {
    let id: UUID
    let target: BrowserFocusTarget

    init(target: BrowserFocusTarget) {
        self.id = UUID()
        self.target = target
    }
}

struct FileInspectorSummary: Equatable, Sendable {
    let title: String
    let subtitle: String
    let itemCount: Int
    let folderCount: Int
    let fileCount: Int
    let packageCount: Int
    let knownByteCount: Int64
    let sizeLabel: String
    let kindLabel: String?
    let modifiedLabel: String?
    let createdLabel: String?
    let accessedLabel: String?
    let hiddenLabel: String?
    let lockedLabel: String?
    let permissionsLabel: String?
    let ownerLabel: String?
    let groupLabel: String?
    let accessLabel: String?
    let accessControlLabel: String?
    let tagsLabel: String?
    let extendedAttributesLabel: String?
    let pathLabel: String?
    let parentPathLabel: String?
    let defaultApplication: OpenWithApplication?

    static func single(
        item: FileItem,
        displayName: String,
        tagNames: [String] = [],
        metadataDetails: FileMetadataDetails? = nil,
        defaultApplication: OpenWithApplication? = nil
    ) -> FileInspectorSummary {
        FileInspectorSummary(
            title: displayName,
            subtitle: item.kindLabel,
            itemCount: 1,
            folderCount: item.kind == .folder ? 1 : 0,
            fileCount: item.kind == .file ? 1 : 0,
            packageCount: item.kind == .package ? 1 : 0,
            knownByteCount: item.byteCount ?? 0,
            sizeLabel: item.detailSizeLabel,
            kindLabel: item.kindLabel,
            modifiedLabel: item.modifiedLabel,
            createdLabel: item.createdLabel,
            accessedLabel: item.accessedLabel,
            hiddenLabel: item.isHidden ? "Yes" : "No",
            lockedLabel: item.isLocked ? "Yes" : "No",
            permissionsLabel: "\(item.permissionsLabel) (\(item.writableLabel))",
            ownerLabel: metadataDetails?.ownerLabel,
            groupLabel: metadataDetails?.groupLabel,
            accessLabel: metadataDetails?.accessLabel,
            accessControlLabel: metadataDetails?.accessControlLabel,
            tagsLabel: tagNames.isEmpty ? "None" : tagNames.joined(separator: ", "),
            extendedAttributesLabel: metadataDetails?.extendedAttributesLabel,
            pathLabel: item.url.path,
            parentPathLabel: item.url.deletingLastPathComponent().path,
            defaultApplication: defaultApplication
        )
    }

    static func multiple(items: [FileItem], currentURL: URL?) -> FileInspectorSummary {
        var folderCount = 0
        var packageCount = 0
        var knownByteCount: Int64 = 0

        for item in items {
            switch item.kind {
            case .folder:
                folderCount += 1
            case .package:
                packageCount += 1
            case .file:
                break
            }

            knownByteCount += item.byteCount ?? 0
        }

        let fileCount = items.count - folderCount - packageCount

        return FileInspectorSummary(
            title: "\(items.count) items",
            subtitle: "Multiple selection",
            itemCount: items.count,
            folderCount: folderCount,
            fileCount: fileCount,
            packageCount: packageCount,
            knownByteCount: knownByteCount,
            sizeLabel: ByteCountFormatter.string(fromByteCount: knownByteCount, countStyle: .file),
            kindLabel: nil,
            modifiedLabel: nil,
            createdLabel: nil,
            accessedLabel: nil,
            hiddenLabel: nil,
            lockedLabel: nil,
            permissionsLabel: nil,
            ownerLabel: nil,
            groupLabel: nil,
            accessLabel: nil,
            accessControlLabel: nil,
            tagsLabel: nil,
            extendedAttributesLabel: nil,
            pathLabel: nil,
            parentPathLabel: currentURL?.path,
            defaultApplication: nil
        )
    }
}

private struct VisibleItemsCache: Sendable {
    let itemsVersion: Int
    let query: String
    let kindFilter: FileKindFilter
    let typeFilter: FileTypeFilter
    let dateFilter: FileDateFilter
    let sizeFilter: FileSizeFilter
    let foldersFirst: Bool
    let sortField: FileSortField
    let sortAscending: Bool
    let items: [FileItem]

    func matches(
        tab: BrowserTab,
        kindFilter: FileKindFilter,
        typeFilter: FileTypeFilter,
        dateFilter: FileDateFilter,
        sizeFilter: FileSizeFilter,
        foldersFirst: Bool,
        sortField: FileSortField,
        sortAscending: Bool
    ) -> Bool {
        itemsVersion == tab.itemsVersion
            && query == tab.query
            && self.kindFilter == kindFilter
            && self.typeFilter == typeFilter
            && self.dateFilter == dateFilter
            && self.sizeFilter == sizeFilter
            && self.foldersFirst == foldersFirst
            && self.sortField == sortField
            && self.sortAscending == sortAscending
    }
}

private struct FolderTypeLogoItemsCache: Sendable {
    let itemsVersion: Int
    let items: [FileItem]

    func matches(tab: BrowserTab) -> Bool {
        itemsVersion == tab.itemsVersion
    }
}

private struct ItemInventoryCache: Sendable {
    let itemsVersion: Int
    let folderCount: Int
    let fileCount: Int
    let packageCount: Int
    let hasNoExtension: Bool
    let extensions: Set<String>

    func matches(tab: BrowserTab) -> Bool {
        itemsVersion == tab.itemsVersion
    }

    func contains(_ typeFilter: FileTypeFilter) -> Bool {
        guard typeFilter.isActive else {
            return true
        }

        if typeFilter == .noExtension {
            return hasNoExtension
        }

        return extensions.contains(typeFilter.rawValue)
    }
}

private struct AvailableTypeFiltersCache: Sendable {
    let itemsVersion: Int
    let baseFilters: [FileTypeFilter]
    let baseFilterSet: Set<FileTypeFilter>

    func matches(tab: BrowserTab) -> Bool {
        itemsVersion == tab.itemsVersion
    }

    func filters(including activeTypeFilter: FileTypeFilter) -> [FileTypeFilter] {
        guard activeTypeFilter.isActive,
              !baseFilterSet.contains(activeTypeFilter) else {
            return baseFilters
        }

        var filters = baseFilters
        filters.append(activeTypeFilter)
        return filters
    }
}

private struct SortedItemsCache: Sendable {
    let itemsVersion: Int
    let foldersFirst: Bool
    let sortField: FileSortField
    let sortAscending: Bool
    let items: [FileItem]

    func matches(
        tab: BrowserTab,
        foldersFirst: Bool,
        sortField: FileSortField,
        sortAscending: Bool
    ) -> Bool {
        itemsVersion == tab.itemsVersion
            && self.foldersFirst == foldersFirst
            && self.sortField == sortField
            && self.sortAscending == sortAscending
    }
}

private struct ItemFilterIndexCache: Sendable {
    let itemsVersion: Int
    let foldersFirst: Bool
    let sortField: FileSortField
    let sortAscending: Bool
    let allItems: [FileItem]
    let folders: [FileItem]
    let files: [FileItem]
    let packages: [FileItem]
    let noExtensionItems: [FileItem]
    let noExtensionFiles: [FileItem]
    let noExtensionPackages: [FileItem]
    let itemsByExtension: [String: [FileItem]]
    let filesByExtension: [String: [FileItem]]
    let packagesByExtension: [String: [FileItem]]

    func matches(
        tab: BrowserTab,
        foldersFirst: Bool,
        sortField: FileSortField,
        sortAscending: Bool
    ) -> Bool {
        itemsVersion == tab.itemsVersion
            && self.foldersFirst == foldersFirst
            && self.sortField == sortField
            && self.sortAscending == sortAscending
    }

    func items(kindFilter: FileKindFilter, typeFilter: FileTypeFilter) -> [FileItem] {
        if typeFilter.isActive {
            if typeFilter == .noExtension {
                switch kindFilter {
                case .all:
                    return noExtensionItems
                case .folders:
                    return []
                case .files:
                    return noExtensionFiles
                case .packages:
                    return noExtensionPackages
                }
            }

            switch kindFilter {
            case .all:
                return itemsByExtension[typeFilter.rawValue] ?? []
            case .folders:
                return []
            case .files:
                return filesByExtension[typeFilter.rawValue] ?? []
            case .packages:
                return packagesByExtension[typeFilter.rawValue] ?? []
            }
        }

        switch kindFilter {
        case .all:
            return allItems
        case .folders:
            return folders
        case .files:
            return files
        case .packages:
            return packages
        }
    }
}

private struct VisibleSectionsCache: Sendable {
    let itemsVersion: Int
    let query: String
    let kindFilter: FileKindFilter
    let typeFilter: FileTypeFilter
    let dateFilter: FileDateFilter
    let sizeFilter: FileSizeFilter
    let foldersFirst: Bool
    let sortField: FileSortField
    let sortAscending: Bool
    let groupField: FileGroupField
    let sections: [FileItemSection]

    func matches(
        tab: BrowserTab,
        kindFilter: FileKindFilter,
        typeFilter: FileTypeFilter,
        dateFilter: FileDateFilter,
        sizeFilter: FileSizeFilter,
        foldersFirst: Bool,
        sortField: FileSortField,
        sortAscending: Bool,
        groupField: FileGroupField
    ) -> Bool {
        itemsVersion == tab.itemsVersion
            && query == tab.query
            && self.kindFilter == kindFilter
            && self.typeFilter == typeFilter
            && self.dateFilter == dateFilter
            && self.sizeFilter == sizeFilter
            && self.foldersFirst == foldersFirst
            && self.sortField == sortField
            && self.sortAscending == sortAscending
            && self.groupField == groupField
    }
}

private struct SelectedItemsCache: Sendable {
    let itemsVersion: Int
    let selectionVersion: Int
    let items: [FileItem]

    func matches(tab: BrowserTab) -> Bool {
        itemsVersion == tab.itemsVersion
            && selectionVersion == tab.selectionVersion
    }
}

private struct SelectionStatusSummaryCache: Sendable {
    let itemsVersion: Int
    let selectionVersion: Int
    let showFileExtensions: Bool
    let summary: String?

    func matches(tab: BrowserTab, showFileExtensions: Bool) -> Bool {
        itemsVersion == tab.itemsVersion
            && selectionVersion == tab.selectionVersion
            && self.showFileExtensions == showFileExtensions
    }
}

private struct SelectedItemsAggregate: Sendable {
    let itemsVersion: Int
    let selectionVersion: Int
    let itemCount: Int
    let folderCount: Int
    let fileCount: Int
    let packageCount: Int
    let knownByteCount: Int64
    let unknownFileCount: Int
    let sizeLabel: String
    let firstItem: FileItem?

    func matches(tab: BrowserTab) -> Bool {
        itemsVersion == tab.itemsVersion
            && selectionVersion == tab.selectionVersion
    }
}

private struct InspectorSummaryCache: Sendable {
    let itemsVersion: Int
    let selectionVersion: Int
    let showFileExtensions: Bool
    let currentURL: URL?
    let summary: FileInspectorSummary?

    func matches(tab: BrowserTab, showFileExtensions: Bool) -> Bool {
        itemsVersion == tab.itemsVersion
            && selectionVersion == tab.selectionVersion
            && self.showFileExtensions == showFileExtensions
            && currentURL == tab.currentURL
    }
}

private struct PathComponentsCache: Sendable {
    let currentPath: String
    let components: [BrowserPathComponent]
}

private struct AddressMenuLocationsCache: Sendable {
    let currentPath: String?
    let typedPathHistoryPaths: [String]
    let pinnedDirectoryPaths: [String]
    let recentDirectoryPaths: [String]
    let locations: [AddressMenuLocation]

    func matches(currentPath: String?, typedPathHistory: [URL], pinnedDirectories: [URL], recentDirectories: [URL]) -> Bool {
        self.currentPath == currentPath
            && typedPathHistoryPaths == typedPathHistory.prefix(12).map { $0.standardizedFileURL.path }
            && pinnedDirectoryPaths == pinnedDirectories.prefix(8).map { $0.standardizedFileURL.path }
            && recentDirectoryPaths == recentDirectories.prefix(10).map { $0.standardizedFileURL.path }
    }
}

private struct ChildFolderComponentsCache: Sendable {
    let includingHidden: Bool
    let limit: Int
    let components: [BrowserPathComponent]

    func matches(includingHidden: Bool, limit: Int) -> Bool {
        self.includingHidden == includingHidden
            && self.limit == limit
    }
}

private struct PathInputCompletionsCache: Sendable {
    let rawInput: String
    let basePath: String?
    let includingHidden: Bool
    let limit: Int
    let completions: [PathInputCompletion]

    func matches(rawInput: String, baseURL: URL?, includingHidden: Bool, limit: Int) -> Bool {
        self.rawInput == rawInput
            && basePath == baseURL?.standardizedFileURL.path
            && self.includingHidden == includingHidden
            && self.limit == limit
    }
}

private struct PathInputDirectoryCompletionsCache: Sendable {
    let directoryPath: String
    let includingHidden: Bool
    let completions: [PathInputCompletion]

    func matches(directoryURL: URL, includingHidden: Bool) -> Bool {
        directoryPath == directoryURL.standardizedFileURL.path
            && self.includingHidden == includingHidden
    }
}

private struct FolderViewSettings: Codable, Equatable, Sendable {
    let viewMode: FileViewMode
    let groupField: FileGroupField
    let foldersFirst: Bool
    let sortField: FileSortField
    let sortAscending: Bool
    let showFileExtensions: Bool
    let compactView: Bool
    let showsItemCheckboxes: Bool
    let showsDetailPanel: Bool
    let showsPreviewPanel: Bool
    let showsKindColumn: Bool
    let showsSizeColumn: Bool
    let showsModifiedColumn: Bool
    let showsCreatedColumn: Bool
    let showsAccessedColumn: Bool
    let showsPermissionsColumn: Bool

    private enum CodingKeys: String, CodingKey {
        case viewMode
        case groupField
        case foldersFirst
        case sortField
        case sortAscending
        case showFileExtensions
        case compactView
        case showsItemCheckboxes
        case showsDetailPanel
        case showsPreviewPanel
        case showsKindColumn
        case showsSizeColumn
        case showsModifiedColumn
        case showsCreatedColumn
        case showsAccessedColumn
        case showsPermissionsColumn
    }

    @MainActor
    init(store: BrowserStore) {
        self.viewMode = store.viewMode
        self.groupField = store.groupField
        self.foldersFirst = store.foldersFirst
        self.sortField = store.sortField
        self.sortAscending = store.sortAscending
        self.showFileExtensions = store.showFileExtensions
        self.compactView = store.compactView
        self.showsItemCheckboxes = store.showsItemCheckboxes
        self.showsDetailPanel = store.showsDetailPanel
        self.showsPreviewPanel = store.showsPreviewPanel
        self.showsKindColumn = store.showsKindColumn
        self.showsSizeColumn = store.showsSizeColumn
        self.showsModifiedColumn = store.showsModifiedColumn
        self.showsCreatedColumn = store.showsCreatedColumn
        self.showsAccessedColumn = store.showsAccessedColumn
        self.showsPermissionsColumn = store.showsPermissionsColumn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.viewMode = try container.decode(FileViewMode.self, forKey: .viewMode)
        self.groupField = try container.decode(FileGroupField.self, forKey: .groupField)
        self.foldersFirst = try container.decode(Bool.self, forKey: .foldersFirst)
        self.sortField = try container.decode(FileSortField.self, forKey: .sortField)
        self.sortAscending = try container.decode(Bool.self, forKey: .sortAscending)
        self.showFileExtensions = try container.decode(Bool.self, forKey: .showFileExtensions)
        self.compactView = try container.decode(Bool.self, forKey: .compactView)
        self.showsItemCheckboxes = try container.decode(Bool.self, forKey: .showsItemCheckboxes)
        self.showsDetailPanel = try container.decode(Bool.self, forKey: .showsDetailPanel)
        self.showsPreviewPanel = try container.decodeIfPresent(Bool.self, forKey: .showsPreviewPanel) ?? false
        self.showsKindColumn = try container.decode(Bool.self, forKey: .showsKindColumn)
        self.showsSizeColumn = try container.decode(Bool.self, forKey: .showsSizeColumn)
        self.showsModifiedColumn = try container.decode(Bool.self, forKey: .showsModifiedColumn)
        self.showsCreatedColumn = try container.decode(Bool.self, forKey: .showsCreatedColumn)
        self.showsAccessedColumn = try container.decodeIfPresent(Bool.self, forKey: .showsAccessedColumn) ?? true
        self.showsPermissionsColumn = try container.decodeIfPresent(Bool.self, forKey: .showsPermissionsColumn) ?? false
    }

    @MainActor
    func apply(to store: BrowserStore) {
        store.viewMode = viewMode
        store.groupField = groupField
        store.foldersFirst = foldersFirst
        store.sortField = sortField
        store.sortAscending = sortAscending
        store.showFileExtensions = showFileExtensions
        store.compactView = compactView
        store.showsItemCheckboxes = showsItemCheckboxes
        store.showsDetailPanel = showsDetailPanel
        store.showsPreviewPanel = showsPreviewPanel
        store.showsKindColumn = showsKindColumn
        store.showsSizeColumn = showsSizeColumn
        store.showsModifiedColumn = showsModifiedColumn
        store.showsCreatedColumn = showsCreatedColumn
        store.showsAccessedColumn = showsAccessedColumn
        store.showsPermissionsColumn = showsPermissionsColumn
    }
}

private struct FileOperationResult: Sendable {
    var selectedItemIDs: Set<FileItem.ID> = []
    var undoAction: FileUndoAction?
}

private struct FolderPermissionSeed: Sendable {
    let url: URL
    let permissions: UInt16
}

private final class FileOperationCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var storedIsCancelled = false

    var isCancelled: Bool {
        lock.withLock {
            storedIsCancelled
        }
    }

    func cancel() {
        lock.withLock {
            storedIsCancelled = true
        }
    }
}

private struct FileOperationContext: Sendable {
    let cancellationToken: FileOperationCancellationToken
    let reportCompleted: @Sendable (Int) -> Void

    func checkCancellation() throws {
        if cancellationToken.isCancelled {
            throw CancellationError()
        }
    }
}

private enum FileUndoAction: Sendable {
    case createFile(URL)
    case createFolder(URL)
    case rename([(from: URL, to: URL)])
    case copy([(from: URL, to: URL)])
    case duplicate([(from: URL, to: URL)])
    case alias([(from: URL, to: URL)])
    case move([(from: URL, to: URL)])
    case trash([(from: URL, to: URL)])
    case compress(archiveURL: URL, sourceURLs: [URL])
    case extract([(archiveURL: URL, destinationURL: URL)])

    var undoTitle: String {
        switch self {
        case .createFile, .createFolder:
            return "Undo New"
        case .rename(let moves):
            return moves.count > 1 ? "Undo Batch Rename" : "Undo Rename"
        case .copy:
            return "Undo Copy"
        case .duplicate:
            return "Undo Duplicate"
        case .alias:
            return "Undo Make Alias"
        case .move:
            return "Undo Move"
        case .trash:
            return "Undo Move to Trash"
        case .compress:
            return "Undo Zip"
        case .extract:
            return "Undo Extract"
        }
    }

    var redoTitle: String {
        switch self {
        case .createFile, .createFolder:
            return "Redo New"
        case .rename(let moves):
            return moves.count > 1 ? "Redo Batch Rename" : "Redo Rename"
        case .copy:
            return "Redo Copy"
        case .duplicate:
            return "Redo Duplicate"
        case .alias:
            return "Redo Make Alias"
        case .move:
            return "Redo Move"
        case .trash:
            return "Redo Move to Trash"
        case .compress:
            return "Redo Zip"
        case .extract:
            return "Redo Extract"
        }
    }
}

@Observable
@MainActor
final class BrowserStore {
    private enum PreferenceKey {
        static let showHiddenFiles = "BetterFiles.showHiddenFiles"
        static let foldersFirst = "BetterFiles.foldersFirst"
        static let kindFilter = "BetterFiles.kindFilter"
        static let typeFilter = "BetterFiles.typeFilter"
        static let dateFilter = "BetterFiles.dateFilter"
        static let sizeFilter = "BetterFiles.sizeFilter"
        static let sortField = "BetterFiles.sortField"
        static let sortAscending = "BetterFiles.sortAscending"
        static let groupField = "BetterFiles.groupField"
        static let showFileExtensions = "BetterFiles.showFileExtensions"
        static let compactView = "BetterFiles.compactView"
        static let showsNavigationPane = "BetterFiles.showsNavigationPane"
        static let showsDetailPanel = "BetterFiles.showsDetailPanel"
        static let showsPreviewPanel = "BetterFiles.showsPreviewPanel"
        static let showsItemCheckboxes = "BetterFiles.showsItemCheckboxes"
        static let showsKindColumn = "BetterFiles.showsKindColumn"
        static let showsSizeColumn = "BetterFiles.showsSizeColumn"
        static let showsModifiedColumn = "BetterFiles.showsModifiedColumn"
        static let showsCreatedColumn = "BetterFiles.showsCreatedColumn"
        static let showsAccessedColumn = "BetterFiles.showsAccessedColumn"
        static let showsPermissionsColumn = "BetterFiles.showsPermissionsColumn"
        static let viewMode = "BetterFiles.viewMode"
        static let folderViewSettings = "BetterFiles.folderViewSettings"
        static let tabPaths = "BetterFiles.tabPaths"
        static let selectedTabPath = "BetterFiles.selectedTabPath"
        static let typedPathHistoryPaths = "BetterFiles.typedPathHistoryPaths"
        static let recentDirectoryPaths = "BetterFiles.recentDirectoryPaths"
        static let recentFilePaths = "BetterFiles.recentFilePaths"
        static let pinnedDirectoryPaths = "BetterFiles.pinnedDirectoryPaths"
        static let sidebarExpandedPaths = "BetterFiles.sidebarExpandedPaths"
    }

    private let service: FileSystemServicing
    @ObservationIgnored private var loadTasks: [BrowserTab.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var searchTasks: [BrowserTab.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var reloadDebounceTasks: [BrowserTab.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var searchDebounceTasks: [BrowserTab.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var directoryWatchers: [BrowserTab.ID: DirectoryWatcher] = [:]
    @ObservationIgnored private var visibleItemsCaches: [BrowserTab.ID: VisibleItemsCache] = [:]
    @ObservationIgnored private var folderTypeLogoItemsCaches: [BrowserTab.ID: FolderTypeLogoItemsCache] = [:]
    @ObservationIgnored private var itemInventoryCaches: [BrowserTab.ID: ItemInventoryCache] = [:]
    @ObservationIgnored private var availableTypeFiltersCaches: [BrowserTab.ID: AvailableTypeFiltersCache] = [:]
    @ObservationIgnored private var sortedItemsCaches: [BrowserTab.ID: SortedItemsCache] = [:]
    @ObservationIgnored private var itemFilterIndexCaches: [BrowserTab.ID: ItemFilterIndexCache] = [:]
    @ObservationIgnored private var visibleSectionsCaches: [String: VisibleSectionsCache] = [:]
    @ObservationIgnored private var directoryContentSnapshots: [String: DirectoryContentSnapshot] = [:]
    @ObservationIgnored private var directoryContentSnapshotOrder: [String] = []
    @ObservationIgnored private var selectedItemsCaches: [BrowserTab.ID: SelectedItemsCache] = [:]
    @ObservationIgnored private var selectedItemsAggregateCaches: [BrowserTab.ID: SelectedItemsAggregate] = [:]
    @ObservationIgnored private var selectionStatusSummaryCaches: [BrowserTab.ID: SelectionStatusSummaryCache] = [:]
    @ObservationIgnored private var inspectorSummaryCaches: [BrowserTab.ID: InspectorSummaryCache] = [:]
    @ObservationIgnored private var pathComponentsCache: PathComponentsCache?
    @ObservationIgnored private var addressMenuLocationsCache: AddressMenuLocationsCache?
    @ObservationIgnored private var childFolderComponentsCaches: [String: ChildFolderComponentsCache] = [:]
    @ObservationIgnored private var pathInputCompletionsCaches: [String: PathInputCompletionsCache] = [:]
    @ObservationIgnored private var pathInputDirectoryCompletionsCache: PathInputDirectoryCompletionsCache?
    @ObservationIgnored private var openWithApplicationsCache: [String: [OpenWithApplication]] = [:]
    @ObservationIgnored private var volumeStatusSummaryCaches: [String: VolumeStatusSummary] = [:]
    @ObservationIgnored private var fileOperationTask: Task<Void, Never>?
    @ObservationIgnored private var fileOperationCancellationToken: FileOperationCancellationToken?
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let persistsTabSession: Bool
    @ObservationIgnored private var preferenceFlushTask: Task<Void, Never>?
    @ObservationIgnored private static var cachedPreferenceValuesByDefaultsID: [ObjectIdentifier: [String: Any]] = [:]

    var tabs: [BrowserTab]
    var selectedTabID: BrowserTab.ID
    var recentDirectories: [URL]
    var recentFiles: [URL]
    var pinnedDirectories: [URL]
    private(set) var typedPathHistory: [URL]
    private(set) var closedTabURLs: [URL]
    @ObservationIgnored private var closedTabInsertions: [ClosedTabInsertion]
    private(set) var sidebarExpandedPaths: [String]
    private var folderViewSettingsByPath: [String: FolderViewSettings]
    var clipboardPayload: FileClipboardPayload?
    var activeOperation: FileOperationSummary?
    var lastOperationSummary: FileOperationSummary?
    private(set) var performanceEvents: [PerformanceEventSummary]
    var focusRequest: BrowserFocusRequest?
    var masksSensitiveData = false
    var inlineRenameItemID: FileItem.ID?
    var inlineRenameDraft: String
    private var undoStack: [FileUndoAction]
    private var redoStack: [FileUndoAction]
    var showHiddenFiles: Bool {
        didSet {
            guard oldValue != showHiddenFiles else { return }
            setPreference(showHiddenFiles, forKey: PreferenceKey.showHiddenFiles)
            reload()
        }
    }
    var foldersFirst: Bool {
        didSet {
            guard oldValue != foldersFirst else { return }
            setPreference(foldersFirst, forKey: PreferenceKey.foldersFirst)
        }
    }
    var kindFilter: FileKindFilter {
        didSet {
            guard oldValue != kindFilter else { return }
            setPreference(kindFilter.rawValue, forKey: PreferenceKey.kindFilter)
        }
    }
    var typeFilter: FileTypeFilter {
        didSet {
            guard oldValue != typeFilter else { return }
            setPreference(typeFilter.rawValue, forKey: PreferenceKey.typeFilter)
        }
    }
    var dateFilter: FileDateFilter {
        didSet {
            guard oldValue != dateFilter else { return }
            setPreference(dateFilter.rawValue, forKey: PreferenceKey.dateFilter)
        }
    }
    var sizeFilter: FileSizeFilter {
        didSet {
            guard oldValue != sizeFilter else { return }
            setPreference(sizeFilter.rawValue, forKey: PreferenceKey.sizeFilter)
        }
    }
    var sortField: FileSortField {
        didSet {
            guard oldValue != sortField else { return }
            setPreference(sortField.rawValue, forKey: PreferenceKey.sortField)
        }
    }
    var sortAscending: Bool {
        didSet {
            guard oldValue != sortAscending else { return }
            setPreference(sortAscending, forKey: PreferenceKey.sortAscending)
        }
    }
    var groupField: FileGroupField {
        didSet {
            guard oldValue != groupField else { return }
            setPreference(groupField.rawValue, forKey: PreferenceKey.groupField)
        }
    }
    var showFileExtensions: Bool {
        didSet {
            guard oldValue != showFileExtensions else { return }
            setPreference(showFileExtensions, forKey: PreferenceKey.showFileExtensions)
        }
    }
    var compactView: Bool {
        didSet {
            guard oldValue != compactView else { return }
            setPreference(compactView, forKey: PreferenceKey.compactView)
        }
    }
    var showsNavigationPane: Bool {
        didSet {
            guard oldValue != showsNavigationPane else { return }
            setPreference(showsNavigationPane, forKey: PreferenceKey.showsNavigationPane)
        }
    }
    var showsDetailPanel: Bool {
        didSet {
            guard oldValue != showsDetailPanel else { return }
            setPreference(showsDetailPanel, forKey: PreferenceKey.showsDetailPanel)
        }
    }
    var showsPreviewPanel: Bool {
        didSet {
            guard oldValue != showsPreviewPanel else { return }
            setPreference(showsPreviewPanel, forKey: PreferenceKey.showsPreviewPanel)
        }
    }
    var showsItemCheckboxes: Bool {
        didSet {
            guard oldValue != showsItemCheckboxes else { return }
            setPreference(showsItemCheckboxes, forKey: PreferenceKey.showsItemCheckboxes)
        }
    }
    var showsKindColumn: Bool {
        didSet {
            guard oldValue != showsKindColumn else { return }
            setPreference(showsKindColumn, forKey: PreferenceKey.showsKindColumn)
        }
    }
    var showsSizeColumn: Bool {
        didSet {
            guard oldValue != showsSizeColumn else { return }
            setPreference(showsSizeColumn, forKey: PreferenceKey.showsSizeColumn)
        }
    }
    var showsModifiedColumn: Bool {
        didSet {
            guard oldValue != showsModifiedColumn else { return }
            setPreference(showsModifiedColumn, forKey: PreferenceKey.showsModifiedColumn)
        }
    }
    var showsCreatedColumn: Bool {
        didSet {
            guard oldValue != showsCreatedColumn else { return }
            setPreference(showsCreatedColumn, forKey: PreferenceKey.showsCreatedColumn)
        }
    }
    var showsAccessedColumn: Bool {
        didSet {
            guard oldValue != showsAccessedColumn else { return }
            setPreference(showsAccessedColumn, forKey: PreferenceKey.showsAccessedColumn)
        }
    }
    var showsPermissionsColumn: Bool {
        didSet {
            guard oldValue != showsPermissionsColumn else { return }
            setPreference(showsPermissionsColumn, forKey: PreferenceKey.showsPermissionsColumn)
        }
    }
    var viewMode: FileViewMode {
        didSet {
            guard oldValue != viewMode else { return }
            setPreference(viewMode.rawValue, forKey: PreferenceKey.viewMode)
        }
    }

    init(
        service: FileSystemServicing = FileSystemService(),
        userDefaults: UserDefaults = .standard,
        initialURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        restoresTabSession: Bool = true,
        persistsTabSession: Bool = true
    ) {
        let restoredTabConfiguration = restoresTabSession
            ? Self.restoredTabConfiguration(
                userDefaults: userDefaults,
                fallbackURL: initialURL
            )
            : Self.initialTabConfiguration(for: initialURL)

        self.service = service
        self.userDefaults = userDefaults
        self.persistsTabSession = persistsTabSession
        let restoredPinnedDirectories = Self.restoredPinnedDirectories(userDefaults: userDefaults)

        self.tabs = restoredTabConfiguration.tabs
        self.selectedTabID = restoredTabConfiguration.selectedTabID
        self.typedPathHistory = Self.restoredTypedPathHistory(userDefaults: userDefaults)
        self.recentDirectories = Self.restoredRecentDirectories(userDefaults: userDefaults).filter { recentURL in
            !restoredPinnedDirectories.contains { pinnedURL in
                pinnedURL.standardizedFileURL.path == recentURL.standardizedFileURL.path
            }
        }
        self.recentFiles = Self.restoredRecentFiles(userDefaults: userDefaults)
        self.pinnedDirectories = restoredPinnedDirectories
        self.closedTabURLs = []
        self.closedTabInsertions = []
        self.sidebarExpandedPaths = Self.restoredSidebarExpandedPaths(userDefaults: userDefaults)
        self.folderViewSettingsByPath = Self.restoredFolderViewSettings(userDefaults: userDefaults)
        self.clipboardPayload = nil
        self.activeOperation = nil
        self.lastOperationSummary = nil
        self.performanceEvents = []
        self.focusRequest = nil
        self.inlineRenameItemID = nil
        self.inlineRenameDraft = ""
        self.undoStack = []
        self.redoStack = []
        self.showHiddenFiles = Self.cachedPreferenceValue(forKey: PreferenceKey.showHiddenFiles, userDefaults: userDefaults) as? Bool
            ?? userDefaults.bool(forKey: PreferenceKey.showHiddenFiles)
        self.foldersFirst = Self.cachedPreferenceValue(forKey: PreferenceKey.foldersFirst, userDefaults: userDefaults) as? Bool ?? userDefaults.object(forKey: PreferenceKey.foldersFirst) as? Bool ?? true
        self.kindFilter = FileKindFilter(
            rawValue: Self.cachedPreferenceValue(forKey: PreferenceKey.kindFilter, userDefaults: userDefaults) as? String ?? userDefaults.string(forKey: PreferenceKey.kindFilter) ?? ""
        ) ?? .all
        self.typeFilter = FileTypeFilter(
            rawValue: Self.cachedPreferenceValue(forKey: PreferenceKey.typeFilter, userDefaults: userDefaults) as? String ?? userDefaults.string(forKey: PreferenceKey.typeFilter) ?? ""
        )
        self.dateFilter = FileDateFilter(
            rawValue: Self.cachedPreferenceValue(forKey: PreferenceKey.dateFilter, userDefaults: userDefaults) as? String ?? userDefaults.string(forKey: PreferenceKey.dateFilter) ?? ""
        ) ?? .any
        self.sizeFilter = FileSizeFilter(
            rawValue: Self.cachedPreferenceValue(forKey: PreferenceKey.sizeFilter, userDefaults: userDefaults) as? String ?? userDefaults.string(forKey: PreferenceKey.sizeFilter) ?? ""
        ) ?? .any
        self.sortField = FileSortField(
            rawValue: Self.cachedPreferenceValue(forKey: PreferenceKey.sortField, userDefaults: userDefaults) as? String ?? userDefaults.string(forKey: PreferenceKey.sortField) ?? ""
        ) ?? .name
        self.sortAscending = Self.cachedPreferenceValue(forKey: PreferenceKey.sortAscending, userDefaults: userDefaults) as? Bool ?? userDefaults.object(forKey: PreferenceKey.sortAscending) as? Bool ?? true
        self.groupField = FileGroupField(
            rawValue: Self.cachedPreferenceValue(forKey: PreferenceKey.groupField, userDefaults: userDefaults) as? String ?? userDefaults.string(forKey: PreferenceKey.groupField) ?? ""
        ) ?? .none
        self.showFileExtensions = Self.cachedPreferenceValue(forKey: PreferenceKey.showFileExtensions, userDefaults: userDefaults) as? Bool ?? userDefaults.object(forKey: PreferenceKey.showFileExtensions) as? Bool ?? true
        self.compactView = Self.cachedPreferenceValue(forKey: PreferenceKey.compactView, userDefaults: userDefaults) as? Bool ?? userDefaults.object(forKey: PreferenceKey.compactView) as? Bool ?? false
        self.showsNavigationPane = Self.cachedPreferenceValue(forKey: PreferenceKey.showsNavigationPane, userDefaults: userDefaults) as? Bool ?? userDefaults.object(forKey: PreferenceKey.showsNavigationPane) as? Bool ?? true
        self.showsDetailPanel = Self.cachedPreferenceValue(forKey: PreferenceKey.showsDetailPanel, userDefaults: userDefaults) as? Bool ?? userDefaults.object(forKey: PreferenceKey.showsDetailPanel) as? Bool ?? false
        self.showsPreviewPanel = Self.cachedPreferenceValue(forKey: PreferenceKey.showsPreviewPanel, userDefaults: userDefaults) as? Bool ?? userDefaults.object(forKey: PreferenceKey.showsPreviewPanel) as? Bool ?? false
        self.showsItemCheckboxes = Self.cachedPreferenceValue(forKey: PreferenceKey.showsItemCheckboxes, userDefaults: userDefaults) as? Bool ?? userDefaults.object(forKey: PreferenceKey.showsItemCheckboxes) as? Bool ?? false
        self.showsKindColumn = Self.cachedPreferenceValue(forKey: PreferenceKey.showsKindColumn, userDefaults: userDefaults) as? Bool ?? userDefaults.object(forKey: PreferenceKey.showsKindColumn) as? Bool ?? true
        self.showsSizeColumn = Self.cachedPreferenceValue(forKey: PreferenceKey.showsSizeColumn, userDefaults: userDefaults) as? Bool ?? userDefaults.object(forKey: PreferenceKey.showsSizeColumn) as? Bool ?? true
        self.showsModifiedColumn = Self.cachedPreferenceValue(forKey: PreferenceKey.showsModifiedColumn, userDefaults: userDefaults) as? Bool ?? userDefaults.object(forKey: PreferenceKey.showsModifiedColumn) as? Bool ?? true
        self.showsCreatedColumn = Self.cachedPreferenceValue(forKey: PreferenceKey.showsCreatedColumn, userDefaults: userDefaults) as? Bool ?? userDefaults.object(forKey: PreferenceKey.showsCreatedColumn) as? Bool ?? true
        self.showsAccessedColumn = Self.cachedPreferenceValue(forKey: PreferenceKey.showsAccessedColumn, userDefaults: userDefaults) as? Bool ?? userDefaults.object(forKey: PreferenceKey.showsAccessedColumn) as? Bool ?? true
        self.showsPermissionsColumn = Self.cachedPreferenceValue(forKey: PreferenceKey.showsPermissionsColumn, userDefaults: userDefaults) as? Bool ?? userDefaults.object(forKey: PreferenceKey.showsPermissionsColumn) as? Bool ?? false
        self.viewMode = FileViewMode(
            rawValue: Self.cachedPreferenceValue(forKey: PreferenceKey.viewMode, userDefaults: userDefaults) as? String ?? userDefaults.string(forKey: PreferenceKey.viewMode) ?? ""
        ) ?? .details

        if let currentURL = restoredTabConfiguration.tabs.first(where: { $0.id == restoredTabConfiguration.selectedTabID })?.currentURL {
            applySavedFolderViewSettings(for: currentURL)
        }

        reload()
    }

    deinit {
        loadTasks.values.forEach { $0.cancel() }
        searchTasks.values.forEach { $0.cancel() }
        reloadDebounceTasks.values.forEach { $0.cancel() }
        searchDebounceTasks.values.forEach { $0.cancel() }
        directoryWatchers.values.forEach { $0.cancel() }
        fileOperationTask?.cancel()
        preferenceFlushTask?.cancel()
    }

    private func setPreference(_ value: Any, forKey key: String) {
        let defaultsID = ObjectIdentifier(userDefaults)
        var cachedValues = Self.cachedPreferenceValuesByDefaultsID[defaultsID] ?? [:]
        cachedValues[key] = value
        Self.cachedPreferenceValuesByDefaultsID[defaultsID] = cachedValues
        schedulePreferenceFlush()
    }

    private func schedulePreferenceFlush() {
        guard preferenceFlushTask == nil else {
            return
        }

        preferenceFlushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                self?.flushCachedPreferences()
            }
        }
    }

    func flushPendingPreferences() {
        preferenceFlushTask?.cancel()
        flushCachedPreferences()
    }

    private func flushCachedPreferences() {
        defer {
            preferenceFlushTask = nil
        }

        let defaultsID = ObjectIdentifier(userDefaults)
        guard let cachedValues = Self.cachedPreferenceValuesByDefaultsID[defaultsID] else {
            return
        }

        for (key, value) in cachedValues {
            userDefaults.set(value, forKey: key)
        }

        Self.cachedPreferenceValuesByDefaultsID[defaultsID] = nil
    }

    private static func cachedPreferenceValue(forKey key: String, userDefaults: UserDefaults) -> Any? {
        cachedPreferenceValuesByDefaultsID[ObjectIdentifier(userDefaults)]?[key]
    }

    private static func restoredTabConfiguration(
        userDefaults: UserDefaults,
        fallbackURL: URL
    ) -> (tabs: [BrowserTab], selectedTabID: BrowserTab.ID) {
        let fallbackTab = BrowserTab(url: fallbackURL)
        let restoredPaths = userDefaults.stringArray(forKey: PreferenceKey.tabPaths) ?? []
        let selectedPath = userDefaults.string(forKey: PreferenceKey.selectedTabPath)

        var seenPaths: Set<String> = []
        let restoredTabs = restoredPaths.prefix(12).compactMap { path -> BrowserTab? in
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
                .standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  seenPaths.insert(url.path).inserted
            else {
                return nil
            }

            return BrowserTab(url: url)
        }

        let tabs = restoredTabs.isEmpty ? [fallbackTab] : restoredTabs
        let selectedTabID = tabs.first { tab in
            tab.currentURL?.path == selectedPath
        }?.id ?? tabs.first?.id ?? fallbackTab.id

        return (tabs, selectedTabID)
    }

    private static func initialTabConfiguration(for url: URL) -> (tabs: [BrowserTab], selectedTabID: BrowserTab.ID) {
        let tab = BrowserTab(url: url.standardizedFileURL)
        return ([tab], tab.id)
    }

    private static func restoredRecentDirectories(userDefaults: UserDefaults) -> [URL] {
        restoredDirectoryList(
            userDefaults: userDefaults,
            key: PreferenceKey.recentDirectoryPaths,
            limit: 8
        )
    }

    private static func restoredTypedPathHistory(userDefaults: UserDefaults) -> [URL] {
        restoredDirectoryList(
            userDefaults: userDefaults,
            key: PreferenceKey.typedPathHistoryPaths,
            limit: 12
        )
    }

    private static func restoredRecentFiles(userDefaults: UserDefaults) -> [URL] {
        restoredFileList(
            userDefaults: userDefaults,
            key: PreferenceKey.recentFilePaths,
            limit: 12
        )
    }

    private static func restoredPinnedDirectories(userDefaults: UserDefaults) -> [URL] {
        restoredDirectoryList(
            userDefaults: userDefaults,
            key: PreferenceKey.pinnedDirectoryPaths,
            limit: 8
        )
    }

    private static func restoredSidebarExpandedPaths(userDefaults: UserDefaults) -> [String] {
        let paths = Self.cachedPreferenceValue(forKey: PreferenceKey.sidebarExpandedPaths, userDefaults: userDefaults) as? [String]
            ?? userDefaults.stringArray(forKey: PreferenceKey.sidebarExpandedPaths)
            ?? []

        return normalizedSidebarExpandedPaths(paths)
    }

    private static func normalizedSidebarExpandedPaths(_ paths: [String]) -> [String] {
        var normalizedPaths: [String] = []
        var seenPaths: Set<String> = []

        for path in paths {
            let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPath.isEmpty else {
                continue
            }

            let standardizedPath = URL(
                fileURLWithPath: (trimmedPath as NSString).expandingTildeInPath,
                isDirectory: true
            )
            .standardizedFileURL
            .path

            guard seenPaths.insert(standardizedPath).inserted else {
                continue
            }

            normalizedPaths.append(standardizedPath)
            if normalizedPaths.count >= sidebarExpandedPathLimit {
                break
            }
        }

        return normalizedPaths
    }

    private static func restoredFolderViewSettings(userDefaults: UserDefaults) -> [String: FolderViewSettings] {
        guard let data = userDefaults.data(forKey: PreferenceKey.folderViewSettings),
              let settings = try? JSONDecoder().decode([String: FolderViewSettings].self, from: data)
        else {
            return [:]
        }

        return settings
    }

    private static func restoredDirectoryList(userDefaults: UserDefaults, key: String, limit: Int) -> [URL] {
        let paths = userDefaults.stringArray(forKey: key) ?? []
        var seenPaths: Set<String> = []

        return paths.prefix(limit).compactMap { path -> URL? in
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
                .standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  seenPaths.insert(url.path).inserted
            else {
                return nil
            }

            return url
        }
    }

    private static func restoredFileList(userDefaults: UserDefaults, key: String, limit: Int) -> [URL] {
        let paths = userDefaults.stringArray(forKey: key) ?? []
        var seenPaths: Set<String> = []

        return paths.prefix(limit).compactMap { path -> URL? in
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                .standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  seenPaths.insert(url.path).inserted
            else {
                return nil
            }

            return url
        }
    }

    private static func folderViewSettingsKey(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    var selectedTab: BrowserTab {
        tabs[selectedTabIndex]
    }

    var currentURL: URL? {
        get { selectedTab.currentURL }
        set {
            updateSelectedTab { tab in
                tab.currentURL = newValue
            }
        }
    }

    var pathInput: String {
        get { selectedTab.pathInput }
        set {
            updateSelectedTab { tab in
                tab.pathInput = newValue
            }
        }
    }

    var query: String {
        get { selectedTab.query }
        set {
            let previousQuery = selectedTab.query
            updateSelectedTab { tab in
                tab.query = newValue
            }
            updateSearch(forChangedQueryFrom: previousQuery, to: newValue)
        }
    }

    var searchesSubfolders: Bool {
        get { selectedTab.searchesSubfolders }
        set {
            guard selectedTab.searchesSubfolders != newValue else {
                return
            }

            updateSelectedTab { tab in
                tab.searchesSubfolders = newValue
                tab.searchSummary = nil
            }

            if newValue {
                scheduleRecursiveSearchIfNeeded(for: selectedTabID)
            } else {
                cancelRecursiveSearch(tabID: selectedTabID)
                reload()
            }
        }
    }

    var items: [FileItem] {
        selectedTab.items
    }

    var selectedItemIDs: Set<FileItem.ID> {
        get { selectedTab.selectedItemIDs }
        set {
            updateSelectedTab { tab in
                tab.selectedItemIDs = newValue
            }
        }
    }

    var errorMessage: String? {
        selectedTab.errorMessage
    }

    var isLoading: Bool {
        selectedTab.isLoading
    }

    var loadSummary: DirectoryLoadSummary? {
        selectedTab.loadSummary
    }

    var searchSummary: RecursiveSearchSummary? {
        selectedTab.searchSummary
    }

    var lastPerformanceEvent: PerformanceEventSummary? {
        performanceEvents.last
    }

    var performanceReport: String {
        guard !performanceEvents.isEmpty else {
            return "No performance events"
        }

        return (["Action\tItems\tElapsed\tSeconds\tPath"] + performanceEvents.map(\.reportLine)).joined(separator: "\n")
    }

    var canReopenClosedTab: Bool {
        !closedTabURLs.isEmpty
    }

    var canOpenCurrentFolderInNewTab: Bool {
        currentURL != nil
    }

    var canClearTypedPathHistory: Bool {
        !typedPathHistory.isEmpty
    }

    var canMoveSelectedTabToNewWindow: Bool {
        canMoveTabToNewWindow(selectedTabID)
    }

    func canSelectTab(atDisplayIndex displayIndex: Int) -> Bool {
        tabs.indices.contains(displayIndex)
    }

    var canGoBack: Bool {
        !selectedTab.backStack.isEmpty
    }

    var canGoForward: Bool {
        !selectedTab.forwardStack.isEmpty
    }

    var backHistoryLocations: [NavigationHistoryLocation] {
        selectedTab.backStack.indices.reversed().map { index in
            historyLocation(selectedTab.backStack[index], direction: .back, stackIndex: index)
        }
    }

    var forwardHistoryLocations: [NavigationHistoryLocation] {
        selectedTab.forwardStack.indices.reversed().map { index in
            historyLocation(selectedTab.forwardStack[index], direction: .forward, stackIndex: index)
        }
    }

    var usesDefaultDetailsColumns: Bool {
        showsKindColumn
            && showsSizeColumn
            && showsModifiedColumn
            && showsCreatedColumn
            && showsAccessedColumn
            && !showsPermissionsColumn
    }

    var currentFolderHasSavedView: Bool {
        guard let currentURL else {
            return false
        }

        return folderViewSettingsByPath[Self.folderViewSettingsKey(for: currentURL)] != nil
    }

    var hasActiveContentFilters: Bool {
        !query.isEmpty
            || searchesSubfolders
            || kindFilter != .all
            || typeFilter.isActive
            || dateFilter != .any
            || sizeFilter != .any
    }

    var hasVisibleFilterSummary: Bool {
        hasActiveContentFilters
            || showHiddenFiles
            || groupField != .none
    }

    var availableTypeFilters: [FileTypeFilter] {
        let tab = selectedTab

        if let cachedFilters = availableTypeFiltersCaches[tab.id],
           cachedFilters.matches(tab: tab) {
            return cachedFilters.filters(including: typeFilter)
        }

        let inventory = itemInventory(for: tab)
        var filters: [FileTypeFilter] = [.any]

        if inventory.hasNoExtension {
            filters.append(.noExtension)
        }

        filters.append(contentsOf: inventory.extensions.sorted().map { FileTypeFilter(rawValue: $0) })
        let cache = AvailableTypeFiltersCache(
            itemsVersion: tab.itemsVersion,
            baseFilters: filters,
            baseFilterSet: Set(filters)
        )
        availableTypeFiltersCaches[tab.id] = cache
        return cache.filters(including: typeFilter)
    }

    var visibleItems: [FileItem] {
        let tab = selectedTab

        if let cachedItems = visibleItemsCaches[tab.id],
           cachedItems.matches(
               tab: tab,
               kindFilter: kindFilter,
               typeFilter: typeFilter,
               dateFilter: dateFilter,
               sizeFilter: sizeFilter,
               foldersFirst: foldersFirst,
               sortField: sortField,
               sortAscending: sortAscending
           ) {
            return cachedItems.items
        }

        let items = makeVisibleItems(for: tab)
        visibleItemsCaches[tab.id] = VisibleItemsCache(
            itemsVersion: tab.itemsVersion,
            query: tab.query,
            kindFilter: kindFilter,
            typeFilter: typeFilter,
            dateFilter: dateFilter,
            sizeFilter: sizeFilter,
            foldersFirst: foldersFirst,
            sortField: sortField,
            sortAscending: sortAscending,
            items: items
        )
        return items
    }

    var folderTypeLogoItems: [FileItem] {
        folderTypeLogoItems(for: selectedTab)
    }

    func folderTypeLogoItems(for tab: BrowserTab) -> [FileItem] {
        if let cachedItems = folderTypeLogoItemsCaches[tab.id],
           cachedItems.matches(tab: tab) {
            return cachedItems.items
        }

        let items = Self.folderTypeLogoItems(from: tab.items)
        folderTypeLogoItemsCaches[tab.id] = FolderTypeLogoItemsCache(
            itemsVersion: tab.itemsVersion,
            items: items
        )
        return items
    }

    var visibleSections: [FileItemSection] {
        let tab = selectedTab
        let cacheKey = visibleSectionsCacheKey(for: tab)

        if let cachedSections = visibleSectionsCaches[cacheKey],
           cachedSections.matches(
               tab: tab,
               kindFilter: kindFilter,
               typeFilter: typeFilter,
               dateFilter: dateFilter,
               sizeFilter: sizeFilter,
               foldersFirst: foldersFirst,
               sortField: sortField,
               sortAscending: sortAscending,
               groupField: groupField
           ) {
            return cachedSections.sections
        }

        let sections = makeVisibleSections(from: visibleItems)
        visibleSectionsCaches[cacheKey] = VisibleSectionsCache(
            itemsVersion: tab.itemsVersion,
            query: tab.query,
            kindFilter: kindFilter,
            typeFilter: typeFilter,
            dateFilter: dateFilter,
            sizeFilter: sizeFilter,
            foldersFirst: foldersFirst,
            sortField: sortField,
            sortAscending: sortAscending,
            groupField: groupField,
            sections: sections
        )
        return sections
    }

    var selectedItem: FileItem? {
        selectedItems.first
    }

    var selectedItems: [FileItem] {
        let tab = selectedTab

        if let cachedItems = selectedItemsCaches[tab.id], cachedItems.matches(tab: tab) {
            return cachedItems.items
        }

        let ids = tab.selectedItemIDs
        let items = tab.items.filter { ids.contains($0.id) }
        selectedItemsCaches[tab.id] = SelectedItemsCache(
            itemsVersion: tab.itemsVersion,
            selectionVersion: tab.selectionVersion,
            items: items
        )
        selectedItemsAggregateCaches[tab.id] = makeSelectedItemsAggregate(for: tab, items: items)
        return items
    }

    private func selectedItemsAggregate(for tab: BrowserTab) -> SelectedItemsAggregate {
        if let cachedAggregate = selectedItemsAggregateCaches[tab.id], cachedAggregate.matches(tab: tab) {
            return cachedAggregate
        }

        let items = selectedItems
        let aggregate = makeSelectedItemsAggregate(for: tab, items: items)
        selectedItemsAggregateCaches[tab.id] = aggregate
        return aggregate
    }

    private func makeSelectedItemsAggregate(for tab: BrowserTab, items: [FileItem]) -> SelectedItemsAggregate {
        var folderCount = 0
        var packageCount = 0
        var knownByteCount: Int64 = 0
        var unknownFileCount = 0

        for item in items {
            switch item.kind {
            case .folder:
                folderCount += 1
            case .package:
                packageCount += 1
            case .file:
                break
            }

            if let byteCount = item.byteCount {
                knownByteCount += byteCount
            } else if !item.canOpenAsFolder {
                unknownFileCount += 1
            }
        }

        let aggregate = SelectedItemsAggregate(
            itemsVersion: tab.itemsVersion,
            selectionVersion: tab.selectionVersion,
            itemCount: items.count,
            folderCount: folderCount,
            fileCount: items.count - folderCount - packageCount,
            packageCount: packageCount,
            knownByteCount: knownByteCount,
            unknownFileCount: unknownFileCount,
            sizeLabel: ByteCountFormatter.string(fromByteCount: knownByteCount, countStyle: .file),
            firstItem: items.first
        )
        return aggregate
    }

    func displayName(for item: FileItem) -> String {
        if masksSensitiveData {
            return item.canOpenAsFolder ? "Private Folder" : "Private File"
        }

        guard !showFileExtensions,
              item.kind != .folder,
              !item.url.pathExtension.isEmpty else {
            return item.name
        }

        let displayName = (item.name as NSString).deletingPathExtension
        return displayName.isEmpty ? item.name : displayName
    }

    func displayName(for url: URL) -> String {
        if url.path == "/" {
            return "Macintosh HD"
        }

        guard !masksSensitiveData else {
            return "Private Folder"
        }

        return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    private func historyLocation(
        _ url: URL,
        direction: NavigationHistoryLocation.Direction,
        stackIndex: Int
    ) -> NavigationHistoryLocation {
        let standardizedURL = url.standardizedFileURL
        return NavigationHistoryLocation(
            direction: direction,
            stackIndex: stackIndex,
            name: displayName(for: standardizedURL),
            detail: standardizedURL.path,
            url: standardizedURL
        )
    }

    var hasSelection: Bool {
        !selectedTab.selectedItemIDs.isEmpty
    }

    var hasClipboardItems: Bool {
        clipboardPayload?.urls.isEmpty == false
    }

    var canPasteItems: Bool {
        hasClipboardItems || !pasteboardFileURLs().isEmpty
    }

    var canEmptyTrash: Bool {
        Self.trashDirectoryContainsItems(at: Self.trashDirectoryURL)
    }

    func isTrashDirectory(_ url: URL) -> Bool {
        url.standardizedFileURL.path == Self.trashDirectoryURL.path
    }

    var pathComponents: [BrowserPathComponent] {
        guard let currentURL else {
            return []
        }

        let standardizedURL = currentURL.standardizedFileURL
        let currentPath = standardizedURL.path
        if let cache = pathComponentsCache, cache.currentPath == currentPath {
            return cache.components
        }

        let components = standardizedURL.pathComponents
        guard !components.isEmpty else {
            return []
        }

        var breadcrumbs = [
            BrowserPathComponent(
                name: "Macintosh HD",
                url: URL(fileURLWithPath: "/", isDirectory: true)
            )
        ]

        var accumulatedURL = URL(fileURLWithPath: "/", isDirectory: true)
        for component in components.dropFirst() {
            accumulatedURL = accumulatedURL.appendingPathComponent(component, isDirectory: true)
            breadcrumbs.append(BrowserPathComponent(name: component, url: accumulatedURL))
        }

        pathComponentsCache = PathComponentsCache(
            currentPath: currentPath,
            components: breadcrumbs
        )
        return breadcrumbs
    }

    var sidebarPathComponents: [BrowserPathComponent] {
        Array(pathComponents.filter { $0.url.path != "/" }.suffix(5))
    }

    var addressMenuLocations: [AddressMenuLocation] {
        let currentPath = currentURL?.standardizedFileURL.path
        if let cache = addressMenuLocationsCache,
           cache.matches(
                currentPath: currentPath,
                typedPathHistory: typedPathHistory,
                pinnedDirectories: pinnedDirectories,
                recentDirectories: recentDirectories
           ) {
            return cache.locations
        }

        var locations: [AddressMenuLocation] = []
        var seenPaths: Set<String> = []

        func append(_ url: URL, group: AddressMenuLocation.Group, name: String? = nil, allowDuplicatePath: Bool = false) {
            let standardizedURL = url.standardizedFileURL
            let path = standardizedURL.path
            if allowDuplicatePath {
                seenPaths.insert(path)
            } else {
                guard seenPaths.insert(path).inserted else {
                    return
                }
            }

            locations.append(
                AddressMenuLocation(
                    group: group,
                    name: name ?? displayName(for: standardizedURL),
                    detail: path,
                    url: standardizedURL
                )
            )
        }

        for component in pathComponents.reversed() {
            append(component.url, group: .currentPath, name: component.name, allowDuplicatePath: true)
        }

        for location in Self.defaultAddressMenuLocations {
            append(location.url, group: .quickAccess, name: location.name, allowDuplicatePath: true)
        }

        for url in pinnedDirectories.prefix(8) {
            append(url, group: .pinned)
        }

        for url in recentDirectories.prefix(10) {
            append(url, group: .recent)
        }

        for url in typedPathHistory.prefix(12) {
            append(url, group: .typedHistory)
        }

        addressMenuLocationsCache = AddressMenuLocationsCache(
            currentPath: currentPath,
            typedPathHistoryPaths: typedPathHistory.prefix(12).map { $0.standardizedFileURL.path },
            pinnedDirectoryPaths: pinnedDirectories.prefix(8).map { $0.standardizedFileURL.path },
            recentDirectoryPaths: recentDirectories.prefix(10).map { $0.standardizedFileURL.path },
            locations: locations
        )
        return locations
    }

    var pathInputCompletions: [PathInputCompletion] {
        completionsForPathInput(pathInput, relativeTo: currentURL)
    }

    func completionsForPathInput(_ rawInput: String, relativeTo baseURL: URL?, limit: Int = 10) -> [PathInputCompletion] {
        let cacheKey = Self.pathInputCompletionsCacheKey(
            rawInput: rawInput,
            baseURL: baseURL,
            includingHidden: showHiddenFiles,
            limit: limit
        )

        if let cache = pathInputCompletionsCaches[cacheKey],
           cache.matches(rawInput: rawInput, baseURL: baseURL, includingHidden: showHiddenFiles, limit: limit) {
            return cache.completions
        }

        guard let request = Self.pathInputCompletionRequest(for: rawInput, relativeTo: baseURL, limit: limit) else {
            pathInputCompletionsCaches[cacheKey] = PathInputCompletionsCache(
                rawInput: rawInput,
                basePath: baseURL?.standardizedFileURL.path,
                includingHidden: showHiddenFiles,
                limit: limit,
                completions: []
            )
            return []
        }

        let directoryCompletions: [PathInputCompletion]
        if let directoryCache = pathInputDirectoryCompletionsCache,
           directoryCache.matches(directoryURL: request.directoryURL, includingHidden: showHiddenFiles) {
            directoryCompletions = directoryCache.completions
        } else {
            directoryCompletions = Self.pathInputDirectoryCompletions(
                in: request.directoryURL,
                includingHidden: showHiddenFiles
            )
            pathInputDirectoryCompletionsCache = PathInputDirectoryCompletionsCache(
                directoryPath: request.directoryURL.standardizedFileURL.path,
                includingHidden: showHiddenFiles,
                completions: directoryCompletions
            )
        }

        let normalizedPrefix = request.namePrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let completions = Array(directoryCompletions.lazy.filter { completion in
            normalizedPrefix.isEmpty
                || completion.name.localizedStandardContainsPrefix(normalizedPrefix)
                || completion.url.lastPathComponent.localizedStandardContainsPrefix(normalizedPrefix)
        }
        .prefix(limit))

        pathInputCompletionsCaches[cacheKey] = PathInputCompletionsCache(
            rawInput: rawInput,
            basePath: baseURL?.standardizedFileURL.path,
            includingHidden: showHiddenFiles,
            limit: limit,
            completions: completions
        )
        trimPathInputCompletionsCacheIfNeeded()
        return completions
    }

    private func trimPathInputCompletionsCacheIfNeeded(limit: Int = 160) {
        guard pathInputCompletionsCaches.count > limit else {
            return
        }

        pathInputCompletionsCaches.removeAll(keepingCapacity: true)
    }

    func openPathInputCompletion(_ completion: PathInputCompletion) {
        pathInput = completion.url.standardizedFileURL.path
        openPathInput()
    }

    private static var defaultAddressMenuLocations: [(name: String, url: URL)] {
        var locations: [(String, URL)] = [
            ("Home", FileManager.default.homeDirectoryForCurrentUser),
            ("This Mac", URL(fileURLWithPath: "/", isDirectory: true)),
            ("Trash", Self.trashDirectoryURL),
            ("Network", Self.networkDirectoryURL)
        ]

        let userDirectories: [(String, FileManager.SearchPathDirectory)] = [
            ("Desktop", .desktopDirectory),
            ("Documents", .documentDirectory),
            ("Downloads", .downloadsDirectory),
            ("Applications", .applicationDirectory)
        ]

        for (name, directory) in userDirectories {
            if let url = FileManager.default.urls(for: directory, in: .userDomainMask).first {
                locations.append((name, url))
            }
        }

        if let localApplicationsURL = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first {
            locations.append(("Mac Applications", localApplicationsURL))
        }

        return locations
    }

    static var trashDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash", isDirectory: true)
            .standardizedFileURL
    }

    private static var networkDirectoryURL: URL {
        URL(fileURLWithPath: "/Network", isDirectory: true)
            .standardizedFileURL
    }

    var currentVolumeStatusSummary: VolumeStatusSummary? {
        guard let currentURL else {
            return nil
        }

        let standardizedURL = currentURL.standardizedFileURL
        let cacheKey = Self.volumeCacheKey(for: standardizedURL)
        if let cachedSummary = volumeStatusSummaryCaches[cacheKey] {
            return cachedSummary
        }

        let keys: Set<URLResourceKey> = [
            .volumeURLKey,
            .volumeNameKey,
            .volumeAvailableCapacityKey,
            .volumeTotalCapacityKey
        ]

        guard let values = try? standardizedURL.resourceValues(forKeys: keys) else {
            return nil
        }

        let availableByteCount = values.volumeAvailableCapacity.map { Int64($0) }
        let totalByteCount = values.volumeTotalCapacity.map { Int64($0) }

        let summary = VolumeStatusSummary(
            name: values.volumeName,
            availableByteCount: availableByteCount,
            totalByteCount: totalByteCount
        )
        volumeStatusSummaryCaches[cacheKey] = summary
        return summary
    }

    private static func volumeCacheKey(for url: URL) -> String {
        let components = url.standardizedFileURL.pathComponents
        guard components.count >= 3,
              components[0] == "/",
              components[1] == "Volumes"
        else {
            return "/"
        }

        return "/Volumes/\(components[2])"
    }

    func childFolderComponents(for component: BrowserPathComponent, limit: Int = 80) -> [BrowserPathComponent] {
        let directoryURL = component.url.standardizedFileURL
        let cacheKey = directoryURL.path
        if let cache = childFolderComponentsCaches[cacheKey],
           cache.matches(includingHidden: showHiddenFiles, limit: limit) {
            return cache.components
        }

        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey, .isPackageKey, .localizedNameKey]

        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        let folders = urls.compactMap { url -> BrowserPathComponent? in
            let values = try? url.resourceValues(forKeys: resourceKeys)
            guard values?.isDirectory == true, values?.isPackage != true else {
                return nil
            }

            if !showHiddenFiles, values?.isHidden == true {
                return nil
            }

            return BrowserPathComponent(
                name: values?.localizedName ?? url.lastPathComponent,
                url: url.standardizedFileURL
            )
        }

        let components = folders
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .prefix(limit)
            .map { $0 }

        childFolderComponentsCaches[cacheKey] = ChildFolderComponentsCache(
            includingHidden: showHiddenFiles,
            limit: limit,
            components: components
        )
        return components
    }

    var selectionSummary: String {
        let count = selectedItems.count
        if count == 1, let selectedItem {
            return selectedItem.name
        }

        return "\(count) items selected"
    }

    var selectionStatusSummary: String? {
        let tab = selectedTab
        if let cachedSummary = selectionStatusSummaryCaches[tab.id],
           cachedSummary.matches(tab: tab, showFileExtensions: showFileExtensions) {
            return cachedSummary.summary
        }

        let aggregate = selectedItemsAggregate(for: tab)
        guard aggregate.itemCount > 0 else {
            selectionStatusSummaryCaches[tab.id] = SelectionStatusSummaryCache(
                itemsVersion: tab.itemsVersion,
                selectionVersion: tab.selectionVersion,
                showFileExtensions: showFileExtensions,
                summary: nil
            )
            return nil
        }

        let summary: String
        if aggregate.itemCount == 1, let item = aggregate.firstItem {
            summary = "\(displayName(for: item)) - \(item.detailSizeLabel)"
        } else {
            if aggregate.unknownFileCount > 0 {
                summary = "\(aggregate.itemCount) items selected - \(aggregate.sizeLabel) known"
            } else {
                summary = "\(aggregate.itemCount) items selected - \(aggregate.sizeLabel)"
            }
        }

        selectionStatusSummaryCaches[tab.id] = SelectionStatusSummaryCache(
            itemsVersion: tab.itemsVersion,
            selectionVersion: tab.selectionVersion,
            showFileExtensions: showFileExtensions,
            summary: summary
        )
        return summary
    }

    var inspectorSummary: FileInspectorSummary? {
        let tab = selectedTab
        if let cachedSummary = inspectorSummaryCaches[tab.id],
           cachedSummary.matches(tab: tab, showFileExtensions: showFileExtensions) {
            return cachedSummary.summary
        }

        let aggregate = selectedItemsAggregate(for: tab)
        guard aggregate.itemCount > 0 else {
            inspectorSummaryCaches[tab.id] = InspectorSummaryCache(
                itemsVersion: tab.itemsVersion,
                selectionVersion: tab.selectionVersion,
                showFileExtensions: showFileExtensions,
                currentURL: tab.currentURL,
                summary: nil
            )
            return nil
        }

        let summary: FileInspectorSummary
        if aggregate.itemCount == 1, let item = aggregate.firstItem {
            summary = .single(
                item: item,
                displayName: displayName(for: item),
                tagNames: Self.finderTagNames(for: item.url),
                metadataDetails: Self.metadataDetails(for: item.url),
                defaultApplication: Self.defaultApplication(for: item)
            )
        } else {
            summary = FileInspectorSummary(
                title: "\(aggregate.itemCount) items",
                subtitle: "Multiple selection",
                itemCount: aggregate.itemCount,
                folderCount: aggregate.folderCount,
                fileCount: aggregate.fileCount,
                packageCount: aggregate.packageCount,
                knownByteCount: aggregate.knownByteCount,
                sizeLabel: aggregate.sizeLabel,
                kindLabel: nil,
                modifiedLabel: nil,
                createdLabel: nil,
                accessedLabel: nil,
                hiddenLabel: nil,
                lockedLabel: nil,
                permissionsLabel: nil,
                ownerLabel: nil,
                groupLabel: nil,
                accessLabel: nil,
                accessControlLabel: nil,
                tagsLabel: nil,
                extendedAttributesLabel: nil,
                pathLabel: nil,
                parentPathLabel: currentURL?.path,
                defaultApplication: nil
            )
        }

        inspectorSummaryCaches[tab.id] = InspectorSummaryCache(
            itemsVersion: tab.itemsVersion,
            selectionVersion: tab.selectionVersion,
            showFileExtensions: showFileExtensions,
            currentURL: tab.currentURL,
            summary: summary
        )
        return summary
    }

    var canUndoFileOperation: Bool {
        !undoStack.isEmpty
    }

    var canRedoFileOperation: Bool {
        !redoStack.isEmpty
    }

    var canOpenSelectionInNewTabs: Bool {
        selectedItems.contains { Self.folderNavigationURL(for: $0) != nil }
    }

    var selectionFolderNavigationURLs: [URL] {
        selectedItems.compactMap(Self.folderNavigationURL(for:))
    }

    var selectionPackageContentURLs: [URL] {
        selectedItems.reduce(into: [URL]()) { urls, item in
            guard let packageURL = Self.packageContentsURL(for: item) else {
                return
            }

            if !urls.contains(packageURL) {
                urls.append(packageURL)
            }
        }
    }

    var canShowSelectionPackageContents: Bool {
        !selectionPackageContentURLs.isEmpty
    }

    var selectionFolderPinURLs: [URL] {
        selectedItems.reduce(into: [URL]()) { urls, item in
            guard let folderURL = Self.folderNavigationURL(for: item)?.standardizedFileURL else {
                return
            }

            if !urls.contains(folderURL) {
                urls.append(folderURL)
            }
        }
    }

    var canPinSelectionToSidebar: Bool {
        selectionFolderPinURLs.contains { !isPinnedDirectory($0) }
    }

    var canUnpinSelectionFromSidebar: Bool {
        selectionFolderPinURLs.contains { isPinnedDirectory($0) }
    }

    func isPinnedFolderTarget(_ item: FileItem) -> Bool {
        guard let folderURL = Self.folderNavigationURL(for: item) else {
            return false
        }

        return isPinnedDirectory(folderURL)
    }

    func canShowPackageContents(_ item: FileItem) -> Bool {
        Self.packageContentsURL(for: item) != nil
    }

    private var selectedFolderPermissionSeeds: [FolderPermissionSeed] {
        selectedItems.compactMap { item in
            guard item.canOpenAsFolder, let permissions = item.posixPermissions else {
                return nil
            }

            return FolderPermissionSeed(url: item.url.standardizedFileURL, permissions: permissions)
        }
    }

    var canApplySelectedFolderPermissionsToEnclosedItems: Bool {
        !selectedFolderPermissionSeeds.isEmpty
    }

    var selectionParentFolderURLs: [URL] {
        selectedItems.reduce(into: [URL]()) { urls, item in
            let parentURL = item.url.deletingLastPathComponent().standardizedFileURL
            if !urls.contains(parentURL) {
                urls.append(parentURL)
            }
        }
    }

    var canOpenSelectionParentFoldersInNewTabs: Bool {
        !selectionParentFolderURLs.isEmpty
    }

    var canOpenSelectionLocation: Bool {
        selectedItems.count == 1
    }

    var canExtractSelectedArchives: Bool {
        let selectedItems = selectedItems
        return !selectedItems.isEmpty && selectedItems.allSatisfy(Self.canExtractArchive)
    }

    var canOpenSelectionInTerminal: Bool {
        terminalTargetURLForSelection != nil
    }

    var terminalTargetURLForSelection: URL? {
        guard selectedItems.count == 1, let selectedItem else {
            return currentURL?.standardizedFileURL
        }

        return Self.terminalTargetURL(for: selectedItem)
    }

    var undoFileOperationTitle: String {
        undoStack.last?.undoTitle ?? "Undo"
    }

    var redoFileOperationTitle: String {
        redoStack.last?.redoTitle ?? "Redo"
    }

    func undoLastFileOperation() {
        guard let action = undoStack.popLast() else {
            return
        }

        do {
            selectedItemIDs = try Self.performUndo(action)
            redoStack.append(action)
            reload()
        } catch {
            undoStack.append(action)
            setSelectedError("Could not \(action.undoTitle.lowercased()): \(error.localizedDescription)")
        }
    }

    func redoLastFileOperation() {
        guard let action = redoStack.popLast() else {
            return
        }

        do {
            selectedItemIDs = try Self.performRedo(action)
            undoStack.append(action)
            reload()
        } catch {
            redoStack.append(action)
            setSelectedError("Could not \(action.redoTitle.lowercased()): \(error.localizedDescription)")
        }
    }

    func reload() {
        reload(tabID: selectedTabID)
    }

    func open(_ url: URL) {
        navigate(to: url, recordHistory: true)
    }

    func openHomeDirectory() {
        open(FileManager.default.homeDirectoryForCurrentUser)
    }

    func openComputerRoot() {
        open(URL(fileURLWithPath: "/", isDirectory: true))
    }

    func openNetworkRoot() {
        open(Self.networkDirectoryURL)
    }

    func openBreadcrumb(_ component: BrowserPathComponent) {
        open(component.url)
    }

    func openItem(_ item: FileItem) {
        if item.canOpenAsFolder {
            open(item.url)
        } else if item.kind == .file, let folderURL = Self.resolvedFolderURL(for: item.url) {
            open(folderURL)
        } else {
            selectedItemIDs = [item.id]
            recordRecentFile(item.url)
            NSWorkspace.shared.open(item.url)
        }
    }

    @discardableResult
    func showSelectedPackageContents() -> Bool {
        let urls = selectionPackageContentURLs
        guard !urls.isEmpty else {
            return false
        }

        if urls.count == 1, let packageURL = urls.first {
            open(packageURL)
        } else {
            for url in urls {
                addTab(opening: url)
            }
        }

        return true
    }

    @discardableResult
    func openSelectedItems() -> Bool {
        let items = selectedItems
        guard !items.isEmpty else {
            return false
        }

        if items.count == 1, let item = items.first {
            openItem(item)
            return true
        }

        let folderURLs = items.compactMap(Self.folderNavigationURL(for:))
        for folderURL in folderURLs {
            addTab(opening: folderURL)
        }

        let files = items.filter { item in
            Self.folderNavigationURL(for: item) == nil
        }
        for file in files {
            recordRecentFile(file.url)
            NSWorkspace.shared.open(file.url)
        }

        return true
    }

    func goBack() {
        guard let previousURL = selectedTab.backStack.last, let currentURL else {
            return
        }

        updateSelectedTab { tab in
            tab.backStack.removeLast()
            tab.forwardStack.append(currentURL)
        }

        navigate(to: previousURL, recordHistory: false)
    }

    func goBack(to targetURL: URL) {
        let standardizedURL = targetURL.standardizedFileURL
        guard let targetIndex = selectedTab.backStack.firstIndex(of: standardizedURL),
              let currentURL else {
            return
        }

        updateSelectedTab { tab in
            let skippedURLs = tab.backStack[(targetIndex + 1)...]
            tab.backStack = Array(tab.backStack[..<targetIndex])
            tab.forwardStack.append(currentURL)
            tab.forwardStack.append(contentsOf: skippedURLs.reversed())
        }

        navigate(to: standardizedURL, recordHistory: false)
    }

    func goBack(to location: NavigationHistoryLocation) {
        guard location.direction == .back,
              selectedTab.backStack.indices.contains(location.stackIndex),
              let currentURL else {
            return
        }

        let targetURL = selectedTab.backStack[location.stackIndex].standardizedFileURL
        updateSelectedTab { tab in
            let skippedURLs = tab.backStack[(location.stackIndex + 1)...]
            tab.backStack = Array(tab.backStack[..<location.stackIndex])
            tab.forwardStack.append(currentURL)
            tab.forwardStack.append(contentsOf: skippedURLs.reversed())
        }

        navigate(to: targetURL, recordHistory: false)
    }

    func goForward() {
        guard let nextURL = selectedTab.forwardStack.last, let currentURL else {
            return
        }

        updateSelectedTab { tab in
            tab.forwardStack.removeLast()
            tab.backStack.append(currentURL)
        }

        navigate(to: nextURL, recordHistory: false)
    }

    func goForward(to targetURL: URL) {
        let standardizedURL = targetURL.standardizedFileURL
        guard let targetIndex = selectedTab.forwardStack.firstIndex(of: standardizedURL),
              let currentURL else {
            return
        }

        updateSelectedTab { tab in
            let skippedURLs = tab.forwardStack[(targetIndex + 1)...]
            tab.forwardStack = Array(tab.forwardStack[..<targetIndex])
            tab.backStack.append(currentURL)
            tab.backStack.append(contentsOf: skippedURLs.reversed())
        }

        navigate(to: standardizedURL, recordHistory: false)
    }

    func goForward(to location: NavigationHistoryLocation) {
        guard location.direction == .forward,
              selectedTab.forwardStack.indices.contains(location.stackIndex),
              let currentURL else {
            return
        }

        let targetURL = selectedTab.forwardStack[location.stackIndex].standardizedFileURL
        updateSelectedTab { tab in
            let skippedURLs = tab.forwardStack[(location.stackIndex + 1)...]
            tab.forwardStack = Array(tab.forwardStack[..<location.stackIndex])
            tab.backStack.append(currentURL)
            tab.backStack.append(contentsOf: skippedURLs.reversed())
        }

        navigate(to: targetURL, recordHistory: false)
    }

    @discardableResult
    func createFolder(in directory: URL? = nil) -> Bool {
        guard let directoryURL = (directory ?? currentURL)?.standardizedFileURL else {
            return false
        }

        let start = ContinuousClock.now
        do {
            let folderURL = uniqueFolderURL(in: directoryURL)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
            recordUndo(.createFolder(folderURL))
            recordPerformanceEvent(
                label: "Created Folder",
                itemCount: 1,
                elapsedSeconds: Self.elapsedSeconds(since: start),
                path: directoryURL.path
            )

            if currentURL?.standardizedFileURL.path == directoryURL.path {
                reload()
                selectedItemIDs = [folderURL.standardizedFileURL.path]
            }

            return true
        } catch {
            recordPerformanceEvent(
                label: "Failed Create Folder",
                itemCount: 1,
                elapsedSeconds: Self.elapsedSeconds(since: start),
                path: directoryURL.path
            )
            setSelectedError("Could not create folder in \(directoryURL.path): \(error.localizedDescription)")
            return false
        }
    }

    func createFile(in directory: URL? = nil) {
        let alert = NSAlert()
        alert.messageText = "New File"
        alert.informativeText = "Enter a name for the new file."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(string: "New File.txt")
        textField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        createFile(named: textField.stringValue, in: directory)
    }

    @discardableResult
    func createFile(named requestedName: String, in directory: URL? = nil) -> Bool {
        guard let directoryURL = (directory ?? currentURL)?.standardizedFileURL else {
            return false
        }

        let trimmedName = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return false
        }

        let start = ContinuousClock.now
        do {
            let fileURL = uniqueFileURL(in: directoryURL, requestedName: trimmedName)
            try Data().write(to: fileURL, options: .withoutOverwriting)
            recordUndo(.createFile(fileURL))
            recordPerformanceEvent(
                label: "Created File",
                itemCount: 1,
                elapsedSeconds: Self.elapsedSeconds(since: start),
                path: directoryURL.path
            )

            if currentURL?.standardizedFileURL.path == directoryURL.path {
                reload()
                selectedItemIDs = [fileURL.standardizedFileURL.path]
            }

            return true
        } catch {
            recordPerformanceEvent(
                label: "Failed Create File",
                itemCount: 1,
                elapsedSeconds: Self.elapsedSeconds(since: start),
                path: directoryURL.path
            )
            setSelectedError("Could not create file in \(directoryURL.path): \(error.localizedDescription)")
            return false
        }
    }

    func renameSelectedItem() {
        guard !beginInlineRenameSelectedItem() else {
            return
        }

        guard let selectedItem else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.informativeText = "Enter a new name for \(selectedItem.name)."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(string: selectedItem.name)
        textField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let trimmedName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName != selectedItem.name else {
            return
        }

        renameSelectedItem(to: trimmedName)
    }

    func renameLocation(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        if selectVisibleLocation(standardizedURL), beginInlineRenameSelectedItem() {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.informativeText = "Enter a new name for \(displayName(for: standardizedURL))."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(string: standardizedURL.lastPathComponent)
        textField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let trimmedName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName != standardizedURL.lastPathComponent else {
            return
        }

        _ = renameLocation(standardizedURL, to: trimmedName)
    }

    @discardableResult
    func renameSelectedItem(to requestedName: String) -> Bool {
        guard let selectedItem else {
            return false
        }

        let trimmedName = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName != selectedItem.name else {
            return false
        }

        let destinationURL = selectedItem.url.deletingLastPathComponent().appendingPathComponent(trimmedName)
        let start = ContinuousClock.now
        do {
            try FileManager.default.moveItem(at: selectedItem.url, to: destinationURL)
            recordPerformanceEvent(
                label: "Renamed",
                itemCount: 1,
                elapsedSeconds: Self.elapsedSeconds(since: start),
                path: selectedItem.url.deletingLastPathComponent().standardizedFileURL.path
            )
            recordUndo(.rename([(from: selectedItem.url, to: destinationURL)]))
            reload()
            selectedItemIDs = [destinationURL.standardizedFileURL.path]
            return true
        } catch {
            recordPerformanceEvent(
                label: "Failed Rename",
                itemCount: 1,
                elapsedSeconds: Self.elapsedSeconds(since: start),
                path: selectedItem.url.deletingLastPathComponent().standardizedFileURL.path
            )
            setSelectedError("Could not rename \(selectedItem.name): \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func renameLocation(_ url: URL, to requestedName: String) -> Bool {
        let standardizedURL = url.standardizedFileURL
        let trimmedName = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName != standardizedURL.lastPathComponent else {
            return false
        }

        let destinationURL = standardizedURL.deletingLastPathComponent().appendingPathComponent(
            trimmedName,
            isDirectory: isDirectory(standardizedURL)
        )
        let start = ContinuousClock.now
        do {
            try FileManager.default.moveItem(at: standardizedURL, to: destinationURL)
            recordUndo(.rename([(from: standardizedURL, to: destinationURL)]))
            recordPerformanceEvent(
                label: "Renamed",
                itemCount: 1,
                elapsedSeconds: Self.elapsedSeconds(since: start),
                path: standardizedURL.deletingLastPathComponent().path
            )
            replaceTrackedDirectory(standardizedURL, with: destinationURL.standardizedFileURL)
            if currentURL?.standardizedFileURL.path == standardizedURL.path {
                navigate(to: destinationURL.standardizedFileURL, recordHistory: false)
            } else if currentURL?.standardizedFileURL.path == standardizedURL.deletingLastPathComponent().path {
                reload()
                selectedItemIDs = [destinationURL.standardizedFileURL.path]
            }
            return true
        } catch {
            recordPerformanceEvent(
                label: "Failed Rename",
                itemCount: 1,
                elapsedSeconds: Self.elapsedSeconds(since: start),
                path: standardizedURL.deletingLastPathComponent().path
            )
            setSelectedError("Could not rename \(standardizedURL.path): \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func beginInlineRenameSelectedItem() -> Bool {
        guard selectedItems.count == 1, let selectedItem else {
            return false
        }

        inlineRenameItemID = selectedItem.id
        inlineRenameDraft = selectedItem.name
        selectedItemIDs = [selectedItem.id]
        return true
    }

    func cancelInlineRename() {
        inlineRenameItemID = nil
        inlineRenameDraft = ""
    }

    @discardableResult
    func commitInlineRename() -> Bool {
        guard let inlineRenameItemID else {
            return false
        }

        guard selectedItemIDs.contains(inlineRenameItemID) else {
            cancelInlineRename()
            return false
        }

        let requestedName = inlineRenameDraft
        cancelInlineRename()

        return renameSelectedItem(to: requestedName)
    }

    func batchRenameSelection() {
        let selectedItems = selectedItems
        guard selectedItems.count > 1 else {
            beginInlineRenameSelectedItem()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Batch Rename"
        alert.informativeText = "Enter a base name for \(selectedItems.count) items."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(string: "File")
        textField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let baseName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseName.isEmpty else {
            return
        }

        batchRenameSelectedItems(baseName: baseName)
    }

    @discardableResult
    func batchRenameSelectedItems(baseName: String) -> Bool {
        let selectedItems = selectedItems
        guard selectedItems.count > 1 else {
            return false
        }

        let cleanBaseName = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanBaseName.isEmpty else {
            return false
        }

        let start = ContinuousClock.now
        let directoryURL = selectedItems[0].url.deletingLastPathComponent().standardizedFileURL
        do {
            var renamedIDs: Set<FileItem.ID> = []
            var renameMoves: [(from: URL, to: URL)] = []

            for (index, item) in selectedItems.enumerated() {
                let destinationURL = uniqueBatchRenameURL(
                    for: item.url,
                    baseName: cleanBaseName,
                    index: index + 1
                )
                try FileManager.default.moveItem(at: item.url, to: destinationURL)
                renamedIDs.insert(destinationURL.standardizedFileURL.path)
                renameMoves.append((from: item.url, to: destinationURL))
            }

            recordUndo(.rename(renameMoves))
            recordPerformanceEvent(
                label: "Batch Renamed",
                itemCount: renameMoves.count,
                elapsedSeconds: Self.elapsedSeconds(since: start),
                path: directoryURL.path
            )
            reload()
            selectedItemIDs = renamedIDs
            return true
        } catch {
            recordPerformanceEvent(
                label: "Failed Batch Rename",
                itemCount: selectedItems.count,
                elapsedSeconds: Self.elapsedSeconds(since: start),
                path: directoryURL.path
            )
            setSelectedError("Could not batch rename selection: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func moveSelectedItemToTrash() -> Bool {
        let selectedItems = selectedItems
        guard !selectedItems.isEmpty else {
            return false
        }

        let tabID = selectedTabID
        startFileOperation(label: "Moved to Trash", itemCount: selectedItems.count, tabID: tabID) { context in
            try Self.performTrashItems(selectedItems.map(\.url), context: context)
        } onSuccess: { [weak self] _ in
            self?.updateTab(tabID) { tab in
                tab.selectedItemIDs = []
            }
        }

        return true
    }

    @discardableResult
    func moveLocationToTrash(_ url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        guard canTrashLocation(standardizedURL) else {
            return false
        }

        let tabID = selectedTabID
        startFileOperation(label: "Moved to Trash", itemCount: 1, tabID: tabID) { context in
            try Self.performTrashItems([standardizedURL], context: context)
        } onSuccess: { [weak self] _ in
            guard let self else { return }
            self.removeTrackedDirectory(standardizedURL)
            if self.currentURL?.standardizedFileURL.path == standardizedURL.path {
                self.navigate(to: standardizedURL.deletingLastPathComponent().standardizedFileURL, recordHistory: false)
            } else if self.currentURL?.standardizedFileURL.path == standardizedURL.deletingLastPathComponent().path {
                self.reload()
            }
        }

        return true
    }

    func showProperties(for url: URL) {
        if selectVisibleLocation(url.standardizedFileURL) {
            showPropertiesForSelection()
        } else {
            revealInFinder(url)
        }
    }

    func confirmEmptyTrash() {
        guard canEmptyTrash else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Empty Trash?"
        alert.informativeText = "This permanently deletes every item in Trash."
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        emptyTrash()
    }

    @discardableResult
    func emptyTrash() -> Bool {
        emptyTrash(at: Self.trashDirectoryURL)
    }

    @discardableResult
    func emptyTrash(at trashDirectory: URL) -> Bool {
        let trashDirectory = trashDirectory.standardizedFileURL
        guard let trashItemURLs = Self.trashItemURLs(in: trashDirectory), !trashItemURLs.isEmpty else {
            return false
        }

        let tabID = selectedTabID
        startFileOperation(label: "Emptied Trash", itemCount: trashItemURLs.count, tabID: tabID) { context in
            try Self.performDeleteItems(trashItemURLs, context: context)
        } onSuccess: { [weak self] _ in
            guard let self else {
                return
            }

            self.updateTab(tabID) { tab in
                if tab.currentURL?.standardizedFileURL.path == trashDirectory.path {
                    tab.selectedItemIDs = []
                }
            }
        }

        return true
    }

    func confirmDeleteSelectedItemsPermanently() {
        let selectedItems = selectedItems
        guard !selectedItems.isEmpty else {
            return
        }

        let itemLabel = selectedItems.count == 1 ? selectedItems[0].name : "\(selectedItems.count) items"
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Delete \(itemLabel) permanently?"
        alert.informativeText = "This removes the selection immediately without moving it to Trash."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        deleteSelectedItemsPermanently()
    }

    @discardableResult
    func deleteSelectedItemsPermanently() -> Bool {
        let selectedItems = selectedItems
        guard !selectedItems.isEmpty else {
            return false
        }

        let tabID = selectedTabID
        startFileOperation(label: "Deleted", itemCount: selectedItems.count, tabID: tabID) { context in
            try Self.performDeleteItems(selectedItems.map(\.url), context: context)
        } onSuccess: { [weak self] _ in
            self?.updateTab(tabID) { tab in
                tab.selectedItemIDs = []
            }
        }

        return true
    }

    @discardableResult
    func setSelectedItemsHidden(_ hidden: Bool) -> Bool {
        let selectedItems = selectedItems
        guard !selectedItems.isEmpty else {
            return false
        }

        let tabID = selectedTabID
        let label = hidden ? "Hidden" : "Unhidden"
        startFileOperation(label: label, itemCount: selectedItems.count, tabID: tabID) { context in
            try Self.performSetHidden(selectedItems.map(\.url), hidden: hidden, context: context)
        } onSuccess: { [weak self] result in
            guard !result.selectedItemIDs.isEmpty else {
                return
            }

            self?.updateTab(tabID) { tab in
                tab.selectedItemIDs = result.selectedItemIDs
            }
        }

        return true
    }

    @discardableResult
    func setSelectedItemsWritable(_ writable: Bool) -> Bool {
        if writable {
            return setSelectedItemsPermissionBits(.ownerWrite, enabled: true, label: "Made Writable")
        }

        return setSelectedItemsPermissionBits([.ownerWrite, .groupWrite, .everyoneWrite], enabled: false, label: "Made Read-Only")
    }

    @discardableResult
    func setSelectedItemsLocked(_ locked: Bool) -> Bool {
        let selectedItems = selectedItems
        guard !selectedItems.isEmpty else {
            return false
        }

        let tabID = selectedTabID
        let label = locked ? "Locked" : "Unlocked"
        startFileOperation(label: label, itemCount: selectedItems.count, tabID: tabID) { context in
            try Self.performSetLocked(selectedItems.map(\.url), locked: locked, context: context)
        } onSuccess: { [weak self] result in
            guard !result.selectedItemIDs.isEmpty else {
                return
            }

            self?.updateTab(tabID) { tab in
                tab.selectedItemIDs = result.selectedItemIDs
            }
        }

        return true
    }

    @discardableResult
    func clearSelectedItemsAccessControl() -> Bool {
        let selectedItems = selectedItems
        guard !selectedItems.isEmpty else {
            return false
        }

        let tabID = selectedTabID
        startFileOperation(label: "Cleared Access Control", itemCount: selectedItems.count, tabID: tabID) { context in
            try Self.performClearAccessControl(selectedItems.map(\.url), context: context)
        } onSuccess: { [weak self] result in
            guard !result.selectedItemIDs.isEmpty else {
                return
            }

            self?.updateTab(tabID) { tab in
                tab.selectedItemIDs = result.selectedItemIDs
            }
        }

        return true
    }

    func promptSetTagsForSelection() {
        let selectedItems = selectedItems
        guard !selectedItems.isEmpty else {
            return
        }

        let alert = NSAlert()
        alert.messageText = selectedItems.count == 1 ? "Set Finder Tags" : "Set Finder Tags for \(selectedItems.count) Items"
        alert.informativeText = "Enter tag names separated by commas. Leave empty to clear tags."
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")

        let existingTags = selectedItems.count == 1 ? Self.finderTagNames(for: selectedItems[0].url).joined(separator: ", ") : ""
        let textField = NSTextField(string: existingTags)
        textField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        textField.placeholderString = "Client, Review, Personal"
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        setSelectedItemsFinderTags(Self.normalizedFinderTags(from: textField.stringValue))
    }

    @discardableResult
    func setSelectedItemsFinderTags(_ tagNames: [String]) -> Bool {
        let selectedItems = selectedItems
        guard !selectedItems.isEmpty else {
            return false
        }

        let normalizedTags = Self.normalizedFinderTags(tagNames)
        let tabID = selectedTabID
        let label = normalizedTags.isEmpty ? "Cleared Tags" : "Tagged"
        startFileOperation(label: label, itemCount: selectedItems.count, tabID: tabID) { context in
            try Self.performSetFinderTags(selectedItems.map(\.url), tagNames: normalizedTags, context: context)
        } onSuccess: { [weak self] result in
            guard !result.selectedItemIDs.isEmpty else {
                return
            }

            self?.updateTab(tabID) { tab in
                tab.selectedItemIDs = result.selectedItemIDs
            }
        }

        return true
    }

    @discardableResult
    func setSelectedItemsPOSIXPermissions(_ permissions: UInt16) -> Bool {
        setSelectedItemsPOSIXPermissions(permissions, label: "Changed Permissions")
    }

    @discardableResult
    func applySelectedFolderPermissionsToEnclosedItems() -> Bool {
        let permissionSeeds = selectedFolderPermissionSeeds
        guard !permissionSeeds.isEmpty else {
            return false
        }

        let tabID = selectedTabID
        startFileOperation(label: "Applied Enclosed Permissions", itemCount: permissionSeeds.count, tabID: tabID) { context in
            try Self.performApplyFolderPermissionsToEnclosedItems(permissionSeeds, context: context)
        } onSuccess: { [weak self] result in
            guard !result.selectedItemIDs.isEmpty else {
                return
            }

            self?.updateTab(tabID) { tab in
                tab.selectedItemIDs = result.selectedItemIDs
            }
        }

        return true
    }

    @discardableResult
    func setSelectedItemsPermissionBits(_ bits: FilePermissionBits, enabled: Bool) -> Bool {
        let label = enabled ? "Added Permissions" : "Removed Permissions"
        return setSelectedItemsPermissionBits(bits, enabled: enabled, label: label)
    }

    @discardableResult
    private func setSelectedItemsPOSIXPermissions(_ permissions: UInt16, label: String) -> Bool {
        let selectedItems = selectedItems
        guard !selectedItems.isEmpty else {
            return false
        }

        let tabID = selectedTabID
        startFileOperation(label: label, itemCount: selectedItems.count, tabID: tabID) { context in
            try Self.performSetPOSIXPermissions(selectedItems.map(\.url), permissions: permissions, context: context)
        } onSuccess: { [weak self] result in
            guard !result.selectedItemIDs.isEmpty else {
                return
            }

            self?.updateTab(tabID) { tab in
                tab.selectedItemIDs = result.selectedItemIDs
            }
        }

        return true
    }

    @discardableResult
    private func setSelectedItemsPermissionBits(_ bits: FilePermissionBits, enabled: Bool, label: String) -> Bool {
        let selectedItems = selectedItems
        guard !selectedItems.isEmpty else {
            return false
        }

        let tabID = selectedTabID
        startFileOperation(label: label, itemCount: selectedItems.count, tabID: tabID) { context in
            try Self.performSetPermissionBits(selectedItems.map(\.url), bits: bits, enabled: enabled, context: context)
        } onSuccess: { [weak self] result in
            guard !result.selectedItemIDs.isEmpty else {
                return
            }

            self?.updateTab(tabID) { tab in
                tab.selectedItemIDs = result.selectedItemIDs
            }
        }

        return true
    }

    func revealSelectedInFinder() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url.standardizedFileURL])
    }

    @discardableResult
    func openCurrentFolderInTerminal() -> Bool {
        guard let currentURL else {
            return false
        }

        return openInTerminal(at: currentURL)
    }

    @discardableResult
    func openFolderInTerminal(_ url: URL) -> Bool {
        openInTerminal(at: url)
    }

    @discardableResult
    func openSelectionInTerminal() -> Bool {
        guard let terminalTargetURLForSelection else {
            return false
        }

        return openInTerminal(at: terminalTargetURLForSelection)
    }

    func quickLookSelectedItems() {
        let paths = selectedItems.map(\.url.path)
        guard !paths.isEmpty else {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = ["-p"] + paths

        do {
            try process.run()
        } catch {
            setSelectedError("Could not preview selection: \(error.localizedDescription)")
        }
    }

    func chooseApplicationForSelection() {
        guard hasSelection else {
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Open With"
        panel.prompt = "Open"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        guard panel.runModal() == .OK, let applicationURL = panel.url else {
            return
        }

        openSelectedItems(withApplicationAt: applicationURL)
    }

    func openWithApplicationsForSelection(limit: Int = 10) -> [OpenWithApplication] {
        openWithApplications(for: selectedItems, limit: limit)
    }

    func openWithApplications(forContextItemID itemID: FileItem.ID, limit: Int = 10) -> [OpenWithApplication] {
        let contextIDs = contextSelectionIDs(for: itemID)
        let items = selectedTab.items.filter { contextIDs.contains($0.id) }
        return openWithApplications(for: items, limit: limit)
    }

    @discardableResult
    func openSelectedItems(withApplicationAt applicationURL: URL) -> Bool {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else {
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.open(
            urls,
            withApplicationAt: applicationURL,
            configuration: configuration
        ) { [weak self] _, error in
            guard let error else {
                return
            }

            Task { @MainActor [weak self] in
                self?.setSelectedError(
                    "Could not open selection with \(applicationURL.deletingPathExtension().lastPathComponent): \(error.localizedDescription)"
                )
            }
        }

        return true
    }

    private func openWithApplications(for items: [FileItem], limit: Int) -> [OpenWithApplication] {
        guard !items.isEmpty, limit > 0 else {
            return []
        }

        let urls = items.map { $0.url.standardizedFileURL }
        let cacheKey = Self.openWithApplicationsCacheKey(for: urls)
        if let cachedApplications = openWithApplicationsCache[cacheKey] {
            return Array(cachedApplications.prefix(limit))
        }

        let applications = Self.resolveOpenWithApplications(for: urls)
        if openWithApplicationsCache.count > 40 {
            openWithApplicationsCache.removeAll(keepingCapacity: true)
        }
        openWithApplicationsCache[cacheKey] = applications

        return Array(applications.prefix(limit))
    }

    func openSelectionInNewTabs() {
        let folderURLs = selectionFolderNavigationURLs
        guard !folderURLs.isEmpty else {
            return
        }

        for folderURL in folderURLs {
            addTab(opening: folderURL)
        }
    }

    func openSelectionParentFoldersInNewTabs() {
        let parentFolderURLs = selectionParentFolderURLs
        guard !parentFolderURLs.isEmpty else {
            return
        }

        for parentFolderURL in parentFolderURLs {
            addTab(opening: parentFolderURL)
        }
    }

    func openSelectionLocation() {
        guard let item = selectedItems.first, selectedItems.count == 1 else {
            return
        }

        let itemURL = item.url.standardizedFileURL
        let parentURL = itemURL.deletingLastPathComponent().standardizedFileURL
        navigate(to: parentURL, recordHistory: true)
        selectedItemIDs = [itemURL.path]
    }

    func canOpenInNewTab(_ item: FileItem) -> Bool {
        Self.folderNavigationURL(for: item) != nil
    }

    func copySelectedPaths() {
        let paths = selectedItems.map(\.url.path)
        guard !paths.isEmpty else {
            return
        }

        copyPaths(paths)
    }

    func copySelectedPathsAsQuotedPaths() {
        let paths = selectedItems.map { Self.quotedPath($0.url.standardizedFileURL.path) }
        guard !paths.isEmpty else {
            return
        }

        copyPaths(paths)
    }

    func copySelectedNames() {
        let names = selectedItems.map(\.name)
        guard !names.isEmpty else {
            return
        }

        copyPaths(names)
    }

    func copySelectedParentFolderPaths() {
        let parentPaths = selectedItems.reduce(into: [String]()) { paths, item in
            let parentPath = item.url.deletingLastPathComponent().standardizedFileURL.path
            if !paths.contains(parentPath) {
                paths.append(parentPath)
            }
        }

        guard !parentPaths.isEmpty else {
            return
        }

        copyPaths(parentPaths)
    }

    func copyPerformanceReport() {
        copyText(performanceReport)
    }

    func copyPath(of url: URL) {
        copyPaths([url.standardizedFileURL.path])
    }

    func copyPathAsQuotedPath(of url: URL) {
        copyPaths([Self.quotedPath(url.standardizedFileURL.path)])
    }

    private func copyPaths(_ paths: [String]) {
        guard !paths.isEmpty else {
            return
        }

        copyText(paths.joined(separator: "\n"))
    }

    private nonisolated static func quotedPath(_ path: String) -> String {
        "\"\(path.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private func copyText(_ text: String) {
        guard !text.isEmpty else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func shareSelectedItems() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else {
            return
        }

        guard let contentView = NSApp.keyWindow?.contentView else {
            NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
            return
        }

        let picker = NSSharingServicePicker(items: urls)
        picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
    }

    func selectAllVisibleItems() {
        selectedItemIDs = Set(visibleItems.map(\.id))
    }

    func setItemSelection(_ itemID: FileItem.ID, isSelected: Bool) {
        var ids = selectedItemIDs
        if isSelected {
            ids.insert(itemID)
        } else {
            ids.remove(itemID)
        }
        selectedItemIDs = ids
    }

    func contextSelectionIDs(for itemID: FileItem.ID) -> Set<FileItem.ID> {
        selectedItemIDs.contains(itemID) ? selectedItemIDs : [itemID]
    }

    func prepareContextSelection(for itemID: FileItem.ID) {
        selectedItemIDs = contextSelectionIDs(for: itemID)
    }

    func clearSelection() {
        selectedItemIDs = []
    }

    func invertSelection() {
        let visibleIDs = Set(visibleItems.map(\.id))
        selectedItemIDs = visibleIDs.subtracting(selectedItemIDs)
    }

    func clearRecentDirectories() {
        recentDirectories = []
        userDefaults.removeObject(forKey: PreferenceKey.recentDirectoryPaths)
    }

    func clearRecentFiles() {
        recentFiles = []
        userDefaults.removeObject(forKey: PreferenceKey.recentFilePaths)
    }

    func removeRecentFile(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        recentFiles.removeAll { $0.standardizedFileURL.path == standardizedURL.path }
        persistRecentFiles()
    }

    func clearTypedPathHistory() {
        typedPathHistory = []
        addressMenuLocationsCache = nil
        userDefaults.removeObject(forKey: PreferenceKey.typedPathHistoryPaths)
    }

    func recordRecentFile(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardizedURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            return
        }

        recentFiles.removeAll { $0.standardizedFileURL.path == standardizedURL.path }
        recentFiles.insert(standardizedURL, at: 0)
        if recentFiles.count > 12 {
            recentFiles.removeLast(recentFiles.count - 12)
        }

        persistRecentFiles()
    }

    func openRecentFile(_ url: URL) {
        recordRecentFile(url)
        NSWorkspace.shared.open(url.standardizedFileURL)
    }

    func openRecentFileLocation(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardizedURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            removeRecentFile(standardizedURL)
            setSelectedError("Recent file is no longer available: \(standardizedURL.path)")
            return
        }

        let parentURL = standardizedURL.deletingLastPathComponent().standardizedFileURL
        navigate(to: parentURL, recordHistory: true)
        selectedItemIDs = [standardizedURL.path]
        recordRecentFile(standardizedURL)
    }

    func pinCurrentDirectory() {
        guard let currentURL else {
            return
        }

        pinDirectory(currentURL)
    }

    func pinDirectory(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        guard isDirectory(standardizedURL) else {
            return
        }

        pinnedDirectories.removeAll { $0.standardizedFileURL.path == standardizedURL.path }
        pinnedDirectories.insert(standardizedURL, at: 0)
        if pinnedDirectories.count > 8 {
            pinnedDirectories.removeLast(pinnedDirectories.count - 8)
        }

        recentDirectories.removeAll { $0.standardizedFileURL.path == standardizedURL.path }
        persistPinnedDirectories()
        persistRecentDirectories()
    }

    @discardableResult
    func pinSelectedFoldersToSidebar() -> Bool {
        let urls = selectionFolderPinURLs
        guard !urls.isEmpty else {
            return false
        }

        for url in urls.reversed() where !isPinnedDirectory(url) {
            pinDirectory(url)
        }

        return true
    }

    func unpinDirectory(_ url: URL) {
        let standardizedPath = url.standardizedFileURL.path
        pinnedDirectories.removeAll { $0.standardizedFileURL.path == standardizedPath }
        persistPinnedDirectories()
    }

    @discardableResult
    func unpinSelectedFoldersFromSidebar() -> Bool {
        let urls = selectionFolderPinURLs.filter { isPinnedDirectory($0) }
        guard !urls.isEmpty else {
            return false
        }

        for url in urls {
            unpinDirectory(url)
        }

        return true
    }

    func isPinnedDirectory(_ url: URL?) -> Bool {
        guard let path = url?.standardizedFileURL.path else {
            return false
        }

        return pinnedDirectories.contains { $0.standardizedFileURL.path == path }
    }

    func setSidebarExpandedPath(_ path: String, isExpanded: Bool) {
        let standardizedPath = URL(
            fileURLWithPath: (path as NSString).expandingTildeInPath,
            isDirectory: true
        )
        .standardizedFileURL
        .path

        var paths = sidebarExpandedPaths.filter { $0 != standardizedPath }
        if isExpanded {
            paths.insert(standardizedPath, at: 0)
        }

        let normalizedPaths = Self.normalizedSidebarExpandedPaths(paths)
        guard normalizedPaths != sidebarExpandedPaths else {
            return
        }

        sidebarExpandedPaths = normalizedPaths
        setPreference(sidebarExpandedPaths, forKey: PreferenceKey.sidebarExpandedPaths)
    }

    func setSortField(_ field: FileSortField) {
        if sortField == field {
            sortAscending.toggle()
        } else {
            sortField = field
            sortAscending = true
        }
    }

    func focusAddressBar() {
        pathInput = currentURL?.path ?? pathInput
        focusRequest = BrowserFocusRequest(target: .addressBar)
    }

    func focusSearchField() {
        focusRequest = BrowserFocusRequest(target: .searchField)
    }

    func clearSearchAndContentFilters() {
        query = ""
        searchesSubfolders = false
        kindFilter = .all
        typeFilter = .any
        dateFilter = .any
        sizeFilter = .any
    }

    func showAllDetailsColumns() {
        showsKindColumn = true
        showsSizeColumn = true
        showsModifiedColumn = true
        showsCreatedColumn = true
        showsAccessedColumn = true
        showsPermissionsColumn = true
    }

    func saveCurrentFolderViewSettings() {
        guard let currentURL else {
            return
        }

        folderViewSettingsByPath[Self.folderViewSettingsKey(for: currentURL)] = FolderViewSettings(store: self)
        persistFolderViewSettings()
    }

    func clearCurrentFolderViewSettings() {
        guard let currentURL else {
            return
        }

        folderViewSettingsByPath.removeValue(forKey: Self.folderViewSettingsKey(for: currentURL))
        persistFolderViewSettings()
    }

    func copySelectedItems() {
        setClipboard(mode: .copy)
    }

    func cutSelectedItems() {
        setClipboard(mode: .cut)
    }

    func pasteItems(to destinationDirectory: URL? = nil) {
        let payload = clipboardPayload ?? FileClipboardPayload(mode: .copy, urls: pasteboardFileURLs())
        if let destinationDirectory {
            importItems(payload.urls, to: destinationDirectory, operation: FileTransferOperation(payload.mode))
        } else {
            importItems(payload.urls, operation: FileTransferOperation(payload.mode))
        }
    }

    @discardableResult
    func importItems(_ urls: [URL], operation: FileTransferOperation = .copy) -> Bool {
        guard let currentURL else {
            return false
        }

        return importItems(urls, to: currentURL, operation: operation)
    }

    @discardableResult
    func importItems(
        _ urls: [URL],
        to destinationDirectory: URL,
        operation: FileTransferOperation = .copy
    ) -> Bool {
        guard !urls.isEmpty else {
            return false
        }

        let destinationDirectory = destinationDirectory.standardizedFileURL
        let label = operation == .copy ? "Copied" : "Moved"
        let tabID = selectedTabID
        let currentDirectory = currentURL?.standardizedFileURL
        let clearsClipboard = clipboardPayload?.mode == .cut && operation == .move

        startFileOperation(label: label, itemCount: urls.count, tabID: tabID) { context in
            try Self.performImportItems(urls, to: destinationDirectory, operation: operation, context: context)
        } onSuccess: { [weak self] result in
            if clearsClipboard {
                self?.clipboardPayload = nil
            }

            guard destinationDirectory == currentDirectory, !result.selectedItemIDs.isEmpty else {
                return
            }

            self?.updateTab(tabID) { tab in
                tab.selectedItemIDs = result.selectedItemIDs
            }
        }

        return true
    }

    func defaultDropOperation(for urls: [URL], to destinationDirectory: URL? = nil) -> FileTransferOperation {
        guard let currentURL else {
            return .copy
        }

        let currentDirectory = currentURL.standardizedFileURL
        let destinationDirectory = (destinationDirectory ?? currentURL).standardizedFileURL
        guard destinationDirectory != currentDirectory else {
            return .copy
        }

        return urls.allSatisfy { url in
            url.deletingLastPathComponent().standardizedFileURL == currentDirectory
        } ? .move : .copy
    }

    @discardableResult
    func dropItems(_ urls: [URL], to destinationDirectory: URL? = nil) -> Bool {
        let destinationDirectory = destinationDirectory ?? currentURL
        guard let destinationDirectory else {
            return false
        }

        let urls = expandedDropURLs(from: urls)
        return importItems(
            urls,
            to: destinationDirectory,
            operation: defaultDropOperation(for: urls, to: destinationDirectory)
        )
    }

    func expandedDropURLs(from urls: [URL]) -> [URL] {
        let droppedPaths = Set(urls.map(\.standardizedFileURL.path))
        guard !droppedPaths.isEmpty else {
            return []
        }

        let selectedItems = selectedItems
        let selectedPaths = Set(selectedItems.map(\.url.standardizedFileURL.path))
        guard !selectedPaths.isEmpty, droppedPaths.isSubset(of: selectedPaths) else {
            return urls
        }

        return selectedItems.map(\.url)
    }

    func duplicateSelectedItems() {
        let selectedItems = selectedItems
        guard !selectedItems.isEmpty else {
            return
        }

        let tabID = selectedTabID
        startFileOperation(label: "Duplicated", itemCount: selectedItems.count, tabID: tabID) { context in
            try Self.performDuplicateItems(selectedItems.map(\.url), context: context)
        } onSuccess: { [weak self] result in
            if !result.selectedItemIDs.isEmpty {
                self?.updateTab(tabID) { tab in
                    tab.selectedItemIDs = result.selectedItemIDs
                }
            }
        }
    }

    func createAliasesForSelection() {
        let selectedItems = selectedItems
        guard !selectedItems.isEmpty else {
            return
        }

        let tabID = selectedTabID
        startFileOperation(label: "Created Alias", itemCount: selectedItems.count, tabID: tabID) { context in
            try Self.performCreateAliases(selectedItems.map(\.url), context: context)
        } onSuccess: { [weak self] result in
            if !result.selectedItemIDs.isEmpty {
                self?.updateTab(tabID) { tab in
                    tab.selectedItemIDs = result.selectedItemIDs
                }
            }
        }
    }

    func copySelectedItemsToFolder() {
        chooseTransferDestination(operation: .copy)
    }

    func moveSelectedItemsToFolder() {
        chooseTransferDestination(operation: .move)
    }

    @discardableResult
    func transferSelectedItems(to destinationDirectory: URL, operation: FileTransferOperation) -> Bool {
        let selectedItems = selectedItems
        guard !selectedItems.isEmpty else {
            return false
        }

        let destinationDirectory = destinationDirectory.standardizedFileURL
        let tabID = selectedTabID
        let currentDirectory = currentURL?.standardizedFileURL
        let label = operation == .copy ? "Copied" : "Moved"

        startFileOperation(label: label, itemCount: selectedItems.count, tabID: tabID) { context in
            try Self.performTransferItems(selectedItems.map(\.url), to: destinationDirectory, operation: operation, context: context)
        } onSuccess: { [weak self] result in
            guard destinationDirectory == currentDirectory, !result.selectedItemIDs.isEmpty else {
                return
            }

            self?.updateTab(tabID) { tab in
                tab.selectedItemIDs = result.selectedItemIDs
            }
        }

        return true
    }

    @discardableResult
    func compressSelectedItems() -> Bool {
        let selectedItems = selectedItems
        guard let currentURL, !selectedItems.isEmpty else {
            return false
        }

        let currentDirectory = currentURL.standardizedFileURL
        let tabID = selectedTabID

        startFileOperation(label: "Compressed", itemCount: selectedItems.count, tabID: tabID) { context in
            try Self.performCompressItems(selectedItems.map(\.url), in: currentDirectory, context: context)
        } onSuccess: { [weak self] result in
            if !result.selectedItemIDs.isEmpty {
                self?.updateTab(tabID) { tab in
                    tab.selectedItemIDs = result.selectedItemIDs
                }
            }
        }

        return true
    }

    @discardableResult
    func extractSelectedArchives() -> Bool {
        let selectedItems = selectedItems
        guard !selectedItems.isEmpty, selectedItems.allSatisfy(Self.canExtractArchive) else {
            return false
        }

        let tabID = selectedTabID
        startFileOperation(label: "Extracted", itemCount: selectedItems.count, tabID: tabID) { context in
            try Self.performExtractArchives(selectedItems.map(\.url), context: context)
        } onSuccess: { [weak self] result in
            if !result.selectedItemIDs.isEmpty {
                self?.updateTab(tabID) { tab in
                    tab.selectedItemIDs = result.selectedItemIDs
                }
            }
        }

        return true
    }

    func showPropertiesForSelection() {
        guard hasSelection else {
            return
        }

        showsDetailPanel = true
    }

    private func setClipboard(mode: FileClipboardMode) {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else {
            return
        }

        clipboardPayload = FileClipboardPayload(mode: mode, urls: urls)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    private func pasteboardFileURLs() -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]

        let fileURLs = NSPasteboard.general.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [NSURL]

        return fileURLs?.map { $0 as URL } ?? []
    }

    private func navigate(to url: URL, recordHistory: Bool) {
        let standardizedURL = url.standardizedFileURL
        let visibleSnapshot = loadedTabSnapshot(for: standardizedURL)

        updateSelectedTab { tab in
            if recordHistory, let currentURL = tab.currentURL, currentURL != standardizedURL {
                tab.backStack.append(currentURL)
                tab.forwardStack.removeAll()
            }

            tab.currentURL = standardizedURL
            tab.pathInput = standardizedURL.path
            tab.query = ""
            tab.searchesSubfolders = false
            tab.errorMessage = nil
            tab.loadSummary = nil
            tab.searchSummary = nil

            if let visibleSnapshot {
                tab.items = visibleSnapshot.items
                tab.loadSummary = visibleSnapshot.loadSummary
                tab.isLoading = false
            }
        }

        cancelInlineRename()
        applySavedFolderViewSettings(for: standardizedURL)
        reload(tabID: selectedTabID, showsLoadingIndicator: false)
        recordRecentDirectory(standardizedURL)
        persistTabSession()
    }

    func openPathInput() {
        guard let url = Self.resolvedPathInputURL(pathInput, relativeTo: currentURL) else {
            setSelectedError("Path is empty")
            return
        }

        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            setSelectedError("Path does not exist: \(url.path)")
            return
        }

        if isDirectory.boolValue {
            let directoryURL = URL(fileURLWithPath: url.path, isDirectory: true)
            open(directoryURL)
            recordTypedPath(directoryURL)
        } else {
            let parentURL = url.deletingLastPathComponent()
            navigate(to: parentURL, recordHistory: true)
            selectedItemIDs = [url.path]
            recordTypedPath(parentURL)
        }
    }

    func openPathInputInNewTab() {
        guard let url = Self.resolvedPathInputURL(pathInput, relativeTo: currentURL) else {
            setSelectedError("Path is empty")
            return
        }

        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            setSelectedError("Path does not exist: \(url.path)")
            return
        }

        if isDirectory.boolValue {
            let directoryURL = URL(fileURLWithPath: url.path, isDirectory: true)
            addTab(opening: directoryURL)
            recordTypedPath(directoryURL)
        } else {
            let parentURL = url.deletingLastPathComponent()
            addTab(opening: parentURL)
            selectedItemIDs = [url.path]
            recordTypedPath(parentURL)
        }
    }

    private static func resolvedPathInputURL(_ rawInput: String, relativeTo baseURL: URL?) -> URL? {
        let trimmedInput = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            return nil
        }

        let unquotedInput = trimmedInput.removingMatchingOuterQuotes()
        if let fileURL = URL(string: unquotedInput), fileURL.isFileURL {
            return fileURL.standardizedFileURL
        }

        let expandedPath = (unquotedInput as NSString).expandingTildeInPath
        if expandedPath.hasPrefix("/") {
            return URL(fileURLWithPath: expandedPath).standardizedFileURL
        }

        let baseURL = baseURL ?? FileManager.default.homeDirectoryForCurrentUser
        return baseURL.appendingPathComponent(expandedPath).standardizedFileURL
    }

    private static func pathInputCompletionRequest(
        for rawInput: String,
        relativeTo baseURL: URL?,
        limit: Int
    ) -> (directoryURL: URL, namePrefix: String)? {
        let trimmedInput = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty, limit > 0 else {
            return nil
        }

        let unquotedInput = trimmedInput.removingMatchingOuterQuotes()
        let expandedInput = (unquotedInput as NSString).expandingTildeInPath
        let usesFileURL = URL(string: unquotedInput)?.isFileURL == true
        let candidateURL = resolvedPathInputURL(unquotedInput, relativeTo: baseURL)

        let inputEndsAtDirectoryBoundary = unquotedInput.hasSuffix("/") || expandedInput.hasSuffix("/")
        let directoryURL: URL
        let namePrefix: String

        if inputEndsAtDirectoryBoundary, let candidateURL {
            directoryURL = candidateURL.standardizedFileURL
            namePrefix = ""
        } else if let candidateURL,
                  (try? candidateURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            directoryURL = candidateURL.standardizedFileURL
            namePrefix = ""
        } else {
            let baseDirectory: URL
            if usesFileURL, let candidateURL {
                baseDirectory = candidateURL.deletingLastPathComponent()
                namePrefix = candidateURL.lastPathComponent
            } else if expandedInput.hasPrefix("/") {
                let normalizedPath = (expandedInput as NSString).standardizingPath
                baseDirectory = URL(fileURLWithPath: normalizedPath).deletingLastPathComponent()
                namePrefix = URL(fileURLWithPath: normalizedPath).lastPathComponent
            } else {
                let relativeURL = (baseURL ?? FileManager.default.homeDirectoryForCurrentUser)
                    .appendingPathComponent(expandedInput)
                baseDirectory = relativeURL.deletingLastPathComponent()
                namePrefix = relativeURL.lastPathComponent
            }

            directoryURL = baseDirectory.standardizedFileURL
        }

        return (directoryURL, namePrefix)
    }

    private static func pathInputCompletionsCacheKey(
        rawInput: String,
        baseURL: URL?,
        includingHidden: Bool,
        limit: Int
    ) -> String {
        [
            rawInput,
            baseURL?.standardizedFileURL.path ?? "",
            includingHidden ? "hidden" : "visible",
            "\(limit)"
        ].joined(separator: "\u{1F}")
    }

    private static func pathInputDirectoryCompletions(
        in directoryURL: URL,
        includingHidden: Bool
    ) -> [PathInputCompletion] {
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: includingHidden ? [] : [.skipsHiddenFiles]
        ) else {
            return []
        }

        let completions = urls.compactMap { url -> PathInputCompletion? in
            let values = try? url.resourceValues(forKeys: resourceKeys)
            if !includingHidden, values?.isHidden == true {
                return nil
            }

            let standardizedURL = url.standardizedFileURL
            return PathInputCompletion(
                name: url.lastPathComponent,
                detail: standardizedURL.path,
                url: standardizedURL,
                isDirectory: values?.isDirectory == true
            )
        }

        return completions
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory && !rhs.isDirectory
                }

                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    func goUp() {
        guard let parent = currentURL?.deletingLastPathComponent() else {
            return
        }

        open(parent)
    }

    func addTab(opening url: URL? = nil) {
        addTab(opening: url, at: nil)
    }

    private func addTab(opening url: URL?, at insertionIndex: Int?) {
        let targetURL = (url ?? FileManager.default.homeDirectoryForCurrentUser).standardizedFileURL
        var tab = BrowserTab(url: targetURL)
        let visibleSnapshot = loadedTabSnapshot(for: targetURL)

        if let visibleSnapshot {
            tab.items = visibleSnapshot.items
            tab.loadSummary = visibleSnapshot.loadSummary
            tab.isLoading = false
        }

        if let insertionIndex {
            tabs.insert(tab, at: min(max(insertionIndex, tabs.startIndex), tabs.endIndex))
        } else {
            tabs.append(tab)
        }
        selectedTabID = tab.id
        reload(tabID: tab.id, showsLoadingIndicator: visibleSnapshot == nil)
        recordRecentDirectory(targetURL)
        persistTabSession()
    }

    private func loadedTabSnapshot(for url: URL) -> DirectoryContentSnapshot? {
        let standardizedURL = url.standardizedFileURL

        if let snapshot = directoryContentSnapshots[standardizedURL.path] {
            return snapshot
        }

        guard let sourceTab = tabs.first(where: { tab in
            tab.currentURL?.standardizedFileURL == standardizedURL
                && !tab.searchesSubfolders
                && tab.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && tab.errorMessage == nil
                && tab.loadSummary != nil
        }) else {
            return nil
        }

        return DirectoryContentSnapshot(items: sourceTab.items, loadSummary: sourceTab.loadSummary)
    }

    @discardableResult
    func openDroppedURLsInNewTabs(_ urls: [URL]) -> Bool {
        let urls = expandedDropURLs(from: urls)
        guard !urls.isEmpty else {
            return false
        }

        var didOpenTab = false
        var openedPaths: Set<String> = []

        for url in urls {
            let standardizedURL = url.standardizedFileURL
            guard openedPaths.insert(standardizedURL.path).inserted else {
                continue
            }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: standardizedURL.path, isDirectory: &isDirectory) else {
                continue
            }

            if isDirectory.boolValue {
                addTab(opening: URL(fileURLWithPath: standardizedURL.path, isDirectory: true))
            } else {
                let parentURL = standardizedURL.deletingLastPathComponent()
                addTab(opening: parentURL)
                selectedItemIDs = [standardizedURL.path]
                recordRecentFile(standardizedURL)
            }

            didOpenTab = true
        }

        return didOpenTab
    }

    @discardableResult
    func openDroppedURLs(_ urls: [URL], inTab tabID: BrowserTab.ID) -> Bool {
        let urls = expandedDropURLs(from: urls)
        guard !urls.isEmpty, tabs.contains(where: { $0.id == tabID }) else {
            return false
        }

        var didOpen = false
        var openedPaths: Set<String> = []
        var openedTargetTab = false

        for url in urls {
            let standardizedURL = url.standardizedFileURL
            guard openedPaths.insert(standardizedURL.path).inserted else {
                continue
            }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: standardizedURL.path, isDirectory: &isDirectory) else {
                continue
            }

            if !openedTargetTab {
                selectedTabID = tabID
                if isDirectory.boolValue {
                    open(URL(fileURLWithPath: standardizedURL.path, isDirectory: true))
                } else {
                    let parentURL = standardizedURL.deletingLastPathComponent()
                    navigate(to: parentURL, recordHistory: true)
                    selectedItemIDs = [standardizedURL.path]
                    recordRecentFile(standardizedURL)
                }
                openedTargetTab = true
            } else if isDirectory.boolValue {
                addTab(opening: URL(fileURLWithPath: standardizedURL.path, isDirectory: true))
            } else {
                let parentURL = standardizedURL.deletingLastPathComponent()
                addTab(opening: parentURL)
                selectedItemIDs = [standardizedURL.path]
                recordRecentFile(standardizedURL)
            }

            didOpen = true
        }

        return didOpen
    }

    func openCurrentFolderInNewTab() {
        guard let currentURL else {
            return
        }

        addTab(opening: currentURL)
    }

    func duplicateTab(_ tabID: BrowserTab.ID) {
        guard let source = tabs.first(where: { $0.id == tabID }),
              let sourceURL = source.currentURL else {
            return
        }

        addTab(opening: sourceURL)
    }

    func selectTab(_ tabID: BrowserTab.ID) {
        guard tabs.contains(where: { $0.id == tabID }) else {
            return
        }

        selectedTabID = tabID
        if selectedTab.items.isEmpty, selectedTab.loadSummary == nil, !selectedTab.isLoading {
            reload()
        }
        persistTabSession()
    }

    func selectTab(atDisplayIndex displayIndex: Int) {
        guard tabs.indices.contains(displayIndex) else {
            return
        }

        selectTab(tabs[displayIndex].id)
    }

    func selectNextTab() {
        guard tabs.count > 1 else {
            return
        }

        let nextIndex = (selectedTabIndex + 1) % tabs.count
        selectTab(tabs[nextIndex].id)
    }

    func selectPreviousTab() {
        guard tabs.count > 1 else {
            return
        }

        let previousIndex = (selectedTabIndex - 1 + tabs.count) % tabs.count
        selectTab(tabs[previousIndex].id)
    }

    func canMoveTabLeft(_ tabID: BrowserTab.ID) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else {
            return false
        }

        return index > 0
    }

    func canMoveTabRight(_ tabID: BrowserTab.ID) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else {
            return false
        }

        return index < tabs.index(before: tabs.endIndex)
    }

    func moveTabLeft(_ tabID: BrowserTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }), index > 0 else {
            return
        }

        moveTab(from: index, to: index - 1)
    }

    func moveTabRight(_ tabID: BrowserTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              index < tabs.index(before: tabs.endIndex) else {
            return
        }

        moveTab(from: index, to: index + 1)
    }

    func moveTabToBeginning(_ tabID: BrowserTab.ID) {
        guard let sourceIndex = tabs.firstIndex(where: { $0.id == tabID }),
              sourceIndex > 0 else {
            return
        }

        moveTab(from: sourceIndex, to: tabs.startIndex)
    }

    func moveTab(_ tabID: BrowserTab.ID, before targetTabID: BrowserTab.ID) {
        guard tabID != targetTabID,
              let sourceIndex = tabs.firstIndex(where: { $0.id == tabID }),
              let targetIndex = tabs.firstIndex(where: { $0.id == targetTabID }) else {
            return
        }

        let destinationIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        moveTab(from: sourceIndex, to: destinationIndex)
    }

    func moveTab(_ tabID: BrowserTab.ID, after targetTabID: BrowserTab.ID) {
        guard tabID != targetTabID,
              let sourceIndex = tabs.firstIndex(where: { $0.id == tabID }),
              let targetIndex = tabs.firstIndex(where: { $0.id == targetTabID }) else {
            return
        }

        let destinationIndex = sourceIndex < targetIndex ? targetIndex : targetIndex + 1
        moveTab(from: sourceIndex, to: destinationIndex)
    }

    func moveTabToEnd(_ tabID: BrowserTab.ID) {
        guard let sourceIndex = tabs.firstIndex(where: { $0.id == tabID }),
              sourceIndex < tabs.index(before: tabs.endIndex) else {
            return
        }

        moveTab(from: sourceIndex, to: tabs.index(before: tabs.endIndex))
    }

    func closeTab(_ tabID: BrowserTab.ID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == tabID }) else {
            return
        }

        recordClosedTab(tabs[index], index: index)
        cleanUpTab(tabID)
        tabs.remove(at: index)

        if selectedTabID == tabID {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
        persistTabSession()
    }

    func closeOtherTabs(keeping tabID: BrowserTab.ID) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else {
            return
        }

        let removedIDs = tabs.map(\.id).filter { $0 != tabID }
        for (index, tab) in tabs.enumerated() where tab.id != tabID {
            recordClosedTab(tab, index: index)
        }
        removedIDs.forEach(cleanUpTab)
        tabs = [tab]
        selectedTabID = tabID
        persistTabSession()
    }

    func closeTabsToRight(of tabID: BrowserTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else {
            return
        }

        let removedIDs = tabs.suffix(from: index + 1).map(\.id)
        for removedIndex in (index + 1)..<tabs.endIndex {
            recordClosedTab(tabs[removedIndex], index: removedIndex)
        }
        removedIDs.forEach(cleanUpTab)
        tabs.removeSubrange((index + 1)..<tabs.endIndex)

        if !tabs.contains(where: { $0.id == selectedTabID }) {
            selectedTabID = tabID
        }
        persistTabSession()
    }

    func reopenClosedTab() {
        guard let url = closedTabURLs.popLast() else {
            return
        }

        let insertion = closedTabInsertions.popLast()
        addTab(opening: url, at: insertion?.index)
    }

    func canMoveTabToNewWindow(_ tabID: BrowserTab.ID) -> Bool {
        tabs.count > 1 && tabs.contains { $0.id == tabID }
    }

    func moveTabToNewWindow(_ tabID: BrowserTab.ID) -> URL? {
        guard tabs.count > 1,
              let index = tabs.firstIndex(where: { $0.id == tabID }),
              let url = tabs[index].currentURL?.standardizedFileURL else {
            return nil
        }

        cleanUpTab(tabID)
        tabs.remove(at: index)

        if selectedTabID == tabID {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }

        persistTabSession()
        return url
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Open Folder"
        panel.prompt = "Open"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = currentURL

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        open(url)
    }

    private func chooseTransferDestination(operation: FileTransferOperation) {
        let panel = NSOpenPanel()
        panel.title = "\(operation.actionLabel) to Folder"
        panel.prompt = operation.actionLabel
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = currentURL

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        transferSelectedItems(to: url, operation: operation)
    }

    private var selectedTabIndex: Int {
        tabs.firstIndex { $0.id == selectedTabID } ?? 0
    }

    private func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard tabs.indices.contains(sourceIndex),
              tabs.indices.contains(destinationIndex),
              sourceIndex != destinationIndex else {
            return
        }

        let tab = tabs.remove(at: sourceIndex)
        tabs.insert(tab, at: destinationIndex)
        persistTabSession()
    }

    private func updateSelectedTab(_ update: (inout BrowserTab) -> Void) {
        updateTab(selectedTabID, update)
    }

    private func updateTab(_ tabID: BrowserTab.ID, _ update: (inout BrowserTab) -> Void) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else {
            return
        }

        update(&tabs[index])
    }

    private func cleanUpTab(_ tabID: BrowserTab.ID) {
        loadTasks[tabID]?.cancel()
        loadTasks[tabID] = nil
        searchTasks[tabID]?.cancel()
        searchTasks[tabID] = nil
        reloadDebounceTasks[tabID]?.cancel()
        reloadDebounceTasks[tabID] = nil
        searchDebounceTasks[tabID]?.cancel()
        searchDebounceTasks[tabID] = nil
        directoryWatchers[tabID]?.cancel()
        directoryWatchers[tabID] = nil
        visibleItemsCaches[tabID] = nil
        folderTypeLogoItemsCaches[tabID] = nil
        itemInventoryCaches[tabID] = nil
        availableTypeFiltersCaches[tabID] = nil
        sortedItemsCaches[tabID] = nil
        itemFilterIndexCaches[tabID] = nil
        selectedItemsCaches[tabID] = nil
        selectedItemsAggregateCaches[tabID] = nil
        selectionStatusSummaryCaches[tabID] = nil
        inspectorSummaryCaches[tabID] = nil
        visibleSectionsCaches = visibleSectionsCaches.filter { key, _ in
            !key.hasPrefix("\(tabID.uuidString)|")
        }
    }

    private func setSelectedError(_ message: String) {
        updateSelectedTab { tab in
            tab.errorMessage = message
        }
    }

    private func visibleSectionsCacheKey(for tab: BrowserTab) -> String {
        [
            tab.id.uuidString,
            "\(tab.itemsVersion)",
            tab.query,
            kindFilter.rawValue,
            typeFilter.rawValue,
            dateFilter.rawValue,
            sizeFilter.rawValue,
            foldersFirst.description,
            sortField.rawValue,
            sortAscending.description,
            groupField.rawValue
        ].joined(separator: "|")
    }

    private func persistTabSession() {
        guard persistsTabSession else {
            return
        }

        let paths = tabs.compactMap { $0.currentURL?.standardizedFileURL.path }
        userDefaults.set(paths, forKey: PreferenceKey.tabPaths)
        userDefaults.set(selectedTab.currentURL?.standardizedFileURL.path, forKey: PreferenceKey.selectedTabPath)
    }

    private func recordRecentDirectory(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        guard isDirectory(standardizedURL) else {
            return
        }

        recentDirectories.removeAll { $0.standardizedFileURL.path == standardizedURL.path }
        guard !isPinnedDirectory(standardizedURL) else {
            persistRecentDirectories()
            return
        }

        recentDirectories.insert(standardizedURL, at: 0)
        if recentDirectories.count > 8 {
            recentDirectories.removeLast(recentDirectories.count - 8)
        }

        persistRecentDirectories()
    }

    private func replaceTrackedDirectory(_ oldURL: URL, with newURL: URL) {
        let oldPath = oldURL.standardizedFileURL.path
        let standardizedNewURL = newURL.standardizedFileURL

        func replacing(_ urls: inout [URL]) {
            urls = urls.map { trackedURL in
                trackedURL.standardizedFileURL.path == oldPath ? standardizedNewURL : trackedURL
            }
        }

        replacing(&pinnedDirectories)
        replacing(&recentDirectories)
        replacing(&typedPathHistory)
        persistPinnedDirectories()
        persistRecentDirectories()
        persistTypedPathHistory()
    }

    private func removeTrackedDirectory(_ url: URL) {
        let path = url.standardizedFileURL.path
        pinnedDirectories.removeAll { $0.standardizedFileURL.path == path }
        recentDirectories.removeAll { $0.standardizedFileURL.path == path }
        typedPathHistory.removeAll { $0.standardizedFileURL.path == path }
        persistPinnedDirectories()
        persistRecentDirectories()
        persistTypedPathHistory()
    }

    func canTrashLocation(_ url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        let protectedPaths = [
            "/",
            FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path,
            Self.trashDirectoryURL.path,
            Self.networkDirectoryURL.path
        ]

        guard !protectedPaths.contains(standardizedURL.path) else {
            return false
        }

        return FileManager.default.isDeletableFile(atPath: standardizedURL.path)
    }

    @discardableResult
    private func selectVisibleLocation(_ url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        guard currentURL?.standardizedFileURL.path == standardizedURL.deletingLastPathComponent().path,
              items.contains(where: { $0.url.standardizedFileURL.path == standardizedURL.path }) else {
            return false
        }

        selectedItemIDs = [standardizedURL.path]
        return true
    }

    private func recordTypedPath(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        guard isDirectory(standardizedURL) else {
            return
        }

        typedPathHistory.removeAll { $0.standardizedFileURL.path == standardizedURL.path }
        typedPathHistory.insert(standardizedURL, at: 0)
        if typedPathHistory.count > 12 {
            typedPathHistory.removeLast(typedPathHistory.count - 12)
        }

        persistTypedPathHistory()
    }

    private func persistTypedPathHistory() {
        userDefaults.set(typedPathHistory.map(\.path), forKey: PreferenceKey.typedPathHistoryPaths)
    }

    private func persistRecentDirectories() {
        userDefaults.set(recentDirectories.map(\.path), forKey: PreferenceKey.recentDirectoryPaths)
    }

    private func persistRecentFiles() {
        userDefaults.set(recentFiles.map(\.path), forKey: PreferenceKey.recentFilePaths)
    }

    private func persistPinnedDirectories() {
        userDefaults.set(pinnedDirectories.map(\.path), forKey: PreferenceKey.pinnedDirectoryPaths)
    }

    private func persistFolderViewSettings() {
        guard !folderViewSettingsByPath.isEmpty else {
            userDefaults.removeObject(forKey: PreferenceKey.folderViewSettings)
            return
        }

        guard let data = try? JSONEncoder().encode(folderViewSettingsByPath) else {
            return
        }

        userDefaults.set(data, forKey: PreferenceKey.folderViewSettings)
    }

    private func applySavedFolderViewSettings(for url: URL) {
        guard let settings = folderViewSettingsByPath[Self.folderViewSettingsKey(for: url)] else {
            return
        }

        settings.apply(to: self)
    }

    private func isDirectory(_ url: URL) -> Bool {
        Self.isDirectoryURL(url)
    }

    private nonisolated static func resolvedFolderURL(for url: URL) -> URL? {
        if isDirectoryURL(url) {
            return url.standardizedFileURL
        }

        if let symbolicLinkTarget = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) {
            let destinationURL: URL
            if symbolicLinkTarget.hasPrefix("/") {
                destinationURL = URL(fileURLWithPath: symbolicLinkTarget, isDirectory: true)
            } else {
                destinationURL = url.deletingLastPathComponent().appendingPathComponent(symbolicLinkTarget, isDirectory: true)
            }

            if isDirectoryURL(destinationURL) {
                return destinationURL.standardizedFileURL
            }
        }

        if let aliasTarget = try? URL(resolvingAliasFileAt: url, options: [.withoutUI]),
           aliasTarget.standardizedFileURL != url.standardizedFileURL,
           isDirectoryURL(aliasTarget) {
            return aliasTarget.standardizedFileURL
        }

        return nil
    }

    private nonisolated static func folderNavigationURL(for item: FileItem) -> URL? {
        if item.canOpenAsFolder {
            return item.url
        }

        guard item.kind == .file else {
            return nil
        }

        return resolvedFolderURL(for: item.url)
    }

    private nonisolated static func packageContentsURL(for item: FileItem) -> URL? {
        guard item.kind == .package, isDirectoryURL(item.url) else {
            return nil
        }

        return item.url.standardizedFileURL
    }

    private nonisolated static func terminalTargetURL(for item: FileItem) -> URL {
        if let folderURL = folderNavigationURL(for: item) {
            return folderURL.standardizedFileURL
        }

        return item.url.deletingLastPathComponent().standardizedFileURL
    }

    private func openInTerminal(at url: URL) -> Bool {
        let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: terminalURL.path) else {
            setSelectedError("Could not find Terminal.app.")
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url.standardizedFileURL], withApplicationAt: terminalURL, configuration: configuration) { [weak self] _, error in
            guard let error else {
                return
            }

            Task { @MainActor [weak self] in
                self?.setSelectedError("Could not open Terminal: \(error.localizedDescription)")
            }
        }

        return true
    }

    private nonisolated static func isDirectoryURL(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func setError(_ message: String, tabID: BrowserTab.ID) {
        updateTab(tabID) { tab in
            tab.errorMessage = message
        }
    }

    private func recordUndo(_ action: FileUndoAction) {
        undoStack.append(action)
        if undoStack.count > 50 {
            undoStack.removeFirst(undoStack.count - 50)
        }
        redoStack = []
    }

    private func startFileOperation(
        label: String,
        itemCount: Int,
        tabID: BrowserTab.ID,
        work: @escaping @Sendable (FileOperationContext) throws -> FileOperationResult,
        onSuccess: @escaping @MainActor (FileOperationResult) -> Void = { _ in }
    ) {
        fileOperationCancellationToken?.cancel()
        fileOperationTask?.cancel()

        let summary = FileOperationSummary(
            id: UUID(),
            label: label,
            itemCount: itemCount,
            completedItemCount: 0,
            elapsedSeconds: nil,
            isCancelling: false
        )
        let cancellationToken = FileOperationCancellationToken()
        activeOperation = summary
        lastOperationSummary = nil
        fileOperationCancellationToken = cancellationToken

        let operationID = summary.id
        let context = FileOperationContext(cancellationToken: cancellationToken) { [weak self] completedItemCount in
            Task { @MainActor [weak self] in
                guard let self, self.activeOperation?.id == operationID else {
                    return
                }

                self.activeOperation = self.activeOperation?.reportingCompleted(completedItemCount)
            }
        }

        fileOperationTask = Task(priority: .userInitiated) { [weak self] in
            let start = ContinuousClock.now
            let result = await Task.detached(priority: .userInitiated) {
                try work(context)
            }.result
            let elapsed = start.duration(to: ContinuousClock.now)
            let elapsedSeconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000

            await MainActor.run { [weak self] in
                guard let self, self.activeOperation?.id == summary.id else {
                    return
                }

                let finalActiveOperation = self.activeOperation ?? summary
                self.activeOperation = nil
                self.fileOperationTask = nil
                self.fileOperationCancellationToken = nil

                switch result {
                case .success(let operationResult):
                    let finishedSummary = summary.finished(elapsedSeconds: elapsedSeconds)
                    self.lastOperationSummary = finishedSummary
                    self.recordPerformanceEvent(
                        label: finishedSummary.label,
                        itemCount: finishedSummary.itemCount,
                        elapsedSeconds: elapsedSeconds,
                        path: self.tabs.first(where: { $0.id == tabID })?.currentURL?.path
                    )
                    if let undoAction = operationResult.undoAction {
                        self.recordUndo(undoAction)
                    }
                    onSuccess(operationResult)
                    self.reload(tabID: tabID, showsLoadingIndicator: false)
                case .failure(let error):
                    if error is CancellationError {
                        let cancelledSummary = finalActiveOperation.cancelled(elapsedSeconds: elapsedSeconds)
                        self.lastOperationSummary = cancelledSummary
                        self.recordPerformanceEvent(
                            label: cancelledSummary.label,
                            itemCount: cancelledSummary.itemCount,
                            elapsedSeconds: elapsedSeconds,
                            path: self.tabs.first(where: { $0.id == tabID })?.currentURL?.path
                        )
                        self.reload(tabID: tabID, showsLoadingIndicator: false)
                    } else {
                        let failedSummary = finalActiveOperation.failed(elapsedSeconds: elapsedSeconds)
                        self.lastOperationSummary = failedSummary
                        self.recordPerformanceEvent(
                            label: failedSummary.label,
                            itemCount: failedSummary.itemCount,
                            elapsedSeconds: elapsedSeconds,
                            path: self.tabs.first(where: { $0.id == tabID })?.currentURL?.path
                        )
                        self.setError("Could not \(label.lowercased()) selection: \(error.localizedDescription)", tabID: tabID)
                    }
                }
            }
        }
    }

    func cancelActiveFileOperation() {
        guard let activeOperation, activeOperation.isRunning else {
            return
        }

        fileOperationCancellationToken?.cancel()
        self.activeOperation = activeOperation.cancelling()
    }

    private nonisolated static func performUndo(_ action: FileUndoAction) throws -> Set<FileItem.ID> {
        switch action {
        case .createFile(let url), .createFolder(let url):
            try FileManager.default.removeItem(at: url)
            return []
        case .rename(let moves):
            for move in moves.reversed() {
                try FileManager.default.moveItem(at: move.to, to: move.from)
            }
            return Set(moves.map { $0.from.standardizedFileURL.path })
        case .copy(let moves), .duplicate(let moves), .alias(let moves):
            for move in moves.reversed() {
                try FileManager.default.removeItem(at: move.to)
            }
            return Set(moves.map { $0.from.standardizedFileURL.path })
        case .move(let moves):
            for move in moves.reversed() {
                try FileManager.default.moveItem(at: move.to, to: move.from)
            }
            return Set(moves.map { $0.from.standardizedFileURL.path })
        case .trash(let moves):
            for move in moves.reversed() {
                try FileManager.default.moveItem(at: move.to, to: move.from)
            }
            return Set(moves.flatMap { move in
                [
                    move.from.path,
                    move.from.standardizedFileURL.path
                ]
            })
        case .compress(let archiveURL, let sourceURLs):
            try FileManager.default.removeItem(at: archiveURL)
            return Set(sourceURLs.map { $0.standardizedFileURL.path })
        case .extract(let extracts):
            for extract in extracts.reversed() {
                try FileManager.default.removeItem(at: extract.destinationURL)
            }
            return Set(extracts.map { $0.archiveURL.standardizedFileURL.path })
        }
    }

    private nonisolated static func performRedo(_ action: FileUndoAction) throws -> Set<FileItem.ID> {
        switch action {
        case .createFile(let url):
            try Data().write(to: url, options: .withoutOverwriting)
            return [url.standardizedFileURL.path]
        case .createFolder(let url):
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            return [url.standardizedFileURL.path]
        case .rename(let moves):
            for move in moves {
                try FileManager.default.moveItem(at: move.from, to: move.to)
            }
            return Set(moves.map { $0.to.standardizedFileURL.path })
        case .copy(let moves), .duplicate(let moves):
            for move in moves {
                try FileManager.default.copyItem(at: move.from, to: move.to)
            }
            return Set(moves.map { $0.to.standardizedFileURL.path })
        case .alias(let moves):
            for move in moves {
                try createAlias(from: move.from, to: move.to)
            }
            return Set(moves.map { $0.to.standardizedFileURL.path })
        case .move(let moves), .trash(let moves):
            for move in moves {
                try FileManager.default.moveItem(at: move.from, to: move.to)
            }
            return Set(moves.map { $0.to.standardizedFileURL.path })
        case .compress(let archiveURL, let sourceURLs):
            try zipItems(sourceURLs, to: archiveURL)
            return [archiveURL.standardizedFileURL.path]
        case .extract(let extracts):
            for extract in extracts {
                try unzipArchive(extract.archiveURL, to: extract.destinationURL)
            }
            return Set(extracts.map { $0.destinationURL.standardizedFileURL.path })
        }
    }

    private nonisolated static func performImportItems(
        _ urls: [URL],
        to destinationDirectory: URL,
        operation: FileTransferOperation,
        context: FileOperationContext
    ) throws -> FileOperationResult {
        try performTransferItems(urls, to: destinationDirectory, operation: operation, context: context)
    }

    private nonisolated static func performTransferItems(
        _ urls: [URL],
        to destinationDirectory: URL,
        operation: FileTransferOperation,
        context: FileOperationContext
    ) throws -> FileOperationResult {
        var selectedItemIDs: Set<FileItem.ID> = []
        var moves: [(from: URL, to: URL)] = []
        var completedCount = 0

        for sourceURL in urls {
            try context.checkCancellation()
            if operation == .move,
               sourceURL.deletingLastPathComponent().standardizedFileURL == destinationDirectory.standardizedFileURL {
                completedCount += 1
                context.reportCompleted(completedCount)
                continue
            }

            let destinationURL = uniqueDestinationURL(for: sourceURL, in: destinationDirectory)
            switch operation {
            case .copy:
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            case .move:
                try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            }
            selectedItemIDs.insert(destinationURL.standardizedFileURL.path)
            moves.append((from: sourceURL.standardizedFileURL, to: destinationURL.standardizedFileURL))
            completedCount += 1
            context.reportCompleted(completedCount)
        }

        let undoAction: FileUndoAction? = switch operation {
        case .copy:
            moves.isEmpty ? nil : .copy(moves)
        case .move:
            moves.isEmpty ? nil : .move(moves)
        }

        return FileOperationResult(selectedItemIDs: selectedItemIDs, undoAction: undoAction)
    }

    private nonisolated static func performDuplicateItems(_ urls: [URL], context: FileOperationContext) throws -> FileOperationResult {
        var selectedItemIDs: Set<FileItem.ID> = []
        var moves: [(from: URL, to: URL)] = []
        var completedCount = 0

        for sourceURL in urls {
            try context.checkCancellation()
            let destinationURL = uniqueDestinationURL(
                for: sourceURL,
                in: sourceURL.deletingLastPathComponent(),
                copyStyle: true
            )
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            selectedItemIDs.insert(destinationURL.standardizedFileURL.path)
            moves.append((from: sourceURL.standardizedFileURL, to: destinationURL.standardizedFileURL))
            completedCount += 1
            context.reportCompleted(completedCount)
        }

        return FileOperationResult(
            selectedItemIDs: selectedItemIDs,
            undoAction: moves.isEmpty ? nil : .duplicate(moves)
        )
    }

    private nonisolated static func performCreateAliases(_ urls: [URL], context: FileOperationContext) throws -> FileOperationResult {
        var selectedItemIDs: Set<FileItem.ID> = []
        var moves: [(from: URL, to: URL)] = []
        var completedCount = 0

        for sourceURL in urls {
            try context.checkCancellation()
            let destinationURL = uniqueAliasURL(for: sourceURL)
            try createAlias(from: sourceURL, to: destinationURL)
            selectedItemIDs.insert(destinationURL.standardizedFileURL.path)
            moves.append((from: sourceURL.standardizedFileURL, to: destinationURL.standardizedFileURL))
            completedCount += 1
            context.reportCompleted(completedCount)
        }

        return FileOperationResult(
            selectedItemIDs: selectedItemIDs,
            undoAction: moves.isEmpty ? nil : .alias(moves)
        )
    }

    private nonisolated static func performTrashItems(_ urls: [URL], context: FileOperationContext) throws -> FileOperationResult {
        var moves: [(from: URL, to: URL)] = []

        for (index, url) in urls.enumerated() {
            try context.checkCancellation()
            var trashedURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
            if let trashedURL = trashedURL as URL? {
                moves.append((from: url.standardizedFileURL, to: trashedURL.standardizedFileURL))
            }
            context.reportCompleted(index + 1)
        }

        return FileOperationResult(undoAction: moves.isEmpty ? nil : .trash(moves))
    }

    private nonisolated static func performDeleteItems(_ urls: [URL], context: FileOperationContext) throws -> FileOperationResult {
        for (index, url) in urls.enumerated() {
            try context.checkCancellation()
            try FileManager.default.removeItem(at: url)
            context.reportCompleted(index + 1)
        }

        return FileOperationResult()
    }

    private nonisolated static func trashItemURLs(in trashDirectory: URL) -> [URL]? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: trashDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return nil
        }

        return try? FileManager.default.contentsOfDirectory(
            at: trashDirectory,
            includingPropertiesForKeys: nil,
            options: []
        )
    }

    private nonisolated static func trashDirectoryContainsItems(at trashDirectory: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: trashDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let enumerator = FileManager.default.enumerator(
                at: trashDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsSubdirectoryDescendants]
              )
        else {
            return false
        }

        return enumerator.nextObject() != nil
    }

    private nonisolated static func performSetHidden(_ urls: [URL], hidden: Bool, context: FileOperationContext) throws -> FileOperationResult {
        var selectedItemIDs: Set<FileItem.ID> = []

        for (index, url) in urls.enumerated() {
            try context.checkCancellation()
            let updatedURL = try setHidden(hidden, for: url)
            selectedItemIDs.insert(updatedURL.standardizedFileURL.path)
            context.reportCompleted(index + 1)
        }

        return FileOperationResult(selectedItemIDs: selectedItemIDs)
    }

    private nonisolated static func performSetPOSIXPermissions(_ urls: [URL], permissions: UInt16, context: FileOperationContext) throws -> FileOperationResult {
        var selectedItemIDs: Set<FileItem.ID> = []

        for (index, url) in urls.enumerated() {
            try context.checkCancellation()
            try setPOSIXPermissions(permissions, for: url)
            selectedItemIDs.insert(url.standardizedFileURL.path)
            context.reportCompleted(index + 1)
        }

        return FileOperationResult(selectedItemIDs: selectedItemIDs)
    }

    private nonisolated static func performApplyFolderPermissionsToEnclosedItems(
        _ permissionSeeds: [FolderPermissionSeed],
        context: FileOperationContext
    ) throws -> FileOperationResult {
        var selectedItemIDs: Set<FileItem.ID> = []

        for (index, seed) in permissionSeeds.enumerated() {
            try context.checkCancellation()
            try applyPOSIXPermissionsToEnclosedItems(seed.permissions, in: seed.url, context: context)
            selectedItemIDs.insert(seed.url.standardizedFileURL.path)
            context.reportCompleted(index + 1)
        }

        return FileOperationResult(selectedItemIDs: selectedItemIDs)
    }

    private nonisolated static func performSetLocked(_ urls: [URL], locked: Bool, context: FileOperationContext) throws -> FileOperationResult {
        var selectedItemIDs: Set<FileItem.ID> = []

        for (index, url) in urls.enumerated() {
            try context.checkCancellation()
            try setLocked(locked, for: url)
            selectedItemIDs.insert(url.standardizedFileURL.path)
            context.reportCompleted(index + 1)
        }

        return FileOperationResult(selectedItemIDs: selectedItemIDs)
    }

    private nonisolated static func performSetFinderTags(_ urls: [URL], tagNames: [String], context: FileOperationContext) throws -> FileOperationResult {
        var selectedItemIDs: Set<FileItem.ID> = []

        for (index, url) in urls.enumerated() {
            try context.checkCancellation()
            let resolvedURL = try setFinderTags(tagNames, for: url)
            selectedItemIDs.insert(resolvedURL.path)
            context.reportCompleted(index + 1)
        }

        return FileOperationResult(selectedItemIDs: selectedItemIDs)
    }

    private nonisolated static func setFinderTags(_ tagNames: [String], for url: URL) throws -> URL {
        guard #available(macOS 26.0, *) else {
            throw NSError(
                domain: "BetterFiles.FinderTags",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Editing Finder tags requires macOS 26 or newer."]
            )
        }

        var resolvedURL = url.standardizedFileURL
        var values = URLResourceValues()
        values.tagNames = tagNames
        try resolvedURL.setResourceValues(values)
        return resolvedURL
    }

    private nonisolated static func performClearAccessControl(_ urls: [URL], context: FileOperationContext) throws -> FileOperationResult {
        var selectedItemIDs: Set<FileItem.ID> = []

        for (index, url) in urls.enumerated() {
            try context.checkCancellation()
            try clearAccessControl(for: url)
            selectedItemIDs.insert(url.standardizedFileURL.path)
            context.reportCompleted(index + 1)
        }

        return FileOperationResult(selectedItemIDs: selectedItemIDs)
    }

    private nonisolated static func performSetPermissionBits(
        _ urls: [URL],
        bits: FilePermissionBits,
        enabled: Bool,
        context: FileOperationContext
    ) throws -> FileOperationResult {
        var selectedItemIDs: Set<FileItem.ID> = []

        for (index, url) in urls.enumerated() {
            try context.checkCancellation()
            try setPermissionBits(bits, enabled: enabled, for: url)
            selectedItemIDs.insert(url.standardizedFileURL.path)
            context.reportCompleted(index + 1)
        }

        return FileOperationResult(selectedItemIDs: selectedItemIDs)
    }

    private nonisolated static func setHidden(_ hidden: Bool, for url: URL) throws -> URL {
        var resolvedURL = url.standardizedFileURL

        if !hidden, resolvedURL.lastPathComponent.hasPrefix(".") {
            let visibleURL = uniqueVisibleURL(forHiddenURL: resolvedURL)
            try FileManager.default.moveItem(at: resolvedURL, to: visibleURL)
            resolvedURL = visibleURL.standardizedFileURL
        }

        var statInfo = stat()
        guard lstat(resolvedURL.path, &statInfo) == 0 else {
            throw CocoaError(.fileNoSuchFile)
        }

        let currentFlags = statInfo.st_flags
        let updatedFlags = hidden ? (currentFlags | UInt32(UF_HIDDEN)) : (currentFlags & ~UInt32(UF_HIDDEN))
        guard chflags(resolvedURL.path, updatedFlags) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        return resolvedURL
    }

    private nonisolated static func setLocked(_ locked: Bool, for url: URL) throws {
        let resolvedURL = url.standardizedFileURL
        var statInfo = stat()
        guard lstat(resolvedURL.path, &statInfo) == 0 else {
            throw CocoaError(.fileNoSuchFile)
        }

        let currentFlags = statInfo.st_flags
        let updatedFlags = locked ? (currentFlags | UInt32(UF_IMMUTABLE)) : (currentFlags & ~UInt32(UF_IMMUTABLE))
        guard chflags(resolvedURL.path, updatedFlags) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private nonisolated static func clearAccessControl(for url: URL) throws {
        let resolvedURL = url.standardizedFileURL
        guard let emptyACL = acl_init(0) else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer {
            acl_free(UnsafeMutableRawPointer(emptyACL))
        }

        guard acl_set_file(resolvedURL.path, ACL_TYPE_EXTENDED, emptyACL) == 0 else {
            if errno == ENOENT || errno == ENOATTR {
                return
            }

            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private nonisolated static func setPOSIXPermissions(_ permissions: UInt16, for url: URL) throws {
        let updatedMode = permissions & FilePermissionBits.all.rawValue

        guard chmod(url.path, mode_t(updatedMode)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private nonisolated static func applyPOSIXPermissionsToEnclosedItems(
        _ permissions: UInt16,
        in folderURL: URL,
        context: FileOperationContext
    ) throws {
        let resourceKeys: [URLResourceKey] = [.isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: resourceKeys,
            options: [],
            errorHandler: { _, error in
                error is CancellationError
            }
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }

        for case let childURL as URL in enumerator {
            try context.checkCancellation()
            let values = try? childURL.resourceValues(forKeys: Set(resourceKeys))
            if values?.isSymbolicLink == true {
                continue
            }

            try setPOSIXPermissions(permissions, for: childURL)
        }
    }

    private nonisolated static func setPermissionBits(
        _ bits: FilePermissionBits,
        enabled: Bool,
        for url: URL
    ) throws {
        var statInfo = stat()
        guard lstat(url.path, &statInfo) == 0 else {
            throw CocoaError(.fileNoSuchFile)
        }

        let currentMode = UInt16(statInfo.st_mode & 0o777)
        let updatedMode = enabled ? (currentMode | bits.rawValue) : (currentMode & ~bits.rawValue)

        guard chmod(url.path, mode_t(updatedMode)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private nonisolated static func performCompressItems(_ urls: [URL], in directory: URL, context: FileOperationContext) throws -> FileOperationResult {
        try context.checkCancellation()
        let archiveURL = uniqueArchiveURL(for: urls, in: directory)
        try zipItems(urls, to: archiveURL)
        context.reportCompleted(urls.count)

        return FileOperationResult(
            selectedItemIDs: [archiveURL.standardizedFileURL.path],
            undoAction: .compress(
                archiveURL: archiveURL.standardizedFileURL,
                sourceURLs: urls.map(\.standardizedFileURL)
            )
        )
    }

    private nonisolated static func performExtractArchives(_ urls: [URL], context: FileOperationContext) throws -> FileOperationResult {
        var selectedItemIDs: Set<FileItem.ID> = []
        var extracts: [(archiveURL: URL, destinationURL: URL)] = []
        var completedCount = 0

        for archiveURL in urls {
            try context.checkCancellation()
            guard canExtractArchive(archiveURL) else {
                throw CocoaError(.fileReadUnsupportedScheme)
            }

            let destinationURL = uniqueExtractionDirectoryURL(for: archiveURL)
            try unzipArchive(archiveURL, to: destinationURL)
            selectedItemIDs.insert(destinationURL.standardizedFileURL.path)
            extracts.append((archiveURL: archiveURL.standardizedFileURL, destinationURL: destinationURL.standardizedFileURL))
            completedCount += 1
            context.reportCompleted(completedCount)
        }

        return FileOperationResult(
            selectedItemIDs: selectedItemIDs,
            undoAction: extracts.isEmpty ? nil : .extract(extracts)
        )
    }

    private nonisolated static func canExtractArchive(_ item: FileItem) -> Bool {
        canExtractArchive(item.url)
    }

    private nonisolated static func canExtractArchive(_ url: URL) -> Bool {
        url.pathExtension.localizedCaseInsensitiveCompare("zip") == .orderedSame
    }

    private nonisolated static func zipItems(_ urls: [URL], to archiveURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = archiveURL.deletingLastPathComponent()
        process.arguments = ["-qry", archiveURL.path, "--"] + urls.map(\.lastPathComponent)

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private nonisolated static func unzipArchive(_ archiveURL: URL, to destinationURL: URL) throws {
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: false)

        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-q", archiveURL.path, "-d", destinationURL.path]

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    private nonisolated static func uniqueArchiveURL(for urls: [URL], in directory: URL) -> URL {
        let baseName: String
        if urls.count == 1, let firstURL = urls.first {
            baseName = firstURL.deletingPathExtension().lastPathComponent
        } else {
            baseName = "Archive"
        }

        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension("zip")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(suffix)").appendingPathExtension("zip")
            suffix += 1
        }

        return candidate
    }

    private nonisolated static func uniqueExtractionDirectoryURL(for archiveURL: URL) -> URL {
        let directory = archiveURL.deletingLastPathComponent()
        let baseName = archiveURL.deletingPathExtension().lastPathComponent.isEmpty
            ? "Archive"
            : archiveURL.deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(suffix)", isDirectory: true)
            suffix += 1
        }

        return candidate
    }

    private nonisolated static func uniqueDestinationURL(
        for sourceURL: URL,
        in directory: URL,
        copyStyle: Bool = false
    ) -> URL {
        let fileManager = FileManager.default
        let originalName = sourceURL.deletingPathExtension().lastPathComponent
        let fileExtension = sourceURL.pathExtension

        func candidateURL(name: String) -> URL {
            var url = directory.appendingPathComponent(name)
            if !fileExtension.isEmpty {
                url = url.appendingPathExtension(fileExtension)
            }
            return url
        }

        if !copyStyle {
            let originalCandidate = directory.appendingPathComponent(sourceURL.lastPathComponent)
            if !fileManager.fileExists(atPath: originalCandidate.path) {
                return originalCandidate
            }
        }

        var candidate = candidateURL(name: "\(originalName) copy")
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = candidateURL(name: "\(originalName) copy \(suffix)")
            suffix += 1
        }

        return candidate
    }

    private nonisolated static func uniqueAliasURL(for sourceURL: URL) -> URL {
        let directory = sourceURL.deletingLastPathComponent()
        let fileManager = FileManager.default
        let originalName = sourceURL.deletingPathExtension().lastPathComponent
        let fileExtension = sourceURL.pathExtension

        func candidateURL(name: String) -> URL {
            var url = directory.appendingPathComponent(name)
            if !fileExtension.isEmpty {
                url = url.appendingPathExtension(fileExtension)
            }
            return url
        }

        var candidate = candidateURL(name: "\(originalName) alias")
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = candidateURL(name: "\(originalName) alias \(suffix)")
            suffix += 1
        }

        return candidate
    }

    private nonisolated static func createAlias(from sourceURL: URL, to destinationURL: URL) throws {
        let bookmarkData = try sourceURL.bookmarkData(
            options: [.suitableForBookmarkFile],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        try URL.writeBookmarkData(bookmarkData, to: destinationURL)
    }

    private nonisolated static func uniqueVisibleURL(forHiddenURL sourceURL: URL) -> URL {
        let directory = sourceURL.deletingLastPathComponent()
        let strippedName = sourceURL.lastPathComponent.drop { $0 == "." }
        let baseName = strippedName.isEmpty ? "Untitled" : String(strippedName)
        let fileManager = FileManager.default
        var candidate = directory.appendingPathComponent(baseName)
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(suffix)")
            suffix += 1
        }

        return candidate
    }

    private func uniqueFolderURL(in directory: URL) -> URL {
        let fileManager = FileManager.default
        let baseName = "New Folder"
        var candidate = directory.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(suffix)", isDirectory: true)
            suffix += 1
        }

        return candidate
    }

    private func uniqueFileURL(in directory: URL, requestedName: String) -> URL {
        let fileManager = FileManager.default
        let requestedURL = directory.appendingPathComponent(requestedName)
        let baseName = requestedURL.deletingPathExtension().lastPathComponent
        let fileExtension = requestedURL.pathExtension
        var candidate = requestedURL
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(suffix)")
            if !fileExtension.isEmpty {
                candidate = candidate.appendingPathExtension(fileExtension)
            }
            suffix += 1
        }

        return candidate
    }

    private func uniqueCopyURL(for sourceURL: URL) -> URL {
        uniqueDestinationURL(for: sourceURL, in: sourceURL.deletingLastPathComponent(), copyStyle: true)
    }

    private func uniqueBatchRenameURL(for sourceURL: URL, baseName: String, index: Int) -> URL {
        let directory = sourceURL.deletingLastPathComponent()
        let fileExtension = sourceURL.pathExtension
        var candidate = directory.appendingPathComponent("\(baseName) \(index)")

        if !fileExtension.isEmpty {
            candidate = candidate.appendingPathExtension(fileExtension)
        }

        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(index) copy \(suffix)")
            if !fileExtension.isEmpty {
                candidate = candidate.appendingPathExtension(fileExtension)
            }
            suffix += 1
        }

        return candidate
    }

    private func uniqueArchiveURL(for selectedItems: [FileItem], in directory: URL) -> URL {
        let baseName: String
        if selectedItems.count == 1, let firstItem = selectedItems.first {
            baseName = firstItem.url.deletingPathExtension().lastPathComponent
        } else {
            baseName = "Archive"
        }

        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension("zip")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(suffix)").appendingPathExtension("zip")
            suffix += 1
        }

        return candidate
    }

    private func uniqueDestinationURL(
        for sourceURL: URL,
        in directory: URL,
        copyStyle: Bool = false
    ) -> URL {
        let fileManager = FileManager.default
        let originalName = sourceURL.deletingPathExtension().lastPathComponent
        let fileExtension = sourceURL.pathExtension
        var candidate = directory.appendingPathComponent(copyStyle ? "\(originalName) copy" : sourceURL.lastPathComponent)

        if !fileExtension.isEmpty, copyStyle {
            candidate = candidate.appendingPathExtension(fileExtension)
        }

        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(originalName) copy \(suffix)")
            if !fileExtension.isEmpty {
                candidate = candidate.appendingPathExtension(fileExtension)
            }

            suffix += 1
        }

        return candidate
    }

    nonisolated static func folderTypeLogoItems(
        from items: [FileItem],
        maxLogos: Int = 4,
        sampleLimit: Int = 160
    ) -> [FileItem] {
        guard maxLogos > 0, sampleLimit > 0 else {
            return []
        }

        var seenExtensions: Set<String> = []
        var logoItems: [FileItem] = []
        logoItems.reserveCapacity(maxLogos)

        for item in items.prefix(sampleLimit) {
            guard item.kind == .file,
                  !item.normalizedFileExtension.isEmpty,
                  seenExtensions.insert(item.normalizedFileExtension).inserted else {
                continue
            }

            logoItems.append(item)

            if logoItems.count == maxLogos {
                break
            }
        }

        return logoItems
    }

    private func makeVisibleSections(from items: [FileItem]) -> [FileItemSection] {
        guard !items.isEmpty else {
            return []
        }

        switch groupField {
        case .none:
            return [FileItemSection(id: "all", title: "Items", items: items)]
        case .kind:
            return sections(
                from: items,
                buckets: [
                    ("folders", "Folders", { $0.kind == .folder }),
                    ("packages", "Packages", { $0.kind == .package }),
                    ("files", "Files", { $0.kind == .file })
                ]
            )
        case .dateModified:
            let now = Date()
            let calendar = Calendar.current
            let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            let currentYear = calendar.component(.year, from: now)

            return sections(
                from: items,
                buckets: [
                    ("today", "Today", { item in
                        item.modifiedAt.map(calendar.isDateInToday) ?? false
                    }),
                    ("last7", "Last 7 Days", { item in
                        guard let modifiedAt = item.modifiedAt else { return false }
                        return modifiedAt >= sevenDaysAgo && modifiedAt <= now && !calendar.isDateInToday(modifiedAt)
                    }),
                    ("last30", "Last 30 Days", { item in
                        guard let modifiedAt = item.modifiedAt else { return false }
                        return modifiedAt >= thirtyDaysAgo && modifiedAt < sevenDaysAgo
                    }),
                    ("thisYear", "Earlier This Year", { item in
                        guard let modifiedAt = item.modifiedAt else { return false }
                        return calendar.component(.year, from: modifiedAt) == currentYear && modifiedAt < thirtyDaysAgo
                    }),
                    ("older", "Older", { item in
                        guard let modifiedAt = item.modifiedAt else { return false }
                        return calendar.component(.year, from: modifiedAt) < currentYear
                    }),
                    ("noDate", "No Date", { $0.modifiedAt == nil })
                ]
            )
        case .size:
            return sections(
                from: items,
                buckets: [
                    ("folders", "Folders", { $0.canOpenAsFolder }),
                    ("empty", "Empty", { ($0.byteCount ?? -1) == 0 }),
                    ("under1MB", "< 1 MB", { item in
                        guard let byteCount = item.byteCount else { return false }
                        return byteCount > 0 && byteCount < 1_048_576
                    }),
                    ("oneTo100MB", "1-100 MB", { item in
                        guard let byteCount = item.byteCount else { return false }
                        return byteCount >= 1_048_576 && byteCount <= 104_857_600
                    }),
                    ("over100MB", "> 100 MB", { ($0.byteCount ?? -1) > 104_857_600 }),
                    ("unknown", "Unknown Size", { !$0.canOpenAsFolder && $0.byteCount == nil })
                ]
            )
        }
    }

    private func sections(
        from items: [FileItem],
        buckets: [(id: String, title: String, includes: (FileItem) -> Bool)]
    ) -> [FileItemSection] {
        var claimedItemIDs: Set<FileItem.ID> = []
        var groupedSections: [FileItemSection] = []

        for bucket in buckets {
            let bucketItems = items.filter { item in
                guard !claimedItemIDs.contains(item.id), bucket.includes(item) else {
                    return false
                }

                claimedItemIDs.insert(item.id)
                return true
            }

            if !bucketItems.isEmpty {
                groupedSections.append(FileItemSection(id: bucket.id, title: bucket.title, items: bucketItems))
            }
        }

        let ungroupedItems = items.filter { !claimedItemIDs.contains($0.id) }
        if !ungroupedItems.isEmpty {
            groupedSections.append(FileItemSection(id: "other", title: "Other", items: ungroupedItems))
        }

        return groupedSections
    }

    private func makeVisibleItems(for tab: BrowserTab) -> [FileItem] {
        let sourceItems = sortedItems(for: tab)
        let inventory = itemInventory(for: tab)

        guard !sourceItems.isEmpty else {
            return []
        }

        let query = tab.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kindFilter != .all || typeFilter.isActive || dateFilter != .any || sizeFilter != .any || !query.isEmpty else {
            return sourceItems
        }

        if kindFilter == .folders, typeFilter.isActive || sizeFilter != .any {
            return []
        }

        switch kindFilter {
        case .all:
            break
        case .folders where inventory.folderCount == 0:
            return []
        case .files where inventory.fileCount == 0:
            return []
        case .packages where inventory.packageCount == 0:
            return []
        case .folders, .files, .packages:
            break
        }

        if typeFilter.isActive, !inventory.contains(typeFilter) {
            return []
        }

        let indexedItems = itemFilterIndex(for: tab, sortedItems: sourceItems)
            .items(kindFilter: kindFilter, typeFilter: typeFilter)
        guard !indexedItems.isEmpty else {
            return []
        }

        let hasQuery = !query.isEmpty
        if dateFilter == .any, sizeFilter == .any, !hasQuery {
            return indexedItems
        }

        let now = dateFilter == .any ? nil : Date()
        let calendar = dateFilter == .any ? nil : Calendar.current
        let startOfToday = now.map { calendar?.startOfDay(for: $0) } ?? nil
        let startOfTomorrow = startOfToday.flatMap { calendar?.date(byAdding: .day, value: 1, to: $0) } ?? now
        let sevenDaysAgo = now.flatMap { calendar?.date(byAdding: .day, value: -7, to: $0) } ?? now
        let thirtyDaysAgo = now.flatMap { calendar?.date(byAdding: .day, value: -30, to: $0) } ?? now
        let currentYear = now.flatMap { calendar?.component(.year, from: $0) }
        let startOfCurrentYear = currentYear.flatMap { calendar?.date(from: DateComponents(year: $0)) } ?? now
        let startOfNextYear = startOfCurrentYear.flatMap { calendar?.date(byAdding: .year, value: 1, to: $0) } ?? now

        var filteredItems: [FileItem] = []
        filteredItems.reserveCapacity(indexedItems.count)

        for item in indexedItems {
            if dateFilter != .any {
                guard let modifiedAt = item.modifiedAt else {
                    continue
                }

                switch dateFilter {
                case .any:
                    break
                case .today:
                    guard let startOfToday, let startOfTomorrow,
                          modifiedAt >= startOfToday && modifiedAt < startOfTomorrow else { continue }
                case .last7Days:
                    guard let sevenDaysAgo, let now,
                          modifiedAt >= sevenDaysAgo && modifiedAt <= now else { continue }
                case .last30Days:
                    guard let thirtyDaysAgo, let now,
                          modifiedAt >= thirtyDaysAgo && modifiedAt <= now else { continue }
                case .thisYear:
                    guard let startOfCurrentYear, let startOfNextYear,
                          modifiedAt >= startOfCurrentYear && modifiedAt < startOfNextYear else { continue }
                }
            }

            if sizeFilter != .any {
                guard let byteCount = item.byteCount else {
                    continue
                }

                switch sizeFilter {
                case .any:
                    break
                case .empty:
                    guard byteCount == 0 else { continue }
                case .under1MB:
                    guard byteCount > 0 && byteCount < 1_048_576 else { continue }
                case .oneTo100MB:
                    guard byteCount >= 1_048_576 && byteCount <= 104_857_600 else { continue }
                case .over100MB:
                    guard byteCount > 104_857_600 else { continue }
                }
            }

            if !hasQuery
                || item.name.localizedCaseInsensitiveContains(query)
                || item.kindLabel.localizedCaseInsensitiveContains(query) {
                filteredItems.append(item)
            }
        }

        return filteredItems
    }

    private func itemFilterIndex(for tab: BrowserTab, sortedItems: [FileItem]) -> ItemFilterIndexCache {
        if let cachedIndex = itemFilterIndexCaches[tab.id],
           cachedIndex.matches(
               tab: tab,
               foldersFirst: foldersFirst,
               sortField: sortField,
               sortAscending: sortAscending
           ) {
            return cachedIndex
        }

        var folders: [FileItem] = []
        var files: [FileItem] = []
        var packages: [FileItem] = []
        var noExtensionItems: [FileItem] = []
        var noExtensionFiles: [FileItem] = []
        var noExtensionPackages: [FileItem] = []
        var itemsByExtension: [String: [FileItem]] = [:]
        var filesByExtension: [String: [FileItem]] = [:]
        var packagesByExtension: [String: [FileItem]] = [:]

        folders.reserveCapacity(sortedItems.count)
        files.reserveCapacity(sortedItems.count)
        packages.reserveCapacity(min(sortedItems.count, 64))

        for item in sortedItems {
            switch item.kind {
            case .folder:
                folders.append(item)
                continue
            case .file:
                files.append(item)
            case .package:
                packages.append(item)
            }

            let fileExtension = item.normalizedFileExtension
            if fileExtension.isEmpty {
                noExtensionItems.append(item)
                switch item.kind {
                case .file:
                    noExtensionFiles.append(item)
                case .package:
                    noExtensionPackages.append(item)
                case .folder:
                    break
                }
            } else {
                itemsByExtension[fileExtension, default: []].append(item)
                switch item.kind {
                case .file:
                    filesByExtension[fileExtension, default: []].append(item)
                case .package:
                    packagesByExtension[fileExtension, default: []].append(item)
                case .folder:
                    break
                }
            }
        }

        let index = ItemFilterIndexCache(
            itemsVersion: tab.itemsVersion,
            foldersFirst: foldersFirst,
            sortField: sortField,
            sortAscending: sortAscending,
            allItems: sortedItems,
            folders: folders,
            files: files,
            packages: packages,
            noExtensionItems: noExtensionItems,
            noExtensionFiles: noExtensionFiles,
            noExtensionPackages: noExtensionPackages,
            itemsByExtension: itemsByExtension,
            filesByExtension: filesByExtension,
            packagesByExtension: packagesByExtension
        )
        itemFilterIndexCaches[tab.id] = index
        return index
    }

    private func sortedItems(for tab: BrowserTab) -> [FileItem] {
        if let cachedItems = sortedItemsCaches[tab.id],
           cachedItems.matches(
               tab: tab,
               foldersFirst: foldersFirst,
               sortField: sortField,
               sortAscending: sortAscending
           ) {
            return cachedItems.items
        }

        let items = sortedItems(tab.items)
        sortedItemsCaches[tab.id] = SortedItemsCache(
            itemsVersion: tab.itemsVersion,
            foldersFirst: foldersFirst,
            sortField: sortField,
            sortAscending: sortAscending,
            items: items
        )
        return items
    }

    private func itemInventory(for tab: BrowserTab) -> ItemInventoryCache {
        if let cachedInventory = itemInventoryCaches[tab.id],
           cachedInventory.matches(tab: tab) {
            return cachedInventory
        }

        var folderCount = 0
        var packageCount = 0
        var hasNoExtension = false
        var extensions: Set<String> = []

        for item in tab.items {
            switch item.kind {
            case .folder:
                folderCount += 1
            case .package:
                packageCount += 1
                fallthrough
            case .file:
                let fileExtension = item.normalizedFileExtension
                if fileExtension.isEmpty {
                    hasNoExtension = true
                } else {
                    extensions.insert(fileExtension)
                }
            }
        }

        let inventory = ItemInventoryCache(
            itemsVersion: tab.itemsVersion,
            folderCount: folderCount,
            fileCount: tab.items.count - folderCount - packageCount,
            packageCount: packageCount,
            hasNoExtension: hasNoExtension,
            extensions: extensions
        )
        itemInventoryCaches[tab.id] = inventory
        return inventory
    }

    private func seedNameSortedItemsCacheIfPossible(
        tabID: BrowserTab.ID,
        itemsVersion: Int,
        items: [FileItem],
        foldersFirst: Bool
    ) {
        guard sortField == .name,
              sortAscending,
              Self.itemsAreNameSorted(items, foldersFirst: foldersFirst) else {
            sortedItemsCaches[tabID] = nil
            return
        }

        sortedItemsCaches[tabID] = SortedItemsCache(
            itemsVersion: itemsVersion,
            foldersFirst: foldersFirst,
            sortField: .name,
            sortAscending: true,
            items: items
        )
    }

    private static func itemsAreNameSorted(_ items: [FileItem], foldersFirst: Bool) -> Bool {
        guard items.count > 1 else {
            return true
        }

        for index in items.indices.dropFirst() {
            let previous = items[items.index(before: index)]
            let current = items[index]

            if foldersFirst, !previous.canOpenAsFolder, current.canOpenAsFolder {
                return false
            }

            guard !foldersFirst || previous.canOpenAsFolder == current.canOpenAsFolder else {
                continue
            }

            if previous.name.localizedStandardCompare(current.name) == .orderedDescending {
                return false
            }
        }

        return true
    }

    private func sortedItems(_ items: [FileItem]) -> [FileItem] {
        guard items.count > 1 else {
            return items
        }

        return items.sorted { lhs, rhs in
            if foldersFirst, lhs.canOpenAsFolder != rhs.canOpenAsFolder {
                return lhs.canOpenAsFolder
            }

            let ascendingResult: Bool

            switch sortField {
            case .name:
                ascendingResult = lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .kind:
                let kindComparison = lhs.kindLabel.localizedStandardCompare(rhs.kindLabel)
                ascendingResult = kindComparison == .orderedSame
                    ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    : kindComparison == .orderedAscending
            case .size:
                ascendingResult = (lhs.byteCount ?? -1) == (rhs.byteCount ?? -1)
                    ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    : (lhs.byteCount ?? -1) < (rhs.byteCount ?? -1)
            case .modified:
                ascendingResult = (lhs.modifiedAt ?? .distantPast) == (rhs.modifiedAt ?? .distantPast)
                    ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    : (lhs.modifiedAt ?? .distantPast) < (rhs.modifiedAt ?? .distantPast)
            case .created:
                ascendingResult = (lhs.createdAt ?? .distantPast) == (rhs.createdAt ?? .distantPast)
                    ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    : (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
            case .accessed:
                ascendingResult = (lhs.accessedAt ?? .distantPast) == (rhs.accessedAt ?? .distantPast)
                    ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    : (lhs.accessedAt ?? .distantPast) < (rhs.accessedAt ?? .distantPast)
            }

            return sortAscending ? ascendingResult : !ascendingResult
        }
    }

    private func reload(tabID: BrowserTab.ID, showsLoadingIndicator: Bool = true) {
        guard let tab = tabs.first(where: { $0.id == tabID }), let currentURL = tab.currentURL else {
            return
        }

        childFolderComponentsCaches.removeAll()
        pathInputCompletionsCaches.removeAll(keepingCapacity: true)
        pathInputDirectoryCompletionsCache = nil

        if tab.searchesSubfolders, !tab.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            runRecursiveSearch(tabID: tabID, debounce: false)
            return
        }

        loadTasks[tabID]?.cancel()
        cancelRecursiveSearch(tabID: tabID)
        startWatching(tabID: tabID, url: currentURL)

        updateTab(tabID) { tab in
            tab.isLoading = showsLoadingIndicator
            tab.errorMessage = nil
            tab.searchSummary = nil
        }

        let service = service
        let includingHidden = showHiddenFiles
        let foldersFirst = foldersFirst
        let start = ContinuousClock.now

        loadTasks[tabID] = Task.detached(priority: .userInitiated) { [weak self] in
            let result = Result {
                try service.contents(
                    of: currentURL,
                    includingHidden: includingHidden,
                    foldersFirst: foldersFirst
                )
            }

            guard !Task.isCancelled else {
                return
            }

            let elapsed = start.duration(to: ContinuousClock.now)
            let elapsedSeconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
            await MainActor.run {
                guard
                    let self,
                    let index = self.tabs.firstIndex(where: { $0.id == tabID }),
                    self.tabs[index].currentURL == currentURL
                else {
                    return
                }

                switch result {
                case .success(let items):
                    self.tabs[index].items = items
                    let loadedItemsVersion = self.tabs[index].itemsVersion
                    self.seedNameSortedItemsCacheIfPossible(
                        tabID: tabID,
                        itemsVersion: loadedItemsVersion,
                        items: items,
                        foldersFirst: foldersFirst
                    )
                    self.tabs[index].selectedItemIDs = Self.reconciledSelectionIDs(
                        self.tabs[index].selectedItemIDs,
                        availableIn: items
                    )
                    self.tabs[index].errorMessage = nil
                    self.tabs[index].loadSummary = DirectoryLoadSummary(
                        itemCount: items.count,
                        elapsedSeconds: elapsedSeconds
                    )
                    if let loadSummary = self.tabs[index].loadSummary {
                        self.cacheDirectoryContentSnapshot(
                            for: currentURL,
                            items: items,
                            loadSummary: loadSummary
                        )
                    }
                    self.recordPerformanceEvent(
                        label: "Loaded",
                        itemCount: items.count,
                        elapsedSeconds: elapsedSeconds,
                        path: currentURL.path
                    )
                case .failure(let error):
                    self.tabs[index].items = []
                    self.sortedItemsCaches[tabID] = nil
                    self.tabs[index].selectedItemIDs = []
                    self.tabs[index].errorMessage = "Could not read \(currentURL.path): \(error.localizedDescription)"
                    self.tabs[index].loadSummary = nil
                }

                self.tabs[index].isLoading = false
                self.loadTasks[tabID] = nil
            }
        }
    }

    private func startWatching(tabID: BrowserTab.ID, url: URL) {
        let standardizedURL = url.standardizedFileURL
        if directoryWatchers[tabID]?.url == standardizedURL {
            return
        }

        directoryWatchers[tabID]?.cancel()

        do {
            directoryWatchers[tabID] = try DirectoryWatcher(url: standardizedURL) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.scheduleReload(tabID: tabID, expectedURL: standardizedURL)
                }
            }
        } catch {
            directoryWatchers[tabID] = nil
        }
    }

    private func scheduleReload(tabID: BrowserTab.ID, expectedURL: URL) {
        reloadDebounceTasks[tabID]?.cancel()
        reloadDebounceTasks[tabID] = nil

        guard
            let tab = tabs.first(where: { $0.id == tabID }),
            tab.currentURL == expectedURL
        else {
            return
        }

        reload(tabID: tabID, showsLoadingIndicator: false)
    }

    private func updateSearch(forChangedQueryFrom previousQuery: String, to newQuery: String) {
        guard searchesSubfolders else {
            return
        }

        let trimmedQuery = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            cancelRecursiveSearch(tabID: selectedTabID)
            updateSelectedTab { tab in
                tab.searchSummary = nil
            }

            if !previousQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                reload()
            }
        } else {
            scheduleRecursiveSearchIfNeeded(for: selectedTabID)
        }
    }

    private func scheduleRecursiveSearchIfNeeded(for tabID: BrowserTab.ID) {
        guard
            let tab = tabs.first(where: { $0.id == tabID }),
            tab.searchesSubfolders,
            !tab.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }

        runRecursiveSearch(tabID: tabID, debounce: true)
    }

    private func runRecursiveSearch(tabID: BrowserTab.ID, debounce: Bool) {
        searchDebounceTasks[tabID]?.cancel()
        let delay = debounce ? Self.recursiveSearchDebounceDelay : .zero

        searchDebounceTasks[tabID] = Task { [weak self] in
            if delay != .zero {
                try? await Task.sleep(for: delay)
            }

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                self?.startRecursiveSearch(tabID: tabID)
            }
        }
    }

    private func startRecursiveSearch(tabID: BrowserTab.ID) {
        guard
            let tab = tabs.first(where: { $0.id == tabID }),
            let currentURL = tab.currentURL,
            tab.searchesSubfolders
        else {
            return
        }

        let query = tab.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return
        }

        loadTasks[tabID]?.cancel()
        searchTasks[tabID]?.cancel()
        startWatching(tabID: tabID, url: currentURL)

        updateTab(tabID) { tab in
            tab.isLoading = true
            tab.errorMessage = nil
            tab.searchSummary = nil
        }

        let service = service
        let includingHidden = showHiddenFiles
        let foldersFirst = foldersFirst
        let limit = Self.recursiveSearchResultLimit
        let start = ContinuousClock.now

        searchTasks[tabID] = Task(priority: .userInitiated) {
            let result = await Task.detached(priority: .userInitiated) {
                try service.search(
                    in: currentURL,
                    query: query,
                    includingHidden: includingHidden,
                    foldersFirst: foldersFirst,
                    limit: limit
                )
            }.result

            guard !Task.isCancelled else {
                return
            }

            let elapsed = start.duration(to: ContinuousClock.now)
            let elapsedSeconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
            await MainActor.run {
                guard
                    let index = self.tabs.firstIndex(where: { $0.id == tabID }),
                    self.tabs[index].currentURL == currentURL,
                    self.tabs[index].query.trimmingCharacters(in: .whitespacesAndNewlines) == query,
                    self.tabs[index].searchesSubfolders
                else {
                    return
                }

                switch result {
                case .success(let items):
                    self.tabs[index].items = items
                    self.tabs[index].selectedItemIDs = Self.reconciledSelectionIDs(
                        self.tabs[index].selectedItemIDs,
                        availableIn: items
                    )
                    self.tabs[index].errorMessage = nil
                    self.tabs[index].loadSummary = nil
                    self.tabs[index].searchSummary = RecursiveSearchSummary(
                        query: query,
                        itemCount: items.count,
                        reachedLimit: items.count >= limit,
                        elapsedSeconds: elapsedSeconds
                    )
                    self.recordPerformanceEvent(
                        label: "Searched",
                        itemCount: items.count,
                        elapsedSeconds: elapsedSeconds,
                        path: currentURL.path
                    )
                case .failure(let error):
                    self.tabs[index].items = []
                    self.tabs[index].selectedItemIDs = []
                    self.tabs[index].errorMessage = "Could not search \(currentURL.path): \(error.localizedDescription)"
                    self.tabs[index].loadSummary = nil
                    self.tabs[index].searchSummary = nil
                }

                self.tabs[index].isLoading = false
                self.searchTasks[tabID] = nil
                self.searchDebounceTasks[tabID] = nil
            }
        }
    }

    private func cancelRecursiveSearch(tabID: BrowserTab.ID) {
        searchTasks[tabID]?.cancel()
        searchTasks[tabID] = nil
        searchDebounceTasks[tabID]?.cancel()
        searchDebounceTasks[tabID] = nil
    }

    private static func reconciledSelectionIDs(
        _ existingSelectionIDs: Set<FileItem.ID>,
        availableIn items: [FileItem]
    ) -> Set<FileItem.ID> {
        guard let firstID = items.first?.id else {
            return []
        }

        guard !existingSelectionIDs.isEmpty else {
            return [firstID]
        }

        if existingSelectionIDs.count <= 32 {
            var retainedSelectionIDs: Set<FileItem.ID> = []
            retainedSelectionIDs.reserveCapacity(existingSelectionIDs.count)

            for item in items where existingSelectionIDs.contains(item.id) {
                retainedSelectionIDs.insert(item.id)
                if retainedSelectionIDs.count == existingSelectionIDs.count {
                    break
                }
            }

            return retainedSelectionIDs.isEmpty ? [firstID] : retainedSelectionIDs
        }

        let availableIDs = Set(items.map(\.id))
        let retainedSelectionIDs = existingSelectionIDs.intersection(availableIDs)
        return retainedSelectionIDs.isEmpty ? [firstID] : retainedSelectionIDs
    }

    private static func resolveOpenWithApplications(for urls: [URL]) -> [OpenWithApplication] {
        guard let primaryURL = urls.first else {
            return []
        }

        let workspace = NSWorkspace.shared
        let compatibilityURLs = Array(urls.prefix(6))
        let additionalApplicationURLs = Array(workspace.urlsForApplications(toOpen: primaryURL).prefix(24))
        var candidateURLs: [URL] = []

        if let defaultApplicationURL = workspace.urlForApplication(toOpen: primaryURL) {
            candidateURLs.append(defaultApplicationURL)
        }
        candidateURLs.append(contentsOf: additionalApplicationURLs)

        let compatibleApplicationPaths = compatibilityURLs.dropFirst().map { url in
            Set(workspace.urlsForApplications(toOpen: url).map { $0.standardizedFileURL.path })
        }

        var seenPaths: Set<String> = []
        return candidateURLs.compactMap { applicationURL -> OpenWithApplication? in
            let standardizedURL = applicationURL.standardizedFileURL
            let path = standardizedURL.path

            guard seenPaths.insert(path).inserted else {
                return nil
            }

            guard compatibleApplicationPaths.allSatisfy({ $0.contains(path) }) else {
                return nil
            }

            return OpenWithApplication(
                url: standardizedURL,
                displayName: displayName(forApplicationAt: standardizedURL)
            )
        }
    }

    private static func defaultApplication(for item: FileItem) -> OpenWithApplication? {
        guard item.kind == .file || item.kind == .package,
              let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: item.url)
        else {
            return nil
        }

        let standardizedURL = applicationURL.standardizedFileURL
        return OpenWithApplication(
            url: standardizedURL,
            displayName: displayName(forApplicationAt: standardizedURL)
        )
    }

    private static func finderTagNames(for url: URL) -> [String] {
        guard let tagNames = try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames else {
            return []
        }

        return tagNames.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func normalizedFinderTags(from rawValue: String) -> [String] {
        normalizedFinderTags(rawValue.split(separator: ",").map(String.init))
    }

    private static func normalizedFinderTags(_ tagNames: [String]) -> [String] {
        var seenTags: Set<String> = []
        var normalizedTags: [String] = []

        for tagName in tagNames {
            let normalizedTag = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedTag.isEmpty else {
                continue
            }

            guard seenTags.insert(normalizedTag.localizedLowercase).inserted else {
                continue
            }

            normalizedTags.append(normalizedTag)
        }

        return normalizedTags
    }

    private static func metadataDetails(for url: URL) -> FileMetadataDetails {
        let standardizedURL = url.standardizedFileURL
        let path = standardizedURL.path
        var statInfo = stat()
        let hasStat = lstat(path, &statInfo) == 0

        return FileMetadataDetails(
            ownerName: hasStat ? ownerName(for: statInfo.st_uid) : nil,
            groupName: hasStat ? groupName(for: statInfo.st_gid) : nil,
            accessModes: accessModes(forPath: path),
            accessControlEntries: accessControlEntries(atPath: path),
            extendedAttributeNames: extendedAttributeNames(atPath: path)
        )
    }

    private static func ownerName(for uid: uid_t) -> String? {
        guard let owner = getpwuid(uid), let name = owner.pointee.pw_name else {
            return nil
        }

        return String(cString: name)
    }

    private static func groupName(for gid: gid_t) -> String? {
        guard let group = getgrgid(gid), let name = group.pointee.gr_name else {
            return nil
        }

        return String(cString: name)
    }

    private static func accessModes(forPath path: String) -> [String] {
        let fileManager = FileManager.default
        var modes: [String] = []

        if fileManager.isReadableFile(atPath: path) {
            modes.append("Read")
        }

        if fileManager.isWritableFile(atPath: path) {
            modes.append("Write")
        }

        if fileManager.isExecutableFile(atPath: path) {
            modes.append("Run")
        }

        if fileManager.isDeletableFile(atPath: path) {
            modes.append("Delete")
        }

        return modes
    }

    private static func accessControlEntries(atPath path: String) -> [String] {
        guard let acl = acl_get_file(path, ACL_TYPE_EXTENDED) else {
            return []
        }
        defer {
            acl_free(UnsafeMutableRawPointer(acl))
        }

        var length: ssize_t = 0
        guard let text = acl_to_text(acl, &length), length > 0 else {
            return []
        }
        defer {
            acl_free(UnsafeMutableRawPointer(text))
        }

        return String(cString: text)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func extendedAttributeNames(atPath path: String) -> [String] {
        let length = listxattr(path, nil, 0, 0)
        guard length > 0 else {
            return []
        }

        var buffer = [CChar](repeating: 0, count: length)
        let result = buffer.withUnsafeMutableBufferPointer { pointer in
            listxattr(path, pointer.baseAddress, length, 0)
        }

        guard result > 0 else {
            return []
        }

        var names: [String] = []
        var currentName: [CChar] = []
        for character in buffer.prefix(result) {
            if character == 0 {
                if !currentName.isEmpty {
                    let nameBytes = currentName.map { UInt8(bitPattern: $0) }
                    names.append(String(decoding: nameBytes, as: UTF8.self))
                    currentName.removeAll(keepingCapacity: true)
                }
            } else {
                currentName.append(character)
            }
        }

        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func openWithApplicationsCacheKey(for urls: [URL]) -> String {
        urls
            .prefix(12)
            .map { $0.standardizedFileURL.path }
            .joined(separator: "\n")
    }

    private static func displayName(forApplicationAt url: URL) -> String {
        let displayName = FileManager.default.displayName(atPath: url.path)
        return displayName.isEmpty ? url.deletingPathExtension().lastPathComponent : displayName
    }

    private func recordPerformanceEvent(
        label: String,
        itemCount: Int,
        elapsedSeconds: TimeInterval,
        path: String?
    ) {
        performanceEvents.append(
            PerformanceEventSummary(
                label: label,
                itemCount: itemCount,
                elapsedSeconds: elapsedSeconds,
                path: path
            )
        )

        if performanceEvents.count > Self.performanceEventLimit {
            performanceEvents.removeFirst(performanceEvents.count - Self.performanceEventLimit)
        }
    }

    private static func elapsedSeconds(since start: ContinuousClock.Instant) -> TimeInterval {
        let elapsed = start.duration(to: ContinuousClock.now)
        return Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
    }

    private func recordClosedTab(_ tab: BrowserTab, index: Int) {
        guard let url = tab.currentURL?.standardizedFileURL else {
            return
        }

        closedTabURLs.append(url)
        closedTabInsertions.append(ClosedTabInsertion(index: index))
        if closedTabURLs.count > Self.closedTabHistoryLimit {
            closedTabURLs.removeFirst(closedTabURLs.count - Self.closedTabHistoryLimit)
            closedTabInsertions.removeFirst(closedTabInsertions.count - Self.closedTabHistoryLimit)
        }
    }

    private func cacheDirectoryContentSnapshot(
        for url: URL,
        items: [FileItem],
        loadSummary: DirectoryLoadSummary
    ) {
        let path = url.standardizedFileURL.path
        if directoryContentSnapshots[path] == nil {
            directoryContentSnapshotOrder.append(path)
        }

        directoryContentSnapshots[path] = DirectoryContentSnapshot(
            items: items,
            loadSummary: loadSummary
        )

        if directoryContentSnapshotOrder.count > Self.directoryContentSnapshotLimit {
            let overflowCount = directoryContentSnapshotOrder.count - Self.directoryContentSnapshotLimit
            let removedPaths = directoryContentSnapshotOrder.prefix(overflowCount)
            for removedPath in removedPaths {
                directoryContentSnapshots[removedPath] = nil
            }
            directoryContentSnapshotOrder.removeFirst(overflowCount)
        }
    }

    private static let recursiveSearchDebounceDelay: Duration = .milliseconds(250)
    private static let recursiveSearchResultLimit = 5_000
    private static let sidebarExpandedPathLimit = 80
    private static let closedTabHistoryLimit = 12
    private static let directoryContentSnapshotLimit = 80
    private static let performanceEventLimit = 24
}

private extension String {
    func removingMatchingOuterQuotes() -> String {
        guard count >= 2,
              let firstCharacter = first,
              let lastCharacter = last,
              (firstCharacter == "\"" && lastCharacter == "\"")
                || (firstCharacter == "'" && lastCharacter == "'")
        else {
            return self
        }

        return String(dropFirst().dropLast())
    }

    func localizedStandardContainsPrefix(_ prefix: String) -> Bool {
        guard !prefix.isEmpty else {
            return true
        }

        return range(
            of: prefix,
            options: [.caseInsensitive, .diacriticInsensitive, .anchored],
            range: startIndex..<endIndex,
            locale: .current
        ) != nil
    }
}

private final class DirectoryWatcher: @unchecked Sendable {
    let url: URL

    private let descriptor: CInt
    private let source: DispatchSourceFileSystemObject

    init(url: URL, onChange: @escaping @Sendable () -> Void) throws {
        self.url = url.standardizedFileURL
        descriptor = open(self.url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke],
            queue: Self.queue
        )
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }
        source.resume()
    }

    func cancel() {
        source.cancel()
    }

    private static let queue = DispatchQueue(label: "dev.leo.better-files.directory-watcher", qos: .userInitiated)
}
