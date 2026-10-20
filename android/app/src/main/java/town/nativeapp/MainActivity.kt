package town.nativeapp

import android.os.Bundle
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.draw.clip
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import androidx.compose.ui.platform.LocalDensity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import android.speech.RecognizerIntent
import android.content.Intent
import android.app.Activity
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.ArrowForward
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.compose.foundation.interaction.collectIsDraggedAsState

class MainActivity : ComponentActivity() {
    override fun onNewIntent(intent: android.content.Intent) { super.onNewIntent(intent); setIntent(intent); CompletionNotifications.capture(intent) }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState); CompletionNotifications.capture(intent); enableEdgeToEdge()
        setContent {
            val nav: NavigationModel = viewModel()
            val dark = nav.appearance == "dark" || nav.appearance == "system" && isSystemInDarkTheme()
            MaterialTheme(colorScheme = clientColors(dark)) { Town(nav = nav) }
        }
    }
}
@OptIn(ExperimentalMaterial3Api::class)
@Composable fun Town(m: TownModel = viewModel(), nav: NavigationModel = viewModel(), social: SocialModel = viewModel()) {
    val drawer = rememberDrawerState(DrawerValue.Closed)
    val scope = rememberCoroutineScope()
    var query by rememberSaveable { mutableStateOf("") }
    var deleting by remember { mutableStateOf<Room?>(null) }
    var rename by remember { mutableStateOf<Room?>(null) }
    var renameText by remember { mutableStateOf("") }
    val screen = nav.screen
    LaunchedEffect(m.connection,m.appActive,screen) {
        if(m.connection!=null && m.appActive && screen=="chat")while(true){m.syncSBS();kotlinx.coroutines.delay(10000)}
    }
    LaunchedEffect(m.connection,m.selected){m.showSBS=m.getSBSVisibility()}
    SideEffect { m.chatVisible = screen == "chat" }
    LaunchedEffect(CompletionNotifications.pendingScene,CompletionNotifications.pendingEndpoint,m.connection?.endpoint){if(CompletionNotifications.pendingEndpoint==m.connection?.endpoint)CompletionNotifications.pendingScene?.let{m.selectScene(it);nav.screen="chat";CompletionNotifications.pendingScene=null}}
    val keyboard = WindowInsets.ime.getBottom(LocalDensity.current) > 0
    LifecycleResumeEffect(social.identity?.id) { m.appActive=true; m.history(); m.resumeDelivery(); if(CompletionNotifications.pendingEndpoint==m.connection?.endpoint)CompletionNotifications.pendingScene?.let{m.selectScene(it);nav.screen="chat";CompletionNotifications.pendingScene=null}; social.startLive(); onPauseOrDispose { m.appActive=false; social.stopLive() } }
    BackHandler(drawer.isOpen || nav.canBack) { if (drawer.isOpen) scope.launch { drawer.close() } else nav.back() }
    ModalNavigationDrawer(drawerState = drawer, gesturesEnabled = (screen == "chat" || drawer.isOpen), drawerContent = {
        ModalDrawerSheet(Modifier.fillMaxWidth(0.84f),drawerContainerColor=MaterialTheme.colorScheme.background) {
            Row(Modifier.fillMaxWidth().padding(horizontal=16.dp,vertical=8.dp), verticalAlignment = Alignment.CenterVertically) { Text("Being", fontSize = 22.sp, fontWeight = FontWeight.SemiBold); Spacer(Modifier.weight(1f)); IconButton(onClick = { scope.launch { drawer.close() } }) { Icon(Icons.AutoMirrored.Outlined.ArrowBack,"收起侧栏") } }
            OutlinedTextField(query,{query=it},Modifier.padding(horizontal=16.dp).fillMaxWidth(),textStyle=androidx.compose.ui.text.TextStyle(fontSize=15.sp),placeholder={Text("搜索场景",fontSize=15.sp)},singleLine=true,shape=RoundedCornerShape(12.dp))
            TextButton(onClick={nav.sceneSheet="create";nav.screen="chat";scope.launch{drawer.close()}},enabled=m.connection!=null,modifier=Modifier.padding(12.dp)) { Icon(Icons.Outlined.Edit,null); Spacer(Modifier.width(12.dp)); Text("新建场景") }
            LazyColumn(Modifier.weight(1f).padding(horizontal=12.dp),verticalArrangement=Arrangement.spacedBy(4.dp)) {
                items(m.visibleRooms.filter { query.isEmpty() || it.title.contains(query,true) },key={it.id}) { room ->
                    val swipe = rememberSwipeToDismissBoxState(confirmValueChange={ value ->
                        if (m.busy) false else when(value) {
                            SwipeToDismissBoxValue.StartToEnd -> {rename=room;renameText=room.title;false}
                            SwipeToDismissBoxValue.EndToStart -> {deleting=room;false}
                            else -> false
                        }
                    })
                    SwipeToDismissBox(state=swipe,backgroundContent={Row(Modifier.fillMaxSize().padding(20.dp),horizontalArrangement=Arrangement.SpaceBetween,verticalAlignment=Alignment.CenterVertically){Text("重命名");Text("删除",color=MaterialTheme.colorScheme.error)}}) {
                        ListItem(headlineContent={Text(room.title,maxLines=1,fontSize=15.sp,fontWeight=if(room.id==m.selected)FontWeight.SemiBold else FontWeight.Normal)},supportingContent={room.messages.lastOrNull()?.text?.takeIf{it.isNotBlank()}?.let{Text(it.take(35),maxLines=1,fontSize=12.sp)}},colors=ListItemDefaults.colors(containerColor=if(room.id==m.selected)MaterialTheme.colorScheme.secondaryContainer else MaterialTheme.colorScheme.background),modifier=Modifier.clip(RoundedCornerShape(12.dp)).clickable{m.selectScene(room.id);nav.screen="chat";scope.launch{drawer.close()}})
                    }
                }
            }
            Column(Modifier.padding(horizontal=20.dp,vertical=8.dp)) {
                Row { TextButton(onClick={nav.sceneSheet="bind"},enabled=m.connection!=null){Text("绑定已有场景")};TextButton(onClick={nav.sceneSheet="details"},enabled=m.current!=null){Text("场景详情")} }
                Row(Modifier.fillMaxWidth().heightIn(min=44.dp),verticalAlignment=Alignment.CenterVertically) { Text("显示全部场景上下文",Modifier.weight(1f),fontSize=14.sp);Switch(m.showAllScenes,{m.showAllScenes=it},enabled=m.current!=null) }
            }
            HorizontalDivider(); ListItem(headlineContent={Text(m.connection?.being ?: "未连接")},leadingContent={Icon(Icons.Outlined.AccountCircle,null)},trailingContent={TextButton(onClick={nav.screen="more";scope.launch{drawer.close()}}){Text("设置")}})
        }
    }) {
        Scaffold(topBar={Column { CenterAlignedTopAppBar(
            title={if(screen=="chat") Column(Modifier.clickable{nav.screen="conversation-settings"},horizontalAlignment=Alignment.CenterHorizontally){Text(m.current?.title ?: "Being",fontWeight=FontWeight.Medium,fontSize=19.sp,maxLines=1,overflow=androidx.compose.ui.text.style.TextOverflow.Ellipsis);if(m.connection!=null)Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(4.dp)){SBSStatusDot(m.sbsEnabled==true,m.sbsActivity.isNotEmpty());Text(m.sbsStatus,fontSize=11.sp,color=MaterialTheme.colorScheme.onSurfaceVariant,maxLines=1,overflow=androidx.compose.ui.text.style.TextOverflow.Ellipsis)}} else Text(destinations.find{it.id==screen}?.title ?: mapOf("more" to "更多","connection" to "连接 Being","pair" to "连接 Being Town","models" to "模型设置","navigation" to "自定义导航")[screen] ?: "Being",fontWeight=FontWeight.Medium,fontSize=19.sp)},
            navigationIcon={IconButton(onClick={if(screen in nav.tabs+"more")scope.launch{drawer.open()} else nav.back()}){Icon(if(screen in nav.tabs+"more")Icons.Outlined.Menu else Icons.AutoMirrored.Outlined.ArrowBack,"侧栏或返回")}},
            actions={if(screen=="chat") IconButton(onClick={m.history()},enabled=!m.historyLoading&&m.connection!=null){Icon(Icons.Outlined.Refresh,"刷新")}},
            colors=TopAppBarDefaults.topAppBarColors(containerColor=MaterialTheme.colorScheme.background))
            }},
            bottomBar={Column{
                if(screen=="chat"){Composer(m){nav.screen="connection"}}
                if(!keyboard && screen in nav.tabs+"more")NavigationBar {
                    (nav.tabs+"more").forEach { id -> NavigationBarItem(selected=screen==id,onClick={nav.screen=id},icon={BadgedBox(badge={val n=social.unread[id] ?: 0;if(n>0)Badge{Text(if(n>99)"99+" else "$n")}}){Icon(destinationIcon(id),destinations.find{it.id==id}?.title ?: "更多")}}) }
                }
            }}
        ) { padding -> Box(Modifier.fillMaxSize().padding(padding)) {
            EdgeNavigation(nav.canBack && screen != "chat",nav.canForward,{nav.back()},{nav.forward()}) {
            when(screen) {
                "chat" -> Chat(m){nav.screen="connection"}
                "firesides","bonfire","mail" -> key(screen,social.identity?.id) { SocialScreen(screen,m,social,nav) }
                "pair" -> PairingScreen(m,social)
                "queue" -> DeliveryQueueScreen(m)
                "models" -> ModelsScreen(m)
                "navigation" -> NavigationSettings(nav)
                "conversation-settings" -> ConversationSettingsScreen(m)
                "notification-settings" -> NotificationSettingsScreen()
                "connection" -> Settings(m){nav.screen="more"}
                "more" -> MoreScreen(m,social,nav)
                else -> key(screen,social.identity?.id) { CatalogScreen(screen,m,social,nav) }
            }
        } } }
    }
    nav.sceneSheet?.let{mode->SceneDialog(mode,m){nav.sceneSheet=null}}
    deleting?.let{room->AlertDialog(onDismissRequest={deleting=null},title={Text("删除场景？")},text={Text("确定从本机场景列表中删除「${room.title}」？历史记录会保留，仍可开启「显示全部场景上下文」查看。")},confirmButton={TextButton(onClick={m.delete(room.id);deleting=null}){Text("确认删除")}},dismissButton={TextButton(onClick={deleting=null}){Text("取消")}})}
    if(rename!=null)AlertDialog(onDismissRequest={rename=null},title={Text("重命名场景")},text={OutlinedTextField(renameText,{renameText=it})},confirmButton={TextButton(onClick={m.rename(rename!!.id,renameText);rename=null}){Text("保存")}},dismissButton={TextButton(onClick={rename=null}){Text("取消")}})
}
@Composable fun Chat(m: TownModel, connect:()->Unit) {
    LaunchedEffect(m.connection?.endpoint){m.history()}
    val focus = androidx.compose.ui.platform.LocalFocusManager.current
    val messages = m.displayMessages
    var showIndex by remember{mutableStateOf(false)};var indexSearch by remember{mutableStateOf("")}
    val state = rememberLazyListState()
    val scope = rememberCoroutineScope()
    var followLatest by remember(m.selected,m.showAllScenes) { mutableStateOf(true) }
    val dragging by state.interactionSource.collectIsDraggedAsState()
    LaunchedEffect(dragging) { if(dragging) followLatest=false }
    LaunchedEffect(state) { snapshotFlow { !state.canScrollForward }.collect { if(it) followLatest=true } }
    // A streamed reply changes its text for every network chunk.  Scrolling on
    // every chunk forces LazyColumn to measure the whole visible window again,
    // which makes both streaming and dragging feel sticky.  Coalesce those
    // updates and scroll only after the stream has been quiet briefly.
    LaunchedEffect(messages.lastOrNull()?.text,messages.size,m.selected,m.showAllScenes) {
        if(messages.isNotEmpty() && followLatest) {
            delay(80)
            if (followLatest) state.scrollToItem(messages.lastIndex)
        }
    }
    if (messages.isEmpty()) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 28.dp).padding(top = 42.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(28.dp)) {
            Box(Modifier.size(100.dp).background(MaterialTheme.colorScheme.primary.copy(alpha = 0.08f), CircleShape), contentAlignment = Alignment.Center) { Image(painterResource(R.drawable.client_logo), "Being", Modifier.size(100.dp).clip(RoundedCornerShape(24.dp))) }
            Text(if(m.connection==null)"从一个想法开始" else "Being", fontSize = 34.sp)
            Text(if(m.connection==null)"连接你的 Being，继续对话。" else "当前场景还没有对话。", color = MaterialTheme.colorScheme.onSurfaceVariant)
            if(m.connection==null)Button(onClick=connect){Text("连接我的 Being")}
        }
    } else {
        Box(Modifier.fillMaxSize()) {
        LazyColumn(state = state,modifier=Modifier.fillMaxSize().pointerInput(Unit) { detectTapGestures { focus.clearFocus() } }, contentPadding = PaddingValues(24.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            itemsIndexed(messages, key = { index, message ->
                message.sequence ?: message.kind ?: "${message.role}:${message.timestamp}:${index}"
            }) { index,message ->
                message.timestamp?.let{time->if(index==0||messages[index-1].timestamp?.take(16)!=time.take(16))Text(chatTime(time),Modifier.fillMaxWidth().padding(vertical=4.dp),fontSize=11.sp,color=MaterialTheme.colorScheme.onSurfaceVariant,textAlign=androidx.compose.ui.text.style.TextAlign.Center)}
                if(message.kind=="marker"){Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically){HorizontalDivider(Modifier.weight(1f));Text(message.text,Modifier.padding(horizontal=8.dp),fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant);HorizontalDivider(Modifier.weight(1f))}}
                else {
                val user = message.role == "user"
                Row(Modifier.fillMaxWidth(), horizontalArrangement = if (user) Arrangement.End else Arrangement.Start) {
                    val hasAttachment = user && (message.files?.isNotEmpty() == true || message.text.contains("[attachment-message:v1:"))
                    val originalText = DeliveryRules.displayText(message.text).trim()
                    if (hasAttachment) {
                        Column(Modifier.wrapContentWidth().widthIn(max = 310.dp), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.chatBubble(true), RoundedCornerShape(22.dp)).padding(16.dp)) {
                                val isGlobalBeingMessage = message.sceneID == null && message.role == "being" && message.kind == null
                                if((m.showAllScenes&&message.sceneID!=m.selected)||isGlobalBeingMessage)Text(if(isGlobalBeingMessage) "全局消息" else (message.sceneLabel ?: message.sceneID ?: m.sceneName(message)),fontSize=12.sp,color=Color.White.copy(alpha=.82f),maxLines=1,overflow=androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                                AttachmentMessageView(message,m,Color.White)
                                DeliveryStatusView(message,m,Color.White)
                            }
                            if (originalText.isNotBlank()) {
                                Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.chatBubble(true), RoundedCornerShape(22.dp)).padding(horizontal = 16.dp, vertical = 12.dp)) {
                                    TextButton(onClick={m.draft+=(if(m.draft.isEmpty())"" else "\n\n")+originalText.lines().joinToString("\n") { "> $it" }}){Text("引用到草稿",color=Color.White)}
                                    MarkdownText(originalText, textColor=Color.White)
                                }
                            }
                        }
                    } else {
                        Column(Modifier.wrapContentWidth().widthIn(max = if (user) 310.dp else 580.dp).background(MaterialTheme.colorScheme.chatBubble(user), RoundedCornerShape(22.dp)).padding(16.dp)) {
                            val isGlobalBeingMessage = message.sceneID == null && message.role == "being" && message.kind == null
                            if((m.showAllScenes&&message.sceneID!=m.selected)||isGlobalBeingMessage)Text(if(isGlobalBeingMessage) "全局消息" else (message.sceneLabel ?: message.sceneID ?: m.sceneName(message)),fontSize=12.sp,color=if(user)Color.White else MaterialTheme.colorScheme.onSurfaceVariant,maxLines=1,overflow=androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                            TextButton(onClick={m.draft+=(if(m.draft.isEmpty())"" else "\n\n")+DeliveryRules.displayText(message.text).lines().joinToString("\n") { "> $it" }}){Text("引用到草稿",color=if(user)Color.White else MaterialTheme.colorScheme.primary)}
                            AttachmentMessageView(message,m,if(user)Color.White else MaterialTheme.colorScheme.onSurface)
                            if(user) DeliveryStatusView(message,m,Color.White)
                        }
                    }
                }
                }
            }
            item {
                if(m.busy && m.activeScene==m.selected && m.activity.isNotEmpty() && m.activity != "正在回复") ThinkingIndicator(m.activity)
                Spacer(Modifier.height(1.dp))
            }
        }
        TextButton(onClick={showIndex=true},modifier=Modifier.align(Alignment.TopEnd)){Text("提问索引")}
        if(state.canScrollForward)SmallFloatingActionButton(onClick={followLatest=true;scope.launch{state.animateScrollToItem(messages.lastIndex)}},modifier=Modifier.align(Alignment.BottomEnd).padding(16.dp),containerColor=MaterialTheme.colorScheme.surface){Icon(Icons.Outlined.ArrowDownward,"回到底部")}
        }
    }
    if(showIndex)AlertDialog(onDismissRequest={showIndex=false},title={Text("提问索引")},text={Column{OutlinedTextField(indexSearch,{indexSearch=it},label={Text("搜索提问")});LazyColumn(Modifier.heightIn(max=400.dp)){itemsIndexed(messages){index,message->if(message.role=="user"&&(indexSearch.isEmpty()||message.text.contains(indexSearch,true)))TextButton(onClick={followLatest=false;showIndex=false;scope.launch{state.scrollToItem(index)}}){Text(DeliveryRules.displayText(message.text),maxLines=3)}}}}},confirmButton={TextButton(onClick={showIndex=false}){Text("完成")}})
}
@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun Composer(m: TownModel, connect: () -> Unit) {
    val focus = androidx.compose.ui.platform.LocalFocusManager.current
    var voiceScene by rememberSaveable { mutableStateOf<String?>(null) }
    var voiceEndpoint by rememberSaveable { mutableStateOf<String?>(null) }
    var actionsExpanded by rememberSaveable { mutableStateOf(false) }
    val voice=rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()){result->
        if(result.resultCode==Activity.RESULT_OK && voiceScene==m.selected && voiceEndpoint==m.connection?.endpoint){
            result.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()?.takeIf{it.isNotBlank()}?.let{m.draft=m.draft+(if(m.draft.isEmpty())"" else " ")+it}
        }
    }
    Column(Modifier.imePadding().padding(horizontal = 16.dp).padding(top = 12.dp, bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        m.notice?.let { Text(it, fontSize = 12.sp, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(horizontal = 8.dp)) }
        Surface(shape = RoundedCornerShape(28.dp), tonalElevation = 3.dp, shadowElevation = 2.dp) {
            Column(Modifier.fillMaxWidth()) {
                AttachmentPreviewStrip(m)
                Row(Modifier.fillMaxWidth().heightIn(min=48.dp).padding(horizontal=4.dp), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick={actionsExpanded=!actionsExpanded},modifier=Modifier.size(44.dp)){Icon(if(actionsExpanded) Icons.Outlined.Close else Icons.Outlined.Add,"资源库")}
                    androidx.compose.foundation.text.BasicTextField(
                        value=m.draft,onValueChange={m.draft=it},modifier=Modifier.weight(1f).padding(start=12.dp,end=4.dp),maxLines=6,
                        textStyle=androidx.compose.ui.text.TextStyle(fontSize=16.sp,color=MaterialTheme.colorScheme.onSurface),
                        cursorBrush=androidx.compose.ui.graphics.SolidColor(MaterialTheme.colorScheme.primary),
                        decorationBox={inner->Box(Modifier.padding(vertical=8.dp)){if(m.draft.isEmpty())Text("说点什么…",fontSize=16.sp,color=MaterialTheme.colorScheme.onSurfaceVariant);inner()}}
                    )
                    IconButton(onClick={
                        focus.clearFocus()
                        voiceScene=m.selected;voiceEndpoint=m.connection?.endpoint
                        try{voice.launch(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply{putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);putExtra(RecognizerIntent.EXTRA_LANGUAGE,java.util.Locale.getDefault().toLanguageTag())})}catch(_:android.content.ActivityNotFoundException){m.notice="系统语音识别暂不可用。"}
                    },enabled=!m.busy,modifier=Modifier.size(44.dp)){Icon(Icons.Outlined.Mic,"语音输入",tint=MaterialTheme.colorScheme.onSurfaceVariant)}
                    if(m.busy || m.connection==null || m.draft.isNotBlank() || m.attachments.isNotEmpty())FilledIconButton(onClick = { focus.clearFocus(); if (m.connection == null) connect() else if (m.busy && m.draft.isBlank() && m.attachments.isEmpty()) m.stop() else m.send() }, enabled = m.connection == null || m.busy || m.draft.isNotBlank() || m.attachments.isNotEmpty(), modifier = Modifier.size(44.dp)) { Icon(if (m.busy && m.draft.isBlank() && m.attachments.isEmpty()) Icons.Outlined.Stop else if (m.connection == null) Icons.Outlined.Link else Icons.Outlined.ArrowUpward, if (m.busy) "停止生成" else if (m.connection == null) "连接 Being" else "发送") }
                }
            }
        }
    }
    if (actionsExpanded) ModalBottomSheet(onDismissRequest={actionsExpanded=false}, dragHandle={BottomSheetDefaults.DragHandle()}) {
        AttachmentPickerRow(m) { actionsExpanded = false }
    }
}
@Composable private fun History(m: TownModel, close: () -> Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    LaunchedEffect(Unit) { m.history() }
    Column(Modifier.fillMaxSize().padding(horizontal = 20.dp)) {
        OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth(), placeholder = { Text("搜索场景") }, leadingIcon = { Icon(Icons.Outlined.Search, null) }, singleLine = true, shape = RoundedCornerShape(22.dp))
        Row { TextButton(onClick = { m.newChat(); close() }, enabled = m.connection != null) { Text("＋ 新对话") }; TextButton(onClick = { m.history() }) { Text("同步历史") } }
        if (m.visibleRooms.isEmpty()) Text("还没有对话。从一个问题开始。", Modifier.padding(top = 60.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
        LazyColumn { items(m.visibleRooms.filter { it.title.contains(query, ignoreCase = true) }, key = { it.id }) { room ->
            ListItem(headlineContent = { Text(room.title) }, supportingContent = { Text(room.messages.lastOrNull()?.text?.take(45) ?: "新的开始", maxLines = 1) }, modifier = Modifier.clickable { m.selected = room.id; close() }, trailingContent = { IconButton(onClick = { m.delete(room.id) }) { Icon(Icons.Outlined.DeleteOutline, "删除本地记录") } })
        } }
    }
}
@Composable private fun Settings(m: TownModel, close: () -> Unit) {
    var link by remember { mutableStateOf("") }
    val uri = LocalUriHandler.current
    LaunchedEffect(m.connection) { m.loadModel() }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
        Icon(Icons.Outlined.AutoAwesome, null, Modifier.size(40.dp), tint = MaterialTheme.colorScheme.primary)
        Text("Being", fontSize = 24.sp, fontFamily = FontFamily.Serif)
        OutlinedTextField(link, { link = it }, Modifier.fillMaxWidth(), label = { Text("Being 完整连接地址") }, singleLine = true, visualTransformation = PasswordVisualTransformation(), shape = RoundedCornerShape(18.dp))
        Button(onClick = { m.connect(link) { link = ""; close() } }, enabled = link.isNotBlank() && !m.connecting, modifier = Modifier.fillMaxWidth().height(52.dp)) { Text(if (m.connecting) "正在验证…" else "连接 Being") }
        m.notice?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        m.connection?.let { c ->
            HorizontalDivider(); Text("当前连接", fontWeight = FontWeight.SemiBold); Text(c.being); Text(c.endpoint, fontSize = 12.sp); Text("模型 · ${m.model}", fontSize = 14.sp)
            TextButton(onClick = { m.disconnect(); close() }) { Text("断开连接", color = MaterialTheme.colorScheme.error) }
        }
        HorizontalDivider()
        TextButton(onClick = { uri.openUri("https://beings.town") }) { Icon(Icons.Outlined.Eco, null); Spacer(Modifier.width(10.dp)); Text("探索 Being Town"); Spacer(Modifier.weight(1f)); Icon(Icons.AutoMirrored.Outlined.ArrowForward, null) }
        Text("Being 0.2 · Jetpack Compose", fontSize = 12.sp, color = MaterialTheme.colorScheme.outline)
    }
}

