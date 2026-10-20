package town.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Test

class AudioTranscriptTest {
    @Test fun removesOnlyFixedPreambleAndSingleSpeakerLabels() {
        val preamble = "[说话人编号仅在本录音内有效，由模型根据声音区分，不代表真实身份或已确认的销售/客户角色；unknown 表示无法可靠区分。]"
        assertEquals("你好\n明天见", AudioTranscript.display("\n$preamble\n[说话人 A] 你好\n[说话人 A] 明天见"))
        assertEquals("正文 $preamble", AudioTranscript.display("正文 $preamble"))
    }
    @Test fun preservesMultipleSpeakersAndUncertainty() {
        listOf("[说话人 A] 你好\n[说话人 B] 再见", "[说话人 A] 可能\n[说话人不确定] 听不清", "[无法辨认] [unknown] 嗯").forEach { assertEquals(it, AudioTranscript.display(it)) }
    }
}
