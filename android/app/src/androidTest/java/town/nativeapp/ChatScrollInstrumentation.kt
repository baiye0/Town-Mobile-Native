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
    override fun onCreate(arguments:Bundle?) { super.onCreate(arguments);start() }
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
                        controller=rememberChatScrollController()
                        scope=rememberCoroutineScope()
                        ready=true
                        ChatScrollEffects(controller,messages,replyID,focused,submittedID)
                        LazyColumn(Modifier.fillMaxWidth().height(viewport.dp),state=controller.list,contentPadding=PaddingValues(24.dp),verticalArrangement=Arrangement.spacedBy(18.dp)) {
                            itemsIndexed(messages,key={_,message->message.id}) { index,message ->
                                Box(Modifier.fillMaxWidth().height(if(index==messages.lastIndex)lastHeight.dp else (40+index%5*25).dp)){Text(message.text)}
                            }
                            item(key=CHAT_BOTTOM_KEY){Spacer(Modifier.height(1.dp))}
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
                    !controller.list.canScrollForward&&layout.totalItemsCount==messages.size+1&&tail.offset+tail.size+layout.afterContentPadding<=layout.viewportEndOffset+1
            }
            await("initial long last message",{ready&&bottom()})
            passed.add("initial long history reaches actual footer")
            onMain{controller.message("m2")}
            await("index jump",{controller.request==null&&controller.list.firstVisibleItemIndex==2})
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
            onMain{focused=false;controller.message("m3")}
            await("read history",{controller.request==null&&controller.list.firstVisibleItemIndex==3})
            onMain{lastHeight=2200;messages=messages+Message("being","background update",id="m42")}
            Thread.sleep(150)
            check(onMain{controller.mode==ChatFollowMode.Reading&&controller.list.firstVisibleItemIndex==3})
            passed.add("reading history is not pulled down by updates")
            onMain{
                messages=messages+Message("user","new prompt",id="m43")+Message("being","new long reply",id="m44")
                replyID="m44";submittedID="m43";viewport=360
            }
            await("automatic long reply anchor",{controller.mode==ChatFollowMode.Anchored&&controller.list.firstVisibleItemIndex==44})
            onMain{controller.bottom()}
            await("override anchor",{bottom()&&controller.mode==ChatFollowMode.Explicit})
            passed.add("bottom button overrides automatic long reply anchor")
            repeat(10){index->onMain{controller.bottom();lastHeight+=15;messages=messages+Message("being","burst $index",id="burst$index")};Thread.sleep(16)}
            await("burst final footer",{bottom()&&controller.request==null})
            passed.add("ten rapid requests and appends finish at latest footer")
            lateinit var oldScroll:Job
            onMain{controller.dragged();oldScroll=scope.launch{controller.list.animateScrollToItem(0)}}
            await("old scroll running",{controller.list.isScrollInProgress})
            onMain{controller.bottom()}
            await("bottom interrupts old scroll",{bottom()&&controller.request==null})
            check(oldScroll.isCancelled){"Old scroll was not superseded"}
            passed.add("explicit bottom cancels an in-flight scroll")
            onMain{host.finish()}
            finish(Activity.RESULT_OK,Bundle().apply{putString("stream","PASS ${passed.size} scroll scenarios\n"+passed.joinToString("\n"))})
        } catch(error:Throwable) {
            host?.let{onMain{it.finish()}}
            finish(Activity.RESULT_CANCELED,Bundle().apply{putString("stream","FAIL after ${passed.size} scenarios\n"+error.stackTraceToString())})
        }
    }
}