fun chatTime(value:String):String = runCatching {
    val date=java.time.OffsetDateTime.parse(value).atZoneSameInstant(java.time.ZoneId.systemDefault())
    val format=if(date.toLocalDate()==java.time.LocalDate.now())java.time.format.DateTimeFormatter.ofLocalizedTime(java.time.format.FormatStyle.SHORT) else java.time.format.DateTimeFormatter.ofLocalizedDateTime(java.time.format.FormatStyle.MEDIUM,java.time.format.FormatStyle.SHORT)
    date.format(format)
}.getOrDefault(value.replace("T"," ").take(16))

@Composable private fun ThinkingIndicator(activity: String) {
    var phase by remember { mutableStateOf(0) }
    LaunchedEffect(Unit) { while(true) { kotlinx.coroutines.delay(330); phase=(phase+1)%3 } }
    Column(verticalArrangement=Arrangement.spacedBy(8.dp)) {
        Text("Being",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
        Row(Modifier.padding(vertical=10.dp),horizontalArrangement=Arrangement.spacedBy(6.dp),verticalAlignment=Alignment.CenterVertically) {
            repeat(3) { index -> Box(Modifier.size(6.dp).background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha=if(phase==index)1f else 0.3f),CircleShape)) }
            if(activity!="思考中") Text(activity,fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable private fun DeliveryStatusView(message: Message, m: TownModel, color: Color) {
    val entry = m.outbox.firstOrNull { "local:${it.id}:user" == message.kind } ?: return
    val label = when (entry.phase) {
        "queued" -> if (entry.files.isEmpty()) "等待发送" else "等待上传附件"
        "preparing" -> if (entry.files.any { it.attachmentID == null }) "正在上传附件" else "正在准备附件"
        "sending" -> "正在发送"
        "waiting" -> "服务端排队中"
        "failed" -> "发送失败"
        "unknown" -> "发送结果待确认"
        "stopped" -> "已停止"
        else -> entry.phase
    }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(label, fontSize = 12.sp, color = color.copy(alpha = .82f))
        entry.error?.takeIf { it.isNotBlank() }?.let { Text(it, fontSize = 11.sp, color = color.copy(alpha = .76f), maxLines = 3) }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (entry.phase == "failed") TextButton(onClick = { m.retryQueued(entry.id) }, contentPadding = PaddingValues(0.dp)) { Text("重试", color = color) }
            if (entry.phase == "unknown") TextButton(onClick = { m.resumeDelivery() }, contentPadding = PaddingValues(0.dp)) { Text("核对历史", color = color) }
        }
    }
}


@Composable fun SBSControl(m:TownModel) {
    var expanded by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceVariant).padding(horizontal=20.dp,vertical=4.dp)) {
        TextButton(onClick={expanded=!expanded},modifier=Modifier.fillMaxWidth()) {
            SBSStatusDot(m.sbsEnabled==true,m.sbsActivity.isNotEmpty())
            Spacer(Modifier.width(8.dp))
            Text(m.sbsStatus,Modifier.weight(1f),color=MaterialTheme.colorScheme.onSurface,style=MaterialTheme.typography.bodySmall)
            Text(if(expanded)"收起" else "设置",color=MaterialTheme.colorScheme.onSurface)
        }
        if(expanded){
            Row(verticalAlignment=Alignment.CenterVertically){Text("显示 SBS 消息正文",Modifier.weight(1f));Switch(m.showAllScenes||m.showSBS,{m.showSBS=it;m.saveSBS()},enabled=!m.showAllScenes&&m.current!=null)}
            Text(if(m.showAllScenes)"全部场景包含 SBS 正文；切回当前场景后恢复该场景的设置。" else "仅影响当前场景，思考状态统一在顶部显示。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
            Row(verticalAlignment=Alignment.CenterVertically){Text("自主醒来",Modifier.weight(1f));Switch(m.sbsEnabled==true,{m.setSBSEnabled(it)},enabled=m.sbsEnabled!=null&&!m.sbsUpdating)}
            Text("控制 SBS 是否主动开始任务",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
            m.sbsError?.let{Text(it,color=MaterialTheme.colorScheme.error,style=MaterialTheme.typography.bodySmall)}
        }
    }
}
