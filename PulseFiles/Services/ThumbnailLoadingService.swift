import AppKit
import QuickLookThumbnailing

/// A cancellable, bounded thumbnail pipeline shared by Gallery rows.
final class ThumbnailLoadingService {
    private let cache = NSCache<NSURL, NSImage>()
    private let queue: OperationQueue

    init(maxConcurrentLoads: Int = 4, cacheCountLimit: Int = 256, cacheCostLimit: Int = 64 * 1024 * 1024) {
        queue = OperationQueue()
        queue.name = "PulseFiles.ThumbnailLoading"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = max(1, maxConcurrentLoads)
        cache.countLimit = max(1, cacheCountLimit)
        cache.totalCostLimit = max(1, cacheCostLimit)
    }

    func thumbnail(for url: URL, size: CGSize, scale: CGFloat) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let operation = ThumbnailOperation(url: url, size: size, scale: scale) { [weak self] image in
                    if let image {
                        let cost = max(1, Int(image.size.width * image.size.height * 4))
                        self?.cache.setObject(image, forKey: url as NSURL, cost: cost)
                    }
                    continuation.resume(returning: image)
                }
                queue.addOperation(operation)
            }
        } onCancel: {
            // QLThumbnailGenerator cancellation is scoped by request; queued work
            // also checks Operation cancellation before it starts.
            QLThumbnailGenerator.shared.cancelAllRequests()
        }
    }
}

private final class ThumbnailOperation: Operation, @unchecked Sendable {
    private let url: URL
    private let size: CGSize
    private let scale: CGFloat
    private let completion: (NSImage?) -> Void

    init(url: URL, size: CGSize, scale: CGFloat, completion: @escaping (NSImage?) -> Void) {
        self.url = url
        self.size = size
        self.scale = scale
        self.completion = completion
    }

    override func main() {
        guard !isCancelled else { completion(nil); return }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .thumbnail)
        let semaphore = DispatchSemaphore(value: 0)
        var result: NSImage?
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            if let representation { result = representation.nsImage }
            semaphore.signal()
        }
        semaphore.wait()
        completion(isCancelled ? nil : result)
    }
}
