import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, AVSpeechSynthesizerDelegate {
  private let synthesizer = AVSpeechSynthesizer()
  private var ttsChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 1. 确保后台与物理静音开启动态下正常发声 (AVAudioSession Category Playback)
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("[AppDelegate] AVAudioSession setup error: \(error)")
    }

    // 2. 绑定原生双语兜底 TTS 通道 (lazyvocab/tts)
    let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
    ttsChannel = FlutterMethodChannel(name: "lazyvocab/tts", binaryMessenger: controller.binaryMessenger)
    synthesizer.delegate = self

    ttsChannel?.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else { return }
      switch call.method {
      case "speak":
        let args = call.arguments as? [String: Any]
        let text = args?["text"] as? String ?? ""
        let lang = args?["lang"] as? String ?? "zh-CN"
        self.speak(text: text, lang: lang)
        result(true)
      case "stop":
        self.stopSpeaking()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func speak(text: String, lang: String) {
    if synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
    }
    guard !text.isEmpty else {
      notifyTtsDone()
      return
    }

    let utterance = AVSpeechUtterance(string: text)
    if lang.lowercased().hasPrefix("en") {
      utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
      utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
    } else {
      utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
      utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    }
    synthesizer.speak(utterance)
  }

  private func stopSpeaking() {
    if synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
    }
  }

  private func notifyTtsDone() {
    DispatchQueue.main.async { [weak self] in
      self?.ttsChannel?.invokeMethod("ttsDone", arguments: nil)
    }
  }

  // MARK: - AVSpeechSynthesizerDelegate
  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    notifyTtsDone()
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    notifyTtsDone()
  }
}
