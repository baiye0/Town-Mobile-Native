package town.nativeapp

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import androidx.compose.foundation.Image
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.FileProvider
import android.graphics.BitmapFactory
import java.io.File
import java.util.UUID
import android.os.Build
import kotlinx.coroutines.launch

@Composable fun AttachmentPickerRow(m:TownModel,onImported:()->Unit = {}){
    val picker=rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()){uris->if(uris.isNotEmpty()){m.importFiles(uris);onImported()}}
    val context=LocalContext.current
    var cameraFile by remember { mutableStateOf<File?>(null) }
    val camera=rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()){ok->if(ok)cameraFile?.let{m.importFiles(listOf(android.net.Uri.fromFile(it)));onImported()} }
    val cameraPermission=rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()){allowed->if(allowed){val file=File(context.cacheDir,"capture-${UUID.randomUUID()}.jpg");cameraFile=file;camera.launch(FileProvider.getUriForFile(context,"${context.packageName}.files",file))}}
    if(m.connection!=null)Column(Modifier.fillMaxWidth().padding(horizontal=20.dp),verticalArrangement=Arrangement.spacedBy(16.dp)){
        Text("资源库",style=MaterialTheme.typography.titleLarge)
        Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(12.dp)) {
            resourceCard(Icons.Outlined.PhotoCamera,"拍照",Modifier.weight(1f)){if(androidx.core.content.ContextCompat.checkSelfPermission(context,android.Manifest.permission.CAMERA)==android.content.pm.PackageManager.PERMISSION_GRANTED){val file=File(context.cacheDir,"capture-${UUID.randomUUID()}.jpg");cameraFile=file;camera.launch(FileProvider.getUriForFile(context,"${context.packageName}.files",file))}else cameraPermission.launch(android.Manifest.permission.CAMERA)}
            resourceCard(Icons.Outlined.Image,"照片",Modifier.weight(1f)){picker.launch(arrayOf("image/*"))}
            resourceCard(Icons.Outlined.AttachFile,"文件",Modifier.weight(1f)){picker.launch(arrayOf("*/*"))}
        }
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(MaterialTheme.colorScheme.surfaceVariant)) {
            TextButton(onClick={picker.launch(arrayOf("*/*"))},modifier=Modifier.fillMaxWidth().height(56.dp),contentPadding=PaddingValues(horizontal=16.dp)){Icon(Icons.Outlined.AttachFile,null);Spacer(Modifier.width(14.dp));Text("添加文件");Spacer(Modifier.weight(1f));Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight,null)}
            HorizontalDivider(Modifier.padding(start=56.dp))
            Row(Modifier.fillMaxWidth().height(56.dp).padding(horizontal=16.dp),verticalAlignment=androidx.compose.ui.Alignment.CenterVertically){Icon(Icons.Outlined.AutoAwesome,null,tint=MaterialTheme.colorScheme.onSurfaceVariant);Spacer(Modifier.width(14.dp));Text("智能 UI");Spacer(Modifier.weight(1f));Switch(m.intelligentUI,{m.intelligentUI=it})}
        }
        if(m.attachments.isNotEmpty()) androidx.compose.foundation.lazy.LazyRow(horizontalArrangement=Arrangement.spacedBy(8.dp)){items(m.attachments,key={it.id}){file->AssistChip(onClick={m.attachments=m.attachments.filter{it.id!=file.id}},label={Text(file.name,maxLines=1)},trailingIcon={Icon(Icons.Outlined.Close,null)})}}
    } else Text("连接 Being 后可添加附件",color=MaterialTheme.colorScheme.onSurfaceVariant)
}
@Composable private fun resourceCard(icon:androidx.compose.ui.graphics.vector.ImageVector,title:String,modifier:Modifier=Modifier,onClick:()->Unit){OutlinedCard(onClick=onClick,modifier=modifier.height(84.dp)){Column(Modifier.fillMaxSize(),horizontalAlignment=androidx.compose.ui.Alignment.CenterHorizontally,verticalArrangement=Arrangement.Center){Icon(icon,null,Modifier.size(26.dp));Spacer(Modifier.height(6.dp));Text(title,style=MaterialTheme.typography.labelMedium)}}}

