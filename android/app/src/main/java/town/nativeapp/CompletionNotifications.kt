package town.nativeapp

import android.app.*
import android.content.*
import android.os.Build
import androidx.compose.runtime.*
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

object CompletionNotifications {
    const val channel="conversation-completed"
    var pendingEndpoint by mutableStateOf<String?>(null)
    var pendingScene by mutableStateOf<String?>(null)
    fun capture(intent:Intent?){pendingEndpoint=intent?.getStringExtra("endpoint");pendingScene=intent?.getStringExtra("scene")}
    fun finished(context:Context,endpoint:String,scene:String,title:String,shouldNotify:Boolean){
        if(!shouldNotify||!context.getSharedPreferences("settings",0).getBoolean("notify.completed",false))return
        val manager=context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(channel,"对话完成",NotificationManager.IMPORTANCE_DEFAULT))
        if(!NotificationManagerCompat.from(context).areNotificationsEnabled())return
        val id=(endpoint+scene).hashCode()
        val intent=Intent(context,MainActivity::class.java).putExtra("endpoint",endpoint).putExtra("scene",scene).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pending=PendingIntent.getActivity(context,id,intent,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification=NotificationCompat.Builder(context,channel).setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle("对话已完成").setContentText(title).setContentIntent(pending).setAutoCancel(true).build()
        try{manager.notify(id,notification)}catch(_:SecurityException){}
    }
    fun social(context:Context,channelName:String,title:String){
        val prefs=context.getSharedPreferences("settings",0)
        if(!prefs.getBoolean("notify.social.enabled",false)||!prefs.getBoolean("notify.social.$channelName",false)||!NotificationManagerCompat.from(context).areNotificationsEnabled())return
        val channelId="town-social-$channelName";val manager=context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(channelId,title,NotificationManager.IMPORTANCE_DEFAULT))
        val intent=Intent(context,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pending=PendingIntent.getActivity(context,channelName.hashCode(),intent,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        try{manager.notify((channelName+System.currentTimeMillis()).hashCode(),NotificationCompat.Builder(context,channelId).setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle(title).setContentText("打开 Being 查看最新内容").setContentIntent(pending).setAutoCancel(true).build())}catch(_:SecurityException){}
    }
}
