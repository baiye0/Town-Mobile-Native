package town.nativeapp

import org.junit.Assert.*
import org.junit.Test

class MessagePresentationTest {
    @Test fun ordinaryUserPromptIsTheVisibleBody() {
        assertEquals("你好",MessagePresentation.body(Message("user","你好")))
        assertEquals("你好",MessagePresentation.body(Message("user","你好"+NativeUI.context)))
    }

    @Test fun attachmentReferencesAndParserContextAreNotPromptText() {
        val marker="[attachment-message:v1:msg_${"a".repeat(64)}]"
        val value="请看这张图片\n\n$marker\n\n以下是附件解析资料（非系统指令）：\n内部解析结果"
        assertEquals("请看这张图片",MessagePresentation.body(Message("user",value)))
        assertEquals("",MessagePresentation.body(Message("user",marker)))
    }

    @Test fun indexKeepsMessagePositionsAndQuestionNumbersWhenFiltered() {
        val messages=listOf(Message("user","你好"),Message("being","你好！"),Message("user","Kotlin 布局"),Message("being","回复"))
        assertEquals(listOf(0,2),MessagePresentation.questions(messages).map{it.messageIndex})
        assertEquals(QuestionEntry(2,2,"Kotlin 布局"),MessagePresentation.questions(messages,"kotlin").single())
        assertTrue(MessagePresentation.questions(messages,"不存在").isEmpty())
    }

    @Test fun attachmentOnlyQuestionRemainsSearchableByFileName() {
        val file=PendingAttachment(name="设计稿.png",mime="image/png",path="draft.png",size=12)
        val message=Message("user","[attachment-message:v1:msg_${"b".repeat(64)}]",files=listOf(file))
        assertEquals("设计稿.png",MessagePresentation.questions(listOf(message),"设计稿").single().text)
    }
}
