import AppKit
import QuickLookThumbnailing

/// A cancellable, bounded thumbnail pipeline shared by Gallery rows.
package final class ThumbnailLoadingService {
    private let cache = NSCache<NSURL, NSImage>()
    private let queue: OperationQueue

    package init(maxConcurrentLoads: Int = 4, cacheCountLimit: Int = 256, cacheCostLimit: Int = 64 * 1024 * 1024) {
        queue = OperationQueue()
        queue.name = "PulseFiles.ThumbnailLoading"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = max(1, maxConcurrentLoads)
        cache.countLimit = max(1, cacheCountLimit)
        cache.totalCostLimit = max(1, cacheCostLimit)
    }

    package func thumbnail(for url: URL, size: CGSize, scale: CGFloat) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let operationBox = ThumbnailOperationBox()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let operation = ThumbnailOperation(url: url, size: size, scale: scale) { [weak self] image in
                    if let image {
                        let cost = max(1, Int(image.size.width * image.size.height * 4))
                        self?.cache.setObject(image, forKey: url as NSURL, cost: cost)
                    }
                    continuation.resume(returning: image)
                }
                operationBox.set(operation)
                queue.addOperation(operation)
            }
        } onCancel: {
            operationBox.cancel()
        }
    }
}

private final class ThumbnailOperationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var operation: ThumbnailOperation?
    private var isCancelled = false

    package func set(_ operation: ThumbnailOperation) {
        lock.lock()
        self.operation = operation
        let shouldCancel = isCancelled
        lock.unlock()
        if shouldCancel { operation.cancel() }
    }

    package func cancel() {
        lock.lock()
        isCancelled = true
        let operation = operation
        lock.unlock()
        operation?.cancel()
    }
}

private final class ThumbnailOperation: Operation, @unchecked Sendable {
    private let url: URL
    private let size: CGSize
    private let scale: CGFloat
    private let completion: (NSImage?) -> Void
    private let request: QLThumbnailGenerator.Request

    package init(url: URL, size: CGSize, scale: CGFloat, completion: @escaping (NSImage?) -> Void) {
        self.url = url
        self.size = size
        self.scale = scale
        self.completion = completion
        request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .thumbnail)
    }

    package override func main() {
        guard !isCancelled else { completion(nil); return }
        let semaphore = DispatchSemaphore(value: 0)
        var result: NSImage?
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            if let representation { result = representation.nsImage }
            semaphore.signal()
        }
        semaphore.wait()
        completion(isCancelled ? nil : result)
    }

    package override func cancel() {
        super.cancel()
        QLThumbnailGenerator.shared.cancel(request)
    }
}
