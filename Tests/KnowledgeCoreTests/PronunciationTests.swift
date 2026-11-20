import Foundation
import XCTest

@testable import KnowledgeCore

final class PronunciationTests: XCTestCase {
    func testOnlyExactWordAndDeclaredAccentAreSelected() {
        let candidates = PronunciationRecording.candidates(
            word: "hello",
            images: [
                "File:En-us-hello.ogg", "File:En-uk-hello-1.ogg", "File:En-us-helloworld.ogg",
                "File:Fr-hello.ogg",
            ])
        XCTAssertEqual(candidates.map(\.accent), ["en-US", "en-GB"])
        XCTAssertTrue(
            PronunciationRecording.candidates(word: "../../hello", images: ["File:En-us-../../hello.ogg"])
                .isEmpty)
    }
    func testUnlicensedSyntheticAndUntrustedAudioAreRejected() throws {
        var info: [String: Any] = [
            "descriptionurl": "https://commons.wikimedia.org/wiki/File:En-us-hello.ogg",
            "url": "https://upload.wikimedia.org/example.mp3",
            "extmetadata": [
                "Artist": ["value": "Dvortygirl"], "LicenseShortName": ["value": "Public domain"],
                "ImageDescription": ["value": "Pronunciation of hello"],
            ],
        ]
        XCTAssertNotNil(
            PronunciationRecording.parse(title: "File:En-us-hello.ogg", accent: "en-US", info: info))
        info["url"] = "https://upload.wikimedia.org.evil.example/file.mp3"
        XCTAssertNil(PronunciationRecording.parse(title: "hello", accent: "en-US", info: info))
        info["url"] = "https://upload.wikimedia.org/example.mp3"
        info["comment"] = "Synthesized text-to-speech"
        XCTAssertNil(PronunciationRecording.parse(title: "hello", accent: "en-US", info: info))
        info.removeValue(forKey: "comment")
        info["extmetadata"] = [:]
        XCTAssertNil(PronunciationRecording.parse(title: "hello", accent: "en-US", info: info))
    }
    func testPDFContextMatchesOnlyTheOriginalRange() {
        let anchor = PDFTextAnchor(
            page: 1, location: 6, length: 4, text: "word", before: "first ", after: " end")
        XCTAssertTrue(anchor.matches("first word end"))
        XCTAssertFalse(anchor.matches("other word end"))
        XCTAssertFalse(anchor.matches("word first word end"))
        XCTAssertFalse(anchor.matches("short"))
    }
}
