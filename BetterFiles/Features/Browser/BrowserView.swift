import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

private struct BetterFilesPrivacyMaskKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var betterFilesMasksSensitiveData: Bool {
        get { self[BetterFilesPrivacyMaskKey.self] }
        set { self[BetterFilesPrivacyMaskKey.self] = newValue }
    }
}

struct BrowserView: View {
    @Bindable var store: BrowserStore
    @State private var isEditingPath = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                TabStrip(store: store)
                CommandBar(store: store, showsNavigationPane: $store.showsNavigationPane, isEditingPath: $isEditingPath)
            }
            .background(topChromeBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.30))
                    .frame(height: 1)
            }

            HStack(spacing: 0) {
                if store.showsNavigationPane {
                    SidebarView(store: store)
                        .frame(width: 226)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .overlay(alignment: .trailing) {
                            Rectangle()
                                .fill(Color(nsColor: .separatorColor).opacity(0.32))
                                .frame(width: 1)
                        }
                }

                VStack(spacing: 0) {
                    if let errorMessage = store.errorMessage {
                        ErrorBanner(message: errorMessage)
                            .padding(.horizontal, 14)
                            .padding(.top, 12)
                    }

                    HSplitView {
                        FileWorkspaceView(store: store)
                            .frame(minWidth: 420)
                            .layoutPriority(1)

                        if store.showsPreviewPanel {
                            PreviewPanel(store: store)
                                .frame(minWidth: 220, idealWidth: 280, maxWidth: 360)
                        }

                        if store.showsDetailPanel {
                            DetailPanel(store: store)
                                .frame(minWidth: 210, idealWidth: 260, maxWidth: 340)
                        }
                    }

                    Divider()
                    StatusBar(store: store)
                }
                .navigationTitle("")
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    isEditingPath = false
                }
            )
            .transaction { transaction in
                transaction.animation = nil
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.betterFilesMasksSensitiveData, store.masksSensitiveData)
        .onExitCommand {
            isEditingPath = false
        }
    }

    private var topChromeBackground: some ShapeStyle {
        Color(nsColor: .windowBackgroundColor).opacity(0.995)
    }

}

private struct TabStrip: View {
    let store: BrowserStore

    var body: some View {
        GeometryReader { _ in
            ViewThatFits(in: .horizontal) {
                tabStripContent(
                    density: .regular,
                    showsSummary: false,
                    showsActions: true
                )
                tabStripContent(
                    density: .compact,
                    showsSummary: false,
                    showsActions: true
                )
                tabStripContent(
                    density: .tight,
                    showsSummary: false,
                    showsActions: false
                )
            }
        }
        .frame(height: 41)
        .background(tabStripBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.16))
                .frame(height: 1)
        }
        .task(id: tabIconWarmupID) {
            await FileIconLibrary.warmLocationIcons(
                for: [store.currentURL] + store.tabs.map(\.currentURL),
                limit: 48
            )
        }
    }

    private func tabStripContent(
        density: TabStripDensity,
        showsSummary: Bool,
        showsActions: Bool
    ) -> some View {
        HStack(alignment: .bottom, spacing: 5) {
            ScrollView(.horizontal) {
                HStack(alignment: .bottom, spacing: 1) {
                    ForEach(Array(store.tabs.enumerated()), id: \.element.id) { index, tab in
                        TabButton(
                            store: store,
                            tab: tab,
                            displayNumber: index < 9 ? index + 1 : nil,
                            density: density
                        )
                    }

                    TabStripNewTabButton(store: store, density: density)

                    TabStripTrailingDropTarget(store: store)
                }
                .padding(.top, 2)
                .padding(.bottom, 0)
            }
            .scrollIndicators(.hidden)
            .layoutPriority(1)

            if showsSummary {
                TabStripFolderSummary(store: store)
                    .padding(.bottom, 4)
            }

            if showsActions {
                TabStripActionCluster(store: store)
                    .padding(.bottom, 3)
            }
        }
        .padding(.trailing, density.trailingInset)
        .padding(.top, 0)
        .frame(height: 41)
    }

    private var tabStripBackground: some ShapeStyle {
        Color(nsColor: .controlBackgroundColor).opacity(0.86)
    }

    private var tabIconWarmupID: String {
        ([store.currentURL?.standardizedFileURL.path ?? "nil"] + store.tabs.map { tab in
            tab.currentURL?.standardizedFileURL.path ?? tab.id.uuidString
        }).joined(separator: "|")
    }
}

private enum TabStripDensity {
    case regular
    case compact
    case tight

    var tabMinWidth: CGFloat {
        switch self {
        case .regular:
            return 110
        case .compact:
            return 94
        case .tight:
            return 76
        }
    }

    var tabIdealWidth: CGFloat {
        switch self {
        case .regular:
            return 148
        case .compact:
            return 126
        case .tight:
            return 104
        }
    }

    var tabMaxWidth: CGFloat {
        switch self {
        case .regular:
            return 220
        case .compact:
            return 176
        case .tight:
            return 144
        }
    }

    var tabIconSize: CGFloat {
        switch self {
        case .regular, .compact:
            return 18
        case .tight:
            return 16
        }
    }

    var newTabButtonSize: CGFloat {
        switch self {
        case .regular:
            return 32
        case .compact:
            return 29
        case .tight:
            return 26
        }
    }

    var trailingInset: CGFloat {
        switch self {
        case .regular:
            return 8
        case .compact:
            return 6
        case .tight:
            return 4
        }
    }
}

private struct TabStripFolderSummary: View {
    let store: BrowserStore

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: store.isLoading ? "hourglass" : "checkmark.circle")
                .font(.system(size: 10, weight: .semibold))
                .symbolRenderingMode(.hierarchical)

            Text(summaryText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(Color.secondary)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .frame(maxWidth: 170)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.42), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.14))
        }
        .help(summaryText)
    }

    private var summaryText: String {
        if store.masksSensitiveData, store.selectedItem != nil {
            return "Private item"
        }

        if store.isLoading {
            return "Loading"
        }

        if let selectedItem = store.selectedItem {
            return selectedItem.name
        }

        let count = store.visibleItems.count
        return count == 1 ? "1 item" : "\(count) items"
    }
}

private struct TabNumberBadge: View {
    let displayNumber: Int
    let isSelected: Bool

    var body: some View {
        Text("\(displayNumber)")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(isSelected ? Color.primary.opacity(0.72) : Color.secondary.opacity(0.58))
            .frame(width: 13, height: 13)
            .background(Color(nsColor: .controlBackgroundColor).opacity(isSelected ? 0.64 : 0.18), in: RoundedRectangle(cornerRadius: 2, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(isSelected ? Color(nsColor: .separatorColor).opacity(0.18) : Color.clear)
            }
    }
}

private struct TabStripTrailingDropTarget: View {
    let store: BrowserStore
    @State private var isDropTargeted = false
    @State private var isFileDropTargeted = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(isDropTargeted || isFileDropTargeted ? Color.accentColor : Color.clear)
            .frame(width: 8, height: 34)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { draggedTabIDs, _ in
                guard let draggedTabIDString = draggedTabIDs.first,
                      let draggedTabID = UUID(uuidString: draggedTabIDString) else {
                    return false
                }

                let wasAlreadyLast = store.tabs.last?.id == draggedTabID
                store.moveTabToEnd(draggedTabID)
                return !wasAlreadyLast
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }
            .tabStripFileURLDropTarget(store: store, isTargeted: $isFileDropTargeted)
            .accessibilityHidden(true)
    }
}

private struct TabStripNewTabButton: View {
    let store: BrowserStore
    let density: TabStripDensity
    @State private var isHovering = false
    @State private var isFileDropTargeted = false

    private var isActive: Bool {
        isHovering || isFileDropTargeted
    }

    var body: some View {
        Button {
            store.addTab()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isActive ? Color.primary : Color.secondary.opacity(0.82))
                .frame(width: density.newTabButtonSize, height: density.newTabButtonSize)
                .background(
                    isActive ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.14) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(isActive ? 0.24 : 0.00))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 2)
        .help("New tab")
        .accessibilityLabel("New tab")
        .tabStripFileURLDropTarget(store: store, isTargeted: $isFileDropTargeted)
        .onHover { isHovering = $0 }
    }
}

private struct TabStripActionCluster: View {
    let store: BrowserStore

    var body: some View {
        Button {
            store.masksSensitiveData.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: store.masksSensitiveData ? "eye.slash.fill" : "eye.slash")
                    .font(.system(size: 11, weight: .bold))

                Text(store.masksSensitiveData ? "Masked" : "Mask")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(store.masksSensitiveData ? .white : Color.secondary)
            .padding(.horizontal, 9)
            .frame(height: 25)
            .background(maskBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(maskStroke)
            }
        }
        .buttonStyle(.plain)
        .help("Mask file and folder names for screenshots")
        .accessibilityLabel(store.masksSensitiveData ? "Disable privacy mask" : "Enable privacy mask")
        .padding(.horizontal, 1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var maskBackground: AnyShapeStyle {
        if store.masksSensitiveData {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.52, green: 0.24, blue: 0.94),
                        Color(red: 0.39, green: 0.18, blue: 0.76)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            return AnyShapeStyle(Color(nsColor: .controlBackgroundColor).opacity(0.74))
        }
    }

    private var maskStroke: Color {
        store.masksSensitiveData ? Color.white.opacity(0.18) : Color(nsColor: .separatorColor).opacity(0.26)
    }
}

private struct TabStripIcon: View {
    let systemImage: String
    let accessibilityLabel: String

    var body: some View {
            Image(systemName: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.secondary)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .accessibilityLabel(accessibilityLabel)
    }
}

private struct TabMenuLabel: View {
    let title: String
    let detail: String
    let url: URL?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 7) {
            LocationIconImage(url: url, fallbackSystemImage: "folder", size: 16, showsApplicationBadge: true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .lineLimit(1)

                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tint)
            }
        }
    }
}

private struct TabDragPreviewLabel: View {
    let title: String
    let url: URL?

    var body: some View {
        HStack(spacing: 7) {
            LocationIconImage(url: url, fallbackSystemImage: "folder", size: 16, showsApplicationBadge: true)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.32))
        }
    }
}

private struct TabButton: View {
    let store: BrowserStore
    let tab: BrowserTab
    let displayNumber: Int?
    let density: TabStripDensity
    @State private var isHovering = false
    @State private var isDropTargeted = false
    @State private var isFileDropTargeted = false

    private var isSelected: Bool {
        store.selectedTabID == tab.id
    }

    private var showsCloseButton: Bool {
        store.tabs.count > 1 && (isSelected || isHovering)
    }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                store.selectTab(tab.id)
            } label: {
                HStack(alignment: .center, spacing: 7) {
                    LocationIconImage(
                        url: tab.currentURL,
                        fallbackSystemImage: "folder",
                        size: density.tabIconSize,
                        showsApplicationBadge: true
                    )
                        .frame(width: density.tabIconSize + 4, height: density.tabIconSize + 4)

                    Text(store.masksSensitiveData ? "Private Folder" : tab.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tabHelp)
            .accessibilityValue(isSelected ? "Selected" : "")

            Button {
                store.closeTab(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 15, height: 15)
                    .background(
                        (isHovering && showsCloseButton) ? Color(nsColor: .separatorColor).opacity(0.18) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .opacity(showsCloseButton ? 1 : 0)
            .disabled(!showsCloseButton)
            .accessibilityLabel("Close tab")
            .frame(width: 18)
        }
        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(minWidth: density.tabMinWidth, idealWidth: density.tabIdealWidth, maxWidth: density.tabMaxWidth)
        .frame(height: 34)
        .background(tabBackground, in: tabShape)
        .overlay {
            tabShape
                .strokeBorder(
                    tabStrokeColor,
                    lineWidth: 1
                )
        }
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .frame(height: 3)
                    .offset(y: 1)
            }
        }
        .overlay(alignment: .trailing) {
            if !isSelected && !isHovering {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.20))
                    .frame(width: 1, height: 16)
                    .padding(.trailing, -1)
            }
        }
        .overlay(alignment: .leading) {
            if isDropTargeted || isFileDropTargeted {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.accentColor.opacity(isFileDropTargeted ? 0.86 : 1))
                    .frame(width: 3)
                    .padding(.vertical, 5)
            }
        }
        .contextMenu {
            Button("Duplicate Tab") {
                store.duplicateTab(tab.id)
            }

            Button("Move Tab to New Window") {
                if let url = store.moveTabToNewWindow(tab.id) {
                    BetterFilesWindowManager.openWindow(at: url)
                }
            }
            .disabled(!store.canMoveTabToNewWindow(tab.id))

            Button("Move Tab Left") {
                store.moveTabLeft(tab.id)
            }
            .disabled(!store.canMoveTabLeft(tab.id))

            Button("Move Tab Right") {
                store.moveTabRight(tab.id)
            }
            .disabled(!store.canMoveTabRight(tab.id))

            Button("Move Tab to Beginning") {
                store.moveTabToBeginning(tab.id)
            }
            .disabled(!store.canMoveTabLeft(tab.id))

            Button("Move Tab to End") {
                store.moveTabToEnd(tab.id)
            }
            .disabled(!store.canMoveTabRight(tab.id))

            Button("Close Tab") {
                store.closeTab(tab.id)
            }
            .disabled(store.tabs.count <= 1)

            Button("Close Other Tabs") {
                store.closeOtherTabs(keeping: tab.id)
            }
            .disabled(store.tabs.count <= 1)

            Button("Close Tabs to Right") {
                store.closeTabsToRight(of: tab.id)
            }
            .disabled(store.tabs.last?.id == tab.id)

            Divider()

            Button("Reopen Closed Tab") {
                store.reopenClosedTab()
            }
            .disabled(!store.canReopenClosedTab)
        }
        .draggable(tab.id.uuidString) {
            TabDragPreviewLabel(title: store.masksSensitiveData ? "Private Folder" : tab.title, url: tab.currentURL)
        }
        .dropDestination(for: String.self) { draggedTabIDs, location in
            guard let draggedTabIDString = draggedTabIDs.first,
                  let draggedTabID = UUID(uuidString: draggedTabIDString) else {
                return false
            }

            if location.x > density.tabIdealWidth / 2 {
                store.moveTab(draggedTabID, after: tab.id)
            } else {
                store.moveTab(draggedTabID, before: tab.id)
            }
            return draggedTabID != tab.id
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .tabStripFileURLDropTarget(store: store, targetTabID: tab.id, isTargeted: $isFileDropTargeted)
        .onHover { isHovering = $0 }
    }

    private var tabBackground: AnyShapeStyle {
        if isFileDropTargeted {
            return AnyShapeStyle(Color.accentColor.opacity(0.16))
        }

        if isSelected {
            return AnyShapeStyle(Color(nsColor: .controlBackgroundColor).opacity(0.94))
        } else if isHovering {
            return AnyShapeStyle(Color(nsColor: .selectedContentBackgroundColor).opacity(0.14))
        } else {
            return AnyShapeStyle(Color.clear)
        }
    }

    private var tabStrokeColor: Color {
        if isFileDropTargeted {
            return Color.accentColor.opacity(0.46)
        }

        if isSelected {
            return Color(nsColor: .separatorColor).opacity(0.48)
        }

        return Color(nsColor: .separatorColor).opacity(isHovering ? 0.28 : 0.00)
    }

    private var tabShape: UnevenRoundedRectangle {
        let topRadius: CGFloat = 5
        let bottomRadius: CGFloat = isSelected ? 0 : 3
        return UnevenRoundedRectangle(
            topLeadingRadius: topRadius,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: topRadius,
            style: .continuous
        )
    }

    private var tabHelp: String {
        var parts = [store.masksSensitiveData ? "Private path" : (tab.currentURL?.path ?? tab.title)]
        if let displayNumber {
            parts.append("Command-Option-\(displayNumber)")
        }
        return parts.joined(separator: "\n")
    }
}

struct SidebarRevealCandidate: Equatable, Sendable {
    let url: URL
    var includesRootDescendants = false
}

enum SidebarRevealTarget {
    static func bestCandidateURL(for currentURL: URL?, in candidates: [SidebarRevealCandidate]) -> URL? {
        guard let currentPath = currentURL?.standardizedFileURL.path else {
            return nil
        }

        return candidates
            .filter { candidate in
                let candidatePath = candidate.url.standardizedFileURL.path
                if candidatePath == "/" {
                    return candidate.includesRootDescendants ? currentPath.hasPrefix("/") : currentPath == "/"
                }

                return currentPath == candidatePath || currentPath.hasPrefix(candidatePath + "/")
            }
            .max { lhs, rhs in
                lhs.url.standardizedFileURL.path.count < rhs.url.standardizedFileURL.path.count
            }?
            .url
            .standardizedFileURL
    }
}

enum SidebarRevealPath {
    static func ancestorURLsToExpand(
        for currentURL: URL,
        from rootURL: URL,
        maximumDepth: Int = 8
    ) -> [URL] {
        let rootURL = rootURL.standardizedFileURL
        let currentURL = currentURL.standardizedFileURL
        let rootPath = rootURL.path
        let currentPath = currentURL.path

        guard rootPath == "/" || currentPath == rootPath || currentPath.hasPrefix(rootPath + "/") else {
            return []
        }

        guard currentPath != rootPath else {
            return [rootURL]
        }

        let prefixLength = rootPath == "/" ? rootPath.count : rootPath.count + 1
        let relativePath = String(currentPath.dropFirst(prefixLength))
        let parts = relativePath.split(separator: "/").map(String.init)
        guard !parts.isEmpty else {
            return [rootURL]
        }

        var expandedPaths = [rootPath]
        var ancestorPath = rootPath
        for part in parts.dropLast().prefix(max(0, maximumDepth - 1)) {
            if ancestorPath == "/" {
                ancestorPath += part
            } else {
                ancestorPath += "/\(part)"
            }

            expandedPaths.append(ancestorPath)
        }

        return expandedPaths.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
    }
}

enum SidebarScopeResolver {
    static func primaryActiveRootPath(
        for currentURL: URL?,
        mountedVolumes: [URL],
        pinnedDirectories: [URL],
        recentDirectories: [URL],
        favorites: [URL] = FavoriteLocation.defaults.map(\.url)
    ) -> String? {
        guard let currentPath = currentURL?.standardizedFileURL.path else {
            return nil
        }

        let candidates = favorites
            + pinnedDirectories
            + recentDirectories
            + mountedVolumes

        return candidates
            .filter { candidateURL in
                let candidatePath = candidateURL.standardizedFileURL.path
                if candidatePath == "/" {
                    return currentPath.hasPrefix("/")
                }

                return currentPath == candidatePath || currentPath.hasPrefix(candidatePath + "/")
            }
            .max { lhs, rhs in
                lhs.standardizedFileURL.path.count < rhs.standardizedFileURL.path.count
            }?
            .standardizedFileURL
            .path
    }

    static func sectionContains(_ activeRootPath: String?, urls: [URL]) -> Bool {
        guard let activeRootPath else {
            return false
        }

        return urls.contains { url in
            url.standardizedFileURL.path == activeRootPath
        }
    }
}

enum LocationScopeResolver {
    enum Scope: Equatable {
        case home
        case thisMac
        case network

        var label: String {
            switch self {
            case .home:
                return "Home"
            case .thisMac:
                return "This Mac"
            case .network:
                return "Network"
            }
        }
    }

    static func scope(
        for currentURL: URL?,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        networkURL: URL = URL(fileURLWithPath: "/Network", isDirectory: true)
    ) -> Scope? {
        guard let currentURL else {
            return nil
        }

        if isLocation(currentURL, inside: networkURL, includesRootDescendants: true) {
            return .network
        }

        if isLocation(currentURL, inside: homeURL) {
            return .home
        }

        return currentURL.standardizedFileURL.path.hasPrefix("/") ? .thisMac : nil
    }

    static func isScopeActive(
        _ scope: Scope,
        for currentURL: URL?,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        networkURL: URL = URL(fileURLWithPath: "/Network", isDirectory: true)
    ) -> Bool {
        self.scope(for: currentURL, homeURL: homeURL, networkURL: networkURL) == scope
    }

    private static func isLocation(_ currentURL: URL, inside candidateURL: URL, includesRootDescendants: Bool = false) -> Bool {
        let currentPath = currentURL.standardizedFileURL.path
        let candidatePath = candidateURL.standardizedFileURL.path
        if candidatePath == "/" {
            return includesRootDescendants ? currentPath.hasPrefix("/") : currentPath == "/"
        }

        return currentPath == candidatePath || currentPath.hasPrefix(candidatePath + "/")
    }
}

enum FileAccessRecoveryResolver {
    static let fullDiskAccessSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    )!

    static func shouldSuggestFullDiskAccess(for message: String) -> Bool {
        let lowercasedMessage = message.lowercased()
        return lowercasedMessage.contains("operation not permitted")
            || lowercasedMessage.contains("permission denied")
            || lowercasedMessage.contains("not authorized")
            || lowercasedMessage.contains("not authorised")
            || lowercasedMessage.contains("could not read")
    }

    @MainActor
    static func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(fullDiskAccessSettingsURL)
    }
}

enum VisibleIconWarmupPolicy {
    static func limit(for viewMode: FileViewMode, compactView: Bool) -> Int {
        switch viewMode {
        case .details:
            return compactView ? 128 : 96
        case .list:
            return compactView ? 144 : 112
        case .tiles:
            return compactView ? 180 : 144
        case .icons:
            return compactView ? 220 : 180
        }
    }

    static func prefersFileSpecificIcons(for viewMode: FileViewMode) -> Bool {
        switch viewMode {
        case .details, .list:
            return false
        case .tiles, .icons:
            return true
        }
    }
}

enum FolderTypeLogoResolver {
    static func logoItems(
        from items: [FileItem],
        maxLogos: Int = 4,
        sampleLimit: Int = 160
    ) -> [FileItem] {
        BrowserStore.folderTypeLogoItems(
            from: items,
            maxLogos: maxLogos,
            sampleLimit: sampleLimit
        )
    }
}

enum SidebarCurrentRouteResolver {
    static func shouldShowCurrentRoute(from rootURL: URL, to currentURL: URL, isPrimaryActive: Bool) -> Bool {
        guard isPrimaryActive else {
            return false
        }

        guard currentLocation(
            currentURL,
            isInside: rootURL,
            includesRootDescendants: rootURL.standardizedFileURL.path == "/"
        ),
              currentURL.standardizedFileURL.path != rootURL.standardizedFileURL.path else {
            return false
        }

        return !routeComponents(from: rootURL, to: currentURL).isEmpty
    }

    static func visibleRouteComponents(from rootURL: URL, to currentURL: URL, limit: Int = 4) -> [BrowserPathComponent] {
        let components = routeComponents(from: rootURL, to: currentURL)
        guard components.count > limit else {
            return components
        }

        return Array(components.suffix(limit))
    }

    static func routeComponents(from rootURL: URL, to currentURL: URL) -> [BrowserPathComponent] {
        let rootPath = rootURL.standardizedFileURL.path
        let currentPath = currentURL.standardizedFileURL.path
        guard rootPath != currentPath else {
            return []
        }

        let prefixLength = rootPath == "/" ? rootPath.count : rootPath.count + 1
        guard currentPath.count > prefixLength else {
            return []
        }

        let relativePath = String(currentPath.dropFirst(prefixLength))
        let parts = relativePath.split(separator: "/").map(String.init)
        guard !parts.isEmpty else {
            return []
        }

        var routeURL = rootURL.standardizedFileURL
        return parts.map { part in
            routeURL = routeURL.appendingPathComponent(part, isDirectory: true).standardizedFileURL
            return BrowserPathComponent(name: part, url: routeURL)
        }
    }

    private static func currentLocation(_ currentURL: URL, isInside candidateURL: URL, includesRootDescendants: Bool = false) -> Bool {
        let currentPath = currentURL.standardizedFileURL.path
        let candidatePath = candidateURL.standardizedFileURL.path
        if candidatePath == "/" {
            return includesRootDescendants ? currentPath.hasPrefix("/") : currentPath == "/"
        }

        return currentPath == candidatePath || currentPath.hasPrefix(candidatePath + "/")
    }
}

enum SidebarChildListResolver {
    static func visibleFolders(
        _ sortedFolders: [BrowserPathComponent],
        inside directoryURL: URL,
        limit: Int,
        preferredDescendantURL: URL? = nil
    ) -> [BrowserPathComponent] {
        guard limit > 0 else {
            return []
        }

        var visibleFolders = Array(sortedFolders.prefix(limit))
        if let preferredChildURL = directChildURL(inside: directoryURL, toward: preferredDescendantURL),
           !visibleFolders.contains(where: { $0.url.standardizedFileURL == preferredChildURL }),
           let preferredFolder = sortedFolders.first(where: { $0.url.standardizedFileURL == preferredChildURL }) {
            if visibleFolders.count >= limit {
                visibleFolders.removeLast()
            }

            visibleFolders.append(preferredFolder)
            visibleFolders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }

        return visibleFolders
    }

