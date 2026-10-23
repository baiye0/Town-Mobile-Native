package town.nativeapp

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import kotlinx.coroutines.runBlocking

class ImageGenerationTest {
    private val receipt = """{"type":"being.image-generation","version":1,"being_id":"willow","jobs":[{"index":1,"title":"图片","submission":"accepted","generation_id":"gen_one","client_request_id":"request_one","error_code":null}]}"""
    @Test fun validatesReceiptWithoutCoercingTypesOrAcceptingExtraFields() {
        assertNotNull(ImageGeneration.parse(receipt))
        assertNull(ImageGeneration.parse(receipt + " trailing text"))
        assertNull(ImageGeneration.parse(receipt.replace("\"version\"", "'version'")))
        for (bad in listOf(receipt.replace("\"version\":1", "\"version\":true"), receipt.replace("\"index\":1", "\"index\":\"1\""), receipt.replace("\"gen_one\"", "null"), receipt.replace("\"being_id\":", "\"extra\":1,\"being_id\":"))) assertNull(ImageGeneration.parse(bad))
        val duplicate = JSONObject(receipt); duplicate.getJSONArray("jobs").put(JSONObject(duplicate.getJSONArray("jobs").getJSONObject(0).toString()).put("index", 2))
        assertNull(ImageGeneration.parse(duplicate.toString()))
    }
    @Test fun extractsOnlyStandaloneReceiptsAndPreservesSurroundingText() {
        val parts = ImageGeneration.parts("前文\n```json\n$receipt\n```\n后文")
        assertEquals(listOf(false, true, false), parts.map { it.receipt })
        assertEquals("前文\n", parts.first().text); assertEquals("后文", parts.last().text)
        for (text in listOf("`$receipt`", "> $receipt", "```python\n$receipt\n```", "{\"example\":$receipt}")) assertFalse(ImageGeneration.parts(text).any { it.receipt })
        assertTrue(ImageGeneration.parts(receipt.dropLast(3)).single().receipt)
        assertNull(ImageGeneration.parse(receipt.dropLast(3)))
    }
    private fun snapshot(): JSONObject = JSONObject("""{"id":"gen_one","client_request_id":"request_one","status":"succeeded","stage":"done","deadline":9999999999999,"poll_after_ms":10,"required_action":null,"error_code":null,"availability":"available","manifest":{"version":1,"kind":"image","outputs":[{"id":"out","mime":"image/png","attachment":{"source":"being-service","attachment_id":"att_one"},"view_url":"https://beings.town/api/being-service/v1/assets/att_one/view?token=a%2Bb%3D&x=1"}]}}""")
    @Test fun validatesTaskIdentityAndSignedManifestOrigin() {
        val job = ImageGeneration.parse(receipt)!!.jobs.single()
        val valid = ImageGeneration.snapshot(snapshot(), job)
        assertTrue(valid.images.single().url.endsWith("token=a%2Bb%3D&x=1"))
        for (bad in listOf(snapshot().put("id", "gen_other"), snapshot().put("client_request_id", "other"), JSONObject(snapshot().toString().replace("https://beings.town/", "https://evil.example/")), JSONObject(snapshot().toString().replace("att_one/view", "att_other/view")))) assertTrue(runCatching { ImageGeneration.snapshot(bad, job) }.isFailure)
    }
    @Test fun pollingStopsForTerminalUncertainAndDeadlineAndClampsDelays() {
        val s = GenerationSnapshot("gen_one", "queued", 100000, 0, false, emptyList(), "pending")
        assertEquals(1000L, s.wait(0)); assertEquals(500L, s.wait(99500)); assertNull(s.wait(100000))
        assertEquals(60000L, s.copy(delay = 999999).wait(0))
        for (status in listOf("succeeded", "failed", "cancelled", "uncertain")) assertNull(s.copy(status = status).wait(0))
        assertNull(s.copy(action = true).wait(0))
    }
    @Test fun rendersInlineAndReferenceImagesButLeavesCodeUntouched() {
        val url = "https://example.com/a(b).png?token=a%2Bb%3D&x=1"
        val blocks = MarkdownBlocks.parse("前 ![照片]($url) 后\n\n![引用][pic]\n\n[pic]: <$url>\n\n`![代码]($url)`\n\n```md\n![代码]($url)\n```")
        assertEquals(listOf(url, url), blocks.filter { it.kind == "image" }.map { it.text })
        assertTrue(blocks.any { it.kind == "paragraph" && it.text.contains("前 ") })
        assertTrue(blocks.any { it.kind == "code" && it.text.contains("![代码]") })
    }
    @Test fun rejectsCredentialBearingAndNonHttpsImageURLs() {
        for (url in listOf("http://example.com/a.png", "file:///a.png", "https://user:pass@example.com/a.png", "javascript:alert(1)")) assertFalse(ImageTransport.validURL(url))
        assertTrue(ImageTransport.validURL("https://example.com/a.png?token=abc"))
    }
    @Test fun rasterDataAndCrossReceiptReferences() = runBlocking {
        assertArrayEquals(byteArrayOf(1, 2, 3), ImageTransport.imageBytes("data:image/png;base64,AQID"))
        assertTrue(runCatching { ImageTransport.imageBytes("data:image/svg+xml;base64,AQID") }.isFailure)
        val text = "![照片][pic]\n\n$receipt\n\n[pic]: https://example.com/a.png\n\n```md\n[bad]: https://example.com/b.png\n```"
        val definitions = MarkdownImages.definitions(text)
        assertFalse(definitions.contains("[bad]"))
        val first = ImageGeneration.parts(text).first().text
        assertEquals("https://example.com/a.png", MarkdownBlocks.parse(first, definitions).first { it.kind == "image" }.text)
    }
    @Test fun snapshotRejectsCoercedAndFractionalNumbers() {
        val job = ImageGeneration.parse(receipt)!!.jobs.single()
        for (value in listOf("1000", 1.5, true, -1)) assertTrue(runCatching { ImageGeneration.snapshot(snapshot().put("poll_after_ms", value), job) }.isFailure)
    }
    @Test fun nestedArrayExamplesNeverTriggerQueries() {
        assertFalse(ImageGeneration.parts("```json\n[\n$receipt\n]\n```").any { it.receipt })
        for (array in listOf("[\n$receipt\n]", "[true,\n$receipt\n]", "[\"example\",\n$receipt\n]", "[\n[\n$receipt\n]\n]")) {
            val text = "示例：\n$array\n\n实际回执：\n$receipt"
            val parts = ImageGeneration.parts(text)
            assertEquals(1, parts.count { it.receipt })
            assertEquals("示例：\n$array\n\n实际回执：\n", parts.first().text)
        }
        assertEquals(1, ImageGeneration.parts("[pic]: https://example.com/a.png\n$receipt").count { it.receipt })
    }
    @Test fun referenceContextDoesNotAlterCodeOrStreamingText() {
        val definitions = "[pic]: https://example.com/a.png"
        val text = "![照片][pic]\n\n```text\n尚未闭合"
        val blocks = MarkdownBlocks.parse(text, definitions)
        assertEquals("https://example.com/a.png", blocks.first { it.kind == "image" }.text)
        assertEquals("尚未闭合", blocks.last().text)
        assertEquals("code", blocks.last().kind)
        assertEquals("{\"key\":1}", MarkdownBlocks.parse("{\"key\":1}", definitions).single().text)
    }
}
