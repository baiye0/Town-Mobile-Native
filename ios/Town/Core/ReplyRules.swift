import Foundation
public enum ReplyRules {
    private static func value(_ row:[String:Any],_ keys:[String])->String { for key in keys { if let s=row[key] as? String,!s.isEmpty{return s};if let n=row[key] as? NSNumber{return n.stringValue} };return "" }
    public static func context(_ row:[String:Any],rows:[[String:Any]] = [])->String? {
        let id=value(row,["reply_to"]);guard !id.isEmpty else{return nil}
        let author=value(row,["reply_to_display","reply_to_sender_display","reply_to_being","reply_to_sender"])
        let parent=rows.first{value($0,["seq","id","message_id"]) == id}
        let preview=value(row,["reply_to_preview"])
        let body=preview.isEmpty ? parent.map{value($0,["content","message"])} ?? "" : preview
        return "\(author.isEmpty || author.hasPrefix("t_") ? "原消息" : author)：\(body.isEmpty ? "原消息预览不可用" : String(body.prefix(500)))"
    }
    public static func prompt(place:String,author:String?,content:String,context:String?,description:String)->String {
        func quote(_ s:String)->String { String(s.prefix(32000)).components(separatedBy:"\n").map{"> "+$0}.joined(separator:"\n") }
        let request=description.trimmingCharacters(in:.whitespacesAndNewlines)
        var parts:[String]
        if let author {
            parts=["请帮我拟一段回复，直接发送，并将回复正文发给我。","位置：\(place)","回复对象：\(author)"]
            if let context,!context.isEmpty{parts.append("这条消息所回复的上文：\n"+quote(context))}
            parts.append("要回复的原消息：\n"+quote(content.trimmingCharacters(in:.whitespacesAndNewlines)))
            if !request.isEmpty{parts.append("我已经手写的内容或要求，请结合它完善回复：\n"+quote(request))}
        } else {parts=["请根据我的描述和场景位置，帮我写一句适合发布的内容，直接发送，并将发送正文发给我。","场景位置：\(place)","我的描述：\n"+quote(request)]}
        return String(parts.joined(separator:"\n\n").prefix(33000))
    }
}