    static func directChildURL(inside directoryURL: URL, toward descendantURL: URL?) -> URL? {
        guard let descendantURL else {
            return nil
        }

        let directoryPath = directoryURL.standardizedFileURL.path
        let descendantPath = descendantURL.standardizedFileURL.path
        guard directoryPath != descendantPath else {
            return nil
        }

        let relativePath: String
        if directoryPath == "/" {
            guard descendantPath.hasPrefix("/") else {
                return nil
            }
            relativePath = String(descendantPath.dropFirst())
        } else {
            guard descendantPath.hasPrefix(directoryPath + "/") else {
                return nil
            }
            relativePath = String(descendantPath.dropFirst(directoryPath.count + 1))
        }

        guard let childName = relativePath.split(separator: "/").first.map(String.init) else {
            return nil
        }

        if directoryPath == "/" {
            return URL(fileURLWithPath: "/" + childName, isDirectory: true).standardizedFileURL
        }

        return directoryURL
            .appendingPathComponent(childName, isDirectory: true)
            .standardizedFileURL
    }
}

private struct SidebarView: View {
    let store: BrowserStore
    @State private var mountedVolumes = FavoriteLocation.initialMountedVolumes
    @State private var expandedSidebarNodeIDs: Set<String> = []
    @State private var sidebarChildrenByID: [String: [BrowserPathComponent]] = [:]
    @State private var loadingSidebarNodeIDs: Set<String> = []
    @State private var restoredPersistedSidebarExpansion = false

    var body: some View {
        let defaultPaths = Set(FavoriteLocation.defaults.map { $0.url.standardizedFileURL.path })
        let filteredPinnedDirectories = store.pinnedDirectories.filter { !defaultPaths.contains($0.standardizedFileURL.path) }
        let activeID = FavoriteLocation.activeID(
            for: store.currentURL,
            in: FavoriteLocation.defaults + mountedVolumes
        )
        let primaryActiveRootPath = SidebarView.primaryActiveRootPath(
            for: store.currentURL,
            mountedVolumes: mountedVolumes,
            pinnedDirectories: store.pinnedDirectories,
            recentDirectories: []
        )

        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(FavoriteLocation.defaults) { location in
                        SidebarTreeLocationButton(
                            store: store,
                            title: location.name,
                            subtitle: nil,
                            url: location.url,
                            fallbackSystemImage: location.systemImage,
                            isActive: activeID == location.id,
                            isPrimaryActive: primaryActiveRootPath == location.url.standardizedFileURL.path,
                            activeDetail: SidebarView.activeDetail(for: store.currentURL, inside: location.url),
                            currentURL: store.currentURL,
                            isPinnedLocation: store.isPinnedDirectory(location.url),
                            isExpanded: sidebarExpansionBinding(for: location.url),
                            children: sidebarChildren(for: location.url),
                            isLoading: sidebarIsLoading(location.url),
                            onExpand: { loadSidebarChildren(for: location.url) },
                            childExpansion: { sidebarExpansionBinding(for: $0) },
                            childChildren: { sidebarChildren(for: $0) },
                            childIsLoading: { sidebarIsLoading($0) },
                            childOnExpand: { loadSidebarChildren(for: $0) }
                        )
                    }

                if !filteredPinnedDirectories.isEmpty {
                    SidebarGroupDivider()

                        ForEach(filteredPinnedDirectories, id: \.path) { url in
                            SidebarTreeLocationButton(
                                store: store,
                                title: store.displayName(for: url),
                                subtitle: nil,
                                url: url,
                                fallbackSystemImage: "pin",
                                isActive: SidebarView.currentLocation(store.currentURL, isInside: url),
                                isPrimaryActive: primaryActiveRootPath == url.standardizedFileURL.path,
                                activeDetail: SidebarView.activeDetail(for: store.currentURL, inside: url),
                                currentURL: store.currentURL,
                                isPinnedLocation: true,
                                isExpanded: sidebarExpansionBinding(for: url),
                                children: sidebarChildren(for: url),
                                isLoading: sidebarIsLoading(url),
                                onExpand: { loadSidebarChildren(for: url) },
                                childExpansion: { sidebarExpansionBinding(for: $0) },
                                childChildren: { sidebarChildren(for: $0) },
                                childIsLoading: { sidebarIsLoading($0) },
                                childOnExpand: { loadSidebarChildren(for: $0) }
                            )
                        }
                }

                    SidebarGroupDivider()

                    ForEach(Array(uniqueMountedVolumes.enumerated()), id: \.offset) { _, location in
                        let isInsideVolume = SidebarView.currentLocation(
                            store.currentURL,
                            isInside: location.url,
                            includesRootDescendants: true
                        )
                        SidebarTreeLocationButton(
                            store: store,
                            title: store.masksSensitiveData ? "Private Drive" : location.name,
                            subtitle: nil,
                            url: location.url,
                            fallbackSystemImage: location.systemImage,
                            isActive: isInsideVolume || activeID == location.id,
                            isPrimaryActive: primaryActiveRootPath == location.url.standardizedFileURL.path,
                            activeDetail: SidebarView.activeDetail(
                                for: store.currentURL,
                                inside: location.url,
                                includesRootDescendants: true
                            ),
                            currentURL: store.currentURL,
                            isPinnedLocation: store.isPinnedDirectory(location.url),
                            isExpanded: sidebarExpansionBinding(for: location.url),
                            children: sidebarChildren(for: location.url),
                            isLoading: sidebarIsLoading(location.url),
                            onExpand: { loadSidebarChildren(for: location.url) },
                            childExpansion: { sidebarExpansionBinding(for: $0) },
                            childChildren: { sidebarChildren(for: $0) },
                            childIsLoading: { sidebarIsLoading($0) },
                            childOnExpand: { loadSidebarChildren(for: $0) }
                        )
                    }
                }
                .padding(.horizontal, 7)
                .padding(.top, 7)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle("Locations")
        .task {
            warmSidebarLocationIcons()
            await refreshMountedVolumes()
            warmSidebarLocationIcons()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didMountNotification)) { _ in
            Task {
                await refreshMountedVolumes()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            Task {
                await refreshMountedVolumes()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didRenameVolumeNotification)) { _ in
            Task {
                await refreshMountedVolumes()
            }
        }
        .onChange(of: store.showHiddenFiles) {
            warmSidebarLocationIcons()
        }
        .onChange(of: store.currentURL) {
            warmSidebarLocationIcons()
        }
        .onChange(of: mountedVolumes.map(\.id)) {
            warmSidebarLocationIcons()
        }
        .onChange(of: store.pinnedDirectories.map(\.path)) {
            warmSidebarLocationIcons()
        }
        .onChange(of: store.recentDirectories.map(\.path)) {
            warmSidebarLocationIcons()
        }
    }

    private func warmSidebarLocationIcons() {
        let urls = [store.currentURL]
            + store.tabs.map(\.currentURL)
            + store.sidebarPathComponents.map(\.url).map(Optional.some)
            + FavoriteLocation.defaults.map(\.url).map(Optional.some)
            + uniqueMountedVolumes.map(\.url).map(Optional.some)
            + store.pinnedDirectories.map(Optional.some)

        Task {
            await FileIconLibrary.warmLocationIcons(for: urls, limit: 260)
        }
    }

    private var uniqueMountedVolumes: [FavoriteLocation] {
        var seenPaths: Set<String> = []
        return mountedVolumes.filter { location in
            seenPaths.insert(location.url.standardizedFileURL.path).inserted
        }
    }

    private func refreshMountedVolumes() async {
        let volumes = await Task.detached(priority: .utility) {
            FavoriteLocation.mountedVolumes()
        }.value

        mountedVolumes = volumes
    }

    private func sidebarExpansionBinding(for url: URL) -> Binding<Bool> {
        let id = SidebarView.sidebarNodeID(for: url)

        return Binding {
            expandedSidebarNodeIDs.contains(id)
        } set: { isExpanded in
            if isExpanded {
                expandedSidebarNodeIDs.insert(id)
                store.setSidebarExpandedPath(id, isExpanded: true)
                loadSidebarChildren(for: url)
            } else {
                expandedSidebarNodeIDs.remove(id)
                store.setSidebarExpandedPath(id, isExpanded: false)
            }
        }
    }

    private func restorePersistedSidebarExpansionIfNeeded() {
        guard !restoredPersistedSidebarExpansion else {
            return
        }

        restoredPersistedSidebarExpansion = true
        expandedSidebarNodeIDs.formUnion(store.sidebarExpandedPaths)
    }

    private func expandDefaultSidebarRoots() {
        guard let homeURL = FavoriteLocation.defaults.first(where: { $0.name == "Home" })?.url else {
            return
        }

        let homeID = Self.sidebarNodeID(for: homeURL)
        expandedSidebarNodeIDs.insert(homeID)
        loadSidebarChildren(for: homeURL)
    }

    private func sidebarChildren(for url: URL) -> [BrowserPathComponent] {
        sidebarChildrenByID[SidebarView.sidebarNodeID(for: url)] ?? []
    }

    private func sidebarIsLoading(_ url: URL) -> Bool {
        loadingSidebarNodeIDs.contains(SidebarView.sidebarNodeID(for: url))
    }

    private func loadSidebarChildren(for url: URL) {
        let standardizedURL = url.standardizedFileURL
        let id = SidebarView.sidebarNodeID(for: standardizedURL)

        guard sidebarChildrenByID[id] == nil, !loadingSidebarNodeIDs.contains(id) else {
            return
        }

        let showHiddenFiles = store.showHiddenFiles
        let preferredDescendantURL = store.currentURL?.standardizedFileURL
        loadingSidebarNodeIDs.insert(id)

        Task {
            let children = await Self.loadSidebarChildFolders(
                for: standardizedURL,
                includingHidden: showHiddenFiles,
                preferredDescendantURL: preferredDescendantURL
            )

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                sidebarChildrenByID[id] = children
                loadingSidebarNodeIDs.remove(id)
                warmSidebarLocationIcons()
            }
        }
    }

    private func reloadExpandedSidebarChildren() {
        let expandedURLs = expandedSidebarNodeIDs.map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
        }

        sidebarChildrenByID.removeAll()
        loadingSidebarNodeIDs.removeAll()

        for url in expandedURLs {
            loadSidebarChildren(for: url)
        }
    }

    private func revealCurrentSidebarScope() {
        guard let currentURL = store.currentURL else {
            return
        }

        let candidates = FavoriteLocation.defaults.map { SidebarRevealCandidate(url: $0.url) }
            + store.pinnedDirectories.map { SidebarRevealCandidate(url: $0) }
            + mountedVolumes.map {
                SidebarRevealCandidate(
                    url: $0.url,
                    includesRootDescendants: $0.url.standardizedFileURL.path == "/"
                )
            }

        guard let revealURL = SidebarRevealTarget.bestCandidateURL(for: currentURL, in: candidates) else {
            return
        }

        let revealChain = SidebarRevealPath.ancestorURLsToExpand(
            for: currentURL,
            from: revealURL,
            maximumDepth: 8
        )

        for url in revealChain {
            let id = Self.sidebarNodeID(for: url)
            expandedSidebarNodeIDs.insert(id)
            loadSidebarChildren(for: url)
        }
    }

    private static func sidebarNodeID(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private static func loadSidebarChildFolders(
        for directoryURL: URL,
        includingHidden: Bool,
        limit: Int = 60,
        preferredDescendantURL: URL? = nil
    ) async -> [BrowserPathComponent] {
        await Task.detached(priority: .utility) {
            let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey, .isPackageKey, .localizedNameKey]
            var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
            if !includingHidden {
                options.insert(.skipsHiddenFiles)
            }

            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: options
            ) else {
                return []
            }

            let folders = urls.compactMap { url -> BrowserPathComponent? in
                let values = try? url.resourceValues(forKeys: resourceKeys)
                guard values?.isDirectory == true, values?.isPackage != true else {
                    return nil
                }

                if !includingHidden, values?.isHidden == true {
                    return nil
                }

                return BrowserPathComponent(
                    name: values?.localizedName ?? url.lastPathComponent,
                    url: url.standardizedFileURL
                )
            }

            let sortedFolders = folders
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            return SidebarChildListResolver.visibleFolders(
                sortedFolders,
                inside: directoryURL,
                limit: limit,
                preferredDescendantURL: preferredDescendantURL
            )
        }.value
    }

    fileprivate static func currentLocation(
        _ currentURL: URL?,
        isInside candidateURL: URL,
        includesRootDescendants: Bool = false
    ) -> Bool {
        guard let currentPath = currentURL?.standardizedFileURL.path else {
            return false
        }

        let candidatePath = candidateURL.standardizedFileURL.path
        if candidatePath == "/" {
            return includesRootDescendants ? currentPath.hasPrefix("/") : currentPath == "/"
        }

        return currentPath == candidatePath || currentPath.hasPrefix(candidatePath + "/")
    }

    fileprivate static func activeDetail(
        for currentURL: URL?,
        inside candidateURL: URL,
        includesRootDescendants: Bool = false
    ) -> String? {
        guard currentLocation(currentURL, isInside: candidateURL, includesRootDescendants: includesRootDescendants),
              let currentPath = currentURL?.standardizedFileURL.path else {
            return nil
        }

        let candidatePath = candidateURL.standardizedFileURL.path
        guard currentPath != candidatePath else {
            return "Current"
        }

        let prefixLength = candidatePath == "/" ? candidatePath.count : candidatePath.count + 1
        let relativePath = String(currentPath.dropFirst(prefixLength))
        let parts = relativePath.split(separator: "/").map(String.init)
        guard !parts.isEmpty else {
            return "Current"
        }

        let visibleTail = parts.suffix(2).joined(separator: "/")
        return parts.count > 2 ? "Inside .../\(visibleTail)" : "Inside \(visibleTail)"
    }

    private static func activeLocationLabel(
        for currentURL: URL?,
        mountedVolumes: [FavoriteLocation],
        pinnedDirectories: [URL],
        recentDirectories: [URL]
    ) -> String? {
        guard let currentURL else {
            return nil
        }

        let fixedScopes = (FavoriteLocation.defaults + mountedVolumes).map { location in
            SidebarActiveScopeCandidate(
                url: location.url,
                exactPrefix: "Current in",
                insidePrefix: "Inside",
                name: location.name,
                includesRootDescendants: location.url.standardizedFileURL.path == "/"
            )
        }
        let pinnedScopes = pinnedDirectories.map { url in
            SidebarActiveScopeCandidate(
                url: url,
                exactPrefix: "Pinned",
                insidePrefix: "Inside pinned",
                name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
            )
        }
        let recentScopes = recentDirectories.map { url in
            SidebarActiveScopeCandidate(
                url: url,
                exactPrefix: "Recent",
                insidePrefix: "Inside recent",
                name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
            )
        }

        return (fixedScopes + pinnedScopes + recentScopes)
            .filter {
                currentLocation(
                    currentURL,
                    isInside: $0.url,
                    includesRootDescendants: $0.includesRootDescendants
                )
            }
            .max { lhs, rhs in
                let lhsPath = lhs.url.standardizedFileURL.path
                let rhsPath = rhs.url.standardizedFileURL.path
                if lhsPath.count == rhsPath.count {
                    return lhs.priority < rhs.priority
                }
                return lhsPath.count < rhsPath.count
            }
            .map { candidate in
                activeScopeLabel(
                    currentURL: currentURL,
                    scopeURL: candidate.url,
                    exactPrefix: candidate.exactPrefix,
                    insidePrefix: candidate.insidePrefix,
                    name: candidate.name
                )
            }
    }

    private static func primaryActiveRootPath(
        for currentURL: URL?,
        mountedVolumes: [FavoriteLocation],
        pinnedDirectories: [URL],
        recentDirectories: [URL]
    ) -> String? {
        SidebarScopeResolver.primaryActiveRootPath(
            for: currentURL,
            mountedVolumes: mountedVolumes.map(\.url),
            pinnedDirectories: pinnedDirectories,
            recentDirectories: recentDirectories
        )
    }

    private static func activeScopeLabel(
        currentURL: URL,
        scopeURL: URL,
        exactPrefix: String,
        insidePrefix: String,
        name: String
    ) -> String {
        let currentPath = currentURL.standardizedFileURL.path
        let scopePath = scopeURL.standardizedFileURL.path
        let prefix = currentPath == scopePath ? exactPrefix : insidePrefix
        return "\(prefix) \(name)"
    }

}

private struct SidebarActiveScopeCandidate {
    let url: URL
    let exactPrefix: String
    let insidePrefix: String
    let name: String
    var includesRootDescendants = false

    var priority: Int {
        switch exactPrefix {
        case "Pinned":
            return 3
        case "Recent":
            return 2
        default:
            return 1
        }
    }
}

private struct SidebarGroupDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.22))
            .frame(height: 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
    }
}

private struct SidebarSectionHeader: View {
    let title: String
    let isActive: Bool
    let detail: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .textCase(.uppercase)

            if isActive, let detail {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)

                    Image(systemName: detail.hasPrefix("Current") ? "location.fill" : "arrow.turn.down.right")
                        .font(.system(size: 8, weight: .bold))

                    Text(detail)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(.tint)
                .padding(.horizontal, 6)
                .frame(height: 17)
                .frame(maxWidth: 164)
                .background(Color.accentColor.opacity(0.10), in: Capsule())
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct CommandBar: View {
    @Bindable var store: BrowserStore
    @Binding var showsNavigationPane: Bool
    @Binding var isEditingPath: Bool

    var body: some View {
        VStack(spacing: 0) {
            ExplorerCommandRow(store: store, showsNavigationPane: $showsNavigationPane)
            AddressRow(store: store, isEditingPath: $isEditingPath)

            if store.hasVisibleFilterSummary {
                FilterBar(store: store)
            }
        }
        .controlSize(.small)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ExplorerCommandRow: View {
    @Bindable var store: BrowserStore
    @Binding var showsNavigationPane: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            commandControls(showsPrimaryActions: true, showsTitles: true)
            commandControls(showsPrimaryActions: true, showsTitles: false)
            commandControls(showsPrimaryActions: false, showsTitles: false)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.10))
                .frame(height: 1)
        }
    }

    private func commandControls(showsPrimaryActions: Bool, showsTitles: Bool) -> some View {
        HStack(spacing: 4) {
            CommandBarGroup {
                CommandButton(
                    title: showsNavigationPane ? "Hide pane" : "Show pane",
                    systemImage: showsNavigationPane ? "sidebar.left" : "sidebar.leading",
                    showsTitle: false
                ) {
                    showsNavigationPane.toggle()
                }
                .help("Navigation pane (Command-B)")
            }

            if showsPrimaryActions {
                CommandBarGroup {
                    Menu {
                        Button("Folder") {
                            store.createFolder()
                        }

                        Button("File") {
                            store.createFile()
                        }
                    } label: {
                        CommandMenuLabel(
                            title: "New",
                            systemImage: "plus",
                            showsTitle: showsTitles,
                            prominence: .primary
                        )
                    }
                    .menuStyle(.borderlessButton)
                }

                CommandBarGroup {
                    CommandButton(title: "Cut", systemImage: "scissors", showsTitle: showsTitles) {
                        store.cutSelectedItems()
                    }
                    .disabled(!store.hasSelection)

                    CommandButton(title: "Copy", systemImage: "doc.on.doc", showsTitle: showsTitles) {
                        store.copySelectedItems()
                    }
                    .disabled(!store.hasSelection)

                    CommandButton(title: "Paste", systemImage: "doc.on.clipboard", showsTitle: showsTitles) {
                        store.pasteItems()
                    }
                    .disabled(!store.canPasteItems)
                }

                CommandBarGroup {
                    CommandButton(title: "Rename", systemImage: "pencil", showsTitle: showsTitles) {
                        store.renameSelectedItem()
                    }
                    .disabled(store.selectedItems.count != 1)

                    CommandButton(title: "Share", systemImage: "square.and.arrow.up", showsTitle: showsTitles) {
                        store.shareSelectedItems()
                    }
                    .disabled(!store.hasSelection)

                    CommandButton(title: "Delete", systemImage: "trash", showsTitle: showsTitles) {
                        store.moveSelectedItemToTrash()
                    }
                    .disabled(!store.hasSelection)

                    ActionsMenu(store: store, showsTitle: showsTitles)
                }
            }

            CommandBarGroup(showsDivider: false, tone: .viewControls) {
                ViewModeSegmentedControl(store: store)
                    .fixedSize(horizontal: true, vertical: false)
                SortMenu(store: store, showsTitle: showsTitles)
                FilterMenu(store: store, showsTitle: showsTitles)
                ViewMenu(store: store, showsNavigationPane: $showsNavigationPane, showsTitle: showsTitles)
                MoreMenu(store: store, showsTitle: showsTitles)
            }
        }
    }
}

private struct CommandBarGroup<Content: View>: View {
    enum Tone {
        case standard
        case viewControls
    }

    let showsDivider: Bool
    let tone: Tone
    let content: Content

    init(showsDivider: Bool = true, tone: Tone = .standard, @ViewBuilder content: () -> Content) {
        self.showsDivider = showsDivider
        self.tone = tone
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: tone == .viewControls ? 1 : 2) {
                content
            }
            .padding(.horizontal, tone == .viewControls ? 2 : 0)
            .padding(.vertical, tone == .viewControls ? 1 : 0)
            .background(groupBackground, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(groupStroke)
            }

            if showsDivider {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.16))
                    .frame(width: 1, height: 20)
                    .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal, 0)
        .padding(.vertical, 0)
    }

    private var groupBackground: Color {
        switch tone {
        case .standard:
            return Color.clear
        case .viewControls:
            return Color(nsColor: .textBackgroundColor).opacity(0.50)
        }
    }

    private var groupStroke: Color {
        switch tone {
        case .standard:
            return Color.clear
        case .viewControls:
            return Color(nsColor: .separatorColor).opacity(0.16)
        }
    }
}

private struct AddressRow: View {
    @Bindable var store: BrowserStore
    @Binding var isEditingPath: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            addressControls(usesCompactSearch: false)
            addressControls(usesCompactSearch: true)
        }
        .padding(.horizontal, 8)
        .padding(.top, 5)
        .padding(.bottom, 5)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.14))
                .frame(height: 1)
        }
        .onChange(of: store.focusRequest) {
            guard store.focusRequest?.target == .addressBar else {
                return
            }

            store.pathInput = store.currentURL?.path ?? store.pathInput
            isEditingPath = true
        }
    }

    private func addressControls(usesCompactSearch: Bool) -> some View {
        HStack(spacing: 7) {
            HStack(spacing: 0) {
                NavigationButton(systemImage: "chevron.left", help: "Back") {
                    store.goBack()
                }
                .disabled(!store.canGoBack)

                NavigationButton(systemImage: "chevron.right", help: "Forward") {
                    store.goForward()
                }
                .disabled(!store.canGoForward)

                NavigationButton(systemImage: "chevron.up", help: "Up") {
                    store.goUp()
                }
                .disabled(store.currentURL?.path == "/")
            }
            .padding(1)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.66), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.18))
            }
            .fixedSize(horizontal: true, vertical: false)

            PathBar(store: store, isEditingPath: $isEditingPath)
                .layoutPriority(4)

            SearchField(store: store, isCompact: usesCompactSearch)
                .layoutPriority(1)
        }
    }
}

private struct ViewModeSegmentedControl: View {
    @Bindable var store: BrowserStore
    @State private var hoveringMode: FileViewMode?

    var body: some View {
        HStack(spacing: 1) {
            ForEach(FileViewMode.allCases) { mode in
                Button {
                    store.viewMode = mode
                } label: {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 12, weight: store.viewMode == mode ? .semibold : .medium))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 26, height: 23)
                        .foregroundStyle(store.viewMode == mode ? Color.accentColor : Color.secondary)
                        .background(segmentBackground(for: mode), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("\(mode.label) view")
                .accessibilityLabel("\(mode.label) view")
                .accessibilityValue(store.viewMode == mode ? "Selected" : "")
                .onHover { isHovering in
                    hoveringMode = isHovering ? mode : nil
                }
            }
        }
        .padding(1)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.70), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.18))
        }
    }

    private func segmentBackground(for mode: FileViewMode) -> Color {
        if store.viewMode == mode {
            return Color.accentColor.opacity(0.14)
        }

        if hoveringMode == mode {
            return Color(nsColor: .separatorColor).opacity(0.14)
        }

        return .clear
    }
}

