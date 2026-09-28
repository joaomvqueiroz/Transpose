package com.example.transpose_mobile

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONObject

/** App-owned, offline inference. Only the model is fetched over HTTPS. */
class StemEngine private constructor(private val context: Context) {
    private external fun available(): Boolean
    private external fun resetNative()
    private external fun cancelNative()
    private external fun progressNative(): Int
    private external fun purgeNative(sdkInt: Int): Int
    private external fun separateNative(model: String, input: String, output: String): String?

    private var channel: MethodChannel? = null
    private var attachedMessenger: BinaryMessenger? = null
    private val worker = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    private val cancelled = AtomicBoolean(false)
    private val modelDir = File(context.filesDir, "stems")
    private val modelFile = File(modelDir, "ggml-model-htdemucs-6s-f16.bin")
    private val resultManifest = File(modelDir, "last_result.json")
    @Volatile private var modelVerified = false
    @Volatile private var phase = "idle"
    @Volatile private var downloaded = 0L
    @Volatile private var resultPaths: Map<String, String>? = null
    @Volatile private var error: String? = null

    init {
        System.loadLibrary("transpono_stems")
        restoreResult()
        worker.execute {
            modelVerified = validModel()
            if (modelVerified && phase == "idle") phase = "ready"
        }
    }

    private fun bind(messenger: BinaryMessenger) {
        channel?.setMethodCallHandler(null)
        attachedMessenger = messenger
        channel = MethodChannel(messenger, "transpose/stems")
        channel?.setMethodCallHandler { call, reply ->
            when (call.method) {
                "available" -> reply.success(available())
                "status" -> reply.success(status())
                "prepare" -> {
                    if (!available()) reply.error("UNAVAILABLE", "Separação disponível apenas em Android ARM64 com o motor incluído.", null)
                    else if (!busy.compareAndSet(false, true)) reply.error("BUSY", "Já existe uma operação em curso.", null)
                    else {
                        cancelled.set(false); phase = "downloading"; error = null
                        worker.execute { prepareModel() }
                        reply.success(null)
                    }
                }
                "start" -> {
                    val path = call.argument<String>("input")
                    val input = path?.let { File(it) }
                    val inputRoot = File(context.cacheDir, "stem_inputs").canonicalFile
                    if (!available()) reply.error("UNAVAILABLE", "Motor de separação indisponível.", null)
                    else if (input == null || !input.isFile || input.canonicalFile.parentFile != inputRoot || input.length() !in 44L..(64L * 1024 * 1024))
                        reply.error("INPUT", "Escolha um WAV até 64 MB, copiado para a área privada da app.", null)
                    else if (!wavPreamble(input)) reply.error("INPUT", "Escolha um ficheiro RIFF/WAV válido.", null)
                    else if (!modelVerified || modelFile.length() != MODEL_SIZE) reply.error("MODEL", "Prepare primeiro o modelo verificado.", null)
                    else if (!enoughMemory()) reply.error("MEMORY", "Memória disponível insuficiente para iniciar a separação. Feche outras apps e tente novamente.", null)
                    else if (!enoughStorage(input.length())) reply.error("STORAGE", "Espaço livre insuficiente para guardar seis pistas. Libere espaço e tente novamente.", null)
                    else if (!busy.compareAndSet(false, true)) reply.error("BUSY", "Já existe uma operação em curso.", null)
                    else {
                        cancelled.set(false)
                        resetNative()
                        phase = "separating"; error = null
                        val ownedInput = input.canonicalFile
                        worker.execute { separate(ownedInput) }
                        reply.success(null)
                    }
                }
                "cancel" -> {
                    cancelled.set(true)
                    cancelNative() // Must run immediately, never behind the inference task.
                    reply.success(null)
                }
                else -> reply.notImplemented()
            }
        }
    }

