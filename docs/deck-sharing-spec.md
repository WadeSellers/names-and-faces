# Deck sharing — V2 spec

> **Superseded 2026-09-16.** Sharing decks as files was built, then removed in
> favor of 6-digit share codes only (Wade's call: the code is simpler for the
> person receiving). What survives from this spec is the deck *format* —
> `DeckFile`, a binary plist — which is now the payload a share code stores on
> the server. The export UI, `.ntfdeck` file type, Open With handling, and the
> Quick Look preview extension are gone. See `docs/v2-privacy-changes.md`.

A deck becomes a file. Export it, hand it over any way you already hand
things over, the other person taps it and it opens in the app: cropped,
named, ready to study.

No account, no server, no change to the App Privacy label. The app still
collects nothing; the user hands a file to someone using the OS share sheet.

## The file

**Extension:** `.ntfdeck`
**UTI:** `com.wadesellers.namethatface.deck`, conforming to `public.data`
**Container:** a binary property list, written with
`PropertyListEncoder` (`outputFormat = .binary`).

Binary plist because it stores `Data` natively — JSON would base64 every
JPEG and inflate the file by a third — and because it needs no dependency.
Zero packages, same as the rest of the app.

```swift
struct DeckFile: Codable {
    /// Bump when the shape changes. Importer refuses anything it does not know.
    var formatVersion: Int      // 1
    var deckName: String
    var exportedAt: Date
    var appVersion: String      // e.g. "1.1 (4)" — for support, not for logic
    var note: String?           // optional: "Fall 2026 First Years, NP"
    var people: [PersonFile]
}

struct PersonFile: Codable {
    var name: String
    /// The cropped portrait — what every screen shows.
    var imageData: Data
    /// Only present when this person has a crop, so the recipient can
    /// re-crop. When there is no crop the original is the display image
    /// and shipping it twice doubles the file for nothing.
    var originalImageData: Data?
    var crop: CropRegion?
}
```

**Progress is deliberately not included.** Which faces you have in rotation
and how well you know them is yours, not a property of the deck. The
recipient starts at zero, three faces in, like any new deck.

**Size.** At the current 900px / quality 0.8 JPEGs, a 23-person cohort runs
about 2–3MB, a 45-person deck about 5MB. AirDrops instantly; emails fine.
Dropping redundant originals is what keeps it there.

## Export

Deck menu → **Share Deck…**

1. Build `DeckFile`, encode, write to a temp file named after the deck:
   `Fall 2026 First Years.ntfdeck`.
2. Hand it to `UIActivityViewController` (SwiftUI `ShareLink`).
3. Delete the temp file when the share sheet dismisses.

AirDrop, Messages, Mail, Files, Slack — whatever the person already uses.

## Import

Register the type so the app shows up in *Open With* and Files:

- `UTExportedTypeDeclarations` for the UTI
- `CFBundleDocumentTypes` claiming it
- handle `onOpenURL` (and `application(_:open:options:)`)

Then:

1. Decode. On any failure, one clear alert — never a crash, never a
   half-imported deck.
2. Show a **preview sheet** before anything is saved: deck name, face count,
   a grid of the portraits, **Add Deck** / **Cancel**. Opening a file from
   someone else should never silently write to your library.
3. On confirm, insert a new deck. If the name is taken, append ` (2)`.
4. Progress starts fresh.

## Treat the file as untrusted

It arrives from outside the app, so decode defensively:

- Refuse `formatVersion` newer than the app knows, with a message that says
  to update the app.
- Cap people per deck (2,000) and bytes per image (10MB) before decoding.
- Confirm every `imageData` actually decodes as an image; drop the ones that
  don't rather than failing the whole import.
- Truncate absurd names (say 200 characters) instead of storing them.
- Wrap the whole decode in one `do/catch`. A malformed or hostile file
  produces an alert, nothing else.

## Privacy policy

One line to add: decks stay on the device unless *you* choose to share one,
and a deck you share travels by whatever channel you picked. The App Privacy
answer does not change — the app still collects nothing and still talks to
no server.

## What this does for the Playhouse

Wade imports the PDF, fixes the faces, exports once, AirDrops it across the
room. The teacher taps it. No sign-in, no share code, no account to delete
later, and the student photos never touch a server anyone operates.
