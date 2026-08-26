// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import PulseFilesUtilities
import PulseFilesModels
import Foundation

/// Coordinates blocking filesystem calls so an unresponsive volume cannot create
/// an unlimited number of threads. Directory loads are dispatched before optional
/// probes; timed-out/cancelled calls continue to occupy a slot until their
/// underlying synchronous API actually returns.
package actor FileSystemOperationScheduler {
  package final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    package var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    fileprivate func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    package func checkCancellation() throws { if isCancelled { throw CancellationError() } }
  }
  enum Priority: Int, Sendable, Comparable {
    /// Recursive, best-effort reads which must never crowd out pane navigation.
    case inspection
    case probe
    case backgroundPane
    case visiblePane

    package static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
  }

  enum Rejection: Error, Equatable, Sendable {
    case queueFull
    case inspectionQueueFull
    case abandonedProbeLimitReached
  }

  struct Configuration: Sendable {
    package let maximumConcurrentOperations: Int
    package let maximumQueuedOperations: Int
    package let maximumAbandonedOperations: Int
    package let maximumConcurrentInspections: Int
    package let maximumQueuedInspections: Int

    package init(
      maximumConcurrentOperations: Int = 2, maximumQueuedOperations: Int = 32,
      maximumAbandonedOperations: Int = 2,
      maximumConcurrentInspections: Int = 1,
      maximumQueuedInspections: Int = 4
    ) {
      precondition(maximumConcurrentOperations > 0)
      precondition(maximumQueuedOperations >= 0)
      precondition(maximumAbandonedOperations >= 0)
      precondition(maximumConcurrentInspections > 0)
      precondition(maximumQueuedInspections >= 0)
      self.maximumConcurrentOperations = maximumConcurrentOperations
      self.maximumQueuedOperations = maximumQueuedOperations
      self.maximumAbandonedOperations = maximumAbandonedOperations
      self.maximumConcurrentInspections = maximumConcurrentInspections
      self.maximumQueuedInspections = maximumQueuedInspections
    }
  }

  struct Statistics: Sendable, Equatable {
    package let running: Int
    package let queued: Int
    package let abandoned: Int
    package let staleOperations: Int
  }

  package static let shared = FileSystemOperationScheduler()

  private struct Work {
    package let id: UInt64
    package let priority: Priority
    package let operation: @Sendable () throws -> AnySendable
    package let resume: @Sendable (Result<AnySendable, Error>) -> Void
    package let cancel: @Sendable () -> Void
  }

  private let configuration: Configuration
  private var nextID: UInt64 = 0
  private var running: Set<UInt64> = []
  private var runningCancellation: [UInt64: @Sendable () -> Void] = [:]
  private var runningInspections: Set<UInt64> = []
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
    try await submit(priority: priority, cancellation: {}, operation: operation)
  }

  package func submitInspection<Value: Sendable>(
    operation: @escaping @Sendable (CancellationToken) throws -> Value
  ) async throws -> Value {
    let token = CancellationToken()
    return try await submit(
      priority: .inspection, cancellation: { token.cancel() }, operation: { try operation(token) })
  }

  private func submit<Value: Sendable>(
    priority: Priority,
    cancellation: @escaping @Sendable () -> Void,
    operation: @escaping @Sendable () throws -> Value
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
          guard priority != .inspection
            || queue.lazy.filter({ $0.priority == .inspection }).count < configuration.maximumQueuedInspections
            || (running.count < configuration.maximumConcurrentOperations
              && runningInspections.count < configuration.maximumConcurrentInspections)
          else {
            continuation.resume(throwing: Rejection.inspectionQueueFull)
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
            },
            cancel: cancellation
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
      work.cancel()
      staleOperations += 1
      work.resume(.failure(CancellationError()))
    } else if running.contains(id), abandoned.insert(id).inserted {
      // Cooperative inspection work observes this even though the synchronous
      // detached task itself cannot be forcibly cancelled.
      // Other operation categories use a no-op cancellation hook.
      // Locate the running work via a separate hook registry.
      runningCancellation[id]?()
      staleOperations += 1
    }
  }

  private func startNextIfPossible() {
    while running.count < configuration.maximumConcurrentOperations, !queue.isEmpty {
      let eligible = queue.indices.filter {
        queue[$0].priority != .inspection
          || runningInspections.count < configuration.maximumConcurrentInspections
      }
      guard let index = eligible.max(by: { queue[$0].priority < queue[$1].priority }) else { return }
      let work = queue.remove(at: index)
      running.insert(work.id)
      runningCancellation[work.id] = work.cancel
      if work.priority == .inspection { runningInspections.insert(work.id) }
      Task.detached(priority: work.priority == .visiblePane ? .userInitiated : .utility) {
        [weak self] in
        let result = Result { try work.operation() }
        await self?.finished(work, result: result)
      }
    }
  }

  private func finished(_ work: Work, result: Result<AnySendable, Error>) {
    running.remove(work.id)
    runningCancellation.removeValue(forKey: work.id)
    runningInspections.remove(work.id)
    abandoned.remove(work.id)
    work.resume(result)
    startNextIfPossible()
  }
}

private struct AnySendable: @unchecked Sendable {
  let value: Any
  init<T: Sendable>(_ value: T) { self.value = value }
}
