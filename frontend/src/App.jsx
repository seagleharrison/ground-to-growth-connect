import { useCallback, useEffect, useRef, useState } from 'react';
import { api, clearAuth, getStoredAuth, storeAuth } from './api';
import LocationMap from './LocationMap';

const REPORT_INTERVAL_MS = 15 * 60 * 1000;

function useLocationTracker(enabled, onReport) {
  const watchIdRef = useRef(null);
  const intervalRef = useRef(null);
  const lastReportRef = useRef(0);

  const reportPosition = useCallback(() => {
    if (!navigator.geolocation) return;

    navigator.geolocation.getCurrentPosition(
      async (pos) => {
        const now = Date.now();
        if (now - lastReportRef.current < REPORT_INTERVAL_MS - 5000) return;
        lastReportRef.current = now;

        await onReport({
          latitude: pos.coords.latitude,
          longitude: pos.coords.longitude,
          accuracyMeters: pos.coords.accuracy,
          reportedAt: new Date().toISOString(),
        });
      },
      (err) => console.warn('Geolocation error:', err.message),
      { enableHighAccuracy: false, maximumAge: REPORT_INTERVAL_MS, timeout: 15000 }
    );
  }, [onReport]);

  useEffect(() => {
    if (!enabled) {
      if (watchIdRef.current != null) {
        navigator.geolocation.clearWatch(watchIdRef.current);
        watchIdRef.current = null;
      }
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
      return;
    }

    reportPosition();
    intervalRef.current = setInterval(reportPosition, REPORT_INTERVAL_MS);

    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
  }, [enabled, reportPosition]);
}

const GENDERS = [
  { value: 'female', label: 'Female' },
  { value: 'male', label: 'Male' },
  { value: 'nonbinary', label: 'Non-binary' },
  { value: 'other', label: 'Other' },
  { value: 'prefer_not_to_say', label: 'Prefer not to say' },
];

const PERSON_TYPES = [
  { value: 'homeless', label: 'Person we serve' },
  { value: 'volunteer', label: 'Volunteer' },
  { value: 'employee', label: 'Employee' },
  { value: 'admin', label: 'Admin' },
];

