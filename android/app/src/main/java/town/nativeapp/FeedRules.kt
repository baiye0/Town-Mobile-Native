package town.nativeapp
import org.json.JSONObject
import java.time.OffsetDateTime
object FeedRules {
    fun newestFirst(rows:List<JSONObject>):List<JSONObject> = rows.withIndex().sortedWith(compareByDescending<IndexedValue<JSONObject>>{row->runCatching{OffsetDateTime.parse(row.value.optString("at",row.value.optString("created_at"))).toInstant().toEpochMilli()}.getOrDefault(0)}.thenByDescending{it.value.optLong("seq",0)}.thenByDescending{it.index}).map{it.value}
    fun announcementQuery(category:String,includeExpired:Boolean):Map<String,String> = buildMap{put("include_expired",includeExpired.toString());if(category.isNotEmpty())put("category",category)}
}
