import Foundation

enum TranscriptionStatus: String, Codable {
    case pending = "pending"
    case processing = "processing"
    case completed = "completed"
    case failed = "failed"
}

struct VoiceRecording: Identifiable, Codable {
    let id: Int64?
    let date: Date
    let startTime: Date
    let endTime: Date
    let duration: Double
    var audioFilePath: String?
    var transcription: String?
    var transcriptionStatus: TranscriptionStatus
    var errorMessage: String?
    let createdAt: Date

    init(
        id: Int64? = nil,
        date: Date,
        startTime: Date,
        endTime: Date,
        duration: Double,
        audioFilePath: String? = nil,
        transcription: String? = nil,
        transcriptionStatus: TranscriptionStatus = .pending,
        errorMessage: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.audioFilePath = audioFilePath
        self.transcription = transcription
        self.transcriptionStatus = transcriptionStatus
        self.errorMessage = errorMessage
        self.createdAt = createdAt
    }
}
