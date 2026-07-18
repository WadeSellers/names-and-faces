import UIKit

extension UIImage {
    /// Downscale so the longest side is at most `maxDimension` points at 1x.
    func resized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }

        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Apply a normalized crop region (top-left origin).
    func cropped(to region: CropRegion) -> UIImage {
        guard let cg = cgImage else { return self }
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        let rect = CGRect(x: region.x * w,
                          y: region.y * h,
                          width: region.width * w,
                          height: region.height * h)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
            .integral
        guard rect.width > 1, rect.height > 1, let out = cg.cropping(to: rect) else { return self }
        return UIImage(cgImage: out)
    }
}
