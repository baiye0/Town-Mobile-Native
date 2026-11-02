package town.nativeapp

import android.app.Activity
import android.app.Application
import android.app.Instrumentation
import android.os.Bundle
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
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/** Exercises the production scheduler, Android main dispatcher and on-disk queue. All HTTP is intercepted. */
class DeliveryQueueInstrumentation : Instrumentation() {
    private var coldLaunch = false
    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments); coldLaunch = arguments?.getString("cold") == "true"; start()
    }
    private fun <T> main(block: () -> T): T {
        val result = AtomicReference<Result<T>>()
        runOnMainSync { result.set(runCatching(block)) }; return result.get().getOrThrow()
    }
    private fun waitUntil(label: String, block: () -> Boolean) {
        repeat(200) { if(main(block)) return; Thread.sleep(50) }; error("Timeout: $label")
    }
    override fun onStart() {
        val done = mutableListOf<String>()
        try {
            check(targetContext.packageName.endsWith(".portalqa"))
            val app = targetContext.applicationContext as Application
            val endpoint = "https://fixture.invalid/queue"
            val link = "$endpoint?token=test"
            val scene = "scene"
            val file = File(app.filesDir,"outbox.json")
            fun entry(text:String, phase:String) = PendingSend(endpoint=endpoint,sceneID=scene,title=scene,text=text,phase=phase)
            val failed=entry("old failure","failed")
            val missing=entry("missing submission","waiting")
            val confirmed=entry("already answered","sending")
            val queued=entry("next message","queued")
            val foreign=queued.copy(id="foreign",endpoint="https://other.invalid/queue")
            val posts = CopyOnWriteArrayList<String>()
            val stops = CopyOnWriteArrayList<String>()
            val checks = AtomicInteger()
            val overread = AtomicInteger()
            val active = AtomicReference<String?>(null)
            val history = JSONArray().put(JSONObject().put("seq",1).put("role","user").put("content",confirmed.text).put("scene_id",scene))
                .put(JSONObject().put("seq",2).put("role","self").put("content","saved reply").put("scene_id",scene))
            val client = OkHttpClient.Builder().addInterceptor { chain ->
                val req=chain.request()
                val res=Response.Builder().request(req).protocol(Protocol.HTTP_1_1).message("fixture").code(200)
                fun body()=JSONObject(Buffer().also{req.body!!.writeTo(it)}.readUtf8())
                when(req.url.encodedPath.substringAfter("/api/")) {
                    "history" -> res.body(JSONObject().put("messages",if((req.url.queryParameter("after")?.toIntOrNull() ?: 0)<2) history else JSONArray()).toString().toResponseBody()).build()
                    "stream/active" -> {
                        val count=checks.incrementAndGet()
                        val id=active.get()
                        if(id!=null || count==1) res.body(JSONObject().put("stream_id",id ?: "old-stream").put("scene_id",scene)
                            .put("finished",id==null).put("events",if(id!=null) JSONArray() else JSONArray().put(JSONObject()
                                .put("seq",1).put("event","text").put("data",JSONObject().put("text","previous turn")))).toString().toResponseBody()).build()
                        else res.code(204).body("".toResponseBody()).build()
                    }
                    "chat/stream" -> {
                        val text=body().getString("message");posts.add(text)
                        if(text=="active") {
                            active.set("owned");res.code(202).body("".toResponseBody()).build()
                        } else {
                            // A terminal SSE frame on a still-open HTTP response must release the worker.
                            val bytes=Buffer().writeUtf8("event: text\ndata: {\"text\":\"ok\"}\n\nevent: message_stop\ndata: {}\n\ndata: [DONE]\n\n")
                            val src=object:Source {
                                override fun read(sink:Buffer,byteCount:Long):Long {
                                    if(bytes.exhausted()){overread.incrementAndGet();throw java.io.IOException("Read past [DONE]")}
                                    return bytes.read(sink,byteCount)
                                }
                                override fun timeout()=Timeout.NONE
                                override fun close() {}
                            }.buffer()
                            res.header("Content-Type","text/event-stream").body(object:ResponseBody(){
                                override fun contentType()=null
                                override fun contentLength()=-1L
                                override fun source()=src
                            }).build()
                        }
                    }
                    "stop" -> { stops.add(body().getString("stream_id"));active.set(null);res.body("{}".toResponseBody()).build() }
                    else -> error("Unexpected fixture request: ${req.url.encodedPath}")
                }
            }.build()
            fun readQueue()=JSONArray(file.readText()).let{a->(0 until a.length()).map{PendingSend.read(a.getJSONObject(it))}}
            if (coldLaunch) {
                check(Vault(app).load()==link)
                check(readQueue().any { it.text=="orphan at death" && it.phase=="waiting" })
                val cold=main{ TownModel(app,client).also{it.resumeDelivery()} }
                waitUntil("cold start drain"){ !cold.busy && posts.contains("after process death") }
                check(posts==listOf("after process death") && overread.get()==0)
                check(readQueue().single{it.text=="orphan at death"}.phase=="unknown")
                check(readQueue().single{it.text=="active"}.phase=="stopped")
                finish(Activity.RESULT_OK,Bundle().apply{putString("stream","PASS: new process recovered disk queue without resending old turns.")})
                return
            }
            Vault(app).save(link)
            file.writeText(JSONArray(listOf(failed,missing,confirmed,queued,foreign).map{it.json()}).toString())
            val m=main{ TownModel(app,client).also{it.createScene(scene,scene);it.resumeDelivery()} }
            waitUntil("drain recovered entries") { !m.busy && posts.contains(queued.text) }
            check(posts==listOf(queued.text) && overread.get()==0)
            val retained=readQueue().associate{it.id to it.phase}
            check(retained==mapOf(failed.id to "failed",missing.id to "unknown",foreign.id to "queued"))
            check(readQueue().single{it.id==missing.id}.let { it.reply.isEmpty() && it.streamID==null })
            check(main{m.current!!.messages.any{it.text=="saved reply"} && m.current!!.messages.none{it.text=="previous turn"}})
            done += "Restored two orphan sends, kept uncertain/failed and foreign entries, and sent only the unsent message."
            val restarted=main{TownModel(app,client).also{it.resumeDelivery()} }
            waitUntil("second restart") { !restarted.busy }
            check(posts==listOf(queued.text))
            main { restarted.selectScene(scene); restarted.draft="active";restarted.send() }
            waitUntil("recover accepted stream") { restarted.canInterrupt(scene) }
            main { restarted.draft="ordinary";restarted.send();restarted.draft="priority";restarted.send(interrupt=true) }
            waitUntil("priority drain") { !restarted.busy && posts.contains("ordinary") }
            check(stops==listOf("owned"))
            check(posts==listOf(queued.text,"active","priority","ordinary") && overread.get()==0)
            val final=readQueue()
            check(final.single{it.id==failed.id}.phase=="failed" && final.single{it.text=="active"}.phase=="stopped")
            done += "Restart did not resend; stop targeted the active ID; priority preceded the older queued send; [DONE] did not wait for socket close."
            // Seed the next run, invoked after am force-stop, with crash-time phases.
            file.writeText(JSONArray((final+entry("orphan at death","waiting")+entry("after process death","queued")).map{it.json()}).toString())
            finish(Activity.RESULT_OK,Bundle().apply{putString("stream","PASS\n"+done.joinToString("\n"))})
        } catch(t:Throwable){finish(Activity.RESULT_CANCELED,Bundle().apply{putString("stream","FAIL\n"+t.stackTraceToString())})}
    }
}
