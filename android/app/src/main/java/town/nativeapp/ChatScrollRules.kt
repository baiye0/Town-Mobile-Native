package town.nativeapp

enum class ChatScrollAction { Hold, FollowTail, AnchorReply }
object ChatScrollRules {
    fun action(following:Boolean,dragging:Boolean,focused:Boolean,replyAfterPrompt:Boolean,replyHeight:Int,viewport:Int):ChatScrollAction = when {
        !following||dragging -> ChatScrollAction.Hold
        !focused&&replyAfterPrompt&&viewport>0&&replyHeight>=viewport -> ChatScrollAction.AnchorReply
        else -> ChatScrollAction.FollowTail
    }
}
