/// Monitors device network connectivity and Paperless server reachability.
/// Uses NWPathMonitor for instant offline detection and periodic server pings.
import Foundation
import Network
import Observation

@Observable
@MainActor
final class NetworkMonitor {

    enum ConnectionState: Equatable {
        case unknown
        case checking
        case connected
        case offline
        case serverUnreachable
    }

    // MARK: - Published state

    var isNetworkAvailable: Bool = true
    var isServerReachable: Bool = false
    var serverError: String?
    var state: ConnectionState = .unknown

    // MARK: - Private

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    private var periodicTask: Task<Void, Never>?
    private var serverURL: String = ""
    private var token: String = ""
    private var hasPassedGracePeriod = false

    // MARK: - Init

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let satisfied = path.status == .satisfied
                self.isNetworkAvailable = satisfied
                if !satisfied {
                    self.state = .offline
                    self.isServerReachable = false
                } else if self.state == .offline {
                    // Network came back, check server
                    self.state = .checking
                    await self.performServerCheck()
                }
            }
        }
        monitor.start(queue: queue)
    }

    // MARK: - Public methods

    func startMonitoring(serverURL: String, token: String) {
        self.serverURL = serverURL
        self.token = token
        hasPassedGracePeriod = false

        periodicTask?.cancel()
        periodicTask = Task { [weak self] in
            guard let self else { return }

            // Grace period: wait 3 seconds before showing errors
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self.hasPassedGracePeriod = true }

            // Initial check
            await self.performServerCheck()

            // Periodic checks: faster when server is unreachable, slower when connected
            while !Task.isCancelled {
                let interval: UInt64 = self.state == .serverUnreachable ? 10_000_000_000 : 30_000_000_000
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled else { break }
                await self.performServerCheck()
            }
        }
    }

    func stopMonitoring() {
        periodicTask?.cancel()
        periodicTask = nil
        monitor.cancel()
    }

    // MARK: - Private

    private func performServerCheck() async {
        guard isNetworkAvailable else {
            state = .offline
            return
        }

        if hasPassedGracePeriod {
            state = .checking
        }

        do {
            try await PaperlessAPI.connectivityCheck(serverURL: serverURL, token: token)
            state = .connected
            isServerReachable = true
            serverError = nil
        } catch {
            if Task.isCancelled { return }
            isServerReachable = false
            serverError = error.localizedDescription
            if hasPassedGracePeriod {
                state = .serverUnreachable
            }
        }
    }
}