    @Synchronized private fun status(): Map<String, Any?> {
        val memory = memoryInfo()
        return mapOf(
        "phase" to phase,
        "busy" to busy.get(),
        "progress" to if (phase == "separating") progressNative() else if (phase == "ready") 100 else 0,
        "downloaded" to downloaded,
        "downloadSize" to MODEL_SIZE,
        "modelReady" to (modelVerified && modelFile.length() == MODEL_SIZE),
        "paths" to resultPaths,
        "error" to error,
        "availableMemoryBytes" to memory.availMem,
        "lowMemoryThresholdBytes" to memory.threshold,
        )
    }

    private fun validModel(): Boolean = modelFile.isFile && modelFile.length() == MODEL_SIZE && digest(modelFile) == MODEL_SHA256

    private fun wavPreamble(file: File): Boolean = try {
        file.inputStream().use { stream ->
            val prefix = ByteArray(12)
            stream.read(prefix) == 12 &&
                String(prefix, 0, 4, Charsets.US_ASCII) == "RIFF" &&
                String(prefix, 8, 4, Charsets.US_ASCII) == "WAVE"
        }
    } catch (_: Exception) { false }

    private fun digest(file: File): String {
        val hash = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { stream ->
            val buffer = ByteArray(128 * 1024)
            while (true) {
                val count = stream.read(buffer)
                if (count < 0) break
                hash.update(buffer, 0, count)
            }
        }
        return hash.digest().joinToString("") { "%02x".format(it) }
    }

    private fun prepareModel() {
        var partial: File? = null
        try {
            downloaded = 0
            if (!validModel()) {
                modelDir.mkdirs()
                val target = File(modelDir, "${UUID.randomUUID()}.partial")
                partial = target
                val connection = (URL(MODEL_URL).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 15000
                    readTimeout = 15000
                    instanceFollowRedirects = true
                }
                try {
                    if (connection.responseCode != 200 || (connection.contentLengthLong >= 0 && connection.contentLengthLong != MODEL_SIZE))
                        throw IllegalStateException("O ficheiro do modelo não corresponde à versão esperada.")
                    connection.inputStream.use { input ->
                        target.outputStream().buffered().use { output ->
                            val buffer = ByteArray(128 * 1024)
                            while (true) {
                                if (cancelled.get()) throw InterruptedException()
                                val count = input.read(buffer)
                                if (count < 0) break
                                output.write(buffer, 0, count)
                                downloaded += count
                                if (downloaded > MODEL_SIZE) throw IllegalStateException("Modelo maior que o esperado.")
                            }
                        }
                    }
                } finally { connection.disconnect() }
                if (cancelled.get()) throw InterruptedException()
                if (target.length() != MODEL_SIZE || digest(target) != MODEL_SHA256)
                    throw IllegalStateException("Verificação SHA-256 do modelo falhou.")
                if (modelFile.exists() && !modelFile.delete()) throw IllegalStateException("Não foi possível substituir o modelo inválido.")
                if (!target.renameTo(modelFile)) throw IllegalStateException("Não foi possível guardar o modelo.")
            }
            modelVerified = true
            phase = "ready"
        } catch (_: InterruptedException) {
            phase = "cancelled"
        } catch (failure: Exception) {
            modelVerified = false
            error = failure.message ?: "Falha ao preparar o modelo."
            phase = "error"
        } finally {
            partial?.delete()
            try { purgeNative(Build.VERSION.SDK_INT) } finally { busy.set(false) }
        }
    }

    private fun memoryInfo(): ActivityManager.MemoryInfo {
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val info = ActivityManager.MemoryInfo()
        manager.getMemoryInfo(info)
        return info
    }

    private fun enoughMemory(): Boolean {
        val info = memoryInfo()
        // 12 s ARM64 native probe peaked at 738,472 KiB; retain ~300 MiB for
        // app/UI/JNI and avoid crossing Android's low-memory threshold.
        return !info.lowMemory && info.availMem - info.threshold >= 1024L * 1024 * 1024
    }

