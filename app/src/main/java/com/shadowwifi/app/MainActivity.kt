package com.shadowwifi.app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Bundle
import android.text.Html
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.weight
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Login
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material.icons.outlined.Wifi
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalLayoutDirection
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.FormBody
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

private val Ink = Color(0xFF0B1015)
private val SurfaceDark = Color(0xFF121920)
private val SurfaceRaised = Color(0xFF19232C)
private val Crimson = Color(0xFFFF4D5A)
private val Mint = Color(0xFF35D49A)
private val TextPrimary = Color(0xFFF4F7F8)
private val TextSecondary = Color(0xFFA7B2BA)
private val BorderDark = Color(0xFF293640)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme(
                colorScheme = androidx.compose.material3.darkColorScheme(
                    primary = Crimson,
                    onPrimary = Color.White,
                    secondary = Mint,
                    onSecondary = Ink,
                    background = Ink,
                    onBackground = TextPrimary,
                    surface = SurfaceDark,
                    onSurface = TextPrimary,
                    surfaceVariant = SurfaceRaised,
                    onSurfaceVariant = TextSecondary,
                    error = Color(0xFFFF727B),
                    outline = BorderDark
                )
            ) {
                CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                    ShadowWifiApp()
                }
            }
        }
    }
}

@Composable
private fun ShadowWifiApp() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var selectedTab by remember { mutableIntStateOf(0) }
    var snapshot by remember {
        mutableStateOf(
            PortalSnapshot(
                networkLabel = PortalRepository.currentNetworkLabel(context)
            )
        )
    }
    var scanning by remember { mutableStateOf(false) }
    var scanMessage by remember { mutableStateOf("اضغط «فحص الشبكة» لاكتشاف بوابة التسجيل.") }
    var cardCode by remember { mutableStateOf("") }
    var loginBusy by remember { mutableStateOf(false) }
    var loginOutcome by remember { mutableStateOf<LoginOutcome?>(null) }
    var checkingInternet by remember { mutableStateOf(false) }
    var internetAvailable by remember { mutableStateOf<Boolean?>(null) }
    var copiedReport by remember { mutableStateOf(false) }

    val runPortalScan: () -> Unit = {
        if (!scanning) {
            scope.launch {
                scanning = true
                scanMessage = "جارٍ فحص إعادة التوجيه وعنوان البوابة…"
                try {
                    val found = PortalRepository.discoverPortal()
                    snapshot = found.copy(networkLabel = PortalRepository.currentNetworkLabel(context))
                    scanMessage = if (found.detected) {
                        "تم اكتشاف بوابة تسجيل وإحضار عنوان الصفحة."
                    } else {
                        "لم يظهر تحويل Captive Portal؛ عُرض العنوان الافتراضي."
                    }
                } catch (_: Exception) {
                    snapshot = PortalSnapshot(
                        networkLabel = PortalRepository.currentNetworkLabel(context)
                    )
                    scanMessage = "تعذّر إكمال الفحص؛ تم استخدام عنوان MikroTik الافتراضي."
                } finally {
                    scanning = false
                }
            }
        }
    }

    val runLogin: () -> Unit = {
        if (cardCode.isNotBlank() && !loginBusy) {
            scope.launch {
                loginBusy = true
                loginOutcome = null
                loginOutcome = PortalRepository.loginOnce(snapshot.portalUrl, cardCode.trim())
                loginBusy = false
            }
        }
    }

    val runInternetCheck: () -> Unit = {
        if (!checkingInternet) {
            scope.launch {
                checkingInternet = true
                internetAvailable = PortalRepository.verifyInternet()
                checkingInternet = false
            }
        }
    }

    val copyDiagnostics: () -> Unit = {
        val internetLabel = when (internetAvailable) {
            true -> "متاح"
            false -> "غير متاح أو لم يُؤكَّد"
            null -> "لم يُفحص"
        }
        val report = """
            ShadowWi-Fi — تقرير تشخيصي
            نوع الاتصال: ${snapshot.networkLabel}
            عنوان البوابة: ${snapshot.portalUrl}
            عنوان الصفحة: ${snapshot.pageTitle}
            الإنترنت: $internetLabel
        """.trimIndent()
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("ShadowWi-Fi diagnostics", report))
        copiedReport = true
    }

    Scaffold(
        containerColor = Ink,
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        topBar = { AppHeader() },
        bottomBar = {
            NavigationBar(
                containerColor = SurfaceDark,
                contentColor = TextPrimary
            ) {
                NavigationBarItem(
                    selected = selectedTab == 0,
                    onClick = { selectedTab = 0 },
                    icon = { androidx.compose.material3.Icon(Icons.Outlined.Wifi, contentDescription = null) },
                    label = { Text("البوابة") },
                    colors = NavigationBarItemDefaults.colors(
                        selectedIconColor = Crimson,
                        selectedTextColor = TextPrimary,
                        indicatorColor = Crimson.copy(alpha = 0.14f),
                        unselectedIconColor = TextSecondary,
                        unselectedTextColor = TextSecondary
                    )
                )
                NavigationBarItem(
                    selected = selectedTab == 1,
                    onClick = { selectedTab = 1 },
                    icon = { androidx.compose.material3.Icon(Icons.Outlined.Info, contentDescription = null) },
                    label = { Text("التشخيص") },
                    colors = NavigationBarItemDefaults.colors(
                        selectedIconColor = Crimson,
                        selectedTextColor = TextPrimary,
                        indicatorColor = Crimson.copy(alpha = 0.14f),
                        unselectedIconColor = TextSecondary,
                        unselectedTextColor = TextSecondary
                    )
                )
            }
        }
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            if (selectedTab == 0) {
                PortalScreen(
                    snapshot = snapshot,
                    scanning = scanning,
                    scanMessage = scanMessage,
                    onScan = runPortalScan,
                    cardCode = cardCode,
                    onCardCodeChange = {
                        cardCode = it.take(80)
                        loginOutcome = null
                    },
                    loginBusy = loginBusy,
                    loginOutcome = loginOutcome,
                    onLogin = runLogin
                )
            } else {
                DiagnosticsScreen(
                    snapshot = snapshot,
                    internetAvailable = internetAvailable,
                    checkingInternet = checkingInternet,
                    copiedReport = copiedReport,
                    onInternetCheck = runInternetCheck,
                    onScan = runPortalScan,
                    onCopyReport = copyDiagnostics
                )
            }
        }
    }
}

