import Foundation
import AVFoundation

/// Errors that can occur during Whisper transcription
enum WhisperTranscriptionError: Error, LocalizedError {
    case noAPIKey
    case fileNotFound
    case fileTooLarge
    case networkError(Error)
    case invalidResponse
    case rateLimited
    case apiError(String)
    case chunkingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No OpenAI API key configured. Please set your API key in Settings."
        case .fileNotFound:
            return "Audio file not found."
        case .fileTooLarge:
            return "Audio file is too large and could not be chunked."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from Whisper API."
        case .rateLimited:
            return "Rate limited. Please try again later."
        case .apiError(let message):
            return "API error: \(message)"
        case .chunkingFailed(let message):
            return "Failed to split audio file: \(message)"
        }
    }
}

/// Singleton service for transcribing audio files using OpenAI's Whisper API
final class WhisperTranscriptionService {
    static let shared = WhisperTranscriptionService()

    /// Maximum file size allowed by Whisper API (25MB)
    static let maxFileSizeBytes: Int64 = 25 * 1024 * 1024

    /// Target chunk size when splitting large files (20MB to stay safely under limit)
    static let targetChunkSizeBytes: Int64 = 20 * 1024 * 1024

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

        // If file is larger than max, chunk it
        if fileSize > WhisperTranscriptionService.maxFileSizeBytes {
            print("[WhisperTranscriptionService] File too large (\(fileSize) bytes), splitting into chunks")
            return try await transcribeWithChunking(fileURL: fileURL, apiKey: apiKey)
        }

        print("[WhisperTranscriptionService] Starting transcription for: \(audioFilePath) (\(fileSize) bytes)")
        return try await transcribeSingleFile(fileURL: fileURL, apiKey: apiKey)
    }

    // MARK: - Private Methods

    /// Transcribe a single audio file (must be under 25MB)
    private func transcribeSingleFile(fileURL: URL, apiKey: String) async throws -> String {
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

    /// Transcribe a large audio file by splitting it into chunks
    private func transcribeWithChunking(fileURL: URL, apiKey: String) async throws -> String {
        // Get audio asset duration
        let asset = AVAsset(url: fileURL)

        let duration: CMTime
        do {
            duration = try await asset.load(.duration)
        } catch {
            print("[WhisperTranscriptionService] Failed to load audio duration: \(error)")
            throw WhisperTranscriptionError.chunkingFailed("Could not load audio duration")
        }

        let totalSeconds = CMTimeGetSeconds(duration)
        guard totalSeconds.isFinite && totalSeconds > 0 else {
            print("[WhisperTranscriptionService] Invalid audio duration")
            throw WhisperTranscriptionError.chunkingFailed("Invalid audio duration")
        }

        // Get file size to calculate bytes per second
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let fileSize = fileAttributes[.size] as? Int64 else {
            throw WhisperTranscriptionError.chunkingFailed("Could not determine file size")
        }

        let bytesPerSecond = Double(fileSize) / totalSeconds
        let targetChunkDuration = Double(WhisperTranscriptionService.targetChunkSizeBytes) / bytesPerSecond
        let numberOfChunks = Int(ceil(totalSeconds / targetChunkDuration))

        print("[WhisperTranscriptionService] Splitting \(Int(totalSeconds))s audio into \(numberOfChunks) chunks of ~\(Int(targetChunkDuration))s each")

        // Create temporary directory for chunks
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("whisper_chunks_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var chunkURLs: [URL] = []
        var transcriptions: [String] = []

        defer {
            // Clean up temporary chunk files
            cleanupChunkFiles(at: tempDir)
        }

        // Create and transcribe each chunk
        for chunkIndex in 0..<numberOfChunks {
            let startTime = Double(chunkIndex) * targetChunkDuration
            let endTime = min(startTime + targetChunkDuration, totalSeconds)

            print("[WhisperTranscriptionService] Processing chunk \(chunkIndex + 1)/\(numberOfChunks) (\(Int(startTime))s - \(Int(endTime))s)")

            let chunkURL = tempDir.appendingPathComponent("chunk_\(chunkIndex).m4a")
            chunkURLs.append(chunkURL)

            // Export the chunk
            try await exportAudioChunk(
                from: asset,
                startTime: startTime,
                endTime: endTime,
                to: chunkURL
            )

            // Verify chunk was created and check its size
            guard FileManager.default.fileExists(atPath: chunkURL.path) else {
                throw WhisperTranscriptionError.chunkingFailed("Failed to create chunk file")
            }

            let chunkAttributes = try FileManager.default.attributesOfItem(atPath: chunkURL.path)
            if let chunkSize = chunkAttributes[.size] as? Int64 {
                print("[WhisperTranscriptionService] Chunk \(chunkIndex + 1) size: \(chunkSize) bytes")
            }

            // Transcribe the chunk
            let chunkTranscription = try await transcribeSingleFile(fileURL: chunkURL, apiKey: apiKey)
            transcriptions.append(chunkTranscription)
        }

        // Concatenate all transcriptions with space separator
        let fullTranscription = transcriptions.joined(separator: " ")
        print("[WhisperTranscriptionService] Chunked transcription completed. Total length: \(fullTranscription.count) characters")

        return fullTranscription
    }

    /// Export a portion of an audio file to a new file
    private func exportAudioChunk(from asset: AVAsset, startTime: Double, endTime: Double, to outputURL: URL) async throws {
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw WhisperTranscriptionError.chunkingFailed("Could not create export session")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        let startCMTime = CMTime(seconds: startTime, preferredTimescale: 1000)
        let endCMTime = CMTime(seconds: endTime, preferredTimescale: 1000)
        exportSession.timeRange = CMTimeRange(start: startCMTime, end: endCMTime)

        await exportSession.export()

        switch exportSession.status {
        case .completed:
            return
        case .failed:
            let errorMessage = exportSession.error?.localizedDescription ?? "Unknown export error"
            throw WhisperTranscriptionError.chunkingFailed(errorMessage)
        case .cancelled:
            throw WhisperTranscriptionError.chunkingFailed("Export was cancelled")
        default:
            throw WhisperTranscriptionError.chunkingFailed("Unexpected export status: \(exportSession.status.rawValue)")
        }
    }

    /// Clean up temporary chunk files
    private func cleanupChunkFiles(at directory: URL) {
        do {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
                print("[WhisperTranscriptionService] Cleaned up temporary chunk files at \(directory.path)")
            }
        } catch {
            print("[WhisperTranscriptionService] Warning: Failed to clean up chunk files: \(error)")
        }
    }
}
