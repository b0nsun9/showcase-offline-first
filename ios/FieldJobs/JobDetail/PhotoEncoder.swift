import Domain
import UIKit

/// Encodes a photo as a JPEG that fits the API's limit: lower quality first, then a smaller size.
enum PhotoEncoder {
    static func jpeg(from image: UIImage, maxBytes: Int = Job.photoByteLimit) -> Data? {
        var image = image
        while true {
            for quality in [0.8, 0.6, 0.4] {
                if let data = image.jpegData(compressionQuality: quality), data.count <= maxBytes { return data }
            }
            let size = CGSize(width: image.size.width * 0.75, height: image.size.height * 0.75)
            guard max(size.width, size.height) >= 640 else { return nil }
            let format = UIGraphicsImageRendererFormat()
            format.scale = image.scale // the default is the screen's scale, which would triple a camera photo's pixels
            format.opaque = true
            image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        }
    }
}
