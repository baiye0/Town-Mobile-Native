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
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.compose.LifecycleResumeEffect

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
    var inputFocused by remember { mutableStateOf(false) }
    var showQuestionIndex by rememberSaveable(m.connection?.endpoint,m.selected,m.showAllScenes) { mutableStateOf(false) }
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
            HorizontalDivider(); ListItem(headlineContent={Text(m.connection?.being ?: "未连接",maxLines=1,overflow=androidx.compose.ui.text.style.TextOverflow.Ellipsis)},leadingContent={Icon(Icons.Outlined.AccountCircle,null)},trailingContent={ActionIcon(AppIcons.Settings,"设置"){nav.screen="more";scope.launch{drawer.close()}}})
        }
    }) {
        Scaffold(topBar={Column { CenterAlignedTopAppBar(
            title={if(screen=="chat") Column(Modifier.clickable{nav.screen="conversation-settings"},horizontalAlignment=Alignment.CenterHorizontally){Text(m.current?.title ?: "Being",fontWeight=FontWeight.Medium,fontSize=19.sp,maxLines=1,overflow=androidx.compose.ui.text.style.TextOverflow.Ellipsis);if(m.connection!=null)Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(4.dp)){SBSStatusDot(m.sbsEnabled==true,m.sbsActivity.isNotEmpty());Text(m.sbsStatus,fontSize=11.sp,color=MaterialTheme.colorScheme.onSurfaceVariant,maxLines=1,overflow=androidx.compose.ui.text.style.TextOverflow.Ellipsis)}} else Text(destinations.find{it.id==screen}?.title ?: mapOf("more" to "设置与小镇","connection" to "连接 Being","pair" to "小镇连接","models" to "模型设置","navigation" to "底部导航","conversation-settings" to "对话设置","notification-settings" to "通知设置","appearance" to "外观","updates" to "应用更新","queue" to "发送队列")[screen] ?: "Being",fontWeight=FontWeight.Medium,fontSize=19.sp,maxLines=1,overflow=androidx.compose.ui.text.style.TextOverflow.Ellipsis)},
            navigationIcon={IconButton(onClick={if(screen in nav.tabs+"more")scope.launch{drawer.open()} else nav.back()}){Icon(if(screen in nav.tabs+"more")Icons.Outlined.Menu else Icons.AutoMirrored.Outlined.ArrowBack,"侧栏或返回")}},
            actions={if(screen=="chat") {
                ActionIcon(AppIcons.List,"提问索引",m.displayMessages.any{it.role=="user"}) { showQuestionIndex=true }
                ActionIcon(Icons.Outlined.Refresh,"刷新",!m.historyLoading&&m.connection!=null) { m.history() }
            }},
            colors=TopAppBarDefaults.topAppBarColors(containerColor=MaterialTheme.colorScheme.background))
            }},
            bottomBar={Column{
                if(screen=="chat"){Composer(m,onFocus={inputFocused=it}){nav.screen="connection"}}
                if(!keyboard && screen in nav.tabs+"more")NavigationBar {
                    (nav.tabs+"more").forEach { id -> NavigationBarItem(selected=screen==id,onClick={nav.screen=id},icon={BadgedBox(badge={val n=social.unread[id] ?: 0;if(n>0)Badge{Text(if(n>99)"99+" else "$n")}}){Icon(destinationIcon(id),destinations.find{it.id==id}?.title ?: "更多")}}) }
                }
            }}
        ) { padding -> Box(Modifier.fillMaxSize().padding(padding)) {
            EdgeNavigation(nav.canBack && screen != "chat",nav.canForward,{nav.back()},{nav.forward()}) {
            when(screen) {
                "chat" -> Chat(m,showQuestionIndex,{showQuestionIndex=false},inputFocused){nav.screen="connection"}
                "firesides","bonfire","mail" -> key(screen,social.identity?.id) { SocialScreen(screen,m,social,nav) }
                "pair" -> PairingScreen(m,social)
                "queue" -> DeliveryQueueScreen(m)
                "models" -> ModelsScreen(m)
                "navigation" -> NavigationSettings(nav)
                "conversation-settings" -> ConversationSettingsScreen(m)
                "notification-settings" -> NotificationSettingsScreen()
                "appearance" -> AppearanceSettings(nav)
                "updates" -> AppUpdateScreen()
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
@Composable fun Chat(m: TownModel, showIndex:Boolean=false, closeIndex:()->Unit={}, inputFocused:Boolean=false, connect:()->Unit) {
    LaunchedEffect(m.connection?.endpoint){m.history()}
    val focus = androidx.compose.ui.platform.LocalFocusManager.current
    val messages = m.displayMessages
    val scroll = key(m.connection?.endpoint,m.selected,m.showAllScenes){rememberChatScrollController()}
    val state = scroll.list
    ChatScrollEffects(scroll,messages,m.streamingReplyID,inputFocused,m.submittedMessageID){focus.clearFocus()}
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
            itemsIndexed(messages, key = { _, message -> message.id }) { index,message ->
                message.timestamp?.let{time->if(index==0||messages[index-1].timestamp?.take(16)!=time.take(16))Text(chatTime(time),Modifier.fillMaxWidth().padding(vertical=4.dp),fontSize=11.sp,color=MaterialTheme.colorScheme.onSurfaceVariant,textAlign=androidx.compose.ui.text.style.TextAlign.Center)}
                if(message.kind=="marker"){Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically){HorizontalDivider(Modifier.weight(1f));Text(message.text,Modifier.padding(horizontal=8.dp),fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant);HorizontalDivider(Modifier.weight(1f))}}
                else {
                val user = message.role == "user"
                Row(Modifier.fillMaxWidth().padding(start=if(user)40.dp else 0.dp,end=if(user)0.dp else 24.dp), horizontalArrangement = if (user) Arrangement.End else Arrangement.Start) {
                    val hasAttachment = user && (message.files?.isNotEmpty() == true || message.text.contains("[attachment-message:v1:"))
                    val originalText = MessagePresentation.body(message)
                    MessageActions(originalText,onQuote={m.draft+=(if(m.draft.isEmpty())"" else "\n\n")+it}) {
                    Column(Modifier.widthIn(max=if(user)310.dp else 580.dp),horizontalAlignment=if(user)Alignment.End else Alignment.Start) {
                    if (hasAttachment) {
                        Column(Modifier.wrapContentWidth().widthIn(max = 310.dp), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Column(Modifier.wrapContentWidth()) {
                                val isGlobalBeingMessage = message.sceneID == null && message.role == "being" && message.kind == null
                                if((m.showAllScenes&&message.sceneID!=m.selected)||isGlobalBeingMessage)Text(if(isGlobalBeingMessage) "全局消息" else (message.sceneLabel ?: message.sceneID ?: m.sceneName(message)),fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant,maxLines=1,overflow=androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                                AttachmentMessageView(message,m,MaterialTheme.colorScheme.onSurface)
                                DeliveryStatusView(message,m,MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            if (originalText.isNotBlank()) {
                                Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.chatBubble(true), RoundedCornerShape(22.dp)).padding(horizontal = 16.dp, vertical = 12.dp)) {
                                    MarkdownText(originalText, textColor=Color.White)
                                }
                            }
                        }
                    } else {
                        Column(Modifier.wrapContentWidth().widthIn(max = if (user) 310.dp else 580.dp).background(MaterialTheme.colorScheme.chatBubble(user), RoundedCornerShape(22.dp)).padding(16.dp)) {
                            val isGlobalBeingMessage = message.sceneID == null && message.role == "being" && message.kind == null
                            if((m.showAllScenes&&message.sceneID!=m.selected)||isGlobalBeingMessage)Text(if(isGlobalBeingMessage) "全局消息" else (message.sceneLabel ?: message.sceneID ?: m.sceneName(message)),fontSize=12.sp,color=if(user)Color.White else MaterialTheme.colorScheme.onSurfaceVariant,maxLines=1,overflow=androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                            // AttachmentMessageView intentionally omits user text: render the prompt here,
                            // just as the attachment branch does, before its secondary actions/status.
                            if(user) UserMessageBody(message) else AttachmentMessageView(message,m,MaterialTheme.colorScheme.onSurface)
                            if(user) DeliveryStatusView(message,m,Color.White)
                        }
                    }
                    }
                    }
                }
                if(user) {
                    val running=m.busy&&m.activeSendID?.let{message.id=="local:$it:user"}==true
                    if(running||!message.process.isNullOrEmpty())ChatRunView(message.process.orEmpty(),m.activity,running)
                }
                }
            }
            item(key=CHAT_BOTTOM_KEY) {
                if(m.historyLoading)CircularProgressIndicator(Modifier.size(20.dp),strokeWidth=2.dp)
                Spacer(Modifier.height(1.dp))
            }
        }
        if(state.canScrollForward)SmallFloatingActionButton(onClick={scroll.bottom()},modifier=Modifier.align(Alignment.BottomEnd).padding(16.dp),containerColor=MaterialTheme.colorScheme.surface){Icon(Icons.Outlined.ArrowDownward,"回到底部")}
        }
    }
    if(showIndex)QuestionIndexSheet(messages,onDismiss=closeIndex){index->scroll.message(messages[index].id);closeIndex()}
}
@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun Composer(m: TownModel, onFocus:(Boolean)->Unit={}, connect: () -> Unit) {
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
        Surface(
            shape = RoundedCornerShape(28.dp),
            color = MaterialTheme.colorScheme.surfaceContainerLow,
            contentColor = MaterialTheme.colorScheme.onSurface,
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
            tonalElevation = 0.dp,
            shadowElevation = 0.dp
        ) {
            Column(Modifier.fillMaxWidth()) {
                AttachmentPreviewStrip(m)
                Row(Modifier.fillMaxWidth().heightIn(min=48.dp).padding(horizontal=4.dp), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick={actionsExpanded=!actionsExpanded},modifier=Modifier.size(44.dp)){Icon(if(actionsExpanded) Icons.Outlined.Close else Icons.Outlined.Add,"资源库")}
                    androidx.compose.foundation.text.BasicTextField(
                        value=m.draft,onValueChange={m.draft=it},modifier=Modifier.weight(1f).onFocusChanged{onFocus(it.isFocused)}.padding(start=12.dp,end=4.dp),maxLines=6,
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
@Composable fun Settings(m: TownModel, close: () -> Unit) {
    var link by remember { mutableStateOf("") }
    val uri = LocalUriHandler.current
    LaunchedEffect(m.connection) { m.loadModel() }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).imePadding().padding(20.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
        SettingsCard { Column(Modifier.padding(20.dp),verticalArrangement=Arrangement.spacedBy(18.dp)) {
            SettingsHeading("连接你的 Being",Icons.Outlined.Link)
            OutlinedTextField(link, { link = it }, Modifier.fillMaxWidth(), label = { Text("Being 完整连接地址") }, singleLine = true, visualTransformation = PasswordVisualTransformation(), shape = RoundedCornerShape(14.dp))
            Button(onClick = { m.connect(link) { link = ""; close() } }, enabled = link.isNotBlank() && !m.connecting, modifier = Modifier.fillMaxWidth().heightIn(min=52.dp)) {
                if(m.connecting)CircularProgressIndicator(Modifier.size(18.dp),strokeWidth=2.dp) else Icon(Icons.Outlined.Link,null,Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp));Text(if (m.connecting) "正在验证…" else "连接 Being")
            }
            m.notice?.let { Text(it, color = MaterialTheme.colorScheme.error,style=MaterialTheme.typography.bodySmall) }
        } }
        m.connection?.let { c ->
            SettingsCard { Column(Modifier.padding(20.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
                SettingsHeading("当前连接",Icons.Outlined.CheckCircle,c.being)
                Text(c.endpoint,style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
                Text("模型 · ${m.model}",style=MaterialTheme.typography.bodyMedium)
                TextButton(onClick = { m.disconnect(); close() }) { Icon(Icons.Outlined.LinkOff,null,Modifier.size(18.dp),tint=MaterialTheme.colorScheme.error);Spacer(Modifier.width(8.dp));Text("断开连接", color = MaterialTheme.colorScheme.error) }
            } }
        }
        SettingsCard { SettingsRow("探索 Being Town",Icons.Outlined.Eco){uri.openUri("https://beings.town")} }
    }
}

fun chatTime(value:String):String = runCatching {
    val date=java.time.OffsetDateTime.parse(value).atZoneSameInstant(java.time.ZoneId.systemDefault())
    val format=if(date.toLocalDate()==java.time.LocalDate.now())java.time.format.DateTimeFormatter.ofLocalizedTime(java.time.format.FormatStyle.SHORT) else java.time.format.DateTimeFormatter.ofLocalizedDateTime(java.time.format.FormatStyle.MEDIUM,java.time.format.FormatStyle.SHORT)
    date.format(format)
}.getOrDefault(value.replace("T"," ").take(16))

@Composable private fun DeliveryStatusView(message: Message, m: TownModel, color: Color) {
    val entry = m.outbox.firstOrNull { "local:${it.id}:user" == message.kind } ?: return
    val label = DeliveryRules.bubbleStatus(entry) ?: return
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
    LaunchedEffect(m.connection) { if(m.connection!=null)m.syncSBS() }
    Column(Modifier.fillMaxWidth(),verticalArrangement=Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment=Alignment.CenterVertically) {
            SBSStatusDot(m.sbsEnabled==true,m.sbsActivity.isNotEmpty())
            Spacer(Modifier.width(8.dp))
            Text(m.sbsStatus,Modifier.weight(1f),color=MaterialTheme.colorScheme.onSurface,style=MaterialTheme.typography.bodySmall)
        }
            SettingsToggle("显示 SBS 消息正文",m.showAllScenes||m.showSBS,enabled=!m.showAllScenes&&m.current!=null,
                subtitle=if(m.showAllScenes)"全部场景包含 SBS 正文；切回当前场景后恢复该场景的设置。" else "仅影响当前场景，思考状态在顶部显示。") {m.showSBS=it;m.saveSBS()}
            HorizontalDivider()
            SettingsToggle("自主醒来",m.sbsEnabled==true,enabled=m.sbsEnabled!=null&&!m.sbsUpdating,subtitle="允许 SBS 主动开始任务") {m.setSBSEnabled(it)}
            m.sbsError?.let{Text(it,color=MaterialTheme.colorScheme.error,style=MaterialTheme.typography.bodySmall)}
    }
}
