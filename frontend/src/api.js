const TOKEN_KEY = 'locvault_token';
const USER_KEY = 'locvault_user';

export function getStoredAuth() {
  const token = sessionStorage.getItem(TOKEN_KEY);
  const user = sessionStorage.getItem(USER_KEY);
  return {
    token,
    user: user ? JSON.parse(user) : null,
  };
}

export function storeAuth(token, user) {
  sessionStorage.setItem(TOKEN_KEY, token);
  sessionStorage.setItem(USER_KEY, JSON.stringify(user));
}

export function clearAuth() {
  sessionStorage.removeItem(TOKEN_KEY);
  sessionStorage.removeItem(USER_KEY);
}

async function request(path, options = {}) {
  const { token } = getStoredAuth();
  const headers = {
    'Content-Type': 'application/json',
    ...options.headers,
  };
  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }

  const res = await fetch(path, { ...options, headers });
  const data = await res.json().catch(() => ({}));

  if (!res.ok) {
    throw new Error(data.error ?? `Request failed (${res.status})`);
  }
  return data;
}

export const api = {
  register: (payload) =>
    request('/api/users', {
      method: 'POST',
      body: JSON.stringify(payload),
    }),

  deleteAccount: () => request('/api/account', { method: 'DELETE' }),

  getDisclosure: () => request('/api/consent/disclosure'),

  getConsentStatus: () => request('/api/consent/status'),

  getConsentHistory: () => request('/api/consent/history'),

  setConsent: (granted) =>
    request('/api/consent', {
      method: 'POST',
      body: JSON.stringify({ granted }),
    }),

  postLocation: (payload) =>
    request('/api/locations', {
      method: 'POST',
      body: JSON.stringify(payload),
    }),

  getLatestLocations: () => request('/api/locations/latest'),

  getMyLocations: () => request('/api/locations/mine'),
};
