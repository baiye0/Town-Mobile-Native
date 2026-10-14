package town.nativeapp

import org.json.JSONArray
import org.json.JSONObject

data class FiresideMember(val id:String,val name:String,val townID:String,val joinedAt:String)
object FiresideMembers {
    fun decode(payload:Any):List<FiresideMember> {
        val values=(payload as? JSONArray) ?: (payload as? JSONObject)?.optJSONArray("members")
            ?: error("Town 返回的成员名单格式不正确。")
        val seen=mutableSetOf<String>()
        return (0 until values.length()).mapNotNull { index ->
            val value=values.opt(index)
            val record=value as? JSONObject
            val townID=record?.field("town_id","being_id","id") ?: ""
            val name=record?.field("display_name","displayName","name","display","town_id","being_id","id")
                ?: when(value) { is String,is Number -> value.toString(); else -> "" }
            val id=townID.ifEmpty { name }
            if(id.isBlank() || !seen.add(id)) null else FiresideMember(id,name,townID,record?.field("joined_at","joinedAt") ?: "")
        }
    }
    fun authorKey(identity:String)=if(identity.startsWith("t_"))"author" else "being_id"
}
