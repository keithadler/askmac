//  Ask for Mac — MIT licensed. See LICENSE.
//
//  Text in screenshots and photos, recognised on the Mac with Vision, so "the screenshot of the
//  wifi password" is answerable. Images are only read when the question asks for pictures or
//  screenshots; reading every image in Downloads for every question would be slow and pointless.

import Foundation
import AppKit
import Vision

enum OCR {
    static func recognize(_ url: URL) -> String? {
        guard let image = NSImage(contentsOf: url), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return recognize(cg)
    }
    static func recognize(_ cg: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
        do { try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request]) } catch { return nil }
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
