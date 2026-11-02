package town.nativeapp

import androidx.compose.foundation.interaction.DragInteraction
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.runtime.*
import kotlinx.coroutines.flow.conflate

const val CHAT_BOTTOM_KEY = "chat-bottom"
enum class ChatFollowMode { Automatic, Explicit, Reading, Anchored }
data class ChatScrollRequest(val revision:Int,val messageID:String?=null)

@Stable
class ChatScrollController(val list:LazyListState, val reversed:Boolean=false) {
    fun listIndex(messageIndex:Int,count:Int)=if(reversed)count-messageIndex else messageIndex
    var mode by mutableStateOf(ChatFollowMode.Automatic); private set
    var request by mutableStateOf<ChatScrollRequest?>(null); private set
    private var revision=0
    private var dragging=false
    private var settlePending=false
    var gestureRevision by mutableIntStateOf(0); private set
    private var anchoredReply:String?=null

    private fun resetGesture() { dragging=false;settlePending=false }
    fun bottom() { resetGesture();mode=ChatFollowMode.Explicit;request=ChatScrollRequest(++revision) }
    fun submitted() { resetGesture();mode=ChatFollowMode.Automatic;anchoredReply=null;request=ChatScrollRequest(++revision) }
    fun message(id:String) { resetGesture();mode=ChatFollowMode.Reading;request=ChatScrollRequest(++revision,id) }
    fun dragged() { dragging=true;settlePending=false;mode=ChatFollowMode.Reading;request=null;gestureRevision++ }
    fun dragEnded(cancelled:Boolean=false) {
        if(!dragging)return
        dragging=false;settlePending=!cancelled;gestureRevision++
    }
    fun settled(atBottom:Boolean,towardBottom:Boolean) {
        // Consume only the end of this gesture/fling. Later IME or Markdown
        // remeasurement must never reuse a stale scroll direction to resume follow.
        if(dragging||!settlePending)return
        settlePending=false
        if(atBottom&&towardBottom)mode=ChatFollowMode.Explicit
    }
    fun replyChanged(id:String?) {
        if(mode==ChatFollowMode.Anchored&&id!=null&&id!=anchoredReply)mode=ChatFollowMode.Automatic
    }
    fun anchored(id:String) { anchoredReply=id;mode=ChatFollowMode.Anchored }
    fun completed(command:ChatScrollRequest) { if(request==command)request=null }
}

private data class ScrollLayout(
    val messages:List<Message>,val replyID:String?,val focused:Boolean,val mode:ChatFollowMode,val request:ChatScrollRequest?,
    val count:Int,val viewport:Int,val replyHeight:Int,val tailOffset:Int?,val tailSize:Int?,val tailOverflow:Int?,val canForward:Boolean,val scrolling:Boolean,val forward:Boolean,val gestureRevision:Int,
    val firstKey:Any?,val firstSize:Int,val firstIndex:Int,val firstOffset:Int
)

@Composable fun rememberChatScrollController(reversed:Boolean=false):ChatScrollController {
    val list=rememberLazyListState()
    return remember(list,reversed){ChatScrollController(list,reversed)}
}

