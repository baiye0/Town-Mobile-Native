import Testing
@testable import TownCore

@Test func transcriptRemovesOnlyFixedPreambleAndSingleSpeakerLabels() {
    let preamble = "[说话人编号仅在本录音内有效，由模型根据声音区分，不代表真实身份或已确认的销售/客户角色；unknown 表示无法可靠区分。]"
    #expect(AudioTranscript.display("\n\(preamble)\n[说话人 A] 你好\n[说话人 A] 明天见") == "你好\n明天见")
    #expect(AudioTranscript.display("正文 \(preamble)") == "正文 \(preamble)")
}

@Test func transcriptPreservesMultipleSpeakersAndUncertainty() {
    for text in ["[说话人 A] 你好\n[说话人 B] 再见", "[说话人 A] 可能\n[说话人不确定] 听不清", "[无法辨认] [unknown] 嗯"] {
        #expect(AudioTranscript.display(text) == text)
    }
}