@Composable
private fun AppHeader() {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Ink)
            .statusBarsPadding()
            .padding(horizontal = 18.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(46.dp)
                .clip(RoundedCornerShape(15.dp))
                .background(
                    Brush.linearGradient(
                        listOf(Color(0xFF432026), Color(0xFF1C2828))
                    )
                ),
            contentAlignment = Alignment.Center
        ) {
            androidx.compose.material3.Icon(
                imageVector = Icons.Outlined.Wifi,
                contentDescription = "ShadowWi-Fi",
                tint = Crimson,
                modifier = Modifier.size(25.dp)
            )
        }
        Column(modifier = Modifier.weight(1f).padding(start = 12.dp)) {
            Text(
                text = "ShadowWi-Fi",
                color = TextPrimary,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = "أدوات بوابة الشبكة",
                color = TextSecondary,
                fontSize = 12.sp
            )
        }
        StatusPill(text = "آمن", color = Mint)
    }
}

@Composable
private fun PortalScreen(
    snapshot: PortalSnapshot,
    scanning: Boolean,
    scanMessage: String,
    onScan: () -> Unit,
    cardCode: String,
    onCardCodeChange: (String) -> Unit,
    loginBusy: Boolean,
    loginOutcome: LoginOutcome?,
    onLogin: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 18.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(28.dp))
                .background(
                    Brush.linearGradient(
                        listOf(Color(0xFF30191F), Color(0xFF171E24), Color(0xFF10251F))
                    )
                )
                .padding(22.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    text = "CAPTIVE PORTAL  •  NETWORK TOOLS",
                    color = Mint,
                    fontSize = 10.sp,
                    letterSpacing = 1.1.sp,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = "افحص بوابتك\nبخطوة واحدة",
                    color = TextPrimary,
                    fontSize = 27.sp,
                    lineHeight = 34.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "اكتشاف إعادة التوجيه، قراءة عنوان الصفحة، والتحقق من اتصالك.",
                    color = TextSecondary,
                    fontSize = 14.sp,
                    lineHeight = 21.sp
                )
                Button(
                    onClick = onScan,
                    enabled = !scanning,
                    modifier = Modifier.fillMaxWidth().height(52.dp),
                    shape = RoundedCornerShape(16.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Crimson,
                        contentColor = Color.White,
                        disabledContainerColor = Crimson.copy(alpha = 0.45f)
                    )
                ) {
                    if (scanning) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(19.dp),
                            color = Color.White,
                            strokeWidth = 2.dp
                        )
                        Spacer(Modifier.width(10.dp))
                        Text("جارٍ الفحص…", fontWeight = FontWeight.SemiBold)
                    } else {
                        androidx.compose.material3.Icon(Icons.Outlined.Refresh, contentDescription = null)
                        Spacer(Modifier.width(8.dp))
                        Text("فحص الشبكة", fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }

        Text(
            text = scanMessage,
            color = TextSecondary,
            fontSize = 12.sp,
            modifier = Modifier.padding(horizontal = 4.dp)
        )

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            MetricCard(
                modifier = Modifier.weight(1f),
                label = "نوع الاتصال",
                value = snapshot.networkLabel,
                icon = { androidx.compose.material3.Icon(Icons.Outlined.Wifi, contentDescription = null, tint = Mint) }
            )
            MetricCard(
                modifier = Modifier.weight(1f),
                label = "اكتشاف البوابة",
                value = if (snapshot.detected) "تم اكتشافها" else "العنوان الافتراضي",
                icon = { androidx.compose.material3.Icon(Icons.Outlined.Link, contentDescription = null, tint = Crimson) }
            )
        }

        PortalDetailsCard(snapshot = snapshot)

        ManualLoginCard(
            code = cardCode,
            onCodeChange = onCardCodeChange,
            busy = loginBusy,
            outcome = loginOutcome,
            onLogin = onLogin
        )

        SafeNotice(
            title = "تجربة يدوية فقط",
            body = "أدخل رمزاً مخولاً لك استخدامه. يرسل التطبيق محاولة واحدة عند ضغطك على الزر، ولا يحفظ الرمز."
        )
        Spacer(Modifier.height(4.dp))
    }
}

