package ru.smena.sbp

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.ByteArrayOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** SbpPlugin */
class SbpPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null

    /// работа с PackageManager и сжатие иконок выполняются вне main thread
    private lateinit var executor: ExecutorService
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        executor = Executors.newSingleThreadExecutor()
        channel = MethodChannel(binding.binaryMessenger, "sbp")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getInstalledBanks" -> getInstalledBanks(call, result)
            "openBank" -> openBank(call, result)
            else -> result.notImplemented()
        }
    }

    private fun getInstalledBanks(call: MethodCall, result: Result) {
        val banks = call.argument<List<Map<String, Any?>>>("banks")?.mapNotNull { bank ->
            val schema = bank["schema"] as? String ?: return@mapNotNull null
            val packageNames = (bank["package_names"] as? List<*>)?.filterIsInstance<String>()
                ?: listOfNotNull(bank["package_name"] as? String)
            BankQuery(schema, packageNames.filter { it.isNotBlank() }.distinct())
        }
        if (banks == null) {
            result.error(ERROR_INVALID_ARGUMENT, "Argument 'banks' is required", null)
            return
        }
        val useLocalIcons = call.argument<Boolean>("use_android_local_icons") ?: false
        val useLocalNames = call.argument<Boolean>("use_android_local_names") ?: false

        executor.execute {
            try {
                val pm = context.packageManager
                val installed = BankAppResolver { uri -> queryHandlers(pm, uri, matchAll = uri == BankAppResolver.NSPK_HTTPS_URI) }
                    .resolve(banks)
                    .map { bank ->
                        val appInfo = applicationInfo(pm, bank.packageName)
                        mapOf(
                            "schema" to bank.schema,
                            "package_name" to bank.packageName,
                            "name" to if (useLocalNames && appInfo != null) {
                                pm.getApplicationLabel(appInfo).toString()
                            } else null,
                            "bitmap" to if (useLocalIcons && appInfo != null) iconPng(pm, appInfo) else null,
                        )
                    }
                mainHandler.post { result.success(installed) }
            } catch (exception: Exception) {
                mainHandler.post { result.error(ERROR_RESOLVE_FAILED, exception.message, null) }
            }
        }
    }

    /**
     * Открывает ссылку в банке. Сначала с setPackage, при ActivityNotFoundException -
     * без пакета (система сама найдёт приложение по схеме банка).
     */
    private fun openBank(call: MethodCall, result: Result) {
        val url = call.argument<String>("url")
        val uri = url?.let { Uri.parse(it) }
        if (uri == null || uri.scheme.isNullOrEmpty()) {
            result.error(ERROR_INVALID_ARGUMENT, "Invalid url: $url", null)
            return
        }
        val packageName = call.argument<String>("package_name")?.takeIf { it.isNotBlank() }
        // исходная https-ссылка: для приложений, которые открывают только https://qr.nspk.ru
        val httpsUri = call.argument<String>("https_url")?.let { Uri.parse(it) }?.takeIf { it.scheme == "https" }

        val attempts = buildList {
            if (packageName != null) add(uri to packageName)
            add(uri to null)
            if (packageName != null && httpsUri != null) add(httpsUri to packageName)
        }
        var lastError: Exception? = null
        for ((targetUri, targetPackage) in attempts) {
            try {
                startView(targetUri, targetPackage)
                result.success(true)
                return
            } catch (exception: ActivityNotFoundException) {
                lastError = exception
            } catch (exception: SecurityException) {
                lastError = exception
            }
        }
        if (lastError is ActivityNotFoundException) {
            result.error(ERROR_NOT_INSTALLED, "No application can open $uri", null)
        } else {
            result.error(ERROR_OPEN_FAILED, lastError?.message, null)
        }
    }

    private fun startView(uri: Uri, packageName: String?) {
        val intent = Intent(Intent.ACTION_VIEW, uri)
        if (packageName != null) intent.setPackage(packageName)
        val launcher = activity
        if (launcher != null) {
            launcher.startActivity(intent)
        } else {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        }
    }

    /**
     * [matchAll] - для https: с Android 12 приложения без подтверждённого домена (App Links)
     * не считаются обработчиками https://qr.nspk.ru по умолчанию, а подтвердить этот домен банк
     * не может. Поэтому без MATCH_DEFAULT_ONLY и с MATCH_ALL; пакет всё равно сверяется со списком банка.
     */
    private fun queryHandlers(pm: PackageManager, uri: String, matchAll: Boolean = false): List<String> {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri))
        val flags = when {
            !matchAll -> PackageManager.MATCH_DEFAULT_ONLY
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M -> PackageManager.MATCH_ALL
            else -> 0
        }
        val handlers: List<ResolveInfo> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(flags.toLong()))
        } else {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(intent, flags)
        }
        return handlers.mapNotNull { it.activityInfo?.packageName }.distinct()
    }

    private fun applicationInfo(pm: PackageManager, packageName: String): ApplicationInfo? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getApplicationInfo(packageName, PackageManager.ApplicationInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.getApplicationInfo(packageName, 0)
        }
    } catch (exception: PackageManager.NameNotFoundException) {
        null
    }

    private fun iconPng(pm: PackageManager, appInfo: ApplicationInfo): ByteArray? = try {
        val icon = appInfo.loadIcon(pm)
        val bitmap = if (icon is BitmapDrawable && icon.bitmap != null) {
            icon.bitmap
        } else {
            val width = icon.intrinsicWidth.takeIf { it > 0 } ?: ICON_SIZE_PX
            val height = icon.intrinsicHeight.takeIf { it > 0 } ?: ICON_SIZE_PX
            Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also {
                val canvas = Canvas(it)
                icon.setBounds(0, 0, canvas.width, canvas.height)
                icon.draw(canvas)
            }
        }
        ByteArrayOutputStream().use { stream ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            stream.toByteArray()
        }
    } catch (exception: Exception) {
        null
    }

    companion object {
        private const val ICON_SIZE_PX = 192

        const val ERROR_INVALID_ARGUMENT = "INVALID_ARGUMENT"
        const val ERROR_NOT_INSTALLED = "NOT_INSTALLED"
        const val ERROR_OPEN_FAILED = "OPEN_FAILED"
        const val ERROR_RESOLVE_FAILED = "RESOLVE_FAILED"
    }
}
