package town.nativeapp

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.*
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.time.TimeRangeFilter
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import java.time.Instant

object AndroidPortalHealth {
    val permissions = setOf(HealthPermission.getReadPermission(StepsRecord::class), HealthPermission.getReadPermission(SleepSessionRecord::class),
        HealthPermission.getReadPermission(ExerciseSessionRecord::class), HealthPermission.getReadPermission(HeartRateRecord::class), HealthPermission.getReadPermission(WeightRecord::class))
    fun available(context: Context) = HealthConnectClient.getSdkStatus(context) == HealthConnectClient.SDK_AVAILABLE
    fun call(context: Context, args: JSONObject): JSONObject = runBlocking {
        check(available(context)) { "Health Connect unavailable; install/update provider in Android settings" }
        val client = HealthConnectClient.getOrCreate(context)
        val granted = client.permissionController.getGrantedPermissions()
        val (start, end) = AndroidPortalRules.interval(args, 31)
        val range = TimeRangeFilter.between(Instant.ofEpochMilli(start), Instant.ofEpochMilli(end))
        val type = args.text("type", 30)
        val needed = when (type) { "steps" -> HealthPermission.getReadPermission(StepsRecord::class); "sleep" -> HealthPermission.getReadPermission(SleepSessionRecord::class)
            "exercise" -> HealthPermission.getReadPermission(ExerciseSessionRecord::class); "heart_rate" -> HealthPermission.getReadPermission(HeartRateRecord::class)
            "weight" -> HealthPermission.getReadPermission(WeightRecord::class); else -> error("Unsupported health type") }
        check(needed in granted) { "Health permission required for $type" }
        // Foreground only unless a future release explicitly adds background health access.
        check(AndroidPortalPolicy.foreground) { "Open Being on the phone to read health data" }
        val result = JSONObject().put("type", type).put("start", args.getString("start")).put("end", args.getString("end"))
        when (type) {
            "steps" -> {
                val data = client.aggregate(AggregateRequest(setOf(StepsRecord.COUNT_TOTAL), range))
                result.put("count", data[StepsRecord.COUNT_TOTAL] ?: JSONObject.NULL)
            }
            "sleep" -> {
                val page = client.readRecords(ReadRecordsRequest(SleepSessionRecord::class, range, pageSize = 100, pageToken = args.optString("page_token").ifBlank { null }))
                result.put("records", jsonArray(page.records.map { JSONObject().put("start", it.startTime.toString()).put("end", it.endTime.toString()).put("source", it.metadata.dataOrigin.packageName) })).put("next_page_token", page.pageToken ?: JSONObject.NULL)
            }
            "exercise" -> {
                val page = client.readRecords(ReadRecordsRequest(ExerciseSessionRecord::class, range, pageSize = 100, pageToken = args.optString("page_token").ifBlank { null }))
                result.put("records", jsonArray(page.records.map { JSONObject().put("start", it.startTime.toString()).put("end", it.endTime.toString()).put("exercise_type", it.exerciseType).put("source", it.metadata.dataOrigin.packageName) })).put("next_page_token", page.pageToken ?: JSONObject.NULL)
            }
            "heart_rate" -> {
                val page = client.readRecords(ReadRecordsRequest(HeartRateRecord::class, range, pageSize = 20, pageToken = args.optString("page_token").ifBlank { null }))
                result.put("records", jsonArray(page.records.map { row -> JSONObject().put("start", row.startTime.toString()).put("end", row.endTime.toString())
                    .put("samples", jsonArray(row.samples.take(200).map { JSONObject().put("time", it.time.toString()).put("bpm", it.beatsPerMinute) }))
                    .put("samples_truncated", row.samples.size > 200) })).put("next_page_token", page.pageToken ?: JSONObject.NULL)
            }
            "weight" -> {
                val page = client.readRecords(ReadRecordsRequest(WeightRecord::class, range, pageSize = 100, pageToken = args.optString("page_token").ifBlank { null }))
                result.put("records", jsonArray(page.records.map { JSONObject().put("time", it.time.toString()).put("kilograms", it.weight.inKilograms) })).put("next_page_token", page.pageToken ?: JSONObject.NULL)
            }
        }
        result.put("note", "Only authorized existing Health Connect records; empty does not imply zero activity. No medical diagnosis.")
    }
}
