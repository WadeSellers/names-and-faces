import UIKit
import SwiftUI
import QuickLook

/// Gives a shared deck a real preview wherever iOS previews files — Messages,
/// Mail, Files. Without this, a deck arrives as a name, a type, and a size.
final class PreviewViewController: UIViewController, QLPreviewingController {


    /// Enough to show the deck is real without paying to decode a whole cohort.
    private static let facesShown = 24
    private static let thumbnailPixels: CGFloat = 220

    func preparePreviewOfFile(at url: URL) async throws {

        let root: AnyView
        do {
            let file = try DeckFile.read(from: url)
            let faces = file.people.prefix(Self.facesShown).enumerated().map { index, person in
                DeckPreviewView.Face(
                    id: index,
                    name: person.name,
                    image: DeckThumbnail.make(from: person.imageData, maxPixel: Self.thumbnailPixels)
                )
            }
            root = AnyView(DeckPreviewView(
                deckName: file.deckName,
                totalCount: file.people.count,
                note: file.note,
                faces: faces
            ))
        } catch {
            // Never throw: a failed preview shows Quick Look's own blank error,
            // which tells the person nothing.
            root = AnyView(DeckPreviewUnavailableView(
                message: error.localizedDescription
            ))
        }

        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.backgroundColor = .clear
        // Constraints rather than a frame: Quick Look hands the controller a
        // zero-sized view at prepare time, so an autoresizing copy of those
        // bounds stays invisible.
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }
}
