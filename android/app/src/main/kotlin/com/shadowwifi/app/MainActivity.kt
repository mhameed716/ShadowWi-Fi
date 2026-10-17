package com.shadowwifi.app

import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.wifi.SupplicantState
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSuggestion
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address
import java.net.NetworkInterface

/**
 * النشاط الرئيسي للتطبيق.
 *
 * يوفّر قناة نظامية "com.shadowwifi.app/system" بقدرات لا تتوفر عبر إضافات
 * Flutter: البوابة الافتراضية، خوادم DNS، عناوين الجهاز، بيانات الواي فاي
 * المتصلة، و**الاتصال الحقيقي بشبكة واي فاي بكلمة مرور** كما يفعل تطبيق
 * إعدادات أندرويد:
 *
 * - أندرويد 9 فما قبل (API < 29): [WifiConfiguration] مع
 *   addNetwork/enableNetwork/reconnect — اتصال برمجي كامل.
 * - أندرويد 10+ (API 29+): [WifiNetworkSuggestion] — تقديم اقتراح الشبكة
 *   بكلمة المرور ليتولى النظام الاتصال (سياسة جوجل: لا اتصال صامت
 *   لتطبيقات الجهات الخارجية على أندرويد 10+).
 */
class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null

    /** آخر اقتراح شبكة قدّمناه — لحذفه بدقة عند "نسيان" الشبكة. */
    private var lastSuggestions: WifiNetworkSuggestion? = null

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
    // الاتصال الحقيقي بشبكة واي فاي
    // ------------------------------------------------------------------

    /**
     * يحاول الاتصال بشبكة WPA2/WPA3 بكلمة مرور.
     *
     * يعيد خريطة: mode = legacy | suggestion | error مع رسالة عربية.
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

        // أندرويد 10+ : تقديم اقتراح شبكة (سياسة النظام — لا اتصال صامت).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return try {
                val builder = WifiNetworkSuggestion.Builder().setSsid(ssid)
                if (useWpa3) {
                    builder.setWpa3Passphrase(password)
                } else {
                    builder.setWpa2Passphrase(password)
                }
                val suggestion = builder.build()

                // حذف الاقتراح السابق لنفس الشبكة لتجنّب رفض التكرار.
                val previous = lastSuggestions
                if (previous != null) {
                    manager.removeNetworkSuggestions(listOf(previous))
                }

                val status = manager.addNetworkSuggestions(listOf(suggestion))
                lastSuggestions = suggestion

                out["mode"] = "suggestion"
                out["status"] = status
                out["message"] =
                    if (status == WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS) {
                        "قُدّم الاقتراح للنظام — سيتصل تلقائياً عند توافر الشبكة"
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

        // أندرويد 9 فما قبل: اتصال برمجي كامل مثل تطبيق الإعدادات.
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

    /** هل الجهاز متصل فعلياً بالشبكة المطلوبة (BSSID مكتمل + نفس SSID)؟ */
    private fun isConnectedTo(ssid: String): Boolean {
        return try {
            val manager = wifiManager() ?: return false
            val info = manager.connectionInfo ?: return false
            val current = info.ssid?.trim('"') ?: return false
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
                val suggestion = lastSuggestions
                if (suggestion != null) {
                    val status =
                        manager.removeNetworkSuggestions(listOf(suggestion))
                    lastSuggestions = null
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

    /** بيانات الواي فاي المتصلة حالياً. */
    private fun readWifiInfo(): Map<String, Any?> {
        val info = mutableMapOf<String, Any?>()
        try {
            val manager = wifiManager()
            val connectionInfo = manager?.connectionInfo ?: return info

            val ssid = connectionInfo.ssid?.trim('"')
            info["ssid"] = if (ssid == "0x" || ssid.isNullOrBlank()) null else ssid
            info["bssid"] = connectionInfo.bssid
            info["level"] = connectionInfo.rssi
            info["linkSpeed"] = connectionInfo.linkSpeed
            info["supplicantState"] = connectionInfo.supplicantState?.name

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
