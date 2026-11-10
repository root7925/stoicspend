import Speech
import AVFoundation

/// FR-26 语音快记 — 实时听写转文字（优先端侧识别，转写文案可二次编辑）
@MainActor
final class VoiceTranscriber: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    /// 权限/启动失败提示（已本地化的文案）
    @Published var errorHint: String?

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() {
        errorHint = nil
        transcript = ""
        Task { @MainActor in
            guard await Self.requestSpeechAuth(), await Self.requestMic() else {
                errorHint = NSLocalizedString("需要在设置中允许麦克风和语音识别", comment: "")
                return
            }
            beginRecording()
        }
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorHint = NSLocalizedString("需要在设置中允许麦克风和语音识别", comment: "")
            return
        }

        let node = audioEngine.inputNode
        let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            errorHint = NSLocalizedString("需要在设置中允许麦克风和语音识别", comment: "")
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        node.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        do {
            try audioEngine.start()
        } catch {
            node.removeTap(onBus: 0)
            errorHint = NSLocalizedString("需要在设置中允许麦克风和语音识别", comment: "")
            return
        }

        // 语言跟随系统（中文走 zh-CN），保证日常口语识别质量
        let langCode = Locale.current.language.languageCode?.identifier ?? "zh"
        let locale = Locale(identifier: langCode == "zh" ? "zh-CN" : Locale.current.identifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            stop()
            errorHint = NSLocalizedString("需要在设置中允许麦克风和语音识别", comment: "")
            return
        }
        // 端侧识别可用则不上传音频（纯本地隐私承诺）
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

        task = recognizer.recognitionTask(with: req) { [weak self] result, _ in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    self.transcript = result.bestTranscription.formattedString
                }
            }
        }
        isRecording = true
    }

    private static func requestSpeechAuth() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    private static func requestMic() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }
}
