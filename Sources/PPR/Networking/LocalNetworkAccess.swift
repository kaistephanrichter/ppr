import Foundation
import Network

/// iOS blocks `URLSession` to LAN IPs until the user allows **Local Network** access. A plain HTTP request
/// often fails with `NSURLErrorDomain -1009` and `NWPath` **Local network prohibited** without a clear prompt.
/// Starting a short Bonjour browse triggers the system permission sheet and satisfies the local-network gate.
enum LocalNetworkAccess {
    /// Triggers the iOS local-network permission flow when needed. Concurrent callers share one run (max ~20s once).
    static func warmUpBonjourBrowse() async {
        await LocalNetworkWarmupGate.shared.runIfNeeded()
    }

    fileprivate static func runBonjourWarmupBody() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let completion = WarmupCompletion(continuation: continuation)
            let parameters = NWParameters.tcp
            let browser = NWBrowser(for: .bonjour(type: "_http._tcp", domain: "local."), using: parameters)
            completion.setBrowser(browser)

            let timeout = DispatchWorkItem { completion.complete() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeout)

            browser.stateUpdateHandler = { state in
                switch state {
                case .ready, .failed:
                    timeout.cancel()
                    completion.complete()
                case .cancelled:
                    timeout.cancel()
                default:
                    break
                }
            }

            browser.browseResultsChangedHandler = { _, _ in }
            browser.start(queue: .main)
        }
    }
}

private actor LocalNetworkWarmupGate {
    static let shared = LocalNetworkWarmupGate()
    private var task: Task<Void, Never>?

    func runIfNeeded() async {
        if let task {
            await task.value
            return
        }
        let newTask = Task { await LocalNetworkAccess.runBonjourWarmupBody() }
        task = newTask
        await newTask.value
    }
}

// MARK: - Swift 6 concurrency

/// Single completion of the browse + continuation resume; safe from main-queue handlers and `DispatchWorkItem`.
private final class WarmupCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var browser: NWBrowser?
    private let continuation: CheckedContinuation<Void, Never>

    init(continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func setBrowser(_ browser: NWBrowser) {
        lock.lock()
        self.browser = browser
        lock.unlock()
    }

    func complete() {
        lock.lock()
        let browserToCancel = browser
        browser = nil
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()

        browserToCancel?.cancel()
        continuation.resume()
    }
}
