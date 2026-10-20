package town.nativeapp

data class QuestionEntry(val messageIndex:Int, val number:Int, val text:String)

object MessagePresentation {
    private val attachmentReference = Regex("(?m)^\\[attachment-message:v1:msg_[a-f0-9]{64}(?:,msg_[a-f0-9]{64})*\\]\\r?$\\n?")

    fun body(message:Message):String = DeliveryRules.displayText(message.text).replace(attachmentReference, "").trim()

    fun questions(messages:List<Message>,query:String=""):List<QuestionEntry> = messages.withIndex()
        .filter { it.value.role=="user" && it.value.kind!="marker" }
        .mapIndexed { number, row ->
            QuestionEntry(row.index,number+1,body(row.value).ifEmpty {
                row.value.files?.joinToString("、") { it.name }?.ifBlank { null } ?: "附件消息"
            })
        }.filter { query.isBlank() || it.text.contains(query.trim(),ignoreCase=true) }
}
