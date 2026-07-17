# Names & Faces

An iPhone flashcard app for learning the names of a new cohort fast — built for the moment a stack of new students walks into the Neighborhood Playhouse and you want to greet every one of them by name within a week.

## How it works

1. **Import the cohort PDF.** You get a multi-page PDF of portraits with names printed underneath. Import it in the app and on-device Apple frameworks do the rest: PDFKit renders each page, Vision detects every face and reads the name below it.
2. **Review.** A grid shows each extracted face with its detected name. Fix any misreads, exclude bad detections, then save the cohort as a deck.
3. **Study.** You see a face. Say the name. Tap the card to reveal the answer (tap again to hide it). Swipe right if you knew it, left if you didn't.
4. **Grow the rotation at your own pace.** Studying starts with just three faces in rotation; the screen always shows how many are in rotation out of the total and how many are waiting. Tap **Add Face** whenever you're ready for one more — a new face introduces itself with its name showing before it gets quizzed. Rotation membership is saved, so the next session picks up where you left off.
5. **Repeat.** The rotation cycles until you end the session. A missed face comes back a few cards later, and a Leitner box on each person tracks long-term progress — misses demote, clean recalls promote.

You can also add a single person manually with the camera or photo library, for anyone the PDF scan missed.

## Architecture

- **SwiftUI + SwiftData**, iOS 17+, iPhone only for now.
- **Zero services, zero cost**: everything runs and is stored on-device. Photos of students never leave the phone — which is also the App Store privacy story if this ships publicly one day.
- **Vision + PDFKit** for extraction ([PDFExtractor.swift](NamesAndFaces/Import/PDFExtractor.swift)): face rectangles and OCR run per page, and each face is paired with the text line(s) directly beneath it.
- **Spaced repetition** ([StudySession.swift](NamesAndFaces/Study/StudySession.swift)): a simple Leitner system (boxes 0–4). Correct on first try promotes a box; a miss demotes one and re-queues the card within the session.

## Getting started

1. Clone the repo and open `NamesAndFaces.xcodeproj` in Xcode 16 or newer.
2. In **Signing & Capabilities**, select your development team.
3. Build and run on your iPhone (or any iOS 17+ simulator).

The project file is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from [project.yml](project.yml). Adding files in Xcode works normally; if you prefer, edit `project.yml` and re-run `xcodegen generate`.

## Roadmap ideas

- Type-the-name quiz mode as a harder alternative to reveal-and-swipe
- Free iCloud sync via CloudKit (still zero-cost with a developer account)
- iPad layout
- App Store release: replace the placeholder icon, add privacy nutrition labels (easy: no data collected)
