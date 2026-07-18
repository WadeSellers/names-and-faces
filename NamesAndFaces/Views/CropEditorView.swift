import SwiftUI

/// Photos-style crop editor. The committed crop is the source of truth:
/// after every adjustment the view springs in so your crop fills the
/// screen, and pulling the corners back out zooms out to reveal more of
/// the photo. Crops are normalized against the original image, so they
/// stay non-destructive and re-editable.
struct CropEditorView: View {
    let image: UIImage
    let initialCrop: CropRegion?
    /// Called with the chosen region (nil = effectively uncropped) and the
    /// already-cropped image ready for display.
    let onDone: (CropRegion?, UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Committed crop, normalized 0...1 in image space. The layout zooms
    /// so this region always fits the viewport.
    @State private var region: CropRegion
    /// Live crop rect in display space while a drag is in flight.
    @State private var dragRect: CGRect?
    /// The crop rect as it was when the current drag began.
    @State private var dragAnchor: CGRect?

    private enum Handle: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    private static let fullFrame = CropRegion(x: 0, y: 0, width: 1, height: 1)
    private let inset: CGFloat = 24
    private let minSide: CGFloat = 80

    init(image: UIImage, initialCrop: CropRegion?, onDone: @escaping (CropRegion?, UIImage) -> Void) {
        self.image = image
        self.initialCrop = initialCrop
        self.onDone = onDone
        _region = State(initialValue: initialCrop ?? Self.fullFrame)
    }

    private var isFullFrame: Bool {
        region.x < 0.01 && region.y < 0.01 && region.width > 0.98 && region.height > 0.98
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let viewport = CGRect(origin: .zero, size: geo.size).insetBy(dx: inset, dy: inset)
                let imageFrame = imageFrame(for: region, in: viewport)
                let committedRect = displayRect(of: region, in: imageFrame)
                let cropRect = dragRect ?? committedRect

                ZStack {
                    Color.black.ignoresSafeArea()

                    if viewport.width > 0, viewport.height > 0, imageFrame.width > 0 {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: imageFrame.width, height: imageFrame.height)
                            .position(x: imageFrame.midX, y: imageFrame.midY)

                        CutoutOverlay(rect: cropRect)
                            .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))
                            .allowsHitTesting(false)

                        cropFrame(cropRect)
                            .gesture(moveGesture(imageFrame: imageFrame, viewport: viewport, committed: committedRect))

                        ForEach(Array(Handle.allCases.enumerated()), id: \.offset) { _, handle in
                            bracket(for: handle, at: cropRect)
                                .gesture(cornerDrag(handle, imageFrame: imageFrame, viewport: viewport, committed: committedRect))
                        }
                    }
                }
                .clipped()
            }
            .navigationTitle("Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Button("Reset") {
                        withAnimation(.spring(duration: 0.45)) { region = Self.fullFrame }
                    }
                    .disabled(isFullFrame)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { finish() }
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Overlay pieces

    private func cropFrame(_ cropRect: CGRect) -> some View {
        ZStack {
            Rectangle()
                .strokeBorder(.white, lineWidth: 1.5)

            if dragRect != nil {
                Path { path in
                    for third in [1.0 / 3.0, 2.0 / 3.0] {
                        path.move(to: CGPoint(x: cropRect.width * third, y: 0))
                        path.addLine(to: CGPoint(x: cropRect.width * third, y: cropRect.height))
                        path.move(to: CGPoint(x: 0, y: cropRect.height * third))
                        path.addLine(to: CGPoint(x: cropRect.width, y: cropRect.height * third))
                    }
                }
                .stroke(.white.opacity(0.4), lineWidth: 0.5)
            }
        }
        .frame(width: cropRect.width, height: cropRect.height)
        .position(x: cropRect.midX, y: cropRect.midY)
        .contentShape(Rectangle())
    }

    private func bracket(for handle: Handle, at cropRect: CGRect) -> some View {
        CornerBracket()
            .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .frame(width: 22, height: 22)
            .rotationEffect(rotation(for: handle))
            .shadow(color: .black.opacity(0.5), radius: 2)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .position(position(for: handle, in: cropRect))
    }

    // MARK: - Geometry

    /// Where the full image sits on screen so that `region` fits the
    /// viewport — this is what produces the zoomed-in framing.
    private func imageFrame(for region: CropRegion, in viewport: CGRect) -> CGRect {
        let regionWidth = image.size.width * region.width
        let regionHeight = image.size.height * region.height
        guard regionWidth > 0, regionHeight > 0 else { return .zero }
        let scale = min(viewport.width / regionWidth, viewport.height / regionHeight)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let regionCenter = CGPoint(x: (region.x + region.width / 2) * size.width,
                                   y: (region.y + region.height / 2) * size.height)
        return CGRect(x: viewport.midX - regionCenter.x,
                      y: viewport.midY - regionCenter.y,
                      width: size.width,
                      height: size.height)
    }

    private func displayRect(of region: CropRegion, in imageFrame: CGRect) -> CGRect {
        CGRect(x: imageFrame.minX + region.x * imageFrame.width,
               y: imageFrame.minY + region.y * imageFrame.height,
               width: region.width * imageFrame.width,
               height: region.height * imageFrame.height)
    }

    private func normalized(_ rect: CGRect, in imageFrame: CGRect) -> CropRegion {
        CropRegion(
            x: min(max((rect.minX - imageFrame.minX) / imageFrame.width, 0), 1),
            y: min(max((rect.minY - imageFrame.minY) / imageFrame.height, 0), 1),
            width: min(rect.width / imageFrame.width, 1),
            height: min(rect.height / imageFrame.height, 1)
        )
    }

    private func position(for handle: Handle, in cropRect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: CGPoint(x: cropRect.minX, y: cropRect.minY)
        case .topRight: CGPoint(x: cropRect.maxX, y: cropRect.minY)
        case .bottomLeft: CGPoint(x: cropRect.minX, y: cropRect.maxY)
        case .bottomRight: CGPoint(x: cropRect.maxX, y: cropRect.maxY)
        }
    }

    private func rotation(for handle: Handle) -> Angle {
        switch handle {
        case .topLeft: .degrees(0)
        case .topRight: .degrees(90)
        case .bottomRight: .degrees(180)
        case .bottomLeft: .degrees(270)
        }
    }

    // MARK: - Gestures

    private func cornerDrag(_ handle: Handle, imageFrame: CGRect, viewport: CGRect, committed: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragAnchor == nil { dragAnchor = committed }
                guard let s = dragAnchor else { return }
                let t = value.translation
                // The crop can reach anywhere the photo is visible.
                let bounds = imageFrame.intersection(viewport)

                switch handle {
                case .topLeft:
                    let nx = min(max(bounds.minX, s.minX + t.width), s.maxX - minSide)
                    let ny = min(max(bounds.minY, s.minY + t.height), s.maxY - minSide)
                    dragRect = CGRect(x: nx, y: ny, width: s.maxX - nx, height: s.maxY - ny)
                case .topRight:
                    let nx = max(min(bounds.maxX, s.maxX + t.width), s.minX + minSide)
                    let ny = min(max(bounds.minY, s.minY + t.height), s.maxY - minSide)
                    dragRect = CGRect(x: s.minX, y: ny, width: nx - s.minX, height: s.maxY - ny)
                case .bottomLeft:
                    let nx = min(max(bounds.minX, s.minX + t.width), s.maxX - minSide)
                    let ny = max(min(bounds.maxY, s.maxY + t.height), s.minY + minSide)
                    dragRect = CGRect(x: nx, y: s.minY, width: s.maxX - nx, height: ny - s.minY)
                case .bottomRight:
                    let nx = max(min(bounds.maxX, s.maxX + t.width), s.minX + minSide)
                    let ny = max(min(bounds.maxY, s.maxY + t.height), s.minY + minSide)
                    dragRect = CGRect(x: s.minX, y: s.minY, width: nx - s.minX, height: ny - s.minY)
                }
            }
            .onEnded { _ in commitDrag(imageFrame: imageFrame) }
    }

    private func moveGesture(imageFrame: CGRect, viewport: CGRect, committed: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragAnchor == nil { dragAnchor = committed }
                guard let s = dragAnchor else { return }
                let bounds = imageFrame.intersection(viewport)
                let nx = min(max(bounds.minX, s.minX + value.translation.width), bounds.maxX - s.width)
                let ny = min(max(bounds.minY, s.minY + value.translation.height), bounds.maxY - s.height)
                dragRect = CGRect(x: nx, y: ny, width: s.width, height: s.height)
            }
            .onEnded { _ in commitDrag(imageFrame: imageFrame) }
    }

    /// Adopt the dragged rect as the new committed crop and spring the
    /// whole layout in (or out) around it.
    private func commitDrag(imageFrame: CGRect) {
        defer { dragAnchor = nil }
        guard let rect = dragRect else { return }
        let newRegion = normalized(rect, in: imageFrame)
        withAnimation(.spring(duration: 0.45)) {
            dragRect = nil
            region = newRegion
        }
    }

    // MARK: - Finish

    private func finish() {
        if isFullFrame {
            onDone(nil, image)
        } else {
            onDone(region, image.cropped(to: region))
        }
        dismiss()
    }
}

// MARK: - Shapes

/// Full-screen dim with an animatable window cut out over the crop.
private struct CutoutOverlay: Shape {
    var rect: CGRect

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(AnimatablePair(rect.origin.x, rect.origin.y),
                           AnimatablePair(rect.size.width, rect.size.height))
        }
        set {
            rect = CGRect(x: newValue.first.first, y: newValue.first.second,
                          width: newValue.second.first, height: newValue.second.second)
        }
    }

    func path(in bounds: CGRect) -> Path {
        var path = Path()
        path.addRect(bounds)
        path.addRect(rect)
        return path
    }
}

/// One L-shaped crop handle, drawn for the top-left and rotated for the rest.
private struct CornerBracket: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