private struct SidebarTreeLocationButton: View {
    let store: BrowserStore
    let title: String
    let subtitle: String?
    let url: URL
    let fallbackSystemImage: String
    var volumeSummary: VolumeStatusSummary? = nil
    let isActive: Bool
    let isPrimaryActive: Bool
    let activeDetail: String?
    let currentURL: URL?
    let isPinnedLocation: Bool
    @Binding var isExpanded: Bool
    let children: [BrowserPathComponent]
    let isLoading: Bool
    let onExpand: () -> Void
    let childExpansion: (URL) -> Binding<Bool>
    let childChildren: (URL) -> [BrowserPathComponent]
    let childIsLoading: (URL) -> Bool
    let childOnExpand: (URL) -> Void
    @State private var isHovering = false

    var body: some View {
        Button {
            store.open(url)
        } label: {
            SidebarTreeLocationLabel(
                title: title,
                subtitle: subtitle,
                url: url,
                fallbackSystemImage: fallbackSystemImage,
                volumeSummary: volumeSummary,
                isActive: isActive,
                isPrimaryActive: isPrimaryActive,
                activeDetail: activeDetail,
                isHovering: isHovering
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .sidebarFileDropTarget(store: store, destinationURL: url)
        .contextMenu {
            SidebarLocationContextMenu(store: store, url: url, isPinnedLocation: isPinnedLocation)
        }
        .accessibilityHint("Opens \(title)")
    }
}

private struct SidebarCurrentRouteStack: View {
    let store: BrowserStore
    let currentURL: URL
    let rootURL: URL

    var body: some View {
        let route = SidebarCurrentRouteResolver.visibleRouteComponents(from: rootURL, to: currentURL)

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "location.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tint)

                Text("You are here")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tint)
                    .textCase(.uppercase)
                    .lineLimit(1)

                Text(rootName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Rectangle()
                    .fill(Color.accentColor.opacity(0.24))
                    .frame(height: 1)
            }
            .padding(.leading, 25)
            .padding(.trailing, 8)
            .padding(.top, 3)

            ForEach(Array(route.enumerated()), id: \.element.id) { index, component in
                SidebarCurrentRouteNodeButton(
                    store: store,
                    component: component,
                    depth: index,
                    isCurrent: component.url.standardizedFileURL.path == currentURL.standardizedFileURL.path
                )
            }
        }
        .padding(.vertical, 3)
        .background(Color(nsColor: .selectedContentBackgroundColor).opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.24))
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 3)
                .padding(.vertical, 5)
        }
        .padding(.leading, 4)
        .padding(.trailing, 2)
    }

    private var rootName: String {
        rootURL.lastPathComponent.isEmpty ? rootURL.path : rootURL.lastPathComponent
    }
}

private struct SidebarCurrentRouteNodeButton: View {
    let store: BrowserStore
    let component: BrowserPathComponent
    let depth: Int
    let isCurrent: Bool

    var body: some View {
        Button {
            store.open(component.url)
        } label: {
            HStack(spacing: 7) {
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(isCurrent ? Color.clear : Color.accentColor.opacity(0.24))
                        .frame(width: 1)
                        .offset(y: 9)

                    Circle()
                        .fill(isCurrent ? Color.accentColor : Color.accentColor.opacity(0.42))
                        .frame(width: isCurrent ? 7 : 5, height: isCurrent ? 7 : 5)
                        .padding(.top, 5)
                }
                .frame(width: 12, height: 20)
                .padding(.leading, CGFloat(min(depth, 3)) * 7)

                SidebarNativeIcon(url: component.url, fallbackSystemImage: "folder", size: isCurrent ? 15 : 13, isActive: isCurrent)

                Text(store.masksSensitiveData ? "Private" : component.name)
                    .font(.system(size: isCurrent ? 11 : 10, weight: isCurrent ? .semibold : .medium))
                    .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)

                SidebarActiveIndicator(activeDetail: isCurrent ? "Current" : nil, isActive: isCurrent)
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, isCurrent ? 3 : 2)
            .background(isCurrent ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.68) : Color.clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(isCurrent ? Color.accentColor.opacity(0.56) : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
        .sidebarFileDropTarget(store: store, destinationURL: component.url)
        .contextMenu {
            SidebarLocationContextMenu(store: store, url: component.url, isPinnedLocation: store.isPinnedDirectory(component.url))
        }
        .accessibilityLabel(isCurrent ? "Current location \(component.name)" : "Open \(component.name)")
    }
}

private struct SidebarTreeLocationLabel: View {
    let title: String
    let subtitle: String?
    let url: URL
    let fallbackSystemImage: String
    var volumeSummary: VolumeStatusSummary? = nil
    let isActive: Bool
    let isPrimaryActive: Bool
    let activeDetail: String?
    let isHovering: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            SidebarNativeIcon(url: url, fallbackSystemImage: fallbackSystemImage, size: 17, isActive: isVisiblyActive)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: isVisiblyActive ? .semibold : .medium))
                    .foregroundStyle(isVisiblyActive ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let volumeSummary {
                    Text(volumeSummary.statusLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let usedFraction = volumeSummary.usedFraction {
                        VolumeUsageBar(usedFraction: usedFraction)
                            .frame(maxWidth: 118)
                            .padding(.top, 2)
                    }
                }

            }

            Spacer(minLength: 0)

            if isVisiblyActive {
                Circle()
                    .fill(Color.accentColor.opacity(isPrimaryActive ? 0.86 : 0.38))
                    .frame(width: isPrimaryActive ? 5 : 4, height: isPrimaryActive ? 5 : 4)
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, 8)
        .padding(.vertical, 2)
        .frame(minHeight: volumeSummary == nil ? 32 : 48)
        .background(
            sidebarActiveBackground,
            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(sidebarActiveStroke)
        }
        .overlay(alignment: .leading) {
            if isVisiblyActive {
                Rectangle()
                    .fill(isPrimaryActive ? Color.accentColor : Color.accentColor.opacity(0.42))
                    .frame(width: 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isVisiblyActive: Bool {
        isActive || isPrimaryActive
    }

    private var sidebarActiveBackground: Color {
        if isVisiblyActive {
            return isPrimaryActive
                ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.44)
                : Color(nsColor: .selectedContentBackgroundColor).opacity(0.18)
        }

        if isHovering {
            return Color(nsColor: .selectedContentBackgroundColor).opacity(0.10)
        }

        return .clear
    }

    private var sidebarActiveStroke: Color {
        if isVisiblyActive {
            return Color(nsColor: .separatorColor).opacity(0.14)
        }

        return Color(nsColor: .separatorColor).opacity(isHovering ? 0.12 : 0)
    }

    private var iconBackground: Color {
        if isVisiblyActive {
            return Color.accentColor.opacity(0.12)
        }

        if isHovering {
            return Color(nsColor: .separatorColor).opacity(0.12)
        }

        return .clear
    }
}

private struct SidebarAnchorBar: View {
    let store: BrowserStore
    let currentURL: URL?

    private var homeURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    private var computerURL: URL {
        URL(fileURLWithPath: "/", isDirectory: true)
    }

    private var networkURL: URL {
        URL(fileURLWithPath: "/Network", isDirectory: true)
    }

    var body: some View {
        HStack(spacing: 3) {
            SidebarAnchorButton(
                title: "Home",
                url: homeURL,
                fallbackSystemImage: "house",
                isActive: LocationScopeResolver.isScopeActive(
                    .home,
                    for: currentURL,
                    homeURL: homeURL,
                    networkURL: networkURL
                )
            ) {
                store.openHomeDirectory()
            }

            SidebarAnchorButton(
                title: "This Mac",
                url: computerURL,
                fallbackSystemImage: "desktopcomputer",
                isActive: LocationScopeResolver.isScopeActive(
                    .thisMac,
                    for: currentURL,
                    homeURL: homeURL,
                    networkURL: networkURL
                )
            ) {
                store.openComputerRoot()
            }

            SidebarAnchorButton(
                title: "Network",
                url: networkURL,
                fallbackSystemImage: "network",
                isActive: LocationScopeResolver.isScopeActive(
                    .network,
                    for: currentURL,
                    homeURL: homeURL,
                    networkURL: networkURL
                )
            ) {
                store.openNetworkRoot()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SidebarAnchorButton: View {
    let title: String
    let url: URL
    let fallbackSystemImage: String
    let isActive: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                LocationIconImage(
                    url: url,
                    fallbackSystemImage: fallbackSystemImage,
                    size: 15,
                    showsApplicationBadge: false
                )
                .frame(width: 16, height: 16)

                Text(title)
                    .font(.system(size: 10, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(background, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(stroke)
            }
            .overlay(alignment: .leading) {
                if isActive {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 3)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(isActive ? "Selected" : "")
        .onHover { isHovering = $0 }
    }

    private var background: Color {
        if isActive {
            return Color(nsColor: .selectedContentBackgroundColor).opacity(0.52)
        }

        if isHovering {
            return Color(nsColor: .selectedContentBackgroundColor).opacity(0.14)
        }

        return Color.clear
    }

    private var stroke: Color {
        if isActive {
            return Color.accentColor.opacity(0.42)
        }

        return Color(nsColor: .separatorColor).opacity(isHovering ? 0.28 : 0.16)
    }
}

private struct VolumeUsageBar: View {
    let usedFraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .separatorColor).opacity(0.20))

                Capsule()
                    .fill(barColor)
                    .frame(width: proxy.size.width * usedFraction)
            }
        }
        .frame(height: 4)
        .accessibilityLabel("Volume used")
        .accessibilityValue("\(Int((usedFraction * 100).rounded())) percent")
    }

    private var barColor: Color {
        if usedFraction >= 0.90 {
            return .red
        }

        if usedFraction >= 0.75 {
            return .orange
        }

        return .accentColor
    }
}

private struct SidebarTreeFolderNode: View {
    let store: BrowserStore
    let component: BrowserPathComponent
    let depth: Int
    let currentURL: URL?
    @Binding var isExpanded: Bool
    let children: [BrowserPathComponent]
    let isLoading: Bool
    let onExpand: () -> Void
    let childExpansion: (URL) -> Binding<Bool>
    let childChildren: (URL) -> [BrowserPathComponent]
    let childIsLoading: (URL) -> Bool
    let childOnExpand: (URL) -> Void
    let isActive: Bool
    let activeDetail: String?

    var body: some View {
        if depth >= Self.maximumDepth {
            folderButton
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                if isLoading {
                    sidebarLoadingRow
                } else if children.isEmpty {
                    sidebarEmptyRow
                } else {
                    ForEach(children) { child in
                        SidebarTreeFolderNode(
                            store: store,
                            component: child,
                            depth: depth + 1,
                            currentURL: currentURL,
                            isExpanded: childExpansion(child.url),
                            children: childChildren(child.url),
                            isLoading: childIsLoading(child.url),
                            onExpand: { childOnExpand(child.url) },
                            childExpansion: childExpansion,
                            childChildren: childChildren,
                            childIsLoading: childIsLoading,
                            childOnExpand: childOnExpand,
                            isActive: SidebarView.currentLocation(currentURL, isInside: child.url),
                            activeDetail: SidebarView.activeDetail(for: currentURL, inside: child.url)
                        )
                    }
                }
            } label: {
                folderButton
            }
            .onChange(of: isExpanded) {
                if isExpanded {
                    onExpand()
                }
            }
            .task(id: isExpanded) {
                if isExpanded {
                    onExpand()
                }
            }
        }
    }

    private var folderButton: some View {
        Button {
            store.open(component.url)
        } label: {
            HStack(spacing: 7) {
                SidebarNativeIcon(url: component.url, fallbackSystemImage: "folder", size: 15, isActive: isActive)

                VStack(alignment: .leading, spacing: 1) {
                    Text(store.masksSensitiveData ? "Private Folder" : component.name)
                        .font(isActive ? .caption.weight(.semibold) : .caption)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if isActive, let activeDetail {
                        Text(activeDetail)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tint)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 0)

                SidebarActiveIndicator(activeDetail: activeDetail, isActive: isActive)
            }
            .padding(.leading, CGFloat(20 + min(depth, 6) * 13))
            .padding(.trailing, 6)
            .padding(.vertical, 4)
            .background(sidebarActiveBackground, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(sidebarActiveStroke)
            }
            .overlay(alignment: .leading) {
                if isActive {
                    Rectangle()
                        .fill(isCurrent ? Color.accentColor : Color.accentColor.opacity(0.58))
                        .frame(width: 3)
                        .padding(.leading, CGFloat(max(0, min(depth, 6) - 1) * 13))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .sidebarFileDropTarget(store: store, destinationURL: component.url)
        .contextMenu {
            SidebarLocationContextMenu(store: store, url: component.url, isPinnedLocation: store.isPinnedDirectory(component.url))
        }
        .accessibilityHint("Opens \(component.name)")
    }

    private var sidebarLoadingRow: some View {
        HStack(spacing: 7) {
            ProgressView()
                .controlSize(.small)

            Text("Loading folders")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.leading, CGFloat(35 + min(depth, 6) * 13))
        .padding(.vertical, 4)
    }

    private var sidebarEmptyRow: some View {
        Text("No folders")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.leading, CGFloat(35 + min(depth, 6) * 13))
            .padding(.vertical, 4)
    }

    private var isCurrent: Bool {
        activeDetail == "Current"
    }

    private var sidebarActiveBackground: Color {
        guard isActive else {
            return .clear
        }

        return isCurrent
            ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.52)
            : Color(nsColor: .selectedContentBackgroundColor).opacity(0.26)
    }

    private var sidebarActiveStroke: Color {
        guard isActive else {
            return .clear
        }

        return isCurrent ? Color.accentColor.opacity(0.54) : Color.accentColor.opacity(0.24)
    }

    private static let maximumDepth = 8
}

private struct SidebarLocationButton: View {
    let store: BrowserStore
    let location: FavoriteLocation
    let isActive: Bool
    let activeDetail: String?

    var body: some View {
        Button {
            store.open(location.url)
        } label: {
            HStack(spacing: 8) {
                SidebarNativeIcon(url: location.url, fallbackSystemImage: location.systemImage, size: 16, isActive: isActive)

                VStack(alignment: .leading, spacing: 1) {
                    Text(store.masksSensitiveData ? "Private Folder" : location.name)
                        .lineLimit(1)

                    if isActive, let activeDetail {
                        Text(activeDetail)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tint)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 0)

                SidebarActiveIndicator(activeDetail: activeDetail, isActive: isActive)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                sidebarActiveBackground,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(sidebarActiveStroke)
            }
            .overlay(alignment: .leading) {
                if isCurrent {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 3)
                }
            }
        }
        .buttonStyle(.plain)
        .sidebarFileDropTarget(store: store, destinationURL: location.url)
        .contextMenu {
            SidebarLocationContextMenu(store: store, url: location.url, isPinnedLocation: store.isPinnedDirectory(location.url))
        }
        .accessibilityHint("Opens \(location.name)")
    }

    private var isCurrent: Bool {
        activeDetail == "Current"
    }

    private var sidebarActiveBackground: Color {
        guard isActive else {
            return .clear
        }

        return isCurrent ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.54) : Color(nsColor: .selectedContentBackgroundColor).opacity(0.24)
    }

    private var sidebarActiveStroke: Color {
        guard isActive else {
            return .clear
        }

        return isCurrent ? Color.accentColor.opacity(0.48) : Color.accentColor.opacity(0.18)
    }
}

private struct SidebarCurrentLocationButton: View {
    let store: BrowserStore
    let currentURL: URL
    let scopeLabel: String?
    let itemCount: Int
    let logoItems: [FileItem]
    let selectedCount: Int
    let isLoading: Bool

    var body: some View {
        Button {
            store.open(currentURL)
        } label: {
            HStack(alignment: .center, spacing: 7) {
                SidebarNativeIcon(url: currentURL, fallbackSystemImage: "folder", size: 18, isActive: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(store.displayName(for: currentURL))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 6) {
                        if let scopeLabel {
                            Text(scopeLabel)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.tint)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Text(statusText)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(isLoading ? Color.accentColor : Color.secondary)
                            .lineLimit(1)
                            .layoutPriority(1)

                        if selectedCount > 0 {
                            Text(selectionText)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tint)
                                .lineLimit(1)
                                .padding(.horizontal, 5)
                                .frame(height: 15)
                                .background(Color.accentColor.opacity(0.10), in: Capsule())
                        }

                        FolderTypeLogoStack(items: logoItems, iconSize: 12, maxLogos: 4, sampleLimit: 120)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(Color(nsColor: .selectedContentBackgroundColor).opacity(0.30), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.22))
            }
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .sidebarFileDropTarget(store: store, destinationURL: currentURL)
        .contextMenu {
            SidebarLocationContextMenu(store: store, url: currentURL, isPinnedLocation: store.isPinnedDirectory(currentURL))
        }
        .accessibilityHint("Shows the current folder")
        .accessibilityValue("\(statusText)\(selectedCount > 0 ? ", \(selectionText)" : "")")
    }

    private var statusText: String {
        if isLoading {
            return "Loading"
        }

        return itemCount == 1 ? "1 item" : "\(itemCount) items"
    }

    private var selectionText: String {
        selectedCount == 1 ? "1 selected" : "\(selectedCount) selected"
    }
}

private struct SidebarRecentLocationButton: View {
    let store: BrowserStore
    let url: URL
    let isActive: Bool
    let activeDetail: String?

    var body: some View {
        Button {
            store.open(url)
        } label: {
            HStack(spacing: 8) {
                SidebarNativeIcon(url: url, fallbackSystemImage: "clock.arrow.circlepath", size: 15, isActive: isActive)

                VStack(alignment: .leading, spacing: 1) {
                    Text(store.displayName(for: url))
                        .lineLimit(1)

                    Text(store.masksSensitiveData ? "Private path" : url.deletingLastPathComponent().path)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if isActive, let activeDetail {
                        Text(activeDetail)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tint)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 0)

                SidebarActiveIndicator(activeDetail: activeDetail, isActive: isActive)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(isActive ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.50) : Color.clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.34) : Color.clear)
            }
            .overlay(alignment: .leading) {
                if isActive {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 3)
                }
            }
        }
        .buttonStyle(.plain)
        .sidebarFileDropTarget(store: store, destinationURL: url)
        .contextMenu {
            SidebarLocationContextMenu(store: store, url: url, isPinnedLocation: store.isPinnedDirectory(url))
        }
        .accessibilityHint("Opens recent folder")
    }
}

private struct SidebarPinnedLocationButton: View {
    let store: BrowserStore
    let url: URL
    let isActive: Bool
    let activeDetail: String?

    var body: some View {
        Button {
            store.open(url)
        } label: {
            HStack(spacing: 8) {
                SidebarNativeIcon(url: url, fallbackSystemImage: "pin", size: 15, isActive: isActive)

                VStack(alignment: .leading, spacing: 1) {
                    Text(store.displayName(for: url))
                        .lineLimit(1)

                    Text(store.masksSensitiveData ? "Private path" : url.deletingLastPathComponent().path)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if isActive, let activeDetail {
                        Text(activeDetail)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tint)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 0)

                if isActive {
                    SidebarActiveIndicator(activeDetail: activeDetail, isActive: true)
                } else {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(isActive ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.50) : Color.clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.34) : Color.clear)
            }
            .overlay(alignment: .leading) {
                if isActive {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 3)
                }
            }
        }
        .buttonStyle(.plain)
        .sidebarFileDropTarget(store: store, destinationURL: url)
        .contextMenu {
            SidebarLocationContextMenu(store: store, url: url, isPinnedLocation: true)
        }
        .accessibilityHint("Opens pinned folder")
    }
}

private struct SidebarActiveIndicator: View {
    let activeDetail: String?
    let isActive: Bool

    var body: some View {
        if isActive, let activeDetail {
            HStack(spacing: 4) {
                Image(systemName: activeDetail == "Current" ? "location.fill" : "arrow.turn.down.right")
                    .font(.system(size: 8, weight: .bold))

                Text(indicatorText(for: activeDetail))
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(.tint)
            .padding(.horizontal, activeDetail == "Current" ? 6 : 6)
            .frame(height: 17)
            .frame(maxWidth: activeDetail == "Current" ? 72 : 150)
            .background(Color.accentColor.opacity(activeDetail == "Current" ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(activeDetail == "Current" ? 0.22 : 0.13))
            }
            .help(activeDetail)
            .accessibilityLabel(activeDetail == "Current" ? "Current location" : "Inside current location")
        }
    }

    private func indicatorText(for activeDetail: String) -> String {
        guard activeDetail != "Current" else {
            return "Current"
        }

        return activeDetail
    }
}

private struct SidebarNativeIcon: View {
    let url: URL
    let fallbackSystemImage: String
    let size: CGFloat
    let isActive: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.18))
                .frame(width: size + 8, height: size + 8)
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(
                            isActive ? Color.accentColor.opacity(0.26) : Color(nsColor: .separatorColor).opacity(0.10)
                        )
                }

            LocationIconImage(
                url: url,
                fallbackSystemImage: fallbackSystemImage,
                size: size,
                showsApplicationBadge: true
            )
        }
        .frame(width: size + 8, height: size + 8)
    }
}

private struct SidebarLocationContextMenu: View {
    let store: BrowserStore
    let url: URL
    let isPinnedLocation: Bool

    var body: some View {
        Button("Open in New Tab") {
            store.addTab(opening: url)
        }

        Button("Open in New Window") {
            BetterFilesWindowManager.openWindow(at: url)
        }

        Button("New Folder") {
            store.createFolder(in: url)
        }

        Button("New File") {
            store.createFile(in: url)
        }

        Button("Paste Here") {
            store.pasteItems(to: url)
        }
        .disabled(!store.canPasteItems)

        if store.isTrashDirectory(url) {
            Button("Empty Trash...", role: .destructive) {
                store.confirmEmptyTrash()
            }
            .disabled(!store.canEmptyTrash)
        }

        Divider()

        Button("Rename") {
            store.renameLocation(url)
        }
        .disabled(url.standardizedFileURL.path == "/")

        Button("Move to Trash", role: .destructive) {
            store.moveLocationToTrash(url)
        }
        .disabled(!store.canTrashLocation(url))

        if isPinnedLocation {
            Button("Unpin") {
                store.unpinDirectory(url)
            }
        } else {
            Button("Pin to Sidebar") {
                store.pinDirectory(url)
            }
        }

        Divider()

        Button("Copy Path") {
            store.copyPath(of: url)
        }

        Button("Copy as Path") {
            store.copyPathAsQuotedPath(of: url)
        }

        Button("Reveal in Finder") {
            store.revealInFinder(url)
        }

        Button("Open in Terminal") {
            store.openFolderInTerminal(url)
        }

        Button("Properties") {
            store.showProperties(for: url)
        }
    }
}

private final class FileDropURLAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        urls.append(url)
        lock.unlock()
    }

    func snapshot() -> [URL] {
        lock.lock()
        let urls = urls
        lock.unlock()
        return urls
    }
}

private enum FileDropProviderLoader {
    static func loadFileURLs(
        from providers: [NSItemProvider],
        completion: @escaping @MainActor ([URL]) -> Void
    ) {
        guard !providers.isEmpty else {
            return
        }

        let group = DispatchGroup()
        let accumulator = FileDropURLAccumulator()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let fileURL = FileTableView.fileURL(from: item) {
                    accumulator.append(fileURL)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let urls = accumulator.snapshot()
            guard !urls.isEmpty else {
                return
            }

            Task { @MainActor [urls] in
                completion(urls)
            }
        }
    }
}

private struct SidebarFileDropTargetModifier: ViewModifier {
    let store: BrowserStore
    let destinationURL: URL
    @State private var isDropTarget = false

    func body(content: Content) -> some View {
        content
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget) { providers in
                importDroppedItems(from: providers)
                return true
            }
            .overlay {
                if isDropTarget {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .allowsHitTesting(false)
                }
            }
    }

    private func importDroppedItems(from providers: [NSItemProvider]) {
        FileDropProviderLoader.loadFileURLs(from: providers) { droppedURLs in
            _ = store.dropItems(droppedURLs, to: destinationURL)
        }
    }
}

private struct TabStripFileURLDropTargetModifier: ViewModifier {
    let store: BrowserStore
    var targetTabID: BrowserTab.ID?
    @Binding var isTargeted: Bool

    func body(content: Content) -> some View {
        content.onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
            openDroppedURLs(from: providers)
            return true
        }
    }

    private func openDroppedURLs(from providers: [NSItemProvider]) {
        FileDropProviderLoader.loadFileURLs(from: providers) { droppedURLs in
            if let targetTabID {
                _ = store.openDroppedURLs(droppedURLs, inTab: targetTabID)
            } else {
                _ = store.openDroppedURLsInNewTabs(droppedURLs)
            }
        }
    }
}

private extension View {
    func tabStripFileURLDropTarget(store: BrowserStore, isTargeted: Binding<Bool>) -> some View {
        modifier(TabStripFileURLDropTargetModifier(store: store, targetTabID: nil, isTargeted: isTargeted))
    }

    func tabStripFileURLDropTarget(
        store: BrowserStore,
        targetTabID: BrowserTab.ID,
        isTargeted: Binding<Bool>
    ) -> some View {
        modifier(TabStripFileURLDropTargetModifier(store: store, targetTabID: targetTabID, isTargeted: isTargeted))
    }
}