@Composable
private fun MetricCard(
    modifier: Modifier = Modifier,
    label: String,
    value: String,
    icon: @Composable () -> Unit
) {
    Card(
        modifier = modifier,
        shape = RoundedCornerShape(22.dp),
        colors = CardDefaults.cardColors(containerColor = SurfaceDark),
        border = BorderStroke(1.dp, BorderDark)
    ) {
        Column(
            modifier = Modifier.padding(15.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(34.dp)
                    .clip(RoundedCornerShape(11.dp))
                    .background(SurfaceRaised),
                contentAlignment = Alignment.Center
            ) { icon() }
            Text(label, color = TextSecondary, fontSize = 11.sp)
            Text(
                value,
                color = TextPrimary,
                fontSize = 14.sp,
                lineHeight = 19.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun PortalDetailsCard(snapshot: PortalSnapshot) {
    Card(
        shape = RoundedCornerShape(22.dp),
        colors = CardDefaults.cardColors(containerColor = SurfaceDark),
        border = BorderStroke(1.dp, BorderDark)
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                androidx.compose.material3.Icon(
                    Icons.Outlined.Link,
                    contentDescription = null,
                    tint = Crimson,
                    modifier = Modifier.size(19.dp)
                )
                Spacer(Modifier.width(8.dp))
                Text("تفاصيل البوابة", color = TextPrimary, fontWeight = FontWeight.SemiBold)
            }
            DetailLine(label = "عنوان الصفحة", value = snapshot.pageTitle)
            Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text("Portal URL", color = TextSecondary, fontSize = 11.sp)
                CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                    Text(
                        snapshot.portalUrl,
                        color = Mint,
                        fontSize = 12.sp,
                        lineHeight = 17.sp,
                        textAlign = TextAlign.Start,
                        maxLines = 3,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
    }
}

@Composable
private fun DetailLine(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.Top
    ) {
        Text(label, color = TextSecondary, fontSize = 12.sp)
        Spacer(Modifier.width(12.dp))
        Text(
            value,
            color = TextPrimary,
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium,
            textAlign = TextAlign.End,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun ManualLoginCard(
    code: String,
    onCodeChange: (String) -> Unit,
    busy: Boolean,
    outcome: LoginOutcome?,
    onLogin: () -> Unit
) {
    Card(
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = SurfaceDark),
        border = BorderStroke(1.dp, BorderDark)
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(13.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                androidx.compose.material3.Icon(
                    Icons.Outlined.Login,
                    contentDescription = null,
                    tint = Crimson,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(Modifier.width(9.dp))
                Column {
                    Text("تجربة كرت يدوية", color = TextPrimary, fontWeight = FontWeight.SemiBold)
                    Text("محاولة واحدة للرمز الذي تدخله", color = TextSecondary, fontSize = 11.sp)
                }
            }
            OutlinedTextField(
                value = code,
                onValueChange = onCodeChange,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("كود الكرت") },
                placeholder = { Text("اكتب الرمز كما استلمته") },
                leadingIcon = {
                    androidx.compose.material3.Icon(Icons.Outlined.Lock, contentDescription = null)
                },
                supportingText = { Text("يستخدم الرمز كاسم مستخدم وكلمة مرور.") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Ascii),
                shape = RoundedCornerShape(16.dp)
            )
            Button(
                onClick = onLogin,
                enabled = code.isNotBlank() && !busy,
                modifier = Modifier.fillMaxWidth().height(50.dp),
                shape = RoundedCornerShape(15.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Crimson)
            ) {
                if (busy) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        color = Color.White,
                        strokeWidth = 2.dp
                    )
                    Spacer(Modifier.width(9.dp))
                    Text("جارٍ التحقق…")
                } else {
                    Text("تجربة الكرت", fontWeight = FontWeight.SemiBold)
                }
            }
            if (outcome != null) {
                OutcomeBanner(outcome)
            }
        }
    }
}

@Composable
private fun OutcomeBanner(outcome: LoginOutcome) {
    val tint = if (outcome.success) Mint else Color(0xFFFF727B)
    Surface(
        color = tint.copy(alpha = 0.10f),
        contentColor = tint,
        shape = RoundedCornerShape(15.dp),
        border = BorderStroke(1.dp, tint.copy(alpha = 0.24f))
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(12.dp),
            verticalAlignment = Alignment.Top
        ) {
            androidx.compose.material3.Icon(
                imageVector = if (outcome.success) Icons.Outlined.CheckCircle else Icons.Outlined.ErrorOutline,
                contentDescription = null,
                modifier = Modifier.size(19.dp)
            )
            Spacer(Modifier.width(9.dp))
            Text(outcome.message, fontSize = 13.sp, lineHeight = 19.sp)
        }
    }
}

@Composable
private fun SafeNotice(title: String, body: String) {
    Card(
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = Color(0xFF111E1B)),
        border = BorderStroke(1.dp, Mint.copy(alpha = 0.16f))
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(15.dp),
            verticalAlignment = Alignment.Top
        ) {
            androidx.compose.material3.Icon(
                Icons.Outlined.Shield,
                contentDescription = null,
                tint = Mint,
                modifier = Modifier.size(20.dp)
            )
            Spacer(Modifier.width(10.dp))
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(title, color = TextPrimary, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                Text(body, color = TextSecondary, fontSize = 12.sp, lineHeight = 18.sp)
            }
        }
    }
}

