import SwiftUI

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
                    Label("Pinned", systemImage: "pin.fill")
                    Spacer()
                    Text("\(historyStore.pinnedPinboard.itemIDs.count)")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Pinned")
            } footer: {
                Text("The Pinned tab cannot be renamed or deleted. Use Pin / Unpin on clips to manage its contents.")
            }

            Section {
                if historyStore.customFolders.isEmpty {
                    Text("No custom folders")
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
                                Button("Rename…") {
                                    beginRename(folder)
                                }
                                Button("Delete", role: .destructive) {
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
                    .help("Add Folder")

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
                    .help("Rename Folder")

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
                    .help("Delete Folder")

                    Spacer()
                }
                .padding(.top, 2)
            } header: {
                Text("Folders")
            } footer: {
                Text("Create up to \(HistoryStore.maxCustomFolders) custom folders. They appear as tabs next to Default and Pinned. Clips in folders are kept when history is pruned.")
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $isShowingAddSheet) {
            FolderNameSheet(
                title: "New Folder",
                name: $newFolderName,
                confirmTitle: "Create",
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
                title: "Rename Folder",
                name: $renameName,
                confirmTitle: "Rename",
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
            TextField("Folder name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if canConfirm { onConfirm() }
                }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
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