private struct NavigationButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 27, height: 26)
                .background(
                    isHovering ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.16) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
        .onHover { isHovering = $0 }
    }
}

private struct NavigationHistoryMenu: View {
    let title: String
    let locations: [NavigationHistoryLocation]
    let action: (NavigationHistoryLocation) -> Void

    var body: some View {
        Menu {
            ForEach(locations) { location in
                Button {
                    action(location)
                } label: {
                    LocationMenuLabel(name: location.name, detail: location.detail, url: location.url)
                }
                .help(location.detail)
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct LocationMenuLabel: View {
    let name: String
    let detail: String
    let url: URL
    var fallbackSystemImage = "folder"
    var showsApplicationBadge = false

    var body: some View {
        HStack(spacing: 7) {
            LocationIconImage(
                url: url,
                fallbackSystemImage: fallbackSystemImage,
                size: 16,
                showsApplicationBadge: showsApplicationBadge
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .lineLimit(1)

                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

private struct CommandButton: View {
    let title: String
    let systemImage: String
    var showsTitle = true
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: showsTitle ? 14 : 16)

                if showsTitle {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
            .padding(.horizontal, showsTitle ? 6 : 5)
            .frame(minWidth: showsTitle ? 68 : 27, minHeight: 24)
            .foregroundStyle(foregroundStyle)
            .background(buttonBackground, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(buttonStroke)
            }
            .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .onHover { isHovering = $0 }
    }

    private var foregroundStyle: Color {
        guard isEnabled else {
            return Color.secondary.opacity(0.42)
        }

        return isHovering ? Color.primary : Color.secondary
    }

    private var buttonBackground: Color {
        guard isEnabled else {
            return Color.clear
        }

        guard isHovering else {
            return Color(nsColor: .controlBackgroundColor).opacity(0.001)
        }

        return Color(nsColor: .selectedContentBackgroundColor).opacity(0.13)
    }

    private var buttonStroke: Color {
        guard isEnabled, isHovering else {
            return Color.clear
        }

        return Color(nsColor: .separatorColor).opacity(0.24)
    }
}

private struct CommandMenuLabel: View {
    enum Prominence {
        case standard
        case primary
    }

    let title: String
    let systemImage: String
    var showsTitle = true
    var prominence: Prominence = .standard

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: prominence == .primary ? .semibold : .medium))
                .frame(width: showsTitle ? 16 : 18)
                .symbolRenderingMode(.hierarchical)

            if showsTitle {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, showsTitle ? (prominence == .primary ? 8 : 6) : 5)
        .frame(minWidth: showsTitle ? (prominence == .primary ? 54 : 46) : 27, minHeight: 23)
        .foregroundStyle(foregroundStyle)
        .background(buttonBackground, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(buttonStroke)
        }
        .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .help(title)
        .accessibilityLabel(title)
    }

    private var foregroundStyle: Color {
        switch prominence {
        case .standard:
            return .secondary
        case .primary:
            return .white
        }
    }

    private var buttonBackground: Color {
        switch prominence {
        case .standard:
            return Color(nsColor: .controlBackgroundColor).opacity(0.001)
        case .primary:
            return Color.accentColor
        }
    }

    private var buttonStroke: Color {
        switch prominence {
        case .standard:
            return .clear
        case .primary:
            return Color.white.opacity(0.22)
        }
    }
}

private struct SortMenu: View {
    @Bindable var store: BrowserStore
    var showsTitle = true

    var body: some View {
        Menu {
            ForEach(FileSortField.allCases) { field in
                Button {
                    store.setSortField(field)
                } label: {
                    if store.sortField == field {
                        Label(field.label, systemImage: store.sortAscending ? "arrow.up" : "arrow.down")
                    } else {
                        Text(field.label)
                    }
                }
            }
        } label: {
            CommandMenuLabel(title: "Sort", systemImage: "arrow.up.arrow.down", showsTitle: showsTitle)
        }
        .menuStyle(.borderlessButton)
    }
}

private struct ViewMenu: View {
    @Bindable var store: BrowserStore
    @Binding var showsNavigationPane: Bool
    var showsTitle = true

    var body: some View {
        Menu {
            Picker("Layout", selection: $store.viewMode) {
                ForEach(FileViewMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            Picker("Group By", selection: $store.groupField) {
                ForEach(FileGroupField.allCases) { field in
                    Text(field.label).tag(field)
                }
            }

            Divider()

            Toggle("File Name Extensions", isOn: $store.showFileExtensions)
            Toggle("Hidden Items", isOn: $store.showHiddenFiles)
            Toggle("Compact View", isOn: $store.compactView)
            Toggle("Group Folders First", isOn: $store.foldersFirst)
            Toggle("Item Checkboxes", isOn: $store.showsItemCheckboxes)
            Toggle("Navigation Pane", isOn: $showsNavigationPane)
                .keyboardShortcut("b", modifiers: [.command])
            Toggle("Details Pane", isOn: $store.showsDetailPanel)
            Toggle("Preview Pane", isOn: $store.showsPreviewPanel)

            Divider()

            Menu("Details Columns") {
                Toggle("Kind", isOn: $store.showsKindColumn)
                Toggle("Size", isOn: $store.showsSizeColumn)
                Toggle("Modified", isOn: $store.showsModifiedColumn)
                Toggle("Created", isOn: $store.showsCreatedColumn)
                Toggle("Accessed", isOn: $store.showsAccessedColumn)
                Toggle("Permissions", isOn: $store.showsPermissionsColumn)

                Divider()

                Button("Show All Columns") {
                    store.showAllDetailsColumns()
                }
                .disabled(store.usesDefaultDetailsColumns)
            }

            Divider()

            Button("Save View for This Folder") {
                store.saveCurrentFolderViewSettings()
            }

            Button("Clear Saved Folder View") {
                store.clearCurrentFolderViewSettings()
            }
            .disabled(!store.currentFolderHasSavedView)
        } label: {
            CommandMenuLabel(title: "View", systemImage: "square.grid.2x2", showsTitle: showsTitle)
        }
        .menuStyle(.borderlessButton)
    }
}

private struct FilterMenu: View {
    @Bindable var store: BrowserStore
    var showsTitle = true

    var body: some View {
        Menu {
            Picker("Kind", selection: $store.kindFilter) {
                ForEach(FileKindFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }

            Picker("Type", selection: $store.typeFilter) {
                ForEach(store.availableTypeFilters) { filter in
                    Text(filter.label).tag(filter)
                }
            }

            Picker("Modified", selection: $store.dateFilter) {
                ForEach(FileDateFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }

            Picker("Size", selection: $store.sizeFilter) {
                ForEach(FileSizeFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }

            Divider()

            Toggle("Search Subfolders", isOn: $store.searchesSubfolders)
            Toggle("Show Hidden Files", isOn: $store.showHiddenFiles)

            Divider()

            Button("Clear Search and Filters") {
                store.clearSearchAndContentFilters()
            }
            .disabled(!store.hasActiveContentFilters)
        } label: {
            CommandMenuLabel(title: "Filters", systemImage: "line.3.horizontal.decrease.circle", showsTitle: showsTitle)
        }
        .menuStyle(.borderlessButton)
        .help("Filter, group, and display options")
    }
}

private struct ActionsMenu: View {
    let store: BrowserStore
    var showsTitle = true

    var body: some View {
        Menu {
            Button("Preview") {
                store.quickLookSelectedItems()
            }
            .disabled(!store.hasSelection)

            Button("Properties") {
                store.showPropertiesForSelection()
            }
            .disabled(!store.hasSelection)

            Button("Set Tags...") {
                store.promptSetTagsForSelection()
            }
            .disabled(!store.hasSelection)

            Button("Clear Access Control List") {
                store.clearSelectedItemsAccessControl()
            }
            .disabled(!store.hasSelection)

            OpenWithMenu(store: store)
                .disabled(!store.hasSelection)

            Divider()

            Button("Duplicate") {
                store.duplicateSelectedItems()
            }
            .disabled(!store.hasSelection)

            Button("Make Alias") {
                store.createAliasesForSelection()
            }
            .disabled(!store.hasSelection)

            Button("Compress to Zip") {
                store.compressSelectedItems()
            }
            .disabled(!store.hasSelection)

            Button("Extract Zip") {
                store.extractSelectedArchives()
            }
            .disabled(!store.canExtractSelectedArchives)

            Divider()

            Button("Copy to Folder...") {
                store.copySelectedItemsToFolder()
            }
            .disabled(!store.hasSelection)

            Button("Move to Folder...") {
                store.moveSelectedItemsToFolder()
            }
            .disabled(!store.hasSelection)

            Button("Batch Rename") {
                store.batchRenameSelection()
            }
            .disabled(store.selectedItems.count < 2)
        } label: {
            CommandMenuLabel(title: "Actions", systemImage: "ellipsis.circle", showsTitle: showsTitle)
        }
        .menuStyle(.borderlessButton)
        .help("More file actions")
    }
}

private struct MoreMenu: View {
    @Bindable var store: BrowserStore
    var showsTitle = true

    var body: some View {
        Menu {
            Menu("New") {
                Button("Folder") {
                    store.createFolder()
                }
                .disabled(store.currentURL == nil)

                Button("File") {
                    store.createFile()
                }
                .disabled(store.currentURL == nil)
            }

            Button("Cut") {
                store.cutSelectedItems()
            }
            .disabled(!store.hasSelection)

            Button("Copy") {
                store.copySelectedItems()
            }
            .disabled(!store.hasSelection)

            Button("Paste") {
                store.pasteItems()
            }
            .disabled(!store.canPasteItems)

            Divider()

            Button("Open Folder...") {
                store.chooseFolder()
            }

            Button("Open Selection in New Tabs") {
                store.openSelectionInNewTabs()
            }
            .disabled(!store.canOpenSelectionInNewTabs)

            Button("Open Current Folder in New Tab") {
                store.openCurrentFolderInNewTab()
            }
            .disabled(!store.canOpenCurrentFolderInNewTab)

            Button("Open Parent Folder in New Tab") {
                store.openSelectionParentFoldersInNewTabs()
            }
            .disabled(!store.canOpenSelectionParentFoldersInNewTabs)

            Button("Open File Location") {
                store.openSelectionLocation()
            }
            .disabled(!store.canOpenSelectionLocation)

            Button("Show Package Contents") {
                store.showSelectedPackageContents()
            }
            .disabled(!store.canShowSelectionPackageContents)

            Button("Open Selection in New Windows") {
                store.selectionFolderNavigationURLs.forEach {
                    BetterFilesWindowManager.openWindow(at: $0)
                }
            }
            .disabled(!store.canOpenSelectionInNewTabs)

            Button("Pin Selection to Quick Access") {
                store.pinSelectedFoldersToSidebar()
            }
            .disabled(!store.canPinSelectionToSidebar)

            Button("Unpin Selection from Quick Access") {
                store.unpinSelectedFoldersFromSidebar()
            }
            .disabled(!store.canUnpinSelectionFromSidebar)

            if store.isPinnedDirectory(store.currentURL) {
                Button("Unpin Current Folder") {
                    if let currentURL = store.currentURL {
                        store.unpinDirectory(currentURL)
                    }
                }
            } else {
                Button("Pin Current Folder") {
                    store.pinCurrentDirectory()
                }
                .disabled(store.currentURL == nil)
            }

            Button("Open Current Folder in Terminal") {
                store.openCurrentFolderInTerminal()
            }
            .disabled(store.currentURL == nil)

            Button("Open Current Folder in New Window") {
                if let currentURL = store.currentURL {
                    BetterFilesWindowManager.openWindow(at: currentURL)
                }
            }
            .disabled(store.currentURL == nil)

            Button("Reveal Current Folder in Finder") {
                if let currentURL = store.currentURL {
                    store.revealInFinder(currentURL)
                }
            }
            .disabled(store.currentURL == nil)

            Button("Copy Current Folder Path") {
                if let currentURL = store.currentURL {
                    store.copyPath(of: currentURL)
                }
            }
            .disabled(store.currentURL == nil)

            Button("Copy Current Folder as Path") {
                if let currentURL = store.currentURL {
                    store.copyPathAsQuotedPath(of: currentURL)
                }
            }
            .disabled(store.currentURL == nil)

            Button("Clear Recent Folders") {
                store.clearRecentDirectories()
            }
            .disabled(store.recentDirectories.isEmpty)

            Button("Clear Recent Files") {
                store.clearRecentFiles()
            }
            .disabled(store.recentFiles.isEmpty)

            Button("Clear Search and Filters") {
                store.clearSearchAndContentFilters()
            }
            .disabled(!store.hasActiveContentFilters)

            Divider()

            Button(store.undoFileOperationTitle) {
                store.undoLastFileOperation()
            }
            .disabled(!store.canUndoFileOperation)

            Button(store.redoFileOperationTitle) {
                store.redoLastFileOperation()
            }
            .disabled(!store.canRedoFileOperation)

            Divider()

            Button("Open") {
                store.openSelectedItems()
            }
            .disabled(!store.hasSelection)

            Button("Copy Path") {
                store.copySelectedPaths()
            }
            .disabled(!store.hasSelection)

            Button("Copy as Path") {
                store.copySelectedPathsAsQuotedPaths()
            }
            .disabled(!store.hasSelection)

            Button("Copy Name") {
                store.copySelectedNames()
            }
            .disabled(!store.hasSelection)

            Button("Copy Parent Folder Path") {
                store.copySelectedParentFolderPaths()
            }
            .disabled(!store.hasSelection)

            Button("Open Parent Folder in New Tab") {
                store.openSelectionParentFoldersInNewTabs()
            }
            .disabled(!store.canOpenSelectionParentFoldersInNewTabs)

            Button("Reveal in Finder") {
                store.revealSelectedInFinder()
            }
            .disabled(!store.hasSelection)

            Button("Share...") {
                store.shareSelectedItems()
            }
            .disabled(!store.hasSelection)

            OpenWithMenu(store: store)
                .disabled(!store.hasSelection)

            Button("Open in Terminal") {
                store.openSelectionInTerminal()
            }
            .disabled(!store.canOpenSelectionInTerminal)

            Button("Duplicate") {
                store.duplicateSelectedItems()
            }
            .disabled(!store.hasSelection)

            Button("Make Alias") {
                store.createAliasesForSelection()
            }
            .disabled(!store.hasSelection)

            Button("Compress to Zip") {
                store.compressSelectedItems()
            }
            .disabled(!store.hasSelection)

            Button("Extract Zip") {
                store.extractSelectedArchives()
            }
            .disabled(!store.canExtractSelectedArchives)

            Button("Copy to Folder...") {
                store.copySelectedItemsToFolder()
            }
            .disabled(!store.hasSelection)

            Button("Move to Folder...") {
                store.moveSelectedItemsToFolder()
            }
            .disabled(!store.hasSelection)

            Button("Delete Permanently...", role: .destructive) {
                store.confirmDeleteSelectedItemsPermanently()
            }
            .disabled(!store.hasSelection)

            Button("Hide Selection") {
                store.setSelectedItemsHidden(true)
            }
            .disabled(!store.hasSelection)

            Button("Unhide Selection") {
                store.setSelectedItemsHidden(false)
            }
            .disabled(!store.hasSelection)

            Button("Lock Selection") {
                store.setSelectedItemsLocked(true)
            }
            .disabled(!store.hasSelection)

            Button("Unlock Selection") {
                store.setSelectedItemsLocked(false)
            }
            .disabled(!store.hasSelection)

            Button("Set Tags...") {
                store.promptSetTagsForSelection()
            }
            .disabled(!store.hasSelection)

            Button("Clear Access Control List") {
                store.clearSelectedItemsAccessControl()
            }
            .disabled(!store.hasSelection)

            Button("Make Read-Only") {
                store.setSelectedItemsWritable(false)
            }
            .disabled(!store.hasSelection)

            Button("Make Writable") {
                store.setSelectedItemsWritable(true)
            }
            .disabled(!store.hasSelection)

            Button("Apply Permissions to Enclosed Items") {
                store.applySelectedFolderPermissionsToEnclosedItems()
            }
            .disabled(!store.canApplySelectedFolderPermissionsToEnclosedItems)

            Button("Batch Rename") {
                store.batchRenameSelection()
            }
            .disabled(store.selectedItems.count < 2)

            Button("Properties") {
                store.showPropertiesForSelection()
            }
            .disabled(!store.hasSelection)

            Divider()

            Button("Select All") {
                store.selectAllVisibleItems()
            }
            .disabled(store.visibleItems.isEmpty)

            Button("Select None") {
                store.clearSelection()
            }
            .disabled(!store.hasSelection)

            Button("Invert Selection") {
                store.invertSelection()
            }
            .disabled(store.visibleItems.isEmpty)
        } label: {
            CommandMenuLabel(title: "More", systemImage: "ellipsis.circle", showsTitle: showsTitle)
        }
        .menuStyle(.borderlessButton)
    }
}

private struct FilterBar: View {
    @Bindable var store: BrowserStore

    var body: some View {
        HStack(spacing: 8) {
            Label(store.hasVisibleFilterSummary ? "Active" : "Filters", systemImage: "line.3.horizontal.decrease.circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    Menu {
                        ForEach(FileKindFilter.allCases) { filter in
                            Button {
                                store.kindFilter = filter
                            } label: {
                                if store.kindFilter == filter {
                                    Label(filter.label, systemImage: "checkmark")
                                } else {
                                    Text(filter.label)
                                }
                            }
                        }
                    } label: {
                        FilterSummaryChip(title: "Kind", value: store.kindFilter.label, isActive: store.kindFilter != .all)
                    }
                    .menuStyle(.borderlessButton)

                    Menu {
                        ForEach(store.availableTypeFilters) { filter in
                            Button {
                                store.typeFilter = filter
                            } label: {
                                if store.typeFilter == filter {
                                    Label(filter.label, systemImage: "checkmark")
                                } else {
                                    Text(filter.label)
                                }
                            }
                        }
                    } label: {
                        FilterSummaryChip(title: "Type", value: store.typeFilter.label, isActive: store.typeFilter.isActive)
                    }
                    .menuStyle(.borderlessButton)

                    Menu {
                        ForEach(FileDateFilter.allCases) { filter in
                            Button {
                                store.dateFilter = filter
                            } label: {
                                if store.dateFilter == filter {
                                    Label(filter.label, systemImage: "checkmark")
                                } else {
                                    Text(filter.label)
                                }
                            }
                        }
                    } label: {
                        FilterSummaryChip(title: "Modified", value: store.dateFilter.label, isActive: store.dateFilter != .any)
                    }
                    .menuStyle(.borderlessButton)

                    Menu {
                        ForEach(FileSizeFilter.allCases) { filter in
                            Button {
                                store.sizeFilter = filter
                            } label: {
                                if store.sizeFilter == filter {
                                    Label(filter.label, systemImage: "checkmark")
                                } else {
                                    Text(filter.label)
                                }
                            }
                        }
                    } label: {
                        FilterSummaryChip(title: "Size", value: store.sizeFilter.label, isActive: store.sizeFilter != .any)
                    }
                    .menuStyle(.borderlessButton)

                    Menu {
                        ForEach(FileGroupField.allCases) { field in
                            Button {
                                store.groupField = field
                            } label: {
                                if store.groupField == field {
                                    Label(field.label, systemImage: "checkmark")
                                } else {
                                    Text(field.label)
                                }
                            }
                        }
                    } label: {
                        FilterSummaryChip(title: "Group", value: store.groupField.label, isActive: store.groupField != .none)
                    }
                    .menuStyle(.borderlessButton)

                    FilterToggle(title: "Hidden", systemImage: "eye", isOn: $store.showHiddenFiles)
                    FilterToggle(title: "Subfolders", systemImage: "scope", isOn: $store.searchesSubfolders)

                    if !store.query.isEmpty {
                        FilterSummaryChip(title: "Search", value: store.query, isActive: true)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .layoutPriority(1)

            Button {
                store.clearSearchAndContentFilters()
            } label: {
                Label("Clear", systemImage: "xmark.circle")
                    .font(.system(size: 10, weight: store.hasActiveContentFilters ? .semibold : .regular))
                    .lineLimit(1)
            }
            .buttonStyle(.borderless)
            .disabled(!store.hasActiveContentFilters)
            .help("Clear search, kind, date, and size filters")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.45))
                .frame(height: 1)
        }
    }
}

private struct FilterSummaryChip: View {
    let title: String
    let value: String
    var isActive = false

    var body: some View {
        HStack(spacing: 3) {
            Text(title)
                .foregroundStyle(.secondary)

            Text(value)
                .foregroundStyle(.primary)
        }
        .font(.system(size: 10, weight: .medium))
        .lineLimit(1)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(backgroundColor, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(strokeColor)
        }
    }

    private var backgroundColor: Color {
        isActive ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor).opacity(0.76)
    }

    private var strokeColor: Color {
        isActive ? Color.accentColor.opacity(0.22) : Color(nsColor: .separatorColor).opacity(0.24)
    }
}

private struct FilterToggle: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)

                Text(title)
                    .font(.system(size: 10, weight: isOn ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(strokeColor)
            }
        }
        .buttonStyle(.plain)
        .help(isOn ? "Turn off \(title)" : "Turn on \(title)")
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private var backgroundColor: Color {
        isOn ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor).opacity(0.76)
    }

    private var strokeColor: Color {
        isOn ? Color.accentColor.opacity(0.22) : Color(nsColor: .separatorColor).opacity(0.24)
    }
}

private struct SearchField: View {
    @Bindable var store: BrowserStore
    var isCompact = false
    @FocusState private var searchFieldIsFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(searchPlaceholder, text: $store.query)
                .textFieldStyle(.plain)
                .focused($searchFieldIsFocused)

            Button {
                store.searchesSubfolders.toggle()
            } label: {
                Image(systemName: store.searchesSubfolders ? "scope" : "folder")
                    .foregroundStyle(store.searchesSubfolders ? Color.accentColor : Color.secondary)
                    .frame(width: 17, height: 17)
            }
            .buttonStyle(.plain)
            .help(store.searchesSubfolders ? "Search current folder only" : "Search current folder and subfolders")
            .accessibilityLabel(store.searchesSubfolders ? "Search current folder only" : "Search current folder and subfolders")

            if !store.query.isEmpty {
                Button {
                    store.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(minWidth: isCompact ? 118 : 145, idealWidth: isCompact ? 150 : 210, maxWidth: isCompact ? 190 : 280)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.98), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(searchFieldIsFocused ? Color.accentColor.opacity(0.46) : Color(nsColor: .separatorColor).opacity(0.46))
        }
        .onChange(of: store.focusRequest) {
            guard store.focusRequest?.target == .searchField else {
                return
            }

            searchFieldIsFocused = true
        }
    }

    private var searchPlaceholder: String {
        if store.masksSensitiveData {
            return store.searchesSubfolders ? "Search private folder and subfolders" : "Search private folder"
        }

        let name = store.currentURL?.lastPathComponent
        let folderName = (name?.isEmpty == false ? name : nil) ?? "folder"
        return store.searchesSubfolders ? "Search \(folderName) and subfolders" : "Search \(folderName)"
    }
}

private struct AddressHistoryMenu: View {
    let store: BrowserStore

    var body: some View {
        Menu {
            ForEach(AddressMenuLocation.Group.allCases, id: \.rawValue) { group in
                let locations = store.addressMenuLocations.filter { $0.group == group }
                if !locations.isEmpty {
                    Section(group.label) {
                        ForEach(locations) { location in
                            Button {
                                store.open(location.url)
                            } label: {
                                LocationMenuLabel(name: location.name, detail: location.detail, url: location.url)
                            }
                            .help(location.detail)
                        }
                    }
                }
            }

            if store.canClearTypedPathHistory {
                Divider()

                Button {
                    store.clearTypedPathHistory()
                } label: {
                    Label("Clear Typed Paths", systemImage: "clock.badge.xmark")
                }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .help("Address history")
        .accessibilityLabel("Address history")
    }
}

private struct PathBar: View {
    @Bindable var store: BrowserStore
    @Binding var isEditingPath: Bool
    @FocusState private var pathFieldIsFocused: Bool

    var body: some View {
        HStack(spacing: 7) {
            LocationIconImage(url: store.currentURL, fallbackSystemImage: "folder", size: 16, showsApplicationBadge: true)

            if store.masksSensitiveData {
                Text("Private path")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("Folder path", text: $store.pathInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: pathFieldIsFocused ? .semibold : .medium, design: .monospaced))
                    .lineLimit(1)
                    .focused($pathFieldIsFocused)
                    .onSubmit {
                        commitPath()
                    }
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.99), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(pathFieldIsFocused ? Color.accentColor.opacity(0.58) : Color(nsColor: .separatorColor).opacity(0.46))
        }
        .onAppear {
            resetPathInputToCurrentURL()
        }
        .onChange(of: store.currentURL) {
            if !pathFieldIsFocused {
                resetPathInputToCurrentURL()
            }
        }
        .onChange(of: pathFieldIsFocused) {
            if pathFieldIsFocused {
                isEditingPath = true
            } else if isEditingPath {
                cancelPathEdit()
            }
        }
        .onChange(of: isEditingPath) {
            if isEditingPath {
                pathFieldIsFocused = !store.masksSensitiveData
            } else {
                pathFieldIsFocused = false
                resetPathInputToCurrentURL()
            }
        }
        .onChange(of: store.focusRequest) {
            guard store.focusRequest?.target == .addressBar else {
                return
            }

            pathFieldIsFocused = true
        }
        .onExitCommand {
            cancelPathEdit()
        }
        .contextMenu {
            Button("Copy Current Path") {
                if let currentURL = store.currentURL {
                    store.copyPath(of: currentURL)
                }
            }

            if let currentURL = store.currentURL {
                Divider()

                LocationContextMenu(store: store, url: currentURL)
            }
        }
    }

    private func commitPath() {
        store.openPathInput()
        isEditingPath = false
    }

    private func cancelPathEdit() {
        resetPathInputToCurrentURL()
        isEditingPath = false
    }

    private func resetPathInputToCurrentURL() {
        store.pathInput = store.currentURL?.path ?? store.pathInput
    }
}

private struct PathBarScopeLabel: View {
    let currentURL: URL?

    var body: some View {
        if let scope = LocationScopeResolver.scope(for: currentURL) {
            Text(scope.label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
                .frame(maxWidth: 72)
                .padding(.horizontal, 5)
                .frame(height: 18)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.62), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.18))
                }
        }
    }
}

private struct PathInputCompletionMenu: View {
    let store: BrowserStore

