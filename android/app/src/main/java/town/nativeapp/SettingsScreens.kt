package town.nativeapp

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Chat
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.*
import org.json.JSONObject
import java.net.URLEncoder
import androidx.compose.ui.platform.LocalContext

@Composable fun MoreScreen(m: TownModel,social: SocialModel,nav: NavigationModel) {
    LazyColumn(contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
        item { Text("Being",fontSize=32.sp,fontWeight=FontWeight.Bold);Text(social.identity?.name?.ifEmpty{social.identity?.id ?: ""} ?: "Being",color=MaterialTheme.colorScheme.onSurfaceVariant);Spacer(Modifier.height(16.dp)) }
        items(destinations.filter{it.id!="chat"}) { d -> ListItem(headlineContent={Text(d.title)},leadingContent={Icon(destinationIcon(d.id),null)},modifier=Modifier.clickable{nav.screen=d.id}) }
        item { HorizontalDivider();Text("设置",Modifier.padding(vertical=16.dp),fontWeight=FontWeight.Bold) }
        items(listOf("connection" to "连接 Being","pair" to "连接 Being Town","models" to "模型设置","navigation" to "自定义底部导航")) { (id,title) -> ListItem(headlineContent={Text(title)},modifier=Modifier.clickable{nav.screen=id}) }
        item { ListItem(headlineContent={Text("对话设置")},leadingContent={Icon(Icons.Outlined.Chat,null)},modifier=Modifier.clickable{nav.screen="conversation-settings"}) }
        item { ListItem(headlineContent={Text("通知设置")},leadingContent={Icon(Icons.Outlined.Notifications,null)},modifier=Modifier.clickable{nav.screen="notification-settings"}) }
        item { AppUpdateSetting() }
        item { SocialNotificationSettings() }
        item { Text("外观");Row(horizontalArrangement=Arrangement.spacedBy(8.dp)){listOf("system" to "系统","light" to "浅色","dark" to "深色").forEach{(id,title)->FilterChip(selected=nav.appearance==id,onClick={nav.appearance(id)},label={Text(title)})}} }
        item { Text(social.status,fontSize=12.sp,color=MaterialTheme.colorScheme.primary) }
    }
}

@Composable fun ConversationSettingsScreen(m:TownModel){
    LazyColumn(contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(14.dp)){
        item { Text("SBS",fontWeight=FontWeight.SemiBold); if(m.connection!=null) SBSControl(m) else Text("连接 Being 后可配置 SBS",color=MaterialTheme.colorScheme.onSurfaceVariant) }
        item { HorizontalDivider(); ReadingSizeSetting() }
    }
}

@Composable fun NotificationSettingsScreen(){
    LazyColumn(contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(14.dp)){
        item { Text("对话",fontWeight=FontWeight.SemiBold); CompletionNotificationSetting() }
        item { HorizontalDivider(); SocialNotificationSettings() }
    }
}

