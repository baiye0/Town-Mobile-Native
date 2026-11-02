package town.nativeapp

import android.app.Activity
import android.app.Application
import android.app.Instrumentation
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.FrameMetrics
import android.view.WindowInsets
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.MaterialTheme
import okhttp3.*
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer
import okio.Source
import okio.Timeout
import okio.buffer
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicReference

/** Actual chat, composer, Markdown and IME; all messages and HTTP responses are synthetic. */
class ChatRenderingInstrumentation : Instrumentation() {
    private var longReply=false
    private var ordering=false
    private var scrolling=false
    override fun onCreate(arguments: Bundle?) { scrolling=arguments?.getString("scrolling")=="true";ordering=arguments?.getString("ordering")=="true";longReply=scrolling||arguments?.getString("long")=="true";super.onCreate(arguments); start() }
    private fun <T> main(block: () -> T): T {
        val result=AtomicReference<Result<T>>()
        runOnMainSync { result.set(runCatching(block)) }; return result.get().getOrThrow()
    }
    private fun await(label:String, condition:()->Boolean) {
        repeat(1600) { if(main(condition))return; Thread.sleep(25) }; error("Timeout: $label")
    }
    private fun editable(node:AccessibilityNodeInfo?):AccessibilityNodeInfo? {
        if(node==null)return null
        if(node.isEditable)return node
        for(i in 0 until node.childCount) editable(node.getChild(i))?.let{return it}
        return null
    }
    override fun onStart() {
        var host:ScrollHarnessActivity?=null
        try {
            check(targetContext.packageName.endsWith(".portalqa"))
            val app=targetContext.applicationContext as Application
            val endpoint="https://fixture.invalid/render"
            val scene="render-scene"
            val releaseReply=java.util.concurrent.CountDownLatch(1)
            val releaseHistory=java.util.concurrent.CountDownLatch(1)
            val holdHistory=java.util.concurrent.atomic.AtomicBoolean(false)
            val failHistory=java.util.concurrent.atomic.AtomicBoolean(false)
            val chunks=if(ordering)listOf("这是本次发送之后的回复。") else if(longReply)(1..400).map { index -> when(index%4) {
                0->"\n\n### 第 $index 项\n\n保留一点从容，把复杂的事情分成小步骤。先观察，再行动，最后回顾。\n\n"
                1->"- 做一件重要的小事，给自己留出休息时间。\n- 不必急着完成所有事情。\n\n"
                2->"```kotlin\nval step = $index\nprintln(\"Keep going\")\n```\n\n"
                else->"| 时间 | 安排 |\n| --- | --- |\n| 上午 | 专注工作 |\n| 下午 | 散步休息 |\n\n"
            } } else (1..160).map { if(it%12==0)"\n\n" else "把节奏放慢一点，专注眼前。 " }
            main { Vault(app).save("$endpoint?token=fixture") }
            app.getSharedPreferences("scenes",0).edit().putString("main.$endpoint",scene).commit()
            File(app.filesDir,"outbox.json").writeText("[]")
            File(app.filesDir,"history-cache.json").writeText("{}")
            val rows=JSONArray()
            repeat(60) { i -> rows.put(HistoryRules.encodeLocal(Message(if(i%2==0)"user" else "being",
                "历史条目 $i："+(if(i%2==0)"帮我把今天的计划安排得轻松一点。" else "可以，先选最重要的一件事。\n\n- 上午留给需要专注的工作\n- 午后安排沟通和散步\n\n给自己留一点空白，不必把每一分钟填满。"),sceneID=scene,id="fixture-$i"))) }
            File(app.filesDir,"conversations.json").writeText(JSONArray().put(JSONObject().put("id",scene).put("endpoint",endpoint).put("title","日常灵感").put("messages",rows)).toString())
            val client=OkHttpClient.Builder().addInterceptor { chain ->
                val request=chain.request()
                val response=Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("fixture")
                if(request.url.encodedPath.endsWith("/chat/stream")) {
                    var index=0
                    val source=object:Source {
                        override fun timeout()=Timeout.NONE
                        override fun close(){}
                        override fun read(sink:Buffer,byteCount:Long):Long {
                            if(index>chunks.size)return -1
                            if(ordering&&index==0)check(releaseReply.await(15,java.util.concurrent.TimeUnit.SECONDS))
                            Thread.sleep(if(scrolling)75L else if(longReply)15L else 25L)
                            val packet=if(index==chunks.size) "data: [DONE]\n\n" else
                                "event: text\ndata: ${JSONObject().put("text",chunks[index])}\n\n"
                            index++
                            return Buffer().writeUtf8(packet).read(sink,byteCount)
                        }
                    }.buffer()
                    response.header("Content-Type","text/event-stream").body(object:ResponseBody(){
                        override fun contentType()=null
                        override fun contentLength()=-1L
                        override fun source()=source
                    }).build()
                } else {
                    if(request.url.encodedPath.endsWith("/history")&&holdHistory.get())check(releaseHistory.await(10,java.util.concurrent.TimeUnit.SECONDS))
                    if(request.url.encodedPath.endsWith("/history")&&failHistory.get())response.code(503)
                    response.body("{\"messages\":[],\"enabled\":false}".toResponseBody()).build()
                }
            }.build()
            val model=main { TownModel(app,client) }
            val monitor=addMonitor(ScrollHarnessActivity::class.java.name,null,false)
            uiAutomation.executeShellCommand("am start -n ${targetContext.packageName}/${ScrollHarnessActivity::class.java.name}").use {
                android.os.ParcelFileDescriptor.AutoCloseInputStream(it).use{stream->stream.readBytes()}
            }
            host=waitForMonitorWithTimeout(monitor,10000) as? ScrollHarnessActivity ?: error("No harness")
            val activity=host
            val frames=CopyOnWriteArrayList<Long>()
            val streamingFrames=CopyOnWriteArrayList<Long>()
            var captureInProgress=false
            main {
                activity.enableEdgeToEdge()
                activity.window.setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
                activity.setContent { MaterialTheme(colorScheme=clientColors(false)) { Town(m=model) } }
                activity.window.addOnFrameMetricsAvailableListener({ _, metrics, _ ->
                    val duration=metrics.getMetric(FrameMetrics.TOTAL_DURATION)
                    frames.add(duration)
                    if(model.busy&&!captureInProgress)streamingFrames.add(duration)
                },Handler(Looper.getMainLooper()))
            }
            Thread.sleep(1000)
            fun capture(name:String) {
                main { captureInProgress=true }
                uiAutomation.takeScreenshot()?.let { bitmap ->
                    File(app.getExternalFilesDir(null),"$name.png").outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) }
                    bitmap.recycle()
                }
                Thread.sleep(100)
                main { captureInProgress=false }
            }
            capture("chat-bubbles")
            main { model.draft="给我一个温柔、可执行的建议。";model.send() }
            if(ordering) {
                fun locate(node:AccessibilityNodeInfo?,label:String):AccessibilityNodeInfo? {
                    if(node==null)return null
                    if(node.isVisibleToUser&&(node.text?.toString()==label||node.contentDescription?.toString()==label))return node
                    for(i in 0 until node.childCount)locate(node.getChild(i),label)?.let{return it}
                    return null
                }
                fun bounds(label:String):android.graphics.Rect {
                    repeat(100) {
                        locate(uiAutomation.rootInActiveWindow,label)?.let { node ->
                            return android.graphics.Rect().also{node.getBoundsInScreen(it)}
                        }
                        Thread.sleep(25)
                    }
                    error("Missing visible node: $label")
                }
                Thread.sleep(250)
                capture("order-waiting")
                val prompt=bounds("给我一个温柔、可执行的建议。")
                val waiting=bounds("正在等待回复")
                check(waiting.top>=prompt.bottom){"Waiting reply ABOVE prompt: prompt=$prompt waiting=$waiting"}
                val timestamp=main { model.displayMessages.last{it.role=="user"}.timestamp!! }
                check(bounds(chatTime(timestamp)).bottom<=prompt.top){"Timestamp moved below its prompt"}
                holdHistory.set(true)
                main { model.history() }
                await("refresh starts"){model.historyLoading}
                Thread.sleep(150)
                val during=bounds("给我一个温柔、可执行的建议。")
                releaseHistory.countDown()
                await("refresh ends"){!model.historyLoading}
                Thread.sleep(150)
                val after=bounds("给我一个温柔、可执行的建议。")
                check(prompt==during&&prompt==after){"Empty refresh moved prompt: $prompt -> $during -> $after"}
                failHistory.set(true)
                main { model.history() }
                await("refresh error"){!model.historyLoading&&model.historyNotice!=null}
                Thread.sleep(150)
                check(bounds("给我一个温柔、可执行的建议。") == prompt){"Refresh error resized the conversation"}
                check(bounds(main{model.historyNotice!!}).bottom<prompt.top){"Refresh error is not in the header"}
                failHistory.set(false)
                main { model.history() }
                await("refresh error clears"){!model.historyLoading&&model.historyNotice==null}
                releaseReply.countDown()
                await("ordered reply completes"){!model.busy}
                Thread.sleep(200)
                val finalPrompt=bounds("给我一个温柔、可执行的建议。")
                val reply=bounds(chunks.single())
                check(reply.top>=finalPrompt.bottom){"Reply ABOVE prompt: prompt=$finalPrompt reply=$reply"}
                capture("order-complete")
                main { activity.finish() }
                finish(Activity.RESULT_OK,Bundle().apply{putString("stream","PASS: timestamp above prompt; waiting and final reply below prompt; refresh and refresh error leave message bounds unchanged; error shown only in header")})
                return
            }
            await("stream starts") { model.busy && model.streamingReplyID!=null }
            fun historyPositions():Map<String,Int> {
                if(android.os.Build.VERSION.SDK_INT>=33)uiAutomation.clearCache()
                val found=mutableMapOf<String,Int>()
                val diagnostic=StringBuilder()
                fun walk(node:AccessibilityNodeInfo?) {
                    if(node==null)return
                    node.refresh()
                    val text=node.text?.toString().orEmpty()
                    diagnostic.append("visible=${node.isVisibleToUser} text=$text description=${node.contentDescription}\n")
                    if(node.isVisibleToUser&&(text.startsWith("历史条目 ")||text.startsWith("val step = ")||text=="给我一个温柔、可执行的建议。")) {
                        val bounds=android.graphics.Rect();node.getBoundsInScreen(bounds)
                        if(bounds.top>180)found[text]=bounds.top
                    }
                    for(i in 0 until node.childCount)walk(node.getChild(i))
                }
                walk(uiAutomation.rootInActiveWindow)
                File(app.getExternalFilesDir(null),"scroll-nodes.txt").writeText(diagnostic.toString())
                return found
            }
            fun swipe(from:Float,to:Float) {
                val bounds=android.graphics.Rect();uiAutomation.rootInActiveWindow.getBoundsInScreen(bounds)
                val x=bounds.centerX();val start=(bounds.height()*from).toInt();val end=(bounds.height()*to).toInt()
                val downTime=android.os.SystemClock.uptimeMillis()
                for(step in 0..30) {
                    val action=when(step){0->android.view.MotionEvent.ACTION_DOWN;30->android.view.MotionEvent.ACTION_UP;else->android.view.MotionEvent.ACTION_MOVE}
                    main {
                        val event=android.view.MotionEvent.obtain(downTime,android.os.SystemClock.uptimeMillis(),action,x.toFloat(),start+(end-start)*step/30f,0)
                        activity.dispatchTouchEvent(event);event.recycle()
                    }
                    Thread.sleep(20)
                }
                Thread.sleep(400)
            }
            if(scrolling) {
                var attempts=0
                while(historyPositions().isEmpty()&&attempts++<12)swipe(.25f,.75f)
                repeat(3){swipe(.25f,.75f)}
            }
            repeat(3) {
                if(scrolling) {
                    swipe(if(it%2==0).4f else .6f,if(it%2==0).65f else .4f)
                    check(main{model.busy}){"Reply finished before gesture test"}
                }
                val before=if(scrolling)historyPositions() else emptyMap()
                if(scrolling&&before.isEmpty())capture("scroll-failure")
                if(scrolling)check(before.isNotEmpty()){"Gesture failed to reach historical messages"}
                val input=editable(uiAutomation.rootInActiveWindow) ?: error("No composer")
                check(input.performAction(AccessibilityNodeInfo.ACTION_CLICK))
                main { activity.window.insetsController?.show(WindowInsets.Type.ime()) }
                await("keyboard opens") { activity.window.decorView.rootWindowInsets?.isVisible(WindowInsets.Type.ime())==true }
                Thread.sleep(600)
                if(it==0)capture("chat-keyboard")
                main { activity.window.insetsController?.hide(WindowInsets.Type.ime()) }
                await("keyboard closes") { activity.window.decorView.rootWindowInsets?.isVisible(WindowInsets.Type.ime())==false }
                Thread.sleep(600)
                if(scrolling) {
                    val after=historyPositions()
                    check(before.any{(key,y)->after[key]?.let{kotlin.math.abs(it-y)<=2}==true}){"Keyboard/streaming stole history anchor: $before -> $after"}
                }
            }
            await("reply completes") { !model.busy }
            val expected=chunks.joinToString("")
            check(main { model.displayMessages.last().text==expected }) { "Final reply lost or duplicated a chunk" }
            capture("chat-complete")
            val sorted=streamingFrames.sorted()
            val p95=sorted[(sorted.size*.95).toInt().coerceAtMost(sorted.lastIndex)]/1_000_000.0
            val debuggable=app.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0
            if(scrolling)check(historyPositions().isNotEmpty()){"Stream completion stole reading position"}
            val result="PASS production chat: all ${chunks.size} streamed chunks / ${expected.length} characters preserved, 3 real IME open/close cycles; real swipe/history anchor checks=$scrolling; ${frames.size} total frames; ${sorted.size} streaming frames, P95=${p95}ms, >50ms=${sorted.count{it>50_000_000}} (debuggable=$debuggable, concurrent keyboard animation; screenshot intervals excluded)"
            File(app.getExternalFilesDir(null),if(longReply)"chat-rendering-long.txt" else "chat-rendering.txt").writeText(result)
            main { activity.finish() }
            finish(Activity.RESULT_OK,Bundle().apply{putString("stream",result)})
        } catch(error:Throwable) {
            main { host?.finish() }
            finish(Activity.RESULT_CANCELED,Bundle().apply{putString("stream",error.stackTraceToString())})
        }
    }
}
