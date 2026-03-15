import SwiftUI
import UIKit

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    init() {
        cache.countLimit = 300
        cache.totalCostLimit = 50 * 1024 * 1024
    }

    func get(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }
    func set(_ url: URL, image: UIImage) { cache.setObject(image, forKey: url as NSURL) }
}

struct CachedAsyncImage<Content: View>: View {
    let url: URL?
    @ViewBuilder let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
        if let url, let cached = ImageCache.shared.get(url) {
            _phase = State(initialValue: .success(Image(uiImage: cached)))
        }
    }

    var body: some View {
        content(phase)
            .task(id: url) {
                guard let url else {
                    phase = .empty
                    return
                }
                if let cached = ImageCache.shared.get(url) {
                    phase = .success(Image(uiImage: cached))
                    return
                }
                phase = .empty
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let img = UIImage(data: data) {
                        ImageCache.shared.set(url, image: img)
                        phase = .success(Image(uiImage: img))
                    } else {
                        phase = .failure(URLError(.cannotDecodeContentData))
                    }
                } catch {
                    phase = .failure(error)
                }
            }
    }
}
