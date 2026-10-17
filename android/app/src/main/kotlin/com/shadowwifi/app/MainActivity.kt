package com.shadowwifi.app

import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.wifi.WifiManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address
import java.net.NetworkInterface

/**
 * النشاط الرئيسي للتطبيق.
 *
 * يوفّر قناة نظامية "com.shadowwifi.app/system" بمعلومات لا تتوفر عبر إضافات
 * Flutter: البوابة الافتراضية، خوادم DNS، عناوين الجهاز، وبيانات الواي فاي
 * المتصلة.
 */
class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null

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

    /** البوابة الافتراضية كما يقرأها نظام DHCP. */
    private fun readGateway(): String? {
        return try {
            val wifiManager =
                applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            val dhcpInfo = wifiManager?.dhcpInfo
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

    /** يفتح شاشة إعدادات الموقع في النظام. */
    private fun openLocationSettings(): Boolean {
        return try {
            startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
            true
        } catch (error: Exception) {
            false
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
        return result
    }

    /** بيانات الواي فاي المتصلة حالياً. */
    private fun readWifiInfo(): Map<String, Any?> {
        val info = mutableMapOf<String, Any?>()
        try {
            val wifiManager =
                applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            val connectionInfo = wifiManager?.connectionInfo ?: return info

            val ssid = connectionInfo.ssid?.trim('"')
            info["ssid"] = if (ssid == "0x" || ssid.isNullOrBlank()) null else ssid
            info["bssid"] = connectionInfo.bssid
            info["level"] = connectionInfo.rssi
            info["linkSpeed"] = connectionInfo.linkSpeed

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
