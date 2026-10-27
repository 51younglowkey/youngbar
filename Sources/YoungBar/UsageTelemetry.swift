// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Voluntary usage counts only. Never read hardware IDs, menu-bar contents,
/// accessibility information, filenames, or account information.
@MainActor
final class UsageTelemetry {
    private enum Keys {
        static let installationID = "usageTelemetryInstallationID"
        static let lastReportedDay = "usageTelemetryLastReportedDay"
    }

    private struct Payload: Encodable {
        let installation_id: String
        let app_version: String
    }

    private let defaults: UserDefaults
    private var heartbeatTimer: Timer?
    private var reporting = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var consentGranted: Bool {
        let options = defaults.dictionary(forKey: "barOptions") as? [String: Int] ?? [:]
        return options["shareAnonymousUsage"] == 1
    }

    /// Empty/missing endpoint deliberately means "no network requests".
    /// Configure YoungBarUsageEndpoint in Info.plist only after deploying a
    /// server described in docs/TELEMETRY.md.
    private var endpoint: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "YoungBarUsageEndpoint") as? String,
              let url = URL(string: raw), url.scheme?.lowercased() == "https",
              url.host != nil else { return nil }
        return url
    }

    func start() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.reportIfDue() }
        }
        Task { await reportIfDue() }
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            Task { await reportIfDue() }
        } else {
            // Forget the random installation token immediately. Make a
            // best-effort deletion request for previously stored server data.
            let previousID = defaults.string(forKey: Keys.installationID)
            defaults.removeObject(forKey: Keys.installationID)
            defaults.removeObject(forKey: Keys.lastReportedDay)
            if let previousID, let endpoint {
                Task { _ = await transmit(installationID: previousID, to: endpoint, method: "DELETE") }
            }
        }
    }

    private func reportIfDue() async {
        guard !reporting, consentGranted, let endpoint else { return }
        let day = String(ISO8601DateFormatter().string(from: Date()).prefix(10)) // UTC
        guard defaults.string(forKey: Keys.lastReportedDay) != day else { return }

        reporting = true
        defer { reporting = false }

        let installationID: String
        if let existing = defaults.string(forKey: Keys.installationID) {
            installationID = existing
        } else {
            installationID = UUID().uuidString.lowercased()
            defaults.set(installationID, forKey: Keys.installationID)
        }

        let succeeded = await transmit(installationID: installationID, to: endpoint, method: "POST")
        guard consentGranted,
              defaults.string(forKey: Keys.installationID) == installationID else {
            // Consent was revoked while the POST was in flight.
            if succeeded {
                _ = await transmit(installationID: installationID, to: endpoint, method: "DELETE")
            }
            return
        }
        if succeeded { defaults.set(day, forKey: Keys.lastReportedDay) }
    }

    private func transmit(installationID: String, to url: URL, method: String) async -> Bool {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let payload = Payload(installation_id: installationID, app_version: version)
        guard let body = try? JSONEncoder().encode(payload) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 8
        request.httpBody = body
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let status = (response as? HTTPURLResponse)?.statusCode else { return false }
            return (200..<300).contains(status)
        } catch {
            return false // Usage metrics must never interfere with YoungBar.
        }
    }
}
