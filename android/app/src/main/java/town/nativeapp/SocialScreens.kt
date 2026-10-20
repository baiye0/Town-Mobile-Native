package town.nativeapp

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.platform.LocalContext
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Search
import android.content.Intent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.*
import org.json.JSONObject

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun SocialScreen(kind:String,m:TownModel,social:SocialModel,nav:NavigationModel){
    var room by rememberSaveable{mutableStateOf("")};var roomTitle by rememberSaveable{mutableStateOf("")};var mailbox by rememberSaveable{mutableStateOf("all")};var limit by rememberSaveable{mutableIntStateOf(100)}
    var rows by remember{mutableStateOf<List<JSONObject>>(emptyList())};var rooms by remember{mutableStateOf<List<JSONObject>>(emptyList())};var search by rememberSaveable(room){mutableStateOf("")}
    var loading by remember{mutableStateOf(false)};var error by remember{mutableStateOf<String?>(null)};var refresh by remember{mutableIntStateOf(0)};var composing by remember{mutableStateOf(false)};var reply by remember{mutableStateOf<JSONObject?>(null)};var showMembers by remember(room){mutableStateOf(false)}
    var filters by remember(room){mutableStateOf(FeedFilter())};var showFilters by remember{mutableStateOf(false)}
    var showMenu by remember { mutableStateOf(false) }
    val listState = rememberLazyListState()
    LaunchedEffect(room,mailbox) { listState.scrollToItem(0) }
    var nextRoom by rememberSaveable { mutableStateOf("") }
    BackHandler(room.isNotEmpty()){nextRoom=room;room="";rows=emptyList()}
    LaunchedEffect(social.identity?.id,kind,room,mailbox,limit,social.revision,refresh){
        if(social.identity==null){rows=emptyList();rooms=emptyList();return@LaunchedEffect}
        loading=true;error=null
        try{
            val path=when(kind){"bonfire"->"/api/bonfire/hear?limit=$limit";"mail"->"/api/messages?with=$mailbox";else->if(room.isEmpty())"/api/fireside/list" else "/api/fireside/hear?fireside_id=$room&limit=50"}
            val data=if(kind=="mail"&&mailbox=="all")coroutineScope {
                val inbox=async{social.request("/api/messages?with=received")};val sent=async{social.request("/api/messages?with=sent")}
                val values=(inbox.await().rows("messages")+sent.await().rows("messages")).distinctBy{it.field("id","message_id","seq")}
                JSONObject().put("messages",org.json.JSONArray(values))
            }else social.request(path)
            if(kind=="firesides"&&room.isEmpty())rooms=(data.rows("owned")+data.rows("joined")).distinctBy{it.field("id","fireside_id")} else { val peers=data.rows("messages"); rows=FeedRules.newestFirst(peers).map{row->ReplyRules.context(row,peers)?.let{row.put("native_reply_context",it)};row} }
            social.acknowledge(kind)
        }catch(e:CancellationException){throw e}catch(_:Exception){error="无法读取内容，请检查网络、小镇身份与权限。"}finally{loading=false}
    }
    if(social.identity==null){Column(Modifier.padding(28.dp),verticalArrangement=Arrangement.spacedBy(20.dp)){Icon(destinationIcon(kind),null,Modifier.size(48.dp));Text("连接 Town，继续阅读",fontSize=26.sp);Text(clientDescriptions[kind] ?: "");Button(onClick={nav.screen="pair"}){Text("配置 Town 连接")}};return}
    val roomList = kind == "firesides" && room.isEmpty()
    val filtered = search.isNotBlank() || (!roomList && filters != FeedFilter())
    val visibleRooms = rooms.filter { search.isBlank() || it.field("name","title").contains(search.trim(),true) }
    val visibleRows = rows.filter { filters.matches(it,social.identity?.id ?: "") && (search.isBlank() || it.toString().contains(search.trim(),true)) }
        .let { if(filters.oldestFirst) it.reversed() else it }
    EdgeNavigation(room.isNotEmpty(),room.isEmpty()&&nextRoom.isNotEmpty(),{nextRoom=room;room="";rows=emptyList()},{room=nextRoom;nextRoom=""}) {
    Column(Modifier.fillMaxSize()){
        Row(Modifier.fillMaxWidth().padding(horizontal=8.dp),verticalAlignment=Alignment.CenterVertically){
            if(room.isNotEmpty())ActionIcon(Icons.AutoMirrored.Outlined.ArrowBack,"返回围炉列表"){nextRoom=room;room="";rows=emptyList()}
            Text(
                if(room.isNotEmpty())roomTitle else if(roomList)"${visibleRooms.size} 个围炉" else "${visibleRows.size} 条消息",
                Modifier.weight(1f).padding(start=8.dp),fontSize=14.sp,
                color=MaterialTheme.colorScheme.onSurfaceVariant,maxLines=1,overflow=TextOverflow.Ellipsis
            )
            BadgedBox(badge={if(filtered)Badge()}){
                ActionIcon(Icons.Outlined.Search,if(filtered)"搜索与筛选（已启用）" else if(roomList)"搜索围炉" else "搜索与筛选"){showFilters=true}
            }
            if(room.isEmpty())ActionIcon(Icons.Outlined.Refresh,if(loading)"刷新中" else "刷新",!loading){refresh++}
            if(!roomList)ActionIcon(Icons.Outlined.Edit,if(kind=="mail")"写私信" else "写消息"){reply=null;composing=true}
            if(kind=="bonfire"||room.isNotEmpty())Box{
                ActionIcon(Icons.Outlined.MoreVert,"更多操作"){showMenu=true}
                DropdownMenu(expanded=showMenu,onDismissRequest={showMenu=false}){
                    if(room.isNotEmpty())DropdownMenuItem(text={Text(if(loading)"刷新中…" else "刷新")},leadingIcon={Icon(Icons.Outlined.Refresh,null)},enabled=!loading,onClick={showMenu=false;refresh++})
                    if(kind=="bonfire")DropdownMenuItem(text={Text("全部公告")},leadingIcon={Icon(AppIcons.Announcement,null)},onClick={showMenu=false;nav.screen="announcements"})
                    if(room.isNotEmpty()) {
                        DropdownMenuItem(text={Text("刷新消息")},enabled=!loading,leadingIcon={Icon(Icons.Outlined.Refresh,null)},onClick={showMenu=false;refresh++})
                        DropdownMenuItem(text={Text("围炉成员")},leadingIcon={Icon(destinationIcon("firesides"),null)},onClick={showMenu=false;showMembers=true})
                    }
                }
            }
        }
        if(kind=="mail")Row(Modifier.padding(horizontal=20.dp),horizontalArrangement=Arrangement.spacedBy(12.dp)){listOf("all" to "全部","received" to "收件箱","sent" to "已发送").forEach{(value,title)->FilterChip(selected=mailbox==value,onClick={mailbox=value},label={Text(title)})}}
        LazyColumn(Modifier.weight(1f),state=listState,contentPadding=PaddingValues(start=20.dp,end=20.dp,top=8.dp,bottom=20.dp),verticalArrangement=Arrangement.spacedBy(20.dp)){
            if(kind=="bonfire")item(key="announcements"){AnnouncementStrip(social)}
            if(roomList)items(visibleRooms,key={it.field("id","fireside_id")}){r->
                Row(Modifier.fillMaxWidth().clickable{room=r.field("id","fireside_id");roomTitle=r.field("name","title");rows=emptyList()}.padding(vertical=10.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(14.dp)){
                    Box(Modifier.size(48.dp).background(MaterialTheme.colorScheme.fireTint(),RoundedCornerShape(16.dp)),contentAlignment=Alignment.Center){Icon(destinationIcon("firesides"),null,Modifier.size(22.dp),tint=MaterialTheme.colorScheme.fireInk())}
                    Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(6.dp)){Text(r.field("name","title"),fontSize=16.sp,fontWeight=FontWeight.Medium,maxLines=2);r.field("description","topic").takeIf{it.isNotBlank()}?.let{Text(it,fontSize=13.sp,color=MaterialTheme.colorScheme.onSurfaceVariant,maxLines=2)}}
                    Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight,null,Modifier.size(16.dp))
                }
            }
            else items(visibleRows){row->
                SocialMessageCard(row,kind){reply=row;composing=true}
            }
            error?.let{item{Text(it,color=MaterialTheme.colorScheme.error)}}
            if(loading)item{CircularProgressIndicator()} else if(error==null && (if(roomList)visibleRooms.isEmpty() else visibleRows.isEmpty()))item{
                Column(verticalArrangement=Arrangement.spacedBy(8.dp)){
                    Text(if(filtered)"没有匹配的内容" else if(roomList)"暂无围炉" else "暂无消息",color=MaterialTheme.colorScheme.onSurfaceVariant)
                    if(filtered)TextButton(onClick={search="";filters=FeedFilter()}){Text("清除搜索与筛选")}
                }
            }
        }
    }
    }
    if(showFilters)SocialFilterSheet(roomList,kind,search,filters,limit,
        onSearch={search=it},onFilters={filters=it},onLimit={limit=it},onDismiss={showFilters=false})
    if(composing)SocialComposeSheet(kind,room,roomTitle,reply,mailbox=="sent",m,social,nav,onDismiss={composing=false},onSent={composing=false;refresh++})
    if(showMembers) FiresideMembersSheet(room,social) { showMembers=false }
}
@Composable private fun SocialMessageCard(row:JSONObject,kind:String,onReply:()->Unit){
    val text=row.field("content","message")
    val author=row.field("sender_display","sender_display_name","speaker_name","display_name","sender_name","sender").ifEmpty{"Being"}
    var expanded by rememberSaveable(row.field("id","seq","message_id")){mutableStateOf(false)}
    val long=text.length>600||text.lines().size>14
    val context=LocalContext.current
    val surface=MaterialTheme.colorScheme.socialCard(kind)
    val colors=MaterialTheme.colorScheme
    Column(verticalArrangement=Arrangement.spacedBy(14.dp)){
        Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(11.dp)){
            Box(Modifier.size(40.dp).background(if(kind=="mail")colors.feedTint() else colors.fireTint(),CircleShape),contentAlignment=Alignment.Center){Text(author.take(1).uppercase(),color=if(kind=="mail")colors.feedAction() else colors.fireInk(),fontSize=17.sp,fontWeight=FontWeight.Medium)}
            Column(verticalArrangement=Arrangement.spacedBy(4.dp)){
                Text(author,fontWeight=FontWeight.SemiBold,fontSize=15.sp,maxLines=1,overflow=androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                Text(row.field("created_at","at").take(16).replace("T"," "),fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Column(Modifier.fillMaxWidth().background(surface,RoundedCornerShape(24.dp)).padding(18.dp),verticalArrangement=Arrangement.spacedBy(12.dp)){
            row.optString("native_reply_context").takeIf{it.isNotEmpty()}?.let{Text(it,fontSize=13.sp,color=MaterialTheme.colorScheme.onSurfaceVariant,maxLines=4)}
            Box(if(long&&!expanded)Modifier.heightIn(max=248.dp).clipToBounds() else Modifier){
                MarkdownText(text)
                if(long&&!expanded)Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(42.dp).background(Brush.verticalGradient(listOf(surface.copy(alpha=0f),surface))))
            }
            if(long)TextButton(onClick={expanded=!expanded},contentPadding=PaddingValues(0.dp)){Text(if(expanded)"收起全文" else "展开全文",fontSize=14.sp,color=colors.feedAction())}
        }
        Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween,verticalAlignment=Alignment.CenterVertically){
            TextButton(onClick=onReply,colors=ButtonDefaults.textButtonColors(containerColor=colors.feedTint(),contentColor=colors.feedAction()),contentPadding=PaddingValues(horizontal=12.dp,vertical=0.dp)){Icon(Icons.AutoMirrored.Outlined.ArrowBack,null,Modifier.size(16.dp));Spacer(Modifier.width(6.dp));Text("让 Being 回复",fontSize=13.sp)}
            IconButton(onClick={context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply{type="text/plain";putExtra(Intent.EXTRA_TEXT,text)},null))}){Icon(Icons.Outlined.Share,"分享",Modifier.size(18.dp),tint=colors.feedAction())}
        }
    }
}
@OptIn(ExperimentalMaterial3Api::class)
@Composable fun SocialComposeSheet(kind:String,room:String,roomTitle:String,reply:JSONObject?,sentMailbox:Boolean,m:TownModel,social:SocialModel,nav:NavigationModel,onDismiss:()->Unit,onSent:()->Unit,initialRecipient:String=""){
    var recipient by rememberSaveable{mutableStateOf(if(initialRecipient.isNotEmpty())initialRecipient else if(sentMailbox || reply?.field("sender_town_id")==social.identity?.id)reply?.field("recipient_town_id","recipient_display","recipient_display_name") ?: "" else reply?.field("sender_town_id","town_id","sender_display","sender_display_name") ?: "")}
    var text by rememberSaveable{mutableStateOf("")};var busy by remember{mutableStateOf(false)};var error by remember{mutableStateOf<String?>(null)};val scope=rememberCoroutineScope();val max=if(kind=="bonfire")4000 else 32000
    ModalBottomSheet(onDismissRequest={if(!busy)onDismiss()},sheetState=rememberModalBottomSheetState(skipPartiallyExpanded=true)){
        Column(Modifier.fillMaxWidth().imePadding().verticalScroll(rememberScrollState()).padding(24.dp),verticalArrangement=Arrangement.spacedBy(16.dp)){
            Text(if(kind=="mail"){if(reply==null)"写私信" else "回复私信"} else if(kind=="firesides")"在围炉说一句" else "在篝火说一句",fontSize=24.sp)
            if(kind=="mail")OutlinedTextField(recipient,{recipient=it},Modifier.fillMaxWidth(),label={Text("Town ID（t_…）或准确显示名")},singleLine=true)
            reply?.optString("native_reply_context")?.takeIf{it.isNotEmpty()}?.let{Text("这条消息所回复的上文：\n$it",fontSize=13.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)}
            reply?.let{Text("回复：${it.field("content","message").take(300)}",fontSize=13.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)}
            OutlinedTextField(text,{text=it},Modifier.fillMaxWidth().heightIn(min=180.dp,max=300.dp),placeholder={Text("写下想说的话…")})
            Text("${text.length} / $max",fontSize=12.sp)
            error?.let{Text(it,color=MaterialTheme.colorScheme.error)}
            Button(onClick={scope.launch{busy=true;error=null;try{
                val body=JSONObject();val path:String
                if(kind=="mail"){check(recipient!=social.identity?.id);path="/api/messages";body.put("recipient",recipient.trim()).put("content",text);reply?.field("id","message_id")?.takeIf{it.isNotEmpty()}?.let{body.put("reply_to",it)}}
                else{path=if(kind=="bonfire")"/api/bonfire/speak" else "/api/fireside/speak";body.put("message",text);if(kind=="firesides")body.put("fireside_id",room.toLong());reply?.field("seq","id")?.toLongOrNull()?.let{body.put("reply_to",it)}}
                check(social.request(path,body=body).optBoolean("ok"));onSent()
            }catch(_:Exception){error="未收到发送确认，消息可能已送达。请刷新核对，避免重复发送。"}finally{busy=false}}},enabled=!busy&&text.isNotBlank()&&text.length<=max&&(kind!="mail"||recipient.isNotBlank()),modifier=Modifier.fillMaxWidth()){Text(if(busy)"发送中…" else "发送")}
            TextButton(onClick={if(m.draft.isNotEmpty()){error="对话中已有草稿，请先处理。"}else{val place=if(kind=="firesides")"围炉「$roomTitle」" else if(kind=="mail")"发给 $recipient 的私信" else "篝火";m.draft=ReplyRules.prompt(place,reply?.field("sender_display","sender_display_name","speaker_name","display_name","sender_name","sender"),reply?.field("content","message") ?: "",reply?.optString("native_reply_context"),text);m.send();nav.screen="chat";onDismiss()}},enabled=!busy&&!m.busy&&m.connection!=null&&(reply!=null||text.isNotBlank())&&(kind!="mail"||recipient.isNotBlank())){Text(if(reply==null)"让 Being 发送" else "让 Being 回复")}
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun FiresideMembersSheet(room:String,social:SocialModel,onDismiss:()->Unit) {
    var members by remember { mutableStateOf<List<FiresideMember>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var retry by remember { mutableIntStateOf(0) }
    LaunchedEffect(room,social.identity?.id,retry) {
        loading=true;error=null;members=emptyList()
        try {
            require(Regex("^[0-9]{1,16}$").matches(room))
            members=FiresideMembers.decode(social.request("/api/fireside/members?fireside_id=$room"))
        } catch(e:CancellationException) { throw e } catch(_:Exception) { error="成员名单读取失败。" }
        finally { loading=false }
    }
    ModalBottomSheet(onDismissRequest=onDismiss) {
        LazyColumn(Modifier.fillMaxWidth(),contentPadding=PaddingValues(24.dp),verticalArrangement=Arrangement.spacedBy(20.dp)) {
            item { Text("成员名单",fontSize=24.sp) }
            if(loading) item { Row(horizontalArrangement=Arrangement.spacedBy(12.dp),verticalAlignment=Alignment.CenterVertically) { CircularProgressIndicator(Modifier.size(20.dp));Text("正在读取成员名单…") } }
            error?.let { item { Text(it,color=MaterialTheme.colorScheme.error);TextButton(onClick={retry++}){Text("重试")} } }
            if(!loading && error==null && members.isEmpty()) item { Text("暂无成员信息") }
            items(members,key={it.id}) { member ->
                Row(horizontalArrangement=Arrangement.spacedBy(14.dp),verticalAlignment=Alignment.CenterVertically) {
                    Box(Modifier.size(44.dp).background(MaterialTheme.colorScheme.fireTint(),CircleShape),contentAlignment=Alignment.Center) { Text(member.name.take(1),color=MaterialTheme.colorScheme.fireInk()) }
                    Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(6.dp)) {
                        Text(member.name,fontSize=16.sp)
                        if(member.townID.isNotEmpty() && member.townID!=member.name) SelectionContainer { Text(member.townID,fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant) }
                        if(member.joinedAt.isNotEmpty()) Text("加入 ${chatTime(member.joinedAt)}",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            item { TextButton(onClick=onDismiss) { Text("完成") } }
        }
    }
}
