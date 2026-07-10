import Foundation
import AVFoundation
import Speech
import Observation

/// Локальная транскрипция речи (фреймворк Speech, on-device распознавание).
@MainActor
@Observable
final class SpeechService {
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private(set) var transcript = ""
    private(set) var isRecording = false
    private(set) var errorMessage: String?

    func start(languageCode: String = "ru-RU") async {
        errorMessage = nil
        transcript = ""

        // Разрешения: распознавание речи + микрофон.
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            errorMessage = String(localized: "Нет доступа к распознаванию речи. Разрешите в Настройках iOS.")
            return
        }
        let microphoneGranted = await AVAudioApplication.requestRecordPermission()
        guard microphoneGranted else {
            errorMessage = String(localized: "Нет доступа к микрофону. Разрешите в Настройках iOS.")
            return
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: languageCode)),
              recognizer.isAvailable else {
            errorMessage = String(localized: "Распознавание для этого языка недоступно.")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true // офлайн, приватно
            }

            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            engine.prepare()
            try engine.start()

            audioEngine = engine
            recognitionRequest = request
            isRecording = true

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if error != nil || (result?.isFinal ?? false) {
                        self.stopEngine()
                    }
                }
            }
        } catch {
            errorMessage = String(localized: "Не удалось начать запись: \(error.localizedDescription)")
            stopEngine()
        }
    }

    func stop() {
        recognitionRequest?.endAudio()
        stopEngine()
    }

    private func stopEngine() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
