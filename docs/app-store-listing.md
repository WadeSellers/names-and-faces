# App Store listing — Name That Face

Everything App Store Connect asks for, ready to paste. Character limits noted;
all fields below are within them.

---

## Name (30)
```
Name That Face: Learn Names
```

## Subtitle (30)
```
Flashcards from a headshot PDF
```

## Category
Primary: **Education**
Secondary: **Productivity**

## Price
Free. No in-app purchases.

## Promotional text (170)
```
Meet a room full of strangers on Monday and greet every one of them by name on Friday. Import a PDF of headshots and it builds the flashcards for you, all on your phone.
```

## Keywords (100, comma separated, no spaces)
```
headshot,roster,cohort,students,classroom,teacher,memorize,faces,names,flashcard,onboarding,cast
```

## Description (4000)
```
Meet 23 strangers on Monday. Greet every one of them by name on Friday.

Somebody hands you a PDF — pages of headshots with names printed underneath. A new class, a new cast, a new team, a conference you're about to walk into. Wonderful people. Total strangers.

Name That Face turns that PDF into a deck of flashcards.

THE WHOLE WORKFLOW
Import the PDF. That's it.

In a couple of seconds, entirely on your phone, the app renders every page, finds every face, reads the name printed with it, and deals you a deck. No typing 23 names. No cropping 23 photos. It handles names printed below the photos, above them, or beside them, and it copes with small yearbook type.

Then you check its work on one review screen — fix anything it misread, crop a photo if part of the printed name crept in, leave anyone out you don't need — and you're studying.

THE GAME
Face up. Say the name out loud like you mean it. Tap the card to check. Swipe right if you nailed it, left if you blanked.

You start with three faces. Just three. Nobody learns a whole group at once, and the app doesn't pretend you can. When you're ready, tap Add Face and one more person is introduced by name, then quizzed a few cards later while the name is still warm.

It notices what you don't know. A new face comes around often. Keep getting someone right and they earn their way down to rare. Blank on someone you "knew" and they quietly start coming around more again. You never manage any of this. The deck just pays attention.

NOTHING LEAVES YOUR PHONE
No account. No sign-in. No servers. No subscription. No analytics, no tracking, no ads.

The face detection and the text reading both run on your device using Apple's own frameworks. If those headshots are your students, their photos never leave your iPhone — which is the point.

TRY IT FIRST
No PDF handy? The app comes with a deck of US Presidents, 45 faces, so you can play the game right now and finally learn which one is Chester A. Arthur.

ALSO IN THERE
• Add people one at a time with the camera or your photo library
• Crop any portrait by tapping it; the original is always kept, so no crop is permanent
• Reset your progress on a group without losing the people
• Works with large accessibility text sizes
• iPhone, iOS 18 or later

Built by one person, for the Monday morning when a room full of new faces walks in.
```

## What's New (first release)
```
First release.
```

## App Review notes
```
No account or sign-in is needed — the app has no login and makes no network
requests at all.

TO TEST THE MAIN FEATURE (PDF import):
A sample PDF is attached to this submission. Save it to Files on the device,
then in the app tap "+" in the top right, choose "Import a PDF", and pick it.
The app will extract 9 portraits with their names and show the review screen.
Tap "Add 9 People", then "Study" to see the flashcards.

The sample contains public-domain US presidential portraits, so no real
personal data is involved in review.

TO TEST WITHOUT IMPORTING:
The app seeds a "US Presidents" deck on first launch. Tap it, then "Study".

NOTE ON THE SIMULATOR: face detection requires a physical device. Apple's
Vision framework cannot create an inference context in the iOS Simulator, so
PDF import will fail there. The bundled US Presidents deck works everywhere.

PRIVACY: the app collects nothing and transmits nothing. Camera and photo
library access are optional and used only to add a person's portrait, stored
locally.
```
Attach: `Tests/Fixtures/A-grid-name-below.pdf`

## URLs
- Support: `https://wadesellers.com/support/name-that-face.html`
- Privacy Policy: `https://wadesellers.com/privacy/name-that-face.html`
- Marketing (optional): `https://wadesellers.com/projects/names-and-faces.html`

## App Privacy answers
**Data collection: No**, we do not collect data from this app. That single
answer ends the questionnaire — no data types, no tracking.

## Age rating
4+. Answer "None" to every content question. It is not a social app, has no
user-generated content shared with others, no messaging, no web views, and no
ads.

## Encryption / export compliance
Already declared in the binary (`ITSAppUsesNonExemptEncryption = NO`), so App
Store Connect will not ask.

## EU trader status
**Not a trader.** This is a free app from an individual with no commercial
activity. Declaring "trader" would publish a home address on EU storefronts.

## Screenshots
6.9" (1320 × 2868), in `~/Desktop/NameThatFace-screenshots/`. Suggested order:
1. `03-card-face-up.png` — the card, face up
2. `04-name-revealed.png` — the name revealed
3. `02-deck-roster.png` — the whole group
4. `01-home.png` — the home screen

Apple will scale these down for smaller iPhone sizes; no separate set needed.
