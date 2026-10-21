package town.nativeapp

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
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
import androidx.compose.ui.Alignment

@Composable fun MoreScreen(m: TownModel,social: SocialModel,nav: NavigationModel) {
    LazyColumn(contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(10.dp)) {
        item { SettingsCard { SettingsRow(m.connection?.being ?: "连接你的 Being", Icons.Outlined.AutoAwesome,
            if(m.connection == null) "尚未连接" else "已连接 · ${android.net.Uri.parse(m.connection!!.endpoint).host}") { nav.screen="connection" } } }
        item { SettingsSectionLabel("设置") }
        item { SettingsCard {
            SettingsRow("对话设置", destinationIcon("chat"), "SBS · 阅读字号") { nav.screen="conversation-settings" }
            SettingsDivider()
            SettingsRow("模型设置", AppIcons.Model, "线路、模型与思考深度") { nav.screen="models" }
            SettingsDivider()
            SettingsRow("本机 Portal", Icons.Outlined.Computer, "工作区、工具能力与运行状态") { nav.screen="portal" }
            SettingsDivider()
            SettingsRow("通知设置", AppIcons.Bell) { nav.screen="notification-settings" }
            SettingsDivider()
            SettingsRow("外观", AppIcons.Palette, appearanceTitle(nav.appearance)) { nav.screen="appearance" }
            SettingsDivider()
            SettingsRow("底部导航", AppIcons.Tune, "调整入口与顺序") { nav.screen="navigation" }
        } }
        item { SettingsSectionLabel("Being Town") }
        item { SettingsCard { SettingsRow("小镇连接", Icons.Outlined.Link,
            social.identity?.let { it.name.ifBlank { it.id } } ?: "尚未配对") { nav.screen="pair" } } }
        items(destinations.filter{it.id!="chat"}.chunked(3)) { group ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement=Arrangement.spacedBy(10.dp)) {
                group.forEach { d ->
                    Surface(onClick={nav.screen=d.id},modifier=Modifier.weight(1f),shape=RoundedCornerShape(18.dp),color=MaterialTheme.colorScheme.surfaceContainerLow) {
                        Column(Modifier.padding(horizontal=6.dp,vertical=18.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(10.dp)) {
                            Icon(destinationIcon(d.id),null,Modifier.size(25.dp))
                            Text(d.title,style=MaterialTheme.typography.labelLarge)
                        }
                    }
                }
                repeat(3-group.size) { Spacer(Modifier.weight(1f)) }
            }
        }
        item { SettingsSectionLabel("应用") }
        item { SettingsCard { SettingsRow("应用更新", AppIcons.Update, "版本 ${BuildConfig.VERSION_NAME}") { nav.screen="updates" } } }
        item { Text("Being · ${BuildConfig.VERSION_NAME}",Modifier.fillMaxWidth().padding(vertical=12.dp),style=MaterialTheme.typography.bodySmall,
            color=MaterialTheme.colorScheme.onSurfaceVariant,textAlign=androidx.compose.ui.text.style.TextAlign.Center) }
    }
}

private fun appearanceTitle(value:String)=when(value){"light"->"浅色";"dark"->"深色";else->"跟随系统"}

@Composable fun AppearanceSettings(nav:NavigationModel) {
    LazyColumn(contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
        item { SettingsSectionLabel("主题") }
        item { SettingsCard {
            listOf("system" to AppIcons.System,"light" to AppIcons.Sun,"dark" to AppIcons.Moon).forEachIndexed { index,(id,icon) ->
                if(index>0)SettingsDivider()
                Row(Modifier.fillMaxWidth().clickable(role=androidx.compose.ui.semantics.Role.RadioButton){nav.appearance(id)}.padding(16.dp),
                    verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(14.dp)) {
                    SettingsIcon(icon);Text(appearanceTitle(id),Modifier.weight(1f));RadioButton(nav.appearance==id,{nav.appearance(id)})
                }
            }
        } }
    }
}

