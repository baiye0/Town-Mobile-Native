package town.nativeapp

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ImageGenerationLifecycleTest {
    private val receipt="""{"type":"being.image-generation","version":1,"being_id":"alice","jobs":[{"index":1,"title":"蓝猫","submission":"accepted","generation_id":"gen_one","client_request_id":"cat-one","error_code":null}]}"""

    @Test fun streamingAndRestoredHistoryKeepSameReceipt() {
        val entry=PendingSend(endpoint="https://echo.beings.town/alice",sceneID="s",title="s",text="生图")
        for(part in receipt.chunked(13))ReplyStream.consume("text",JSONObject().put("text",part),entry)
        assertEquals(true,ReplyStream.messages(entry).single().streaming)
        ReplyStream.consume("message_stop",JSONObject(),entry)
        val message=ReplyStream.messages(entry).single()
        assertEquals(false,message.streaming)
        val restored=HistoryRules.decodeLocal(HistoryRules.encodeLocal(message))
        assertEquals("gen_one",ImageGeneration.parse(ImageGeneration.parts(restored.text).single().text)!!.jobs.single().id)
    }

    @Test fun protocolStringsNeverCoerceNumbersOrBooleans() {
        val value=JSONObject(receipt)
        value.getJSONArray("jobs").getJSONObject(0).put("title",123)
        assertNull(ImageGeneration.parse(value.toString()))
        assertNull(ImageGeneration.parse(JSONObject(receipt).put("being_id",true).toString()))
        val raw=JSONObject("""{"id":"gen_one","client_request_id":"cat-one","status":"running","stage":true,"deadline":100000,"poll_after_ms":1000,"required_action":null,"error_code":null,"availability":"pending"}""")
        assertTrue(runCatching{ImageGeneration.snapshot(raw,ImageGeneration.parse(receipt)!!.jobs.single())}.isFailure)
    }
}
