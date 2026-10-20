package town.nativeapp
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import org.json.JSONObject
import kotlinx.coroutines.delay
import kotlinx.coroutines.CancellationException

@Composable fun AnnouncementStrip(social:SocialModel){
    var entries by remember{mutableStateOf<List<JSONObject>>(emptyList())};var index by remember{mutableIntStateOf(0)};var selected by remember{mutableStateOf<JSONObject?>(null)};var content by remember{mutableStateOf("")}
    LaunchedEffect(social.revision){try{entries=social.request("/api/announcements?limit=50&include_expired=false",false).rows("items")}catch(e:CancellationException){throw e}catch(_:Exception){}}
    val regular=entries.filter{!it.optBoolean("pinned")}
    LaunchedEffect(regular.size){while(true){delay(8000);index=(index+1)%maxOf(1,regular.size)}}
    Column{
        entries.filter{it.optBoolean("pinned")}.take(3).forEach{entry->TextButton(onClick={selected=entry}){Text("置顶 · "+entry.optString("title"),maxLines=2)}}
        regular.getOrNull(index%maxOf(1,regular.size))?.let{entry->TextButton(onClick={selected=entry}){Text(entry.optString("title"),maxLines=2)}}
    }
    LaunchedEffect(selected){content="";selected?.let{entry->val id=entry.optString("id");if(!DeliveryRules.safeID(id))return@LaunchedEffect;try{content=social.request("/api/announcements/$id",false).field("content","description")}catch(e:CancellationException){throw e}catch(_:Exception){content="公告读取失败，请在公告列表重试。"}}}
    selected?.let{entry->AlertDialog(onDismissRequest={selected=null},title={Text(entry.optString("title"))},text={Column(Modifier.verticalScroll(rememberScrollState())){if(content.isEmpty())CircularProgressIndicator() else MarkdownText(content)}},confirmButton={TextButton(onClick={selected=null}){Text("完成")}})}
}
