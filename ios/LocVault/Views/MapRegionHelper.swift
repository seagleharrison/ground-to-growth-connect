import MapKit

/// Computes a region that fits every coordinate, with a little breathing
/// room. Shared by the staff map (every participant) and the participant's
/// own map (their own location history) so the two don't drift apart.
func region(containing coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
    var minLat = coordinates[0].latitude
    var maxLat = coordinates[0].latitude
    var minLng = coordinates[0].longitude
    var maxLng = coordinates[0].longitude

    for coord in coordinates {
        minLat = min(minLat, coord.latitude)
        maxLat = max(maxLat, coord.latitude)
        minLng = min(minLng, coord.longitude)
        maxLng = max(maxLng, coord.longitude)
    }

    let center = CLLocationCoordinate2D(
        latitude: (minLat + maxLat) / 2,
        longitude: (minLng + maxLng) / 2
    )
    let span = MKCoordinateSpan(
        latitudeDelta: max(0.02, (maxLat - minLat) * 1.4),
        longitudeDelta: max(0.02, (maxLng - minLng) * 1.4)
    )
    return MKCoordinateRegion(center: center, span: span)
}
