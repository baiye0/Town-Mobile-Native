package town.nativeapp
import org.junit.Test
import org.junit.Assert.*
import org.json.JSONObject
class FeedRulesTest {
    @Test fun newestFirstAcrossTimezonesAndTies(){
        val rows=listOf(JSONObject("""{"seq":1,"at":"2026-10-14T12:00:00Z"}"""),JSONObject("""{"seq":3,"created_at":"2026-10-14T20:01:00+08:00"}"""),JSONObject("""{"seq":2,"at":"2026-10-14T12:01:00Z"}"""))
        assertEquals(listOf(3,2,1),FeedRules.newestFirst(rows).map{it.getInt("seq")})
    }
    @Test fun allAnnouncementsOmitsCategory(){assertFalse(FeedRules.announcementQuery("",false).containsKey("category"));assertEquals("update",FeedRules.announcementQuery("update",false)["category"])}
}
