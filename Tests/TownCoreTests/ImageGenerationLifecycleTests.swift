import Foundation
import Testing
@testable import TownCore

private let imageReceipt = #"{"type":"being.image-generation","version":1,"being_id":"alice","jobs":[{"index":1,"title":"猫咪 {窗边} 和 \"阳光\"","submission":"accepted","generation_id":"gen_one","client_request_id":"cat-one","error_code":null}]}"#

@Test func streamedImageReceiptSurvivesHistoryRoundTrip() throws {
    var entry = PendingSend(endpoint: "https://echo.beings.town/alice", sceneID: "s", title: "s", text: "生图")
    for character in imageReceipt { ReplyStream.consume("text", ["text": String(character)], entry: &entry) }
    #expect(ReplyStream.messages(entry).first?.streaming == true)
    ReplyStream.consume("message_stop", [:], entry: &entry)
    let message = try #require(ReplyStream.messages(entry).first)
    #expect(message.streaming == false)
    let restored = try JSONDecoder().decode(Message.self, from: JSONEncoder().encode(message))
    #expect(ImageGeneration.parts(restored.text).first.map { ImageGeneration.parse($0.text)?.jobs.first?.id } == "gen_one")
    #expect(ImageGeneration.parts(message.text).map(\.text) == ImageGeneration.parts(restored.text).map(\.text))
}
