import Foundation

struct FilePermissionBits: OptionSet, Equatable, Sendable {
    let rawValue: UInt16

    static let ownerRead = FilePermissionBits(rawValue: 0o400)
    static let ownerWrite = FilePermissionBits(rawValue: 0o200)
    static let ownerExecute = FilePermissionBits(rawValue: 0o100)

    static let groupRead = FilePermissionBits(rawValue: 0o040)
    static let groupWrite = FilePermissionBits(rawValue: 0o020)
    static let groupExecute = FilePermissionBits(rawValue: 0o010)

    static let everyoneRead = FilePermissionBits(rawValue: 0o004)
    static let everyoneWrite = FilePermissionBits(rawValue: 0o002)
    static let everyoneExecute = FilePermissionBits(rawValue: 0o001)

    static let owner: FilePermissionBits = [.ownerRead, .ownerWrite, .ownerExecute]
    static let group: FilePermissionBits = [.groupRead, .groupWrite, .groupExecute]
    static let everyone: FilePermissionBits = [.everyoneRead, .everyoneWrite, .everyoneExecute]
    static let all: FilePermissionBits = [.owner, .group, .everyone]
}

struct FileItem: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case folder
        case package
        case file
    }

    static let packageExtensions: Set<String> = [
        "app",
        "appex",
        "bundle",
        "component",
        "docset",
        "framework",
        "key",
        "kext",
        "mdimporter",
        "numbers",
        "pages",
        "pkg",
        "plugin",
        "prefpane",
        "playground",
        "playgroundbook",
        "qlgenerator",
        "rtfd",
        "saver",
        "sketch",
        "service",
        "workflow",
        "xcarchive",
        "xcodeproj",
        "xcworkspace"
    ]

    let id: String
    let url: URL
    let name: String
    let kind: Kind
    let localizedTypeDescription: String?
    let byteCount: Int64?
    let createdAt: Date?
    let modifiedAt: Date?
    let accessedAt: Date?
    let isHidden: Bool
    let isLocked: Bool
    let posixPermissions: UInt16?
    let normalizedFileExtension: String

    init(
        id: String,
        url: URL,
        name: String,
        kind: Kind,
        localizedTypeDescription: String?,
        byteCount: Int64?,
        createdAt: Date?,
        modifiedAt: Date?,
        accessedAt: Date?,
        isHidden: Bool,
        isLocked: Bool,
        posixPermissions: UInt16?
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.kind = kind
        self.localizedTypeDescription = localizedTypeDescription
        self.byteCount = byteCount
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.accessedAt = accessedAt
        self.isHidden = isHidden
        self.isLocked = isLocked
        self.posixPermissions = posixPermissions
        normalizedFileExtension = Self.normalizedExtension(forName: name)
    }

    var canOpenAsFolder: Bool {
        kind == .folder
    }

    var kindLabel: String {
        switch kind {
        case .folder:
            return "Folder"
        case .package:
            return localizedTypeDescription ?? "Package"
        case .file:
            return localizedTypeDescription ?? "File"
        }
    }

    var systemImageName: String {
        switch kind {
        case .folder:
            return "folder"
        case .package:
            return "shippingbox"
        case .file:
            return isHidden ? "doc.badge.gearshape" : "doc"
        }
    }

    var detailSizeLabel: String {
        guard let byteCount else {
            return kind == .folder ? "Folder" : "Unknown size"
        }

        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    var sizeLabel: String {
        guard let byteCount else {
            return "--"
        }

        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    var sizeSortValue: Int64 {
        byteCount ?? -1
    }

    var modifiedLabel: String {
        guard let modifiedAt else {
            return "--"
        }

        return Self.dateTimeFormatter.string(from: modifiedAt)
    }

    var modifiedSortValue: Date {
        modifiedAt ?? .distantPast
    }

    var createdLabel: String {
        guard let createdAt else {
            return "--"
        }

        return Self.dateTimeFormatter.string(from: createdAt)
    }

    var createdSortValue: Date {
        createdAt ?? .distantPast
    }

    var accessedLabel: String {
        guard let accessedAt else {
            return "--"
        }

        return Self.dateTimeFormatter.string(from: accessedAt)
    }

    var accessedSortValue: Date {
        accessedAt ?? .distantPast
    }

    var permissionsLabel: String {
        guard let posixPermissions else {
            return "--"
        }

        return String(format: "%03o", posixPermissions)
    }

    var writableLabel: String {
        guard let posixPermissions else {
            return "--"
        }

        return (posixPermissions & 0o200) == 0 ? "Read only" : "Writable"
    }

    func hasPermission(_ bit: FilePermissionBits) -> Bool {
        guard let posixPermissions else {
            return false
        }

        return (posixPermissions & bit.rawValue) == bit.rawValue
    }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static func normalizedExtension(forName name: String) -> String {
        guard let dotIndex = name.lastIndex(of: "."),
              dotIndex != name.startIndex else {
            return ""
        }

        let extensionStartIndex = name.index(after: dotIndex)
        guard extensionStartIndex < name.endIndex else {
            return ""
        }

        return String(name[extensionStartIndex...]).lowercased()
    }
}

struct DirectoryLoadSummary: Equatable, Sendable {
    let itemCount: Int
    let elapsedSeconds: TimeInterval

    var elapsedLabel: String {
        let milliseconds = Int((elapsedSeconds * 1_000).rounded())
        return milliseconds < 10 ? "<10 ms" : "\(milliseconds) ms"
    }
}

struct RecursiveSearchSummary: Equatable, Sendable {
    let query: String
    let itemCount: Int
    let reachedLimit: Bool
    let elapsedSeconds: TimeInterval

    var elapsedLabel: String {
        let milliseconds = Int((elapsedSeconds * 1_000).rounded())
        return milliseconds < 10 ? "<10 ms" : "\(milliseconds) ms"
    }
}

struct PerformanceEventSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let label: String
    let itemCount: Int
    let elapsedSeconds: TimeInterval
    let path: String?
    let occurredAt: Date

    init(
        id: UUID = UUID(),
        label: String,
        itemCount: Int,
        elapsedSeconds: TimeInterval,
        path: String?,
        occurredAt: Date = Date()
    ) {
        self.id = id
        self.label = label
        self.itemCount = itemCount
        self.elapsedSeconds = elapsedSeconds
        self.path = path
        self.occurredAt = occurredAt
    }

    var elapsedLabel: String {
        let milliseconds = Int((elapsedSeconds * 1_000).rounded())
        return milliseconds < 10 ? "<10 ms" : "\(milliseconds) ms"
    }

    var statusLabel: String {
        "\(label) \(itemCount) in \(elapsedLabel)"
    }

    var reportLine: String {
        let pathLabel = path ?? ""
        return "\(label)\t\(itemCount)\t\(elapsedLabel)\t\(String(format: "%.6f", elapsedSeconds))\t\(pathLabel)"
    }
}

