import { useEffect } from 'react';
import { MapContainer, TileLayer, Marker, Popup, useMap } from 'react-leaflet';
import L from 'leaflet';

const icon = new L.Icon({
  iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
  iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
  shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
  iconSize: [25, 41],
  iconAnchor: [12, 41],
  popupAnchor: [1, -34],
  shadowSize: [41, 41],
});

function FitBounds({ locations }) {
  const map = useMap();

  useEffect(() => {
    if (locations.length === 0) return;
    const bounds = L.latLngBounds(locations.map((l) => [l.latitude, l.longitude]));
    map.fitBounds(bounds, { padding: [40, 40], maxZoom: 14 });
  }, [locations, map]);

  return null;
}

export default function LocationMap({ locations }) {
  const defaultCenter = locations[0]
    ? [locations[0].latitude, locations[0].longitude]
    : [40.7128, -74.006];

  return (
    <div className="map-container">
      <MapContainer
        center={defaultCenter}
        zoom={12}
        style={{ height: '100%', width: '100%' }}
        scrollWheelZoom
      >
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />
        <FitBounds locations={locations} />
        {locations.map((loc) => (
          <Marker
            key={loc.userId}
            position={[loc.latitude, loc.longitude]}
            icon={icon}
          >
            <Popup>
              <strong>{loc.name}</strong>
              <br />
              Last seen: {new Date(loc.reportedAt).toLocaleString()}
              {loc.accuracyMeters != null && (
                <>
                  <br />
                  Accuracy: ~{Math.round(loc.accuracyMeters)}m
                </>
              )}
            </Popup>
          </Marker>
        ))}
      </MapContainer>
    </div>
  );
}
