package com.lazyvocab.vocab_player

import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.*

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {
    private var tts: TextToSpeech? = null
    private var isTtsReady = false
    private var pendingText: String? = null
    private var pendingLang: String? = null
    private var channel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        tts = TextToSpeech(this, this)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lazyvocab/tts").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "speak" -> {
                        val text = call.argument<String>("text") ?: ""
                        val lang = call.argument<String>("lang") ?: "zh-CN"
                        speakText(text, lang)
                        result.success(true)
                    }
                    "stop" -> {
                        stopSpeaking()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            isTtsReady = true
            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {}
                override fun onDone(utteranceId: String?) {
                    mainHandler.post {
                        channel?.invokeMethod("ttsDone", null)
                    }
                }
                override fun onError(utteranceId: String?) {
                    mainHandler.post {
                        channel?.invokeMethod("ttsDone", null)
                    }
                }
            })
            val t = pendingText
            val l = pendingLang
            if (!t.isNullOrEmpty()) {
                pendingText = null
                pendingLang = null
                speakText(t, l ?: "zh-CN")
            }
        }
    }

    private fun speakText(text: String, lang: String) {
        if (!isTtsReady || tts == null) {
            pendingText = text
            pendingLang = lang
            return
        }
        val locale = if (lang.startsWith("en", ignoreCase = true)) Locale.US else Locale.SIMPLIFIED_CHINESE
        tts?.language = locale

        // 优先挑选女声音色（晓晓/慧慧/女声），坚决避开康康/男声
        try {
            val voices = tts?.voices ?: emptySet()
            val zhVoices = voices.filter {
                val tag = it.locale?.toLanguageTag() ?: ""
                val l = it.locale?.language ?: ""
                tag.startsWith("zh", ignoreCase = true) || l.equals("zh", ignoreCase = true)
            }
            val pick = zhVoices.firstOrNull { v ->
                val n = v.name.lowercase(Locale.ROOT)
                (n.contains("female") || n.contains("huihui") || n.contains("xiaoxiao")) &&
                        !n.contains("kangkang") && !n.contains("male")
            } ?: zhVoices.firstOrNull { v ->
                val n = v.name.lowercase(Locale.ROOT)
                !n.contains("kangkang") && !n.contains("male")
            } ?: zhVoices.firstOrNull()

            if (pick != null && lang.startsWith("zh", ignoreCase = true)) {
                tts?.voice = pick
            }
        } catch (_: Exception) {}

        tts?.setSpeechRate(1.0f)
        val utteranceId = UUID.randomUUID().toString()
        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, utteranceId)
    }

    private fun stopSpeaking() {
        try {
            tts?.stop()
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
