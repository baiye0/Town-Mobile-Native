package town.nativeapp
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private fun inlineText(value:String)=buildAnnotatedString {
    val pattern=Regex("""\*\*(.+?)\*\*|`([^`]+)`|\[([^]]+)\]\((https?://[^ )]+)\)""")
    var last=0
    pattern.findAll(value).forEach{m->
        append(value.substring(last,m.range.first))
        when{m.groups[1]!=null->withStyle(SpanStyle(fontWeight=FontWeight.Bold)){append(m.groupValues[1])}
            m.groups[2]!=null->withStyle(SpanStyle(fontFamily=FontFamily.Monospace)){append(m.groupValues[2])}
            else->{pushLink(androidx.compose.ui.text.LinkAnnotation.Url(m.groupValues[4]));append(m.groupValues[3]);pop()}}
        last=m.range.last+1
    };append(value.substring(last))
}
@Composable fun MarkdownText(text:String,previewMarkdownCode:Boolean=true,textColor:androidx.compose.ui.graphics.Color=MaterialTheme.colorScheme.onSurface){
    val clipboard=LocalClipboardManager.current
    val blocks=androidx.compose.runtime.remember(text){MarkdownBlocks.parse(text)}
    Column(verticalArrangement=Arrangement.spacedBy(8.dp)){
        blocks.forEach{b->when(b.kind){
            "rule"->HorizontalDivider()
            "code"->NativeCodeBlock(b.text,b.label,previewMarkdownCode)
            "table"->Column(Modifier.horizontalScroll(rememberScrollState())){b.rows.forEachIndexed{index,row->
                Row{row.forEach{cell->SelectionContainer{Text(inlineText(cell),Modifier.width(150.dp).background(if(index==0)MaterialTheme.colorScheme.surfaceVariant else MaterialTheme.colorScheme.surface).padding(10.dp),fontSize=13.sp,fontWeight=if(index==0)FontWeight.SemiBold else FontWeight.Normal)}}};HorizontalDivider()
            }}
            "list"->Row(Modifier.padding(start=(b.level*16).dp)){Text(b.label,Modifier.width(24.dp),color=textColor);SelectionContainer{Text(inlineText(b.text),fontSize=16.sp,lineHeight=25.sp,color=textColor)}}
            "quote"->Row{Box(Modifier.width(3.dp).heightIn(min=28.dp).background(MaterialTheme.colorScheme.outline));SelectionContainer{Text(inlineText(b.text),Modifier.padding(start=12.dp),fontSize=16.sp,lineHeight=25.sp,color=textColor.copy(alpha=0.8f))}}
            else->SelectionContainer{Text(inlineText(b.text),color=textColor,fontSize=(if(b.kind=="heading")when(b.level){1->20;2->18;else->16}else 16).sp,fontWeight=if(b.kind=="heading")FontWeight.SemiBold else FontWeight.Normal,lineHeight=25.sp)}
        }}
    }
}

@Composable private fun NativeCodeBlock(text:String,language:String,allowPreview:Boolean){
    val clipboard=LocalClipboardManager.current
    val lang=language.ifEmpty{StructuredText.detect(text) ?: "text"}.lowercase()
    val markdown=allowPreview&&lang in listOf("markdown","md","mkdown","mkd")
    val formatted=remember(text,lang){if(lang=="json")StructuredText.formatJSON(text) else null}
    var source by remember{mutableStateOf(false)};var pretty by remember{mutableStateOf(false)}
    val display=if(pretty)formatted ?: text else text
    Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceVariant,RoundedCornerShape(10.dp)).padding(12.dp)){
        Row(verticalAlignment=androidx.compose.ui.Alignment.CenterVertically){
            Text(lang.uppercase(),Modifier.weight(1f),fontSize=10.sp)
            if(markdown)TextButton(onClick={source=!source}){Text(if(source)"预览" else "源码",fontSize=12.sp)}
            else if(formatted!=null)TextButton(onClick={pretty=!pretty}){Text(if(pretty)"源码" else "格式化",fontSize=12.sp)}
            TextButton(onClick={clipboard.setText(AnnotatedString(display))}){Text("复制代码",fontSize=12.sp)}
        }
        if(markdown&&!source)MarkdownText(text,false)
        else SelectionContainer{Text(display,Modifier.horizontalScroll(rememberScrollState()),fontFamily=FontFamily.Monospace,fontSize=13.sp,lineHeight=21.sp)}
    }
}
