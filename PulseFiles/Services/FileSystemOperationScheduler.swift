import Foundation

/// Coordinates blocking filesystem calls so an unresponsive volume cannot create
/// an unlimited number of threads. Directory loads are dispatched before optional
/// probes; timed-out/cancelled calls continue to occupy a slot until their
/// underlying synchronous API actually returns.
actor FileSystemOperationScheduler {
  enum Priority: Int, Sendable, Comparable {
    case probe
    case backgroundPane
    case visiblePane

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
  }

  enum Rejection: Error, Equatable, Sendable {
    case queueFull
    case abandonedProbeLimitReached
  }

  struct Configuration: Sendable {
    let maximumConcurrentOperations: Int
    let maximumQueuedOperations: Int
    let maximumAbandonedOperations: Int

    init(
      maximumConcurrentOperations: Int = 2, maximumQueuedOperations: Int = 32,
      maximumAbandonedOperations: Int = 2
    ) {
      precondition(maximumConcurrentOperations > 0)
      precondition(maximumQueuedOperations >= 0)
      precondition(maximumAbandonedOperations >= 0)
      self.maximumConcurrentOperations = maximumConcurrentOperations
      self.maximumQueuedOperations = maximumQueuedOperations
      self.maximumAbandonedOperations = maximumAbandonedOperations
    }
  }

  struct Statistics: Sendable, Equatable {
    let running: Int
    let queued: Int
    let abandoned: Int
    let staleOperations: Int
  }

  static let shared = FileSystemOperationScheduler()

  private struct Work {
    let id: UInt64
    let priority: Priority
    let operation: @Sendable () throws -> AnySendable
    let resume: @Sendable (Result<AnySendable, Error>) -> Void
  }

  private let configuration: Configuration
  private var nextID: UInt64 = 0
  private var running: Set<UInt64> = []
  private var abandoned: Set<UInt64> = []
  private var queue: [Work] = []
  private var staleOperations = 0

  init(configuration: Configuration = .init()) { self.configuration = configuration }

  func statistics() -> Statistics {
    Statistics(
      running: running.count, queued: queue.count, abandoned: abandoned.count,
      staleOperations: staleOperations)
  }

  func submit<Value: Sendable>(
    priority: Priority, operation: @escaping @Sendable () throws -> Value
  ) async throws -> Value {
    let id = nextID
    nextID &+= 1
    return try await withTaskCancellationHandler(
      operation: {
        try await withCheckedThrowingContinuation { continuation in
          guard !Task.isCancelled else {
            continuation.resume(throwing: CancellationError())
            return
          }
          guard !(priority == .probe && abandoned.count >= configuration.maximumAbandonedOperations)
          else {
            continuation.resume(throwing: Rejection.abandonedProbeLimitReached)
            return
          }
          guard
            queue.count < configuration.maximumQueuedOperations
              || running.count < configuration.maximumConcurrentOperations
          else {
            continuation.resume(throwing: Rejection.queueFull)
            return
          }
          let work = Work(
            id: id,
            priority: priority,
            operation: { AnySendable(try operation()) },
            resume: { result in
              continuation.resume(with: result.map { $0.value as! Value })
            }
          )
          queue.append(work)
          startNextIfPossible()
        }
      },
      onCancel: {
        Task { await self.cancel(id: id) }
      })
  }

  private func cancel(id: UInt64) {
    if let index = queue.firstIndex(where: { $0.id == id }) {
      let work = queue.remove(at: index)
      staleOperations += 1
      work.resume(.failure(CancellationError()))
    } else if running.contains(id), abandoned.insert(id).inserted {
      staleOperations += 1
    }
  }

  private func startNextIfPossible() {
    while running.count < configuration.maximumConcurrentOperations, !queue.isEmpty {
      let index = queue.indices.max { queue[$0].priority < queue[$1].priority }!
      let work = queue.remove(at: index)
      running.insert(work.id)
      Task.detached(priority: work.priority == .visiblePane ? .userInitiated : .utility) {
        [weak self] in
        let result = Result { try work.operation() }
        await self?.finished(work, result: result)
      }
    }
  }

  private func finished(_ work: Work, result: Result<AnySendable, Error>) {
    running.remove(work.id)
    abandoned.remove(work.id)
    work.resume(result)
    startNextIfPossible()
  }
}

private struct AnySendable: @unchecked Sendable {
  let value: Any
  init<T: Sendable>(_ value: T) { self.value = value }
}
