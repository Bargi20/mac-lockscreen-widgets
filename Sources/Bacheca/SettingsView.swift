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
                        Text(tr("I widget compaiono quando blocchi il Mac e spariscono quando accedi.", "Widgets appear when you lock your Mac and go away when you log in."))
                        Text(tr("Blocca con ⌃⌘Q per provarli.", "Lock with ⌃⌘Q to try them.")).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(tr("Disponi i widget…", "Arrange Widgets…"), action: onPreview).buttonStyle(.borderedProminent)
                }
                if SkyLight.shared == nil {
                    Label(tr("Questa versione di macOS non permette di disegnare sopra la schermata di blocco. Lo studio funziona comunque.",
                             "This version of macOS doesn’t allow drawing over the lock screen. The studio still works."),
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                ForEach($store.config.items) { $item in
                    ItemRow(item: $item) { id in store.config.items.removeAll { $0.id == id } }
                }
            } header: {
                HStack {
                    Text(tr("Widget · \(store.config.items.count) di \(Config.maxItems)", "Widgets · \(store.config.items.count) of \(Config.maxItems)"))
                    Spacer()
                    Menu {
                        ForEach(WidgetKind.allCases) { kind in
                            Button { store.add(kind) } label: { Label(kind.title, systemImage: kind.symbol) }
                        }
                    } label: {
                        Label(tr("Aggiungi", "Add"), systemImage: "plus")
                    }
                    .disabled(!store.config.canAddMore)
                    .fixedSize()
                }
            } footer: {
                Text(tr("La posizione si sceglie trascinando i widget in “Disponi i widget…”.", "Choose positions by dragging widgets in “Arrange Widgets…”.")).foregroundStyle(.secondary)
            }

            Section(tr("Aspetto", "Appearance")) {
                Slider(value: $store.config.scale, in: 0.7...1.5) { Text(tr("Dimensione", "Size")) }
                Picker(tr("Stile dei riquadri", "Card style"), selection: $store.config.style) {
                    ForEach(CardStyle.allCases) { Text($0.title).tag($0) }
                }
                if store.config.style.usesAccent {
                    ColorPicker(tr("Colore", "Color"), selection: Binding(
                        get: { store.config.accent.color },
                        set: { store.config.accent = RGBA($0) }), supportsOpacity: false)
                }
                Picker(tr("Carattere", "Font"), selection: $store.config.fontStyle) {
                    ForEach(FontStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section(tr("Meteo", "Weather")) {
                HStack {
                    TextField(tr("Città", "City"), text: $cityQuery, prompt: Text(store.config.weatherCity))
                        .onSubmit(searchCity)
                    Button(searching ? tr("Cerco…", "Searching…") : tr("Imposta", "Set"), action: searchCity)
                        .disabled(searching || cityQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let cityError { Text(cityError).foregroundStyle(.red) }
                Text(tr("Dati da Open-Meteo, aggiornati ogni 15 minuti.", "Data from Open-Meteo, updated every 15 minutes.")).foregroundStyle(.secondary)
            }

            Section(tr("Permessi", "Permissions")) {
                PermissionRow(title: tr("Calendario", "Calendar"), granted: calendar.hasAccess) {
                    Task { await calendar.requestAccess() }
                }
                PermissionRow(title: tr("Promemoria", "Reminders"), granted: calendar.hasRemindersAccess) {
                    Task { await calendar.requestRemindersAccess() }
                }
                Text(tr("Per musica e testi, macOS chiede una volta di poter controllare Musica o Spotify: serve a leggere brano, copertina e punto della riproduzione. I testi arrivano da LRCLIB.", "For music and lyrics, macOS asks once to let Bacheca control Music or Spotify: it reads the track, artwork and playback position. Lyrics come from LRCLIB."))
                    .foregroundStyle(.secondary)
            }

            Section(tr("Generale", "General")) {
                Toggle(tr("Apri al login", "Open at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError { Text(loginError).foregroundStyle(.red) }
                Text(tr("Bacheca deve restare aperta (icona nella barra dei menu) perché i widget compaiano.", "Bacheca must stay open (menu bar icon) for widgets to appear."))
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
                cityError = tr("Non trovo “\(q)”. Prova con il nome in italiano o in inglese.", "Can’t find “\(q)”. Try the city’s English or local name.")
            }
            searching = false
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = tr("Non riesco a cambiare l'apertura al login: \(error.localizedDescription)", "Couldn’t change Open at Login: \(error.localizedDescription)")
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
                Label(tr("Consentito", "Allowed"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button(tr("Consenti accesso", "Allow access"), action: request)
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
                        Picker(tr("Dimensione", "Size"), selection: $item.size) {
                            ForEach(item.kind.sizes) { Text($0.title).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                    }
                    if item.hasRetro {
                        Picker(tr("Retro", "Back"), selection: $item.retro) {
                            ForEach(Retro.allCases) { Text($0.title).tag($0) }
                        }
                        .fixedSize()
                        if item.retro == .color {
                            ColorPicker(tr("Colore", "Color"), selection: Binding(get: { item.backdropColor.color }, set: { item.backdropColor = RGBA($0) }), supportsOpacity: false)
                                .labelsHidden()
                        }
                        if item.retro == .image {
                            Button(item.backdropImage.isEmpty ? tr("Scegli immagine…", "Choose Image…") : URL(fileURLWithPath: item.backdropImage).lastPathComponent) {
                                if let path = chooseImage(startingAt: item.backdropImage) { item.backdropImage = path }
                            }
                        }
                    }
                    if item.kind == .note {
                        ColorPicker(tr("Colore", "Color"), selection: Binding(get: { item.color.color }, set: { item.color = RGBA($0) }), supportsOpacity: false)
                    }
                }
                switch item.kind {
                case .worldClock:
                    Picker(tr("Città", "City"), selection: $item.timeZone) {
                        ForEach(worldCities, id: \.tz) { Text($0.name).tag($0.tz) }
                    }
                    .labelsHidden().frame(maxWidth: 180)
                case .countdown:
                    HStack {
                        TextField(tr("Nome", "Name"), text: $item.label).frame(maxWidth: 160)
                        DatePicker(tr("Data", "Date"), selection: $item.date, displayedComponents: .date).labelsHidden()
                    }
                case .note:
                    TextField(tr("Testo della nota", "Note text"), text: $item.text, axis: .vertical).lineLimit(2...6)
                case .photo:
                    HStack {
                        Button(tr("Scegli cartella…", "Choose Folder…"), action: chooseFolder)
                        Text(URL(fileURLWithPath: item.folderPath).lastPathComponent)
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Picker(tr("Cambia foto ogni", "Change photo every"), selection: $item.photoMinutes) {
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
                .help(tr("Rimuovi", "Remove"))
        }
        .padding(.vertical, 2)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = tr("Usa questa cartella", "Use This Folder")
        panel.directoryURL = URL(fileURLWithPath: item.folderPath)
        if panel.runModal() == .OK, let url = panel.url {
            item.folderPath = url.path
            PhotoLibrary.shared.reload()
        }
    }
}
