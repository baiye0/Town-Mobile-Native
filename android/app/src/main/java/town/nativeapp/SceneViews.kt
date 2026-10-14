package town.nativeapp
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp

@Composable fun SceneDialog(mode:String,m:TownModel,close:()->Unit){
    var name by remember { mutableStateOf("") };var id by remember { mutableStateOf("") };var error by remember { mutableStateOf<String?>(null) }
    val clipboard=LocalClipboardManager.current
    val details=mode=="details";val bind=mode=="bind"
    AlertDialog(onDismissRequest=close,title={Text(if(details)"当前场景" else if(bind)"绑定已有场景" else "新建场景")},text={Column(verticalArrangement=Arrangement.spacedBy(16.dp)){
        if(details){Text(m.current?.title ?: "场景");Text("场景 ID");Text(m.selected ?: "");Text("客户端");Text("being-android/0.2");TextButton(onClick={clipboard.setText(AnnotatedString(m.selected ?: ""))}){Text("复制场景 ID")}}
        else {if(bind)OutlinedTextField(id,{id=it},label={Text("场景 ID")},singleLine=true);OutlinedTextField(name,{name=it},label={Text("场景名称")},singleLine=true);error?.let{Text(it,color=MaterialTheme.colorScheme.error)}}
    }},confirmButton={TextButton(onClick={if(details)close() else runCatching{m.createScene(name,if(bind)id.trim() else null)}.onSuccess{close()}.onFailure{error=it.message}},enabled=details||(!m.busy&&name.isNotBlank()&&(!bind||id.isNotBlank()))){Text(if(details)"完成" else if(bind)"绑定并进入" else "创建并进入")}},dismissButton={if(!details)TextButton(onClick=close){Text("取消")}})
}