    var body: some View {
        let completions = store.pathInputCompletions

        Menu {
            if completions.isEmpty {
                Text("No matching paths")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(completions) { completion in
                    Button {
                        store.openPathInputCompletion(completion)
                    } label: {
                        PathInputCompletionMenuLabel(completion: completion)
                    }
                    .help(completion.detail)
                }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(completions.isEmpty ? .tertiary : .secondary)
                .frame(width: 22, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .disabled(completions.isEmpty)
        .help("Path suggestions")
        .accessibilityLabel("Path suggestions")
    }
}

private struct PathInputCompletionMenuLabel: View {
    let completion: PathInputCompletion

    var body: some View {
        HStack(spacing: 7) {
            LocationIconImage(
                url: completion.url,
                fallbackSystemImage: completion.isDirectory ? "folder" : "doc",
                size: 16,
                showsApplicationBadge: !completion.isDirectory
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(completion.name)
                    .lineLimit(1)

                Text(completion.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

private struct BreadcrumbChildMenu: View {
    let store: BrowserStore
    let component: BrowserPathComponent

    var body: some View {
        Menu {
            let folders = store.childFolderComponents(for: component)
            if folders.isEmpty {
                Text("No folders")
            } else {
                ForEach(folders) { folder in
                    Button {
                        store.open(folder.url)
                    } label: {
                        LocationMenuLabel(name: folder.name, detail: folder.url.path, url: folder.url)
                    }
                    .help(folder.url.path)
                }
            }
        } label: {
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 14, height: 18)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .help("Browse folders in \(component.name)")
        .accessibilityLabel("Browse folders in \(component.name)")
    }
}

private struct LocationContextMenu: View {
    let store: BrowserStore
    let url: URL

    var body: some View {
        Button("Open") {
            store.open(url)
        }

        Button("Open in New Tab") {
            store.addTab(opening: url)
        }

        Button("Open in New Window") {
            BetterFilesWindowManager.openWindow(at: url)
        }

        Button("New Folder") {
            store.createFolder(in: url)
        }

        Button("New File") {
            store.createFile(in: url)
        }

        Button("Paste Here") {
            store.pasteItems(to: url)
        }
        .disabled(!store.canPasteItems)

        if store.isTrashDirectory(url) {
            Button("Empty Trash...", role: .destructive) {
                store.confirmEmptyTrash()
            }
            .disabled(!store.canEmptyTrash)
        }

        if store.isPinnedDirectory(url) {
            Button("Unpin") {
                store.unpinDirectory(url)
            }
        } else {
            Button("Pin to Sidebar") {
                store.pinDirectory(url)
            }
        }

        Divider()

        Button("Copy Path") {
            store.copyPath(of: url)
        }

        Button("Copy as Path") {
            store.copyPathAsQuotedPath(of: url)
        }

        Button("Reveal in Finder") {
            store.revealInFinder(url)
        }

        Button("Open in Terminal") {
            store.openFolderInTerminal(url)
        }
    }
}

private struct FileWorkspaceView: View {
    @Bindable var store: BrowserStore
    @State private var showsRootFilesystem = false

    var body: some View {
        Group {
            if store.currentURL?.standardizedFileURL.path == "/", !showsRootFilesystem {
                ThisMacOverviewView(store: store, showsRootFilesystem: $showsRootFilesystem)
            } else {
                switch store.viewMode {
                case .details:
                    if store.groupField == .none, store.usesDefaultDetailsColumns {
                        FileTableView(store: store)
                    } else {
                        FileGroupedDetailsView(store: store)
                    }
                case .list:
                    FileListView(store: store)
                case .icons:
                    FileIconGridView(store: store)
                case .tiles:
                    FileTileGridView(store: store)
                }
            }
        }
        .contextMenu {
            WorkspaceContextMenu(store: store)
        }
        .onChange(of: store.currentURL?.standardizedFileURL.path) {
            if store.currentURL?.standardizedFileURL.path != "/" {
                showsRootFilesystem = false
            }
        }
        .task(id: visibleIconWarmupID) {
            guard !showsRootFilesystem else {
                return
            }

            await FileIconLibrary.warmVisibleIcons(
                for: store.visibleItems,
                limit: VisibleIconWarmupPolicy.limit(for: store.viewMode, compactView: store.compactView),
                prefersFileSpecificIcons: VisibleIconWarmupPolicy.prefersFileSpecificIcons(for: store.viewMode)
            )
        }
    }

    private var visibleIconWarmupID: String {
        let tab = store.selectedTab
        return [
            tab.id.uuidString,
            "\(tab.itemsVersion)",
            tab.currentURL?.standardizedFileURL.path ?? "",
            tab.query,
            store.viewMode.rawValue,
            store.kindFilter.rawValue,
            store.typeFilter.rawValue,
            store.dateFilter.rawValue,
            store.sizeFilter.rawValue,
            store.sortField.rawValue,
            "\(store.sortAscending)",
            "\(store.foldersFirst)",
            "\(store.compactView)"
        ].joined(separator: "|")
    }
}

private struct WorkspaceContextMenu: View {
    @Bindable var store: BrowserStore

    var body: some View {
        Button("New Folder") {
            store.createFolder()
        }
        .disabled(store.currentURL == nil)

        Button("New File...") {
            store.createFile()
        }
        .disabled(store.currentURL == nil)

        Button("Paste") {
            store.pasteItems()
        }
        .disabled(!store.canPasteItems)

        if let currentURL = store.currentURL, store.isTrashDirectory(currentURL) {
            Button("Empty Trash...", role: .destructive) {
                store.confirmEmptyTrash()
            }
            .disabled(!store.canEmptyTrash)
        }

        Divider()

        Button("Refresh") {
            store.reload()
        }
        .disabled(store.currentURL == nil)

        Button("Open Current Folder in Terminal") {
            store.openCurrentFolderInTerminal()
        }
        .disabled(store.currentURL == nil)

        Button("Reveal Current Folder in Finder") {
            if let currentURL = store.currentURL {
                store.revealInFinder(currentURL)
            }
        }
        .disabled(store.currentURL == nil)

        Button("Copy Current Folder Path") {
            if let currentURL = store.currentURL {
                store.copyPath(of: currentURL)
            }
        }
        .disabled(store.currentURL == nil)

        Button("Copy Current Folder as Path") {
            if let currentURL = store.currentURL {
                store.copyPathAsQuotedPath(of: currentURL)
            }
        }
        .disabled(store.currentURL == nil)

        Divider()

        Button(store.undoFileOperationTitle) {
            store.undoLastFileOperation()
        }
        .disabled(!store.canUndoFileOperation)

        Button(store.redoFileOperationTitle) {
            store.redoLastFileOperation()
        }
        .disabled(!store.canRedoFileOperation)

        Divider()

        Menu("Sort By") {
            ForEach(FileSortField.allCases) { field in
                Button {
                    store.setSortField(field)
                } label: {
                    if store.sortField == field {
                        Label(field.label, systemImage: store.sortAscending ? "arrow.up" : "arrow.down")
                    } else {
                        Text(field.label)
                    }
                }
            }
        }

        Menu("View") {
            Picker("Layout", selection: $store.viewMode) {
                ForEach(FileViewMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            Picker("Group By", selection: $store.groupField) {
                ForEach(FileGroupField.allCases) { field in
                    Text(field.label).tag(field)
                }
            }

            Divider()

            Toggle("File Name Extensions", isOn: $store.showFileExtensions)
            Toggle("Hidden Items", isOn: $store.showHiddenFiles)
            Toggle("Compact View", isOn: $store.compactView)
            Toggle("Group Folders First", isOn: $store.foldersFirst)
            Toggle("Item Checkboxes", isOn: $store.showsItemCheckboxes)
            Toggle("Navigation Pane", isOn: $store.showsNavigationPane)
            Toggle("Details Pane", isOn: $store.showsDetailPanel)
            Toggle("Preview Pane", isOn: $store.showsPreviewPanel)

            Divider()

            Button("Save View for This Folder") {
                store.saveCurrentFolderViewSettings()
            }
            .disabled(store.currentURL == nil)

            Button("Clear Saved Folder View") {
                store.clearCurrentFolderViewSettings()
            }
            .disabled(!store.currentFolderHasSavedView)
        }

        Menu("Filters") {
            Picker("Kind", selection: $store.kindFilter) {
                ForEach(FileKindFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }

            Picker("Type", selection: $store.typeFilter) {
                ForEach(store.availableTypeFilters) { filter in
                    Text(filter.label).tag(filter)
                }
            }

            Picker("Modified", selection: $store.dateFilter) {
                ForEach(FileDateFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }

            Picker("Size", selection: $store.sizeFilter) {
                ForEach(FileSizeFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }

            Divider()

            Toggle("Search Subfolders", isOn: $store.searchesSubfolders)
            Toggle("Show Hidden Files", isOn: $store.showHiddenFiles)

            Button("Clear Search and Filters") {
                store.clearSearchAndContentFilters()
            }
            .disabled(!store.hasActiveContentFilters)
        }

        if store.viewMode == .details {
            Menu("Columns") {
                Toggle("Kind", isOn: $store.showsKindColumn)
                Toggle("Size", isOn: $store.showsSizeColumn)
                Toggle("Modified", isOn: $store.showsModifiedColumn)
                Toggle("Created", isOn: $store.showsCreatedColumn)
                Toggle("Accessed", isOn: $store.showsAccessedColumn)
                Toggle("Permissions", isOn: $store.showsPermissionsColumn)

                Divider()

                Button("Show All Columns") {
                    store.showAllDetailsColumns()
                }
                .disabled(store.usesDefaultDetailsColumns)
            }
        }

        Divider()

        Button("Select All") {
            store.selectAllVisibleItems()
        }
        .disabled(store.visibleItems.isEmpty)

        Button("Select None") {
            store.clearSelection()
        }
        .disabled(!store.hasSelection)

        Button("Invert Selection") {
            store.invertSelection()
        }
        .disabled(store.visibleItems.isEmpty)
    }
}

private struct ThisMacOverviewView: View {
    let store: BrowserStore
    @Binding var showsRootFilesystem: Bool
    @State private var mountedVolumes = FavoriteLocation.initialMountedVolumes

    private let columns = [
        GridItem(.adaptive(minimum: 184, maximum: 280), spacing: 6, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    LocationIconImage(
                        url: URL(fileURLWithPath: "/", isDirectory: true),
                        fallbackSystemImage: "desktopcomputer",
                        size: 23
                    )

                    VStack(alignment: .leading, spacing: 1) {
                        Text("This Mac")
                            .font(.system(size: 15, weight: .semibold))

                        Text("Devices, frequent folders, and recent work")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                }

                ThisMacOverviewSection(title: "Devices and Drives", count: mountedVolumes.count) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                        ForEach(mountedVolumes) { volume in
                            ThisMacOverviewTile(
                                title: store.masksSensitiveData ? "Private Drive" : volume.name,
                                subtitle: store.masksSensitiveData ? "Private path" : volume.url.path,
                                url: volume.url,
                                fallbackSystemImage: volume.systemImage,
                                volumeSummary: volume.volumeSummary
                            ) {
                                store.open(volume.url)
                            }
                        }
                    }
                }

                ThisMacOverviewSection(title: "Frequent Folders", count: FavoriteLocation.defaults.count) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                        ForEach(FavoriteLocation.defaults) { location in
                            ThisMacOverviewTile(
                                title: store.masksSensitiveData ? "Private Folder" : location.name,
                                subtitle: store.masksSensitiveData ? "Private path" : location.url.path,
                                url: location.url,
                                fallbackSystemImage: location.systemImage
                            ) {
                                store.open(location.url)
                            }
                        }
                    }
                }

                if !store.pinnedDirectories.isEmpty {
                    ThisMacOverviewSection(title: "Pinned Folders", count: store.pinnedDirectories.count) {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                            ForEach(store.pinnedDirectories, id: \.standardizedFileURL.path) { url in
                                ThisMacOverviewTile(
                                    title: store.displayName(for: url),
                                    subtitle: store.masksSensitiveData ? "Private path" : url.deletingLastPathComponent().path,
                                    url: url,
                                    fallbackSystemImage: "pin"
                                ) {
                                    store.open(url)
                                }
                            }
                        }
                    }
                }

                if !store.recentDirectories.isEmpty {
                    ThisMacOverviewSection(title: "Recent Folders", count: store.recentDirectories.count) {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                            ForEach(store.recentDirectories, id: \.standardizedFileURL.path) { url in
                                ThisMacOverviewTile(
                                    title: store.displayName(for: url),
                                    subtitle: store.masksSensitiveData ? "Private path" : url.deletingLastPathComponent().path,
                                    url: url,
                                    fallbackSystemImage: "clock.arrow.circlepath"
                                ) {
                                    store.open(url)
                                }
                            }
                        }
                    }
                }

                if !store.recentFiles.isEmpty {
                    ThisMacOverviewSection(title: "Recent Files", count: store.recentFiles.count) {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                            ForEach(store.recentFiles, id: \.standardizedFileURL.path) { url in
                                ThisMacOverviewTile(
                                    title: store.masksSensitiveData ? "Private File" : url.lastPathComponent,
                                    subtitle: store.masksSensitiveData ? "Private path" : url.deletingLastPathComponent().path,
                                    url: url,
                                    fallbackSystemImage: "doc",
                                    iconPresentation: .file
                                ) {
                                    store.openRecentFile(url)
                                }
                                .contextMenu {
                                    RecentFileOverviewContextMenu(store: store, url: url)
                                }
                            }
                        }
                    }
                }

                ThisMacOverviewSection(title: "System", count: 1) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                        ThisMacOverviewTile(
                            title: "System Root",
                            subtitle: "/",
                            url: URL(fileURLWithPath: "/", isDirectory: true),
                            fallbackSystemImage: "folder.badge.gearshape"
                        ) {
                            showsRootFilesystem = true
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            await refreshMountedVolumes()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didMountNotification)) { _ in
            Task { await refreshMountedVolumes() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            Task { await refreshMountedVolumes() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didRenameVolumeNotification)) { _ in
            Task { await refreshMountedVolumes() }
        }
    }

    private func refreshMountedVolumes() async {
        let volumes = await Task.detached(priority: .utility) {
            FavoriteLocation.mountedVolumes()
        }.value

        mountedVolumes = volumes
    }
}

private struct ThisMacOverviewSection<Content: View>: View {
    let title: String
    let count: Int
    let content: Content

    init(title: String, count: Int, @ViewBuilder content: () -> Content) {
        self.title = title
        self.count = count
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("\(count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.36))
                    .frame(height: 1)
            }

            content
        }
    }
}

private struct ThisMacOverviewTile: View {
    enum IconPresentation {
        case location
        case file
    }

    let title: String
    let subtitle: String
    let url: URL
    let fallbackSystemImage: String
    var iconPresentation: IconPresentation = .location
    var volumeSummary: VolumeStatusSummary? = nil
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: volumeSummary == nil ? .center : .top, spacing: 8) {
                icon
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let volumeSummary {
                        Text(volumeSummary.statusLabel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if let usedFraction = volumeSummary.usedFraction {
                            VolumeUsageBar(usedFraction: usedFraction)
                                .frame(maxWidth: 190)
                                .padding(.top, 2)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: volumeSummary == nil ? 46 : 66, alignment: .leading)
            .background(tileBackground, in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(tileStroke)
            }
            .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(url.path)
        .accessibilityLabel("\(title), \(subtitle)")
        .onHover { isHovering = $0 }
    }

    private var tileBackground: Color {
        isHovering ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.16) : Color(nsColor: .controlBackgroundColor).opacity(0.26)
    }

    private var tileStroke: Color {
        isHovering ? Color.accentColor.opacity(0.28) : Color(nsColor: .separatorColor).opacity(0.14)
    }

    @ViewBuilder
    private var icon: some View {
        switch iconPresentation {
        case .location:
            SidebarNativeIcon(url: url, fallbackSystemImage: fallbackSystemImage, size: 25, isActive: false)
        case .file:
            RecentFileOverviewIcon(url: url, fallbackSystemImage: fallbackSystemImage, size: 27)
        }
    }
}

private struct RecentFileOverviewIcon: View {
    let url: URL
    let fallbackSystemImage: String
    let size: CGFloat
    @Environment(\.betterFilesMasksSensitiveData) private var masksSensitiveData
    @State private var fileIcon: NSImage?
    @State private var applicationBadgeIcon: NSImage?

    init(url: URL, fallbackSystemImage: String, size: CGFloat) {
        self.url = url
        self.fallbackSystemImage = fallbackSystemImage
        self.size = size
        _fileIcon = State(initialValue: FileIconLibrary.cachedIcon(for: url))
        _applicationBadgeIcon = State(initialValue: FileIconLibrary.cachedApplicationBadgeIcon(forFileURL: url))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.46))
                .frame(width: size + 8, height: size + 8)
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.18))
            }

            Group {
                if masksSensitiveData {
                    Image(systemName: fallbackSystemImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                } else if let fileIcon {
                    Image(nsImage: fileIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: fallbackSystemImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)

            if !masksSensitiveData, let applicationBadgeIcon {
                Image(nsImage: applicationBadgeIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: max(13, size * 0.44), height: max(13, size * 0.44))
                    .padding(2)
                    .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.30))
                    }
                    .offset(x: 3, y: 3)
            }
        }
        .frame(width: size + 8, height: size + 8)
        .accessibilityHidden(true)
        .task(id: iconTaskID) {
            guard !masksSensitiveData else {
                fileIcon = nil
                applicationBadgeIcon = nil
                return
            }

            fileIcon = FileIconLibrary.cachedIcon(for: url)
            if fileIcon == nil {
                fileIcon = await FileIconLibrary.iconAsync(for: url)
            }

            applicationBadgeIcon = FileIconLibrary.cachedApplicationBadgeIcon(forFileURL: url)
            if applicationBadgeIcon == nil {
                applicationBadgeIcon = await FileIconLibrary.applicationBadgeIconAsync(forFileURL: url)
            }
        }
    }

    private var iconTaskID: String {
        "\(url.standardizedFileURL.path)|\(Int(size.rounded()))|masked:\(masksSensitiveData)"
    }
}

private struct RecentFileOverviewContextMenu: View {
    let store: BrowserStore
    let url: URL

    var body: some View {
        Button("Open") {
            store.openRecentFile(url)
        }

        Button("Open File Location") {
            store.openRecentFileLocation(url)
        }

        Button("Reveal in Finder") {
            store.revealInFinder(url)
        }

        Divider()

        Button("Copy Path") {
            store.copyPath(of: url)
        }

        Button("Copy as Path") {
            store.copyPathAsQuotedPath(of: url)
        }

        Divider()

        Button("Remove from Recent Files") {
            store.removeRecentFile(url)
        }
    }
}

private struct FileOperationOverlay: View {
    let store: BrowserStore
    let operation: FileOperationSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                if let progressFraction = operation.progressFraction {
                    ProgressView(value: progressFraction)
                        .frame(width: 132)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(operation.statusLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Button {
                    store.cancelActiveFileOperation()
                } label: {
                    Image(systemName: operation.isCancelling ? "hourglass" : "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .disabled(operation.isCancelling)
                .help(operation.isCancelling ? "Cancelling" : "Cancel operation")
                .accessibilityLabel(operation.isCancelling ? "Cancelling operation" : "Cancel operation")
            }

            if operation.itemCount > 1, operation.isRunning {
                Text("\(operation.completedItemCount) of \(operation.itemCount) items")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.24))
        }
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}

private struct FileGroupHeader: View {
    let section: FileItemSection
    let compactView: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(section.title)
                .font(.system(size: compactView ? 11 : 12, weight: .semibold))

            Text("\(section.items.count)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, compactView ? 10 : 12)
        .padding(.vertical, compactView ? 4 : 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.36))
                .frame(height: 1)
        }
    }
}

private struct FileGroupedDetailsView: View {
    @Bindable var store: BrowserStore
    @State private var isDropTarget = false

    var body: some View {
        ZStack {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    FileDetailsHeaderRow(store: store)

                    ForEach(store.visibleSections) { section in
                        Section {
                            ForEach(section.items) { item in
                                FileDetailsRow(store: store, item: item)
                            }
                        } header: {
                            if store.groupField != .none {
                                FileGroupHeader(section: section, compactView: store.compactView)
                            }
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))

            WorkspaceStateOverlay(store: store, isDropTarget: isDropTarget)
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget) { providers in
            importDroppedItems(from: providers)
            return true
        }
    }

    private func importDroppedItems(from providers: [NSItemProvider]) {
        FileDropProviderLoader.loadFileURLs(from: providers) { droppedURLs in
            _ = store.dropItems(droppedURLs)
        }
    }
}

private enum FileDetailsMetrics {
    static let kindColumnWidth: CGFloat = 172
}

private struct FileDetailsHeaderRow: View {
    let store: BrowserStore

    var body: some View {
        HStack(spacing: 10) {
            Text("")
                .frame(width: 26)

            Text("Name")
                .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

            if store.showsKindColumn {
                Text("Kind")
                    .frame(width: FileDetailsMetrics.kindColumnWidth, alignment: .leading)
            }

            if store.showsSizeColumn {
                Text("Size")
                    .frame(width: 92, alignment: .trailing)
            }

            if store.showsModifiedColumn {
                Text("Modified")
                    .frame(width: 150, alignment: .trailing)
            }

            if store.showsCreatedColumn {
                Text("Created")
                    .frame(width: 150, alignment: .trailing)
            }

            if store.showsAccessedColumn {
                Text("Accessed")
                    .frame(width: 150, alignment: .trailing)
            }

            if store.showsPermissionsColumn {
                Text("Perms")
                    .frame(width: 58, alignment: .trailing)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.52))
                .frame(height: 1)
        }
    }
}

private struct FileDetailsRow: View {
    let store: BrowserStore
    let item: FileItem
    @State private var isHovering = false

    private var isSelected: Bool {
        store.selectedItemIDs.contains(item.id)
    }

    var body: some View {
        HStack(spacing: 10) {
            Toggle(
                "",
                isOn: Binding(
                    get: { isSelected },
                    set: { store.setItemSelection(item.id, isSelected: $0) }
                )
            )
            .toggleStyle(.checkbox)
            .labelsHidden()
            .opacity(store.showsItemCheckboxes ? 1 : 0)
            .disabled(!store.showsItemCheckboxes)
            .frame(width: 26)

            HStack(spacing: 7) {
                FileIconImage(item: item, size: store.compactView ? 16 : 18)

                FileNameCellText(store: store, item: item)
            }
            .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

            if store.showsKindColumn {
                FileKindLabel(item: item, iconSize: store.compactView ? 10 : 12, showsApplicationName: true)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: FileDetailsMetrics.kindColumnWidth, alignment: .leading)
            }

            if store.showsSizeColumn {
                Text(item.sizeLabel)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .trailing)
            }

            if store.showsModifiedColumn {
                Text(item.modifiedLabel)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .frame(width: 150, alignment: .trailing)
            }

            if store.showsCreatedColumn {
                Text(item.createdLabel)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .frame(width: 150, alignment: .trailing)
            }

