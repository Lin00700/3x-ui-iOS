import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// 把文本画成二维码，用于订阅链接与分享链接预览。
enum QRCodeGenerator {
    static func image(for text: String, scale: CGFloat = 12) -> UIImage? {
        guard !text.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
