import XCTest
import PDFKit
@testable import Inkwell

@MainActor
final class ExtractionTests: XCTestCase {

    func testExtractsTextFromSingleColumnPage() throws {
        let sentence = "Power is the ability to get people to do things you want."
        let data = SyntheticPDF.make(text: sentence)
        let document = try SyntheticPDF.document(data)

        let pages = PDFTextExtractor.extract(document: document)

        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages[0].kind, .text)

        let extracted = pages[0].runs.map(\.text).joined(separator: " ")
        XCTAssertTrue(
            extracted.contains("Power is the ability"),
            "Extracted text was: \(extracted)"
        )
    }

    func testLineGeometryIsNormalised() throws {
        let data = SyntheticPDF.make(text: "Alpha beta gamma")
        let document = try SyntheticPDF.document(data)
        let pages = PDFTextExtractor.extract(document: document)

        let run = try XCTUnwrap(pages[0].runs.first)
        XCTAssertEqual(run.rect.count, 4)
        for value in run.rect {
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 1.5, "Normalised geometry escaped its page")
        }
    }

    func testDetectsTwoColumnLayout() throws {
        var left: [String] = []
        var right: [String] = []
        for index in 0..<20 {
            left.append("Left column line number \(index)")
            right.append("Right column line number \(index)")
        }
        let data = SyntheticPDF.makeTwoColumn(left: left, right: right)
        let document = try SyntheticPDF.document(data)

        let pages = PDFTextExtractor.extract(document: document)

        XCTAssertEqual(pages[0].kind, .complex, "A genuine two-column page should not be reflowed")
    }

    func testBlankDocumentProducesImagePages() throws {
        let data = SyntheticPDF.make(text: "")
        let document = try SyntheticPDF.document(data)

        let pages = PDFTextExtractor.extract(document: document)

        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages[0].kind, .imageOnly)
        XCTAssertTrue(pages[0].runs.isEmpty)
    }

    func testLayoutAnalysisFlagsTwoColumnsDirectly() {
        var lines: [LineBox] = []
        for index in 0..<20 {
            lines.append(LineBox(
                text: "line \(index)",
                rect: CGRect(x: 40, y: CGFloat(index) * 12, width: 150, height: 10),
                pageWidth: 432,
                pageHeight: 648
            ))
            lines.append(LineBox(
                text: "line \(index)",
                rect: CGRect(x: 250, y: CGFloat(index) * 12, width: 150, height: 10),
                pageWidth: 432,
                pageHeight: 648
            ))
        }

        XCTAssertTrue(LayoutAnalysis.isMultiColumn(lines))
    }

    func testLayoutAnalysisAcceptsSingleColumn() {
        let lines = (0..<25).map { index in
            LineBox(
                text: "line \(index)",
                rect: CGRect(x: 60, y: CGFloat(index) * 12, width: 320, height: 10),
                pageWidth: 432,
                pageHeight: 648
            )
        }

        XCTAssertFalse(LayoutAnalysis.isMultiColumn(lines))
    }

    func testHeaderFooterDetection() {
        let pages: [ExtractedPage] = (0..<6).map { index in
            ExtractedPage(
                index: index,
                kind: .text,
                runs: [
                    ExtractedRun(text: "CHAPTER ONE", size: 11, bold: false, italic: false, rect: [0.1, 0.03, 0.5, 0.02]),
                    ExtractedRun(text: "Body text that belongs in the reading flow.", size: 11, bold: false, italic: false, rect: [0.1, 0.2, 0.7, 0.02]),
                    ExtractedRun(text: "\(index + 1)", size: 9, bold: false, italic: false, rect: [0.45, 0.95, 0.05, 0.02])
                ],
                width: 432,
                height: 648
            )
        }

        let drop = LayoutAnalysis.headerFooterRuns(pages: pages)

        XCTAssertTrue(drop.contains(PageRunKey(page: 0, run: 0)), "Repeated header should be dropped")
        XCTAssertTrue(drop.contains(PageRunKey(page: 3, run: 2)), "Page numbers should be dropped")
        XCTAssertFalse(drop.contains(PageRunKey(page: 2, run: 1)), "Body text must survive")
    }
}