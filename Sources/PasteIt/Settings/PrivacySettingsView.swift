import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PrivacySettingsView: View {
    @ObservedObject var settings: AppSettings

    @State private var installedApps: [InstalledApp] = []
    @State private var selectedBundleIDs: Set<String> = []
    @State private var isLoadingApps = false
    @State private var isShowingAddSheet = false

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Share anonymous usage analytics",
                    isOn: Binding(
                        get: { settings.analyticsEnabled },
                        set: { enabled in
                            settings.analyticsEnabled = enabled
                            Analytics.setEnabled(enabled)
                        }
                    )
                )

                DisclosureGroup("What we collect") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Events help improve Paste It (activation, panel use, updates). Data is anonymous and sent to PostHog when enabled.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Never collected")
                            .font(.caption.weight(.semibold))
                        ForEach(AnalyticsCatalog.neverCollected, id: \.self) { item in
                            Text("· \(item)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("Product events")
                            .font(.caption.weight(.semibold))
                            .padding(.top, 4)
                        ForEach(AnalyticsCatalog.lifecycleEvents + AnalyticsCatalog.productEvents) { event in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.name)
                                    .font(.caption.monospaced())
                                Text(event.summary)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        if let url = AnalyticsCatalog.documentationURL {
                            Link("Full disclosure on GitHub", destination: url)
                                .font(.caption)
                                .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
            } header: {
                Text("Analytics")
            } footer: {
                Text("Optional. Off means no events are sent. See \(AnalyticsCatalog.documentationPath) in the open-source repo.")
            }

            Section {
                if ignoredApps.isEmpty {
                    Text("No ignored apps")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    List(selection: $selectedBundleIDs) {
                        ForEach(ignoredApps) { app in
                            HStack(spacing: 10) {
                                Image(nsImage: app.icon)
                                    .resizable()
                                    .frame(width: 28, height: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(app.name)
                                    Text(app.bundleIdentifier)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                            .tag(app.bundleIdentifier)
                        }
                    }
                    .frame(minHeight: 140, maxHeight: 220)
                    .listStyle(.plain)
                }

                HStack(spacing: 0) {
                    Button {
                        isShowingAddSheet = true
                        loadAppsIfNeeded()
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 28, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .help("Add App")

                    Divider()
                        .frame(height: 16)

                    Button {
                        removeSelectedApps()
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 28, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedBundleIDs.isEmpty)
                    .help("Remove App")

                    Spacer()
                }
                .padding(.top, 2)
            } header: {
                Text("Ignored Apps")
            } footer: {
                Text("Copies made in these apps are never saved to history. Use this for password managers and other sensitive apps.")
            }

            Section {
                Text("Sensitive clipboard markers from apps — such as password fields and temporary clips — are ignored automatically.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Protected Content")
            } footer: {
                Text("Ignored Apps skip everything from a whole app. Protected Content skips only marked sensitive pasteboard data, from any app.")
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $isShowingAddSheet) {
            AddIgnoredAppSheet(
                installedApps: installedApps,
                isLoading: isLoadingApps,
                alreadyIgnored: settings.ignoredBundleIdentifiers,
                onAdd: { app in
                    var next = settings.ignoredBundleIdentifiers
                    next.insert(app.bundleIdentifier)
                    settings.ignoredBundleIdentifiers = next
                    isShowingAddSheet = false
                },
                onCancel: { isShowingAddSheet = false },
                onChooseFromDisk: { presentOpenPanel() }
            )
            .frame(width: 420, height: 480)
        }
        .onAppear {
            loadAppsIfNeeded()
        }
    }

    private var ignoredApps: [InstalledApp] {
        let byID = Dictionary(uniqueKeysWithValues: installedApps.map { ($0.bundleIdentifier, $0) })
        return settings.ignoredBundleIdentifiers.sorted().map { bundleID in
            if let app = byID[bundleID] {
                return app
            }
            return InstalledApp.placeholder(bundleIdentifier: bundleID)
        }
    }

    private func removeSelectedApps() {
        var next = settings.ignoredBundleIdentifiers
        next.subtract(selectedBundleIDs)
        settings.ignoredBundleIdentifiers = next
        selectedBundleIDs.removeAll()
    }

    private func loadAppsIfNeeded() {
        guard installedApps.isEmpty else { return }
        isLoadingApps = true
        Task.detached(priority: .userInitiated) {
            let apps = InstalledAppCatalog.load()
            await MainActor.run {
                installedApps = apps
                isLoadingApps = false
            }
        }
    }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose an app to ignore"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier,
              !bundleID.isEmpty
        else { return }

        var next = settings.ignoredBundleIdentifiers
        next.insert(bundleID)
        settings.ignoredBundleIdentifiers = next
        isShowingAddSheet = false

        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        if !installedApps.contains(where: { $0.bundleIdentifier == bundleID }) {
            installedApps.append(
                InstalledApp(
                    bundleIdentifier: bundleID,
                    name: name,
                    icon: icon,
                    path: url.path
                )
            )
            installedApps.sort {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }
}

private struct AddIgnoredAppSheet: View {
    let installedApps: [InstalledApp]
    let isLoading: Bool
    let alreadyIgnored: Set<String>
    let onAdd: (InstalledApp) -> Void
    let onCancel: () -> Void
    let onChooseFromDisk: () -> Void

    @State private var searchText = ""

    private var candidates: [InstalledApp] {
        let available = installedApps.filter { !alreadyIgnored.contains($0.bundleIdentifier) }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return available }
        return available.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Ignored App")
                    .font(.headline)
                Spacer()
                Button("Choose…") { onChooseFromDisk() }
            }
            .padding()

            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            if isLoading && installedApps.isEmpty {
                ProgressView("Loading apps…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(candidates) { app in
                    Button {
                        onAdd(app)
                    } label: {
                        HStack(spacing: 10) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name)
                                    .foregroundStyle(.primary)
                                Text(app.bundleIdentifier)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
    }
}
