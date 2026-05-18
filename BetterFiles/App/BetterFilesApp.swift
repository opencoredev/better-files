import AppKit
import Combine
import Sparkle
import SwiftUI

@main
struct BetterFilesApp: App {
    @State private var store = BrowserStore()
    @Environment(\.scenePhase) private var scenePhase
    private let updaterController: SPUStandardUpdaterController?

    init() {
        if BetterFilesUpdaterConfiguration.isConfigured {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        } else {
            updaterController = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            if Self.isRunningUnitTests {
                EmptyView()
                    .frame(width: 1, height: 1)
            } else {
                BrowserView(store: store)
                    .frame(minWidth: 900, minHeight: 560)
                    .onChange(of: scenePhase) {
                        guard scenePhase != .active else {
                            return
                        }

                        store.flushPendingPreferences()
                    }
            }
        }
        .defaultSize(width: 1080, height: 700)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                if let updater = updaterController?.updater {
                    CheckForUpdatesView(updater: updater)
                } else {
                    Button("Check for Updates...") {}
                        .disabled(true)
                }
            }

            CommandGroup(replacing: .undoRedo) {
                Button(store.undoFileOperationTitle) {
                    store.undoLastFileOperation()
                }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(!store.canUndoFileOperation)

                Button(store.redoFileOperationTitle) {
                    store.redoLastFileOperation()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!store.canRedoFileOperation)
            }

