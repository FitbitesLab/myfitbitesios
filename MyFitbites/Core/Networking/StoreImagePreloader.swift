import CryptoKit
import Foundation
import UIKit

enum StoreImagePreloader {
    private static let imageCache = NSCache<NSURL, UIImage>()
    private static let assetCache = NSCache<NSString, UIImage>()

    // View bodies must never perform disk I/O or image decoding.
    static func cachedImage(for url: URL) -> UIImage? {
        imageCache.object(forKey: url as NSURL)
    }

    static func cachedAsset(named name: String) -> UIImage? {
        assetCache.object(forKey: name as NSString)
    }

    static func prepareAsset(named name: String) async {
        guard cachedAsset(named: name) == nil else { return }
        let image = await Task.detached(priority: .userInitiated) {
            UIImage(named: name)?.preparingForDisplay()
        }.value
        if let image { assetCache.setObject(image, forKey: name as NSString) }
    }

    // Startup uses only local files. A missing banner never holds up the splash.
    static func prepareCachedImage(for url: URL) async -> UIImage? {
        if let image = cachedImage(for: url) { return image }
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let path = diskCacheURL(for: url),
                  let data = try? Data(contentsOf: path),
                  let image = UIImage(data: data) else { return nil }
            return image.preparingForDisplay() ?? image
        }.value
        if let image { imageCache.setObject(image, forKey: url as NSURL) }
        return image
    }

    static func image(for url: URL) async -> UIImage? {
        if let cachedImage = await prepareCachedImage(for: url) {
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

    private static func diskCacheURL(for url: URL) -> URL? {
        guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("store-image-\(key)")
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

        if let path = diskCacheURL(for: url) {
            try? data.write(to: path, options: .atomic)
        }
        return await image.byPreparingForDisplay() ?? image
    }
}
