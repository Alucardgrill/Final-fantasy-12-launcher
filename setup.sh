#!/usr/bin/env bash
# Recria o projeto Ivalice Launcher a partir deste arquivo único.
set -e
mkdir -p "."
cat > "README.md" <<'__IVALICE_EOF__'
# Ivalice Launcher

Launcher Android (Kotlin + Jetpack Compose) para iniciar a **sua própria ISO de PS2**
em um emulador instalado no aparelho (NetherSX2/AetherSX2 ou Play!), com perfis gráficos.

O app não contém, baixa nem distribui nenhum código ou conteúdo de jogo.

## Recursos

- Seletor de ISO (com verificação da assinatura ISO 9660)
- Perfis gráficos salvos: emulador, renderizador (Vulkan/OpenGL/Software), resolução interna 1x–4x,
  velocidade, proporção de tela, widescreen, bilinear, frame skip, mostrar FPS
- Botão JOGAR que abre o emulador escolhido com a ISO
- Resumo do perfil para copiar e aplicar no emulador
- Aba de ajuda com o passo a passo

## Como gerar o APK

### Opção A, Android Studio
1. Abra a pasta `ivalice-launcher` no Android Studio (Hedgehog ou mais novo).
2. Aguarde o Gradle sincronizar.
3. Menu **Build > Build APK(s)**. O arquivo sai em `app/build/outputs/apk/debug/app-debug.apk`.

### Opção B, GitHub Actions (sem instalar nada)
1. Crie um repositório no GitHub e envie esta pasta.
2. Abra a aba **Actions**, rode **Build APK** e baixe o artefato `ivalice-launcher-apk`.

### Opção C, linha de comando
Com JDK 17+ e Android SDK instalados: `gradle assembleDebug`

## Observações honestas

- As configurações gráficas ficam no launcher. Cada emulador mantém as próprias configurações,
  então o launcher não as injeta nele; use o resumo como referência.
- O atalho direto para abrir a ISO (intent) depende da versão do emulador e não foi testado em
  aparelho. Se falhar, o app abre o emulador para você escolher a ISO lá.
- O APK gerado é de debug (instalável, assinado com a chave de debug).
__IVALICE_EOF__
mkdir -p "app"
cat > "app/build.gradle.kts" <<'__IVALICE_EOF__'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.ivalice"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.ivalice"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
    }
    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.14"
    }
    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.06.00")
    implementation(composeBom)
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.8.3")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-core")
    debugImplementation("androidx.compose.ui:ui-tooling")
}
__IVALICE_EOF__
mkdir -p "app/src/main"
cat > "app/src/main/AndroidManifest.xml" <<'__IVALICE_EOF__'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <!-- Necessário para detectar se o emulador está instalado (Android 11+) -->
    <queries>
        <package android:name="xyz.aethersx2.android" />
        <package android:name="com.virtualapplications.play" />
    </queries>

    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:supportsRtl="true"
        android:theme="@style/Theme.Ivalice">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:configChanges="orientation|screenSize|keyboardHidden"
            android:theme="@style/Theme.Ivalice">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>

</manifest>
__IVALICE_EOF__
mkdir -p "app/src/main/java/com/example/ivalice"
cat > "app/src/main/java/com/example/ivalice/AppViewModel.kt" <<'__IVALICE_EOF__'
package com.example.ivalice

