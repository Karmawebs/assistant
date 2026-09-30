import Foundation
import AVFoundation

@MainActor
final class KarmiTranscriptionService: ObservableObject {
    static let shared = KarmiTranscriptionService()

    @Published private(set) var isRecording = false
    @Published private(set) var isTranscribing = false

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    private init() {}

    func toggleRecording() async throws -> String? {
        if isRecording {
            return try await stopAndTranscribe()
        } else {
            try await startRecording()
            return nil
        }
    }

    func startRecording() async throws {
        guard !isRecording else { return }

        let granted = await requestMicrophonePermission()
        guard granted else {
            throw NSError(
                domain: "KarmiTranscription",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Karmi necesita permiso para usar el micrófono."]
            )
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("karmi-dictation-" + UUID().uuidString + ".m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw NSError(
                domain: "KarmiTranscription",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No se ha podido iniciar la grabación."]
            )
        }

        self.recorder = recorder
        self.recordingURL = url
        self.isRecording = true
    }

    func stopAndTranscribe() async throws -> String {
        guard isRecording, let recorder, let recordingURL else {
            throw NSError(
                domain: "KarmiTranscription",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "No hay ninguna grabación activa."]
            )
        }

        recorder.stop()
        self.recorder = nil
        self.isRecording = false
        self.isTranscribing = true

        defer {
            self.isTranscribing = false
            self.recordingURL = nil
            try? FileManager.default.removeItem(at: recordingURL)
        }

        let audio = try Data(contentsOf: recordingURL)
        guard !audio.isEmpty else {
            throw NSError(
                domain: "KarmiTranscription",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "La grabación está vacía."]
            )
        }

        return try await transcribe(audio: audio, filename: recordingURL.lastPathComponent)
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        isTranscribing = false

        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
    }

    private func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    private func transcribe(audio: Data, filename: String) async throws -> String {
        guard let apiKey = KeychainStore.shared.get("openai-api-key"), !apiKey.isEmpty else {
            throw NSError(
                domain: "KarmiTranscription",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Falta la API key de OpenAI."]
            )
        }

        let boundary = "Boundary-" + UUID().uuidString
        var body = Data()

        func append(_ string: String) {
            if let data = string.data(using: .utf8) {
                body.append(data)
            }
        }

        append("--" + boundary + "\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("gpt-4o-mini-transcribe\r\n")

        append("--(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
        append("es\r\n")

        append("--(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"" + filename + "\"\r\n")
        append("Content-Type: audio/mp4\r\n\r\n")
        body.append(audio)
        append("\r\n--" + boundary + "--\r\n")

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=" + boundary, forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200..<300).contains(status) else {
            let message = String(data: data, encoding: .utf8) ?? ("HTTP " + String(status))
            throw NSError(
                domain: "KarmiTranscription",
                code: status,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw NSError(
                domain: "KarmiTranscription",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "OpenAI no devolvió una transcripción válida."]
            )
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
