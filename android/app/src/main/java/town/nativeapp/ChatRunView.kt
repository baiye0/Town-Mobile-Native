package town.nativeapp

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

@Composable fun ChatRunView(process:String,activity:String,isActive:Boolean) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(isActive){if(!isActive)expanded=false}
    Column(Modifier.fillMaxWidth().padding(vertical=10.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth().clickable(enabled=process.isNotEmpty()){expanded=!expanded}
            .semantics{stateDescription=if(expanded)"已展开" else "已折叠"}.heightIn(min=36.dp),
            verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(8.dp)) {
            if(isActive)CircularProgressIndicator(Modifier.size(14.dp),strokeWidth=1.5.dp)
            else Icon(AppIcons.List,null,Modifier.size(16.dp),tint=MaterialTheme.colorScheme.onSurfaceVariant)
            Text(if(isActive)activity.ifEmpty{"思考中"} else "思考与工具过程",Modifier.weight(1f),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
            if(process.isNotEmpty())Icon(if(expanded)Icons.Outlined.ExpandMore else AppIcons.Chevron,if(expanded)"收起过程" else "展开过程",Modifier.size(16.dp))
        }
        if(expanded)SelectionContainer{Text(process,style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}
        else if(isActive&&process.isNotEmpty())Text(process.takeLast(240).trim(),maxLines=3,overflow=TextOverflow.Ellipsis,style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