import android.app.Application
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class AppViewModel(app: Application) : AndroidViewModel(app) {
    private val store = ProfileStore(app)

    var profiles by mutableStateOf(store.loadProfiles())
        private set
    var selected by mutableStateOf(store.loadSelected(profiles.size))
        private set
    var isoUri by mutableStateOf(store.loadIso()?.let { Uri.parse(it) })
        private set
    var isoStatus by mutableStateOf<IsoStatus>(IsoStatus.None)
        private set

    val current: GraphicsProfile get() = profiles[selected]

    init {
        isoUri?.let { validate(it) }
    }

    fun setIso(uri: Uri) {
        isoUri = uri
        store.saveIso(uri.toString())
        validate(uri)
    }

    private fun validate(uri: Uri) {
        viewModelScope.launch {
            val status = withContext(Dispatchers.IO) { IsoChecker.check(getApplication(), uri) }
            isoStatus = status
        }
    }

    fun update(p: GraphicsProfile) {
        profiles = profiles.toMutableList().also { it[selected] = p }
        store.saveProfiles(profiles)
    }

    fun select(i: Int) {
        selected = i.coerceIn(0, profiles.lastIndex)
        store.saveSelected(selected)
    }

    fun addProfile() {
        val copy = current.copy(name = "Perfil ${profiles.size + 1}")
        profiles = profiles + copy
        store.saveProfiles(profiles)
        select(profiles.lastIndex)
    }

    fun deleteCurrent() {
        if (profiles.size <= 1) return
        profiles = profiles.toMutableList().also { it.removeAt(selected) }
        store.saveProfiles(profiles)
        select(selected.coerceAtMost(profiles.lastIndex))
    }
}
__IVALICE_EOF__
mkdir -p "app/src/main/java/com/example/ivalice"
cat > "app/src/main/java/com/example/ivalice/EmulatorLauncher.kt" <<'__IVALICE_EOF__'
package com.example.ivalice

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import java.io.FileInputStream

sealed interface IsoStatus {
    data object None : IsoStatus
    data class Valid(val name: String, val sizeMb: Long) : IsoStatus
    data class Invalid(val reason: String) : IsoStatus
}

object IsoChecker {
    /** Verifica se o arquivo parece uma imagem ISO 9660 (assinatura "CD001" no setor 16). */
    fun check(context: Context, uri: Uri): IsoStatus {
        return try {
            var name = "jogo.iso"
            var size = 0L
            context.contentResolver.query(uri, null, null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val ni = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val si = c.getColumnIndex(OpenableColumns.SIZE)
                    if (ni >= 0) name = c.getString(ni) ?: name
                    if (si >= 0) size = c.getLong(si)
                }
            }
            val pfd = context.contentResolver.openFileDescriptor(uri, "r")
                ?: return IsoStatus.Invalid("Não foi possível abrir o arquivo.")
            pfd.use {
                FileInputStream(it.fileDescriptor).channel.use { ch ->
                    ch.position(0x8001)
                    val buf = java.nio.ByteBuffer.allocate(5)
                    ch.read(buf)
                    val sig = String(buf.array(), Charsets.US_ASCII)
                    if (sig != "CD001") {
                        return IsoStatus.Invalid("Isso não parece uma ISO válida de PS2 (assinatura ISO 9660 ausente).")
                    }
                }
            }
            IsoStatus.Valid(name, size / (1024 * 1024))
        } catch (e: Exception) {
            IsoStatus.Invalid("Erro ao ler o arquivo: ${e.message}")
        }
    }
}

object EmulatorLauncher {
    fun isInstalled(context: Context, emulator: Emulator): Boolean =
        try {
            context.packageManager.getPackageInfo(emulator.pkg, 0)
            true
        } catch (_: Exception) {
            false
        }

    /** Retorna uma mensagem de erro/aviso, ou null se o emulador foi aberto com a ISO. */
    fun launch(context: Context, iso: Uri, profile: GraphicsProfile): String? {
        val emu = profile.emulator
        if (!isInstalled(context, emu)) {
            return "${emu.label} não está instalado neste aparelho."
        }
        val intent = when (emu) {
            Emulator.NETHERSX2 -> Intent(Intent.ACTION_MAIN).apply {
                setClassName(emu.pkg, "xyz.aethersx2.android.EmulationActivity")
                putExtra("bootPath", iso.toString())
            }
            Emulator.PLAY -> Intent(Intent.ACTION_VIEW).apply {
                setPackage(emu.pkg)
                setDataAndType(iso, "*/*")
            }
        }.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)