struct VolumeStatusSummary: Equatable, Sendable {
    let name: String?
    let availableByteCount: Int64?
    let totalByteCount: Int64?

    var usedFraction: Double? {
        guard let availableByteCount,
              let totalByteCount,
              totalByteCount > 0 else {
            return nil
        }

        let fraction = 1 - (Double(availableByteCount) / Double(totalByteCount))
        return min(max(fraction, 0), 1)
    }

    var statusLabel: String {
        let availableLabel = availableByteCount.map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        }
        let totalLabel = totalByteCount.map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        }

        if let availableLabel, let totalLabel {
            return "\(availableLabel) free of \(totalLabel)"
        }

        if let availableLabel {
            return "\(availableLabel) free"
        }

        if let totalLabel {
            return "\(totalLabel) volume"
        }

        return name ?? "Volume"
    }
}

struct FileOperationSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let label: String
    let itemCount: Int
    let completedItemCount: Int
    let elapsedSeconds: TimeInterval?
    let isCancelling: Bool

    var isRunning: Bool {
        elapsedSeconds == nil
    }

    var progressFraction: Double? {
        guard isRunning, itemCount > 0 else {
            return nil
        }

        return min(max(Double(completedItemCount) / Double(itemCount), 0), 1)
    }

    var statusLabel: String {
        let itemLabel = itemCount == 1 ? "item" : "items"

        guard let elapsedSeconds else {
            let runningLabel = isCancelling ? "Cancelling" : Self.runningLabel(for: label)
            guard itemCount > 1 else {
                return "\(runningLabel) \(itemCount) \(itemLabel)"
            }

            return "\(runningLabel) \(completedItemCount)/\(itemCount) \(itemLabel)"
        }

        let milliseconds = Int((elapsedSeconds * 1_000).rounded())
        let elapsedLabel = milliseconds < 10 ? "<10 ms" : "\(milliseconds) ms"
        if label == "Cancelled", itemCount > 1 {
            return "\(label) \(completedItemCount)/\(itemCount) \(itemLabel) in \(elapsedLabel)"
        }

        return "\(label) \(itemCount) \(itemLabel) in \(elapsedLabel)"
    }

    func reportingCompleted(_ completedItemCount: Int) -> FileOperationSummary {
        FileOperationSummary(
            id: id,
            label: label,
            itemCount: itemCount,
            completedItemCount: min(max(completedItemCount, 0), itemCount),
            elapsedSeconds: elapsedSeconds,
            isCancelling: isCancelling
        )
    }

    func cancelling() -> FileOperationSummary {
        FileOperationSummary(
            id: id,
            label: label,
            itemCount: itemCount,
            completedItemCount: completedItemCount,
            elapsedSeconds: elapsedSeconds,
            isCancelling: true
        )
    }

    func finished(elapsedSeconds: TimeInterval) -> FileOperationSummary {
        FileOperationSummary(
            id: id,
            label: label,
            itemCount: itemCount,
            completedItemCount: itemCount,
            elapsedSeconds: elapsedSeconds,
            isCancelling: false
        )
    }

    func cancelled(elapsedSeconds: TimeInterval) -> FileOperationSummary {
        FileOperationSummary(
            id: id,
            label: "Cancelled",
            itemCount: itemCount,
            completedItemCount: completedItemCount,
            elapsedSeconds: elapsedSeconds,
            isCancelling: false
        )
    }

    func failed(elapsedSeconds: TimeInterval) -> FileOperationSummary {
        FileOperationSummary(
            id: id,
            label: "Failed \(label)",
            itemCount: itemCount,
            completedItemCount: completedItemCount,
            elapsedSeconds: elapsedSeconds,
            isCancelling: false
        )
    }

    private static func runningLabel(for label: String) -> String {
        switch label {
        case "Copied":
            return "Copying"
        case "Moved":
            return "Moving"
        case "Moved to Trash":
            return "Moving to Trash"
        case "Emptied Trash":
            return "Emptying Trash"
        case "Deleted":
            return "Deleting"
        case "Duplicated":
            return "Duplicating"
        case "Created Alias":
            return "Creating Alias"
        case "Compressed":
            return "Compressing"
        case "Extracted":
            return "Extracting"
        case "Hidden":
            return "Hiding"
        case "Unhidden":
            return "Unhiding"
        case "Made Writable", "Made Read-Only", "Changed Permissions", "Added Permissions", "Removed Permissions", "Locked", "Unlocked", "Cleared Access Control":
            return "Updating Permissions"
        default:
            return label
        }
    }
}

