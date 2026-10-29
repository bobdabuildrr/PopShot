import Foundation
import Vision

/// On-device text recognition (Apple's Vision framework). Nothing leaves the Mac.
enum OCR {
    static func recognizeText(in url: URL, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let text = ImageFiles.load(url).map { recognizeText(in: $0.image) }
            DispatchQueue.main.async { completion(text) }
        }
    }

    static func recognizeText(in image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            Log.error("Text recognition failed: \(error)")
            return ""
        }
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
