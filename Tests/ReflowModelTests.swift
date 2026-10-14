import XCTest
import PDFKit
@testable import my_kindle

@MainActor
final class ReflowModelTests: XCTestCase {

    private func buildModel(text: String) throws -> ReflowModel {
        let data = SyntheticPDF.make(text: text)
        let document = try SyntheticPDF.document(data)
        return ReflowBuilder.build(document: document, bookID: UUID(), fingerprint: "test")
    }

    func testModelContainsExtractedText() throws {
        let model = try buildModel(text: "Persuasion has one great advantage over all other novels.")

        XCTAssertFalse(model.runs.isEmpty)
        XCTAssertTrue(
            model.text.contains("Persuasion has one great advantage"),
            "Model text was: \(model.text.prefix(120))"
        )
    }

    func testEveryRunPointsInsideTheText() throws {
        let model = try buildModel(text: "One\nTwo\nThree\nFour")
        let length = model.length

        for run in model.runs {
            XCTAssertGreaterThanOrEqual(run.loc, 0)
            XCTAssertLessThanOrEqual(run.loc + run.len, length, "Run \(run) escaped the text")
        }
    }

    func testPageOffsetsAreMonotonic() throws {
        let model = try buildModel(text: "First page text\nwith two lines")

        XCTAssertFalse(model.pageStartOffsets.isEmpty)
        for index in 1..<model.pageStartOffsets.count {
            XCTAssertGreaterThanOrEqual(
                model.pageStartOffsets[index],
                model.pageStartOffsets[index - 1],
                "Page offsets must not go backwards"
            )
        }
    }

    func testPageIndexAttributeSurvivesStyling() throws {
        let model = try buildModel(text: "Page one content")
        var settings = ReaderSettings.default
        settings.fontStep = 5

        let small = ReflowTypography.attributedString(
            model: model, settings: .init(), textAreaSize: CGSize(width: 320, height: 480), imageResolver: { _ in nil }
        )
        let large = ReflowTypography.attributedString(
            model: model, settings: settings, textAreaSize: CGSize(width: 320, height: 480), imageResolver: { _ in nil }
        )

        XCTAssertEqual(small.length, large.length, "Restyling must not change the character count")
        XCTAssertEqual(small.string, large.string, "Restyling must not change the text")

        let size = small.length > 0
            ? small.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
            : nil
        let bigger = large.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertNotNil(size)
        XCTAssertNotNil(bigger)
        XCTAssertGreaterThan(bigger?.pointSize ?? 0, size?.pointSize ?? 0)
    }

    func testLocatorRoundTripsThroughCodable() throws {
        let locators: [Locator] = [
            .reflow(charOffset: 128, length: 42, quote: "some quoted text"),
            .pdfRect(pageIndex: 7, rect: [0.1, 0.2, 0.3, 0.4])
        ]

        for locator in locators {
            let data = try JSONEncoder.inwell.encode(locator)
            let decoded = try JSONDecoder.inwell.decode(Locator.self, from: data)
            XCTAssertEqual(locator, decoded)
        }
    }

    func testFingerprintChangesWithFileSize() throws {
        let small = try SyntheticPDF.temporaryURL(SyntheticPDF.make(text: "a"), name: "small.pdf")
        let large = try SyntheticPDF.temporaryURL(SyntheticPDF.make(text: String(repeating: "word ", count: 400)), name: "large.pdf")

        XCTAssertNotEqual(ReflowBuilder.fingerprint(for: small), ReflowBuilder.fingerprint(for: large))
    }

    func testChapterExtractionSurvivesMissingOutline() throws {
        let document = try SyntheticPDF.document(SyntheticPDF.make(text: "No outline here"))
        XCTAssertTrue(ReflowBuilder.chapters(from: document).isEmpty)
    }
}