enum FileKindFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case folders
    case files
    case packages

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .all:
            return "All"
        case .folders:
            return "Folders"
        case .files:
            return "Files"
        case .packages:
            return "Packages"
        }
    }

    func includes(_ item: FileItem) -> Bool {
        switch self {
        case .all:
            return true
        case .folders:
            return item.kind == .folder
        case .files:
            return item.kind == .file
        case .packages:
            return item.kind == .package
        }
    }
}

struct FileTypeFilter: RawRepresentable, Hashable, Identifiable, Codable, Sendable {
    private static let noExtensionSentinel = "__no_extension__"

    static let any = FileTypeFilter(rawValue: "")
    static let noExtension = FileTypeFilter(rawValue: noExtensionSentinel)

    let rawValue: String

    init(rawValue: String) {
        self.rawValue = Self.normalizedRawValue(rawValue)
    }

    var id: String {
        rawValue
    }

    var isActive: Bool {
        self != .any
    }

    var label: String {
        if self == .any {
            return "Any Type"
        }

        if self == .noExtension {
            return "No Extension"
        }

        return ".\(rawValue)"
    }

    func includes(_ item: FileItem) -> Bool {
        guard isActive else {
            return true
        }

        guard item.kind == .file || item.kind == .package else {
            return false
        }

        if self == .noExtension {
            return item.normalizedFileExtension.isEmpty
        }

        return item.normalizedFileExtension == rawValue
    }