            if store.showsAccessedColumn {
                Text(item.accessedLabel)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .frame(width: 150, alignment: .trailing)
            }

            if store.showsPermissionsColumn {
                Text(item.permissionsLabel)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .trailing)
            }
        }
        .font(.system(size: store.compactView ? 11 : 12))
        .padding(.horizontal, 12)
        .frame(minHeight: store.compactView ? 24 : 30)
        .background(rowBackground)
        .contentShape(Rectangle())
        .fileActivationGesture(
            select: {
                store.selectedItemIDs = [item.id]
            },
            open: {
                store.openItem(item)
            }
        )
        .fileDragDropTarget(store: store, item: item)
        .contextMenu {
            FileItemContextMenu(store: store, item: item)
        }
        .onHover { isHovering = $0 }
    }

    private var rowBackground: some ShapeStyle {
        if isSelected {
            Color.accentColor.opacity(0.16)
        } else if isHovering {
            Color(nsColor: .controlBackgroundColor)
        } else {
            Color.clear
        }
    }
}

private struct FileTableView: View {
    @Bindable var store: BrowserStore
    @State private var isDropTarget = false

    var body: some View {
        ZStack {
            Table(
                store.visibleItems,
                selection: Binding(
                    get: { store.selectedItemIDs },
                    set: { store.selectedItemIDs = $0 }
                )
            ) {
                TableColumn("") { item in
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { store.selectedItemIDs.contains(item.id) },
                            set: { store.setItemSelection(item.id, isSelected: $0) }
                        )
                    )
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .opacity(store.showsItemCheckboxes ? 1 : 0)
                    .disabled(!store.showsItemCheckboxes)
                }
                .width(store.showsItemCheckboxes ? 28 : 0)

                TableColumn("Name") { item in
                    HStack(spacing: 7) {
                        FileIconImage(item: item, size: 18)

                        FileNameCellText(store: store, item: item)
                    }
                    .contentShape(Rectangle())
                    .fileActivationGesture(
                        select: {
                            store.selectedItemIDs = [item.id]
                        },
                        open: {
                            store.openItem(item)
                        }
                    )
                    .fileDragDropTarget(store: store, item: item)
                    .contextMenu {
                        FileItemContextMenu(store: store, item: item)
                    }
                }

                TableColumn("Kind") { item in
                    FileKindLabel(item: item, iconSize: 12, showsApplicationName: true)
                        .foregroundStyle(.secondary)
                }
                .width(ideal: FileDetailsMetrics.kindColumnWidth)

                TableColumn("Size") { item in
                    Text(item.sizeLabel)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                }
                .width(ideal: 96)

                TableColumn("Modified") { item in
                    Text(item.modifiedLabel)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                }
                .width(ideal: 160)

                TableColumn("Created") { item in
                    Text(item.createdLabel)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                }
                .width(ideal: 160)

                TableColumn("Accessed") { item in
                    Text(item.accessedLabel)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                }
                .width(ideal: 160)

            }
            .tableStyle(.bordered(alternatesRowBackgrounds: true))
            .controlSize(store.compactView ? .mini : .small)

            if store.visibleItems.isEmpty, !store.isLoading {
                ContentUnavailableView(
                    store.query.isEmpty ? "No Items" : "No Matches",
                    systemImage: store.query.isEmpty ? "folder" : "magnifyingglass",
                    description: Text(store.query.isEmpty ? "This folder is empty." : "Try another search.")
                )
            }

            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }

            if let activeOperation = store.activeOperation {
                FileOperationOverlay(store: store, operation: activeOperation)
            }

            if isDropTarget {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget) { providers in
            importDroppedItems(from: providers)
            return true
        }
    }

    private func importDroppedItems(from providers: [NSItemProvider]) {
        FileDropProviderLoader.loadFileURLs(from: providers) { droppedURLs in
            _ = store.dropItems(droppedURLs)
        }
    }

    nonisolated fileprivate static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let url = item as? NSURL {
            return url as URL
        }

        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }

        return nil
    }
}

private struct FileListView: View {
    @Bindable var store: BrowserStore
    @State private var isDropTarget = false

    var body: some View {
        ZStack {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: store.groupField == .none ? [] : [.sectionHeaders]) {
                    ForEach(store.visibleSections) { section in
                        Section {
                            ForEach(section.items) { item in
                                FileListRow(store: store, item: item)
                            }
                        } header: {
                            if store.groupField != .none {
                                FileGroupHeader(section: section, compactView: store.compactView)
                            }
                        }
                    }
                }
                .padding(.vertical, store.compactView ? 3 : 6)
            }
            .background(Color(nsColor: .textBackgroundColor))

            WorkspaceStateOverlay(store: store, isDropTarget: isDropTarget)
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget) { providers in
            importDroppedItems(from: providers)
            return true
        }
    }

    private func importDroppedItems(from providers: [NSItemProvider]) {
        FileDropProviderLoader.loadFileURLs(from: providers) { droppedURLs in
            _ = store.dropItems(droppedURLs)
        }
    }
}

private struct FileListRow: View {
    let store: BrowserStore
    let item: FileItem
    @State private var isHovering = false

    private var isSelected: Bool {
        store.selectedItemIDs.contains(item.id)
    }

    var body: some View {
        HStack(spacing: store.compactView ? 8 : 10) {
            if store.showsItemCheckboxes {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { isSelected },
                        set: { store.setItemSelection(item.id, isSelected: $0) }
                    )
                )
                .toggleStyle(.checkbox)
                .labelsHidden()
            }

            FileIconImage(item: item, size: store.compactView ? 18 : 22)

            VStack(alignment: .leading, spacing: 1) {
                FileNameCellText(store: store, item: item)
                    .font(.system(size: store.compactView ? 12 : 13, weight: isSelected ? .semibold : .regular))

                FileKindLabel(item: item, iconSize: store.compactView ? 10 : 12, showsApplicationName: true)
                    .font(.system(size: store.compactView ? 9 : 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 190, maxWidth: .infinity, alignment: .leading)

            Text(item.sizeLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .trailing)

            Text(item.modifiedLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .trailing)
        }
        .padding(.horizontal, store.compactView ? 10 : 14)
        .frame(minHeight: store.compactView ? 27 : 34)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .fileActivationGesture(
            select: {
                store.selectedItemIDs = [item.id]
            },
            open: {
                store.openItem(item)
            }
        )
        .fileDragDropTarget(store: store, item: item)
        .contextMenu {
            FileItemContextMenu(store: store, item: item)
        }
        .onHover { isHovering = $0 }
    }

    private var rowBackground: some ShapeStyle {
        if isSelected {
            Color.accentColor.opacity(0.17)
        } else if isHovering {
            Color(nsColor: .controlBackgroundColor)
        } else {
            Color.clear
        }
    }
}

private struct FileTileGridView: View {
    @Bindable var store: BrowserStore
    @State private var isDropTarget = false

    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: store.compactView ? 185 : 220, maximum: store.compactView ? 300 : 340),
                spacing: store.compactView ? 7 : 10
            )
        ]
    }

    var body: some View {
        ZStack {
            ScrollView {
                LazyVStack(spacing: store.compactView ? 7 : 10) {
                    ForEach(store.visibleSections) { section in
                        VStack(spacing: store.compactView ? 7 : 10) {
                            if store.groupField != .none {
                                FileGroupHeader(section: section, compactView: store.compactView)
                            }

                            LazyVGrid(columns: columns, alignment: .leading, spacing: store.compactView ? 7 : 10) {
                                ForEach(section.items) { item in
                                    FileTileCell(store: store, item: item)
                                }
                            }
                            .padding(.horizontal, store.compactView ? 8 : 12)
                        }
                    }
                }
                .padding(.vertical, store.compactView ? 8 : 12)
            }
            .background(Color(nsColor: .textBackgroundColor))

            WorkspaceStateOverlay(store: store, isDropTarget: isDropTarget)
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget) { providers in
            importDroppedItems(from: providers)
            return true
        }
    }

    private func importDroppedItems(from providers: [NSItemProvider]) {
        FileDropProviderLoader.loadFileURLs(from: providers) { droppedURLs in
            _ = store.dropItems(droppedURLs)
        }
    }
}

private struct FileTileCell: View {
    let store: BrowserStore
    let item: FileItem
    @State private var isHovering = false

    private var isSelected: Bool {
        store.selectedItemIDs.contains(item.id)
    }

    var body: some View {
        HStack(spacing: store.compactView ? 8 : 11) {
            ZStack(alignment: .topLeading) {
                FileIconImage(item: item, size: store.compactView ? 32 : 40)
                    .frame(width: store.compactView ? 38 : 46, height: store.compactView ? 36 : 44)

                if store.showsItemCheckboxes {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { isSelected },
                            set: { store.setItemSelection(item.id, isSelected: $0) }
                        )
                    )
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .offset(x: -5, y: -5)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                FileNameCellText(store: store, item: item, lineLimit: 2)
                    .font(.system(size: store.compactView ? 12 : 13, weight: isSelected ? .semibold : .regular))

                FileKindLabel(item: item, iconSize: store.compactView ? 10 : 12, showsApplicationName: true)
                    .font(.system(size: store.compactView ? 9 : 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(item.sizeLabel)
                    .font(.system(size: store.compactView ? 9 : 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, store.compactView ? 8 : 10)
        .padding(.vertical, store.compactView ? 6 : 9)
        .frame(minHeight: store.compactView ? 50 : 64)
        .background(tileBackground, in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.42) : Color(nsColor: .separatorColor).opacity(isHovering ? 0.28 : 0))
        }
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .fileActivationGesture(
            select: {
                store.selectedItemIDs = [item.id]
            },
            open: {
                store.openItem(item)
            }
        )
        .fileDragDropTarget(store: store, item: item)
        .contextMenu {
            FileItemContextMenu(store: store, item: item)
        }
        .onHover { isHovering = $0 }
    }

    private var tileBackground: some ShapeStyle {
        if isSelected {
            Color.accentColor.opacity(0.16)
        } else if isHovering {
            Color(nsColor: .controlBackgroundColor)
        } else {
            Color.clear
        }
    }
}

private struct WorkspaceStateOverlay: View {
    let store: BrowserStore
    let isDropTarget: Bool

    var body: some View {
        ZStack {
            if store.visibleItems.isEmpty, !store.isLoading {
                ContentUnavailableView(
                    store.query.isEmpty ? "No Items" : "No Matches",
                    systemImage: store.query.isEmpty ? "folder" : "magnifyingglass",
                    description: Text(store.query.isEmpty ? "This folder is empty." : "Try another search.")
                )
            }

            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }

            if let activeOperation = store.activeOperation {
                FileOperationOverlay(store: store, operation: activeOperation)
            }

            if isDropTarget {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct FileIconGridView: View {
    @Bindable var store: BrowserStore
    @State private var isDropTarget = false

    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: store.compactView ? 94 : 118, maximum: store.compactView ? 132 : 160),
                spacing: store.compactView ? 7 : 10
            )
        ]
    }

    var body: some View {
        ZStack {
            ScrollView {
                LazyVStack(spacing: store.compactView ? 7 : 10) {
                    ForEach(store.visibleSections) { section in
                        VStack(spacing: store.compactView ? 7 : 10) {
                            if store.groupField != .none {
                                FileGroupHeader(section: section, compactView: store.compactView)
                            }

                            LazyVGrid(columns: columns, alignment: .leading, spacing: store.compactView ? 7 : 10) {
                                ForEach(section.items) { item in
                                    FileIconCell(store: store, item: item)
                                }
                            }
                            .padding(.horizontal, store.compactView ? 8 : 12)
                        }
                    }
                }
                .padding(.vertical, store.compactView ? 8 : 12)
            }
            .background(Color(nsColor: .textBackgroundColor))

            WorkspaceStateOverlay(store: store, isDropTarget: isDropTarget)
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget) { providers in
            importDroppedItems(from: providers)
            return true
        }
    }

    private func importDroppedItems(from providers: [NSItemProvider]) {
        FileDropProviderLoader.loadFileURLs(from: providers) { droppedURLs in
            _ = store.dropItems(droppedURLs)
        }
    }
}

private struct FileIconCell: View {
    let store: BrowserStore
    let item: FileItem
    @State private var isHovering = false

    private var isSelected: Bool {
        store.selectedItemIDs.contains(item.id)
    }

    var body: some View {
        VStack(spacing: store.compactView ? 4 : 7) {
            ZStack(alignment: .topLeading) {
                FileIconImage(item: item, size: store.compactView ? 36 : 50)
                    .frame(width: store.compactView ? 46 : 62, height: store.compactView ? 36 : 48)

                if store.showsItemCheckboxes {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { isSelected },
                            set: { store.setItemSelection(item.id, isSelected: $0) }
                        )
                    )
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                }
            }

            FileNameCellText(store: store, item: item, lineLimit: 2, alignment: .center)
                .font(store.compactView ? .caption2 : .caption)
                .multilineTextAlignment(.center)
                .frame(width: store.compactView ? 84 : 108, alignment: .top)
                .frame(minHeight: store.compactView ? 26 : 32, alignment: .top)
        }
        .padding(.vertical, store.compactView ? 5 : 8)
        .padding(.horizontal, store.compactView ? 4 : 6)
        .frame(maxWidth: .infinity)
        .background(iconCellBackground, in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(iconCellStroke)
        }
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .fileActivationGesture(
            select: {
                store.selectedItemIDs = [item.id]
            },
            open: {
                store.openItem(item)
            }
        )
        .fileDragDropTarget(store: store, item: item)
        .contextMenu {
            FileItemContextMenu(store: store, item: item)
        }
        .onHover { isHovering = $0 }
    }

    private var iconCellBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.16)
        }

        if isHovering {
            return Color(nsColor: .selectedContentBackgroundColor).opacity(0.08)
        }

        return .clear
    }

    private var iconCellStroke: Color {
        if isSelected {
            return Color.accentColor.opacity(0.45)
        }

        if isHovering {
            return Color(nsColor: .separatorColor).opacity(0.24)
        }

        return .clear
    }
}

private struct FileNameCellText: View {
    @Bindable var store: BrowserStore
    let item: FileItem
    var lineLimit: Int = 1
    var alignment: TextAlignment = .leading
    @FocusState private var isFocused: Bool

    private var isRenaming: Bool {
        store.inlineRenameItemID == item.id
    }

    var body: some View {
        Group {
            if isRenaming {
                TextField("Name", text: $store.inlineRenameDraft)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1)
                    .focused($isFocused)
                    .onSubmit {
                        store.commitInlineRename()
                    }
                    .onExitCommand {
                        store.cancelInlineRename()
                    }
                    .onAppear {
                        isFocused = true
                    }
            } else {
                Text(store.displayName(for: item))
                    .lineLimit(lineLimit)
                    .truncationMode(.middle)
                    .multilineTextAlignment(alignment)
            }
        }
    }
}

private struct FolderTypeLogoStack: View {
    let items: [FileItem]
    var iconSize: CGFloat = 12
    var maxLogos = 4
    var sampleLimit = 160

    var body: some View {
        let logoItems = FolderTypeLogoResolver.logoItems(
            from: items,
            maxLogos: maxLogos,
            sampleLimit: sampleLimit
        )

        if !logoItems.isEmpty {
            HStack(spacing: -4) {
                ForEach(logoItems) { item in
                    FileTypeLogoBubble(item: item, iconSize: iconSize)
                }
            }
            .padding(.horizontal, 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("File type application logos")
        }
    }
}

private struct FileTypeLogoBubble: View {
    let item: FileItem
    let iconSize: CGFloat
    @Environment(\.betterFilesMasksSensitiveData) private var masksSensitiveData
    @State private var applicationIcon: NSImage?

    init(item: FileItem, iconSize: CGFloat) {
        self.item = item
        self.iconSize = iconSize
        _applicationIcon = State(initialValue: FileIconLibrary.cachedApplicationBadgeIcon(for: item))
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay {
                    Circle()
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.30))
                }

            if masksSensitiveData {
                Image(systemName: item.canOpenAsFolder ? "folder.fill" : "doc.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: iconSize, height: iconSize)
            } else if let applicationIcon {
                Image(nsImage: applicationIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
            } else {
                FileIconImage(item: item, size: iconSize)
            }
        }
        .frame(width: iconSize + 8, height: iconSize + 8)
        .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 0.5)
        .help(item.normalizedFileExtension.uppercased())
        .task(id: applicationBadgeTaskID) {
            guard !masksSensitiveData else {
                applicationIcon = nil
                return
            }

            guard FileIconLibrary.shouldRequestApplicationBadge(for: item, iconSize: iconSize) else {
                applicationIcon = nil
                return
            }

            applicationIcon = FileIconLibrary.cachedApplicationBadgeIcon(for: item)
            if applicationIcon == nil {
                applicationIcon = await FileIconLibrary.applicationBadgeIconAsync(for: item)
            }
        }
    }

    private var applicationBadgeTaskID: String {
        "\(item.kind.cacheKeyPart)|\(item.normalizedFileExtension)|\(Int(iconSize.rounded()))|masked:\(masksSensitiveData)"
    }
}

private struct FileKindLabel: View {
    let item: FileItem
    let iconSize: CGFloat
    var showsApplicationName = false
    @Environment(\.betterFilesMasksSensitiveData) private var masksSensitiveData
    @State private var applicationIcon: NSImage?
    @State private var applicationName: String?

    init(item: FileItem, iconSize: CGFloat, showsApplicationName: Bool = false) {
        self.item = item
        self.iconSize = iconSize
        self.showsApplicationName = showsApplicationName
        _applicationIcon = State(initialValue: FileIconLibrary.cachedApplicationBadgeIcon(for: item))
        _applicationName = State(initialValue: showsApplicationName ? FileIconLibrary.cachedApplicationDisplayName(for: item) : nil)
    }

