package town.nativeapp;

import android.app.*;
import android.content.*;
import android.os.Bundle;

/** Separate test APK: SDK-only classes because the target app's Kotlin runtime is not loaded. */
public final class PortalNotificationFixture extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        SharedPreferences prefs = context.getSharedPreferences("synthetic-reply", 0);
        switch (String.valueOf(intent.getAction())) {
            case "fixture.post":
                prefs.edit().clear().commit();
                manager.createNotificationChannel(new NotificationChannel("fixture", "Synthetic Portal QA", NotificationManager.IMPORTANCE_DEFAULT));
                PendingIntent pending = PendingIntent.getBroadcast(context, 1, new Intent(context, PortalNotificationFixture.class).setAction("fixture.reply"), PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_MUTABLE);
                manager.notify(987, new Notification.Builder(context, "fixture").setSmallIcon(android.R.drawable.ic_dialog_info)
                    .setContentTitle("Portal synthetic notification").setContentText("Only fixture data")
                    .addAction(new Notification.Action.Builder(null, "Reply", pending).addRemoteInput(new RemoteInput.Builder("reply").setLabel("Reply").build()).build()).build());
                setResultData("posted");
                break;
            case "fixture.reply":
                Bundle results = RemoteInput.getResultsFromIntent(intent);
                if (results != null) prefs.edit().putString("reply", String.valueOf(results.getCharSequence("reply"))).commit();
                break;
            case "fixture.result": setResultData(prefs.getString("reply", "missing")); break;
            case "fixture.clear": manager.cancel(987); prefs.edit().clear().commit(); break;
        }
    }
}
