package com.shadowwifi.app

import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.SupplicantState
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.net.wifi.WifiNetworkSuggestion
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * النشاط الرئيسي للتطبيق.
 *
 * قناة النظام "com.shadowwifi.app/system":
 *
 * الاتصال الحقيقي بالواي فاي:
 * - أندرويد 10+ (مسار Specifier): [ConnectivityManager.requestNetwork] مع
 *   [WifiNetworkSpecifier] — يطلب من النظام اتصالاً فورياً بتلك الشبكة
 *   بتلك الكلمة ويعيد نتيجة قاطعة (onAvailable = نجح / onUnavailable = فشل).
 * - أندرويد 9- (مسار Legacy): [WifiConfiguration] مع
 *   addNetwork/enableNetwork/reconnect — اتصال برمجي كامل.
 * - حفظ دائم: [WifiNetworkSuggestion] بعد نجاح الـ Specifier.
 * - بديل مضمون: [Settings.Panel.ACTION_WIFI] — لوحة النظام الرسمية.
 */
class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null

    /** آخر اقتراح شبكة قدّمناه — لحذفه بدقة عند "نسيان" الشبكة. */
    private var lastSuggestion: WifiNetworkSuggestion? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getGateway" -> result.success(readGateway())
                    "getDnsServers" -> result.success(readDnsServers())
                    "getDeviceInfo" -> result.success(readDeviceInfo())
                    "getWifiInfo" -> result.success(readWifiInfo())
                    "openLocationSettings" -> result.success(openLocationSettings())
                    "openWifiSettings" -> result.success(openWifiSettings())
                    "openWifiPanel" -> result.success(openWifiPanel())
                    "connectViaSpecifier" -> {
                        val ssid = call.argument<String>("ssid") ?: ""
                        val password = call.argument<String>("password") ?: ""
                        val wpa3 = call.argument<Boolean>("wpa3") ?: false
                        val timeoutMs = call.argument<Int>("timeoutMs") ?: 25000
                        // الانتظار على خيط خلفي — ردود NetworkCallback تُسلَّم
                        // على الخيط الرئيسي، وحجبه سيسبب توقفاً تاماً.
                        Thread {
                            val res = connectViaSpecifier(ssid, password, wpa3, timeoutMs)
                            runOnUiThread { result.success(res) }
                        }.start()
                    }
                    "connectToWifi" -> {
                        val ssid = call.argument<String>("ssid") ?: ""
                        val password = call.argument<String>("password") ?: ""
                        val wpa3 = call.argument<Boolean>("wpa3") ?: false
                        result.success(connectToWifi(ssid, password, wpa3))
                    }
                    "isConnectedTo" -> {
                        val ssid = call.argument<String>("ssid") ?: ""
                        result.success(isConnectedTo(ssid))
                    }
                    "forgetNetwork" -> {
                        val ssid = call.argument<String>("ssid") ?: ""
                        result.success(forgetNetwork(ssid))
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun wifiManager(): WifiManager? =
        applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager

    // ------------------------------------------------------------------
    // المسار الحقيقي الحاسم — أندرويد 10+ عبر WifiNetworkSpecifier
    // ------------------------------------------------------------------

    /**
     * يطلب من النظام اتصالاً فورياً بالشبكة بكلمة المرور ويعيد نتيجة قاطعة.
     *
     * على أندرويد 10+ يعرض النظام نافذة تأكيد للمستخدم — قبولها شرط للنجاح.
     * نجرّب وضع التشفير المطلوب، وإن فشل نجرّب الوضع المعاكس مرة واحدة
     * (لشبكات WPA2/WPA3 الانتقالية).
     */
    private fun connectViaSpecifier(
        ssid: String,
        password: String,
        useWpa3: Boolean,
        timeoutMs: Int
    ): Map<String, Any?> {
        val out = mutableMapOf<String, Any?>()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            out["connected"] = false
            out["unsupported"] = true
            out["reason"] = "unsupported"
            out["message"] = "المسار الحاسم غير مدعوم قبل أندرويد 10"
            return out
        }
        if (ssid.isBlank()) {
            out["connected"] = false
            out["reason"] = "error"
            out["message"] = "اسم الشبكة فارغ"
            return out
        }
        if (password.isBlank()) {
            out["connected"] = false
            out["reason"] = "error"
            out["message"] = "كلمة المرور فارغة"
            return out
        }
        val manager = wifiManager()
        if (manager == null) {
            out["connected"] = false
            out["reason"] = "error"
            out["message"] = "خدمة الواي فاي غير متاحة"
            return out
        }
        if (!manager.isWifiEnabled) {
            out["connected"] = false
            out["reason"] = "wifi_off"
            out["message"] = "الواي فاي مغلق — فعّله ثم أعد المحاولة"
            return out
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val location = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            if (location != null && !location.isLocationEnabled) {
                out["connected"] = false
                out["reason"] = "location_off"
                out["message"] = "فعّل خدمة الموقع — أندرويد يشترطها لاقتران الواي فاي"
                return out
            }
        }

        // وضعان متتاليان: المطلوب ثم المعاكس (شبكات انتقالية WPA2/WPA3).
        val modes = linkedSetOf(useWpa3, !useWpa3)
        var connected = false
        var lastReason = "unavailable"
        var usedWpa3 = useWpa3
        for (mode in modes) {
            val started = SystemClock.elapsedRealtime()
            val attempt = specifierAttempt(ssid, password, mode, timeoutMs)
            lastReason = attempt.second
            if (attempt.first) {
                connected = true
                usedWpa3 = mode
                break
            }
            // رفض سريع = أُغلقت نافذة «اختيار جهاز» — لا نفتحها مرة ثانية
            // فوراً (إزعاج مزدوج)؛ المستخدم يعيد المحاولة عندما يرغب.
            if (SystemClock.elapsedRealtime() - started < 6000L) {
                lastReason = "declined"
                break
            }
        }

        // عند النجاح: حفظ دائم كاقتراح قبل تحرير الشبكة —
        // عند إلغاء الطلب ينتقل النظام سلساً إلى الاقتراح بنفس الكلمة.
        if (connected) {
            try {
                connectToWifi(ssid, password, usedWpa3)
            } catch (error: Exception) {
                // الحفظ الدائم ليس شرطاً لنجاح الاتصال نفسه.
            }
        }

        out["connected"] = connected
        out["reason"] = lastReason
        out["message"] = if (connected) {
            "تم الاتصال بالشبكة فعلياً"
        } else {
            when (lastReason) {
                "declined" ->
                    "أُلغيت نافذة «اختيار جهاز» — أعد المحاولة واضغط على اسم " +
                        "شبكتك داخلها ثم اقبل"
                "unavailable" ->
                    "فشل الاقتران — تأكد من صحة الكلمة وقرب الراوتر"
                else -> "انتهت المهلة دون اقتران"
            }
        }
        return out
    }

    /** محاولة Specifier واحدة بوضع تشفير محدد — تعيد (نجاح، سبب الفشل). */
    private fun specifierAttempt(
        ssid: String,
        password: String,
        useWpa3: Boolean,
        timeoutMs: Int
    ): Pair<Boolean, String> {
        var connected = false
        var reason = "unavailable"
        val latch = CountDownLatch(1)
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                connected = true
                latch.countDown()
            }

            override fun onUnavailable() {
                latch.countDown()
            }

            override fun onLost(network: Network) {
                latch.countDown()
            }
        }

        val connectivityManager =
            getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        try {
            val builder = WifiNetworkSpecifier.Builder().setSsid(ssid)
            if (useWpa3) builder.setWpa3Passphrase(password)
            else builder.setWpa2Passphrase(password)

            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .setNetworkSpecifier(builder.build())
                .build()

            connectivityManager.requestNetwork(
                request, callback, Handler(Looper.getMainLooper()), timeoutMs
            )
            latch.await((timeoutMs / 1000L) + 5L, TimeUnit.SECONDS)
        } catch (error: Exception) {
            reason = "error"
        } finally {
            try {
                connectivityManager.unregisterNetworkCallback(callback)
            } catch (error: Exception) {
                // قد يكون أُلغي تلقائياً بعد onUnavailable.
            }
        }
        return Pair(connected, if (connected) "success" else reason)
    }

    // ------------------------------------------------------------------
    // الاتصال الدائم — اقتراح الشبكة (أندرويد 10+) / الإعداد الكامل (9-)
    // ------------------------------------------------------------------

    /**
     * يحاول الاتصال/حفظ الشبكة:
     * - أندرويد 10+: تقديم اقتراح دائم (يتصل النظام به عند التواجد في النطاق)
     *   مع تحفيز فحص فوري لتسريع الاقتران.
     * - أندرويد 9-: اتصال برمجي كامل فوري.
     */
    private fun connectToWifi(
        ssid: String,
        password: String,
        useWpa3: Boolean
    ): Map<String, Any?> {
        val out = mutableMapOf<String, Any?>()
        if (ssid.isBlank()) {
            out["mode"] = "error"
            out["message"] = "اسم الشبكة فارغ"
            return out
        }
        val manager = wifiManager()
        if (manager == null) {
            out["mode"] = "error"
            out["message"] = "خدمة الواي فاي غير متاحة على الجهاز"
            return out
        }
        if (!manager.isWifiEnabled) {
            out["mode"] = "error"
            out["message"] = "الواي فاي مغلق — فعّله من إعدادات الجهاز"
            return out
        }

        // أندرويد 10+ : اقتراح دائم + تحفيز فحص.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return try {
                val builder = WifiNetworkSuggestion.Builder()
                    .setSsid(ssid)
                    .setIsAppInteractionRequired(true)
                if (useWpa3) builder.setWpa3Passphrase(password)
                else builder.setWpa2Passphrase(password)
                val suggestion = builder.build()

                val previous = lastSuggestion
                if (previous != null) {
                    manager.removeNetworkSuggestions(listOf(previous))
                }

                val status = manager.addNetworkSuggestions(listOf(suggestion))
                lastSuggestion = suggestion

                // تحفيز فحص فوري حتى يلمح النظام الشبكة ويتصل بالاقتراح سريعاً.
                try {
                    manager.startScan()
                } catch (error: Exception) {
                    // التقييد الزمني للفحص غير حرج — النظام يفحص دورياً.
                }

                out["mode"] = "suggestion"
                out["status"] = status
                out["message"] =
                    if (status == WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS) {
                        "حُفظت الشبكة كاقتراح — سيتصل النظام بها تلقائياً"
                    } else {
                        "رفض النظام الاقتراح (رمز $status)"
                    }
                out
            } catch (error: Exception) {
                out["mode"] = "error"
                out["message"] = "فشل تقديم الاقتراح: ${error.message}"
                out
            }
        }

        // أندرويد 9- : اتصال برمجي كامل.
        return try {
            val config = WifiConfiguration().apply {
                SSID = "\"$ssid\""
                preSharedKey = "\"$password\""
                allowedKeyManagement.set(WifiConfiguration.KeyMgmt.WPA_PSK)
            }

            val oldId = findConfiguredNetworkId(manager, ssid)
            if (oldId != null) manager.removeNetwork(oldId)

            val netId = manager.addNetwork(config)
            if (netId == -1) {
                out["mode"] = "error"
                out["message"] = "رفض النظام إضافة الشبكة (تحقق من كلمة المرور)"
                return out
            }

            manager.disconnect()
            val enabled = manager.enableNetwork(netId, true)
            manager.reconnect()

            out["mode"] = if (enabled) "legacy" else "error"
            out["netId"] = netId
            out["message"] = if (enabled) "بدأ الاتصال بالشبكة" else "تعذّر تفعيل الشبكة"
            out
        } catch (error: Exception) {
            out["mode"] = "error"
            out["message"] = "فشل الاتصال: ${error.message}"
            out
        }
    }

    /** هل الجهاز متصل فعلياً بالشبكة المطلوبة (اقتران مكتمل + نفس SSID)؟ */
    private fun isConnectedTo(ssid: String): Boolean {
        return try {
            val manager = wifiManager() ?: return false
            val info = manager.connectionInfo ?: return false
            val current = info.ssid?.trim('"') ?: return false
            // استبعاد الأسماء الوهمية التي يُبقيها النظام بعد الانقطاع.
            if (current.isBlank() || current == "0x" || current.startsWith("<")) {
                return false
            }
            current == ssid && info.supplicantState == SupplicantState.COMPLETED
        } catch (error: Exception) {
            false
        }
    }

    /** نسيان الشبكة: حذف الإعداد المحفوظ أو الاقتراح المقدّم. */
    private fun forgetNetwork(ssid: String): Boolean {
        return try {
            val manager = wifiManager() ?: return false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val suggestion = lastSuggestion
                if (suggestion != null) {
                    val status =
                        manager.removeNetworkSuggestions(listOf(suggestion))
                    lastSuggestion = null
                    status != -1
                } else {
                    true
                }
            } else {
                val oldId = findConfiguredNetworkId(manager, ssid)
                oldId == null || manager.removeNetwork(oldId)
            }
        } catch (error: Exception) {
            false
        }
    }

    /** إيجاد معرّف إعداد محفوظ بنفس الـ SSID (يعمل كاملاً قبل API 29). */
    private fun findConfiguredNetworkId(manager: WifiManager, ssid: String): Int? {
        return try {
            val target = "\"$ssid\""
            manager.configuredNetworks
                ?.firstOrNull { it.SSID == target }?.networkId
        } catch (error: Exception) {
            null
        }
    }

    /** يفتح شاشة إعدادات الواي فاي في النظام. */
    private fun openWifiSettings(): Boolean {
        return try {
            startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
            true
        } catch (error: Exception) {
            false
        }
    }

    /**
     * يفتح لوحة الواي فاي الرسمية (أندرويد 10+) — قائمة النظام نفسها
     * للاتصال بضغطة واحدة — البديل المضمون 100%.
     */
    private fun openWifiPanel(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startActivity(Intent(Settings.Panel.ACTION_WIFI))
            } else {
                startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
            }
            true
        } catch (error: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
                true
            } catch (inner: Exception) {
                false
            }
        }
    }

    /** يفتح شاشة إعدادات الموقع في النظام. */
    private fun openLocationSettings(): Boolean {
        return try {
            startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
            true
        } catch (error: Exception) {
            false
        }
    }

    // ------------------------------------------------------------------
    // القراءات النظامية
    // ------------------------------------------------------------------

    /** البوابة الافتراضية كما يقرأها نظام DHCP. */
    private fun readGateway(): String? {
        return try {
            val manager = wifiManager()
            val dhcpInfo = manager?.dhcpInfo
            val gateway: Int? = dhcpInfo?.gateway
            if (gateway == null || gateway == 0) {
                null
            } else {
                val host = intToIp(gateway)
                if (host.isBlank() || host == "0.0.0.0") null else host
            }
        } catch (error: Exception) {
            null
        }
    }

    /** تحويل عنوان IPv4 المخزّن كـ Int إلى الصورة النقطية. */
    private fun intToIp(value: Int): String {
        return "${value and 0xFF}.${(value shr 8) and 0xFF}." +
            "${(value shr 16) and 0xFF}.${(value shr 24) and 0xFF}"
    }

    /** خوادم DNS المستخدمة في الاتصال الحالي. */
    private fun readDnsServers(): List<String> {
        val servers = mutableListOf<String>()
        try {
            val connectivityManager =
                getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            if (connectivityManager == null) return servers

            val network: Network? = connectivityManager.activeNetwork
            val linkProperties: LinkProperties? =
                if (network != null) connectivityManager.getLinkProperties(network) else null

            if (linkProperties != null) {
                for (dnsAddress in linkProperties.dnsServers) {
                    val host = dnsAddress.hostAddress
                    if (!host.isNullOrBlank()) servers.add(host)
                }
            }
        } catch (error: Exception) {
            // تُترك القائمة فارغة عند الفشل.
        }
        return servers
    }

    /** عناوين الجهاز واسم واجهة الشبكة وعنوانها المادي. */
    private fun readDeviceInfo(): Map<String, Any?> {
        val addresses = mutableListOf<String>()
        var macAddress: String? = null
        var interfaceName: String? = null

        try {
            val interfaces = NetworkInterface.getNetworkInterfaces()
            while (interfaces != null && interfaces.hasMoreElements()) {
                val networkInterface = interfaces.nextElement()
                if (networkInterface.isLoopback || !networkInterface.isUp) {
                    continue
                }
                for (address in networkInterface.inetAddresses) {
                    if (address is Inet4Address) {
                        val host = address.hostAddress ?: continue
                        if (!host.startsWith("127.")) {
                            addresses.add(host)
                        }
                    }
                }
                if (macAddress == null) {
                    val hardware = networkInterface.hardwareAddress
                    if (hardware != null && hardware.isNotEmpty()) {
                        macAddress = hardware.joinToString(":") { byte ->
                            String.format("%02x", byte)
                        }
                        interfaceName = networkInterface.name
                    }
                }
            }
        } catch (error: Exception) {
            // تُترك القيم فارغة عند الفشل.
        }

        val result = mutableMapOf<String, Any?>()
        result["addresses"] = addresses
        result["mac"] = macAddress
        result["interface"] = interfaceName
        result["sdk"] = Build.VERSION.SDK_INT
        return result
    }

    /**
     * بيانات الواي فاي المتصلة حالياً.
     *
     * شرط «متصل فعلاً»: اكتمال الاقتران (COMPLETED) + اسم صالح + عنوان
     * مادي صالح. بدون هذه البوابة تظهر شبكة وهمية «متصل» بعد انقطاع
     * الاتصال لأن النظام يُبقي آخر اسم في WifiInfo.
     */
    private fun readWifiInfo(): Map<String, Any?> {
        val info = mutableMapOf<String, Any?>()
        try {
            val manager = wifiManager()
            val connectionInfo = manager?.connectionInfo ?: return info

            val state = connectionInfo.supplicantState
            val ssid = connectionInfo.ssid?.trim('"')
            val bssid = connectionInfo.bssid

            val ssidValid = !ssid.isNullOrBlank() &&
                ssid != "0x" && !ssid.startsWith("<")
            val bssidValid = bssid != null &&
                bssid.contains(":") && !bssid.startsWith("<") &&
                bssid != "02:00:00:00:00:00"

            if (state != SupplicantState.COMPLETED || !ssidValid) return info
            // على الرومات القديمة قد يكون BSSID فارغاً رغم اتصال حقيقي.
            if (!bssidValid && bssid != null) return info

            info["ssid"] = ssid
            info["bssid"] = bssid
            info["level"] = connectionInfo.rssi
            info["linkSpeed"] = connectionInfo.linkSpeed
            info["supplicantState"] = state.name

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                info["frequency"] = connectionInfo.frequency
            }
        } catch (error: Exception) {
            // تُترك القيم فارغة عند الفشل.
        }
        return info
    }

    companion object {
        private const val CHANNEL_NAME = "com.shadowwifi.app/system"
    }
}
