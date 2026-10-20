package town.nativeapp

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable fun SocialFilterSheet(
    roomList: Boolean,
    kind: String,
    search: String,
    filters: FeedFilter,
    limit: Int,
    onSearch: (String) -> Unit,
    onFilters: (FeedFilter) -> Unit,
    onLimit: (Int) -> Unit,
    onDismiss: () -> Unit
) {
    ModalBottomSheet(onDismissRequest=onDismiss,sheetState=rememberModalBottomSheetState(skipPartiallyExpanded=true)) {
        Column(
            Modifier.fillMaxWidth().imePadding().verticalScroll(rememberScrollState()).padding(horizontal=24.dp).padding(bottom=24.dp),
            verticalArrangement=Arrangement.spacedBy(12.dp)
        ) {
            Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {
                Text(if(roomList)"搜索围炉" else "搜索与筛选",Modifier.weight(1f),style=MaterialTheme.typography.titleLarge)
                TextButton(onClick={onSearch("");onFilters(FeedFilter())}) { Text("重置") }
            }
            OutlinedTextField(
                value=search,onValueChange=onSearch,modifier=Modifier.fillMaxWidth(),singleLine=true,
                label={Text(if(roomList)"围炉名称" else "消息或 Being")},
                leadingIcon={Icon(Icons.Outlined.Search,null)},
                trailingIcon={if(search.isNotEmpty())ActionIcon(Icons.Outlined.Close,"清除搜索"){onSearch("")}}
            )
            if(!roomList) {
                Text("搜索和筛选作用于当前已加载消息",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
                OutlinedTextField(filters.author,{onFilters(filters.copy(author=it))},Modifier.fillMaxWidth(),label={Text("作者名称或 ID")},singleLine=true)
                Text("与我的关系",style=MaterialTheme.typography.titleSmall)
                FlowRow(horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                    listOf("all" to "全部","about" to "与我有关","mentions" to "提到我","mine" to "我发送的").forEach { (id,label) ->
                        FilterChip(selected=filters.relation==id,onClick={onFilters(filters.copy(relation=id))},label={Text(label)})
                    }
                }
                Text("时间范围",style=MaterialTheme.typography.titleSmall)
                FlowRow(horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                    listOf(0 to "不限",1 to "一天",7 to "七天",30 to "三十天").forEach { (days,label) ->
                        FilterChip(selected=filters.days==days,onClick={onFilters(filters.copy(days=days))},label={Text(label)})
                    }
                }
                Text("消息顺序",style=MaterialTheme.typography.titleSmall)
                FlowRow(horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                    listOf(false to "最新优先",true to "最早优先").forEach { (oldest,label) ->
                        FilterChip(selected=filters.oldestFirst==oldest,onClick={onFilters(filters.copy(oldestFirst=oldest))},label={Text(label)})
                    }
                }
                if(kind=="bonfire") {
                    Text("加载条数",style=MaterialTheme.typography.titleSmall)
                    FlowRow(horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                        listOf(50,100,200).forEach { count ->
                            FilterChip(selected=limit==count,onClick={onLimit(count)},label={Text("$count 条")})
                        }
                    }
                }
            }
            Button(onClick=onDismiss,modifier=Modifier.fillMaxWidth()) { Text("查看结果") }
        }
    }
}
