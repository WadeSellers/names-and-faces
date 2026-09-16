import SwiftUI
import UIKit

/// A deck on its way out of the app.
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
    let deckName: String
    let faceCount: Int

    /// Sent alongside the file so the deck doesn't land in someone's thread as
    /// a bare attachment with no idea what to do with it.
    /// In Messages this arrives as three bubbles — this note, an App Store card
    /// made from the link, and the deck file — so the note says which is which,
    /// in the order the person needs them.
    var message: String {
        """
        Here's a Name That Face deck: “\(deckName),” \(faceCount) \(faceCount == 1 ? "face" : "faces"), \
        already cropped and named, so you can learn everyone before you meet them.

        1. Get the free app (skip if you have it): https://apps.apple.com/app/id6811378880
        2. Tap the deck file, then the share button, and choose Name That Face.
        """
    }

    var subject: String { "\(deckName) — a Name That Face deck" }
}

struct ShareSheet: UIViewControllerRepresentable {
    let item: ShareItem
    /// Called once the sheet is gone, so the temporary file can be cleaned up.
    var onFinish: () -> Void = {}

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [DeckFileSource(item: item), DeckMessageSource(item: item)],
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, _ in onFinish() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// The file itself, named so the share sheet header reads as the deck.
private final class DeckFileSource: NSObject, UIActivityItemSource {
    let item: ShareItem
    init(item: ShareItem) { self.item = item }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
        item.url
    }

    func activityViewController(_ controller: UIActivityViewController,
                                itemForActivityType type: UIActivity.ActivityType?) -> Any? {
        item.url
    }

    func activityViewController(_ controller: UIActivityViewController,
                                subjectForActivityType type: UIActivity.ActivityType?) -> String {
        item.subject
    }
}

/// The note that travels with it. AirDrop hands the file straight to the app
/// on the other end, so a sentence of instructions there would be noise.
private final class DeckMessageSource: NSObject, UIActivityItemSource {
    let item: ShareItem
    init(item: ShareItem) { self.item = item }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { "" }

    func activityViewController(_ controller: UIActivityViewController,
                                itemForActivityType type: UIActivity.ActivityType?) -> Any? {
        guard let type else { return item.message }

        // AirDrop hands the file straight to the app on the other end, and
        // Save to Files would otherwise write the sentence out as a second
        // file. Everywhere a person reads a message — Messages, Mail, Slack —
        // the note goes along.
        if type == .airDrop || type == .copyToPasteboard || type == .saveToCameraRoll {
            return nil
        }
        if type.rawValue.contains("SaveToFiles") || type.rawValue.contains("DocumentManager") {
            return nil
        }
        return item.message
    }
}
