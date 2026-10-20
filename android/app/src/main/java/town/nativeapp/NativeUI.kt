package town.nativeapp

import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.*

object NativeUI {
    val types=setOf("stack","row","grid","box","split","section","card","hero","callout","heading","text","metric","badge","divider","input","number","slider","stepper","toggle","select","segmented","choice","button","table","facts","chart","breakdown","list","checklist","timeline","progress")
    const val context="\n\n[客户端 Intelligent UI Beta 上下文]\n用户已开启智能 UI。本条可用 intelligent-ui 代码围栏输出 JSON v1：{\"version\":1,\"title\":\"标题\",\"state\":{\"count\":2},\"body\":[{\"id\":\"countInput\",\"type\":\"stepper\",\"label\":\"数量\",\"bind\":\"count\",\"min\":1,\"max\":20}]}。支持 stack,row,grid,box,split,section,card,hero,callout,heading,text,metric,badge,divider,input,number,slider,stepper,toggle,select,segmented,choice,button,table,facts,chart,breakdown,list,checklist,timeline,progress。value 可为标量、{state:状态名}、{op:add/mul/sub/div/min/max/round/concat/eq/lt/gt/if/not/and/or/fixed/pow,args:[表达式]}。select/segmented 使用 options 字符串数组，choice/list/checklist/timeline 使用 items:[{id,label,description?,bind?}]；table/chart/facts 用 columns 和 rows。button.action 支持 reset/copy/continue/set；set 使用 changes；continue 将选择放入草稿，由用户发送。仅使用已声明 bind；节点唯一 id。窄屏纵向布局。不支持 app、diagram、tabs、图片或跨轮 patch；修改请输出独立的新完整界面。\n[/客户端 Intelligent UI Beta 上下文]"
    fun decode(source:String):JSONObject{
        require(source.toByteArray().size<=200000){"交互界面过大"}
        val plain=runCatching{JSONObject(source)}.getOrNull()
        val document=if(plain?.optInt("version")==1)plain else{
            var title="";val state=JSONObject();val nodes=linkedMapOf<String,JSONObject>();val parents=mutableMapOf<String,String>();var begun=false;var committed=false;var lastSeq=-1
            for(line in source.lines().filter{it.isNotBlank()}){
                val record=JSONObject(line);if(record.has("seq")){val seq=record.getInt("seq");if(seq<=lastSeq)continue;lastSeq=seq};require(!committed)
                when(record.optString("op")){
                    "begin"->{require(!begun&&record.optInt("version")==2&&record.optString("mode")!="patch"&&!record.has("baseRevision")){"此界面需要桌面端的跨轮更新能力"};begun=true;title=record.optString("title")}
                    "state"->{require(begun);state.put(record.getString("key"),record.opt("initial"))}
                    "node"->{require(begun&&nodes.size<200);val node=record.getJSONObject("node");val id=node.getString("id");nodes[id]=node;record.nullString("parent")?.let{parents[id]=it} ?: parents.remove(id)}
                    "commit"->{require(begun);committed=true}
                    else->error("无效交互事件")
                }
            }
            require(begun&&committed){"交互界面尚未生成完成"};require(parents.values.all{nodes.containsKey(it)})
            val visiting=mutableSetOf<String>();val visited=mutableSetOf<String>()
            fun build(id:String,depth:Int):JSONObject{require(depth<=12&&visiting.add(id));val node=JSONObject(nodes.getValue(id).toString());val children=node.optJSONArray("children") ?: JSONArray();nodes.keys.filter{parents[it]==id}.forEach{children.put(build(it,depth+1))};if(children.length()>0)node.put("children",children);visiting.remove(id);visited.add(id);return node}
            val body=JSONArray(nodes.keys.filter{it !in parents}.map{build(it,0)});require(visited.size==nodes.size)
            JSONObject().put("version",1).put("title",title).put("state",state).put("body",body)
        }
        require(document.getString("title").length<=200);val state=document.getJSONObject("state");require(state.length()<=50&&state.keys().asSequence().all{val v=state.get(it);v is String||v is Number||v is Boolean||v==JSONObject.NULL})
        val ids=mutableSetOf<String>()
        fun validate(nodes:JSONArray,depth:Int){require(depth<=12);for(i in 0 until nodes.length()){
            val node=nodes.getJSONObject(i);val id=node.getString("id");val type=node.getString("type");require(DeliveryRules.safeID(id)&&ids.add(id)&&ids.size<=200&&type in types){"包含移动端尚不支持的交互组件，已保留源码"}
            node.nullString("bind")?.let{require(state.has(it))};if(type in listOf("number","slider","stepper")){val lo=node.optDouble("min",0.0);val hi=node.optDouble("max",100.0);val step=node.optDouble("step",1.0);require(lo.isFinite()&&hi.isFinite()&&hi>lo&&abs(lo)<=1e12&&abs(hi)<=1e12&&step.isFinite()&&step>0)}
            require((node.optJSONArray("rows")?.length() ?: 0)<=500&&(node.optJSONArray("items")?.length() ?: 0)<=200);validate(node.optJSONArray("children") ?: JSONArray(),depth+1)
        }}
        validate(document.getJSONArray("body"),0);return document
    }
    fun display(value:Any?):String=if(value==null||value==JSONObject.NULL)"" else value.toString()
    fun evaluate(expression:Any?,state:Map<String,Any>,depth:Int=0):Any{
        if(depth>=20)return "表达式过深";if(expression !is JSONObject)return expression ?: ""
        expression.nullString("state")?.let{return state[it] ?: ""}
        val args=expression.optJSONArray("args") ?: JSONArray();if(args.length()>20)return "表达式过长"
        val values=(0 until args.length()).map{evaluate(args.opt(it),state,depth+1)}
        fun v(i:Int)=values.getOrNull(i) ?: ""
        fun n(i:Int)=(v(i) as? Number)?.toDouble() ?: 0.0
        val numbers=values.map{(it as? Number)?.toDouble() ?: 0.0}
        val result:Any=when(expression.optString("op")){
            "add"->numbers.sum();"mul"->numbers.fold(1.0){a,b->a*b};"sub"->n(0)-n(1);"div"->if(n(1)==0.0)0.0 else n(0)/n(1);"pow"->n(0).pow(n(1));"min"->numbers.minOrNull() ?: 0.0;"max"->numbers.maxOrNull() ?: 0.0;"round"->round(n(0));"fixed"->String.format(java.util.Locale.ROOT,"%.${n(1).toInt().coerceIn(0,10)}f",n(0));"concat"->values.joinToString(""){display(it)};"eq"->v(0)==v(1);"lt"->n(0)<n(1);"gt"->n(0)>n(1);"not"->v(0)!=true;"and"->values.all{it==true};"or"->values.any{it==true};"if"->if(v(0)==true)v(1) else v(2);else->"不支持的表达式"
        };return if(result is Double&&!result.isFinite())"数值超出范围" else result
    }
}
