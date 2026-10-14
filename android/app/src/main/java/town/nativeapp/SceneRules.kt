package town.nativeapp
object SceneRules {
    fun validID(value:String)=Regex("^[\\x21-\\x7e]{1,256}$").matches(value)
    fun validName(value:String)=value.trim().isNotEmpty()&&value.length<=128&&!Regex("[\\r\\n\\x00-\\x1f]").containsMatchIn(value)
    fun stripTransition(value:String)=value.replace(Regex("^【新消息来自 scene「[^」\\r\\n]{1,256}」】\\r?\\n\\r?\\n"),"")
}
