import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let onPreview: () -> Void

    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var weather: WeatherService
    @EnvironmentObject var calendar: CalendarService

    @State private var cityQuery = ""
    @State private var searching = false
    @State private var cityError: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("I widget compaiono quando blocchi il Mac e spariscono quando accedi.")
                        Text("Blocca con ⌃⌘Q per provarli.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Disponi i widget…", action: onPreview).buttonStyle(.borderedProminent)
                }
                if SkyLight.shared == nil {
                    Label("Questa versione di macOS non permette di disegnare sopra la schermata di blocco. Lo studio funziona comunque.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                ForEach($store.config.items) { $item in
                    ItemRow(item: $item) { id in store.config.items.removeAll { $0.id == id } }
                }
            } header: {
                HStack {
                    Text("Widget · \(store.config.items.count) di \(Config.maxItems)")
                    Spacer()
                    Menu {
                        ForEach(WidgetKind.allCases) { kind in
                            Button { store.add(kind) } label: { Label(kind.title, systemImage: kind.symbol) }
                        }
                    } label: {
                        Label("Aggiungi", systemImage: "plus")
                    }
                    .disabled(!store.config.canAddMore)
                    .fixedSize()
                }
            } footer: {
                Text("La posizione si sceglie trascinando i widget in “Disponi i widget…”.").foregroundStyle(.secondary)
            }

            Section("Aspetto") {
                Slider(value: $store.config.scale, in: 0.7...1.5) { Text("Dimensione") }
                Picker("Stile dei riquadri", selection: $store.config.style) {
                    ForEach(CardStyle.allCases) { Text($0.title).tag($0) }
                }
                if store.config.style.usesAccent {
                    ColorPicker("Colore", selection: Binding(
                        get: { store.config.accent.color },
                        set: { store.config.accent = RGBA($0) }), supportsOpacity: false)
                }
                Picker("Carattere", selection: $store.config.fontStyle) {
                    ForEach(FontStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Meteo") {
                HStack {
                    TextField("Città", text: $cityQuery, prompt: Text(store.config.weatherCity))
                        .onSubmit(searchCity)
                    Button(searching ? "Cerco…" : "Imposta", action: searchCity)
                        .disabled(searching || cityQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let cityError { Text(cityError).foregroundStyle(.red) }
                Text("Dati da Open-Meteo, aggiornati ogni 15 minuti.").foregroundStyle(.secondary)
            }

            Section("Permessi") {
                PermissionRow(title: "Calendario", granted: calendar.hasAccess) {
                    Task { await calendar.requestAccess() }
                }
                PermissionRow(title: "Promemoria", granted: calendar.hasRemindersAccess) {
                    Task { await calendar.requestRemindersAccess() }
                }
                Text("Per musica e testi, macOS chiede una volta di poter controllare Musica o Spotify: serve a leggere brano, copertina e punto della riproduzione. I testi arrivano da LRCLIB.")
                    .foregroundStyle(.secondary)
            }

            Section("Generale") {
                Toggle("Apri al login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError { Text(loginError).foregroundStyle(.red) }
                Text("Bacheca deve restare aperta (icona nella barra dei menu) perché i widget compaiano.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, minHeight: 680)
    }

    private func searchCity() {
        let q = cityQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        cityError = nil
        Task {
            if let place = await WeatherService.search(q) {
                store.config.weatherCity = place.name
                store.config.latitude = place.latitude
                store.config.longitude = place.longitude
                cityQuery = ""
                await weather.refresh(latitude: place.latitude, longitude: place.longitude)
            } else {
                cityError = "Non trovo “\(q)”. Prova con il nome in italiano o in inglese."
            }
            searching = false
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Non riesco a cambiare l'apertura al login: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let granted: Bool
    let request: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if granted {
                Label("Consentito", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Consenti accesso", action: request)
            }
        }
    }
}

private struct ItemRow: View {
    @Binding var item: WidgetItem
    let remove: (UUID) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.kind.symbol).frame(width: 20).padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.kind.title).fontWeight(.medium)
                HStack {
                    if item.kind.sizes.count > 1 {
                        Picker("Dimensione", selection: $item.size) {
                            ForEach(item.kind.sizes) { Text($0.title).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                    }
                    if item.kind != .note && item.kind != .photo {
                        Toggle("Senza riquadro", isOn: $item.bare)
                    }
                    if item.kind == .note {
                        ColorPicker("Colore", selection: Binding(get: { item.color.color }, set: { item.color = RGBA($0) }), supportsOpacity: false)
                    }
                }
                switch item.kind {
                case .worldClock:
                    Picker("Città", selection: $item.timeZone) {
                        ForEach(worldCities, id: \.tz) { Text($0.name).tag($0.tz) }
                    }
                    .labelsHidden().frame(maxWidth: 180)
                case .countdown:
                    HStack {
                        TextField("Nome", text: $item.label).frame(maxWidth: 160)
                        DatePicker("Data", selection: $item.date, displayedComponents: .date).labelsHidden()
                    }
                case .note:
                    TextField("Testo della nota", text: $item.text, axis: .vertical).lineLimit(2...6)
                case .photo:
                    HStack {
                        Button("Scegli cartella…", action: chooseFolder)
                        Text(URL(fileURLWithPath: item.folderPath).lastPathComponent)
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Picker("Cambia foto ogni", selection: $item.photoMinutes) {
                        ForEach([1, 5, 10, 30, 60], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .frame(maxWidth: 220)
                default:
                    EmptyView()
                }
            }
            Spacer()
            Button(role: .destructive) { remove(item.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Rimuovi")
        }
        .padding(.vertical, 2)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Usa questa cartella"
        panel.directoryURL = URL(fileURLWithPath: item.folderPath)
        if panel.runModal() == .OK, let url = panel.url {
            item.folderPath = url.path
            PhotoLibrary.shared.reload()
        }
    }
}