export default function App() {
  const [auth, setAuth] = useState(getStoredAuth);
  const [form, setForm] = useState({
    name: '',
    email: '',
    phone: '',
    gender: 'prefer_not_to_say',
    personType: 'homeless',
    staffCode: '',
  });
  const [disclosure, setDisclosure] = useState(null);
  const [consent, setConsent] = useState(null);
  const [consentHistory, setConsentHistory] = useState([]);
  const [locations, setLocations] = useState([]);
  const [lastReport, setLastReport] = useState(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const refreshLocations = useCallback(async () => {
    try {
      const data = await api.getLatestLocations();
      setLocations(data.locations ?? []);
    } catch (err) {
      console.warn(err.message);
    }
  }, []);

  const handleReport = useCallback(async (payload) => {
    try {
      const data = await api.postLocation(payload);
      setLastReport(data.report.reported_at);
      refreshLocations();
    } catch (err) {
      setError(err.message);
    }
  }, [refreshLocations]);

  const isStaff = auth.user?.isStaff === true;
  const trackingEnabled = consent?.granted === true;
  useLocationTracker(trackingEnabled && !!auth.token && !isStaff, handleReport);

  useEffect(() => {
    api.getDisclosure().then(setDisclosure).catch(console.error);
  }, []);

  useEffect(() => {
    if (!auth.token) return;
    if (isStaff) {
      refreshLocations();
      const id = setInterval(refreshLocations, 60_000);
      return () => clearInterval(id);
    }
    api.getConsentStatus().then(setConsent).catch(console.error);
    api.getConsentHistory().then((d) => setConsentHistory(d.records ?? [])).catch(console.error);
  }, [auth.token, isStaff, refreshLocations]);

  async function handleRegister(e) {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      const isStaffType = form.personType !== 'homeless';
      const payload = {
        name: form.name.trim(),
        email: form.email.trim() || undefined,
        phone: form.phone.trim() || undefined,
        gender: form.gender,
        personType: form.personType,
        staffCode: isStaffType ? form.staffCode.trim() : undefined,
      };
      const data = await api.register(payload);
      storeAuth(data.token, data.user);
      setAuth({ token: data.token, user: data.user });
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }

  async function handleDeleteAccount() {
    if (!window.confirm('Permanently delete your account and all location history? This cannot be undone.')) {
      return;
    }
    setError('');
    try {
      await api.deleteAccount();
      handleSignOut();
    } catch (err) {
      setError(err.message);
    }
  }

  function updateForm(field, value) {
    setForm((prev) => ({ ...prev, [field]: value }));
  }

  async function handleConsent(granted) {
    setError('');
    try {
      const data = await api.setConsent(granted);
      setConsent({ granted: data.record.granted, granted_at: data.record.granted_at });
      const history = await api.getConsentHistory();
      setConsentHistory(history.records ?? []);
    } catch (err) {
      setError(err.message);
    }
  }

  function handleSignOut() {
    clearAuth();
    setAuth({ token: null, user: null });
    setConsent(null);
    setConsentHistory([]);
    setLocations([]);
    setLastReport(null);
  }

  return (
    <div className="app">
      <header>
        <h1>Ground to Growth Connect</h1>
        <p>A path to healing, a journey to home · Ground to Growth Initiative</p>
      </header>

      {!auth.token ? (
        <div className="card">
          <h2>Register</h2>
          <p className="meta">
            Create a local account. Your token is stored only in this browser session.
          </p>
          <form onSubmit={handleRegister} className="form-grid">
            <input
              type="text"
              placeholder="Full name"
              value={form.name}
              onChange={(e) => updateForm('name', e.target.value)}
              required
            />
            <input
              type="email"
              placeholder="Email (optional)"
              value={form.email}
              onChange={(e) => updateForm('email', e.target.value)}
            />
            <input
              type="tel"
              placeholder="Phone (optional)"
              value={form.phone}
              onChange={(e) => updateForm('phone', e.target.value)}
            />
            <select value={form.gender} onChange={(e) => updateForm('gender', e.target.value)}>
              {GENDERS.map((g) => (
                <option key={g.value} value={g.value}>{g.label}</option>
              ))}
            </select>
            <select value={form.personType} onChange={(e) => updateForm('personType', e.target.value)}>
              {PERSON_TYPES.map((t) => (
                <option key={t.value} value={t.value}>{t.label}</option>
              ))}
            </select>
            {form.personType !== 'homeless' && (
              <input
                type="password"
                placeholder="Staff invite code"
                value={form.staffCode}
                onChange={(e) => updateForm('staffCode', e.target.value)}
                required
              />
            )}
            <button type="submit" className="btn btn-primary" disabled={loading}>
              {loading ? 'Creating…' : 'Create account'}
            </button>
          </form>
          {error && <p className="error">{error}</p>}
        </div>
      ) : (
        <>
          <div className="card">
            <div className="row" style={{ justifyContent: 'space-between' }}>
              <div>
                Signed in as <strong>{auth.user?.name}</strong>
                <span className="status-badge" style={{ marginLeft: '0.75rem' }}>
                  {isStaff ? 'Staff' : 'Participant'}
                </span>
                {!isStaff && consent != null && (
                  <span
                    className={`status-badge ${consent.granted ? 'status-active' : 'status-inactive'}`}
                    style={{ marginLeft: '0.5rem' }}
                  >
                    {consent.granted ? 'Sharing active' : 'Sharing off'}
                  </span>
                )}
              </div>
              <div className="row">
                <button type="button" className="btn btn-danger" onClick={handleDeleteAccount}>
                  Delete my data
                </button>
                <button type="button" className="btn btn-secondary" onClick={handleSignOut}>
                  Sign out
                </button>
              </div>
            </div>
            {lastReport && (
              <p className="meta" style={{ marginTop: '0.75rem' }}>
                Last report sent: {new Date(lastReport).toLocaleString()}
              </p>
            )}
          </div>

          <div className="grid-2">
            {!isStaff && (
            <div className="card">
              <h2>Consent & disclosure</h2>
              {disclosure && (
                <>
                  <p className="meta">Version {disclosure.version}</p>
                  <div className="disclosure">{disclosure.text}</div>
                </>
              )}
              <div className="row">
                <button
                  type="button"
                  className="btn btn-primary"
                  onClick={() => handleConsent(true)}
                  disabled={consent?.granted}
                >
                  Grant consent
                </button>
                <button
                  type="button"
                  className="btn btn-danger"
                  onClick={() => handleConsent(false)}
                  disabled={consent && !consent.granted}
                >
                  Revoke consent
                </button>
              </div>
              {error && <p className="error">{error}</p>}

              {consentHistory.length > 0 && (
                <>
                  <h2 style={{ marginTop: '1.25rem' }}>Consent audit log</h2>
                  <ul className="history-list">
                    {consentHistory.map((r) => (
                      <li key={r.id}>
                        {r.granted ? 'Granted' : 'Revoked'} · v{r.consent_version} ·{' '}
                        {new Date(r.created_at).toLocaleString()}
                      </li>
                    ))}
                  </ul>
                </>
              )}
            </div>
            )}

            {isStaff && (
            <div className="card">
              <h2>Live map</h2>
              <p className="meta">
                Latest location for each participant with active consent. Coordinates are
                snapped to a ~200m grid before storage and encrypted at rest.
              </p>
              <LocationMap locations={locations} />
            </div>
            )}
          </div>
        </>
      )}
    </div>
  );
}
