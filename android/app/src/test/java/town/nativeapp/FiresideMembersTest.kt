package town.nativeapp
import org.junit.Test
import org.junit.Assert.*
import org.json.JSONArray
import org.json.JSONObject
class FiresideMembersTest {
    @Test fun supportsDesktopMemberShapesAndDeduplicatesIdentity() {
        val payload=JSONArray("""["legacy",{"id":"t_1","displayName":"Same"},{"town_id":"t_2","display":"Same","joinedAt":"2026-10-14"},{"being_id":"t_1","name":"Duplicate"},42,null]""")
        val members=FiresideMembers.decode(payload)
        assertEquals(listOf("legacy","t_1","t_2","42"),members.map{it.id})
        assertEquals(members[1].name,members[2].name)
        assertEquals("2026-10-14",members[2].joinedAt)
        assertEquals(members,FiresideMembers.decode(JSONObject().put("members",payload)))
        assertEquals("author",FiresideMembers.authorKey("t_123"))
        assertEquals("being_id",FiresideMembers.authorKey("legacy_being"))
    }
    @Test(expected=IllegalStateException::class) fun rejectsMalformedMembers() { FiresideMembers.decode(JSONObject().put("members","invalid")) }
}
