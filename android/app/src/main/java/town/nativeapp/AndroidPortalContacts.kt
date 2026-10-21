package town.nativeapp

import android.Manifest
import android.content.ContentProviderOperation
import android.content.ContentUris
import android.content.Context
import android.provider.ContactsContract as C
import org.json.JSONObject

class AndroidPortalContacts(private val context: Context) {
    fun call(action: String, args: JSONObject): JSONObject {
        AndroidPortalPolicy.permission(context, Manifest.permission.READ_CONTACTS)
        val resolver = context.contentResolver
        if (action == "search") {
            val query = args.text("query", 200)
            val rows = linkedMapOf<Long, JSONObject>()
            val pattern = "%${query.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")}%"
            val selection = "(display_name LIKE ? ESCAPE '\\' OR data1 LIKE ? ESCAPE '\\') AND mimetype IN (?,?,?)"
            resolver.query(C.Data.CONTENT_URI, arrayOf(C.Data.CONTACT_ID, C.Data.DISPLAY_NAME, C.Data.DATA1, C.Data.RAW_CONTACT_ID, C.Data.MIMETYPE), selection,
                arrayOf(pattern, pattern, C.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE, C.CommonDataKinds.Phone.CONTENT_ITEM_TYPE, C.CommonDataKinds.Email.CONTENT_ITEM_TYPE), "raw_contact_id ASC")?.use { c ->
                while (c.moveToNext()) {
                    val id = c.getLong(3)
                    if (rows.size == 100 && id !in rows) break
                    val row = rows.getOrPut(id) { JSONObject().put("id", c.getLong(0)).put("name", c.getString(1)).put("raw_contact_id", id).put("phones", org.json.JSONArray()).put("emails", org.json.JSONArray()) }
                    when (c.getString(4)) {
                        C.CommonDataKinds.Phone.CONTENT_ITEM_TYPE -> { row.getJSONArray("phones").put(c.getString(2)); if (!row.has("phone")) row.put("phone", c.getString(2)) }
                        C.CommonDataKinds.Email.CONTENT_ITEM_TYPE -> row.getJSONArray("emails").put(c.getString(2))
                    }
                }
            }
            return JSONObject().put("contacts", jsonArray(rows.values))
        }
        AndroidPortalPolicy.permission(context, Manifest.permission.WRITE_CONTACTS)
        val id = if (action != "create") args.getLong("raw_contact_id") else null
        if (id != null) resolver.query(ContentUris.withAppendedId(C.RawContacts.CONTENT_URI, id), arrayOf("_id"), "deleted=0", null, null)?.use {
            check(it.moveToFirst()) { "Contact not found" }
        } ?: error("Contact unavailable")
        if (action == "delete") {
            check(resolver.delete(ContentUris.withAppendedId(C.RawContacts.CONTENT_URI, id!!), null, null) == 1)
            return JSONObject().put("raw_contact_id", id).put("status", "deleted")
        }
        require(action in listOf("create", "update")) { "Unknown contacts action" }
        val name = args.text("name", 200); val phone = args.text("phone", 80, false); val email = args.text("email", 200, false)
        val operations = arrayListOf<ContentProviderOperation>()
        if (id == null) operations += ContentProviderOperation.newInsert(C.RawContacts.CONTENT_URI).withValue(C.RawContacts.ACCOUNT_TYPE, null).withValue(C.RawContacts.ACCOUNT_NAME, null).build()
        else operations += ContentProviderOperation.newDelete(C.Data.CONTENT_URI).withSelection("raw_contact_id=? AND mimetype IN (?,?,?)", arrayOf(id.toString(), C.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE, C.CommonDataKinds.Phone.CONTENT_ITEM_TYPE, C.CommonDataKinds.Email.CONTENT_ITEM_TYPE)).build()
        fun add(mime: String, value: String, type: Int? = null) {
            val op = ContentProviderOperation.newInsert(C.Data.CONTENT_URI).withValue(C.Data.MIMETYPE, mime).withValue(C.Data.DATA1, value)
            if (id == null) op.withValueBackReference(C.Data.RAW_CONTACT_ID, 0) else op.withValue(C.Data.RAW_CONTACT_ID, id)
            if (type != null) op.withValue(C.Data.DATA2, type)
            operations += op.build()
        }
        add(C.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE, name)
        if (phone.isNotEmpty()) add(C.CommonDataKinds.Phone.CONTENT_ITEM_TYPE, phone, C.CommonDataKinds.Phone.TYPE_MOBILE)
        if (email.isNotEmpty()) add(C.CommonDataKinds.Email.CONTENT_ITEM_TYPE, email, C.CommonDataKinds.Email.TYPE_HOME)
        val results = resolver.applyBatch(C.AUTHORITY, operations)
        return JSONObject().put("raw_contact_id", id ?: ContentUris.parseId(results[0].uri!!)).put("status", "saved")
    }
}
