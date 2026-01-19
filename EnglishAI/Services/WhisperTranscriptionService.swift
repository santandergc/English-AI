import Foundation

/// Errors that can occur during Whisper transcription
enum WhisperTranscriptionError: Error, LocalizedError {
    case noAPIKey
    case fileNotFound
    case fileTooLarge
    case networkError(Error)
    case invalidResponse
    case rateLimited
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No OpenAI API key configured. Please set your API key in Settings."
        case .fileNotFound:
            return "Audio file not found."
        case .fileTooLarge:
            return "Audio file is too large (max 25MB)."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from Whisper API."
        case .rateLimited:
            return "Rate limited. Please try again later."
        case .apiError(let message):
            return "API error: \(message)"
        }
    }
}

/// Singleton service for transcribing audio files using OpenAI's Whisper API
final class WhisperTranscriptionService {
    static let shared = WhisperTranscriptionService()

    /// Maximum file size allowed by Whisper API (25MB)
    static let maxFileSizeBytes: Int64 = 25 * 1024 * 1024

    /// Whisper API endpoint
    private let transcriptionEndpoint = "https://api.openai.com/v1/audio/transcriptions"

    /// Whisper model to use
    private let model = "whisper-1"

    /// Target language for transcription
    private let language = "en"

    private init() {}

    // MARK: - API Key Access

    /// Get the OpenAI API key from AIAnalysisService
    private var openAIAPIKey: String? {
        return AIAnalysisService.shared.openAIAPIKey
    }

    // MARK: - Public Methods

    /// Transcribe an audio file using OpenAI's Whisper API
    /// - Parameter audioFilePath: Path to the audio file to transcribe
    /// - Returns: The transcription text
    /// - Throws: WhisperTranscriptionError on failure
    func transcribe(audioFilePath: String) async throws -> String {
        // Check API key
        guard let apiKey = openAIAPIKey, !apiKey.isEmpty else {
            print("[WhisperTranscriptionService] No OpenAI API key configured")
            throw WhisperTranscriptionError.noAPIKey
        }

        let fileURL = URL(fileURLWithPath: audioFilePath)

        // Verify file exists
        guard FileManager.default.fileExists(atPath: audioFilePath) else {
            print("[WhisperTranscriptionService] Audio file not found: \(audioFilePath)")
            throw WhisperTranscriptionError.fileNotFound
        }

        // Check file size
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: audioFilePath)
        guard let fileSize = fileAttributes[.size] as? Int64 else {
            print("[WhisperTranscriptionService] Could not determine file size")
            throw WhisperTranscriptionError.fileNotFound
        }

        if fileSize > WhisperTranscriptionService.maxFileSizeBytes {
            print("[WhisperTranscriptionService] File too large: \(fileSize) bytes (max: \(WhisperTranscriptionService.maxFileSizeBytes))")
            throw WhisperTranscriptionError.fileTooLarge
        }

        print("[WhisperTranscriptionService] Starting transcription for: \(audioFilePath) (\(fileSize) bytes)")

        // Read audio file data
        let audioData: Data
        do {
            audioData = try Data(contentsOf: fileURL)
        } catch {
            print("[WhisperTranscriptionService] Failed to read audio file: \(error)")
            throw WhisperTranscriptionError.networkError(error)
        }

        // Build multipart/form-data request
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: transcriptionEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)

        // Add language parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(language)\r\n".data(using: .utf8)!)

        // Add audio file
        let filename = fileURL.lastPathComponent
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        // Make request
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            print("[WhisperTranscriptionService] Network error: \(error)")
            throw WhisperTranscriptionError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[WhisperTranscriptionService] Invalid response type")
            throw WhisperTranscriptionError.invalidResponse
        }

        // Handle rate limiting
        if httpResponse.statusCode == 429 {
            print("[WhisperTranscriptionService] Rate limited")
            throw WhisperTranscriptionError.rateLimited
        }

        // Handle errors
        if httpResponse.statusCode != 200 {
            if let errorJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJSON["error"] as? [String: Any],
               let message = error["message"] as? String {
                print("[WhisperTranscriptionService] API error: \(message)")
                throw WhisperTranscriptionError.apiError(message)
            }
            print("[WhisperTranscriptionService] API error with status code: \(httpResponse.statusCode)")
            print("[WhisperTranscriptionService] Response: \(String(data: data, encoding: .utf8) ?? "Unknown")")
            throw WhisperTranscriptionError.invalidResponse
        }

        // Parse response
        guard let responseJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = responseJSON["text"] as? String else {
            print("[WhisperTranscriptionService] Failed to parse transcription response")
            throw WhisperTranscriptionError.invalidResponse
        }

        print("[WhisperTranscriptionService] Transcription completed successfully (\(text.count) characters)")
        return text
    }
}
