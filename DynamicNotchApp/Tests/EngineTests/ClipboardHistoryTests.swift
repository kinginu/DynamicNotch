// Tests of the clipboard history rules (Sources/ClipboardHistory.swift): what is captured,
// consecutive-duplicate merging, the limit, re-copy, deletion and which image files become
// unreferenced.
import Foundation
import Testing
@testable import DynamicNotchApp   // the CLT harness library and the Xcode test-support library

private let t0 = Date(timeIntervalSince1970: 1_792_400_000)

private func text(_ s: String, at offset: TimeInterval = 0, app: String? = nil) -> ClipboardItem {
    var item = ClipboardItem(kind: .text, date: t0.addingTimeInterval(offset), text: s)
    item.sourceBundleID = app
    return item
}

private func image(_ hash: String, file: String, at offset: TimeInterval = 0) -> ClipboardItem {
    ClipboardItem(kind: .image, date: t0.addingTimeInterval(offset), imageFileName: file,
                  imageWidth: 10, imageHeight: 20, imageHash: hash)
}

private func files(_ paths: [String]) -> ClipboardItem {
    ClipboardItem(kind: .files, date: t0, filePaths: paths)
}

@Suite("Clipboard history")
struct ClipboardHistoryTests {

    // MARK: Capture

    @Test(arguments: [
        (["public.utf8-plain-text"], nil as String?, true),
        ([], nil, false),                                                            // empty pasteboard
        (["public.utf8-plain-text", "org.nspasteboard.ConcealedType"], nil, false),  // password manager
        (["public.utf8-plain-text", "org.nspasteboard.TransientType"], nil, false),
        (["public.utf8-plain-text", "com.agilebits.onepassword"], nil, false),
        (["public.utf8-plain-text"], "com.example.excluded", false),                 // excluded app
        (["public.utf8-plain-text"], "com.apple.Safari", true),
    ])
    func mayRecord(_ types: [String], _ source: String?, _ expected: Bool) {
        #expect(ClipboardCapture.mayRecord(types: types, sourceBundleID: source,
                                           excludedBundleIDs: ["com.example.excluded"]) == expected)
    }

    struct ChoiceCase: Sendable, CustomTestStringConvertible {
        var name: String
        var fileType: Bool, fileURLs: Bool, string: String?, image: Bool, captureFiles: Bool, captureImages: Bool
        var expected: ClipboardCapture.Choice
        var testDescription: String { name }
    }

    static let choices: [ChoiceCase] = [
        .init(name: "text", fileType: false, fileURLs: false, string: "hello", image: false, captureFiles: true, captureImages: true, expected: .text),
        .init(name: "whitespace only", fileType: false, fileURLs: false, string: " \n\t", image: false, captureFiles: true, captureImages: true, expected: .nothing),
        .init(name: "files win", fileType: true, fileURLs: true, string: "a.txt", image: true, captureFiles: true, captureImages: true, expected: .files),
        .init(name: "file copy with file capture off", fileType: true, fileURLs: true, string: "a.txt", image: false, captureFiles: false, captureImages: true, expected: .nothing),
        .init(name: "text beats image", fileType: false, fileURLs: false, string: "caption", image: true, captureFiles: true, captureImages: true, expected: .text),
        .init(name: "image", fileType: false, fileURLs: false, string: nil, image: true, captureFiles: true, captureImages: true, expected: .image),
        .init(name: "image with image capture off", fileType: false, fileURLs: false, string: nil, image: true, captureFiles: true, captureImages: false, expected: .nothing),
        .init(name: "unreadable file URLs", fileType: true, fileURLs: false, string: nil, image: true, captureFiles: true, captureImages: true, expected: .nothing),
    ]

    @Test(arguments: choices)
    func choice(_ c: ChoiceCase) {
        let got = ClipboardCapture.choose(hasFileURLType: c.fileType, hasFileURLs: c.fileURLs, string: c.string,
                                          hasImage: { c.image }, captureFiles: c.captureFiles,
                                          captureImages: c.captureImages)
        #expect(got == c.expected)
    }

    @Test func imageIsReadOnlyWhenNeeded() {
        var asked = 0
        _ = ClipboardCapture.choose(hasFileURLType: false, hasFileURLs: false, string: "text",
                                    hasImage: { asked += 1; return true }, captureFiles: true, captureImages: true)
        #expect(asked == 0)
        _ = ClipboardCapture.choose(hasFileURLType: false, hasFileURLs: false, string: nil,
                                    hasImage: { asked += 1; return true }, captureFiles: true, captureImages: true)
        #expect(asked == 1)
    }

    @Test func textItemIsCapped() {
        let long = String(repeating: "a", count: ClipboardCapture.maxTextLength + 10)
        #expect(ClipboardCapture.textItem(long)?.text?.count == ClipboardCapture.maxTextLength)
        #expect(ClipboardCapture.textItem("  \n ") == nil)
        #expect(ClipboardCapture.textItem(" x ")?.text == " x ")   // kept as copied
    }

    // MARK: Dedupe

    @Test func consecutiveDuplicateMerges() {
        var h = ClipboardHistory()
        h.record(text("hello", app: "com.a"), limit: 10)
        h.record(text("hello", at: 60, app: "com.b"), limit: 10)
        #expect(h.items.count == 1)
        #expect(h.items[0].date == t0.addingTimeInterval(60))
        #expect(h.items[0].sourceBundleID == "com.b")
    }

    @Test func mergeKeepsKnownSourceWhenNewOneIsUnknown() {
        var h = ClipboardHistory()
        h.record(text("hello", app: "com.a"), limit: 10)
        h.record(text("hello", at: 5), limit: 10)
        #expect(h.items[0].sourceBundleID == "com.a")
    }

    @Test func nonConsecutiveDuplicateIsAddedAgain() {
        var h = ClipboardHistory()
        h.record(text("a"), limit: 10)
        h.record(text("b"), limit: 10)
        h.record(text("a"), limit: 10)
        #expect(h.items.compactMap(\.text) == ["a", "b", "a"])
    }

    @Test func sameContentRules() {
        #expect(text("x").hasSameContent(as: text("x", at: 9)))
        #expect(!text("x").hasSameContent(as: text("X")))
        #expect(files(["/a", "/b"]).hasSameContent(as: files(["/a", "/b"])))
        #expect(!files(["/a", "/b"]).hasSameContent(as: files(["/b", "/a"])))
        #expect(image("h1", file: "1.png").hasSameContent(as: image("h1", file: "2.png")))
        #expect(!image("h1", file: "1.png").hasSameContent(as: image("h2", file: "1.png")))
        var unhashed = image("h", file: "1.png"); unhashed.imageHash = nil
        #expect(!unhashed.hasSameContent(as: unhashed))
        #expect(!text("1.png").hasSameContent(as: image("1.png", file: "1.png")))
    }

    @Test func duplicateImageMergesAndKeepsItsFile() {
        var h = ClipboardHistory()
        h.record(image("h1", file: "1.png"), limit: 10)
        #expect(h.topImage(withHash: "h1")?.imageFileName == "1.png")
        #expect(h.topImage(withHash: "h2") == nil)
        let freed = h.record(image("h1", file: "1.png", at: 3), limit: 10)
        #expect(freed.isEmpty)
        #expect(h.items.count == 1)
    }

    // MARK: Limit

    @Test func limitDropsOldest() {
        var h = ClipboardHistory()
        for i in 0..<5 { h.record(text("t\(i)", at: Double(i)), limit: 3) }
        #expect(h.items.compactMap(\.text) == ["t4", "t3", "t2"])
    }

    @Test func limitHasAFloorOfOne() {
        var h = ClipboardHistory()
        h.record(text("a"), limit: 0)
        h.record(text("b"), limit: -5)
        #expect(h.items.compactMap(\.text) == ["b"])
    }

    @Test func loweringTheLimitTrimsAndFreesImages() {
        var h = ClipboardHistory()
        h.record(image("h1", file: "1.png"), limit: 10)
        h.record(image("h2", file: "2.png"), limit: 10)
        h.record(text("c"), limit: 10)
        let freed = h.trim(to: 1)
        #expect(h.items.compactMap(\.text) == ["c"])
        #expect(Set(freed) == ["1.png", "2.png"])
        let freedAgain = h.trim(to: 1)
        #expect(freedAgain.isEmpty)
    }

    @Test func recordBeyondLimitFreesTheDroppedImage() {
        var h = ClipboardHistory()
        h.record(image("h1", file: "1.png"), limit: 2)
        h.record(text("a"), limit: 2)
        let freed = h.record(text("b"), limit: 2)
        #expect(freed == ["1.png"])
    }

    // MARK: Re-copy, delete, clear

    @Test func promoteMovesToTopWithNewDate() {
        var h = ClipboardHistory()
        h.record(text("a"), limit: 10)
        h.record(text("b"), limit: 10)
        let a = h.items[1]
        let promoted = h.promote(id: a.id, date: t0.addingTimeInterval(99))
        #expect(promoted)
        #expect(h.items.compactMap(\.text) == ["a", "b"])
        #expect(h.items[0].date == t0.addingTimeInterval(99))
        #expect(h.items[0].id == a.id)
        let promotedUnknown = h.promote(id: UUID(), date: t0)
        #expect(!promotedUnknown)
    }

    @Test func removeFreesOnlyUnreferencedImages() {
        let shared = image("h1", file: "shared.png")
        var other = image("h1", file: "shared.png"); other.id = UUID()
        var h = ClipboardHistory(items: [shared, text("x"), other])   // two entries share a file
        let first = h.remove(id: shared.id)
        #expect(first.isEmpty)
        let second = h.remove(id: other.id)
        #expect(second == ["shared.png"])
        let unknown = h.remove(id: UUID())
        #expect(unknown.isEmpty)
        #expect(h.items.compactMap(\.text) == ["x"])
    }

    @Test func removeAllFreesEveryImageOnce() {
        var h = ClipboardHistory(items: [image("a", file: "a.png"), text("x"), image("b", file: "b.png")])
        let freed = h.removeAll()
        #expect(Set(freed) == ["a.png", "b.png"])
        #expect(h.items.isEmpty)
    }

    @Test func loadDropsImagesWithoutFiles() {
        var noName = image("n", file: "n.png"); noName.imageFileName = nil
        var h = ClipboardHistory(items: [image("a", file: "a.png"), text("x"), image("b", file: "gone.png"), noName])
        h.dropMissingImages { $0 != "gone.png" }
        #expect(h.items.count == 2)
        #expect(h.referencedImageFiles == ["a.png"])
    }

    // MARK: Presentation

    @Test func summaries() {
        #expect(text("  first line \n\n  second  ").summary == "first line second")
        #expect(image("h", file: "f.png").summary == "Image 10 × 20")
        #expect(files(["/tmp/a.txt"]).summary == "a.txt")
        #expect(files(["/tmp/a.txt", "/tmp/b.txt", "/tmp/c.txt"]).summary == "a.txt and 2 more")
        #expect(files([]).summary == "")
    }

    @Test(arguments: [
        ("https://example.com/x", true), ("http://example.com", true), (" https://a.b \n", true),
        ("ftp://example.com", false), ("https://", false), ("see https://a.b", false), ("example.com", false),
    ])
    func webURLs(_ s: String, _ expected: Bool) {
        #expect(ClipboardItem.isWebURL(s) == expected)
        #expect((text(s).symbolName == "link") == expected)
    }

    @Test func codableRoundTrip() throws {
        let items = [text("a", app: "com.a"), image("h", file: "f.png"), files(["/x"])]
        let data = try JSONEncoder().encode(items)
        #expect(try JSONDecoder().decode([ClipboardItem].self, from: data) == items)
    }
}
