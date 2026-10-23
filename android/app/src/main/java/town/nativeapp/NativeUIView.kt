package town.nativeapp

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

val LocalUIContext=staticCompositionLocalOf{""}
val LocalUIContinue=staticCompositionLocalOf<(String)->Unit>{{}}
@Composable fun NativeUIView(source:String){
    val context=LocalContext.current;val scope=LocalUIContext.current;val continuation=LocalUIContinue.current;val clipboard=LocalClipboardManager.current
    val key=remember(scope,source){MessageDigest.getInstance("SHA-256").digest((scope+"|"+source).toByteArray()).joinToString(""){"%02x".format(it)}}
    val prefs=remember{context.getSharedPreferences("native-ui",0)}
    val decoded=remember(source){runCatching{NativeUI.decode(source)}};val document=decoded.getOrNull()
    var values by remember(key){mutableStateOf<Map<String,Any>>(buildMap{document?.getJSONObject("state")?.let{s->s.keys().forEach{put(it,s.get(it))}};runCatching{JSONObject(prefs.getString(key,"{}")!!)}.getOrNull()?.let{s->s.keys().forEach{if(containsKey(it)||it.startsWith("check."))put(it,s.get(it))}}})}
    var showSource by remember{mutableStateOf(false)}
    fun save(next:Map<String,Any>){values=next;prefs.edit().putString(key,JSONObject(next).toString()).apply()}
    fun proceed(){if(document!=null){val snapshot=JSONObject().put("title",document.optString("title")).put("values",JSONObject(values)).put("document",document).toString();if(snapshot.length<=100000)continuation("请根据当前选择继续：\n$snapshot")}}
    Surface(tonalElevation=0.dp,shadowElevation=0.dp,color=MaterialTheme.colorScheme.surfaceVariant,shape=MaterialTheme.shapes.medium,modifier=Modifier.fillMaxWidth()){
        Column(Modifier.fillMaxWidth().padding(16.dp),verticalArrangement=Arrangement.spacedBy(16.dp)){
        if(document!=null&&!showSource){
            Text(document.optString("title"),style=MaterialTheme.typography.titleMedium,modifier=Modifier.fillMaxWidth())
            document.rows("body").forEach{NativeUINode(it,values,{k,v->save(values+(k to v))},{action,node->when(action){"reset"->{val s=document.getJSONObject("state");save(s.keys().asSequence().associateWith{s.get(it)})};"copy"->clipboard.setText(AnnotatedString(NativeUI.display(NativeUI.evaluate(node.opt("value"),values))));"set"->{val s=node.optJSONObject("changes") ?: JSONObject();val changes=s.keys().asSequence().filter{it in values}.associateWith{NativeUI.evaluate(s.get(it),values)};save(values+changes)};else->proceed()}})}
            Button(onClick={proceed()},modifier=Modifier.fillMaxWidth()){Text("用当前选择继续")}
        }
        decoded.exceptionOrNull()?.let{Text(it.message ?: "无法读取界面",style=MaterialTheme.typography.bodySmall)}
        TextButton(onClick={showSource=!showSource}){Text(if(showSource)"查看界面" else "查看源码")}
        if(showSource||document==null)SelectionContainer{Text(source,Modifier.horizontalScroll(rememberScrollState()),style=MaterialTheme.typography.bodySmall)}
    }}
}
@Composable private fun NativeUINode(node:JSONObject,values:Map<String,Any>,set:(String,Any)->Unit,action:(String,JSONObject)->Unit){
    if(node.has("when")&&NativeUI.evaluate(node.get("when"),values)==false)return
    val type=node.optString("type");val label=node.optString("label");val bind=node.optString("bind");val id=node.optString("id")
    val lo=node.optDouble("min",0.0);val hi=node.optDouble("max",100.0);val step=node.optDouble("step",1.0)
    fun value(v:Any?)=NativeUI.display(NativeUI.evaluate(v,values))
    val number=((values[bind] as? Number)?.toDouble() ?: lo).coerceIn(lo,hi)
    Column(Modifier.fillMaxWidth(),verticalArrangement=Arrangement.spacedBy(12.dp)){
        when(type){
            "divider"->HorizontalDivider()
            "toggle"->Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically){Text(label,Modifier.weight(1f));Switch(values[bind]==true,{set(bind,it)})}
            "input"->OutlinedTextField(values[bind] as? String ?: "",{set(bind,it.take(10000))},label={Text(label)},modifier=Modifier.fillMaxWidth())
            "number","stepper"->Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically){Text(label+" · "+value(JSONObject().put("state",bind)),Modifier.weight(1f));TextButton(onClick={set(bind,(number-step).coerceIn(lo,hi))}){Text("−")};TextButton(onClick={set(bind,(number+step).coerceIn(lo,hi))}){Text("＋")}}
            "slider"->{Text(label+" · "+value(node.opt("value") ?: JSONObject().put("state",bind)));Slider(number.toFloat(),{set(bind,(lo+kotlin.math.round((it-lo)/step)*step).coerceIn(lo,hi))},valueRange=lo.toFloat()..hi.toFloat())}
            "select","segmented","choice"->{Text(label,style=MaterialTheme.typography.labelLarge);val options=node.optJSONArray("options") ?: JSONArray();val items=(0 until options.length()).map{JSONObject().put("id",options.getString(it)).put("label",options.getString(it))}+node.rows("items");items.forEach{item->Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically){RadioButton(values[bind]==item.optString("id"),{set(bind,item.optString("id"))});Column{Text(item.optString("label"));item.nullString("description")?.let{Text(it,style=MaterialTheme.typography.bodySmall)}}}}}
            "button"->TextButton(onClick={action(node.optString("action"),node)}){Text(label)}
            "list","checklist","timeline"->{if(label.isNotEmpty())Text(label,style=MaterialTheme.typography.titleSmall);node.rows("items").forEachIndexed{index,item->val key=item.nullString("bind") ?: "check.$id.${item.optString("id",index.toString())}";Row{if(type=="checklist"||type=="timeline"&&node.optBoolean("checkable",true))Checkbox(values[key]==true,{set(key,it)});Column{Text(item.optString("label"));item.nullString("description")?.let{Text(it,style=MaterialTheme.typography.bodySmall)}}}}}
            "chart","breakdown"->{
                if(label.isNotEmpty())Text(label,style=MaterialTheme.typography.titleSmall)
                val rows=node.optJSONArray("rows") ?: JSONArray()
                val data=(0 until rows.length()).mapNotNull{index->val row=rows.optJSONArray(index) ?: return@mapNotNull null;if(row.length()<2)return@mapNotNull null;value(row.opt(0)) to ((NativeUI.evaluate(row.opt(1),values) as? Number)?.toDouble() ?: 0.0)}
                val low=minOf(0.0,data.minOfOrNull{it.second} ?: 0.0);val high=maxOf(1.0,data.maxOfOrNull{it.second} ?: 1.0);val accent=MaterialTheme.colorScheme.primary
                androidx.compose.foundation.Canvas(Modifier.fillMaxWidth().height(200.dp)){
                    val width=size.width/maxOf(1,data.size);fun y(v:Double)=size.height-((v-low)/(high-low)*size.height).toFloat()
                    if(node.optString("variant")=="line")data.zipWithNext().forEachIndexed{index,pair->drawLine(accent,androidx.compose.ui.geometry.Offset((index+0.5f)*width,y(pair.first.second)),androidx.compose.ui.geometry.Offset((index+1.5f)*width,y(pair.second.second)),strokeWidth=3.dp.toPx())}
                    else data.forEachIndexed{index,pair->val top=minOf(y(pair.second),y(0.0));drawRect(accent,androidx.compose.ui.geometry.Offset(index*width+2,top),androidx.compose.ui.geometry.Size(maxOf(1f,width-4),kotlin.math.abs(y(pair.second)-y(0.0))))}
                }
                data.forEach{(label,value)->Text("$label · $value",style=MaterialTheme.typography.bodySmall)}
            }
            "table","facts"->{if(label.isNotEmpty())Text(label,style=MaterialTheme.typography.titleSmall);Column(Modifier.horizontalScroll(rememberScrollState())){val columns=node.optJSONArray("columns") ?: JSONArray();Row{for(i in 0 until columns.length())Text(columns.optString(i),Modifier.width(130.dp),style=MaterialTheme.typography.titleSmall)};val rows=node.optJSONArray("rows") ?: JSONArray();for(i in 0 until rows.length()){val row=rows.optJSONArray(i) ?: JSONArray();Row{for(j in 0 until row.length())Text(value(row.opt(j)),Modifier.width(130.dp))}}}}
            "progress"->{Text(label);val v=(NativeUI.evaluate(node.opt("value"),values) as? Number)?.toDouble() ?: 0.0;LinearProgressIndicator(progress={((v-lo)/maxOf(1.0,hi-lo)).coerceIn(0.0,1.0).toFloat()})}
            else->{if(label.isNotEmpty())Text(label,style=MaterialTheme.typography.titleSmall);if(node.has("value")){if(type=="metric")Text(value(node.get("value")),style=MaterialTheme.typography.headlineSmall) else MarkdownText(value(node.get("value")))};node.rows("children").forEach{NativeUINode(it,values,set,action)}}
        }
    }
}
