package town.nativeapp

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.Future

/** Location registration can outlive a broadcast's deadline, so recovery uses an OS job. */
class AndroidPortalRestoreJob : JobService() {
    private val executor = Executors.newSingleThreadExecutor()
    private var task: Future<*>? = null
    override fun onStartJob(params: JobParameters): Boolean {
        task = executor.submit {
            try {
                File(noBackupFilesDir, "android-portal").listFiles().orEmpty().filter { it.name.matches(Regex("[0-9a-f]{64}\\.json")) }
                    .forEach { AndroidPortalReminders(this, it.nameWithoutExtension).suspendAll() }
                val owner = AndroidPortalPolicy.owner(this)
                // All registrations share this app's PendingIntent; revoke the previous identity too.
                runCatching { AndroidPortalLocation(this, owner.ifEmpty { "0".repeat(64) }).removeRegistrations() }
                if (owner.isNotEmpty() && !Thread.currentThread().isInterrupted) {
                    if (AndroidPortalPolicy.enabled(this, owner, "reminders", true)) AndroidPortalReminders(this, owner).restore()
                    if (AndroidPortalPolicy.enabled(this, owner, "geofences", true)) AndroidPortalLocation(this, owner).restore()
                }
            } finally { jobFinished(params, false) }
        }
        return true
    }
    override fun onStopJob(params: JobParameters): Boolean { task?.cancel(true); return true }
    override fun onDestroy() { executor.shutdownNow(); super.onDestroy() }
    companion object {
        fun enqueue(context: Context) {
            context.getSystemService(JobScheduler::class.java).schedule(JobInfo.Builder(7802, ComponentName(context, AndroidPortalRestoreJob::class.java))
                .setMinimumLatency(1000).setOverrideDeadline(10000).setPersisted(true).build())
        }
    }
}