@Composable
private fun DiagnosticsScreen(
    snapshot: PortalSnapshot,
    internetAvailable: Boolean?,
    checkingInternet: Boolean,
    copiedReport: Boolean,
    onInternetCheck: () -> Unit,
    onScan: () -> Unit,
    onCopyReport: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 18.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text("تشخيص الاتصال", color = TextPrimary, fontSize = 25.sp, fontWeight = FontWeight.Bold)
            Text("ملخص سريع لحالة الشبكة والبوابة، دون حفظ بيانات الدخول.", color = TextSecondary, fontSize = 13.sp, lineHeight = 19.sp)
        }

        Card(
            shape = RoundedCornerShape(24.dp),
            colors = CardDefaults.cardColors(containerColor = SurfaceDark),
            border = BorderStroke(1.dp, BorderDark)
        ) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(18.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier.size(42.dp).clip(CircleShape).background(Mint.copy(alpha = 0.12f)),
                        contentAlignment = Alignment.Center
                    ) {
                        androidx.compose.material3.Icon(Icons.Outlined.Wifi, contentDescription = null, tint = Mint)
                    }
                    Spacer(Modifier.width(12.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text("الشبكة الحالية", color = TextPrimary, fontWeight = FontWeight.SemiBold)
                        Text(snapshot.networkLabel, color = TextSecondary, fontSize = 12.sp)
                    }
                    StatusPill(
                        text = when (internetAvailable) {
                            true -> "إنترنت متاح"
                            false -> "غير مؤكد"
                            null -> "لم يُفحص"
                        },
                        color = when (internetAvailable) {
                            true -> Mint
                            false -> Crimson
                            null -> TextSecondary
                        }
                    )
                }
                DetailLine(label = "عنوان الصفحة", value = snapshot.pageTitle)
                Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Text("Portal URL", color = TextSecondary, fontSize = 11.sp)
                    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                        Text(
                            snapshot.portalUrl,
                            color = Mint,
                            fontSize = 12.sp,
                            textAlign = TextAlign.Start,
                            maxLines = 3,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }
        }

        Button(
            onClick = onInternetCheck,
            enabled = !checkingInternet,
            modifier = Modifier.fillMaxWidth().height(52.dp),
            shape = RoundedCornerShape(16.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Crimson)
        ) {
            if (checkingInternet) {
                CircularProgressIndicator(Modifier.size(18.dp), color = Color.White, strokeWidth = 2.dp)
                Spacer(Modifier.width(9.dp))
                Text("جارٍ اختبار الإنترنت…")
            } else {
                androidx.compose.material3.Icon(Icons.Outlined.Wifi, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("اختبار اتصال الإنترنت", fontWeight = FontWeight.SemiBold)
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            OutlinedButton(
                onClick = onScan,
                modifier = Modifier.weight(1f).height(50.dp),
                shape = RoundedCornerShape(15.dp),
                border = BorderStroke(1.dp, BorderDark)
            ) {
                androidx.compose.material3.Icon(Icons.Outlined.Refresh, contentDescription = null)
                Spacer(Modifier.width(7.dp))
                Text("إعادة الفحص", maxLines = 1)
            }
            OutlinedButton(
                onClick = onCopyReport,
                modifier = Modifier.weight(1f).height(50.dp),
                shape = RoundedCornerShape(15.dp),
                border = BorderStroke(1.dp, BorderDark)
            ) {
                androidx.compose.material3.Icon(Icons.Outlined.ContentCopy, contentDescription = null)
                Spacer(Modifier.width(7.dp))
                Text(if (copiedReport) "تم النسخ" else "نسخ التقرير", maxLines = 1)
            }
        }

        SafeNotice(
            title = "خصوصيتك أولاً",
            body = "لا يطلب التطبيق صلاحيات التخزين أو الموقع، ولا يسجل رمز الكرت في التقرير التشخيصي. استخدمه على شبكة تملكها أو لديك إذن بإدارتها."
        )
        Spacer(Modifier.height(4.dp))
    }
}

