package town.nativeapp
import android.app.Application
import androidx.compose.runtime.*
import androidx.lifecycle.AndroidViewModel

data class Destination(val id: String, val title: String)
val destinations = listOf(Destination("chat","对话"),Destination("firesides","围炉"),Destination("mail","私信"),Destination("bonfire","篝火"),Destination("seeds","种子花园"),Destination("embers","书架"),Destination("scrolls","卷轴"),Destination("announcements","公告"),Destination("contacts","通讯录"),Destination("home","小镇广场"))
class NavigationModel(app: Application): AndroidViewModel(app) {
    var sceneSheet by mutableStateOf<String?>(null)
    private val prefs = app.getSharedPreferences("navigation",0)
    private var current by mutableStateOf("chat")
    private val previous = mutableStateListOf<String>()
    private val next = mutableStateListOf<String>()
    var screen: String
        get() = current
        set(value) { if(value != current) { previous.add(current); next.clear(); current=value } }
    val canBack get() = previous.isNotEmpty()
    val canForward get() = next.isNotEmpty()
    fun back() { if(canBack) { next.add(0,current); current=previous.removeAt(previous.lastIndex) } }
    fun forward() { if(canForward) { previous.add(current);current=next.removeAt(0) } }
    var tabs by mutableStateOf(prefs.getString("tabs",null)?.split(",")?.filter { id -> destinations.any { it.id == id } }?.distinct()?.takeIf { it.contains("chat") && it.size <= 4 } ?: listOf("chat","firesides","mail","bonfire")); private set
    var appearance by mutableStateOf(prefs.getString("appearance","system")!!); private set
    fun appearance(value: String) { appearance = value; prefs.edit().putString("appearance",value).apply() }
    fun tabs(value: List<String>) { if ("chat" !in value || value.size > 4) return; tabs = value.distinct(); prefs.edit().putString("tabs",tabs.joinToString(",")).apply() }
}
