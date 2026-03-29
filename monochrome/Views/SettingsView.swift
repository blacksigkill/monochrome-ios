import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    private var cache = CacheService.shared
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var instanceManager = InstanceManager.shared

    @State private var cacheSize: String = ""
    @State private var cacheEntries: Int = 0
    @State private var showTTLPicker = false
    @State private var showSizePicker = false
    @State private var showClearConfirm = false
    @State private var showStreamQualityPicker = false
    @State private var showDownloadQualityPicker = false
    @State private var showFileNamingPicker = false
    @State private var showCustomNamingEditor = false
    @State private var customNamingText = ""

    var body: some View {
        CompatNavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - Playback
                    SettingsSection(title: "Playback") {
                        SettingsRow(icon: "waveform", title: "Streaming Quality", value: settings.streamQuality.label) {
                            showStreamQualityPicker = true
                        }

                        Divider().foregroundColor(Theme.border).padding(.horizontal, 16)

                        SettingsToggleRow(icon: "waveform.badge.magnifyingglass", title: "Show Track Quality", isOn: $settings.showTrackQuality)
                    }

                    // MARK: - Downloads
                    DownloadsSection(settings: settings, showDownloadQualityPicker: $showDownloadQualityPicker, showFileNamingPicker: $showFileNamingPicker, showCustomNamingEditor: $showCustomNamingEditor, customNamingText: $customNamingText)

                    // MARK: - Cache
                    SettingsSection(title: "Cache") {
                        SettingsRow(
                            icon: "internaldrive.fill",
                            title: "Used",
                            value: "\(cacheSize) · \(cacheEntries) item\(cacheEntries != 1 ? "s" : "")",
                            showChevron: false
                        )

                        Divider().foregroundColor(Theme.border).padding(.horizontal, 16)

                        SettingsRow(icon: "clock.fill", title: "Duration", value: cache.ttlLabel) {
                            showTTLPicker = true
                        }

                        Divider().foregroundColor(Theme.border).padding(.horizontal, 16)

                        SettingsRow(icon: "chart.bar.fill", title: "Max Size", value: cache.sizeLimitLabel) {
                            showSizePicker = true
                        }

                        Divider().foregroundColor(Theme.border).padding(.horizontal, 16)

                        SettingsRow(icon: "trash.fill", title: "Clear Cache", isAction: true) {
                            showClearConfirm = true
                        }
                    }

                    // MARK: - Instances
                    InstancesSection(instanceManager: instanceManager)

                    // MARK: - Appearance
                    SettingsSection(title: "Appearance") {
                        SettingsRow(icon: "paintbrush.fill", title: "Theme", value: "Coming soon...", isDisabled: true)
                        SettingsRow(icon: "textformat.size", title: "Text Size", value: "Coming soon...", isDisabled: true)
                    }

                    // MARK: - About
                    SettingsSection(title: "About") {
                        SettingsRow(icon: "info.circle.fill", title: "Version", value: appVersion, showChevron: false)
                        SettingsRow(icon: "doc.text.fill", title: "Terms of Service", value: "Coming soon...", isDisabled: true)
                        SettingsRow(icon: "hand.raised.fill", title: "Privacy Policy", value: "Coming soon...", isDisabled: true)
                        SettingsRow(icon: "envelope.fill", title: "Contact Us", value: "Coming soon...", isDisabled: true)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.top, 8)
            }
            .background(Theme.background)
            .compatScrollContentBackground(false)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .compatToolbarColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.foreground)
                            .frame(width: 30, height: 30)
                            .background(Theme.secondary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .onAppear { refreshCacheStats() }
            .confirmationDialog("Streaming Quality", isPresented: $showStreamQualityPicker, titleVisibility: .visible) {
                ForEach(AudioQuality.allCases, id: \.self) { quality in
                    Button(quality.label + (quality == settings.streamQuality ? " ✓" : "")) {
                        settings.streamQuality = quality
                    }
                }
            }
            .confirmationDialog("Download Quality", isPresented: $showDownloadQualityPicker, titleVisibility: .visible) {
                ForEach(DownloadQuality.allCases, id: \.self) { quality in
                    Button(quality.label + (quality == settings.downloadQuality ? " ✓" : "")) {
                        settings.downloadQuality = quality
                    }
                }
            }
            .confirmationDialog("File Naming", isPresented: $showFileNamingPicker, titleVisibility: .visible) {
                ForEach(FileNaming.allCases, id: \.self) { naming in
                    Button(naming.label + (naming == settings.fileNaming ? " ✓" : "")) {
                        settings.fileNaming = naming
                    }
                }
            }
            .alert("File Naming Pattern", isPresented: $showCustomNamingEditor) {
                TextField("Pattern", text: $customNamingText)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    let trimmed = customNamingText.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty {
                        settings.fileNaming = .flat
                    } else {
                        settings.customNamingPattern = trimmed
                    }
                }
            } message: {
                Text("Available: {artist}, {album}, {title}, {track}\nUse / for folders.\nEmpty = flat.")
            }
            .confirmationDialog("Cache Duration", isPresented: $showTTLPicker, titleVisibility: .visible) {
                ForEach(CacheService.ttlOptions, id: \.value) { option in
                    Button(option.label + (option.value == cache.maxAge ? " ✓" : "")) {
                        cache.maxAge = option.value
                    }
                }
            }
            .confirmationDialog("Max Cache Size", isPresented: $showSizePicker, titleVisibility: .visible) {
                ForEach(CacheService.sizeOptions, id: \.value) { option in
                    Button(option.label + (option.value == cache.maxSizeMB ? " ✓" : "")) {
                        cache.maxSizeMB = option.value
                    }
                }
            }
            .alert("Clear Cache", isPresented: $showClearConfirm) {
                Button("Clear", role: .destructive) {
                    cache.clearAll()
                    refreshCacheStats()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all cached data (\(cacheSize)). Pages will need to reload from the network.")
            }
        }
    }

    private func refreshCacheStats() {
        cacheSize = cache.formattedSize
        cacheEntries = cache.entryCount
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - Settings Section

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.mutedForeground)
                .tracking(0.8)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            VStack(spacing: 0) {
                content
            }
            .background(Theme.secondary.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Settings Row

private struct SettingsRow: View {
    let icon: String
    let title: String
    var value: String? = nil
    var valueLineLimit: Int? = 1
    var valueTruncationMode: Text.TruncationMode = .tail
    var isAction: Bool = false
    var showChevron: Bool = true
    var isDisabled: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(isAction ? .red : (isDisabled ? Theme.mutedForeground : Theme.foreground))
                    .frame(width: 22)

                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(isAction ? .red : (isDisabled ? Theme.mutedForeground : Theme.foreground))

                Spacer()

                if let value {
                    Text(value)
                        .font(.system(size: 14))
                        .foregroundColor(isDisabled ? Theme.mutedForeground.opacity(0.7) : Theme.mutedForeground)
                        .lineLimit(valueLineLimit)
                        .truncationMode(valueTruncationMode)
                }

                if showChevron && !isAction && !isDisabled {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.mutedForeground.opacity(0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

// MARK: - Settings Toggle Row

private struct SettingsToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(Theme.foreground)
                .frame(width: 22)

            Text(title)
                .font(.system(size: 15))
                .foregroundColor(Theme.foreground)

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Theme.highlight)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

struct DownloadsSection: View {
    @ObservedObject var settings: SettingsManager
    @Binding var showDownloadQualityPicker: Bool
    @Binding var showFileNamingPicker: Bool
    @Binding var showCustomNamingEditor: Bool
    @Binding var customNamingText: String
    @State private var showDeleteConfirm = false

    var body: some View {
        SettingsSection(title: "Downloads") {
            SettingsRow(icon: "arrow.down.circle.fill", title: "Download Quality", value: settings.downloadQuality.label) {
                showDownloadQualityPicker = true
            }

            Divider().foregroundColor(Theme.border).padding(.horizontal, 16)

            SettingsRow(icon: "folder.fill", title: "File Naming", value: settings.fileNaming == .flat ? "Flat" : "Custom") {
                showFileNamingPicker = true
            }

            if settings.fileNaming == .custom {
                Divider().foregroundColor(Theme.border).padding(.horizontal, 16)

                SettingsRow(
                    icon: "textformat",
                    title: "Pattern",
                    value: settings.customNamingPattern,
                    valueTruncationMode: .middle
                ) {
                    customNamingText = settings.customNamingPattern
                    showCustomNamingEditor = true
                }
            }

            Divider().foregroundColor(Theme.border).padding(.horizontal, 16)

            SettingsRow(icon: "trash.fill", title: "Delete All Downloads", isAction: true) {
                showDeleteConfirm = true
            }
        }
        .alert("Delete All Downloads", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                DownloadManager.shared.removeAllDownloads()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all downloaded tracks from storage.")
        }
    }
}

// MARK: - Instances Section

struct InstancesSection: View {
    @ObservedObject var instanceManager: InstanceManager
    @State private var showAddInstance = false
    @State private var newInstanceURL = ""
    @State private var refreshDone = false

    var body: some View {
        SettingsSection(title: "Instances") {
            // Refresh button
            Button {
                Task {
                    await instanceManager.refreshInstances()
                    refreshDone = true
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    refreshDone = false
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15))
                        .foregroundColor(Theme.foreground)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Refresh Instance List")
                            .font(.system(size: 15))
                            .foregroundColor(Theme.foreground)
                        Text("Manage and prioritize API instances.")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.mutedForeground)
                    }

                    Spacer()

                    if instanceManager.isRefreshing {
                        ProgressView()
                            .tint(Theme.mutedForeground)
                    } else if refreshDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.green)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(instanceManager.isRefreshing)

            // Instance list
            let instances = instanceManager.getInstances()
            if !instances.isEmpty {
                ForEach(instances) { instance in
                    Divider().foregroundColor(Theme.border).padding(.horizontal, 16)

                    HStack(spacing: 10) {
                        Circle()
                            .fill(instance.isUser ? Color.blue : Color.green)
                            .frame(width: 6, height: 6)

                        Text(instance.label)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.foreground)
                            .lineLimit(1)

                        Spacer()

                        Text(instance.version)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.mutedForeground)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.background.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        if instance.isUser {
                            Button {
                                instanceManager.removeUserInstance(type: "api", url: instance.url)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.system(size: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }

            Divider().foregroundColor(Theme.border).padding(.horizontal, 16)

            // Add custom instance
            Button {
                showAddInstance = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(Theme.highlight)
                        .frame(width: 22)

                    Text("Add Custom Instance")
                        .font(.system(size: 15))
                        .foregroundColor(Theme.highlight)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .alert("Add Custom Instance", isPresented: $showAddInstance) {
            TextField("https://example.com", text: $newInstanceURL)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            Button("Cancel", role: .cancel) { newInstanceURL = "" }
            Button("Add") {
                let url = newInstanceURL.trimmingCharacters(in: .whitespacesAndNewlines)
                if !url.isEmpty {
                    instanceManager.addUserInstance(type: "api", url: url)
                }
                newInstanceURL = ""
            }
        } message: {
            Text("Enter the full URL of the API instance.")
        }
    }
}

#Preview {
    SettingsView()
        .compatPresentationDetents(medium: true, large: true)
}
