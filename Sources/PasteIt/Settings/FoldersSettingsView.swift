import SwiftUI
import PasteItCore

struct FoldersSettingsView: View {
    @ObservedObject var historyStore: HistoryStore

    @State private var selectedIDs: Set<UUID> = []
    @State private var isShowingAddSheet = false
    @State private var newFolderName = ""
    @State private var renameTarget: Pinboard?
    @State private var renameName = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    Label(L10n.tr("tab.pinned", default: "Pinned"), systemImage: "pin.fill")
                    Spacer()
                    Text("\(historyStore.pinnedPinboard.itemIDs.count)")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(L10n.tr("tab.pinned", default: "Pinned"))
            } footer: {
                Text(L10n.tr("folders.pinnedFooter", default: "The Pinned tab cannot be renamed or deleted. Use Pin / Unpin on clips to manage its contents."))
            }

            Section {
                if historyStore.customFolders.isEmpty {
                    Text(L10n.tr("folders.noCustom", default: "No custom folders"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    List(selection: $selectedIDs) {
                        ForEach(historyStore.customFolders) { folder in
                            HStack {
                                Label(folder.name, systemImage: "folder")
                                Spacer()
                                Text("\(folder.itemIDs.count)")
                                    .foregroundStyle(.secondary)
                            }
                            .tag(folder.id)
                            .contextMenu {
                                Button(L10n.tr("folders.rename", default: "Rename…")) {
                                    beginRename(folder)
                                }
                                Button(L10n.tr("common.delete", default: "Delete"), role: .destructive) {
                                    _ = historyStore.deleteCustomFolder(folder)
                                    selectedIDs.remove(folder.id)
                                }
                            }
                        }
                    }
                    .frame(minHeight: 140, maxHeight: 220)
                    .listStyle(.plain)
                }

                HStack(spacing: 0) {
                    Button {
                        newFolderName = ""
                        isShowingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 28, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!historyStore.canCreateCustomFolder)
                    .help(L10n.tr("folders.addHelp", default: "Add Folder"))

                    Divider()
                        .frame(height: 16)

                    Button {
                        renameSelected()
                    } label: {
                        Image(systemName: "pencil")
                            .frame(width: 28, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedIDs.count != 1)
                    .help(L10n.tr("folders.renameHelp", default: "Rename Folder"))

                    Divider()
                        .frame(height: 16)

                    Button {
                        deleteSelected()
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 28, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedIDs.isEmpty)
                    .help(L10n.tr("folders.deleteHelp", default: "Delete Folder"))

                    Spacer()
                }
                .padding(.top, 2)
            } header: {
                Text(L10n.tr("settings.tab.folders", default: "Folders"))
            } footer: {
                Text(
                    L10n.tr(
                        "folders.footer",
                        default: "Create up to %lld custom folders. They appear as tabs next to Default and Pinned. Clips in folders are kept when history is pruned.",
                        HistoryStore.maxCustomFolders
                    )
                )
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $isShowingAddSheet) {
            FolderNameSheet(
                title: L10n.tr("timeline.newFolder", default: "New Folder"),
                name: $newFolderName,
                confirmTitle: L10n.tr("common.create", default: "Create"),
                onConfirm: {
                    if historyStore.createCustomFolder(name: newFolderName) != nil {
                        isShowingAddSheet = false
                        newFolderName = ""
                    }
                },
                onCancel: {
                    isShowingAddSheet = false
                    newFolderName = ""
                }
            )
        }
        .sheet(item: $renameTarget) { folder in
            FolderNameSheet(
                title: L10n.tr("folders.renameTitle", default: "Rename Folder"),
                name: $renameName,
                confirmTitle: L10n.tr("folders.renameConfirm", default: "Rename"),
                onConfirm: {
                    if historyStore.renameCustomFolder(folder, name: renameName) {
                        renameTarget = nil
                        renameName = ""
                    }
                },
                onCancel: {
                    renameTarget = nil
                    renameName = ""
                }
            )
        }
    }

    private func beginRename(_ folder: Pinboard) {
        renameName = folder.name
        renameTarget = folder
    }

    private func renameSelected() {
        guard let id = selectedIDs.first,
              let folder = historyStore.customFolders.first(where: { $0.id == id })
        else { return }
        beginRename(folder)
    }

    private func deleteSelected() {
        let toDelete = historyStore.customFolders.filter { selectedIDs.contains($0.id) }
        for folder in toDelete {
            _ = historyStore.deleteCustomFolder(folder)
        }
        selectedIDs.removeAll()
    }
}

private struct FolderNameSheet: View {
    let title: String
    @Binding var name: String
    let confirmTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var canConfirm: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
            TextField(L10n.tr("folders.namePlaceholder", default: "Folder name"), text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if canConfirm { onConfirm() }
                }
            HStack {
                Spacer()
                Button(L10n.tr("common.cancel", default: "Cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canConfirm)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
