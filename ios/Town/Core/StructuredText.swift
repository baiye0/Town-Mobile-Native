import Foundation
public enum StructuredText {
    private static func valid(_ text:String) -> Bool { guard let data=text.data(using:.utf8) else{return false};return (try? JSONSerialization.jsonObject(with:data,options:.fragmentsAllowed)) != nil }
    public static func detect(_ source:String) -> String? {
        let text=source.trimmingCharacters(in:.whitespacesAndNewlines)
        guard text.first == "{" || text.first == "[" else{return nil}
        if valid(text){return "json"}
        let lines=text.components(separatedBy:.newlines).filter{!$0.trimmingCharacters(in:.whitespaces).isEmpty}
        return lines.count>1 && lines.allSatisfy { line in let t=line.trimmingCharacters(in:.whitespaces);return (t.first == "{" || t.first == "[") && valid(t) } ? "jsonl" : nil
    }
    // Only whitespace changes. Never deserialize/reserialize values or keys.
    public static func formatJSON(_ source:String) -> String? {
        guard valid(source) else{return nil}
        let chars=Array(source.trimmingCharacters(in:.whitespacesAndNewlines));var out="",depth=0,quoted=false,escaped=false,i=0
        func newline()->String { "\n"+String(repeating:"  ",count:max(0,depth)) }
        while i<chars.count {
            let c=chars[i]
            if quoted {out.append(c);if escaped{escaped=false}else if c=="\\"{escaped=true}else if c=="\""{quoted=false}}
            else if c=="\""{quoted=true;out.append(c)}
            else if c.isWhitespace {}
            else if c=="{" || c=="[" {out.append(c);var j=i+1;while j<chars.count && chars[j].isWhitespace{j+=1};if j<chars.count && chars[j] == (c=="{" ? "}" : "]"){out.append(chars[j]);i=j}else{depth+=1;out+=newline()}}
            else if c=="}" || c=="]" {depth-=1;out+=newline();out.append(c)}
            else if c==","{out+=","+newline()}
            else if c==":"{out+=": "}
            else{out.append(c)}
            i+=1
        };return out
    }
}
