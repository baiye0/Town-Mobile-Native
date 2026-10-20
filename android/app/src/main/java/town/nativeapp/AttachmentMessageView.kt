package town.nativeapp

import android.app.Application
import android.content.Intent
import android.graphics.BitmapFactory
import androidx.core.content.FileProvider
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import kotlinx.coroutines.*
import org.json.JSONObject
import java.io.File

@Composable fun AttachmentMessageView(message:Message,m:TownModel,color:Color){
    val refs=remember(message.text){Regex("(?m)^\\[attachment-message:v1:(msg_[a-f0-9]{64}(?:,msg_[a-f0-9]{64})*)\\]\\r?$").findAll(message.text).lastOrNull()?.groupValues?.get(1)?.split(',') ?: emptyList()}
    var files by remember(message.id,message.files){mutableStateOf(message.files ?: emptyList())};var text by remember(message.id){mutableStateOf<String?>(null)};var remoteImages by remember(message.id){mutableStateOf<Map<String,androidx.compose.ui.graphics.ImageBitmap>>(emptyMap())}
    var error by remember{mutableStateOf<String?>(null)};var busy by remember{mutableStateOf(false)};var parsed by remember{mutableStateOf<String?>(null)};var revision by remember{mutableIntStateOf(0)};var previewFile by remember{mutableStateOf<File?>(null)}
    val context=LocalContext.current;val scope=rememberCoroutineScope()
    LaunchedEffect(m.connection?.endpoint,refs,revision){
        if(refs.isEmpty())return@LaunchedEffect;val c=m.connection ?: return@LaunchedEffect
        try{val parts=mutableListOf<PendingAttachment>();val texts=mutableListOf<String>()
            val localFiles=files.associateBy{it.attachmentID}
            for(id in refs){val data=m.attachmentJSON(c,"/api/attachment-messages/$id");check(data.optInt("version")==1&&data.optString("message_id")==id&&data.nullString("scene_id")==message.sceneID)
                for(part in data.rows("parts")){if(part.optString("type")=="text")texts.add(part.optString("text")) else{val aid=part.optString("attachment_id");check(DeliveryRules.safeID(aid));val local=localFiles[aid];parts.add(PendingAttachment(id=local?.id ?: aid,name=part.optString("name",local?.name ?: "附件"),mime=part.optString("mime",local?.mime ?: "application/octet-stream"),path=local?.path ?: "",size=part.optLong("size",local?.size ?: 0),attachmentID=aid,resultID=part.nullString("parse_result_id")?.takeIf{DeliveryRules.safeID(it)}))}}
            };if(m.connection==c){files=parts;text=texts.joinToString("\n\n");error=null}
        }catch(e:CancellationException){throw e}catch(_:Exception){error="附件详情读取失败，原记录已保留。"}
    }
    LaunchedEffect(m.connection?.endpoint,files.joinToString(","){"${it.id}|${it.attachmentID ?: ""}|${it.path}"}){
        val c=m.connection ?: return@LaunchedEffect
        val loaded=mutableMapOf<String,androidx.compose.ui.graphics.ImageBitmap>()
        for(file in files){
            if(file.path.isEmpty()&&file.mime.startsWith("image/")&&file.size<=50L*1024*1024&&file.attachmentID!=null){
                runCatching{val local=m.downloadAttachment(c,file);attachmentThumbnail(local.path)?.let{loaded[file.id]=it};local.delete()}
            }
        }
        if(m.connection==c&&loaded.isNotEmpty())remoteImages=remoteImages+loaded
    }
    Column(verticalArrangement=Arrangement.spacedBy(8.dp)){
        // The user prompt is rendered by Chat as its own bubble, matching Muse.
        // Keep parsed attachment text in the assistant attachment card only.
        if(message.role != "user") CompositionLocalProvider(LocalUIContext provides "${m.connection?.endpoint}|${message.sceneID}",LocalUIContinue provides {value->m.draft+=(if(m.draft.isEmpty())"" else "\n\n")+value}){MarkdownText(text ?: if(refs.isEmpty())message.text.replace(NativeUI.context,"") else "附件消息",textColor=color)}
        files.forEach{file->
            val localEntry = m.outbox.firstOrNull { "local:${it.id}:user" == message.kind }
            val sourceFile = if(file.path.isNotEmpty()) file else message.files?.firstOrNull { it.attachmentID == file.attachmentID && it.path.isNotEmpty() } ?: file
            val bitmap = remember(sourceFile.path) {
                if (sourceFile.path.isNotEmpty() && sourceFile.mime.startsWith("image/")) attachmentThumbnail(File(m.getApplication<Application>().filesDir, "attachments/${sourceFile.path}").path) else null
            }
            val displayedBitmap = bitmap ?: remoteImages[file.id]
            val openFile: () -> Unit = { scope.launch {
                busy=true;error=null
                try {
                    val c=m.connection ?: return@launch
                    val local=m.downloadAttachment(c,sourceFile)
                    if(m.connection!=c)return@launch
                    if(file.mime.startsWith("image/")) previewFile=local
                    else {
                        val uri=FileProvider.getUriForFile(context,context.packageName+".files",local)
                        context.startActivity(Intent.createChooser(Intent(Intent.ACTION_VIEW).setDataAndType(uri,file.mime).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),"预览附件"))
                    }
                } catch(e:android.content.ActivityNotFoundException) { error="未安装可打开此文件的应用，可查看解析文字。" }
                catch(e:Exception) { if(e is CancellationException)throw e;error=e.message }
                finally { busy=false }
            }; Unit }
            when {
                file.mime.startsWith("image/") -> {
                    if(displayedBitmap!=null) Image(displayedBitmap,contentDescription="查看图片",modifier=Modifier.widthIn(max=260.dp).heightIn(max=240.dp).clip(RoundedCornerShape(12.dp)).clickable(enabled=!busy,onClick=openFile),contentScale=ContentScale.Fit)
                    else Surface(Modifier.size(220.dp,160.dp).clickable(enabled=!busy,onClick=openFile),shape=RoundedCornerShape(12.dp),color=color.copy(alpha=.12f)) {
                        Box(contentAlignment=androidx.compose.ui.Alignment.Center) { Text("图片",color=color) }
                    }
                }
                file.mime.startsWith("audio/") -> key(m.connection?.endpoint,file.id) { AttachmentAudioView(file,sourceFile,m,color) }
                else -> {
                    TextButton(onClick=openFile,enabled=!busy){Text(file.name,color=color)}
                    localEntry?.let { entry ->
                        Text(if(file.resultID!=null) "解析完成" else if(file.attachmentID!=null) (if(entry.phase=="preparing") "正在解析" else "已上传，等待解析") else if(entry.phase=="preparing") "正在上传" else "等待上传",style=MaterialTheme.typography.labelSmall,color=color.copy(alpha=.72f))
                    }
                    if(file.attachmentID!=null&&file.resultID!=null)TextButton(onClick={scope.launch{busy=true;try{val c=m.connection ?: return@launch;val result=m.parsedText(c,file.attachmentID!!,file.resultID!!);if(m.connection==c)parsed=result}catch(e:Exception){if(e is CancellationException)throw e;error=e.message}finally{busy=false}}},enabled=!busy){Text("解析文字",color=color)}
                }
            }
        }
        var expanded by remember{mutableStateOf(false)}
        if(message.role!="user"&&!message.process.isNullOrBlank()){TextButton(onClick={expanded=!expanded}){Text("思考与工具过程",color=color)};if(expanded)Text(message.process,style=MaterialTheme.typography.bodySmall,color=color)}
        if(busy)CircularProgressIndicator(Modifier.size(20.dp))
        error?.let{Text(it,style=MaterialTheme.typography.bodySmall,color=color);TextButton(onClick={revision++}){Text("重新读取附件",color=color)}}
    }
    previewFile?.let { file ->
        Dialog(onDismissRequest={previewFile=null}) {
            Surface(Modifier.fillMaxWidth().padding(16.dp), shape=RoundedCornerShape(20.dp), color=Color.Black) {
                Column(Modifier.padding(12.dp), horizontalAlignment=androidx.compose.ui.Alignment.CenterHorizontally) {
                    val image = remember(file.path) { BitmapFactory.decodeFile(file.path)?.asImageBitmap() }
                    if (image != null) Image(image, contentDescription=file.name, modifier=Modifier.fillMaxWidth().heightIn(max=620.dp), contentScale=ContentScale.Fit)
                    else Text("无法预览此图片", color=Color.White)
                    TextButton(onClick={previewFile=null}) { Text("关闭", color=Color.White) }
                }
            }
        }
    }
    parsed?.let{value->AlertDialog(onDismissRequest={parsed=null},title={Text("解析文字")},text={Column(Modifier.verticalScroll(rememberScrollState())){MarkdownText(value)}},confirmButton={TextButton(onClick={parsed=null}){Text("完成")}})}
}

private fun attachmentThumbnail(path: String): androidx.compose.ui.graphics.ImageBitmap? {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(path, bounds)
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
    val options = BitmapFactory.Options()
    while (maxOf(bounds.outWidth, bounds.outHeight) / options.inSampleSize.coerceAtLeast(1) > 1024) {
        options.inSampleSize = options.inSampleSize.coerceAtLeast(1) * 2
    }
    return BitmapFactory.decodeFile(path, options)?.asImageBitmap()
}
