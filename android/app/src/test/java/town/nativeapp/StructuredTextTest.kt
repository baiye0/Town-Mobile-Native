package town.nativeapp
import org.junit.Test
import org.junit.Assert.*
class StructuredTextTest {
    @Test fun formattingPreservesLargeNumbersDuplicateKeysAndEscapes(){
        val source="""{"id":9007199254740993123,"id":2,"text":"a\\b\n","empty":[]}"""
        assertEquals("json",StructuredText.detect(source));val pretty=StructuredText.formatJSON(source)!!
        assertTrue(pretty.contains("9007199254740993123"));assertEquals(3,pretty.split("\"id\"").size);assertTrue(pretty.contains("""a\\b\n"""))
        assertEquals("code",MarkdownBlocks.parse(source).first().kind)
    }
    @Test fun detectsOnlyCompleteStructuredText(){assertEquals("jsonl",StructuredText.detect("{\"a\":1}\n{\"b\":2}"));assertNull(StructuredText.detect("{\"a\":"));assertNull(StructuredText.detect("123"));assertNull(StructuredText.detect("{\"x\":01}"))}
}