    private static func normalizedRawValue(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        if trimmed == noExtensionSentinel {
            return noExtensionSentinel
        }

        let withoutLeadingDot = trimmed.hasPrefix(".") ? String(trimmed.dropFirst()) : trimmed
        return withoutLeadingDot.lowercased()
    }
}

enum FileDateFilter: String, CaseIterable, Identifiable, Sendable {
    case any
    case today
    case last7Days
    case last30Days
    case thisYear

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .any:
            return "Any Time"
        case .today:
            return "Today"
        case .last7Days:
            return "Last 7 Days"
        case .last30Days:
            return "Last 30 Days"
        case .thisYear:
            return "This Year"
        }
    }

    func includes(_ item: FileItem, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard self != .any else {
            return true
        }

        guard let modifiedAt = item.modifiedAt else {
            return false
        }

        switch self {
        case .any:
            return true
        case .today:
            return calendar.isDateInToday(modifiedAt)
        case .last7Days:
            guard let cutoff = calendar.date(byAdding: .day, value: -7, to: now) else {
                return false
            }
            return modifiedAt >= cutoff && modifiedAt <= now
        case .last30Days:
            guard let cutoff = calendar.date(byAdding: .day, value: -30, to: now) else {
                return false
            }
            return modifiedAt >= cutoff && modifiedAt <= now
        case .thisYear:
            return calendar.component(.year, from: modifiedAt) == calendar.component(.year, from: now)
        }
    }
}

enum FileSizeFilter: String, CaseIterable, Identifiable, Sendable {
    case any
    case empty
    case under1MB
    case oneTo100MB
    case over100MB

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .any:
            return "Any Size"
        case .empty:
            return "Empty"
        case .under1MB:
            return "< 1 MB"
        case .oneTo100MB:
            return "1-100 MB"
        case .over100MB:
            return "> 100 MB"
        }
    }

    func includes(_ item: FileItem) -> Bool {
        guard self != .any else {
            return true
        }

        guard let byteCount = item.byteCount else {
            return false
        }

        switch self {
        case .any:
            return true
        case .empty:
            return byteCount == 0
        case .under1MB:
            return byteCount > 0 && byteCount < 1_048_576
        case .oneTo100MB:
            return byteCount >= 1_048_576 && byteCount <= 104_857_600
        case .over100MB:
            return byteCount > 104_857_600
        }
    }
}

enum FileSortField: String, CaseIterable, Identifiable, Codable, Sendable {
    case name
    case kind
    case size
    case modified
    case created
    case accessed

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .name:
            return "Name"
        case .kind:
            return "Kind"
        case .size:
            return "Size"
        case .modified:
            return "Modified"
        case .created:
            return "Created"
        case .accessed:
            return "Accessed"
        }
    }
}

enum FileViewMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case details
    case list
    case icons
    case tiles

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .details:
            return "Details"
        case .list:
            return "List"
        case .icons:
            return "Icons"
        case .tiles:
            return "Tiles"
        }
    }

    var systemImage: String {
        switch self {
        case .details:
            return "list.bullet.rectangle"
        case .list:
            return "list.bullet"
        case .icons:
            return "square.grid.2x2"
        case .tiles:
            return "rectangle.grid.1x2"
        }
    }
}

enum FileGroupField: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case kind
    case dateModified
    case size

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .none:
            return "None"
        case .kind:
            return "Kind"
        case .dateModified:
            return "Date Modified"
        case .size:
            return "Size"
        }
    }
}

struct FileItemSection: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let items: [FileItem]
}

enum FileClipboardMode: String, Sendable {
    case copy
    case cut

    var label: String {
        switch self {
        case .copy:
            return "Copied"
        case .cut:
            return "Cut"
        }
    }
}

enum FileTransferOperation: String, Sendable {
    case copy
    case move

    var actionLabel: String {
        switch self {
        case .copy:
            return "Copy"
        case .move:
            return "Move"
        }
    }

    init(_ clipboardMode: FileClipboardMode) {
        switch clipboardMode {
        case .copy:
            self = .copy
        case .cut:
            self = .move
        }
    }
}

struct FileClipboardPayload: Equatable, Sendable {
    let mode: FileClipboardMode
    let urls: [URL]

    var itemCount: Int {
        urls.count
    }
}
