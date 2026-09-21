import MapKit
import SwiftUI

struct MapTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            Group {
                if appState.locations.isEmpty {
                    ContentUnavailableView(
                        "No locations yet",
                        systemImage: "map",
                        description: Text("Locations appear here once consented users report in.")
                    )
                } else {
                    Map(position: $cameraPosition) {
                        ForEach(appState.locations) { location in
                            Annotation(location.name, coordinate: location.coordinate) {
                                VStack(spacing: 2) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.blue)
                                    Text(location.name)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .mapControls {
                        MapUserLocationButton()
                        MapCompass()
                    }
                    .onAppear { fitMap() }
                    .onChange(of: appState.locations.count) { _, _ in fitMap() }
                }
            }
            .navigationTitle("Map")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await appState.refreshLocations() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .refreshable {
                await appState.refreshLocations()
            }
        }
    }

    private func fitMap() {
        let coords = appState.locations.map(\.coordinate)
        guard !coords.isEmpty else { return }
        cameraPosition = .region(region(containing: coords))
    }
}

private extension UserLocation {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
