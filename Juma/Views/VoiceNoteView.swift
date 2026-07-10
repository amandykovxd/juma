import SwiftUI
import SwiftData

/// Голосовая заметка: запись → локальная транскрипция → заметка в базе знаний.
struct VoiceNoteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var speech = SpeechService()
    @State private var language = "ru-RU"

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Picker("Язык", selection: $language) {
                    Text("Русский").tag("ru-RU")
                    Text("English").tag("en-US")
                    Text("Қазақша").tag("kk-KZ")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .disabled(speech.isRecording)

                ScrollView {
                    Text(speech.transcript.isEmpty
                         ? String(localized: "Нажмите кнопку и говорите — текст появится здесь.")
                         : speech.transcript)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(speech.transcript.isEmpty ? .secondary : .primary)
                        .padding()
                }

                if let errorMessage = speech.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Button {
                    if speech.isRecording {
                        speech.stop()
                    } else {
                        Task { await speech.start(languageCode: language) }
                    }
                } label: {
                    Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(speech.isRecording ? .red : .accentColor)
                        .symbolEffect(.pulse, isActive: speech.isRecording)
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Голосовая заметка")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        speech.stop()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .disabled(speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        speech.stop()
        let text = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let title = String(localized: "Голосовая заметка \(Date.now.formatted(date: .abbreviated, time: .shortened))")
        let note = Note(title: title, content: text, tags: String(localized: "голос"))
        modelContext.insert(note)
        dismiss()
    }
}
