@testable import FieldJobs
import Foundation
import Testing
import UIKit

@MainActor @Suite(.timeLimit(.minutes(1))) struct PhotoEncoderTests {
    /// Random pixels, the worst case for JPEG, at a scale of 1 so points are pixels.
    func noise(side: Int) -> UIImage {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        arc4random_buf(&bytes, bytes.count)
        let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
                            shouldInterpolate: false, intent: .defaultIntent)!
        return UIImage(cgImage: image)
    }

    func solid(side: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    @Test func encoderFitsLargeNoisyImage() throws {
        let image = noise(side: 4000)
        #expect(try #require(image.jpegData(compressionQuality: 0.4)).count > 5_242_880) // shrinking is needed

        let data = try #require(PhotoEncoder.jpeg(from: image))

        #expect(data.count <= 5_242_880)
        #expect(UIImage(data: data) != nil)
    }

    @Test func encoderKeepsSmallImageAtFirstQuality() {
        let image = solid(side: 200)
        #expect(PhotoEncoder.jpeg(from: image) == image.jpegData(compressionQuality: 0.8))
    }

    @Test func encoderGivesUpBelowMinimumSize() {
        // 1000 → 750 points, and the next step, 562.5, is below 640.
        #expect(PhotoEncoder.jpeg(from: solid(side: 1000), maxBytes: 1) == nil)
    }
}