            CommandGroup(after: .newItem) {
                Button("New Tab") {
                    store.addTab()
                }
                .keyboardShortcut("t", modifiers: [.command])

                Button("Duplicate Tab") {
                    store.duplicateTab(store.selectedTabID)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Open Current Folder in New Tab") {
                    store.openCurrentFolderInNewTab()
                }
                .keyboardShortcut(.return, modifiers: [.command, .option])
                .disabled(!store.canOpenCurrentFolderInNewTab)

                Button("Close Tab") {
                    store.closeTab(store.selectedTabID)
                }
                .keyboardShortcut("w", modifiers: [.command])
                .disabled(store.tabs.count <= 1)

                Button("Reopen Closed Tab") {
                    store.reopenClosedTab()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(!store.canReopenClosedTab)

                Button("Move Tab to New Window") {
                    if let url = store.moveTabToNewWindow(store.selectedTabID) {
                        BetterFilesWindowManager.openWindow(at: url)
                    }
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(!store.canMoveSelectedTabToNewWindow)

                Button("Move Tab Left") {
                    store.moveTabLeft(store.selectedTabID)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .control])
                .disabled(!store.canMoveTabLeft(store.selectedTabID))

                Button("Move Tab Right") {
                    store.moveTabRight(store.selectedTabID)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .control])
                .disabled(!store.canMoveTabRight(store.selectedTabID))

                Button("Move Tab to Beginning") {
                    store.moveTabToBeginning(store.selectedTabID)
                }
                .disabled(!store.canMoveTabLeft(store.selectedTabID))

                Button("Move Tab to End") {
                    store.moveTabToEnd(store.selectedTabID)
                }
                .disabled(!store.canMoveTabRight(store.selectedTabID))

                Button("Open Folder...") {
                    store.chooseFolder()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("New Window") {
                    BetterFilesWindowManager.openWindow(at: store.currentURL ?? FileManager.default.homeDirectoryForCurrentUser)
                }
                .keyboardShortcut("n", modifiers: [.command])

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

                Button("Open Current Folder in Terminal") {
                    store.openCurrentFolderInTerminal()
                }
                .disabled(store.currentURL == nil)

                Button("Home") {
                    store.openHomeDirectory()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Button("This Mac") {
                    store.openComputerRoot()
                }

                Button("Network") {
                    store.openNetworkRoot()
                }

                Button("Focus Address Bar") {
                    store.focusAddressBar()
                }
                .keyboardShortcut("l", modifiers: [.command])

                Button("Search Current Folder") {
                    store.focusSearchField()
                }
                .keyboardShortcut("f", modifiers: [.command])

                Button("Back") {
                    store.goBack()
                }
                .keyboardShortcut("[", modifiers: [.command])
                .disabled(!store.canGoBack)

                Button("Forward") {
                    store.goForward()
                }
                .keyboardShortcut("]", modifiers: [.command])
                .disabled(!store.canGoForward)

                Button("Up") {
                    store.goUp()
                }
                .keyboardShortcut(.upArrow, modifiers: [.command])
                .disabled(store.currentURL?.path == "/")

                Button("Previous Tab") {
                    store.selectPreviousTab()
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(store.tabs.count <= 1)

                Button("Next Tab") {
                    store.selectNextTab()
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(store.tabs.count <= 1)

                Button("Previous Tab") {
                    store.selectPreviousTab()
                }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                .disabled(store.tabs.count <= 1)

                Button("Next Tab") {
                    store.selectNextTab()
                }
                .keyboardShortcut(.tab, modifiers: [.control])
                .disabled(store.tabs.count <= 1)

                ForEach(1...9, id: \.self) { tabNumber in
                    Button("Select Tab \(tabNumber)") {
                        store.selectTab(atDisplayIndex: tabNumber - 1)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(tabNumber))), modifiers: [.command, .option])
                    .disabled(!store.canSelectTab(atDisplayIndex: tabNumber - 1))
                }

                Button("Reload") {
                    store.reload()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Copy Benchmark Report") {
                    store.copyPerformanceReport()
                }
                .disabled(store.performanceEvents.isEmpty)

                Button("New Folder") {
                    store.createFolder()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("New File") {
                    store.createFile()
                }
            }

            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    store.cutSelectedItems()
                }
                .keyboardShortcut("x", modifiers: [.command])
                .disabled(!store.hasSelection)

                Button("Copy") {
                    store.copySelectedItems()
                }
                .keyboardShortcut("c", modifiers: [.command])
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

                Button("Paste") {
                    store.pasteItems()
                }
                .keyboardShortcut("v", modifiers: [.command])
                .disabled(!store.canPasteItems)

                Button("Duplicate") {
                    store.duplicateSelectedItems()
                }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(!store.hasSelection)

                Button("Copy to Folder...") {
                    store.copySelectedItemsToFolder()
                }
                .disabled(!store.hasSelection)

                Button("Move to Folder...") {
                    store.moveSelectedItemsToFolder()
                }
                .disabled(!store.hasSelection)
            }

            CommandGroup(after: .pasteboard) {
                Button("Select All") {
                    store.selectAllVisibleItems()
                }
                .disabled(store.visibleItems.isEmpty)

                Button("Select None") {
                    store.clearSelection()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(!store.hasSelection)

                Button("Invert Selection") {
                    store.invertSelection()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(store.visibleItems.isEmpty)
            }

            CommandMenu("View") {
                Picker("Layout", selection: $store.viewMode) {
                    ForEach(FileViewMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }

                Picker("Group By", selection: $store.groupField) {
                    ForEach(FileGroupField.allCases) { field in
                        Text(field.label)
                            .tag(field)
                    }
                }

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

                Divider()

                Button("Details View") {
                    store.viewMode = .details
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("List View") {
                    store.viewMode = .list
                }
                .keyboardShortcut("2", modifiers: [.command])

                Button("Icon View") {
                    store.viewMode = .icons
                }
                .keyboardShortcut("3", modifiers: [.command])

                Button("Tiles View") {
                    store.viewMode = .tiles
                }
                .keyboardShortcut("4", modifiers: [.command])

                Divider()

                Toggle("Navigation Pane", isOn: $store.showsNavigationPane)
                    .keyboardShortcut("b", modifiers: [.command])
                Toggle("Details Pane", isOn: $store.showsDetailPanel)
                Toggle("Preview Pane", isOn: $store.showsPreviewPanel)
                Toggle("Compact View", isOn: $store.compactView)
                Toggle("Item Checkboxes", isOn: $store.showsItemCheckboxes)
                Toggle("Folders First", isOn: $store.foldersFirst)
                Toggle("File Name Extensions", isOn: $store.showFileExtensions)

                Toggle("Show Hidden Files", isOn: $store.showHiddenFiles)

                Divider()

                Button("Save View for This Folder") {
                    store.saveCurrentFolderViewSettings()
                }
                .disabled(store.currentURL == nil)

                Button("Clear Saved Folder View") {
                    store.clearCurrentFolderViewSettings()
                }
                .disabled(!store.currentFolderHasSavedView)

                Divider()

                Section("Details Columns") {
                    Toggle("Kind", isOn: $store.showsKindColumn)
                    Toggle("Size", isOn: $store.showsSizeColumn)
                    Toggle("Modified", isOn: $store.showsModifiedColumn)
                    Toggle("Created", isOn: $store.showsCreatedColumn)
                    Toggle("Accessed", isOn: $store.showsAccessedColumn)
                    Toggle("Permissions", isOn: $store.showsPermissionsColumn)

                    Button("Show All Columns") {
                        store.showAllDetailsColumns()
                    }
                    .disabled(store.usesDefaultDetailsColumns)
                }
            }

            CommandMenu("Filters") {
                Picker("Kind", selection: $store.kindFilter) {
                    ForEach(FileKindFilter.allCases) { filter in
                        Text(filter.label)
                            .tag(filter)
                    }
                }

                Picker("Type", selection: $store.typeFilter) {
                    ForEach(store.availableTypeFilters) { filter in
                        Text(filter.label)
                            .tag(filter)
                    }
                }

                Picker("Modified", selection: $store.dateFilter) {
                    ForEach(FileDateFilter.allCases) { filter in
                        Text(filter.label)
                            .tag(filter)
                    }
                }

                Picker("Size", selection: $store.sizeFilter) {
                    ForEach(FileSizeFilter.allCases) { filter in
                        Text(filter.label)
                            .tag(filter)
                    }
                }

                Divider()

                Toggle("Search Subfolders", isOn: $store.searchesSubfolders)

                Button(store.showHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files") {
                    store.showHiddenFiles.toggle()
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])

                Divider()

                Button("Clear Search and Filters") {
                    store.clearSearchAndContentFilters()
                }
                .disabled(!store.hasActiveContentFilters)
            }

            CommandGroup(after: .toolbar) {
                Button("Open") {
                    store.openSelectedItems()
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!store.hasSelection)

                Button("Show Package Contents") {
                    store.showSelectedPackageContents()
                }
                .disabled(!store.canShowSelectionPackageContents)

                Button("Rename") {
                    store.renameSelectedItem()
                }
                .disabled(store.selectedItems.count != 1)

                Button("Move to Trash") {
                    store.moveSelectedItemToTrash()
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(!store.hasSelection)

                Button("Empty Trash...") {
                    store.confirmEmptyTrash()
                }
                .disabled(!store.canEmptyTrash)

                Button("Delete Permanently...") {
                    store.confirmDeleteSelectedItemsPermanently()
                }
                .keyboardShortcut(.delete, modifiers: [.command, .option])
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

                Button("Compress to Zip") {
                    store.compressSelectedItems()
                }
                .disabled(!store.hasSelection)

                Button("Extract Zip") {
                    store.extractSelectedArchives()
                }
                .disabled(!store.canExtractSelectedArchives)

                Button("Show Properties") {
                    store.showPropertiesForSelection()
                }
                .keyboardShortcut("i", modifiers: [.command])
                .disabled(!store.hasSelection)

                Button("Quick Look") {
                    store.quickLookSelectedItems()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!store.hasSelection)

                Menu {
                    let suggestedApplications = store.openWithApplicationsForSelection(limit: 8)

                    if suggestedApplications.isEmpty {
                        Text("No suggested applications")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(suggestedApplications) { application in
                            Button {
                                store.openSelectedItems(withApplicationAt: application.url)
                            } label: {
                                Label {
                                    Text(application.displayName)
                                } icon: {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                                }
                            }
                        }

                        Divider()
                    }

                    Button("Choose Application...") {
                        store.chooseApplicationForSelection()
                    }
                } label: {
                    Label("Open With", systemImage: "app")
                }
                .disabled(!store.hasSelection)

                Button("Open in Terminal") {
                    store.openSelectionInTerminal()
                }
                .disabled(!store.canOpenSelectionInTerminal)

                Button("Open Selection in New Tabs") {
                    store.openSelectionInNewTabs()
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .disabled(!store.canOpenSelectionInNewTabs)

                Button("Open Parent Folder in New Tab") {
                    store.openSelectionParentFoldersInNewTabs()
                }
                .disabled(!store.canOpenSelectionParentFoldersInNewTabs)

                Button("Open File Location") {
                    store.openSelectionLocation()
                }
                .disabled(!store.canOpenSelectionLocation)

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

                Button("Copy Path") {
                    store.copySelectedPaths()
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(!store.hasSelection)

                Button("Copy as Path") {
                    store.copySelectedPathsAsQuotedPaths()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift, .option])
                .disabled(!store.hasSelection)

                Button("Reveal in Finder") {
                    store.revealSelectedInFinder()
                }
                .disabled(!store.hasSelection)

                Button("Share...") {
                    store.shareSelectedItems()
                }
                .disabled(!store.hasSelection)
            }
        }
    }

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

private enum BetterFilesUpdaterConfiguration {
    static var isConfigured: Bool {
        guard
            let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            !isPlaceholder(feedURL),
            URL(string: feedURL) != nil,
            let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            !isPlaceholder(publicKey)
        else {
            return false
        }

        return true
    }

    private static func isPlaceholder(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.contains("$(")
    }
}

@MainActor
private final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }
}

private struct CheckForUpdatesView: View {
    @StateObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        _viewModel = StateObject(wrappedValue: CheckForUpdatesViewModel(updater: updater))
    }

    var body: some View {
        Button("Check for Updates...") {
            updater.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
    }
}

@MainActor
enum BetterFilesWindowManager {
    private static var controllers: [ObjectIdentifier: BetterFilesWindowController] = [:]

    static func openWindow(at url: URL) {
        let standardizedURL = url.standardizedFileURL
        let store = BrowserStore(
            initialURL: standardizedURL,
            restoresTabSession: false,
            persistsTabSession: false
        )
        let rootView = BrowserView(store: store)
            .frame(minWidth: 900, minHeight: 560)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = standardizedURL.lastPathComponent.isEmpty ? standardizedURL.path : standardizedURL.lastPathComponent
        window.setContentSize(NSSize(width: 1080, height: 700))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false

        let controller = BetterFilesWindowController(window: window, store: store)
        let controllerID = ObjectIdentifier(controller)
        controller.onClose = {
            controllers[controllerID] = nil
        }
        controllers[controllerID] = controller

        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class BetterFilesWindowController: NSWindowController, NSWindowDelegate {
    let store: BrowserStore
    var onClose: (() -> Void)?

    init(window: NSWindow, store: BrowserStore) {
        self.store = store
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func windowWillClose(_ notification: Notification) {
        store.flushPendingPreferences()
        onClose?()
    }
}
