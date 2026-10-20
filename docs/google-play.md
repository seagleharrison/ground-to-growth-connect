# Google Play: getting Ground to Growth Connect out to testers

Everything here is ready to copy and paste. Items marked **YOU** need your Google login, ID or a payment, so I can't do them.

## 1. Make the developer account (YOU, once)
1. Go to **play.google.com/console/signup** and sign in with the Google account that will own the app.
2. Choose **Organization** (recommended for a nonprofit) or **Personal**.
   - Organization needs a **D-U-N-S number** (free from Dun & Bradstreet, takes days to weeks) and a verified website.
   - Personal is faster, but Google then requires **12 testers for 14 days in a closed test** before you can publish publicly.
3. Pay the one-time **$25** fee and finish Google's ID verification (can take a day or two).

## 2. Create the app (YOU)
- **Create app** → name **Ground to Growth Connect** → App (not game) → Free.
- The app's package name (permanent): `com.harrison.groundtogrowth`

## 3. Upload the build for testers
**Testing → Internal testing → Create new release**
1. Upload `app-release.aab` (in the PlayStore folder on your Desktop).
2. When asked about **Play App Signing**, choose **Continue** (recommended). Google keeps the final signing key. Your upload key is `~/.g2g-android-keys` (back it up!).
3. **Testers** tab → create an email list → add the Google accounts (Gmail) of up to 100 testers.
4. Save, **Roll out**, then copy the **opt-in link** and send it to testers. They open it on their phone, accept, and install from Play. **Every new release you upload reaches them as a normal update.**

## 4. Store listing (copy these)
**App name (max 30):** Ground to Growth Connect

**Short description (max 80):**
Connect with rides, supplies, documents and support from Ground to Growth.

**Full description (max 4000):**
Ground to Growth Connect is a free app from Ground to Growth Initiative, a community nonprofit in Savannah, Georgia working to reduce homelessness and housing instability. "A path to healing, a journey to home."

For people getting support:
• Keep your important documents (ID, Social Security card, birth certificate) safe and encrypted, so you always have copies.
• Add appointments and events to your calendar, and turn on "I need a ride" so a volunteer can take you.
• Ask for basic items like water, socks, a blanket or a hygiene kit.
• Choose whether to share your approximate location with Ground to Growth admins so the outreach team can find you. It's your choice and you can stop any time.
• Find local resources: shelters, food, health care and help with replacing documents.
• Message the Ground to Growth team.

For volunteers:
• See who needs a ride or basic items, accept what you can do, and tap each step: on my way, arrived, done.
• A "I don't feel safe" button alerts the team right away.

Your privacy comes first. Your location and documents are shared only if you choose. Details are encrypted. We never sell your information or show ads. You can delete your account and data in the app at any time.

This app is not an emergency service. In an emergency call 911. If you are in crisis, call or text 988.

**App category:** Social (or Lifestyle). **Tags:** Social.
**Contact email:** (use the same public contact email as on the privacy page)
**Website:** your organization's website
**Privacy policy URL:** https://api.groundtogrowth.org/privacy

**Graphics (in the PlayStore folder):** icon-512.png, feature-graphic-1024x500.png, and the phone screenshots 1 to 6.

## 5. Forms Google makes you fill in (YOU, copy these answers)
**Content rating (IARC questionnaire):** No violence, no sexual content, no gambling, no drugs. The app has **user communication** (messages with admins) and **shares location** with admins. Expect a rating of Everyone or Teen.

**Target audience:** 18 and over. (Not designed for children.)

**Ads:** No ads.

**App access:** Part of the app needs sign-in. For reviewers: anyone can create a "Getting support" account in the app with a name and phone number. The volunteer and admin screens need a staff invite code, which is private. Either leave staff access out of the reviewer notes, or create a dedicated demo account and put its phone number and name here.

**Data safety (what to declare):**
| Data type | Collected? | Shared? | Optional? | Purpose |
|---|---|---|---|---|
| Name | Yes | No | No | Account |
| Phone number | Yes | No | No | Account |
| Email address | Yes | No | Yes | Account |
| Gender (other personal info) | Yes | No | Yes | Account |
| Approximate location | Yes | No | Yes (opt-in) | App functionality (outreach) |
| Photos (profile photo, document scans) | Yes | No | Yes (opt-in) | App functionality |
| Files and docs | Yes | No | Yes (opt-in) | App functionality |
| Messages | Yes | No | No | App functionality |
| Calendar events | Yes | No | Yes | App functionality |
| Device or other IDs (notification address) | Yes | No | Yes | App functionality |
- Data is **encrypted in transit and at rest**.
- Users **can request deletion** (in the app: Me → Delete my data; or by contacting you).
- **No data sold.** Shared with no one, except as required by law.

**Sensitive permission: background location.** Google reviews this closely. In the declaration form say:
- *Core feature:* Letting a person choose to share their approximate location with outreach admins so the team can find them and bring help, even when the app is closed.
- Include a short screen recording (under 30 seconds) showing: turning on location sharing, the consent screen, choosing "Allow all the time", and the "Sharing your location" notification.

**Foreground service (location):** the "Sharing your location" notification is shown while sharing is on.

**Government / health / financial apps:** answer No to all (the app is not a government app, medical app or finance app).

## 6. Then
- Internal testing has no review wait and no 12-tester rule, so you can test right away.
- For a public release later: **Production → Create release** (or **Closed testing first** if you chose a Personal account).


## 7. The background-location video (Google asks for this)
A short screen recording, under 30 seconds, no sound needed. Record it on your phone (swipe down from the top, tap **Screen record**). Steps to show:
1. Open the app and go to the **Home** screen where it says "Location sharing is off".
2. Tap **Turn on sharing**. The **consent screen** appears. Scroll it briefly and tap the agree button.
3. When Android asks for location, choose **Allow all the time** (if shown, otherwise **While using the app**, then open the app's settings and choose Allow all the time).
4. Show the Home screen now saying **Sharing your location**.
5. Pull down the notification shade to show the **"Sharing your location" notification**.
6. Stop the recording.
Upload it to YouTube as **Unlisted** and paste the link in the Play Console location declaration.

Short answer to "why does the app need background location": *The app lets a person choose to share their approximate location (rounded to about 200 meters, roughly every 15 minutes) with Ground to Growth outreach admins, so the team can find them and bring help even when the app is closed. It's off by default, needs explicit consent, can be turned off at any time, and shows a persistent notification while on.*

## 8. App access (the reviewer form)
Pick **"All or some functionality is restricted"** and say: *Anyone can create an account. On the first screen choose "Getting support," enter any name and a phone number, and tap Create account. Staff and volunteer screens need an invitation code we hold privately; these are not needed to review the main features.* No demo password is needed because the app has no passwords.
