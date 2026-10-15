import Foundation
import ImageIO
import UniformTypeIdentifiers
import UIKit

enum ImageDownsampler {
    /// Memory-efficient downsampling via ImageIO. Safe to call off the main thread.
    static func cgImage(from data: Data, maxPixelSize: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    static func jpegData(from data: Data, maxPixelSize: Int, quality: CGFloat = 0.85) -> Data? {
        guard let image = cgImage(from: data, maxPixelSize: maxPixelSize) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    static func image(atPath path: String, maxPixelSize: Int) -> UIImage? {
        guard let data = FileManager.default.contents(atPath: path),
              let cg = cgImage(from: data, maxPixelSize: maxPixelSize) else { return nil }
        return UIImage(cgImage: cg)
    }
}
