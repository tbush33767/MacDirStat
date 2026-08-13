import Foundation
import Synchronization

/// Shared between the scan thread (writer) and the UI (poller).
public final class ScanProgress: Sendable {
    public struct Snapshot: Sendable {
        public var itemCount: Int = 0
        public var byteCount: Int64 = 0
        public var currentPath: String = ""
        public var deniedCount: Int = 0
        public var cancelled: Bool = false
    }

    private let state = Mutex(Snapshot())

    public init() {}

    public var snapshot: Snapshot {
        state.withLock { $0 }
    }

    public func cancel() {
        state.withLock { $0.cancelled = true }
    }

    var isCancelled: Bool {
        state.withLock { $0.cancelled }
    }

    func add(items: Int, bytes: Int64) {
        state.withLock {
            $0.itemCount += items
            $0.byteCount += bytes
        }
    }

    func enteredDirectory(_ path: String) {
        state.withLock { $0.currentPath = path }
    }

    func recordDenied() {
        state.withLock { $0.deniedCount += 1 }
    }
}
