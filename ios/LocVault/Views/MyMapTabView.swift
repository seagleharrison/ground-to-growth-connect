import MapKit
import SwiftUI

/// A participant's own map: one dot per day, never other participants'
/// locations. Tapping a day's dot reveals that day's movement trail — the
/// sequence of points reported that day, connected in order.
struct MyMapTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedDay: String?

    private var days: [DayGroup] {
        let grouped = Dictionary(grouping: appState.myLocations) { dayKey($0.reportedAt) }
        return grouped.map { key, reports in
            DayGroup(key: key, reports: reports.sorted { $0.reportedAt < $1.reportedAt })
        }
        .sorted { $0.key < $1.key }
    }

    var body: some View {
        NavigationStack {
            Group {
                if days.isEmpty {
                    ContentUnavailableView(
                        "No locations yet",
                        systemImage: "location",
                        description: Text("Your reported locations appear here once you grant consent and the app sends its first update.")
                    )
                } else {
                    mapView
                }
            }
            .navigationTitle("My Map")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await appState.refreshMyLocations() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .refreshable {
                await appState.refreshMyLocations()
            }
        }
    }

    private var mapView: some View {
        VStack(spacing: 0) {
            if let selectedDay, let group = days.first(where: { $0.key == selectedDay }) {
                selectedDayBanner(group)
            }

            Map(position: $cameraPosition) {
                ForEach(days) { group in
                    if group.key == selectedDay {
                        MapPolyline(coordinates: group.reports.map(\.coordinate))
                            .stroke(.blue, lineWidth: 3)

                        ForEach(Array(group.reports.enumerated()), id: \.offset) { index, report in
                            Annotation(timeLabel(report.reportedAt), coordinate: report.coordinate) {
                                Circle()
                                    .fill(.blue)
                                    .frame(width: index == group.reports.count - 1 ? 14 : 8,
                                           height: index == group.reports.count - 1 ? 14 : 8)
                                    .overlay(Circle().stroke(.white, lineWidth: 2))
                            }
                        }
                    } else {
                        Annotation(dayLabel(group.key), coordinate: group.anchor) {
                            Button {
                                withAnimation { selectedDay = group.key }
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: "circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.blue)
                                    Text(dayLabel(group.key))
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .onAppear { fitMap() }
            .onChange(of: appState.myLocations.count) { _, _ in fitMap() }
        }
    }

    private func selectedDayBanner(_ group: DayGroup) -> some View {
        HStack {
            Text("\(dayLabel(group.key)) · \(group.reports.count) report\(group.reports.count == 1 ? "" : "s")")
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
            Button("Show all days") {
                withAnimation {
                    selectedDay = nil
                    fitMap()
                }
            }
            .font(.subheadline)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
    }

    private func fitMap() {
        let coords = days.map(\.anchor)
        guard !coords.isEmpty else { return }
        cameraPosition = .region(region(containing: coords))
    }

    private func dayKey(_ iso: String) -> String {
        String(iso.prefix(10))
    }

    private func dayLabel(_ key: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        guard let date = formatter.date(from: key) else { return key }
        let display = DateFormatter()
        display.dateFormat = "MMM d"
        // Must match the UTC-based grouping key above — otherwise formatting
        // in the device's local timezone can roll midnight UTC back to the
        // previous day (e.g. showing "Aug 23" for a key of "2026-08-24").
        display.timeZone = TimeZone(identifier: "UTC")
        return display.string(from: date)
    }

    private func timeLabel(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return "" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct DayGroup: Identifiable {
    let key: String
    let reports: [MyLocationReport]

    var id: String { key }
    /// The most recent point that day — used as the collapsed dot's position.
    var anchor: CLLocationCoordinate2D { reports[reports.count - 1].coordinate }
}

private extension MyLocationReport {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
