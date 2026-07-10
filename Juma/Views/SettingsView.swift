import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        List {
            Section("Оформление") {
                Picker("Тема", selection: $appearance) {
                    Text("Системная").tag("system")
                    Text("Светлая").tag("light")
                    Text("Тёмная").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Язык приложения", systemImage: "globe")
                }
            } header: {
                Text("Язык")
            } footer: {
                Text("Juma поддерживает русский, английский и казахский. Язык выбирается в Настройках iOS → Juma → Язык.")
            }

            Section("О приложении") {
                LabeledContent("Версия", value: "1.0")
                Text("Все данные и AI-обработка — только на вашем устройстве. Ничего не отправляется на серверы.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Настройки")
    }
}
