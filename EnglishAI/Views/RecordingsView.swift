import SwiftUI

struct RecordingsView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Recordings")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Placeholder content - will be expanded in future stories
            VStack {
                Spacer()
                Image(systemName: "mic.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Voice Recordings")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                Text("Record your voice and get transcriptions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
    }
}

#Preview {
    RecordingsView()
}
