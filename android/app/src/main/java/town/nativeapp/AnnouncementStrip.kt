package town.nativeapp
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import org.json.JSONObject
import kotlinx.coroutines.delay
import kotlinx.coroutines.CancellationException

@Composable fun AnnouncementStrip(social:SocialModel){
    var entries by remember{mutableStateOf<List<JSONObject>>(emptyList())};var index by remember{mutableIntStateOf(0)};var selected by remember{mutableStateOf<JSONObject?>(null)};var content by remember{mutableStateOf("")}
    LaunchedEffect(social.revision){try{entries=social.request("/api/announcements?limit=50&include_expired=false",false).rows("items")}catch(e:CancellationException){throw e}catch(_:Exception){}}
    val ordered=entries.sortedByDescending{it.optBoolean("pinned")}
    LaunchedEffect(ordered.size){if(ordered.size>1)while(true){delay(8000);if(selected==null)index=(index+1)%ordered.size}}
    ordered.getOrNull(index%maxOf(1,ordered.size))?.let{entry->
        Surface(shape=RoundedCornerShape(12.dp),color=MaterialTheme.colorScheme.surfaceContainerLow){
            Row(Modifier.fillMaxWidth().clickable(onClickLabel="查看公告"){selected=entry}.heightIn(min=48.dp).padding(horizontal=12.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(8.dp)){
                Icon(AppIcons.Announcement,null,Modifier.size(18.dp),tint=MaterialTheme.colorScheme.primary)
                Text((if(entry.optBoolean("pinned"))"置顶 · " else "")+entry.optString("title"),Modifier.weight(1f),maxLines=1,overflow=TextOverflow.Ellipsis,style=MaterialTheme.typography.bodyMedium)
                if(ordered.size>1)Text("${index%ordered.size+1}/${ordered.size}",style=MaterialTheme.typography.labelSmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
    LaunchedEffect(selected){content="";selected?.let{entry->val id=entry.optString("id");if(!DeliveryRules.safeID(id))return@LaunchedEffect;try{content=social.request("/api/announcements/$id",false).field("content","description")}catch(e:CancellationException){throw e}catch(_:Exception){content="公告读取失败，请在公告列表重试。"}}}
    selected?.let{entry->AlertDialog(onDismissRequest={selected=null},title={Text(entry.optString("title"))},text={Column(Modifier.verticalScroll(rememberScrollState())){if(content.isEmpty())CircularProgressIndicator() else MarkdownText(content)}},confirmButton={TextButton(onClick={selected=null}){Text("完成")}})}
}
