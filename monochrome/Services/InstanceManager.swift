import Foundation
import Combine

struct APIInstance: Identifiable, Hashable {
    var id: String { url }
    let url: String
    let version: String
    var name: String?
    var isUser: Bool

    var label: String {
        URL(string: url)?.host ?? url
    }
}

extension APIInstance: Codable {
    enum CodingKeys: String, CodingKey {
        case url, version, name, isUser
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var rawUrl = try c.decode(String.self, forKey: .url)
        if rawUrl.hasSuffix("/") { rawUrl = String(rawUrl.dropLast()) }
        url = rawUrl
        version = (try? c.decode(String.self, forKey: .version)) ?? "unknown"
        name = try? c.decode(String.self, forKey: .name)
        isUser = (try? c.decode(Bool.self, forKey: .isUser)) ?? false
    }
}

class InstanceManager: ObservableObject {
    static let shared = InstanceManager()

    private let storageKey = "monochrome-api-instances-v9"
    private let userStorageKey = "monochrome-user-api-instances-v1"
    private let uptimeURLs = [
        "https://tidal-uptime.jiffy-puffs-1j.workers.dev/",
        "https://tidal-uptime.props-76styles.workers.dev/"
    ]
    private let cacheDuration: TimeInterval = 15 * 60

    @Published var apiInstances: [APIInstance] = []
    @Published var streamingInstances: [APIInstance] = []
    @Published var isRefreshing = false

    private var userApiInstances: [APIInstance] = []
    private var userStreamingInstances: [APIInstance] = []

    private init() {
        loadUserInstances()
        if !loadFromCache() {
            apiInstances = Self.fallbackAPI
            streamingInstances = Self.fallbackStreaming
        }
        Task { [weak self] in await self?.loadFromNetwork() }
    }

    // MARK: - Public

    func getInstances(type: String = "api") -> [APIInstance] {
        let user = type == "streaming" ? userStreamingInstances : userApiInstances
        let base = type == "streaming" ? streamingInstances : apiInstances
        return user + base
    }

    func refreshInstances() async {
        await MainActor.run { isRefreshing = true }
        UserDefaults.standard.removeObject(forKey: storageKey)
        await loadFromNetwork()
        await MainActor.run {
            apiInstances = prioritySort(apiInstances)
            streamingInstances = prioritySort(streamingInstances)
            saveToCache()
            isRefreshing = false
        }
    }

    func addUserInstance(type: String, url: String) {
        let cleaned = url.hasSuffix("/") ? String(url.dropLast()) : url
        guard !cleaned.isEmpty else { return }
        let inst = APIInstance(url: cleaned, version: "custom", isUser: true)
        if type == "streaming" {
            guard !userStreamingInstances.contains(where: { $0.url == cleaned }) else { return }
            userStreamingInstances.append(inst)
        } else {
            guard !userApiInstances.contains(where: { $0.url == cleaned }) else { return }
            userApiInstances.append(inst)
        }
        saveUserInstances()
        objectWillChange.send()
    }

    func removeUserInstance(type: String, url: String) {
        if type == "streaming" {
            userStreamingInstances.removeAll { $0.url == url }
        } else {
            userApiInstances.removeAll { $0.url == url }
        }
        saveUserInstances()
        objectWillChange.send()
    }

    // MARK: - Fallback Instances

    private static let fallbackAPI: [APIInstance] = [
        .init(url: "https://hifi.geeked.wtf", version: "2.7", isUser: false),
        .init(url: "https://eu-central.monochrome.tf", version: "2.7", isUser: false),
        .init(url: "https://us-west.monochrome.tf", version: "2.7", isUser: false),
        .init(url: "https://api.monochrome.tf", version: "2.5", isUser: false),
        .init(url: "https://monochrome-api.samidy.com", version: "2.3", isUser: false),
        .init(url: "https://maus.qqdl.site", version: "2.6", isUser: false),
        .init(url: "https://vogel.qqdl.site", version: "2.6", isUser: false),
        .init(url: "https://katze.qqdl.site", version: "2.6", isUser: false),
        .init(url: "https://hund.qqdl.site", version: "2.6", isUser: false),
        .init(url: "https://tidal.kinoplus.online", version: "2.2", isUser: false),
        .init(url: "https://wolf.qqdl.site", version: "2.2", isUser: false),
    ]

