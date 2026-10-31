import Foundation
import XCTest
@testable import WristlyCore

final class CoreTests: XCTestCase {
    func testPublicConnectionOmitsAuthorizationForChatAndVoice() {
        let connection = Connection(baseURL: URL(string: "https://worker.example")!, token: "")
        let chat = connection.request("chat")
        let voice = connection.request("asr", websocket: true)
        XCTAssertEqual(chat.url?.absoluteString, "https://worker.example/chat")
        XCTAssertNil(chat.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(voice.url?.absoluteString, "wss://worker.example/asr")
        XCTAssertNil(voice.value(forHTTPHeaderField: "Authorization"))
    }
    func testPrivateConnectionSendsTokenOnlyInHeader() {
        let connection = Connection(baseURL: URL(string: "https://worker.example")!, token: "private-test-token")
        for request in [connection.request("chat"), connection.request("asr", websocket: true)] {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer private-test-token")
            XCTAssertFalse(request.url!.absoluteString.contains("private-test-token"))
        }
    }
    func testSSEFrameWithCommentsAndCRLF() throws {
        var parser = SSEDecoder()
        XCTAssertNil(try parser.line(": heartbeat\r"))
        XCTAssertNil(try parser.line("event: delta\r"))
        XCTAssertNil(try parser.line("data: 你好\r"))
        XCTAssertNil(try parser.line("data: world\r"))
        XCTAssertEqual(try parser.line("\r"), SSEFrame(event: "delta", data: "你好\nworld"))
        XCTAssertNil(try parser.line(""))
    }
    func testContextExcludesPartialAnswersAndBoundsHistory() {
        var messages: [ChatMessage] = (0..<40).map { index in
            ChatMessage(role: index.isMultiple(of: 2) ? .user : .assistant, content: String(repeating: "x", count: 2000))
        }
        messages.append(ChatMessage(role: .assistant, content: "partial", state: .failed))
        messages.append(ChatMessage(role: .user, content: "follow up"))
        let context = ConversationContext.messages(from: messages)
        XCTAssertEqual(context.first?.role, "user")
        XCTAssertEqual(context.last?.content, "follow up")
        XCTAssertFalse(context.contains { $0.content == "partial" })
        XCTAssertLessThanOrEqual(context.reduce(0) { $0 + $1.content.utf16.count }, 24_000)
    }
    func testPersistenceRoundTripAndNewContext() throws {
        let saved = [ChatMessage(role: .user, content: "问题"), ChatMessage(role: .assistant, content: "回答")]
        XCTAssertEqual(try JSONDecoder().decode([ChatMessage].self, from: JSONEncoder().encode(saved)), saved)
        XCTAssertTrue(ConversationContext.messages(from: []).isEmpty)
    }
    func testUnsafeSourceLinksRejected() {
        XCTAssertNil(SourceLink(title: "x", url: "javascript:alert(1)", snippet: "").safeURL)
        XCTAssertNotNil(SourceLink(title: "x", url: "https://example.com", snippet: "").safeURL)
    }
}
