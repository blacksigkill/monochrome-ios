import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    private var cache = CacheService.shared

    @State private var cacheSize: String = ""
    @State private var cacheEntries: Int = 0
    @State private var showTTLPicker = false
    @State private var showSizePicker = false
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - Playback
                    SettingsSection(title: "Playback") {
                        SettingsRow(icon: "waveform", title: "Audio Quality", value: "High")
                        SettingsRow(icon: "antenna.radiowaves.left.and.right", title: "Streaming", value: "Wi-Fi + Cellular")
                        SettingsRow(icon: "speaker.wave.2.fill", title: "Normalisation", value: "On")
                    }

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

                    // MARK: - Appearance
                    SettingsSection(title: "Appearance") {
                        SettingsRow(icon: "paintbrush.fill", title: "Theme", value: "Dark")
                        SettingsRow(icon: "textformat.size", title: "Text Size", value: "Default")
                    }

                    // MARK: - About
                    SettingsSection(title: "About") {
                        SettingsRow(icon: "info.circle.fill", title: "Version", value: appVersion, showChevron: false)
                        SettingsRow(icon: "doc.text.fill", title: "Terms of Service")
                        SettingsRow(icon: "hand.raised.fill", title: "Privacy Policy")
                        SettingsRow(icon: "envelope.fill", title: "Contact Us")
                    }

                    Spacer(minLength: 40)
                }
                .padding(.top, 8)
            }
            .background(Theme.background)
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
    var isAction: Bool = false
    var showChevron: Bool = true
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(isAction ? .red : Theme.foreground)
                    .frame(width: 22)

                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(isAction ? .red : Theme.foreground)

                Spacer()

                if let value {
                    Text(value)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.mutedForeground)
                }

                if showChevron && !isAction {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.mutedForeground.opacity(0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsView()
        .presentationDetents([.medium, .large])
}
