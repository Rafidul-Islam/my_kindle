import Foundation
import UIKit
import PDFKit
import XCTest
@testable import Inkwell

/// Builds PDFs in-memory so the engine tests do not need bundled fixtures.
enum SyntheticPDF {

    @discardableResult
    static func make(
        text: String,
        pageSize: CGSize = CGSize(width: 432, height: 648),
        fontSize: CGFloat = 12
    ) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let data = renderer.pdfData { context in
            context.beginPage()
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 2

            let lines = text.components(separatedBy: "\n")
            var y: CGFloat = 60
            for line in lines {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: fontSize),
                    .foregroundColor: UIColor.black,
                    .paragraphStyle: paragraph
                ]
                (line as NSString).draw(at: CGPoint(x: 60, y: y), withAttributes: attributes)
                y += fontSize * 1.4
            }
        }
        return data
    }

    /// Two blocks of text side by side, to exercise column detection.
    @discardableResult
    static func makeTwoColumn(
        left: [String],
        right: [String],
        pageSize: CGSize = CGSize(width: 432, height: 648)
    ) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { context in
            context.beginPage()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: UIColor.black
            ]
            var leftY: CGFloat = 60
            for line in left {
                (line as NSString).draw(at: CGPoint(x: 50, y: leftY), withAttributes: attributes)
                leftY += 14
            }
            var rightY: CGFloat = 60
            for line in right {
                (line as NSString).draw(at: CGPoint(x: 250, y: rightY), withAttributes: attributes)
                rightY += 14
            }
        }
    }

    static func document(_ data: Data) throws -> PDFDocument {
        let document = PDFDocument(data: data)
        return try XCTUnwrap(document, "Generated PDF could not be reopened")
    }

    static func temporaryURL(_ data: Data, name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InkwellTests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try data.write(to: url)
        return url
    }
}