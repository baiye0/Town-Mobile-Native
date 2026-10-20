package town.nativeapp

object AudioTranscript {
    fun display(text: String): String {
        val preamble = "[说话人编号仅在本录音内有效，由模型根据声音区分，不代表真实身份或已确认的销售/客户角色；unknown 表示无法可靠区分。]"
        var value = text.trim().removePrefix(preamble).trim()
        val speakers = Regex("\\[说话人 ([A-Z])\\]").findAll(value).map { it.groupValues[1] }.toSet()
        if (speakers.size == 1 && !value.contains("[说话人不确定]")) value = value.replace(Regex("\\[说话人 [A-Z]\\]\\s*"), "")
        return value
    }
}