@Composable
private fun StatusPill(text: String, color: Color) {
    Surface(
        color = color.copy(alpha = 0.11f),
        shape = RoundedCornerShape(100.dp)
    ) {
        Text(
            text = text,
            color = color,
            fontSize = 10.sp,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
            maxLines = 1
        )
    }
}

private data class PortalSnapshot(
    val portalUrl: String = PortalRepository.DEFAULT_PORTAL,
    val pageTitle: String = "بانتظار الفحص",
    val networkLabel: String = "جارٍ تحديد الاتصال…",
    val detected: Boolean = false
)

private data class LoginOutcome(
    val success: Boolean,
    val message: String
)

/**
 * Portal discovery and one user-initiated login request. There is deliberately no
 * batch credential testing, retry loop, or credential-list generation.
 */
private object PortalRepository {
    const val DEFAULT_PORTAL = "http://192.168.88.1/login"
    private const val CONNECTIVITY_URL = "http://connectivitycheck.gstatic.com/generate_204"
    private const val USER_AGENT = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

    private val probeClient = OkHttpClient.Builder()
        .followRedirects(false)
        .followSslRedirects(false)
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(5, TimeUnit.SECONDS)
        .writeTimeout(5, TimeUnit.SECONDS)
        .build()

    private val loginClient = probeClient.newBuilder()
        .followRedirects(true)
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(8, TimeUnit.SECONDS)
        .writeTimeout(8, TimeUnit.SECONDS)
        .build()

