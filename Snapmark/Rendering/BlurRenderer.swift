import AppKit
import CoreImage

/// GPU-accelerated blur rendering using Core Image.
final class BlurRenderer {
    /// Shared CIContext for efficient GPU rendering.
    static let ciContext: CIContext = {
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: metalDevice)
        }
        return CIContext()
    }()

    /// Renders a blurred patch of the base image within the given rect.
    ///
    /// - Parameters:
    ///   - baseImage: The full base image.
    ///   - rect: The region to blur, in image-point coordinates (top-left origin).
    ///   - radius: Gaussian blur radius in point units.
    /// - Returns: An NSImage of the blurred region, or nil on failure.
    static func renderBlur(baseImage: NSImage, rect: CGRect, radius: CGFloat) -> NSImage? {
        guard let cgImage = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let ciImage = CIImage(cgImage: cgImage)

        // Convert from image-point coords (top-left origin) to CIImage pixel coords (bottom-left origin).
        // NSImage.size is in points; CGImage/CIImage dimensions are in pixels.
        let scaleX = CGFloat(cgImage.width) / baseImage.size.width
        let scaleY = CGFloat(cgImage.height) / baseImage.size.height
        let pixelHeight = CGFloat(cgImage.height)

        let ciRect = CGRect(
            x: rect.origin.x * scaleX,
            y: pixelHeight - (rect.origin.y + rect.height) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).intersection(ciImage.extent)

        guard !ciRect.isEmpty else { return nil }

        // Clamp edges to avoid border darkening, apply blur, then crop to region.
        let clamped = ciImage.clampedToExtent()

        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(clamped, forKey: kCIInputImageKey)
        // Scale blur radius to pixel space so visual intensity matches what the user expects.
        filter.setValue(radius * max(scaleX, scaleY), forKey: kCIInputRadiusKey)

        guard let output = filter.outputImage else { return nil }
        let cropped = output.cropped(to: ciRect)

        guard let blurredCG = ciContext.createCGImage(cropped, from: ciRect) else {
            return nil
        }

        return NSImage(cgImage: blurredCG, size: NSSize(width: rect.width, height: rect.height))
    }
}
