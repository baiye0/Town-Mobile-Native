package town.nativeapp

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** One fixed header owns sync/run feedback. A status change never resizes the conversation. */
@Composable internal fun ChatHeader(model:TownModel,settings:()->Unit) {
    var detail by remember { mutableStateOf<String?>(null) }
    val error=model.notice ?: model.historyNotice
    val status=when {
        error!=null->error
        model.historyLoading->"正在同步历史…"
        model.busy->model.activity.ifEmpty { "正在等待回复…" }
        model.connection==null->"未连接"
        else->model.sbsStatus
    }
    Column(horizontalAlignment=Alignment.CenterHorizontally) {
        Text(model.current?.title ?: "Being",Modifier.clickable(onClick=settings),fontWeight=FontWeight.Medium,
            fontSize=19.sp,maxLines=1,overflow=TextOverflow.Ellipsis)
        Box(Modifier.height(20.dp).fillMaxWidth().clickable(enabled=error!=null){detail=error},contentAlignment=Alignment.Center) {
            Text(status,fontSize=11.sp,maxLines=1,overflow=TextOverflow.Ellipsis,
                color=if(error!=null)MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    detail?.let { text -> AlertDialog(onDismissRequest={detail=null},title={Text("对话状态")},text={Text(text)},
        confirmButton={TextButton(onClick={detail=null}){Text("知道了")}}) }
}

@Composable internal fun ChatRefreshAction(model:TownModel) {
    IconButton(onClick={model.history()},enabled=model.connection!=null&&!model.historyLoading) {
        Box(Modifier.size(24.dp),contentAlignment=Alignment.Center) {
            if(model.historyLoading)CircularProgressIndicator(Modifier.size(20.dp).semantics{contentDescription="正在同步历史"},strokeWidth=1.5.dp)
            else Icon(Icons.Outlined.Refresh,"刷新历史")
        }
    }
}
