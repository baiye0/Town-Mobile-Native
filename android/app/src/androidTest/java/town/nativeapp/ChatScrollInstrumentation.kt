package town.nativeapp

import android.app.Activity
import android.app.Instrumentation
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.roundToInt
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/** Exercises the production coordinator on a real measured LazyColumn, without injected input or network calls. */
class ChatScrollInstrumentation : Instrumentation() {
    private var reversed=false
    override fun onCreate(arguments:Bundle?) { reversed=arguments?.getString("reverse")=="true";super.onCreate(arguments);start() }
    private fun <T> onMain(block:()->T):T {
        val result=AtomicReference<Result<T>>()
        runOnMainSync{result.set(runCatching(block))}
        return result.get().getOrThrow()
    }
    private fun await(label:String,condition:()->Boolean) {
        repeat(200) { if(onMain(condition))return;Thread.sleep(20) }
        error("Timed out: $label")
    }
    override fun onStart() {
        var host:ScrollHarnessActivity?=null
        val passed=mutableListOf<String>()
        try {
            val monitor=addMonitor(ScrollHarnessActivity::class.java.name,null,false)
            // Shell launch also works on OEMs that block background activity starts
            // from the instrumentation process. No input injection is used.
            uiAutomation.executeShellCommand("am start -n ${targetContext.packageName}/${ScrollHarnessActivity::class.java.name}").use {
                android.os.ParcelFileDescriptor.AutoCloseInputStream(it).use{stream->stream.readBytes()}
            }
            host=waitForMonitorWithTimeout(monitor,10000) as? ScrollHarnessActivity ?: error("Scroll harness did not start")
            lateinit var controller:ChatScrollController
            lateinit var scope:CoroutineScope
            var ready=false
            var messages by mutableStateOf((0 until 40).map{Message(if(it%2==0)"user" else "being","Synthetic $it",id="m$it")})
            var replyID by mutableStateOf<String?>(null)
            var submittedID by mutableStateOf<String?>(null)
            var focused by mutableStateOf(false)
            var viewport by mutableIntStateOf(360)
            var lastHeight by mutableIntStateOf(900)
            onMain {
                host.setContent {
                    MaterialTheme {
                        controller=rememberChatScrollController(reversed)
                        scope=rememberCoroutineScope()
                        ready=true
                        ChatScrollEffects(controller,messages,replyID,focused,submittedID)
                        LazyColumn(Modifier.fillMaxWidth().height(viewport.dp),state=controller.list,reverseLayout=reversed,contentPadding=PaddingValues(24.dp),verticalArrangement=Arrangement.spacedBy(18.dp)) {
                            if(reversed)item(key=CHAT_BOTTOM_KEY){Spacer(Modifier.height(1.dp))}
                            itemsIndexed(if(reversed)messages.asReversed() else messages,key={_,message->message.id}) { _,message ->
                                val stableIndex=messages.indexOfFirst{it.id==message.id}
                                Box(Modifier.fillMaxWidth().height(if(message.id==messages.last().id)lastHeight.dp else (40+stableIndex%5*25).dp)){Text(message.text)}
                            }
                            if(!reversed)item(key=CHAT_BOTTOM_KEY){Spacer(Modifier.height(1.dp))}
                        }
                    }
                }
            }
            fun bottom():Boolean {
                val layout=controller.list.layoutInfo
                val tail=layout.visibleItemsInfo.lastOrNull{it.key==CHAT_BOTTOM_KEY} ?: return false
                val density=targetContext.resources.displayMetrics.density
                val last=layout.visibleItemsInfo.lastOrNull{it.key==messages.last().id} ?: return false
                return layout.viewportSize.height==(viewport*density).roundToInt()&&last.size==(lastHeight*density).roundToInt()&&
                    (if(reversed)!controller.list.canScrollBackward else !controller.list.canScrollForward)&&layout.totalItemsCount==messages.size+1&&
                    (reversed||tail.offset+tail.size+layout.afterContentPadding<=layout.viewportEndOffset+1)
            }
            await("initial long last message",{ready&&bottom()})
            passed.add("initial long history reaches actual footer")
            onMain{controller.message("m10")}
            await("index jump",{controller.request==null&&controller.list.firstVisibleItemIndex==controller.listIndex(10,messages.size)})
            onMain{controller.bottom();messages=messages+Message("being","new while jumping",id="m40");controller.bottom()}
            await("return during append",{bottom()&&controller.request==null})
            passed.add("repeated bottom request uses latest measured list")
            onMain{replyID="m40";lastHeight=1400}
            await("stream growth",{bottom()&&controller.mode==ChatFollowMode.Explicit})
            onMain{messages=messages+Message("being","next bubble",id="m41");replyID="m41"}
            await("new reply bubble",{bottom()&&controller.mode==ChatFollowMode.Explicit})
            passed.add("explicit bottom survives long reply and bubble change")
            onMain{focused=true;viewport=180}
            await("keyboard viewport",{bottom()&&controller.list.layoutInfo.viewportSize.height>0})
            onMain{lastHeight=1800}
            await("late image layout",{bottom()})
            passed.add("keyboard resize and late content remeasure stay at footer")
            onMain{focused=false;controller.message("m13")}
            await("read history",{controller.request==null&&controller.list.firstVisibleItemIndex==controller.listIndex(13,messages.size)})
            onMain{lastHeight=2200;messages=messages+Message("being","background update",id="m42")}
            Thread.sleep(150)
            check(onMain{controller.mode==ChatFollowMode.Reading&&controller.list.firstVisibleItemIndex==controller.listIndex(13,messages.size)})
            passed.add("reading history is not pulled down by updates")
            onMain{
                messages=messages+Message("user","new prompt",id="m43")+Message("being","new long reply",id="m44")
                replyID="m44";submittedID="m43";viewport=360
            }
            if(reversed)await("automatic long reply follows natively",{controller.mode==ChatFollowMode.Automatic&&bottom()})
            else await("automatic long reply anchor",{controller.mode==ChatFollowMode.Anchored&&controller.list.firstVisibleItemIndex==controller.listIndex(44,messages.size)})
            onMain{controller.bottom()}
            await("override anchor",{bottom()&&controller.mode==ChatFollowMode.Explicit})
            passed.add(if(reversed)"long replies keep native bottom follow without jumping to their top" else "bottom button overrides automatic long reply anchor")
            repeat(10){index->onMain{controller.bottom();lastHeight+=15;messages=messages+Message("being","burst $index",id="burst$index")};Thread.sleep(16)}
            await("burst final footer",{bottom()&&controller.request==null})
            passed.add("ten rapid requests and appends finish at latest footer")
            lateinit var oldScroll:Job
            onMain{controller.dragged();oldScroll=scope.launch{controller.list.animateScrollToItem(if(reversed)messages.size else 0)}}
            await("old scroll running",{controller.list.isScrollInProgress})
            onMain{controller.bottom()}
            await("bottom interrupts old scroll",{bottom()&&controller.request==null})
            check(oldScroll.isCancelled){"Old scroll was not superseded"}
            passed.add("explicit bottom cancels an in-flight scroll")
            onMain {
                controller.dragged()
                controller.settled(true,true)
                check(controller.mode==ChatFollowMode.Reading){"Drag start reused stale bottom direction"}
                controller.dragEnded()
                controller.settled(false,true)
                controller.settled(true,true)
                check(controller.mode==ChatFollowMode.Reading){"Layout reflow rearmed follow after gesture settled"}
            }
            passed.add("drag start and later layout reflow cannot reuse a stale direction")
            onMain{scope.launch{controller.list.scrollToItem(controller.listIndex(20,messages.size),30)}}
            await("manual history anchor",{controller.list.firstVisibleItemIndex==controller.listIndex(20,messages.size)})
            val anchor=onMain{controller.list.firstVisibleItemScrollOffset}
            repeat(12){i->
                onMain {
                    focused=i%2==0;viewport=if(focused)180 else 360
                    lastHeight+=35
                    messages=messages+Message("being","stream segment $i",id="reading-$i")
                }
                Thread.sleep(120)
                check(onMain{controller.mode==ChatFollowMode.Reading&&controller.list.firstVisibleItemIndex==controller.listIndex(20,messages.size)&&controller.list.firstVisibleItemScrollOffset==anchor}){"Streaming/keyboard cycle $i stole the history anchor"}
            }
            passed.add("12 streaming append/keyboard resize cycles preserve history key and offset")
            onMain{controller.dragged();controller.dragEnded(cancelled=true);controller.settled(true,true)}
            check(onMain{controller.mode==ChatFollowMode.Reading})
            onMain{controller.dragged();scope.launch{controller.list.scrollToItem(if(reversed)0 else messages.size)}}
            await("manual return to footer",{bottom()})
            onMain{controller.dragEnded();controller.settled(true,true)}
            await("resume from real return",{controller.mode==ChatFollowMode.Explicit})
            onMain{lastHeight+=100}
            await("follow after real return",{bottom()})
            passed.add("cancel preserves reading; completed return-to-bottom gesture resumes follow")
            if(reversed) {
                onMain{controller.message(messages.last().id)}
                await("read growing reply",{controller.request==null&&controller.mode==ChatFollowMode.Reading})
                val before=onMain{controller.list.firstVisibleItemScrollOffset}
                val pixels=(100*targetContext.resources.displayMetrics.density).roundToInt()
                onMain{lastHeight+=100}
                await("growing row keeps its text anchor",{kotlin.math.abs(controller.list.firstVisibleItemScrollOffset-before-pixels)<=1})
                passed.add("growth of the visible reply preserves its text position while reading")
            }
            onMain{host.finish()}
            finish(Activity.RESULT_OK,Bundle().apply{putString("stream","PASS ${passed.size} scroll scenarios (reverse=$reversed)\n"+passed.joinToString("\n"))})
        } catch(error:Throwable) {
            host?.let{onMain{it.finish()}}
            finish(Activity.RESULT_CANCELED,Bundle().apply{putString("stream","FAIL after ${passed.size} scenarios\n"+error.stackTraceToString())})
        }
    }
}
