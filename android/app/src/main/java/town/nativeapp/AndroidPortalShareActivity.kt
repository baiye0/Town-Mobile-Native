package town.nativeapp

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import org.json.JSONObject
import java.io.File
import java.time.Instant
import java.util.UUID

/** Incoming shares are explicitly accepted by the user before exposing them to the Being. */
class AndroidPortalShareActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent.action !in listOf(Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE)) { finish(); return }
        val owner = AndroidPortalPolicy.owner(this)
        if (owner.isEmpty()) { android.widget.Toast.makeText(this, "请先在 Being 中连接身份，再分享内容。", android.widget.Toast.LENGTH_LONG).show(); finish(); return }
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString().orEmpty()
        val uris = if (intent.action == Intent.ACTION_SEND_MULTIPLE) intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM).orEmpty()
            else listOfNotNull(intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
        if (text.length > 100000 || uris.size > 10 || uris.any { it.scheme != "content" }) { finish(); return }
        AlertDialog.Builder(this).setTitle("分享给当前 Being")
            .setMessage("${text.take(300)}\n${uris.size} 个附件。文字需开启分享读取能力后 Being 才能访问；附件复制到当前 Being 的工作区，允许文件访问时即可读取。")
            .setPositiveButton("接收") { _, _ ->
                Thread {
                    val created = mutableListOf<File>()
                    val result = runCatching {
                        check(owner == AndroidPortalPolicy.owner(this))
                        val workspace = PortalRuntime.workspace(this, owner)
                        val files = uris.map { uri ->
                            val original = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { if (it.moveToFirst()) it.getString(0) else null } ?: "attachment"
                            val safe = original.replace(Regex("[^\\p{L}\\p{N}._-]"), "_").take(80)
                            val name = "share-${UUID.randomUUID()}-$safe"
                            contentResolver.openInputStream(uri)?.use { workspace.importFile(name, it) } ?: error("Unable to read attachment")
                            created += workspace.resolve(name)
                            JSONObject().put("path", name).put("name", original.take(200))
                        }
                        check(owner == AndroidPortalPolicy.owner(this))
                        AndroidPortalStore(this, owner).put("shares", JSONObject().put("id", UUID.randomUUID().toString()).put("text", text)
                            .put("files", jsonArray(files)).put("time", Instant.now().toString()), 100)
                    }
                    if (result.isFailure) created.forEach { it.delete() }
                    runOnUiThread {
                        android.widget.Toast.makeText(this, if (result.isSuccess) "已保存到 Portal 分享收件箱" else "接收失败：单文件限 10 MB，请检查文件与可用空间。", android.widget.Toast.LENGTH_LONG).show()
                        if (result.isSuccess) startActivity(Intent(this, MainActivity::class.java).putExtra("open_portal", true))
                        finish()
                    }
                }.start()
            }.setNegativeButton("取消") { _, _ -> finish() }.setOnCancelListener { finish() }.show()
    }
}
