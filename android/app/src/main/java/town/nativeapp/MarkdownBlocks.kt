package town.nativeapp

data class MarkdownBlock(val kind:String,val text:String="",val level:Int=0,val label:String="",val rows:List<List<String>> = emptyList())
object MarkdownBlocks {
    private fun cells(line:String):List<String>{
        val result=mutableListOf<String>();val cell=StringBuilder();var escaped=false;var code=false
        for(c in line.trim()){if(escaped){cell.append(c);escaped=false;continue};if(c=='\\'){escaped=true;continue};if(c=='`')code=!code;if(c=='|'&&!code){result.add(cell.toString().trim());cell.clear()}else cell.append(c)}
        result.add(cell.toString().trim());if(result.firstOrNull()=="")result.removeAt(0);if(result.lastOrNull()=="")result.removeAt(result.lastIndex);return result
    }
    fun parse(text:String, imageReferences:String=""):List<MarkdownBlock>{
        StructuredText.detect(text)?.let{return listOf(MarkdownBlock("code",text,label=it))}
        val lines=text.replace("\r\n","\n").split('\n');val blocks=mutableListOf<MarkdownBlock>();val paragraph=mutableListOf<String>();var i=0
        fun flush(){if(paragraph.isNotEmpty()){blocks.add(MarkdownBlock("paragraph",paragraph.joinToString("\n")));paragraph.clear()}}
        while(i<lines.size){
            val line=lines[i];val trimmed=line.trim()
            if(trimmed.isEmpty()){flush();i++;continue}
            if(trimmed.startsWith("```")||trimmed.startsWith("~~~")){flush();val fence=trimmed.take(3);val language=trimmed.drop(3);val code=mutableListOf<String>();i++;while(i<lines.size&&!lines[i].trim().startsWith(fence)){code.add(lines[i]);i++};blocks.add(MarkdownBlock("code",code.joinToString("\n"),label=language));i++;continue}
            if(i+1<lines.size&&line.contains('|')&&Regex("""^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$""").matches(lines[i+1])){flush();val rows=mutableListOf(cells(line));i+=2;while(i<lines.size&&lines[i].contains('|')&&lines[i].isNotBlank()){rows.add(cells(lines[i]));i++};blocks.add(MarkdownBlock("table",rows=rows));continue}
            val heading=Regex("""^(#{1,6})\s+(.+)$""").find(trimmed)
            if(heading!=null){flush();blocks.add(MarkdownBlock("heading",heading.groupValues[2],heading.groupValues[1].length));i++;continue}
            if(Regex("""^(?:[-*_]\s*){3,}$""").matches(trimmed)){flush();blocks.add(MarkdownBlock("rule"));i++;continue}
            if(trimmed.startsWith('>')){flush();blocks.add(MarkdownBlock("quote",trimmed.drop(1).trim()));i++;continue}
            val list=Regex("""^(\s*)([-+*]|[0-9]+[.)])\s+(.+)$""").find(line)
            if(list!=null){flush();var label=if(list.groupValues[2].length==1)"•" else list.groupValues[2];var content=list.groupValues[3];if(content.startsWith("[ ] ")){label="☐";content=content.drop(4)};if(content.lowercase().startsWith("[x] ")){label="☑";content=content.drop(4)};blocks.add(MarkdownBlock("list",content,list.groupValues[1].length/2,label));i++;continue}
            paragraph.add(line);i++
        };flush();return MarkdownImages.expand(blocks, imageReferences)
    }
}