/** One owner issues all scroll commands, after the lazy list has measured the current messages. */
@Composable fun ChatScrollEffects(
    controller:ChatScrollController,messages:List<Message>,replyID:String?,inputFocused:Boolean,submittedID:String?,onDrag:()->Unit={}
) {
    val currentMessages by rememberUpdatedState(messages)
    val currentReply by rememberUpdatedState(replyID)
    val focused by rememberUpdatedState(inputFocused)
    val dragAction by rememberUpdatedState(onDrag)
    LaunchedEffect(controller,submittedID){if(submittedID!=null)controller.submitted()}
    LaunchedEffect(controller,replyID){controller.replyChanged(replyID)}
    LaunchedEffect(controller){
        controller.list.interactionSource.interactions.collect { interaction ->
            when(interaction) {
                is DragInteraction.Start -> {controller.dragged();dragAction()}
                is DragInteraction.Stop -> controller.dragEnded()
                is DragInteraction.Cancel -> controller.dragEnded(cancelled=true)
            }
        }
    }
    LaunchedEffect(controller) {
        val list=controller.list
        var previous:ScrollLayout?=null
        snapshotFlow {
            val layout=list.layoutInfo
            val tail=layout.visibleItemsInfo.lastOrNull{it.key==CHAT_BOTTOM_KEY}
            val first=layout.visibleItemsInfo.firstOrNull{it.index==list.firstVisibleItemIndex}
            ScrollLayout(currentMessages,currentReply,focused,controller.mode,controller.request,layout.totalItemsCount,
                layout.viewportSize.height,layout.visibleItemsInfo.firstOrNull{it.key==currentReply}?.size ?: 0,
                tail?.offset,tail?.size,tail?.let { it.offset+it.size+layout.afterContentPadding-layout.viewportEndOffset },
                if(controller.reversed)list.canScrollBackward else list.canScrollForward,
                list.isScrollInProgress,if(controller.reversed)list.lastScrolledBackward else list.lastScrolledForward,controller.gestureRevision,
                first?.key,first?.size ?: 0,list.firstVisibleItemIndex,list.firstVisibleItemScrollOffset)
        }.conflate().collect { frame ->
            val old=previous
            previous=frame
            if(frame.scrolling&&controller.request==null)return@collect
            // A new source list may arrive before LazyColumn's next measure pass.
            // Wait for that pass instead of scrolling to an old numeric index.
            if(frame.messages.isEmpty()||frame.count!=frame.messages.size+1||frame.viewport<=0)return@collect
            // A reversed list anchors the bottom edge of its first visible row.
            // If that row is still streaming, growth otherwise pushes the text
            // being read upward even with automatic following disabled.
            if(controller.reversed&&controller.mode==ChatFollowMode.Reading&&controller.request==null&&
                old!=null&&!old.scrolling&&old.mode==ChatFollowMode.Reading&&frame.firstKey!=null&&frame.firstKey==old.firstKey&&
                frame.firstSize!=old.firstSize) {
                list.scrollToItem(frame.firstIndex,(frame.firstOffset+frame.firstSize-old.firstSize).coerceAtLeast(0))
                return@collect
            }
            val atBottom=!frame.canForward&&frame.tailOffset!=null
            controller.settled(atBottom,frame.forward)
            val command=controller.request
            if(command?.messageID!=null) {
                val index=currentMessages.indexOfFirst{it.id==command.messageID}
                if(index>=0) {
                    val target=controller.listIndex(index,currentMessages.size)
                    list.scrollToItem(target)
                    if(controller.reversed) {
                        val height=list.layoutInfo.visibleItemsInfo.firstOrNull{it.index==target}?.size ?: 0
                        list.scrollToItem(target,(height-frame.viewport).coerceAtLeast(0))
                    }
                }
                controller.completed(command)
                return@collect
            }
            val replyIndex=frame.messages.indexOfFirst{it.id==frame.replyID}
            // The reverse list follows natively until the user scrolls away. Switching
            // between top-anchoring and bottom-follow as fragments grow causes jumps.
            val anchor=!controller.reversed&&command==null&&controller.mode==ChatFollowMode.Automatic&&
                ChatScrollRules.action(true,false,focused,replyIndex>frame.messages.indexOfLast{it.role=="user"},frame.replyHeight,frame.viewport)==ChatScrollAction.AnchorReply
            if(anchor&&frame.replyID!=null) {
                controller.anchored(frame.replyID)
                list.scrollToItem(controller.listIndex(replyIndex,frame.messages.size),
                    if(controller.reversed)(frame.replyHeight-frame.viewport).coerceAtLeast(0) else 0)
            } else if(command!=null||controller.mode in listOf(ChatFollowMode.Automatic,ChatFollowMode.Explicit)) {
                // Snap to the measured footer. A separate animation competes with token,
                // keyboard and image remeasure events and can finish at a stale target.
                // A fresh request must also cancel a fling that has started but
                // has not moved away from the footer on its first frame yet.
                val bottom=if(controller.reversed)0 else list.layoutInfo.totalItemsCount-1
                if(command!=null)list.scrollToItem(bottom)
                else if(!atBottom) {
                    // Visible footer: move only the measured overflow instead of resetting
                    // the lazy-list anchor and measuring the entire viewport a second time.
                    val overflow=frame.tailOverflow
                    if(controller.reversed)list.scrollToItem(bottom)
                    else if(overflow!=null&&overflow>0)list.scrollBy(overflow.toFloat())
                    else if(overflow==null)list.scrollToItem(bottom)
                }
                if(command!=null)controller.completed(command)
            }
        }
    }
}