    suspend fun discoverPortal(): PortalSnapshot = withContext(Dispatchers.IO) {
        val discoveredUrl = try {
            val request = Request.Builder()
                .url(CONNECTIVITY_URL)
                .header("User-Agent", USER_AGENT)
                .get()
                .build()
            probeClient.newCall(request).execute().use { response ->
                when (response.code) {
                    301, 302, 307, 308 -> response.header("Location")?.let { location ->
                        response.request.url.resolve(location)?.toString() ?: location
                    }
                    200 -> {
                        val html = response.body?.string().orEmpty()
                        findRedirectLink(html, response.request.url)
                    }
                    else -> null
                }
            }
        } catch (_: Exception) {
            null
        }

        val selectedUrl = discoveredUrl?.takeIf { it.toHttpUrlOrNull() != null } ?: DEFAULT_PORTAL
        PortalSnapshot(
            portalUrl = selectedUrl,
            pageTitle = fetchPageTitle(selectedUrl),
            networkLabel = "غير محدد",
            detected = discoveredUrl != null
        )
    }

    suspend fun verifyInternet(): Boolean = withContext(Dispatchers.IO) {
        verifyInternetBlocking()
    }

    suspend fun loginOnce(portalUrl: String, code: String): LoginOutcome = withContext(Dispatchers.IO) {
        val safeCode = code.trim()
        if (safeCode.isEmpty()) {
            return@withContext LoginOutcome(false, "أدخل كود الكرت أولاً.")
        }
        val endpoint = makeLoginUrl(portalUrl)
            ?: return@withContext LoginOutcome(false, "تعذّر قراءة عنوان البوابة. أعد الفحص ثم تحقق من الرابط.")

        try {
            val request = Request.Builder()
                .url(endpoint)
                .header("User-Agent", USER_AGENT)
                .header("Referer", portalUrl)
                .post(
                    FormBody.Builder()
                        .add("username", safeCode)
                        .add("password", safeCode)
                        .add("dst", "http://www.google.com")
                        .build()
                )
                .build()

            val responseSummary = loginClient.newCall(request).execute().use { response ->
                val html = response.body?.string().orEmpty()
                ResponseSummary(
                    code = response.code,
                    portalError = extractPortalError(html)
                )
            }

            if (verifyInternetBlocking()) {
                LoginOutcome(true, "تم إرسال الرمز وأصبح اتصال الإنترنت متاحاً.")
            } else {
                val detail = responseSummary.portalError
                    ?: if (responseSummary.code in 200..299) {
                        "لم تؤكد البوابة إتاحة الإنترنت بعد. تحقق من الرمز ورابط البوابة."
                    } else {
                        "استجابت البوابة برمز HTTP ${responseSummary.code} ولم يتأكد اتصال الإنترنت."
                    }
                LoginOutcome(false, detail)
            }
        } catch (_: Exception) {
            LoginOutcome(false, "تعذّر الاتصال بالبوابة. تحقق من الشبكة والرابط ثم حاول يدوياً مرة أخرى.")
        }
    }