    private static let fallbackStreaming: [APIInstance] = [
        .init(url: "https://hifi.geeked.wtf", version: "2.7", isUser: false),
        .init(url: "https://maus.qqdl.site", version: "2.6", isUser: false),
        .init(url: "https://vogel.qqdl.site", version: "2.6", isUser: false),
        .init(url: "https://katze.qqdl.site", version: "2.6", isUser: false),
        .init(url: "https://hund.qqdl.site", version: "2.6", isUser: false),
        .init(url: "https://wolf.qqdl.site", version: "2.6", isUser: false),
    ]

    // MARK: - Private Helpers

    private func isBlocked(_ url: String) -> Bool {
        url.contains(".squid.wtf")
    }

    private func prioritySort(_ instances: [APIInstance]) -> [APIInstance] {
        var top: [APIInstance] = [], mid: [APIInstance] = [], bot: [APIInstance] = []
        for i in instances {
            if i.url.contains("hifi.geeked.wtf") { top.append(i) }
            else if i.url.contains(".qqdl.site") { bot.append(i) }
            else { mid.append(i) }
        }
        return top + mid.shuffled() + bot.shuffled()
    }

    // MARK: - Cache

    private struct CachedData: Codable {
        let timestamp: TimeInterval
        let api: [APIInstance]
        let streaming: [APIInstance]
    }

    private func loadFromCache() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let cached = try? JSONDecoder().decode(CachedData.self, from: data),
              Date().timeIntervalSince1970 - cached.timestamp < cacheDuration else { return false }
        apiInstances = cached.api
        streamingInstances = cached.streaming
        return true
    }

    private func saveToCache() {
        let cached = CachedData(timestamp: Date().timeIntervalSince1970, api: apiInstances, streaming: streamingInstances)
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    // MARK: - Network

    private func loadFromNetwork() async {
        var responseData: Data?

        for urlString in uptimeURLs {
            guard let url = URL(string: urlString) else { continue }
            do {
                let (data, resp) = try await URLSession.shared.data(from: url)
                if (resp as? HTTPURLResponse)?.statusCode == 200 { responseData = data; break }
            } catch {
                print("[InstanceManager] Fetch failed from \(urlString): \(error.localizedDescription)")
            }
        }

        let fetchedData = responseData
        await MainActor.run {
            guard let data = fetchedData,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            var api: [APIInstance] = []
            if let arr = json["api"] as? [[String: Any]] {
                for item in arr {
                    guard let url = item["url"] as? String, !isBlocked(url) else { continue }
                    api.append(APIInstance(url: url, version: item["version"] as? String ?? "unknown",
                                          name: item["name"] as? String, isUser: false))
                }
            }

            var streaming: [APIInstance] = []
            if let arr = json["streaming"] as? [[String: Any]] {
                for item in arr {
                    guard let url = item["url"] as? String, !isBlocked(url) else { continue }
                    streaming.append(APIInstance(url: url, version: item["version"] as? String ?? "unknown",
                                                name: item["name"] as? String, isUser: false))
                }
            }

            guard !api.isEmpty else { return }
            apiInstances = api
            streamingInstances = streaming.isEmpty ? api : streaming
            saveToCache()
        }
    }

    // MARK: - User Instances

    private func loadUserInstances() {
        guard let data = UserDefaults.standard.data(forKey: userStorageKey),
              let decoded = try? JSONDecoder().decode([String: [APIInstance]].self, from: data) else { return }
        userApiInstances = decoded["api"] ?? []
        userStreamingInstances = decoded["streaming"] ?? []
    }

    private func saveUserInstances() {
        let dict: [String: [APIInstance]] = ["api": userApiInstances, "streaming": userStreamingInstances]
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: userStorageKey)
        }
    }
}
