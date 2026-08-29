import Foundation
import UIKit

enum StoreImagePreloader {
    private static let imageCache = NSCache<NSURL, UIImage>()

    static func cachedImage(for url: URL) -> UIImage? {
        imageCache.object(forKey: url as NSURL)
    }

    static func image(for url: URL) async -> UIImage? {
        if let cachedImage = cachedImage(for: url) {
            return cachedImage
        }

        guard let image = await load(url) else { return nil }
        imageCache.setObject(image, forKey: url as NSURL)
        return image
    }

    static func preload(_ urls: [URL], maxConcurrent: Int = 3) async {
        let uniqueURLs = Array(Set(urls))
        guard !uniqueURLs.isEmpty else { return }

        var nextIndex = 0

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<min(maxConcurrent, uniqueURLs.count) {
                let url = uniqueURLs[nextIndex]
                nextIndex += 1
                group.addTask {
                    guard !Task.isCancelled else { return }
                    _ = await image(for: url)
                }
            }

            while await group.next() != nil {
                guard !Task.isCancelled, nextIndex < uniqueURLs.count else { continue }
                let url = uniqueURLs[nextIndex]
                nextIndex += 1
                group.addTask {
                    guard !Task.isCancelled else { return }
                    _ = await image(for: url)
                }
            }
        }
    }

    private static func load(_ url: URL) async -> UIImage? {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 20

        guard
            let (data, _) = try? await URLSession.shared.data(for: request),
            !Task.isCancelled,
            let image = UIImage(data: data)
        else { return nil }

        return image
    }
}