    var body: some View {
        HStack(spacing: 5) {
            if !masksSensitiveData, let applicationIcon {
                Image(nsImage: applicationIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
                    .accessibilityHidden(true)
            }

            Text(item.kindLabel)
                .lineLimit(1)
                .truncationMode(.tail)

            if !masksSensitiveData, showsApplicationName, let applicationName {
                Text("· \(applicationName)")
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .task(id: applicationBadgeTaskID) {
            guard !masksSensitiveData else {
                applicationIcon = nil
                applicationName = nil
                return
            }

            guard FileIconLibrary.shouldRequestApplicationBadge(for: item, iconSize: iconSize) else {
                applicationIcon = nil
                applicationName = nil
                return
            }

            applicationIcon = FileIconLibrary.cachedApplicationBadgeIcon(for: item)
            if applicationIcon == nil {
                applicationIcon = await FileIconLibrary.applicationBadgeIconAsync(for: item)
            }

            if showsApplicationName {
                applicationName = FileIconLibrary.cachedApplicationDisplayName(for: item)
                if applicationName == nil {
                    applicationName = await FileIconLibrary.applicationDisplayNameAsync(for: item)
                }
            } else {
                applicationName = nil
            }
        }
    }

    private var applicationBadgeTaskID: String {
        "\(item.kind.cacheKeyPart)|\(item.normalizedFileExtension)|\(Int(iconSize.rounded()))|\(showsApplicationName)|masked:\(masksSensitiveData)"
    }
}

private struct FileItemDragDropModifier: ViewModifier {
    let store: BrowserStore
    let item: FileItem
    @State private var isFolderDropTarget = false

    func body(content: Content) -> some View {
        content
            .onDrag {
                store.prepareContextSelection(for: item.id)
                return NSItemProvider(object: item.url as NSURL)
            }
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isFolderDropTarget) { providers in
                guard item.canOpenAsFolder else {
                    return false
                }

                importDroppedItems(from: providers, to: item.url)
                return true
            }
            .overlay {
                if item.canOpenAsFolder, isFolderDropTarget {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .allowsHitTesting(false)
                }
            }
    }

    private func importDroppedItems(from providers: [NSItemProvider], to destinationURL: URL) {
        FileDropProviderLoader.loadFileURLs(from: providers) { droppedURLs in
            _ = store.dropItems(droppedURLs, to: destinationURL)
        }
    }
}

private struct FileActivationGestureModifier: ViewModifier {
    let select: () -> Void
    let open: () -> Void

    func body(content: Content) -> some View {
        content
            .background(FileActivationClickBridge(select: select, open: open))
    }
}

private struct FileActivationClickBridge: NSViewRepresentable {
    let select: () -> Void
    let open: () -> Void

    func makeNSView(context: Context) -> ActivationView {
        ActivationView()
    }

    func updateNSView(_ nsView: ActivationView, context: Context) {
        FileActivationClickRegistry.shared.register(
            view: nsView,
            select: select,
            open: open
        )
    }

    static func dismantleNSView(_ nsView: ActivationView, coordinator: ()) {
        FileActivationClickRegistry.shared.unregister(view: nsView)
    }

    final class ActivationView: NSView {
        override var isFlipped: Bool {
            true
        }
    }
}

@MainActor
private final class FileActivationClickRegistry {
    static let shared = FileActivationClickRegistry()

    private struct Entry {
        weak var view: NSView?
        let select: () -> Void
        let open: () -> Void
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    private var eventMonitor: Any?

    func register(view: NSView, select: @escaping () -> Void, open: @escaping () -> Void) {
        entries[ObjectIdentifier(view)] = Entry(view: view, select: select, open: open)
        installMonitorIfNeeded()
    }

    func unregister(view: NSView) {
        entries[ObjectIdentifier(view)] = nil
        pruneReleasedViews()

        if entries.isEmpty, let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func installMonitorIfNeeded() {
        guard eventMonitor == nil else {
            return
        }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        guard let window = event.window else {
            return
        }

        pruneReleasedViews()

        for entry in entries.values {
            guard let view = entry.view, view.window === window else {
                continue
            }

            let localPoint = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(localPoint) else {
                continue
            }

            if event.clickCount >= 2 {
                entry.open()
            } else {
                entry.select()
            }
            return
        }
    }

    private func pruneReleasedViews() {
        entries = entries.filter { $0.value.view != nil }
    }
}

private extension View {
    func sidebarFileDropTarget(store: BrowserStore, destinationURL: URL) -> some View {
        modifier(SidebarFileDropTargetModifier(store: store, destinationURL: destinationURL))
    }

    func fileActivationGesture(select: @escaping () -> Void, open: @escaping () -> Void) -> some View {
        modifier(FileActivationGestureModifier(select: select, open: open))
    }

    func fileDragDropTarget(store: BrowserStore, item: FileItem) -> some View {
        modifier(FileItemDragDropModifier(store: store, item: item))
    }
}

private struct FileItemContextMenu: View {
    let store: BrowserStore
    let item: FileItem

    var body: some View {
        Button("Open") {
            prepareContextSelection()
            store.openSelectedItems()
        }

        if store.canShowPackageContents(item) {
            Button("Show Package Contents") {
                prepareContextSelection()
                store.showSelectedPackageContents()
            }
        }

        if store.canOpenInNewTab(item) {
            Button("Open in New Tab") {
                prepareContextSelection()
                store.openSelectionInNewTabs()
            }
        }

        Button("Reveal in Finder") {
            prepareContextSelection()
            store.revealSelectedInFinder()
        }

        Button("Quick Look") {
            prepareContextSelection()
            store.quickLookSelectedItems()
        }

        if !item.canOpenAsFolder {
            OpenWithMenu(store: store, item: item)
        }

        Divider()

        Button("Cut") {
            prepareContextSelection()
            store.cutSelectedItems()
        }

        Button("Copy") {
            prepareContextSelection()
            store.copySelectedItems()
        }

        if item.canOpenAsFolder {
            Button("Paste into Folder") {
                store.pasteItems(to: item.url)
            }
            .disabled(!store.canPasteItems)
        }

        Button("Duplicate") {
            prepareContextSelection()
            store.duplicateSelectedItems()
        }

        Button(renameTitle) {
            prepareContextSelection()
            if contextSelectionCount > 1 {
                store.batchRenameSelection()
            } else {
                store.renameSelectedItem()
            }
        }

        Button("Compress to Zip") {
            prepareContextSelection()
            store.compressSelectedItems()
        }

        if item.url.pathExtension.localizedCaseInsensitiveCompare("zip") == .orderedSame || store.canExtractSelectedArchives {
            Button("Extract Zip") {
                prepareContextSelection()
                store.extractSelectedArchives()
            }
        }

        Button("Move to Trash", role: .destructive) {
            prepareContextSelection()
            store.moveSelectedItemToTrash()
        }

        Divider()

        Button("Copy Path") {
            prepareContextSelection()
            store.copySelectedPaths()
        }

        Button("Share...") {
            prepareContextSelection()
            store.shareSelectedItems()
        }

        Button("Properties") {
            prepareContextSelection()
            store.showPropertiesForSelection()
        }
    }

    private var contextSelectionCount: Int {
        store.contextSelectionIDs(for: item.id).count
    }

    private var renameTitle: String {
        contextSelectionCount > 1 ? "Batch Rename" : "Rename"
    }

    private func prepareContextSelection() {
        store.prepareContextSelection(for: item.id)
    }
}

private struct OpenWithMenu: View {
    let store: BrowserStore
    var item: FileItem?

    private var applications: [OpenWithApplication] {
        if let item {
            return store.openWithApplications(forContextItemID: item.id, limit: 8)
        }

        return store.openWithApplicationsForSelection(limit: 8)
    }

    var body: some View {
        let suggestedApplications = applications

        Menu {
            if suggestedApplications.isEmpty {
                Text("No suggested applications")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(suggestedApplications) { application in
                    Button {
                        prepareSelection()
                        store.openSelectedItems(withApplicationAt: application.url)
                    } label: {
                        OpenWithApplicationMenuLabel(application: application)
                    }
                    .help(application.url.path)
                }

                Divider()
            }

            Button("Choose Application...") {
                prepareSelection()
                store.chooseApplicationForSelection()
            }
        } label: {
            Label("Open With", systemImage: "app")
        }
    }

    private func prepareSelection() {
        if let item {
            store.prepareContextSelection(for: item.id)
        }
    }
}

private struct OpenWithApplicationMenuLabel: View {
    let application: OpenWithApplication

    var body: some View {
        HStack(spacing: 7) {
            LocationIconImage(url: application.url, fallbackSystemImage: "app", size: 16)

            Text(application.displayName)
                .lineLimit(1)
        }
    }
}

private struct PreviewPanel: View {
    let store: BrowserStore

    private var items: [FileItem] {
        store.selectedItems
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)

                Text("Preview")
                    .font(.caption.weight(.semibold))

                Spacer(minLength: 0)

                Text(previewStateLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider()

            Group {
                if items.count == 1, let item = items.first {
                    singleItemPreview(item)
                } else if items.isEmpty {
                    emptyPreview
                } else {
                    multiSelectionPreview
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.42))
                .frame(width: 1)
        }
    }

    private var previewStateLabel: String {
        if items.count == 1 {
            return "1 item"
        }

        if items.isEmpty {
            return "None"
        }

        return "\(items.count) items"
    }

    private func singleItemPreview(_ item: FileItem) -> some View {
        VStack(spacing: 12) {
            NativeThumbnailView(
                item: item,
                thumbnailSize: CGSize(width: 360, height: 360),
                fallbackIconSize: 104
            )
            .frame(maxWidth: .infinity)
            .frame(height: 220)

            VStack(spacing: 5) {
                Text(store.displayName(for: item))
                    .font(.headline)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)

                FileKindLabel(item: item, iconSize: 13, showsApplicationName: true)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                InspectorActionButton("Quick Look", systemImage: "eye") {
                    store.quickLookSelectedItems()
                }

                InspectorActionButton("Reveal", systemImage: "finder") {
                    store.revealSelectedInFinder()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                PreviewFactRow(label: "Name", value: store.displayName(for: item))
                PreviewFactRow(label: "Kind", value: item.kindLabel)
                PreviewFactRow(label: "Size", value: item.byteCount.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Unknown")
                PreviewFactRow(label: "Path", value: store.masksSensitiveData ? "Private path" : item.url.path, lineLimit: 5)
            }
        }
        .padding(12)
    }

    private var multiSelectionPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 48, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)

            Text("\(items.count) items selected")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)

            InspectorActionGrid(store: store, selectedItem: nil)

            Divider()

            Text(store.selectionSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(5)
        }
        .padding(12)
    }

    private var emptyPreview: some View {
        ContentUnavailableView(
            "No Preview",
            systemImage: "rectangle.split.2x1",
            description: Text("Select a file to see its native thumbnail and actions.")
        )
        .padding(16)
    }
}

private struct PreviewFactRow: View {
    let label: String
    let value: String
    var lineLimit: Int = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption)
                .lineLimit(lineLimit)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DetailPanel: View {
    let store: BrowserStore

    private var items: [FileItem] {
        store.selectedItems
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if items.count == 1, let item = items.first, let summary = store.inspectorSummary {
                    if !store.showsPreviewPanel {
                        FilePreviewPane(item: item, displayName: store.displayName(for: item))
                    }

                    HStack(spacing: 10) {
                        FileIconImage(item: item, size: 34)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.displayName(for: item))
                                .font(.headline)
                                .lineLimit(2)
                                .truncationMode(.middle)
                            FileKindLabel(item: item, iconSize: 13, showsApplicationName: true)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    InspectorActionGrid(store: store, selectedItem: item)

                    Divider()

                    InspectorPropertyRows(summary: summary)

                    InspectorAttributesPanel(store: store, item: item)

                    if item.posixPermissions != nil {
                        Divider()

                        InspectorPermissionsMatrix(store: store, item: item)
                    }

                    Divider()

                    Text(store.masksSensitiveData ? "Private path" : item.url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(6)
                } else if let summary = store.inspectorSummary {
                    HStack(spacing: 10) {
                        Image(systemName: "checklist")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(summary.title)
                                .font(.headline)
                            Text(summary.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    InspectorActionGrid(store: store, selectedItem: nil)

                    Divider()

                    InspectorPropertyRows(summary: summary)
                } else {
                    ContentUnavailableView(
                        "No Selection",
                        systemImage: "sidebar.right",
                        description: Text("Select an item to inspect its metadata.")
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct InspectorAttributesPanel: View {
    let store: BrowserStore
    let item: FileItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Attributes", systemImage: "switch.2")
                    .font(.caption.weight(.semibold))

                Spacer()

                Text(item.writableLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                attributeToggle(
                    title: "Hidden",
                    subtitle: "Hide or show this item in normal folder views.",
                    systemImage: "eye.slash",
                    isOn: item.isHidden
                ) { isOn in
                    store.setSelectedItemsHidden(isOn)
                }

                Divider()
                    .padding(.leading, 31)

                attributeToggle(
                    title: "Locked",
                    subtitle: "Prevent accidental changes using the macOS locked flag.",
                    systemImage: "lock",
                    isOn: item.isLocked
                ) { isOn in
                    store.setSelectedItemsLocked(isOn)
                }

                if item.posixPermissions != nil {
                    Divider()
                        .padding(.leading, 31)

                    attributeToggle(
                        title: "Writable",
                        subtitle: "Toggle write access for owner/group/everyone.",
                        systemImage: "pencil.line",
                        isOn: item.hasPermission(.ownerWrite)
                    ) { isOn in
                        store.setSelectedItemsWritable(isOn)
                    }
                }

                Divider()
                    .padding(.leading, 31)

                Button {
                    store.promptSetTagsForSelection()
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "tag")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Finder Tags")
                                .font(.system(size: 12, weight: .semibold))

                            Text("Set or clear macOS Finder tags.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.32))
            }
        }
    }

    private func attributeToggle(
        title: String,
        subtitle: String,
        systemImage: String,
        isOn: Bool,
        action: @escaping (Bool) -> Void
    ) -> some View {
        Toggle(
            isOn: Binding(
                get: { isOn },
                set: { newValue in
                    action(newValue)
                }
            )
        ) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                    .frame(width: 23, height: 23)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption.weight(.medium))

                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .help(subtitle)
    }
}

private struct InspectorActionGrid: View {
    let store: BrowserStore
    let selectedItem: FileItem?

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                InspectorActionButton("Open", systemImage: "arrow.up.right.square") {
                    _ = store.openSelectedItems()
                }

                InspectorActionButton("Reveal", systemImage: "finder") {
                    store.revealSelectedInFinder()
                }
            }

            GridRow {
                InspectorActionButton("Copy Path", systemImage: "doc.on.doc") {
                    store.copySelectedPaths()
                }

                InspectorActionButton("Copy as Path", systemImage: "quote.bubble") {
                    store.copySelectedPathsAsQuotedPaths()
                }
            }

            GridRow {
                InspectorActionButton("Copy Name", systemImage: "textformat") {
                    store.copySelectedNames()
                }

                InspectorActionButton("Copy Folder", systemImage: "folder.badge.gearshape") {
                    store.copySelectedParentFolderPaths()
                }

                InspectorActionButton("Quick Look", systemImage: "eye") {
                    store.quickLookSelectedItems()
                }
            }

            GridRow {
                InspectorActionButton("Share", systemImage: "square.and.arrow.up") {
                    store.shareSelectedItems()
                }

                InspectorActionButton("Terminal", systemImage: "terminal") {
                    store.openSelectionInTerminal()
                }
                .disabled(!store.canOpenSelectionInTerminal)
            }
        }
        .disabled(store.selectedItems.isEmpty)
        .help(selectedItem?.url.path ?? store.selectionSummary)
    }
}

private struct InspectorActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(title)
    }
}

private struct InspectorPropertyRows: View {
    let summary: FileInspectorSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let kindLabel = summary.kindLabel {
                InspectorPropertyRow(label: "Kind", value: kindLabel)
            }

            if let application = summary.defaultApplication {
                InspectorApplicationRow(application: application)
            }

            InspectorPropertyRow(label: summary.itemCount == 1 ? "Size" : "Known size", value: summary.sizeLabel)

            if summary.itemCount > 1 {
                InspectorPropertyRow(label: "Folders", value: "\(summary.folderCount)")
                InspectorPropertyRow(label: "Files", value: "\(summary.fileCount)")

                if summary.packageCount > 0 {
                    InspectorPropertyRow(label: "Packages", value: "\(summary.packageCount)")
                }
            }

            if let modifiedLabel = summary.modifiedLabel {
                InspectorPropertyRow(label: "Modified", value: modifiedLabel)
            }

            if let createdLabel = summary.createdLabel {
                InspectorPropertyRow(label: "Created", value: createdLabel)
            }

            if let accessedLabel = summary.accessedLabel {
                InspectorPropertyRow(label: "Accessed", value: accessedLabel)
            }

            if let hiddenLabel = summary.hiddenLabel {
                InspectorPropertyRow(label: "Hidden", value: hiddenLabel)
            }

            if let lockedLabel = summary.lockedLabel {
                InspectorPropertyRow(label: "Locked", value: lockedLabel)
            }

            if let permissionsLabel = summary.permissionsLabel {
                InspectorPropertyRow(label: "Permissions", value: permissionsLabel)
            }

            if let ownerLabel = summary.ownerLabel {
                InspectorPropertyRow(label: "Owner", value: ownerLabel)
            }

            if let groupLabel = summary.groupLabel {
                InspectorPropertyRow(label: "Group", value: groupLabel)
            }

            if let accessLabel = summary.accessLabel {
                InspectorPropertyRow(label: "Access", value: accessLabel)
            }

            if let accessControlLabel = summary.accessControlLabel {
                InspectorPropertyRow(label: "Access Control", value: accessControlLabel)
            }

            if let tagsLabel = summary.tagsLabel {
                InspectorPropertyRow(label: "Tags", value: tagsLabel)
            }

            if let extendedAttributesLabel = summary.extendedAttributesLabel {
                InspectorPropertyRow(label: "Extended Attributes", value: extendedAttributesLabel)
            }

            if let parentPathLabel = summary.parentPathLabel {
                InspectorPropertyRow(label: "Folder", value: parentPathLabel)
            }
        }
        .font(.caption)
    }
}

private struct InspectorApplicationRow: View {
    let application: OpenWithApplication

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Opens With")
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)

            HStack(spacing: 6) {
                LocationIconImage(url: application.url, fallbackSystemImage: "app", size: 14)

                Text(application.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .help(application.url.path)

            Spacer(minLength: 0)
        }
    }
}

private struct InspectorPermissionsMatrix: View {
    let store: BrowserStore
    let item: FileItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Permissions", systemImage: "lock")
                    .font(.caption.weight(.semibold))

                Spacer()

                Text(item.permissionsLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Grid(horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    permissionHeader("Read")
                    permissionHeader("Write")
                    permissionHeader("Run")
                }

                permissionRow(title: "Owner", read: .ownerRead, write: .ownerWrite, execute: .ownerExecute)
                permissionRow(title: "Group", read: .groupRead, write: .groupWrite, execute: .groupExecute)
                permissionRow(title: "Everyone", read: .everyoneRead, write: .everyoneWrite, execute: .everyoneExecute)
            }

            if item.canOpenAsFolder {
                Button {
                    store.applySelectedFolderPermissionsToEnclosedItems()
                } label: {
                    Label("Apply to Enclosed Items", systemImage: "folder.badge.gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Apply this folder's current POSIX permissions to the items inside it.")
                .disabled(!store.canApplySelectedFolderPermissionsToEnclosedItems)
            }
        }
        .padding(9)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.32))
        }
    }

    private func permissionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 45)
    }

    private func permissionRow(
        title: String,
        read: FilePermissionBits,
        write: FilePermissionBits,
        execute: FilePermissionBits
    ) -> some View {
        GridRow {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            permissionToggle(read, label: "\(title) read")
            permissionToggle(write, label: "\(title) write")
            permissionToggle(execute, label: "\(title) execute")
        }
    }

    private func permissionToggle(_ bit: FilePermissionBits, label: String) -> some View {
        Toggle(
            "",
            isOn: Binding(
                get: { item.hasPermission(bit) },
                set: { enabled in
                    store.setSelectedItemsPermissionBits(bit, enabled: enabled)
                }
            )
        )
        .toggleStyle(.checkbox)
        .labelsHidden()
        .frame(width: 45)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct InspectorPropertyRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)

            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

private struct FilePreviewPane: View {
    let item: FileItem
    let displayName: String

    var body: some View {
        VStack(spacing: 8) {
            NativeThumbnailView(item: item)
                .frame(maxWidth: .infinity)
                .frame(height: 154)

            Text(displayName)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.34))
        }
    }
}

private struct NativeThumbnailView: View {
    let item: FileItem
    var thumbnailSize = CGSize(width: 280, height: 280)
    var fallbackIconSize: CGFloat = 76
    @Environment(\.betterFilesMasksSensitiveData) private var masksSensitiveData
    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .controlBackgroundColor))

            if masksSensitiveData {
                FileIconImage(item: item, size: fallbackIconSize)
                    .symbolRenderingMode(.hierarchical)
                    .opacity(0.88)
            } else if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(8)
                    .transition(.opacity)
            } else {
                FileIconImage(item: item, size: fallbackIconSize)
                    .symbolRenderingMode(.hierarchical)
                    .opacity(0.88)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .task(id: thumbnailTaskID) {
            thumbnail = nil
            guard !masksSensitiveData else {
                return
            }

            guard NativeThumbnailLibrary.shouldRequestThumbnail(for: item, iconSize: fallbackIconSize) else {
                return
            }

            thumbnail = await NativeThumbnailLibrary.thumbnail(
                for: item.url,
                size: thumbnailSize
            )
        }
    }

    private var thumbnailTaskID: String {
        "\(item.id)|\(Int(thumbnailSize.width.rounded()))x\(Int(thumbnailSize.height.rounded()))|masked:\(masksSensitiveData)"
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if FileAccessRecoveryResolver.shouldSuggestFullDiskAccess(for: message) {
                Button {
                    FileAccessRecoveryResolver.openFullDiskAccessSettings()
                } label: {
                    Label("Full Disk Access", systemImage: "gearshape")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open Privacy & Security settings for Full Disk Access")
            }
        }
        .padding(10)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.red.opacity(0.16))
        }
    }
}

private struct StatusBar: View {
    let store: BrowserStore

    var body: some View {
        ViewThatFits(in: .horizontal) {
            fullStatus
            compactStatus
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.34))
                .frame(height: 1)
        }
    }

    private var fullStatus: some View {
        HStack(spacing: 7) {
            StatusChip(
                text: "\(store.visibleItems.count) of \(store.items.count)",
                systemImage: "list.bullet.rectangle",
                prominence: .strong
            )

            if let searchSummary = store.searchSummary {
                StatusChip(
                    text: searchSummary.reachedLimit ? "\(searchSummary.itemCount)+ matches" : "\(searchSummary.itemCount) matches",
                    systemImage: "magnifyingglass",
                    prominence: searchSummary.reachedLimit ? .warning : .standard
                )
            } else if store.searchesSubfolders {
                StatusChip(text: "Subfolders", systemImage: "scope")
            }

            if let volumeSummary = store.currentVolumeStatusSummary {
                StatusChip(text: volumeSummary.statusLabel, systemImage: "internaldrive")
            }

            Spacer(minLength: 8)

            if let selectionStatusSummary = store.selectionStatusSummary {
                StatusChip(
                    text: selectionStatusSummary,
                    systemImage: "checkmark.circle",
                    prominence: .strong
                )
                .frame(maxWidth: 280)
            }
        }
    }

    private var compactStatus: some View {
        HStack(spacing: 7) {
            StatusChip(
                text: "\(store.visibleItems.count)/\(store.items.count)",
                systemImage: "list.bullet.rectangle",
                prominence: .strong
            )

            if let searchSummary = store.searchSummary {
                StatusChip(
                    text: searchSummary.reachedLimit ? "\(searchSummary.itemCount)+" : "\(searchSummary.itemCount)",
                    systemImage: "magnifyingglass"
                )
            }

            Spacer(minLength: 8)

            if let selectionStatusSummary = store.selectionStatusSummary {
                Text(selectionStatusSummary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

private struct StatusDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.42))
            .frame(width: 1, height: 16)
    }
}

private struct StatusChip: View {
    enum Prominence {
        case standard
        case strong
        case positive
        case warning
    }

    let text: String
    let systemImage: String
    var prominence: Prominence = .standard

    var body: some View {
        Label {
            Text(text)
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(iconColor)
        }
        .font(.system(size: 11, weight: prominence == .strong ? .semibold : .medium))
        .foregroundStyle(prominence == .strong ? Color.primary : Color.secondary)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(strokeColor)
        }
    }

    private var iconColor: Color {
        switch prominence {
        case .standard, .strong:
            return .secondary
        case .positive:
            return .accentColor
        case .warning:
            return .orange
        }
    }

    private var backgroundColor: Color {
        switch prominence {
        case .standard:
            return Color(nsColor: .windowBackgroundColor).opacity(0.52)
        case .strong:
            return Color(nsColor: .windowBackgroundColor).opacity(0.78)
        case .positive:
            return Color.accentColor.opacity(0.08)
        case .warning:
            return Color.orange.opacity(0.09)
        }
    }

    private var strokeColor: Color {
        switch prominence {
        case .standard:
            return Color(nsColor: .separatorColor).opacity(0.16)
        case .strong:
            return Color(nsColor: .separatorColor).opacity(0.28)
        case .positive:
            return Color.accentColor.opacity(0.16)
        case .warning:
            return Color.orange.opacity(0.22)
        }
    }
}

private struct FileIconImage: View {
    let item: FileItem
    let size: CGFloat
    @Environment(\.betterFilesMasksSensitiveData) private var masksSensitiveData
    @State private var fileIcon: NSImage?
    @State private var thumbnail: NSImage?
    @State private var applicationBadgeIcon: NSImage?

    init(item: FileItem, size: CGFloat) {
        self.item = item
        self.size = size
        _fileIcon = State(initialValue: FileIconLibrary.cachedIcon(for: item, prefersFileSpecificIcon: size >= 32))
        _applicationBadgeIcon = State(initialValue: FileIconLibrary.cachedApplicationBadgeIcon(for: item))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if masksSensitiveData {
                    Image(systemName: privacySystemImageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                } else if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: max(3, size * 0.08), style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: max(3, size * 0.08), style: .continuous)
                                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.20))
                        }
                } else if let fileIcon {
                    Image(nsImage: fileIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: item.systemImageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)

            if !masksSensitiveData, size >= 16, let applicationIcon = applicationBadgeIcon {
                Image(nsImage: applicationIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: applicationBadgeSize, height: applicationBadgeSize)
                    .padding(size < 24 ? 1.5 : 2)
                    .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 3))
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.32))
                    }
                    .shadow(color: .black.opacity(0.08), radius: 1.5, x: 0, y: 0.5)
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: fileIconTaskID) {
            guard !masksSensitiveData else {
                fileIcon = nil
                return
            }

            fileIcon = FileIconLibrary.cachedIcon(for: item, prefersFileSpecificIcon: prefersFileSpecificIcon)
            if fileIcon == nil {
                fileIcon = await FileIconLibrary.iconAsync(for: item, prefersFileSpecificIcon: prefersFileSpecificIcon)
            }
        }
        .task(id: applicationBadgeTaskID) {
            guard !masksSensitiveData else {
                applicationBadgeIcon = nil
                return
            }

            guard FileIconLibrary.shouldRequestApplicationBadge(for: item, iconSize: size) else {
                applicationBadgeIcon = nil
                return
            }

            applicationBadgeIcon = FileIconLibrary.cachedApplicationBadgeIcon(for: item)
            if applicationBadgeIcon == nil {
                applicationBadgeIcon = await FileIconLibrary.applicationBadgeIconAsync(for: item)
            }
        }
        .task(id: thumbnailTaskID) {
            guard !masksSensitiveData else {
                thumbnail = nil
                return
            }

            guard NativeThumbnailLibrary.shouldRequestThumbnail(for: item, iconSize: size) else {
                thumbnail = nil
                return
            }

            thumbnail = await NativeThumbnailLibrary.thumbnail(
                for: item.url,
                size: CGSize(width: size * 3, height: size * 3)
            )
        }
    }

    private var fileIconTaskID: String {
        "\(item.id)|\(item.kind.cacheKeyPart)|specific:\(prefersFileSpecificIcon)|masked:\(masksSensitiveData)"
    }

    private var thumbnailTaskID: String {
        "\(item.id)|\(Int(size.rounded()))|masked:\(masksSensitiveData)"
    }

    private var applicationBadgeTaskID: String {
        "\(item.kind.cacheKeyPart)|\(item.normalizedFileExtension)|\(Int(size.rounded()))|masked:\(masksSensitiveData)"
    }

    private var applicationBadgeSize: CGFloat {
        size < 24 ? 11 : max(14, size * 0.42)
    }

    private var prefersFileSpecificIcon: Bool {
        size >= 32
    }

    private var privacySystemImageName: String {
        item.canOpenAsFolder ? "folder.fill" : "doc.fill"
    }
}

private extension FileItem.Kind {
    var cacheKeyPart: String {
        switch self {
        case .folder:
            return "folder"
        case .package:
            return "package"
        case .file:
            return "file"
        }
    }
}

private struct LocationIconImage: View {
    let url: URL?
    let fallbackSystemImage: String
    let size: CGFloat
    let showsApplicationBadge: Bool
    @Environment(\.betterFilesMasksSensitiveData) private var masksSensitiveData
    @State private var locationIcon: NSImage?
    @State private var applicationBadgeIcon: NSImage?

    init(url: URL?, fallbackSystemImage: String, size: CGFloat, showsApplicationBadge: Bool = false) {
        self.url = url
        self.fallbackSystemImage = fallbackSystemImage
        self.size = size
        self.showsApplicationBadge = showsApplicationBadge
        _locationIcon = State(initialValue: FileIconLibrary.cachedIcon(for: url))
        _applicationBadgeIcon = State(initialValue: showsApplicationBadge ? FileIconLibrary.cachedApplicationBadgeIcon(forFileURL: url) : nil)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if masksSensitiveData {
                    Image(systemName: fallbackSystemImage)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                } else if isTrashLocation {
                    Image(systemName: fallbackSystemImage)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                } else if let locationIcon {
                    Image(nsImage: locationIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: fallbackSystemImage)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)

            if !masksSensitiveData, size >= 16, let applicationBadgeIcon {
                Image(nsImage: applicationBadgeIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: max(9, size * 0.58), height: max(9, size * 0.58))
                    .padding(1.5)
                    .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 2.5, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.30))
                    }
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: locationIconTaskID) {
            guard !masksSensitiveData else {
                locationIcon = nil
                return
            }

            guard !isTrashLocation, url != nil else {
                locationIcon = nil
                return
            }

            locationIcon = FileIconLibrary.cachedIcon(for: url)
            if locationIcon == nil {
                locationIcon = await FileIconLibrary.iconAsync(for: url)
            }
        }
        .task(id: applicationBadgeTaskID) {
            guard !masksSensitiveData else {
                applicationBadgeIcon = nil
                return
            }

            guard let url,
                  showsApplicationBadge,
                  !isTrashLocation,
                  FileIconLibrary.shouldRequestApplicationBadge(forFileURL: url, iconSize: size) else {
                applicationBadgeIcon = nil
                return
            }

            applicationBadgeIcon = FileIconLibrary.cachedApplicationBadgeIcon(forFileURL: url)
            if applicationBadgeIcon == nil {
                applicationBadgeIcon = await FileIconLibrary.applicationBadgeIconAsync(forFileURL: url)
            }
        }
    }

    private var isTrashLocation: Bool {
        guard let url else {
            return false
        }

        return fallbackSystemImage == "trash" && url.lastPathComponent == ".Trash"
    }

    private var locationIconTaskID: String {
        "\(url?.standardizedFileURL.path ?? "nil")|\(fallbackSystemImage)|\(Int(size.rounded()))|masked:\(masksSensitiveData)"
    }

    private var applicationBadgeTaskID: String {
        "\(url?.standardizedFileURL.pathExtension.lowercased() ?? "")|\(showsApplicationBadge)|\(Int(size.rounded()))|masked:\(masksSensitiveData)"
    }
}

