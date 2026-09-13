import Foundation

/// One complete analysis per app process, across windows and batches. Waiting owns no engine resources.
actor AnalysisAdmission {
    static let shared = AnalysisAdmission()

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<UUID, Error>
    }
    private var owner: UUID?
    private var waiters: [Waiter] = []
    var waitingCount: Int { waiters.count }
    var activeCount: Int { owner == nil ? 0 : 1 }

    func withPermit<Value: Sendable>(_ operation: @Sendable () async throws -> Value) async throws -> Value {
        let id = try await acquire()
        do {
            // Cancellation can race a permit handoff; never execute a cancelled queued operation.
            try Task.checkCancellation()
            let value = try await operation()
            release(id)
            return value
        } catch {
            release(id)
            throw error
        }
    }

    private func acquire() async throws -> UUID {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if owner == nil {
                    owner = id
                    continuation.resume(returning: id)
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func release(_ id: UUID) {
        guard owner == id else { return }
        if waiters.isEmpty {
            owner = nil
        } else {
            let next = waiters.removeFirst()
            owner = next.id
            next.continuation.resume(returning: next.id)
        }
    }
}