        return try {
            context.startActivity(intent)
            null
        } catch (_: Exception) {
            // Plano B: abre o emulador normalmente para o usuário escolher a ISO lá.
            val fallback = context.packageManager.getLaunchIntentForPackage(emu.pkg)
            if (fallback != null) {
                fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(fallback)
                "Abri o ${emu.label}, mas ele não aceitou o atalho direto. Selecione a ISO dentro dele."
            } else {
                "Não consegui abrir o ${emu.label}."
            }
        }
    }
}
__IVALICE_EOF__
mkdir -p "app/src/main/java/com/example/ivalice"
cat > "app/src/main/java/com/example/ivalice/MainActivity.kt" <<'__IVALICE_EOF__'
package com.example.ivalice

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels

class MainActivity : ComponentActivity() {
    private val vm: AppViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val picker = rememberLauncherForActivityResult(
                ActivityResultContracts.OpenDocument()
            ) { uri ->
                if (uri != null) {
                    try {
                        contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    } catch (_: Exception) {
                    }
                    vm.setIso(uri)
                }
            }
            IvaliceTheme {
                AppRoot(vm = vm, onPickIso = { picker.launch(arrayOf("*/*")) })
            }
        }
    }
}
__IVALICE_EOF__
mkdir -p "app/src/main/java/com/example/ivalice"
cat > "app/src/main/java/com/example/ivalice/Screens.kt" <<'__IVALICE_EOF__'
package com.example.ivalice

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun AppRoot(vm: AppViewModel, onPickIso: () -> Unit) {
    var tab by remember { mutableIntStateOf(0) }
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        bottomBar = {
            NavigationBar(containerColor = NavySurface) {
                val colors = NavigationBarItemDefaults.colors(
                    selectedIconColor = Color(0xFF2A1F05),
                    selectedTextColor = Gold,
                    indicatorColor = Gold,
                    unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant
                )
                NavigationBarItem(
                    selected = tab == 0, onClick = { tab = 0 }, colors = colors,
                    icon = { Icon(Icons.Filled.PlayArrow, contentDescription = null) },
                    label = { Text("Jogar") }
                )
                NavigationBarItem(
                    selected = tab == 1, onClick = { tab = 1 }, colors = colors,
                    icon = { Icon(Icons.Filled.Settings, contentDescription = null) },
                    label = { Text("Gráficos") }
                )
                NavigationBarItem(
                    selected = tab == 2, onClick = { tab = 2 }, colors = colors,
                    icon = { Icon(Icons.Filled.Info, contentDescription = null) },
                    label = { Text("Ajuda") }
                )
            }
        }
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when (tab) {
                0 -> HomeScreen(vm, onPickIso)
                1 -> GraphicsScreen(vm)
                else -> HelpScreen()
            }
        }
    }
}

// ---------------------------------------------------------------- Jogar

