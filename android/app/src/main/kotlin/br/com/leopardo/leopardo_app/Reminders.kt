package br.com.leopardo.leopardo_app

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONArray
import org.json.JSONObject

/**
 * Lembretes de garantia (notificações agendadas no próprio aparelho).
 * A lista fica salva para ser reagendada quando o celular reinicia.
 */
object Reminders {
    private const val PREFS = "leopardo_reminders"
    private const val KEY = "list"
    const val CHANNEL = "garantia"

    private fun pending(context: Context, id: Int, title: String, text: String): PendingIntent {
        val i = Intent(context, ReminderReceiver::class.java).apply {
            putExtra("id", id)
            putExtra("title", title)
            putExtra("text", text)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0)
        return PendingIntent.getBroadcast(context, id, i, flags)
    }

    /** Substitui todos os lembretes pela nova lista [{id, at, title, text}]. */
    fun set(context: Context, list: List<Map<String, Any?>>) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        // cancela os anteriores
        for (o in load(context)) {
            am.cancel(pending(context, o.getInt("id"), o.optString("title"), o.optString("text")))
        }
        val arr = JSONArray()
        val now = System.currentTimeMillis()
        for (m in list) {
            val at = (m["at"] as? Number)?.toLong() ?: continue
            if (at <= now) continue
            val o = JSONObject()
            o.put("id", (m["id"] as Number).toInt())
            o.put("at", at)
            o.put("title", m["title"] as? String ?: "")
            o.put("text", m["text"] as? String ?: "")
            arr.put(o)
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, arr.toString()).apply()
        schedule(context)
    }

    private fun load(context: Context): List<JSONObject> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { arr.getJSONObject(it) }
        } catch (e: Exception) {
            emptyList()
        }
    }

    /** Agenda os lembretes salvos (também usado depois de reiniciar o celular). */
    fun schedule(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val now = System.currentTimeMillis()
        for (o in load(context)) {
            val at = o.getLong("at")
            if (at <= now) continue
            val pi = pending(context, o.getInt("id"), o.optString("title"), o.optString("text"))
            if (Build.VERSION.SDK_INT >= 23) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            } else {
                am.set(AlarmManager.RTC_WAKEUP, at, pi)
            }
        }
    }

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(CHANNEL, "Garantia e avisos", NotificationManager.IMPORTANCE_DEFAULT).apply {
                        description = "Lembretes de garantia das impressoras Leopardo"
                    }
                )
            }
        }
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Reminders.ensureChannel(context)
        val open = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0)
        val content = PendingIntent.getActivity(context, 0, open, flags)
        val text = intent.getStringExtra("text") ?: ""
        val n = NotificationCompat.Builder(context, Reminders.CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_leopardo)
            .setContentTitle(intent.getStringExtra("title") ?: "Leopardo")
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setContentIntent(content)
            .setAutoCancel(true)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(intent.getIntExtra("id", 1), n)
        } catch (e: SecurityException) {
            // sem permissão de notificação
        }
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Reminders.schedule(context)
    }
}
