import Foundation
import Darwin
import UniformTypeIdentifiers

protocol FileSystemServicing: Sendable {
    func contents(
        of directory: URL,
        includingHidden: Bool,
        foldersFirst: Bool
    ) throws -> [FileItem]

    func search(
        in directory: URL,
        query: String,
        includingHidden: Bool,
        foldersFirst: Bool,
        limit: Int
    ) throws -> [FileItem]
}

struct FileSystemService: FileSystemServicing, @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func contents(
        of directory: URL,
        includingHidden: Bool = false,
        foldersFirst: Bool = true
    ) throws -> [FileItem] {
        let directoryPath = directory.path
        let separator = directoryPath == "/" ? "" : "/"
        let names = try fileManager.contentsOfDirectory(atPath: directoryPath)
        var items: [FileItem] = []
        var typeDescriptionCache = TypeDescriptionCache()
        items.reserveCapacity(names.count)

        for name in names {
            if !includingHidden, name.hasPrefix(".") {
                continue
            }

            let path = directoryPath + separator + name
            if let item = makeFileItem(
                path: path,
                name: name,
                includingHidden: includingHidden,
                typeDescriptionCache: &typeDescriptionCache
            ) {
                items.append(item)
            }
        }

        return items.sorted { lhs, rhs in
                if foldersFirst, lhs.canOpenAsFolder != rhs.canOpenAsFolder {
                    return lhs.canOpenAsFolder
                }

                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func search(
        in directory: URL,
        query: String,
        includingHidden: Bool = false,
        foldersFirst: Bool = true,
        limit: Int = 5_000
    ) throws -> [FileItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty, limit > 0 else {
            return []
        }

        let rootPath = directory.standardizedFileURL.path
        var items: [FileItem] = []
        var typeDescriptionCache = TypeDescriptionCache()
        var pendingDirectories: [(path: String, hasHiddenAncestor: Bool)] = [(rootPath, false)]

        while let pendingDirectory = pendingDirectories.popLast() {
            if items.count >= limit || Task.isCancelled {
                break
            }

            guard let names = try? fileManager.contentsOfDirectory(atPath: pendingDirectory.path) else {
                continue
            }

            let separator = pendingDirectory.path == "/" ? "" : "/"
            for name in names {
                if items.count >= limit || Task.isCancelled {
                    break
                }

                let path = pendingDirectory.path + separator + name
                let isDotHidden = name.hasPrefix(".")
                if !includingHidden, (pendingDirectory.hasHiddenAncestor || isDotHidden) {
                    continue
                }

                guard let item = makeFileItem(
                    path: path,
                    name: name,
                    includingHidden: includingHidden,
                    typeDescriptionCache: &typeDescriptionCache
                ) else {
                    continue
                }

                if item.name.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    || item.kindLabel.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                    items.append(item)
                }

                if item.kind == .folder, !isSymbolicLink(atPath: path) {
                    pendingDirectories.append((path, pendingDirectory.hasHiddenAncestor || item.isHidden))
                }
            }
        }

        return items.sorted { lhs, rhs in
            if foldersFirst, lhs.canOpenAsFolder != rhs.canOpenAsFolder {
                return lhs.canOpenAsFolder
            }

            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }

    private func makeFileItem(
        path: String,
        name: String,
        includingHidden: Bool,
        typeDescriptionCache: inout TypeDescriptionCache
    ) -> FileItem? {
        var statInfo = stat()
        guard lstat(path, &statInfo) == 0 else {
            return nil
        }

        let isHidden = name.hasPrefix(".") || (statInfo.st_flags & UInt32(UF_HIDDEN)) != 0
        guard includingHidden || !isHidden else {
            return nil
        }

        let mode = statInfo.st_mode & S_IFMT
        let isSymbolicLink = mode == S_IFLNK
        let resolvesToDirectory = isSymbolicLink && targetIsDirectory(atPath: path)
        let isDirectory = mode == S_IFDIR || resolvesToDirectory
        let fileExtension = (name as NSString).pathExtension.lowercased()
        let isPackage = isDirectory && FileItem.packageExtensions.contains(fileExtension)
        let kind: FileItem.Kind

        if isDirectory && !isPackage {
            kind = .folder
        } else if isPackage {
            kind = .package
        } else {
            kind = .file
        }

        let url = URL(fileURLWithPath: path, isDirectory: isDirectory)
        return FileItem(
            id: path,
            url: url,
            name: name,
            kind: kind,
            localizedTypeDescription: typeDescriptionCache.description(forExtension: fileExtension, kind: kind),
            byteCount: isDirectory ? nil : Int64(statInfo.st_size),
            createdAt: Date(timeIntervalSince1970: TimeInterval(statInfo.st_birthtimespec.tv_sec)),
            modifiedAt: Date(timeIntervalSince1970: TimeInterval(statInfo.st_mtimespec.tv_sec)),
            accessedAt: Date(timeIntervalSince1970: TimeInterval(statInfo.st_atimespec.tv_sec)),
            isHidden: isHidden,
            isLocked: (statInfo.st_flags & UInt32(UF_IMMUTABLE)) != 0,
            posixPermissions: UInt16(statInfo.st_mode & 0o777)
        )
    }

    private func targetIsDirectory(atPath path: String) -> Bool {
        var targetStatInfo = stat()
        guard stat(path, &targetStatInfo) == 0 else {
            return false
        }

        return (targetStatInfo.st_mode & S_IFMT) == S_IFDIR
    }

    private func isSymbolicLink(atPath path: String) -> Bool {
        var statInfo = stat()
        guard lstat(path, &statInfo) == 0 else {
            return false
        }

        return (statInfo.st_mode & S_IFMT) == S_IFLNK
    }

}

private struct TypeDescriptionCache {
    private var descriptions: [String: String] = [:]
    private var misses: Set<String> = []

    mutating func description(forExtension fileExtension: String, kind: FileItem.Kind) -> String? {
        guard kind != .folder, !fileExtension.isEmpty else {
            return nil
        }

        let normalizedExtension = fileExtension.lowercased()
        if let description = descriptions[normalizedExtension] {
            return description
        }

        if misses.contains(normalizedExtension) {
            return nil
        }

        guard let description = UTType(filenameExtension: normalizedExtension)?.localizedDescription else {
            misses.insert(normalizedExtension)
            return nil
        }

        descriptions[normalizedExtension] = description
        return description
    }
}
