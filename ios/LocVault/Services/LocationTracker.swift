import CoreLocation
import Foundation

@MainActor
final class LocationTracker: NSObject, ObservableObject {
    static let reportInterval: TimeInterval = 15 * 60

    @Published private(set) var isTracking = false
    @Published private(set) var lastReportAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private var consentGranted = false
    private var lastSentAt: Date?
    private var pendingReport = false
    private var wantsAlways = true
    private var didRequestAlways = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 100
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .other
        authorizationStatus = manager.authorizationStatus
    }

    func updateConsent(granted: Bool) {
        consentGranted = granted
        if granted {
            didRequestAlways = false
            startIfAuthorized()
        } else {
            stopTracking()
        }
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAlwaysPermission() {
        manager.requestAlwaysAuthorization()
    }

    private func startIfAuthorized() {
        guard consentGranted else {
            stopTracking()
            return
        }

        switch manager.authorizationStatus {
        case .authorizedAlways:
            beginUpdates()
        case .authorizedWhenInUse:
            beginUpdates()
            // Escalate to "Always" so background 15-minute reports work.
            if wantsAlways && !didRequestAlways {
                didRequestAlways = true
                manager.requestAlwaysAuthorization()
            }
        case .notDetermined:
            requestPermission()
        default:
            stopTracking()
            lastError = "Location permission denied. Enable in Settings."
        }
    }

    private func beginUpdates() {
        guard CLLocationManager.locationServicesEnabled() else {
            lastError = "Location services are disabled."
            return
        }

        manager.allowsBackgroundLocationUpdates = manager.authorizationStatus == .authorizedAlways
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        isTracking = true
        lastError = nil
        reportIfNeeded(from: manager.location, force: lastSentAt == nil)
    }

    private func stopTracking() {
        manager.stopUpdatingLocation()
        isTracking = false
    }

    private func reportIfNeeded(from location: CLLocation?, force: Bool = false) {
        guard consentGranted, let location else { return }
        guard KeychainService.loadToken() != nil else { return }

        let now = Date()
        if !force, let lastSentAt, now.timeIntervalSince(lastSentAt) < Self.reportInterval - 5 {
            return
        }
        if pendingReport { return }

        // Optimistically mark the interval as consumed so rapid, near-simultaneous
        // location updates (common right after start) can't fire duplicate reports.
        let previousSentAt = lastSentAt
        pendingReport = true
        lastSentAt = now

        let payload = LocationReportPayload(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracyMeters: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
            reportedAt: ISO8601DateFormatter().string(from: now)
        )

        Task {
            defer { pendingReport = false }
            do {
                let report = try await APIClient.shared.postLocation(payload)
                if let date = ISO8601DateFormatter().date(from: report.reportedAt) {
                    lastReportAt = date
                } else {
                    lastReportAt = now
                }
                lastError = nil
            } catch {
                // Roll back so the next update can retry this interval.
                lastSentAt = previousSentAt
                lastError = error.localizedDescription
            }
        }
    }
}

extension LocationTracker: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if consentGranted {
                startIfAuthorized()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            reportIfNeeded(from: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            lastError = error.localizedDescription
        }
    }
}