@Composable private fun SocialNotificationSettings() {
    val context = LocalContext.current; val prefs = remember { context.getSharedPreferences("settings",0) }
    var master by remember { mutableStateOf(prefs.getBoolean("notify.social.enabled",false)) }
    Column(verticalArrangement=Arrangement.spacedBy(2.dp)) {
        Text("小镇通知",fontWeight=FontWeight.SemiBold)
        NotificationSwitch("小镇通知总开关",master,true){ master=it; prefs.edit().putBoolean("notify.social.enabled",it).apply() }
        listOf("mail" to "私信","firesides" to "围炉","bonfire" to "篝火").forEach { (key,title) -> var enabled by remember { mutableStateOf(prefs.getBoolean("notify.social.$key",false)) }; NotificationSwitch(title,enabled,master){ enabled=it; prefs.edit().putBoolean("notify.social.$key",it).apply() } }
        Text("配对 Town 后接收新消息提醒；通知不展示消息正文。",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
@Composable private fun NotificationSwitch(title:String, checked:Boolean, enabled:Boolean, onChange:(Boolean)->Unit) { Row(Modifier.fillMaxWidth(),verticalAlignment=androidx.compose.ui.Alignment.CenterVertically){Text(title,Modifier.weight(1f));Switch(checked,onChange,enabled=enabled)} }

@Composable private fun AppUpdateSetting() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var state by remember { mutableStateOf("正在读取当前版本…") }
    var release by remember { mutableStateOf<AppRelease?>(null) }
    var working by remember { mutableStateOf(false) }
    fun check() = scope.launch {
        working = true
        state = "正在检查更新…"
        try {
            val found = AppUpdates.latest()
            release = found
            state = if (AppUpdates.isNewer(found.version, BuildConfig.VERSION_NAME)) "发现新版本 ${found.version}" else "当前已是最新版本（${BuildConfig.VERSION_NAME}）"
        } catch (e: Exception) { state = e.message ?: "暂时无法检查更新" }
        finally { working = false }
    }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("应用更新", fontWeight = FontWeight.SemiBold)
        Text(state, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            TextButton(onClick = { check() }, enabled = !working) { Text("检查更新") }
            if (release?.let { AppUpdates.isNewer(it.version, BuildConfig.VERSION_NAME) } == true) {
                Button(onClick = { release?.let { item -> scope.launch { working = true; state = "正在下载升级包…"; try { AppUpdates.downloadAndInstall(context, item); state = "请在系统安装界面确认升级" } catch (e: Exception) { state = e.message ?: "升级失败" } finally { working = false } } } }, enabled = !working && release?.assetUrl != null) { Text("下载并升级") }
            }
        }
    }
    LaunchedEffect(Unit) { check() }
}
@Composable fun NavigationSettings(nav: NavigationModel) {
    LazyColumn(contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
        item { Text("底部入口",fontSize=24.sp) }
        items(nav.tabs,key={it}) { id -> val index=nav.tabs.indexOf(id)
            Column { Text(destinations.find{it.id==id}!!.title,fontWeight=FontWeight.Bold)
                Row { TextButton(onClick={val a=nav.tabs.toMutableList();a[index]=a[index-1];a[index-1]=id;nav.tabs(a)},enabled=index>0){Text("前移")};TextButton(onClick={val a=nav.tabs.toMutableList();a[index]=a[index+1];a[index+1]=id;nav.tabs(a)},enabled=index<nav.tabs.lastIndex){Text("后移")};if(id!="chat")TextButton(onClick={nav.tabs(nav.tabs-id)}){Text("移除")} }
            }
        }
        item { HorizontalDivider();Text("添加入口",Modifier.padding(top=16.dp)) }
        items(destinations.filter{it.id !in nav.tabs}) { d -> TextButton(onClick={nav.tabs(nav.tabs+d.id)},enabled=nav.tabs.size<4){Text("＋ ${d.title}")} }
        item { TextButton(onClick={nav.tabs(listOf("chat","firesides","mail","bonfire"))}){Text("恢复默认") } }
    }
}
@Composable fun PairingScreen(m: TownModel,social: SocialModel) {
    var name by rememberSaveable { mutableStateOf(m.connection?.being ?: "") }
    var code by rememberSaveable { mutableStateOf("") }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var job by remember { mutableStateOf<Job?>(null) }
    val scope=rememberCoroutineScope()
    DisposableEffect(Unit){onDispose{job?.cancel();m.cancelPairing()}}
    fun pair(auto:Boolean){working=true;error=null;job=scope.launch{try{withTimeout(90000){val being=if(auto)m.connection?.being ?: "" else name;val actual=if(auto)m.pairingCode() else code;social.pair(being,actual);code=""}}catch(e:TimeoutCancellationException){m.cancelPairing();error="90 秒内未完成自动配对，请使用手动配对。"}catch(e:CancellationException){throw e}catch(e:Exception){error=if(e is IllegalStateException && e.message?.contains("配对")==true)e.message else if(auto)"无法读取 Being 配对回复，请使用手动配对。" else "配对请求未完成，请检查网络；若配对码已失效，请获取新码。"}finally{working=false}}}
    LazyColumn(contentPadding=PaddingValues(24.dp),verticalArrangement=Arrangement.spacedBy(18.dp)) {
        item { Text(social.status,fontWeight=FontWeight.Bold);social.identity?.let{Text(it.name.ifEmpty{it.id});Text(it.id,fontSize=12.sp);TextButton(onClick={social.unpair()},enabled=!working){Text("断开本机配对")}} }
        item { AdvancedPairing(social) }
        item { Text("自动配对",fontSize=23.sp); }
        item { Button(onClick={pair(true)},enabled=!working&&!m.busy&&m.connection!=null,modifier=Modifier.fillMaxWidth()){Text(if(working)"正在连接…" else "自动连接 Town")};if(working)TextButton(onClick={m.cancelPairing();job?.cancel()}){Text("取消自动配对")} }
        item { HorizontalDivider();Text("手动配对",Modifier.padding(top=20.dp),fontSize=20.sp) }
        item { OutlinedTextField(name,{name=it},label={Text("Town ID 或 Being 名")},modifier=Modifier.fillMaxWidth(),singleLine=true) }
        item { OutlinedTextField(code,{code=it.uppercase()},label={Text("配对码")},modifier=Modifier.fillMaxWidth(),singleLine=true) }
        item { Button(onClick={pair(false)},enabled=!working&&name.isNotBlank()&&code.length==6){Text("确认配对")} }
        error?.let{item{Text(it,color=MaterialTheme.colorScheme.error)}}
    }
}
@Composable fun ModelsScreen(m: TownModel) {
    var provider by rememberSaveable { mutableStateOf("") };var model by rememberSaveable{mutableStateOf("")};var thinking by rememberSaveable{mutableStateOf("medium")}
    var key by remember{mutableStateOf("")};var routes by remember{mutableStateOf<List<JSONObject>>(emptyList())};var models by remember{mutableStateOf<List<JSONObject>>(emptyList())}
    var working by remember{mutableStateOf(false)};var info by remember{mutableStateOf<String?>(null)};var menu by remember{mutableStateOf("")}
    val scope=rememberCoroutineScope()
    suspend fun load(){working=true;try{val config=m.modelRequest("/api/llm/config");provider=config.optString("provider");model=config.optString("model");thinking=config.optString("thinking","medium");routes=runCatching{m.modelRequest("/api/llm/routes").rows("routes")}.getOrDefault(emptyList());info=null}catch(_:Exception){info="无法读取配置，请检查连接和 relay secret。"}finally{working=false}}
    LaunchedEffect(m.connection){if(m.connection!=null)load()}
    LaunchedEffect(provider){models=emptyList();if(provider.isNotBlank())models=runCatching{m.modelRequest("/api/llm/models?route=${URLEncoder.encode(provider,"UTF-8")}").rows("models")}.getOrDefault(emptyList())}
    if(m.connection==null){Text("请先连接 Being 对话。",Modifier.padding(24.dp));return}
    LazyColumn(contentPadding=PaddingValues(24.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
        item{Text("模型设置",fontSize=24.sp);Text("选择当前 Being 使用的模型",fontSize=14.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)}
        item{OutlinedTextField(provider,{provider=it},Modifier.fillMaxWidth(),label={Text("线路 / 服务商")},singleLine=true);if(routes.isNotEmpty())TextButton(onClick={menu="routes"}){Text("从线路目录选择")}}
        item{OutlinedTextField(model,{model=it},Modifier.fillMaxWidth(),label={Text("模型 ID")},singleLine=true);if(models.isNotEmpty())TextButton(onClick={menu="models"}){Text("从模型目录选择")}}
        item{TextButton(onClick={menu="thinking"}){Text("思考深度 · $thinking")}}
        item{OutlinedTextField(key,{key=it},Modifier.fillMaxWidth(),label={Text("输入 API 密钥")},visualTransformation=PasswordVisualTransformation(),singleLine=true)}
        item{Button(onClick={scope.launch{working=true;info=null;try{val patch=JSONObject().put("provider",provider).put("model",model.trim()).put("thinking",thinking);if(key.isNotBlank())patch.put("api_key",key);val result=m.modelRequest("/api/llm/config","PATCH",patch);when{result.optBoolean("needs_key")->info="当前线路需要有效 API Key。";!result.optBoolean("ok")||result.optBoolean("rolled_back")->info="配置未生效，服务端保留了原配置。";else->{key="";load();info="已保存，后续回复将使用新的配置。"}}}catch(_:Exception){info="保存未确认，请重新读取配置后核对。"}finally{working=false}}},enabled=!working&&!m.busy&&provider.isNotBlank()&&model.isNotBlank(),modifier=Modifier.fillMaxWidth()){Text(if(working)"处理中…" else "保存配置")}}
        item{TextButton(onClick={scope.launch{load()}},enabled=!working){Text("重新读取")};info?.let{Text(it,fontSize=14.sp)}}
    }
    if(menu.isNotEmpty())AlertDialog(onDismissRequest={menu=""},title={Text("选择")},text={LazyColumn{if(menu=="thinking")items(listOf("off","low","medium","high")){value->TextButton(onClick={thinking=value;menu=""}){Text(mapOf("off" to "关闭","low" to "低","medium" to "中","high" to "高")[value] ?: value)}}else items(if(menu=="routes")routes else models){r->TextButton(onClick={if(menu=="routes")provider=r.optString("id") else model=r.optString("id");menu=""}){Text(r.field("name","id"))}}}},confirmButton={TextButton(onClick={menu=""}){Text("关闭")}})
}
