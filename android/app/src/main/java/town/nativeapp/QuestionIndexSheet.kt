package town.nativeapp

import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import kotlinx.coroutines.launch

@Composable fun UserMessageBody(message:Message) {
    val body = MessagePresentation.body(message)
    if(body.isNotBlank())MarkdownText(body,textColor=Color.White)
}

val LocalMessageContextMenu = staticCompositionLocalOf { false }

@Composable fun MessageActions(text:String,onQuote:(String)->Unit,content:@Composable ()->Unit) {
    var expanded by remember { mutableStateOf(false) }
    val clipboard=LocalClipboard.current
    val scope=rememberCoroutineScope()
    val context=LocalContext.current
    val focus=LocalFocusManager.current
    Box(Modifier.combinedClickable(onClick={focus.clearFocus()},onLongClickLabel="消息操作",onLongClick={expanded=true})) {
        CompositionLocalProvider(LocalMessageContextMenu provides true,content=content)
        DropdownMenu(expanded,onDismissRequest={expanded=false}) {
            DropdownMenuItem(text={Text("复制")},enabled=text.isNotBlank(),leadingIcon={Icon(Icons.Outlined.ContentCopy,null)},onClick={
                expanded=false
                scope.launch { clipboard.setClipEntry(ClipEntry(android.content.ClipData.newPlainText("消息正文",text))) }
            })
            DropdownMenuItem(text={Text("引用到草稿")},enabled=text.isNotBlank(),leadingIcon={Icon(AppIcons.Quote,null)},onClick={
                expanded=false;onQuote(text.lines().joinToString("\n") { "> $it" })
            })
            DropdownMenuItem(text={Text("分享")},enabled=text.isNotBlank(),leadingIcon={Icon(Icons.Outlined.Share,null)},onClick={
                expanded=false
                context.startActivity(android.content.Intent.createChooser(android.content.Intent(android.content.Intent.ACTION_SEND).apply{type="text/plain";putExtra(android.content.Intent.EXTRA_TEXT,text)},"分享消息"))
            })
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun QuestionIndexSheet(messages:List<Message>,onDismiss:()->Unit,onSelect:(Int)->Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    val entries=remember(messages,query){MessagePresentation.questions(messages,query).reversed()}
    val total=remember(messages){messages.count{it.role=="user"&&it.kind!="marker"}}
    ModalBottomSheet(onDismissRequest=onDismiss,sheetState=rememberModalBottomSheetState(skipPartiallyExpanded=true),
        containerColor=MaterialTheme.colorScheme.background) {
        Column(Modifier.fillMaxWidth().fillMaxHeight(.78f).imePadding().padding(horizontal=20.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
            Row(verticalAlignment=Alignment.CenterVertically) {
                Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(4.dp)) {
                    Text("提问索引",style=MaterialTheme.typography.titleLarge,fontWeight=FontWeight.SemiBold)
                    Text("$total 条提问",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
                }
                ActionIcon(Icons.Outlined.Close,"关闭提问索引",onClick=onDismiss)
            }
            OutlinedTextField(query,{query=it},Modifier.fillMaxWidth(),placeholder={Text("搜索提问")},singleLine=true,
                leadingIcon={Icon(Icons.Outlined.Search,null)},trailingIcon={if(query.isNotEmpty())ActionIcon(Icons.Outlined.Close,"清除搜索"){query=""}},shape=RoundedCornerShape(16.dp))
            if(entries.isEmpty())Box(Modifier.fillMaxWidth().weight(1f),contentAlignment=Alignment.Center) {
                Text(if(query.isBlank())"还没有提问" else "没有匹配的提问",color=MaterialTheme.colorScheme.onSurfaceVariant)
            } else LazyColumn(Modifier.weight(1f),contentPadding=PaddingValues(bottom=24.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                items(entries,key={it.messageIndex}) { entry ->
                    Surface(shape=RoundedCornerShape(16.dp),color=MaterialTheme.colorScheme.surfaceContainerLow) {
                        Row(Modifier.fillMaxWidth().clickable { onSelect(entry.messageIndex) }.padding(16.dp),horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                            Text(entry.number.toString().padStart(2,'0'),style=MaterialTheme.typography.labelLarge,color=MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(entry.text,Modifier.weight(1f),style=MaterialTheme.typography.bodyMedium,maxLines=3,overflow=TextOverflow.Ellipsis)
                            Icon(AppIcons.Chevron,null,Modifier.size(18.dp),tint=MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }
    }
}