@Composable fun ConversationSettingsScreen(m:TownModel){
    LazyColumn(contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(14.dp)){
        item { SettingsCard { Column(Modifier.padding(18.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
            SettingsHeading("SBS",Icons.Outlined.AutoAwesome)
            if(m.connection!=null) SBSControl(m) else Text("连接 Being 后可配置 SBS",color=MaterialTheme.colorScheme.onSurfaceVariant)
        } } }
        item { SettingsCard { Column(Modifier.padding(18.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
            SettingsHeading("阅读",AppIcons.Type); ReadingSizeSetting()
        } } }
    }
}

@Composable fun NotificationSettingsScreen(){
    LazyColumn(contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(14.dp)){
        item { SettingsCard { Column(Modifier.padding(18.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
            SettingsHeading("对话通知",destinationIcon("chat")); CompletionNotificationSetting()
        } } }
        item { SettingsCard { Column(Modifier.padding(18.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) { SocialNotificationSettings() } } }
    }
}

@Composable private fun SocialNotificationSettings() {
    val context = LocalContext.current; val prefs = remember { context.getSharedPreferences("settings",0) }
    var master by remember { mutableStateOf(prefs.getBoolean("notify.social.enabled",false)) }
    Column(verticalArrangement=Arrangement.spacedBy(2.dp)) {
        SettingsHeading("小镇通知",AppIcons.Bell)
        NotificationSwitch("小镇通知总开关",master,true){ master=it; prefs.edit().putBoolean("notify.social.enabled",it).apply() }
        listOf("mail" to "私信","firesides" to "围炉","bonfire" to "篝火").forEach { (key,title) -> var enabled by remember { mutableStateOf(prefs.getBoolean("notify.social.$key",false)) }; SettingsToggle(title,enabled,master,icon=destinationIcon(key)){ enabled=it; prefs.edit().putBoolean("notify.social.$key",it).apply() } }
        Text("配对 Town 后接收新消息提醒；通知不展示消息正文。",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
@Composable private fun NotificationSwitch(title:String, checked:Boolean, enabled:Boolean, onChange:(Boolean)->Unit) {
    SettingsToggle(title,checked,enabled,onChange=onChange)
}

@Composable fun AppUpdateScreen() {
    LazyColumn(contentPadding=PaddingValues(20.dp)) { item { SettingsCard {
        Column(Modifier.padding(20.dp),verticalArrangement=Arrangement.spacedBy(18.dp)) {
            SettingsHeading("应用更新",AppIcons.Update,"当前版本 ${BuildConfig.VERSION_NAME}"); AppUpdateSetting()
        }
    } } }
}

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
        Text(state, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            TextButton(onClick = { check() }, enabled = !working) { Icon(Icons.Outlined.Refresh,null,Modifier.size(18.dp));Spacer(Modifier.width(8.dp));Text("检查更新") }
            if (release?.let { AppUpdates.isNewer(it.version, BuildConfig.VERSION_NAME) } == true) {
                Button(onClick = { release?.let { item -> scope.launch { working = true; state = "正在下载升级包…"; try { AppUpdates.downloadAndInstall(context, item); state = "请在系统安装界面确认升级" } catch (e: Exception) { state = e.message ?: "升级失败" } finally { working = false } } } }, enabled = !working && release?.assetUrl != null) { Text("下载并升级") }
            }
        }
    }
    LaunchedEffect(Unit) { check() }
}
@Composable fun NavigationSettings(nav: NavigationModel) {
    LazyColumn(contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(10.dp)) {
        item { SettingsSectionLabel("已显示 · ${nav.tabs.size}/4") }
        items(nav.tabs,key={it}) { id -> val index=nav.tabs.indexOf(id)
            SettingsCard { Row(Modifier.fillMaxWidth().padding(start=16.dp,end=6.dp,top=10.dp,bottom=10.dp),verticalAlignment=Alignment.CenterVertically) {
                Icon(destinationIcon(id),null,Modifier.size(24.dp));Spacer(Modifier.width(12.dp))
                Text(destinations.first{it.id==id}.title,Modifier.weight(1f),style=MaterialTheme.typography.bodyMedium)
                ActionIcon(Icons.Outlined.ArrowUpward,"前移",index>0){ val a=nav.tabs.toMutableList();java.util.Collections.swap(a,index,index-1);nav.tabs(a) }
                ActionIcon(Icons.Outlined.ArrowDownward,"后移",index<nav.tabs.lastIndex){ val a=nav.tabs.toMutableList();java.util.Collections.swap(a,index,index+1);nav.tabs(a) }
                ActionIcon(Icons.Outlined.Remove,"移除",id!="chat"){nav.tabs(nav.tabs-id)}
            } }
        }
        item { SettingsSectionLabel(if(nav.tabs.size<4)"添加入口" else "更多入口 · 移除一项后可添加") }
        item { SettingsCard { destinations.filter{it.id !in nav.tabs}.forEachIndexed { index,d ->
            if(index>0)SettingsDivider()
            Row(Modifier.fillMaxWidth().padding(start=16.dp,end=6.dp,top=6.dp,bottom=6.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(14.dp)) {
                Icon(destinationIcon(d.id),null,Modifier.size(24.dp));Text(d.title,Modifier.weight(1f))
                ActionIcon(Icons.Outlined.Add,"添加${d.title}",nav.tabs.size<4){nav.tabs(nav.tabs+d.id)}
            }
        } } }
        item { TextButton(onClick={nav.tabs(listOf("chat","firesides","mail","bonfire"))}){Icon(Icons.Outlined.Refresh,null,Modifier.size(18.dp));Spacer(Modifier.width(8.dp));Text("恢复默认") } }
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
    LazyColumn(modifier=Modifier.imePadding(),contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
        item { SettingsCard { Column(Modifier.padding(20.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
            SettingsHeading(social.identity?.let{it.name.ifEmpty{it.id}} ?: "尚未配对",destinationIcon("contacts"),social.status)
            social.identity?.let{Text(it.id,style=MaterialTheme.typography.bodySmall);TextButton(onClick={social.unpair()},enabled=!working){Icon(Icons.Outlined.LinkOff,null,Modifier.size(18.dp));Spacer(Modifier.width(8.dp));Text("断开本机配对")}}
        } } }
        item { SettingsCard { Column(Modifier.padding(20.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
            SettingsHeading("自动配对",Icons.Outlined.AutoAwesome)
            Button(onClick={pair(true)},enabled=!working&&!m.busy&&m.connection!=null,modifier=Modifier.fillMaxWidth().heightIn(min=48.dp)){Icon(Icons.Outlined.Link,null,Modifier.size(18.dp));Spacer(Modifier.width(8.dp));Text(if(working)"正在连接…" else "自动连接 Town")}
            if(m.connection==null)Text("先连接 Being，再使用自动配对。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
            if(working)TextButton(onClick={m.cancelPairing();job?.cancel()}){Text("取消自动配对")}
        } } }
        item { SettingsCard { Column(Modifier.padding(20.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
            SettingsHeading("手动配对",Icons.Outlined.Key)
            OutlinedTextField(name,{name=it},label={Text("Town ID 或 Being 名")},modifier=Modifier.fillMaxWidth(),singleLine=true,shape=RoundedCornerShape(14.dp))
            OutlinedTextField(code,{code=it.uppercase()},label={Text("配对码")},modifier=Modifier.fillMaxWidth(),singleLine=true,shape=RoundedCornerShape(14.dp))
            OutlinedButton(onClick={pair(false)},enabled=!working&&name.isNotBlank()&&code.length==6,modifier=Modifier.fillMaxWidth().heightIn(min=48.dp)){Text("确认配对")}
        } } }
        item { SettingsCard { Column(Modifier.padding(16.dp)){AdvancedPairing(social)} } }
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
    if(m.connection==null){Column(Modifier.padding(20.dp)){SettingsCard{Column(Modifier.padding(20.dp)){SettingsHeading("尚未连接",AppIcons.Model,"连接 Being 后可配置模型。")}}};return}
    LazyColumn(modifier=Modifier.imePadding(),contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
        item{SettingsCard{Column(Modifier.padding(20.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
            SettingsHeading("模型与线路",AppIcons.Model)
            OutlinedTextField(provider,{provider=it},Modifier.fillMaxWidth(),label={Text("线路 / 服务商")},singleLine=true,shape=RoundedCornerShape(14.dp))
            if(routes.isNotEmpty())TextButton(onClick={menu="routes"}){Icon(AppIcons.List,null,Modifier.size(18.dp));Spacer(Modifier.width(8.dp));Text("从线路目录选择")}
            OutlinedTextField(model,{model=it},Modifier.fillMaxWidth(),label={Text("模型 ID")},singleLine=true,shape=RoundedCornerShape(14.dp))
            if(models.isNotEmpty())TextButton(onClick={menu="models"}){Icon(AppIcons.List,null,Modifier.size(18.dp));Spacer(Modifier.width(8.dp));Text("从模型目录选择")}
        }}}
        item{SettingsCard{SettingsRow("思考深度",Icons.Outlined.AutoAwesome,mapOf("off" to "关闭","low" to "低","medium" to "中","high" to "高")[thinking] ?: thinking){menu="thinking"}}}
        item{SettingsCard{Column(Modifier.padding(20.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
            SettingsHeading("API 密钥",Icons.Outlined.Key)
            OutlinedTextField(key,{key=it},Modifier.fillMaxWidth(),label={Text("输入 API 密钥")},visualTransformation=PasswordVisualTransformation(),singleLine=true,shape=RoundedCornerShape(14.dp))
        }}}
        item{Button(onClick={scope.launch{working=true;info=null;try{val patch=JSONObject().put("provider",provider).put("model",model.trim()).put("thinking",thinking);if(key.isNotBlank())patch.put("api_key",key);val result=m.modelRequest("/api/llm/config","PATCH",patch);when{result.optBoolean("needs_key")->info="当前线路需要有效 API Key。";!result.optBoolean("ok")||result.optBoolean("rolled_back")->info="配置未生效，服务端保留了原配置。";else->{key="";load();info="已保存，后续回复将使用新的配置。"}}}catch(_:Exception){info="保存未确认，请重新读取配置后核对。"}finally{working=false}}},enabled=!working&&!m.busy&&provider.isNotBlank()&&model.isNotBlank(),modifier=Modifier.fillMaxWidth()){Text(if(working)"处理中…" else "保存配置")}}
        item{TextButton(onClick={scope.launch{load()}},enabled=!working){Icon(Icons.Outlined.Refresh,null,Modifier.size(18.dp));Spacer(Modifier.width(8.dp));Text("重新读取")};info?.let{Text(it,fontSize=14.sp)}}
    }
    if(menu.isNotEmpty())AlertDialog(onDismissRequest={menu=""},title={Text("选择")},text={LazyColumn{if(menu=="thinking")items(listOf("off","low","medium","high")){value->TextButton(onClick={thinking=value;menu=""}){Text(mapOf("off" to "关闭","low" to "低","medium" to "中","high" to "高")[value] ?: value)}}else items(if(menu=="routes")routes else models){r->TextButton(onClick={if(menu=="routes")provider=r.optString("id") else model=r.optString("id");menu=""}){Text(r.field("name","id"))}}}},confirmButton={TextButton(onClick={menu=""}){Text("关闭")}})
}
