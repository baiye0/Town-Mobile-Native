package town.nativeapp
object StructuredText {
    // Validation avoids numeric conversion and accepts duplicate keys, like JSON.parse.
    private class Reader(val s:String){
        var i=0
        fun whitespace(){while(i<s.length&&s[i] in " \r\n\t")i++}
        fun take(c:Char):Boolean{whitespace();if(i<s.length&&s[i]==c){i++;return true};return false}
        fun string(){check(take('"'));while(i<s.length){val c=s[i++];if(c=='"')return;check(c.code>=32);if(c=='\\'){check(i<s.length);val escape=s[i++];if(escape=='u'){repeat(4){check(i<s.length&&s[i++].digitToIntOrNull(16)!=null)}}else check(escape in "\"\\/bfnrt")}};error("string")}
        fun value(depth:Int=0){check(depth<256);whitespace();check(i<s.length);when(s[i]){
            '{'->{i++;if(!take('}')){do{string();check(take(':'));value(depth+1)}while(take(','));check(take('}'))}}
            '['->{i++;if(!take(']')){do{value(depth+1)}while(take(','));check(take(']'))}}
            '"'->string()
            else->{val token=Regex("""(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)""").find(s,i);check(token!=null&&token.range.first==i);i=token.range.last+1}
        }}
    }
    private fun valid(s:String)=runCatching{val r=Reader(s);r.value();r.whitespace();r.i==s.length}.getOrDefault(false)
    fun detect(source:String):String?{val t=source.trim();if(!t.startsWith('{')&&!t.startsWith('['))return null;if(valid(t))return "json";val lines=t.lines().filter{it.isNotBlank()};return if(lines.size>1&&lines.all{val l=it.trim();(l.startsWith('{')||l.startsWith('['))&&valid(l)})"jsonl" else null}
    fun formatJSON(source:String):String?{
        if(!valid(source))return null
        val s=source.trim();val out=StringBuilder();var depth=0;var quoted=false;var escaped=false;var i=0
        fun newline()="\n"+"  ".repeat(depth.coerceAtLeast(0))
        while(i<s.length){val c=s[i]
            if(quoted){out.append(c);if(escaped)escaped=false else if(c=='\\')escaped=true else if(c=='"')quoted=false}
            else when{c=='"'->{quoted=true;out.append(c)};c.isWhitespace()->{};c=='{'||c=='['->{out.append(c);var j=i+1;while(j<s.length&&s[j].isWhitespace())j++;if(j<s.length&&s[j]==if(c=='{')'}' else ']'){out.append(s[j]);i=j}else{depth++;out.append(newline())}};c=='}'||c==']'->{depth--;out.append(newline()).append(c)};c==','->out.append(',').append(newline());c==':'->out.append(": ");else->out.append(c)}
            i++
        };return out.toString()
    }
}
