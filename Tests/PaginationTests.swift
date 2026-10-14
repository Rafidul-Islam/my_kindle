import XCTest
@testable import my_kindle

@MainActor
final class PaginationTests: XCTestCase {

    private func makeParagraphs(_ count: Int) -> NSMutableAttributedString {
        let output = NSMutableAttributedString()
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.alignment = .justified
        style.hyphenationFactor = 1

        let font = UIFont.systemFont(ofSize: 18)
        for index in 0..<count {
            let text = "Paragraph \(index). " + String(repeating: "Lorem ipsum dolor sit amet consectetur. ", count: 6)
            let start = output.length
            output.append(NSAttributedString(string: text + "\n", attributes: [
                .font: font,
                .paragraphStyle: style
            ]))
            output.addAttribute(.myKindlePageIndex, value: index / 3, range: NSRange(location: start, length: output.length - start))
        }
        return output
    }

    func testPaginationCoversEveryCharacter() {
        let text = makeParagraphs(20)
        let size = CGSize(width: 320, height: 480)
        let pages = Paginator.paginate(text, textRect: CGRect(origin: .zero, size: size))

        XCTAssertGreaterThan(pages.count, 1, "Twenty paragraphs cannot fit on one screen")

        var expectedStart = 0
        for page in pages {
            XCTAssertEqual(page.start, expectedStart, "Pages must be contiguous")
            XCTAssertGreaterThan(page.length, 0, "Empty pages should never be emitted")
            expectedStart = page.end
        }
        XCTAssertLessThanOrEqual(expectedStart, text.length)
    }

    func testPagesStayInsideTheDocument() {
        let text = makeParagraphs(5)
        let pages = Paginator.paginate(text, textRect: CGRect(x: 0, y: 0, width: 300, height: 400))

        for page in pages {
            XCTAssertLessThanOrEqual(page.start, text.length)
            XCTAssertLessThanOrEqual(page.end, text.length)
        }
    }

    func testTrailingBlankPagesAreTrimmed() {
        let text = makeParagraphs(3)
        let padded = NSMutableAttributedString(attributedString: text)
        padded.append(NSAttributedString(string: String(repeating: "\n", count: 400)))

        let pages = Paginator.paginate(padded, textRect: CGRect(origin: .zero, size: CGSize(width: 320, height: 480)))
        let trimmed = Paginator.paginate(text, textRect: CGRect(origin: .zero, size: CGSize(width: 320, height: 480)))

        XCTAssertLessThanOrEqual(pages.count, trimmed.count + 1)
    }

    func testDegenerateGeometryReturnsNoPages() {
        let text = makeParagraphs(3)
        XCTAssertTrue(Paginator.paginate(text, textRect: .zero).isEmpty)
        XCTAssertTrue(Paginator.paginate(NSAttributedString(string: ""), textRect: CGRect(x: 0, y: 0, width: 300, height: 400)).isEmpty)
    }

    func testDifferentSizesProduceDifferentPageCounts() {
        let text = makeParagraphs(10)
        let small = Paginator.paginate(text, textRect: CGRect(origin: .zero, size: CGSize(width: 240, height: 320)))
        let large = Paginator.paginate(text, textRect: CGRect(origin: .zero, size: CGSize(width: 600, height: 900)))
        XCTAssertGreaterThan(small.count, large.count)
    }

    func testWordSnappingFindsWholeWords() {
        let text = NSAttributedString(string: "The quick brown fox jumps over the lazy dog")
        let range = ReflowPageUIView.wordRange(in: text, around: 12)
        XCTAssertEqual(text.string[Range(range.location, in: text.string)], "brown")
    }

    func testWordSnappingHandlesPunctuationAndEdges() {
        let text = NSAttributedString(string: "alpha beta gamma")
        XCTAssertEqual(
            text.string[Range(ReflowPageUIView.wordRange(in: text, around: 0).location, in: text.string)],
            "alpha"
        )
        let end = text.length - 1
        let range = ReflowPageUIView.wordRange(in: text, around: end)
        XCTAssertEqual(text.string[Range(range.location, in: text.string)], "gamma")
    }
}