    fun currentNetworkLabel(context: Context): String {
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return "حالة الشبكة غير متاحة"
        val network = manager.activeNetwork ?: return "غير متصل"
        val capabilities = manager.getNetworkCapabilities(network) ?: return "متصل"
        return when {
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi‑Fi متصل"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "بيانات الهاتف"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "Ethernet متصل"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "اتصال VPN"
            else -> "شبكة متصلة"
        }
    }

    private fun findRedirectLink(html: String, baseUrl: HttpUrl): String? {
        val regex = Regex("""(?is)href\s*=\s*["']([^"']+)["']|url\s*=\s*["']([^"']+)["']""")
        val match = regex.find(html) ?: return null
        val raw = match.groupValues.getOrNull(1)?.takeIf { it.isNotBlank() }
            ?: match.groupValues.getOrNull(2)?.takeIf { it.isNotBlank() }
            ?: return null
        return baseUrl.resolve(raw)?.toString() ?: raw
    }

    private fun fetchPageTitle(url: String): String {
        val parsed = url.toHttpUrlOrNull() ?: return "بدون عنوان"
        return try {
            val client = probeClient.newBuilder().followRedirects(true).build()
            val request = Request.Builder()
                .url(parsed)
                .header("User-Agent", USER_AGENT)
                .get()
                .build()
            client.newCall(request).execute().use { response ->
                val html = response.body?.string().orEmpty()
                val title = Regex("""(?is)<title[^>]*>(.*?)</title>""")
                    .find(html)
                    ?.groupValues
                    ?.getOrNull(1)
                    ?.let(::htmlToText)
                    ?.replace(Regex("\\s+"), " ")
                    ?.trim()
                    ?.take(120)
                title?.takeIf { it.isNotBlank() } ?: "بدون عنوان"
            }
        } catch (_: Exception) {
            "بدون عنوان"
        }
    }

    private fun makeLoginUrl(portalUrl: String): HttpUrl? {
        val parsed = portalUrl.toHttpUrlOrNull() ?: DEFAULT_PORTAL.toHttpUrl()
        return if (parsed.encodedPath.endsWith("/login", ignoreCase = true)) {
            parsed
        } else {
            parsed.newBuilder()
                .encodedPath("/login")
                .query(null)
                .fragment(null)
                .build()
        }
    }

    private fun verifyInternetBlocking(): Boolean {
        return try {
            val request = Request.Builder()
                .url(CONNECTIVITY_URL)
                .header("User-Agent", USER_AGENT)
                .get()
                .build()
            probeClient.newCall(request).execute().use { response -> response.code == 204 }
        } catch (_: Exception) {
            false
        }
    }

    private fun extractPortalError(html: String): String? {
        if (html.isBlank()) return null
        val structured = Regex(
            """(?is)<(?:div|span|p)[^>]*(?:class|id)\s*=\s*["'][^"']*(?:error|alert|notice|message)[^"']*["'][^>]*>(.*?)</(?:div|span|p)>"""
        ).find(html)?.groupValues?.getOrNull(1)
        val text = htmlToText(structured ?: html)
            .replace(Regex("\\s+"), " ")
            .trim()
        if (text.isBlank()) return null

        val terms = listOf(
            "invalid", "incorrect", "wrong", "expired", "disabled", "error", "failed",
            "not authorized", "невер", "ошиб", "истек", "منتهي", "خطأ", "غير صحيح", "انته"
        )
        val candidate = text.split(Regex("(?<=[.!?])\\s+|\\n"))
            .map(String::trim)
            .firstOrNull { part ->
                part.length in 3..240 && terms.any { term -> part.contains(term, ignoreCase = true) }
            }
        return (candidate ?: structured?.let { text.takeIf { value -> value.length <= 180 } })?.take(180)
    }

    private fun htmlToText(value: String): String =
        Html.fromHtml(value, Html.FROM_HTML_MODE_LEGACY).toString()

    private data class ResponseSummary(val code: Int, val portalError: String?)
}
