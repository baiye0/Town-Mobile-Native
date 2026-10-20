package town.nativeapp
import org.json.JSONObject
import java.time.OffsetDateTime
object FeedRules {
    fun newestFirst(rows:List<JSONObject>):List<JSONObject> = rows.withIndex().sortedWith(compareByDescending<IndexedValue<JSONObject>>{row->runCatching{OffsetDateTime.parse(row.value.optString("at",row.value.optString("created_at"))).toInstant().toEpochMilli()}.getOrDefault(0)}.thenByDescending{it.value.optLong("seq",0)}.thenByDescending{it.index}).map{it.value}
    fun announcementQuery(category:String,includeExpired:Boolean):Map<String,String> = buildMap{put("include_expired",includeExpired.toString());if(category.isNotEmpty())put("category",category)}
}

data class FeedFilter(val author:String="",val relation:String="all",val days:Int=0,val oldestFirst:Boolean=false){
    fun matches(row:JSONObject,me:String,now:Long=System.currentTimeMillis()):Boolean{
        val authorID=row.field("sender_town_id","sender_being_id","sender_id","town_id","being_id","being","sender")
        val name=row.field("sender_display","sender_display_name","speaker_name","display_name","display","sender_name")
        if(author.isNotEmpty()&&!authorID.contains(author,true)&&!name.contains(author,true))return false
        val mine=me.isNotEmpty()&&authorID==me;val received=me.isNotEmpty()&&row.field("recipient_town_id","recipient_being_id","recipient_id","recipient","to")==me
        val mentions=row.optJSONArray("mentions")?.let{a->(0 until a.length()).map{(a.opt(it) as? String) ?: a.optJSONObject(it)?.field("town_id","being_id") ?: ""}} ?: Regex("@([A-Za-z0-9_-]+)").findAll(row.field("content","message")).map{it.groupValues[1]}.toList()
        val mentioned=me.isNotEmpty()&&me in mentions
        if(relation=="mine"&&!mine||relation=="mentions"&&!mentioned||relation=="about"&&!(mine||received||mentioned))return false
        if(days>0){val time=runCatching{OffsetDateTime.parse(row.field("at","created_at")).toInstant().toEpochMilli()}.getOrNull() ?: return false;if(time<now-days*86400000L)return false}
        return true
    }
}
