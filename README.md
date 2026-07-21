# Names & Faces

**Meet 23 strangers on Monday. Greet every one of them by name on Friday.**

I work at a theater conservatory. A few times a year a brand-new cohort of students walks through the door, and somebody hands me a PDF — pages of headshots with names printed underneath. Wonderful people. Total strangers. And there is nothing warmer on this earth than someone who's met you exactly once saying *"Morning, Coraline"* like it was nothing.

So I built the thing that makes that happen.

## The magic trick 🎩

You import the PDF. That's it. That's the whole workflow.

In a couple of seconds, entirely on your phone, the app renders every page, **finds every face**, **reads the name printed under it**, and deals you a deck of flashcards. No typing 23 names. No cropping 23 photos.

(In our real test sheet, one headshot was simply too cool for Apple's face detector — dark background, great hair, an absolute legend. The app noticed an unclaimed *name* sitting there, figured the photo had to be right above it, and went and got it anyway. Nobody gets left behind.)

## The game

Face up. Say the name out loud like you mean it. Tap — the name slides up from the bottom of the card. Swipe right if you nailed it, left if you blanked. The next face is already peeking out from behind, waiting in the wings.

But here's the part I actually care about:

- **You start with three faces.** Just three. Nobody learns a whole cohort at once, and the app doesn't pretend you can.
- **You control the pace.** When you're feeling dangerous, tap **Add Face**. The new person introduces themselves — name showing — and then gets quizzed a few cards later, while the name is still warm.
- **It notices what you don't know.** A new face comes around *three times a pass*. Keep nailing it and it earns its way down to once. Blank on someone you "knew" and their frequency quietly climbs right back up. You never manage any of this. The deck just… pays attention.

The screen always shows the score of the campaign: *12 of 23 in rotation, 11 waiting in the lobby.*

## The little things

- Sometimes the scan catches a sliver of someone's printed name at the bottom of their photo. A spoiler! There's a crop button **right on the flashcard** — trim it out and the view springs into your crop like the Photos app. Originals are kept, so no crop is ever forever.
- Haptics everywhere: a soft tick when the name reveals, a happy buzz when you're right, a shameful one when you're wrong.
- Miss a face and it comes back a few cards later. It knows. It always knows.

## The boring part (it isn't)

SwiftUI + SwiftData, iOS 18+, iPhone. Vision + PDFKit do the extraction **on-device** — no servers, no accounts, no subscription, no "we value your privacy" theater. The students' photos never leave the phone. Cost to run: **$0.00, forever.**

## Run it

1. Clone it, open `NamesAndFaces.xcodeproj` in Xcode 16+.
2. Pick your team under **Signing & Capabilities**.
3. Run it **on a real iPhone** (the simulator can't run the face detector — it gets stage fright).
4. Import any PDF of portraits with names under them. Go learn your people.

No PDF handy? The app deals you a starter deck on first launch: **US Presidents** — 45 faces, Washington through Biden, official portraits and all. Try the game before your first cohort arrives, or finally learn which one is Chester A. Arthur.

*(The project file is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`, if you're the regenerating type.)*

---

Built at the Neighborhood Playhouse, in conversation with Claude — I described the app I wished existed, we argued a little about spaced repetition, and this came out the other side.

Because the best thing you can do with someone's face is know their name.