    private fun enoughStorage(inputBytes: Long): Boolean {
        val available = android.os.StatFs(context.filesDir.absolutePath).availableBytes
        return available > inputBytes * 12 + 128L * 1024 * 1024
    }

    private fun restoreResult() {
        try {
            if (!resultManifest.isFile) return
            val json = JSONObject(resultManifest.readText())
            val paths = listOf("drums", "bass", "other", "vocals", "guitar", "piano")
                .associateWith { json.getString(it) }
            val root = File(context.filesDir, "stem_outputs").canonicalFile
            if (paths.values.all { path ->
                val file = File(path).canonicalFile
                file.isFile && file.length() > 44 && file.parentFile?.parentFile == root
            }) {
                resultPaths = paths
                phase = "done"
            }
        } catch (_: Exception) { /* An incomplete previous result is not exposed. */ }
    }

    private fun persistResult(paths: Map<String, String>) {
        modelDir.mkdirs()
        val temporary = File(modelDir, "last_result.${UUID.randomUUID()}.partial")
        try {
            val json = JSONObject()
            paths.forEach { (name, path) -> json.put(name, path) }
            temporary.writeText(json.toString())
            if (!temporary.renameTo(resultManifest)) {
                if (resultManifest.exists() && !resultManifest.delete()) throw IllegalStateException("Não foi possível atualizar o resultado.")
                if (!temporary.renameTo(resultManifest)) throw IllegalStateException("Não foi possível guardar o resultado.")
            }
        } finally { temporary.delete() }
    }

    private fun separate(input: File) {
        val output = File(File(context.filesDir, "stem_outputs"), UUID.randomUUID().toString())
        try {
            if (!output.mkdirs()) throw IllegalStateException("Não foi possível criar a pasta de saída.")
            val nativeError = separateNative(modelFile.absolutePath, input.absolutePath, output.absolutePath)
            if (cancelled.get()) throw InterruptedException()
            if (nativeError != null) throw IllegalStateException(nativeError)
            val names = listOf("drums", "bass", "other", "vocals", "guitar", "piano")
            val paths = names.associateWith { name -> File(output, "$name.wav").absolutePath }
            if (paths.values.any { !File(it).isFile || File(it).length() <= 44 })
                throw IllegalStateException("Uma das saídas não foi concluída.")
            persistResult(paths)
            resultPaths = paths
            phase = "done"
        } catch (_: InterruptedException) {
            phase = "cancelled"
            output.deleteRecursively()
        } catch (failure: Exception) {
            error = failure.message ?: "Falha na separação."
            phase = "error"
            output.deleteRecursively()
        } finally {
            try { purgeNative(Build.VERSION.SDK_INT) } finally { busy.set(false) }
        }
    }

    fun cancelForLifecycle(messenger: BinaryMessenger?) {
        if (attachedMessenger === messenger) {
            cancelled.set(true)
            cancelNative()
        }
    }

    fun close(messenger: BinaryMessenger) {
        if (attachedMessenger === messenger) {
            cancelForLifecycle(messenger)
            channel?.setMethodCallHandler(null)
            channel = null
            attachedMessenger = null
        }
    }

    companion object {
        private var instance: StemEngine? = null

        @Synchronized fun attach(context: Context, messenger: BinaryMessenger): StemEngine {
            val engine = instance ?: StemEngine(context.applicationContext).also { instance = it }
            engine.bind(messenger)
            return engine
        }

        private const val MODEL_SIZE = 54855129L
        private const val MODEL_SHA256 = "09704f4ceae204e56e77d5eefd6ac71d7275be81fd507e6913371d59abcee856"
        private const val MODEL_URL = "https://huggingface.co/datasets/Retrobear/demucs.cpp/resolve/8f58ac0491bbea657275bcd3e38af1ab3a27bfc9/ggml-model-htdemucs-6s-f16.bin"
    }
}