@MainActor
private enum NativeThumbnailLibrary {
    private static let cache = NSCache<NSString, NSImage>()
    private static var missingThumbnailKeys: Set<String> = []

    static func shouldRequestThumbnail(for item: FileItem, iconSize: CGFloat) -> Bool {
        guard iconSize >= 32, item.kind == .file else {
            return false
        }

        return previewableFileExtensions.contains(item.normalizedFileExtension)
    }

    static func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let cacheKey = cacheKey(for: url, size: size) as NSString
        if let cachedThumbnail = cache.object(forKey: cacheKey) {
            return cachedThumbnail
        }

        guard !missingThumbnailKeys.contains(cacheKey as String) else {
            return nil
        }

        let image = await withCheckedContinuation { continuation in
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: size,
                scale: NSScreen.main?.backingScaleFactor ?? 2,
                representationTypes: [.thumbnail]
            )

            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.nsImage)
            }
        }

        guard let image else {
            missingThumbnailKeys.insert(cacheKey as String)
            return nil
        }

        cache.setObject(image, forKey: cacheKey)
        return image
    }

    private static func cacheKey(for url: URL, size: CGSize) -> String {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        return "\(url.standardizedFileURL.path)|\(width)x\(height)"
    }

    private static let previewableFileExtensions: Set<String> = [
        "ai",
        "bmp",
        "c",
        "cpp",
        "css",
        "csv",
        "gif",
        "heic",
        "heif",
        "html",
        "jpeg",
        "jpg",
        "js",
        "json",
        "key",
        "m",
        "md",
        "mov",
        "mp4",
        "numbers",
        "pages",
        "pdf",
        "png",
        "psd",
        "py",
        "rtf",
        "swift",
        "tif",
        "tiff",
        "ts",
        "txt",
        "webp",
        "xml"
    ]
}

@MainActor
private enum FileIconLibrary {
    private struct ApplicationMetadata {
        let icon: NSImage
        let displayName: String
    }

    private struct SendableImage: @unchecked Sendable {
        let image: NSImage
    }

    private static let cache = NSCache<NSString, NSImage>()
    private static var missingApplicationBadgeExtensions: Set<String> = []
    private static var applicationMetadataCache: [String: ApplicationMetadata] = [:]

    static func cachedIcon(for item: FileItem, prefersFileSpecificIcon: Bool = false) -> NSImage? {
        cache.object(forKey: cacheKey(for: item, prefersFileSpecificIcon: prefersFileSpecificIcon) as NSString)
    }

    static func warmVisibleIcons(
        for items: [FileItem],
        limit: Int = 220,
        prefersFileSpecificIcons: Bool = false
    ) async {
        guard !items.isEmpty else {
            return
        }

        await Task.yield()

        var warmedIconKeys: Set<String> = []
        var warmedBadgeExtensions: Set<String> = []

        for (index, item) in items.prefix(limit).enumerated() {
            guard !Task.isCancelled else {
                return
            }

            if index > 0, index.isMultiple(of: 24) {
                await Task.yield()
            }

            let itemCacheKey = cacheKey(for: item, prefersFileSpecificIcon: prefersFileSpecificIcons)
            if warmedIconKeys.insert(itemCacheKey).inserted,
               cache.object(forKey: itemCacheKey as NSString) == nil {
                _ = await iconAsync(for: item, prefersFileSpecificIcon: prefersFileSpecificIcons)
            }

            guard shouldRequestApplicationBadge(for: item, iconSize: 16) else {
                continue
            }

            let fileExtension = item.normalizedFileExtension
            if warmedBadgeExtensions.insert(fileExtension).inserted,
               cache.object(forKey: applicationBadgeCacheKey(for: fileExtension)) == nil {
                _ = await applicationBadgeIconAsync(for: item)
            }
        }
    }

    static func warmLocationIcons(for urls: [URL?], limit: Int = 180) async {
        guard !urls.isEmpty else {
            return
        }

        await Task.yield()

        var warmedLocationKeys: Set<String> = []
        var warmedBadgeExtensions: Set<String> = []
        for (index, url) in urls.compactMap(\.self).prefix(limit).enumerated() {
            guard !Task.isCancelled else {
                return
            }

            if index > 0, index.isMultiple(of: 24) {
                await Task.yield()
            }

            let path = url.standardizedFileURL.path
            let cacheKey = "location:\(path)"
            if warmedLocationKeys.insert(cacheKey).inserted,
               cache.object(forKey: cacheKey as NSString) == nil {
                _ = await iconAsync(for: url, key: cacheKey)
            }

            let fileExtension = url.pathExtension.lowercased()
            if shouldRequestApplicationBadge(forFileURL: url, iconSize: 16),
               warmedBadgeExtensions.insert(fileExtension).inserted,
               cache.object(forKey: applicationBadgeCacheKey(for: fileExtension)) == nil {
                _ = await applicationBadgeIconAsync(forFileURL: url)
            }
        }
    }

    static func iconAsync(for item: FileItem, prefersFileSpecificIcon: Bool = false) async -> NSImage {
        switch item.kind {
        case .folder:
            if prefersFileSpecificIcon || usesFileSpecificIcon(forFolderAt: item.url) {
                return await iconAsync(for: item.url, key: cacheKey(for: item, prefersFileSpecificIcon: prefersFileSpecificIcon))
            }

            return await iconForContentTypeAsync(.folder, key: cacheKey(for: item))
        case .package:
            if prefersFileSpecificIcon || usesFileSpecificIcon(forPackageExtension: item.normalizedFileExtension) {
                return await iconAsync(for: item.url, key: cacheKey(for: item, prefersFileSpecificIcon: prefersFileSpecificIcon))
            }
            return await iconForFileExtensionAsync(item.normalizedFileExtension, fallbackContentType: .package, key: cacheKey(for: item))
        case .file:
            let fileExtension = item.normalizedFileExtension
            if prefersFileSpecificIcon || usesFileSpecificIcon(forFileExtension: fileExtension) {
                return await iconAsync(for: item.url, key: cacheKey(for: item, prefersFileSpecificIcon: prefersFileSpecificIcon))
            }

            return await iconForFileExtensionAsync(fileExtension, fallbackContentType: .data, key: cacheKey(for: item))
        }
    }

    static func icon(for item: FileItem, prefersFileSpecificIcon: Bool = false) -> NSImage {
        switch item.kind {
        case .folder:
            if prefersFileSpecificIcon || usesFileSpecificIcon(forFolderAt: item.url) {
                return icon(for: item.url, key: cacheKey(for: item, prefersFileSpecificIcon: prefersFileSpecificIcon))
            }

            return icon(forContentType: .folder, key: cacheKey(for: item))
        case .package:
            if prefersFileSpecificIcon || usesFileSpecificIcon(forPackageExtension: item.normalizedFileExtension) {
                return icon(for: item.url, key: cacheKey(for: item, prefersFileSpecificIcon: prefersFileSpecificIcon))
            }
            return icon(forFileExtension: item.normalizedFileExtension, fallbackContentType: .package, key: cacheKey(for: item))
        case .file:
            let fileExtension = item.normalizedFileExtension
            if prefersFileSpecificIcon || usesFileSpecificIcon(forFileExtension: fileExtension) {
                return icon(for: item.url, key: cacheKey(for: item, prefersFileSpecificIcon: prefersFileSpecificIcon))
            }

            return icon(forFileExtension: fileExtension, fallbackContentType: .data, key: cacheKey(for: item))
        }
    }

    static func cachedIcon(for url: URL?) -> NSImage? {
        guard let url else {
            return nil
        }

        let path = url.standardizedFileURL.path
        return cache.object(forKey: "location:\(path)" as NSString)
    }

    private static func usesFileSpecificIcon(forPackageExtension fileExtension: String) -> Bool {
        FileItem.packageExtensions.contains(fileExtension)
    }

    private static func usesFileSpecificIcon(forFolderAt url: URL) -> Bool {
        nativeFolderIconPaths.contains(url.standardizedFileURL.path)
    }

    private static func usesFileSpecificIcon(forFileExtension fileExtension: String) -> Bool {
        fileSpecificIconExtensions.contains(fileExtension)
    }

    static func icon(for url: URL?) -> NSImage? {
        guard let url else {
            return nil
        }

        let path = url.standardizedFileURL.path
        return icon(for: url, key: "location:\(path)")
    }

    static func iconAsync(for url: URL?) async -> NSImage? {
        guard let url else {
            return nil
        }

        let path = url.standardizedFileURL.path
        return await iconAsync(for: url, key: "location:\(path)")
    }

    static func shouldRequestApplicationBadge(for item: FileItem, iconSize: CGFloat) -> Bool {
        guard iconSize >= 10, item.kind == .file else {
            return false
        }

        return !item.normalizedFileExtension.isEmpty
            && !missingApplicationBadgeExtensions.contains(item.normalizedFileExtension)
    }

    static func shouldRequestApplicationBadge(forFileURL url: URL?, iconSize: CGFloat) -> Bool {
        guard iconSize >= 10, let url else {
            return false
        }

        let fileExtension = url.pathExtension.lowercased()
        return !fileExtension.isEmpty && !missingApplicationBadgeExtensions.contains(fileExtension)
    }

    static func cachedApplicationBadgeIcon(for item: FileItem) -> NSImage? {
        guard item.kind == .file, !item.normalizedFileExtension.isEmpty else {
            return nil
        }

        if let metadata = applicationMetadataCache[item.normalizedFileExtension] {
            return metadata.icon
        }

        return cache.object(forKey: applicationBadgeCacheKey(for: item.normalizedFileExtension))
    }

    static func cachedApplicationDisplayName(for item: FileItem) -> String? {
        guard item.kind == .file, !item.normalizedFileExtension.isEmpty else {
            return nil
        }

        return applicationMetadataCache[item.normalizedFileExtension]?.displayName
    }

    static func cachedApplicationBadgeIcon(forFileURL url: URL?) -> NSImage? {
        guard let url else {
            return nil
        }

        return cachedApplicationBadgeIcon(forFileURL: url)
    }

    static func applicationBadgeIcon(for item: FileItem) -> NSImage? {
        guard item.kind == .file else {
            return nil
        }

        let fileExtension = item.normalizedFileExtension
        guard !fileExtension.isEmpty else {
            return nil
        }

        guard !missingApplicationBadgeExtensions.contains(fileExtension) else {
            return nil
        }

        return applicationMetadata(for: item.url, fileExtension: fileExtension)?.icon
    }

    static func applicationBadgeIconAsync(for item: FileItem) async -> NSImage? {
        guard item.kind == .file else {
            return nil
        }

        let fileExtension = item.normalizedFileExtension
        guard !fileExtension.isEmpty else {
            return nil
        }

        guard !missingApplicationBadgeExtensions.contains(fileExtension) else {
            return nil
        }

        return await applicationMetadataAsync(for: item.url, fileExtension: fileExtension)?.icon
    }

    static func applicationDisplayNameAsync(for item: FileItem) async -> String? {
        guard item.kind == .file else {
            return nil
        }

        let fileExtension = item.normalizedFileExtension
        guard !fileExtension.isEmpty else {
            return nil
        }

        guard !missingApplicationBadgeExtensions.contains(fileExtension) else {
            return nil
        }

        return await applicationMetadataAsync(for: item.url, fileExtension: fileExtension)?.displayName
    }

    static func cachedApplicationBadgeIcon(forFileURL url: URL) -> NSImage? {
        let fileExtension = url.pathExtension.lowercased()
        guard !fileExtension.isEmpty else {
            return nil
        }

        if let metadata = applicationMetadataCache[fileExtension] {
            return metadata.icon
        }

        return cache.object(forKey: applicationBadgeCacheKey(for: fileExtension))
    }

    static func applicationBadgeIcon(forFileURL url: URL) -> NSImage? {
        let fileExtension = url.pathExtension.lowercased()
        guard !fileExtension.isEmpty else {
            return nil
        }

        guard !missingApplicationBadgeExtensions.contains(fileExtension) else {
            return nil
        }

        return applicationMetadata(for: url, fileExtension: fileExtension)?.icon
    }

    static func applicationBadgeIconAsync(forFileURL url: URL) async -> NSImage? {
        let fileExtension = url.pathExtension.lowercased()
        guard !fileExtension.isEmpty else {
            return nil
        }

        guard !missingApplicationBadgeExtensions.contains(fileExtension) else {
            return nil
        }

        return await applicationMetadataAsync(for: url, fileExtension: fileExtension)?.icon
    }

    private static func applicationBadgeCacheKey(for fileExtension: String) -> NSString {
        "application-badge:\(fileExtension.lowercased())" as NSString
    }

    private static func applicationMetadata(for url: URL, fileExtension: String) -> ApplicationMetadata? {
        let normalizedExtension = fileExtension.lowercased()
        if let metadata = applicationMetadataCache[normalizedExtension] {
            return metadata
        }

        guard !missingApplicationBadgeExtensions.contains(normalizedExtension) else {
            return nil
        }

        guard let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            missingApplicationBadgeExtensions.insert(normalizedExtension)
            return nil
        }

        let icon = icon(for: applicationURL, key: "application:\(applicationURL.standardizedFileURL.path)")
        let displayName = FileManager.default.displayName(atPath: applicationURL.path)
        let metadata = ApplicationMetadata(icon: icon, displayName: displayName)
        applicationMetadataCache[normalizedExtension] = metadata
        cache.setObject(icon, forKey: applicationBadgeCacheKey(for: normalizedExtension))
        return metadata
    }

    private static func applicationMetadataAsync(for url: URL, fileExtension: String) async -> ApplicationMetadata? {
        let normalizedExtension = fileExtension.lowercased()
        if let metadata = applicationMetadataCache[normalizedExtension] {
            return metadata
        }

        guard !missingApplicationBadgeExtensions.contains(normalizedExtension) else {
            return nil
        }

        guard let applicationURL = await applicationURL(toOpen: url) else {
            missingApplicationBadgeExtensions.insert(normalizedExtension)
            return nil
        }

        let icon = await iconAsync(for: applicationURL, key: "application:\(applicationURL.standardizedFileURL.path)")
        let displayName = await Task.detached(priority: .utility) {
            FileManager.default.displayName(atPath: applicationURL.path)
        }.value
        let metadata = ApplicationMetadata(icon: icon, displayName: displayName)
        applicationMetadataCache[normalizedExtension] = metadata
        cache.setObject(icon, forKey: applicationBadgeCacheKey(for: normalizedExtension))
        return metadata
    }

    private static func iconAsync(for url: URL, key: String) async -> NSImage {
        let cacheKey = key as NSString
        if let cachedIcon = cache.object(forKey: cacheKey) {
            return cachedIcon
        }

        let path = url.path
        let icon = await Task.detached(priority: .utility) {
            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.size = NSSize(width: 64, height: 64)
            return SendableImage(image: icon)
        }.value.image

        cache.setObject(icon, forKey: cacheKey)
        return icon
    }

    private static func iconForContentTypeAsync(_ contentType: UTType, key: String) async -> NSImage {
        let cacheKey = key as NSString
        if let cachedIcon = cache.object(forKey: cacheKey) {
            return cachedIcon
        }

        let icon = await Task.detached(priority: .utility) {
            let icon = NSWorkspace.shared.icon(for: contentType)
            icon.size = NSSize(width: 64, height: 64)
            return SendableImage(image: icon)
        }.value.image

        cache.setObject(icon, forKey: cacheKey)
        return icon
    }

    private static func iconForFileExtensionAsync(_ fileExtension: String, fallbackContentType: UTType, key: String) async -> NSImage {
        let cacheKey = key as NSString
        if let cachedIcon = cache.object(forKey: cacheKey) {
            return cachedIcon
        }

        let normalizedExtension = fileExtension.lowercased()
        let icon = await Task.detached(priority: .utility) {
            var icon: NSImage
            if normalizedExtension.isEmpty {
                icon = NSWorkspace.shared.icon(for: fallbackContentType)
            } else {
                let probePath = (NSTemporaryDirectory() as NSString)
                    .appendingPathComponent("better-files-icon-probe.\(normalizedExtension)")
                icon = NSWorkspace.shared.icon(forFile: probePath)
                if icon.isValid == false {
                    icon = NSWorkspace.shared.icon(for: UTType(filenameExtension: normalizedExtension) ?? fallbackContentType)
                }
            }
            icon.size = NSSize(width: 64, height: 64)
            return SendableImage(image: icon)
        }.value.image

        cache.setObject(icon, forKey: cacheKey)
        return icon
    }

    private static func applicationURL(toOpen url: URL) async -> URL? {
        await Task.detached(priority: .utility) {
            NSWorkspace.shared.urlForApplication(toOpen: url)
        }.value
    }

    private static func icon(for url: URL, key: String) -> NSImage {
        let cacheKey = key as NSString
        if let cachedIcon = cache.object(forKey: cacheKey) {
            return cachedIcon
        }

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64)
        cache.setObject(icon, forKey: cacheKey)
        return icon
    }

    private static func icon(forContentType contentType: UTType, key: String) -> NSImage {
        let cacheKey = key as NSString
        if let cachedIcon = cache.object(forKey: cacheKey) {
            return cachedIcon
        }

        let icon = NSWorkspace.shared.icon(for: contentType)
        icon.size = NSSize(width: 64, height: 64)
        cache.setObject(icon, forKey: cacheKey)
        return icon
    }

    private static func icon(forFileExtension fileExtension: String, fallbackContentType: UTType, key: String) -> NSImage {
        let cacheKey = key as NSString
        if let cachedIcon = cache.object(forKey: cacheKey) {
            return cachedIcon
        }

        let normalizedExtension = fileExtension.lowercased()
        var icon: NSImage
        if normalizedExtension.isEmpty {
            icon = NSWorkspace.shared.icon(for: fallbackContentType)
        } else {
            let probePath = (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("better-files-icon-probe.\(normalizedExtension)")
            icon = NSWorkspace.shared.icon(forFile: probePath)
            if icon.isValid == false {
                icon = NSWorkspace.shared.icon(for: UTType(filenameExtension: normalizedExtension) ?? fallbackContentType)
            }
        }

        icon.size = NSSize(width: 64, height: 64)
        cache.setObject(icon, forKey: cacheKey)
        return icon
    }

    private static func cacheKey(for item: FileItem, prefersFileSpecificIcon: Bool = false) -> String {
        if prefersFileSpecificIcon {
            return "specific:\(item.url.standardizedFileURL.path)"
        }

        switch item.kind {
        case .folder:
            if usesFileSpecificIcon(forFolderAt: item.url) {
                return "folder-specific:\(item.url.standardizedFileURL.path)"
            }

            return "folder"
        case .package:
            if usesFileSpecificIcon(forPackageExtension: item.normalizedFileExtension) {
                return "app:\(item.url.standardizedFileURL.path)"
            }
            return "package:\(item.normalizedFileExtension)"
        case .file:
            let fileExtension = item.normalizedFileExtension
            if usesFileSpecificIcon(forFileExtension: fileExtension) {
                return "file-specific:\(item.url.standardizedFileURL.path)"
            }
            return fileExtension.isEmpty ? "file:none" : "file:\(fileExtension)"
        }
    }

    private static let nativeFolderIconPaths: Set<String> = {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.standardizedFileURL
        var paths: Set<String> = [
            home.path,
            home.appendingPathComponent("Desktop", isDirectory: true).standardizedFileURL.path,
            home.appendingPathComponent("Documents", isDirectory: true).standardizedFileURL.path,
            home.appendingPathComponent("Downloads", isDirectory: true).standardizedFileURL.path,
            home.appendingPathComponent("Movies", isDirectory: true).standardizedFileURL.path,
            home.appendingPathComponent("Music", isDirectory: true).standardizedFileURL.path,
            home.appendingPathComponent("Pictures", isDirectory: true).standardizedFileURL.path,
            URL(fileURLWithPath: "/Applications", isDirectory: true).standardizedFileURL.path,
            URL(fileURLWithPath: "/Library", isDirectory: true).standardizedFileURL.path,
            URL(fileURLWithPath: "/Network", isDirectory: true).standardizedFileURL.path,
            URL(fileURLWithPath: "/System", isDirectory: true).standardizedFileURL.path,
            URL(fileURLWithPath: "/Users", isDirectory: true).standardizedFileURL.path,
            URL(fileURLWithPath: "/", isDirectory: true).standardizedFileURL.path
        ]

        for directory in [
            FileManager.SearchPathDirectory.applicationDirectory,
            .desktopDirectory,
            .documentDirectory,
            .downloadsDirectory,
            .libraryDirectory,
            .moviesDirectory,
            .musicDirectory,
            .picturesDirectory,
            .trashDirectory,
            .userDirectory
        ] {
            for url in fileManager.urls(for: directory, in: [.userDomainMask, .localDomainMask, .systemDomainMask]) {
                paths.insert(url.standardizedFileURL.path)
            }
        }

        return paths
    }()

    private static let fileSpecificIconExtensions: Set<String> = [
        "alias",
        "command",
        "inetloc",
        "terminal",
        "url",
        "webloc"
    ]
}

private struct FavoriteLocation: Identifiable {
    let name: String
    let systemImage: String
    let url: URL
    var volumeSummary: VolumeStatusSummary? = nil

    var id: String {
        url.path
    }

    static let defaults: [FavoriteLocation] = {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser

        return [
            FavoriteLocation(name: "Home", systemImage: "house", url: home),
            FavoriteLocation(name: "Desktop", systemImage: "macwindow", url: home.appendingPathComponent("Desktop")),
            FavoriteLocation(name: "Documents", systemImage: "doc.text", url: home.appendingPathComponent("Documents")),
            FavoriteLocation(name: "Downloads", systemImage: "arrow.down.circle", url: home.appendingPathComponent("Downloads")),
            FavoriteLocation(name: "Pictures", systemImage: "photo.on.rectangle", url: home.appendingPathComponent("Pictures")),
            FavoriteLocation(name: "Music", systemImage: "music.note", url: home.appendingPathComponent("Music")),
            FavoriteLocation(name: "Movies", systemImage: "film", url: home.appendingPathComponent("Movies")),
            FavoriteLocation(name: "Applications", systemImage: "app.dashed", url: URL(fileURLWithPath: "/Applications", isDirectory: true)),
            FavoriteLocation(name: "Trash", systemImage: "trash", url: home.appendingPathComponent(".Trash", isDirectory: true)),
            FavoriteLocation(name: "Network", systemImage: "network", url: URL(fileURLWithPath: "/Network", isDirectory: true))
        ]
    }()

    static let initialMountedVolumes = [
        FavoriteLocation(
            name: "Macintosh HD",
            systemImage: "internaldrive",
            url: URL(fileURLWithPath: "/", isDirectory: true)
        )
    ]

    static func mountedVolumes() -> [FavoriteLocation] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeAvailableCapacityKey,
            .volumeTotalCapacityKey
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? initialMountedVolumes.map(\.url)

        var seenPaths: Set<String> = []
        return urls.compactMap { url in
            let standardizedURL = url.standardizedFileURL
            guard seenPaths.insert(standardizedURL.path).inserted else {
                return nil
            }

            let values = try? standardizedURL.resourceValues(forKeys: Set(keys))
            let name = values?.volumeName ?? (standardizedURL.path == "/" ? "Macintosh HD" : standardizedURL.lastPathComponent)
            let systemImage = standardizedURL.path == "/" ? "internaldrive" : "externaldrive"
            let summary = VolumeStatusSummary(
                name: name,
                availableByteCount: values?.volumeAvailableCapacity.map { Int64($0) },
                totalByteCount: values?.volumeTotalCapacity.map { Int64($0) }
            )
            return FavoriteLocation(name: name, systemImage: systemImage, url: standardizedURL, volumeSummary: summary)
        }
        .sorted { lhs, rhs in
            if lhs.url.path == "/" {
                return true
            }

            if rhs.url.path == "/" {
                return false
            }

            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func activeID(for currentURL: URL?, in locations: [FavoriteLocation]) -> String? {
        guard let currentPath = currentURL?.standardizedFileURL.path else {
            return nil
        }

        return locations
            .filter { location in
                let locationPath = location.url.standardizedFileURL.path
                if locationPath == "/" {
                    return currentPath == "/"
                }

                return currentPath == locationPath || currentPath.hasPrefix(locationPath + "/")
            }
            .max { lhs, rhs in
                lhs.url.standardizedFileURL.path.count < rhs.url.standardizedFileURL.path.count
            }?
            .id
    }
}

#Preview {
    BrowserView(store: BrowserStore())
}