@Composable fun AttachmentPreviewStrip(m:TownModel, modifier:Modifier = Modifier) {
    if (m.attachments.isEmpty()) return
    val context = LocalContext.current
    LazyRow(modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = 12.dp, bottom = 4.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        items(m.attachments, key = { it.id }) { file ->
            val bitmap = remember(file.path) {
                if (file.mime.startsWith("image/")) {
                    BitmapFactory.decodeFile(File(context.filesDir, "attachments/${file.path}").path)?.asImageBitmap()
                } else null
            }
            Box(Modifier.size(96.dp), contentAlignment = Alignment.TopEnd) {
                Box(Modifier.size(88.dp).clip(RoundedCornerShape(14.dp)).background(MaterialTheme.colorScheme.surfaceVariant), contentAlignment = Alignment.Center) {
                    if (bitmap != null) Image(bitmap, contentDescription = file.name, modifier = Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                    else Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                        Icon(if (file.mime.startsWith("image/")) Icons.Outlined.Image else Icons.Outlined.InsertDriveFile, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(file.name, maxLines = 2, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(6.dp))
                    }
                }
                IconButton(onClick = { m.attachments = m.attachments.filter { it.id != file.id } }, modifier = Modifier.size(26.dp).background(MaterialTheme.colorScheme.scrim.copy(alpha = 0.72f), androidx.compose.foundation.shape.CircleShape)) {
                    Icon(Icons.Outlined.Close, "移除附件 ${file.name}", tint = MaterialTheme.colorScheme.inverseOnSurface, modifier = Modifier.size(15.dp))
                }
            }
        }
    }
}
@Composable fun DeliveryQueueScreen(m:TownModel){
    var edit by remember{mutableStateOf<String?>(null)};var text by remember{mutableStateOf("")}
    LazyColumn(contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(16.dp)){
        if(m.visibleOutbox.isEmpty())item{Text("没有等待发送的消息")}
        items(m.visibleOutbox,key={it.id}){entry->
            Column(verticalArrangement=Arrangement.spacedBy(8.dp)){
                Text(entry.title,style=MaterialTheme.typography.titleMedium)
                Text(entry.text.ifEmpty{entry.files.joinToString("、"){it.name}},maxLines=4)
                Text(mapOf("queued" to "等待发送","preparing" to "正在准备附件","sending" to "正在回复","waiting" to "服务端排队中","failed" to "发送失败","unknown" to "结果待确认","stopped" to "已停止")[entry.phase] ?: entry.phase)
                entry.error?.let{Text(it,color=MaterialTheme.colorScheme.error)}
                var expanded by remember(entry.id){mutableStateOf(false)}
                if(entry.process.isNotEmpty()){TextButton(onClick={expanded=!expanded}){Text("思考与工具过程")};if(expanded)Text(entry.process)}
                if(entry.phase=="queued"&&m.busy)TextButton(onClick={m.interruptQueued(entry.id)}){Text("停止当前回复并优先发送")}
                Row{
                    if(DeliveryRules.canEdit(entry.phase)){if(entry.files.isEmpty())TextButton(onClick={edit=entry.id;text=entry.text}){Text("编辑")};TextButton(onClick={m.changeQueued(entry.id,move=-1)}){Text("上移")};TextButton(onClick={m.changeQueued(entry.id,move=1)}){Text("下移")};if(entry.phase=="failed")TextButton(onClick={m.retryQueued(entry.id)}){Text("重试")}}
                    if(entry.phase in listOf("queued","failed","unknown","stopped"))TextButton(onClick={m.changeQueued(entry.id,remove=true)}){Text("移除")}
                    if(entry.phase=="unknown")TextButton(onClick={m.resumeDelivery()}){Text("核对结果")}
                };HorizontalDivider()
            }
        }
    }
    edit?.let{id->AlertDialog(onDismissRequest={edit=null},title={Text("编辑消息")},text={OutlinedTextField(text,{text=it})},confirmButton={TextButton(onClick={m.changeQueued(id,text=text);edit=null}){Text("保存")}},dismissButton={TextButton(onClick={edit=null}){Text("取消")}})}
}
@Composable fun CompletionNotificationSetting(){
    val context=LocalContext.current;val preferences=remember{context.getSharedPreferences("settings",0)}
    var enabled by remember{mutableStateOf(preferences.getBoolean("notify.completed",false))}
    val permission=rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()){allowed->enabled=allowed;preferences.edit().putBoolean("notify.completed",allowed).apply()}
    Row{Text("对话完成通知",Modifier.weight(1f));Switch(enabled,{value->if(value&&Build.VERSION.SDK_INT>=33)permission.launch(android.Manifest.permission.POST_NOTIFICATIONS) else{enabled=value;preferences.edit().putBoolean("notify.completed",value).apply()}})}
    Text("应用仍在运行时提示完成；系统暂停或关闭应用后，返回应用会核对回复。",style=MaterialTheme.typography.bodySmall)
}

@Composable fun ReadingSizeSetting(){
    val context=LocalContext.current;val prefs=remember{context.getSharedPreferences("settings",0)};var size by remember{mutableFloatStateOf(prefs.getFloat("reading.size",16f))}
    Column{Text("阅读字号 · ${size.toInt()}");Slider(size,{size=it;prefs.edit().putFloat("reading.size",it).apply()},valueRange=12f..24f,steps=11)}
}
@Composable fun readingSize():Float{
    val context=LocalContext.current;val prefs=remember{context.getSharedPreferences("settings",0)};var size by remember{mutableFloatStateOf(prefs.getFloat("reading.size",16f))}
    DisposableEffect(prefs){val listener=android.content.SharedPreferences.OnSharedPreferenceChangeListener{_,key->if(key=="reading.size")size=prefs.getFloat("reading.size",16f)};prefs.registerOnSharedPreferenceChangeListener(listener);onDispose{prefs.unregisterOnSharedPreferenceChangeListener(listener)}}
    return size.coerceIn(12f,24f)
}

@Composable fun AdvancedPairing(social:SocialModel){
    var open by remember{mutableStateOf(false)};var id by remember{mutableStateOf("")};var token by remember{mutableStateOf("")};var busy by remember{mutableStateOf(false)};var error by remember{mutableStateOf<String?>(null)};val scope=rememberCoroutineScope()
    Column{TextButton(onClick={open=!open}){Text("导入已有 Town 凭据")};if(open){OutlinedTextField(id,{id=it},label={Text("Town ID 或 Being 名")});OutlinedTextField(token,{token=it},label={Text("Town client token")},visualTransformation=androidx.compose.ui.text.input.PasswordVisualTransformation());TextButton(onClick={scope.launch{busy=true;error=null;try{social.importIdentity(id,token.trim());token=""}catch(e:kotlinx.coroutines.CancellationException){throw e}catch(e:Exception){error=e.message}finally{busy=false}}},enabled=!busy&&id.isNotBlank()&&token.isNotBlank()){Text(if(busy)"正在验证…" else "验证并导入")};error?.let{Text(it,color=MaterialTheme.colorScheme.error)}}}
}
