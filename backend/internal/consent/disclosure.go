// Package consent holds the disclosure text shown to users before they grant
// consent — for location sharing (ported verbatim from the Node
// consent/disclosure.js) and, separately, for document storage.
package consent

import (
	"fmt"
	"os"
)

const (
	OrgName    = "Ground to Growth Initiative"
	OrgAddress = "Ground to Growth Initiative, 1305 Barnard Street #2041, Savannah, GA 31401"
)

// Version applies to both consent types. Bump CONSENT_VERSION whenever
// either disclosure's text changes.
func Version() string {
	if v := os.Getenv("CONSENT_VERSION"); v != "" {
		return v
	}
	return "1.0"
}

func LocationDisclosureText() string {
	return fmt.Sprintf(`%s — Location Sharing Consent (v%s)

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
  %s
• Choosing not to share your location will never affect your access to our services.

RETENTION
• Location updates are kept only as long as needed to support you, or until you ask
  us to delete them or close your account.

By granting consent, you confirm that this has been explained to you, that you
understand it, and that you agree to share your location with %s.`, OrgName, Version(), OrgAddress, OrgName)
}

func DocumentDisclosureText() string {
	return fmt.Sprintf(`%s — Document Storage Consent (v%s)

“A path to healing, a journey to home.”

This app also lets you store copies of important personal documents — like a
government ID, Social Security card, or birth certificate — so you always have
access to them, even if the physical copies are lost, stolen, or damaged. This is
completely separate from location sharing: you can use one without the other.

WHAT WE COLLECT
• A photo or scan of documents you choose to upload, and the type of document you
  say it is (e.g. "government ID").
• The date and time you upload or delete a document.

WHO CAN SEE YOUR DOCUMENTS
• Only you. Ground to Growth staff can see that you have a document of a certain
  type on file, but staff have no way to view its contents — the file itself is
  encrypted and only ever decrypted for your own account's requests.

HOW WE PROTECT YOUR INFORMATION
• Every document is encrypted (AES-256-GCM) before it is saved, the same
  protection used for your location data.
• Access requires your personal account token, on your own device.
• Every time a document is actually opened, that access is permanently logged,
  so there is always a record of when your files were viewed.

YOUR RIGHTS
• You must opt in before you can upload any document.
• You may revoke this consent at any time; it does not delete documents already
  stored, but stops you from uploading new ones until you opt in again.
• You may delete any individual document, at any time, permanently.
• You may request that we delete all of your data. Contact us at:
  %s
• Choosing not to store documents will never affect your access to our services.

RETENTION
• Documents are kept only as long as you want them stored, until you delete them
  yourself or close your account.

By granting consent, you confirm that this has been explained to you, that you
understand it, and that you agree to let %s store copies of documents you choose
to upload.`, OrgName, Version(), OrgAddress, OrgName)
}
