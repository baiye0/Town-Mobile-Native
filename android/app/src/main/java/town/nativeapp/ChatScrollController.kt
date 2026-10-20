package town.nativeapp

import androidx.compose.foundation.interaction.DragInteraction
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.*
import kotlinx.coroutines.flow.conflate

const val CHAT_BOTTOM_KEY = "chat-bottom"
enum class ChatFollowMode { Automatic, Explicit, Reading, Anchored }
data class ChatScrollRequest(val revision:Int,val messageID:String?=null)

@Stable
class ChatScrollController(val list:LazyListState) {
    var mode by mutableStateOf(ChatFollowMode.Automatic); private set
    var request by mutableStateOf<ChatScrollRequest?>(null); private set
    private var revision=0
    private var manual=false
    private var anchoredReply:String?=null

    fun bottom() { manual=false;mode=ChatFollowMode.Explicit;request=ChatScrollRequest(++revision) }
    fun submitted() { manual=false;mode=ChatFollowMode.Automatic;anchoredReply=null;request=ChatScrollRequest(++revision) }
    fun message(id:String) { manual=false;mode=ChatFollowMode.Reading;request=ChatScrollRequest(++revision,id) }
    fun dragged() { manual=true;mode=ChatFollowMode.Reading;request=null }
    fun settled(atBottom:Boolean,towardBottom:Boolean) {
        if(manual&&atBottom&&towardBottom){mode=ChatFollowMode.Explicit;manual=false}
    }
    fun replyChanged(id:String?) {
        if(mode==ChatFollowMode.Anchored&&id!=null&&id!=anchoredReply)mode=ChatFollowMode.Automatic
    }
    fun anchored(id:String) { anchoredReply=id;mode=ChatFollowMode.Anchored }
    fun completed(command:ChatScrollRequest) { if(request==command)request=null }
}

private data class ScrollLayout(
    val messages:List<Message>,val replyID:String?,val focused:Boolean,val mode:ChatFollowMode,val request:ChatScrollRequest?,
    val count:Int,val viewport:Int,val replyHeight:Int,val tailOffset:Int?,val tailSize:Int?,val canForward:Boolean,val scrolling:Boolean,val forward:Boolean
)

@Composable fun rememberChatScrollController():ChatScrollController {
    val list=rememberLazyListState()
    return remember(list){ChatScrollController(list)}
}

/** One owner issues all scroll commands, after the lazy list has measured the current messages. */
@Composable fun ChatScrollEffects(
    controller:ChatScrollController,messages:List<Message>,replyID:String?,inputFocused:Boolean,submittedID:String?,onDrag:()->Unit={}
) {
    val currentMessages by rememberUpdatedState(messages)
    val currentReply by rememberUpdatedState(replyID)
    val focused by rememberUpdatedState(inputFocused)
    val dragAction by rememberUpdatedState(onDrag)
    LaunchedEffect(controller,inputFocused){if(inputFocused)controller.bottom()}
    LaunchedEffect(controller,submittedID){if(submittedID!=null)controller.submitted()}
    LaunchedEffect(controller,replyID){controller.replyChanged(replyID)}
    LaunchedEffect(controller){
        controller.list.interactionSource.interactions.collect { interaction ->
            if(interaction is DragInteraction.Start){controller.dragged();dragAction()}
        }
    }
    LaunchedEffect(controller) {
        val list=controller.list
        snapshotFlow {
            val layout=list.layoutInfo
            val tail=layout.visibleItemsInfo.lastOrNull{it.key==CHAT_BOTTOM_KEY}
            ScrollLayout(currentMessages,currentReply,focused,controller.mode,controller.request,layout.totalItemsCount,
                layout.viewportSize.height,layout.visibleItemsInfo.firstOrNull{it.key==currentReply}?.size ?: 0,
                tail?.offset,tail?.size,list.canScrollForward,list.isScrollInProgress,list.lastScrolledForward)
        }.conflate().collect { frame ->
            if(frame.scrolling&&controller.request==null)return@collect
            // A new source list may arrive before LazyColumn's next measure pass.
            // Wait for that pass instead of scrolling to an old numeric index.
            if(frame.messages.isEmpty()||frame.count!=frame.messages.size+1||frame.viewport<=0)return@collect
            val atBottom=!frame.canForward&&frame.tailOffset!=null
            controller.settled(atBottom,frame.forward)
            val command=controller.request
            if(command?.messageID!=null) {
                val index=currentMessages.indexOfFirst{it.id==command.messageID}
                if(index>=0)list.scrollToItem(index)
                controller.completed(command)
                return@collect
            }
            val replyIndex=frame.messages.indexOfFirst{it.id==frame.replyID}
            val anchor=command==null&&controller.mode==ChatFollowMode.Automatic&&
                ChatScrollRules.action(true,false,focused,replyIndex>frame.messages.indexOfLast{it.role=="user"},frame.replyHeight,frame.viewport)==ChatScrollAction.AnchorReply
            if(anchor&&frame.replyID!=null) {
                controller.anchored(frame.replyID);list.scrollToItem(replyIndex)
            } else if(command!=null||controller.mode in listOf(ChatFollowMode.Automatic,ChatFollowMode.Explicit)) {
                // Snap to the measured footer. A separate animation competes with token,
                // keyboard and image remeasure events and can finish at a stale target.
                // A fresh request must also cancel a fling that has started but
                // has not moved away from the footer on its first frame yet.
                if(command!=null||!atBottom)list.scrollToItem(list.layoutInfo.totalItemsCount-1)
                if(command!=null)controller.completed(command)
            }
        }
    }
}
