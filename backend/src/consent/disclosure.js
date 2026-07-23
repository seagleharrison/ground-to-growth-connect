export const CONSENT_VERSION = process.env.CONSENT_VERSION ?? '1.0';

export const ORG_NAME = 'Ground to Growth Initiative';
export const ORG_ADDRESS = 'Ground to Growth Initiative, 1305 Barnard Street #2041, Savannah, GA 31401';

export const DISCLOSURE_TEXT = `
${ORG_NAME} — Location Sharing Consent (v${CONSENT_VERSION})

“A path to healing, a journey to home.”

Ground to Growth Initiative is a community nonprofit in Savannah, GA working to
reduce homelessness and housing instability. This app lets you share your location
with our outreach team so we can stay connected, reach you with resources, and
provide dignity-centered support. Sharing your location is completely voluntary and
you can stop at any time.

WHAT WE COLLECT
• Your approximate location (latitude and longitude), snapped to a fixed grid of
  about 200 meters before it is stored — never a precise pinpoint.
• The time each location update is sent (about once every 15 minutes while sharing
  is turned on).
• Optional GPS accuracy in meters.

WHAT WE DO NOT COLLECT
• No continuous, real-time tracking (updates are limited to roughly every 15 minutes).
• No raw device or network identifiers are stored (only a one-way hash is kept with
  your consent record for our audit log).
• No location history beyond what is stored in our secure database, which you may ask
  us to delete at any time.

HOW WE PROTECT YOUR INFORMATION
• Your coordinates are encrypted (AES-256-GCM) before they are saved.
• Access requires your personal account token.
• Only authorized Ground to Growth outreach staff can view participant locations.

YOUR RIGHTS
• You must opt in before any location is collected.
• You may revoke consent at any time — location sharing stops immediately.
• You may request that we delete your data. Contact us at:
  ${ORG_ADDRESS}
• Choosing not to share your location will never affect your access to our services.

RETENTION
• Location updates are kept only as long as needed to support you, or until you ask
  us to delete them or close your account.

By granting consent, you confirm that this has been explained to you, that you
understand it, and that you agree to share your location with ${ORG_NAME}.
`.trim();