@Composable
fun HomeScreen(vm: AppViewModel, onPickIso: () -> Unit) {
    val ctx = LocalContext.current
    val profile = vm.current
    val status = vm.isoStatus
    val ready = status is IsoStatus.Valid && vm.isoUri != null

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Cabeçalho
        Box(
            Modifier.fillMaxWidth()
                .background(
                    Brush.verticalGradient(listOf(Color(0xFF2B3A67), Color(0xFF151B2D))),
                    RoundedCornerShape(24.dp)
                )
                .padding(24.dp)
        ) {
            Column {
                Text("IVALICE", color = Gold, fontSize = 13.sp, fontWeight = FontWeight.Bold, letterSpacing = 4.sp)
                Spacer(Modifier.height(4.dp))
                Text("Launcher", fontSize = 34.sp, fontWeight = FontWeight.Bold, color = Color.White)
                Spacer(Modifier.height(6.dp))
                Text(
                    "Inicie a sua própria ISO do PS2 com o perfil gráfico que você escolher.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        // Cartão da ISO
        SectionCard("Sua ISO") {
            when (status) {
                is IsoStatus.None -> Text(
                    "Nenhuma ISO selecionada. Você precisa da imagem do seu próprio disco.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                is IsoStatus.Valid -> {
                    Text(status.name, fontWeight = FontWeight.SemiBold)
                    Text("${status.sizeMb} MB · formato ISO reconhecido", color = Color(0xFF8EDC9D))
                }
                is IsoStatus.Invalid -> Text(status.reason, color = MaterialTheme.colorScheme.error)
            }
            Spacer(Modifier.height(12.dp))
            OutlinedButton(onClick = onPickIso, modifier = Modifier.fillMaxWidth()) {
                Text(if (vm.isoUri == null) "Escolher ISO" else "Trocar ISO")
            }
        }

        // Perfil ativo
        SectionCard("Perfil ativo") {
            Text(profile.name, fontWeight = FontWeight.SemiBold, fontSize = 18.sp)
            Text(
                "${profile.emulator.label} · ${profile.renderer.label} · ${profile.resolutionLabel()}",
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            if (!EmulatorLauncher.isInstalled(ctx, profile.emulator)) {
                Spacer(Modifier.height(8.dp))
                Text(
                    "${profile.emulator.label} não está instalado. Veja a aba Ajuda.",
                    color = MaterialTheme.colorScheme.error
                )
            }
        }

        Button(
            onClick = {
                val uri = vm.isoUri
                if (uri != null) {
                    EmulatorLauncher.launch(ctx, uri, profile)?.let {
                        Toast.makeText(ctx, it, Toast.LENGTH_LONG).show()
                    }
                }
            },
            enabled = ready,
            modifier = Modifier.fillMaxWidth().height(60.dp),
            shape = RoundedCornerShape(18.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Gold, contentColor = Color(0xFF2A1F05))
        ) {
            Icon(Icons.Filled.PlayArrow, contentDescription = null)
            Spacer(Modifier.width(8.dp))
            Text("JOGAR", fontSize = 18.sp, fontWeight = FontWeight.Bold, letterSpacing = 2.sp)
        }
    }
}

// ---------------------------------------------------------------- Gráficos

@Composable
fun GraphicsScreen(vm: AppViewModel) {
    val ctx = LocalContext.current
    val p = vm.current

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text("Configurações gráficas", fontSize = 26.sp, fontWeight = FontWeight.Bold)

        // Perfis
        SectionCard("Perfis") {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                itemsIndexed(vm.profiles) { i, prof ->
                    FilterChip(
                        selected = i == vm.selected,
                        onClick = { vm.select(i) },
                        label = { Text(prof.name) }
                    )
                }
                item {
                    IconButton(onClick = { vm.addProfile() }) {
                        Icon(Icons.Filled.Add, contentDescription = "Novo perfil", tint = Gold)
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(
                    value = p.name,
                    onValueChange = { vm.update(p.copy(name = it.take(24))) },
                    label = { Text("Nome do perfil") },
                    singleLine = true,
                    modifier = Modifier.weight(1f)
                )
                if (vm.profiles.size > 1) {
                    IconButton(onClick = { vm.deleteCurrent() }) {
                        Icon(Icons.Filled.Delete, contentDescription = "Apagar perfil", tint = MaterialTheme.colorScheme.error)
                    }
                }
            }
        }

        // Emulador
        SectionCard("Emulador") {
            ChipRow(Emulator.entries, p.emulator, { it.label }) { vm.update(p.copy(emulator = it)) }
        }

        // Renderizador
        SectionCard("Renderizador") {
            ChipRow(Renderer.entries, p.renderer, { it.label }) { vm.update(p.copy(renderer = it)) }
        }

        // Resolução
        SectionCard("Resolução interna") {
            Text(p.resolutionLabel(), color = Gold, fontWeight = FontWeight.SemiBold)
            Slider(
                value = p.resolutionScale.toFloat(),
                onValueChange = { vm.update(p.copy(resolutionScale = it.toInt().coerceIn(1, 4))) },
                valueRange = 1f..4f,
                steps = 2
            )
            Text(
                "Valores altos pedem GPU mais forte. Em aparelhos medianos, 2x costuma ser o ideal.",
                color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp
            )
        }

        // Velocidade
        SectionCard("Velocidade da emulação") {
            ChipRow(listOf(50, 75, 100, 150, 200), p.speedPercent, { "$it%" }) {
                vm.update(p.copy(speedPercent = it))
            }
        }

        // Proporção
        SectionCard("Proporção de tela") {
            ChipRow(AspectRatio.entries, p.aspect, { it.label }) { vm.update(p.copy(aspect = it)) }
        }

        // Opções
        SectionCard("Opções") {
            ToggleRow("Patch widescreen (16:9)", p.widescreenPatch) { vm.update(p.copy(widescreenPatch = it)) }
            ToggleRow("Filtro bilinear", p.bilinear) { vm.update(p.copy(bilinear = it)) }
            ToggleRow("Frame skip", p.frameSkip) { vm.update(p.copy(frameSkip = it)) }
            ToggleRow("Mostrar FPS", p.showFps) { vm.update(p.copy(showFps = it)) }
        }

        // Resumo
        SectionCard("Resumo do perfil") {
            Text(p.summary(), color = MaterialTheme.colorScheme.onSurfaceVariant, lineHeight = 22.sp)
            Spacer(Modifier.height(12.dp))
            OutlinedButton(
                onClick = {
                    val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    cm.setPrimaryClip(ClipData.newPlainText("perfil", p.summary()))
                    Toast.makeText(ctx, "Resumo copiado", Toast.LENGTH_SHORT).show()
                },
                modifier = Modifier.fillMaxWidth()
            ) { Text("Copiar resumo") }
            Spacer(Modifier.height(6.dp))
            Text(
                "O launcher guarda seus perfis, mas cada emulador mantém as próprias configurações. " +
                    "Use este resumo como referência para ajustar o emulador.",
                color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp
            )
        }
    }
}

// ---------------------------------------------------------------- Ajuda

@Composable
fun HelpScreen() {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text("Como usar", fontSize = 26.sp, fontWeight = FontWeight.Bold)

        SectionCard("1. Instale um emulador de PS2") {
            Text(
                "Este app é só um iniciador. Ele abre a ISO em um emulador instalado no aparelho: " +
                    "NetherSX2 / AetherSX2 ou Play!.",
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        SectionCard("2. Tenha a sua própria ISO") {
            Text(
                "Use a imagem do seu disco original, extraída do seu console ou do seu disco. " +
                    "O app não inclui, baixa nem distribui nenhum conteúdo do jogo.",
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        SectionCard("3. BIOS") {
            Text(
                "O NetherSX2/AetherSX2 exige uma BIOS de PS2, que você deve extrair do seu próprio console. " +
                    "Configure-a dentro do emulador, uma vez.",
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        SectionCard("4. Escolha a ISO e jogue") {
            Text(
                "Na aba Jogar, selecione a ISO, escolha o perfil gráfico e toque em JOGAR. " +
                    "Se o emulador não aceitar o atalho direto, o app abre ele para você escolher a ISO lá.",
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        SectionCard("Sobre") {
            Text(
                "Ivalice Launcher é um projeto independente, sem vínculo com a Square Enix. " +
                    "Nomes e marcas pertencem aos seus donos.",
                color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp
            )
        }
    }
}

// ---------------------------------------------------------------- Componentes

@Composable
fun SectionCard(title: String, content: @Composable () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
    ) {
        Column(Modifier.padding(18.dp)) {
            Text(title, color = Gold, fontWeight = FontWeight.Bold, fontSize = 13.sp, letterSpacing = 1.sp)
            Spacer(Modifier.height(10.dp))
            content()
        }
    }
}

@Composable
fun ToggleRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
fun <T> ChipRow(items: List<T>, selected: T, label: (T) -> String, onSelect: (T) -> Unit) {
    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        itemsIndexed(items) { _, item ->
            FilterChip(
                selected = item == selected,
                onClick = { onSelect(item) },
                label = { Text(label(item)) }
            )
        }
    }
}
__IVALICE_EOF__
mkdir -p "app/src/main/java/com/example/ivalice"
cat > "app/src/main/java/com/example/ivalice/Settings.kt" <<'__IVALICE_EOF__'
package com.example.ivalice

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

enum class Emulator(val label: String, val pkg: String) {
    NETHERSX2("NetherSX2 / AetherSX2", "xyz.aethersx2.android"),
    PLAY("Play!", "com.virtualapplications.play")
}

enum class Renderer(val label: String) {
    VULKAN("Vulkan"),
    OPENGL("OpenGL"),
    SOFTWARE("Software")
}

enum class AspectRatio(val label: String) {
    AUTO("Auto (4:3)"),
    WIDE("16:9"),
    STRETCH("Esticar")
}

data class GraphicsProfile(
    val name: String = "Padrão",
    val emulator: Emulator = Emulator.NETHERSX2,
    val renderer: Renderer = Renderer.VULKAN,
    val resolutionScale: Int = 2,
    val speedPercent: Int = 100,
    val aspect: AspectRatio = AspectRatio.AUTO,
    val widescreenPatch: Boolean = false,
    val bilinear: Boolean = true,
    val frameSkip: Boolean = false,
    val showFps: Boolean = true
) {
    fun resolutionLabel(): String = when (resolutionScale) {
        1 -> "1x (nativo)"
        2 -> "2x (≈ 720p)"
        3 -> "3x (≈ 1080p)"
        else -> "4x (≈ 1440p)"
    }

    /** Resumo legível para o usuário aplicar manualmente no emulador. */
    fun summary(): String = buildString {
        appendLine("Perfil: $name")
        appendLine("Emulador: ${emulator.label}")
        appendLine("Renderizador: ${renderer.label}")
        appendLine("Resolução interna: ${resolutionLabel()}")
        appendLine("Velocidade: $speedPercent%")
        appendLine("Proporção: ${aspect.label}")
        appendLine("Patch widescreen: ${if (widescreen()) "ligado" else "desligado"}")
        appendLine("Filtro bilinear: ${if (bilinear) "ligado" else "desligado"}")
        appendLine("Frame skip: ${if (frameSkip) "ligado" else "desligado"}")
        append("Mostrar FPS: ${if (showFps) "sim" else "não"}")
    }

    private fun widescreen() = widescreenPatch

    fun toJson(): JSONObject = JSONObject().apply {
        put("name", name)
        put("emulator", emulator.name)
        put("renderer", renderer.name)
        put("resolutionScale", resolutionScale)
        put("speedPercent", speedPercent)
        put("aspect", aspect.name)
        put("widescreenPatch", widescreenPatch)
        put("bilinear", bilinear)
        put("frameSkip", frameSkip)
        put("showFps", showFps)
    }

    companion object {
        private inline fun <reified T : Enum<T>> JSONObject.enumOr(key: String, def: T): T =
            try {
                enumValueOf<T>(optString(key, def.name))
            } catch (_: Exception) {
                def
            }

        fun fromJson(o: JSONObject): GraphicsProfile {
            val d = GraphicsProfile()
            return GraphicsProfile(
                name = o.optString("name", d.name),
                emulator = o.enumOr("emulator", d.emulator),
                renderer = o.enumOr("renderer", d.renderer),
                resolutionScale = o.optInt("resolutionScale", d.resolutionScale).coerceIn(1, 4),
                speedPercent = o.optInt("speedPercent", d.speedPercent).coerceIn(50, 200),
                aspect = o.enumOr("aspect", d.aspect),
                widescreenPatch = o.optBoolean("widescreenPatch", d.widescreenPatch),
                bilinear = o.optBoolean("bilinear", d.bilinear),
                frameSkip = o.optBoolean("frameSkip", d.frameSkip),
                showFps = o.optBoolean("showFps", d.showFps)
            )
        }
    }
}

/** Persistência simples em SharedPreferences (sem dependências extras). */
class ProfileStore(context: Context) {
    private val prefs = context.getSharedPreferences("ivalice_launcher", Context.MODE_PRIVATE)

    fun loadProfiles(): List<GraphicsProfile> {
        val raw = prefs.getString("profiles", null) ?: return listOf(GraphicsProfile())
        return try {
            val arr = JSONArray(raw)
            val list = (0 until arr.length()).map { GraphicsProfile.fromJson(arr.getJSONObject(it)) }
            list.ifEmpty { listOf(GraphicsProfile()) }
        } catch (_: Exception) {
            listOf(GraphicsProfile())
        }
    }

    fun saveProfiles(list: List<GraphicsProfile>) {
        val arr = JSONArray()
        list.forEach { arr.put(it.toJson()) }
        prefs.edit().putString("profiles", arr.toString()).apply()
    }

    fun loadSelected(size: Int): Int = prefs.getInt("selected", 0).coerceIn(0, (size - 1).coerceAtLeast(0))
    fun saveSelected(i: Int) = prefs.edit().putInt("selected", i).apply()

    fun loadIso(): String? = prefs.getString("iso_uri", null)
    fun saveIso(uri: String?) = prefs.edit().putString("iso_uri", uri).apply()
}
__IVALICE_EOF__
mkdir -p "app/src/main/java/com/example/ivalice"
cat > "app/src/main/java/com/example/ivalice/Theme.kt" <<'__IVALICE_EOF__'
package com.example.ivalice

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val Gold = Color(0xFFE8C26A)
val Navy = Color(0xFF0E1320)
val NavySurface = Color(0xFF151B2D)
val NavyCard = Color(0xFF1C2440)

private val Scheme = darkColorScheme(
    primary = Gold,
    onPrimary = Color(0xFF2A1F05),
    secondary = Color(0xFF7FA6E8),
    background = Navy,
    onBackground = Color(0xFFEDEFF7),
    surface = NavySurface,
    onSurface = Color(0xFFEDEFF7),
    surfaceVariant = NavyCard,
    onSurfaceVariant = Color(0xFFB9C0D8),
    error = Color(0xFFFF8A80)
)

@Composable
fun IvaliceTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = Scheme, content = content)
}
__IVALICE_EOF__
mkdir -p "app/src/main/res/drawable"
cat > "app/src/main/res/drawable/ic_launcher_foreground.xml" <<'__IVALICE_EOF__'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <!-- Cristal genérico (design original) -->
    <path
        android:fillColor="#E8C26A"
        android:pathData="M54,22 L72,54 L54,86 L36,54 Z" />
    <path
        android:fillColor="#B8893A"
        android:pathData="M54,22 L72,54 L54,54 Z" />
    <path
        android:fillColor="#F6E3A8"
        android:pathData="M54,22 L36,54 L54,54 Z" />
</vector>
__IVALICE_EOF__
mkdir -p "app/src/main/res/mipmap-anydpi-v26"
cat > "app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml" <<'__IVALICE_EOF__'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
__IVALICE_EOF__
mkdir -p "app/src/main/res/values"
cat > "app/src/main/res/values/ic_launcher_background.xml" <<'__IVALICE_EOF__'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#151B2D</color>
</resources>
__IVALICE_EOF__
mkdir -p "app/src/main/res/values"
cat > "app/src/main/res/values/strings.xml" <<'__IVALICE_EOF__'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">Ivalice Launcher</string>
</resources>
__IVALICE_EOF__
mkdir -p "app/src/main/res/values"
cat > "app/src/main/res/values/themes.xml" <<'__IVALICE_EOF__'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="Theme.Ivalice" parent="android:Theme.Material.NoActionBar">
        <item name="android:windowBackground">#0E1320</item>
        <item name="android:statusBarColor">#0E1320</item>
        <item name="android:navigationBarColor">#151B2D</item>
    </style>
</resources>
__IVALICE_EOF__
mkdir -p "."
cat > "build.gradle.kts" <<'__IVALICE_EOF__'
plugins {
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}
__IVALICE_EOF__
mkdir -p "."
cat > "gradle.properties" <<'__IVALICE_EOF__'
org.gradle.jvmargs=-Xmx3g -Dfile.encoding=UTF-8
android.useAndroidX=true
android.nonTransitiveRClass=true
kotlin.code.style=official
__IVALICE_EOF__
mkdir -p "."
cat > "settings.gradle.kts" <<'__IVALICE_EOF__'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "IvaliceLauncher"
include(":app")
__IVALICE_EOF__
