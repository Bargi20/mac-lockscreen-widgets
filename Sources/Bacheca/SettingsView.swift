import ServiceManagement
import SwiftUI

/// Settings panes, shown as toolbar tabs like a standard Mac Settings window (see `AppDelegate.openSettings`).
enum SettingsPane {
    static let size = CGSize(width: 620, height: 560)
}

// MARK: - General

struct GeneralSettings: View {
    let onArrange: () -> Void

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
                HStack(spacing: 14) {
                    Image(systemName: "lock.rectangle.stack")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(.tint)
                        .frame(width: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("Widget sulla schermata di blocco", "Lock screen widgets")).font(.headline)
                        Text(tr("Compaiono quando blocchi il Mac (⌃⌘Q) e spariscono quando accedi.",
                                "They appear when you lock your Mac (⌃⌘Q) and go away when you log in."))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Button(tr("Disponi i widget…", "Arrange Widgets…"), action: onArrange)
                        .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 4)
                if SkyLight.shared == nil {
                    Label(tr("Questa versione di macOS non permette di disegnare sopra la schermata di blocco. Lo studio funziona comunque.",
                             "This version of macOS doesn’t allow drawing over the lock screen. The studio still works."),
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Toggle(tr("Apri al login", "Open at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError { Text(loginError).foregroundStyle(.red) }
            } footer: {
                Text(tr("Bacheca deve restare aperta, con la sua icona nella barra dei menu, perché i widget compaiano.",
                        "Bacheca must stay open, with its icon in the menu bar, for widgets to appear."))
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent(tr("Città", "City"), value: store.config.weatherCity)
                HStack {
                    TextField(tr("Cambia città", "Change city"), text: $cityQuery, prompt: Text(tr("Cerca una città", "Search for a city")))
                        .labelsHidden()
                        .onSubmit(searchCity)
                    Button(searching ? tr("Cerco…", "Searching…") : tr("Imposta", "Set"), action: searchCity)
                        .disabled(searching || cityQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let cityError { Text(cityError).foregroundStyle(.red) }
            } header: {
                Text(tr("Meteo", "Weather"))
            } footer: {
                Text(tr("Dati da Open-Meteo, aggiornati ogni 15 minuti.", "Data from Open-Meteo, updated every 15 minutes."))
                    .foregroundStyle(.secondary)
            }

            Section {
                PermissionRow(title: tr("Calendario", "Calendar"), symbol: "calendar", granted: calendar.hasAccess) {
                    Task { await calendar.requestAccess() }
                }
                PermissionRow(title: tr("Promemoria", "Reminders"), symbol: "checklist", granted: calendar.hasRemindersAccess) {
                    Task { await calendar.requestRemindersAccess() }
                }
            } header: {
                Text(tr("Permessi", "Permissions"))
            } footer: {
                Text(tr("Per musica e testi, macOS chiede una volta di poter controllare Musica o Spotify: serve a leggere brano, copertina e punto della riproduzione. I testi arrivano da LRCLIB.",
                        "For music and lyrics, macOS asks once to let Bacheca control Music or Spotify: it reads the track, artwork and playback position. Lyrics come from LRCLIB."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsPane.size.width, height: SettingsPane.size.height)
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
    let symbol: String
    let granted: Bool
    let request: () -> Void

    var body: some View {
        LabeledContent {
            if granted {
                Label(tr("Consentito", "Allowed"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(SystemColor.green)
            } else {
                Button(tr("Consenti accesso", "Allow Access"), action: request)
            }
        } label: {
            Label(title, systemImage: symbol)
        }
    }
}

// MARK: - Widgets

struct WidgetsSettings: View {
    @EnvironmentObject var store: ConfigStore

    var body: some View {
        Form {
            Section {
                if store.config.items.isEmpty {
                    Text(tr("Nessun widget. Aggiungine uno con il pulsante qui sopra.", "No widgets yet. Add one with the button above."))
                        .foregroundStyle(.secondary)
                }
                ForEach($store.config.items) { $item in
                    WidgetRow(item: $item) { id in
                        withAnimation { store.config.items.removeAll { $0.id == id } }
                    }
                }
            } header: {
                HStack {
                    Text(tr("\(store.config.items.count) di \(Config.maxItems) widget", "\(store.config.items.count) of \(Config.maxItems) widgets"))
                    Spacer()
                    Menu {
                        ForEach(WidgetKind.allCases) { kind in
                            Button { store.add(kind) } label: { Label(kind.title, systemImage: kind.symbol) }
                        }
                    } label: {
                        Label(tr("Aggiungi", "Add"), systemImage: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(!store.config.canAddMore)
                }
            } footer: {
                Text(tr("La posizione si sceglie trascinando i widget in “Disponi i widget…”.", "Choose positions by dragging widgets in “Arrange Widgets…”."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsPane.size.width, height: SettingsPane.size.height)
    }
}

/// One widget: name, size and remove on the first line, then its options in an aligned grid.
private struct WidgetRow: View {
    @Binding var item: WidgetItem
    let remove: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: item.kind.symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(item.kind.title).fontWeight(.medium)
                Spacer()
                Picker(tr("Dimensione", "Size"), selection: $item.size) {
                    ForEach(item.kind.sizes) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Button(role: .destructive) { remove(item.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help(tr("Rimuovi", "Remove"))
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                if item.hasRetro {
                    GridRow {
                        caption(tr("Retro", "Back"))
                        HStack(spacing: 8) {
                            Picker(tr("Retro", "Back"), selection: $item.retro) {
                                ForEach(Retro.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                            if item.retro == .color {
                                ColorPicker(tr("Colore", "Color"), selection: color(\.backdropColor), supportsOpacity: false)
                                    .labelsHidden()
                            }
                            if item.retro == .image {
                                Button(item.backdropImage.isEmpty ? tr("Scegli immagine…", "Choose Image…")
                                                                  : URL(fileURLWithPath: item.backdropImage).lastPathComponent) {
                                    if let path = chooseImage(startingAt: item.backdropImage) { item.backdropImage = path }
                                }
                                .lineLimit(1)
                            }
                        }
                    }
                }
                options
            }
            .padding(.leading, 30)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var options: some View {
        switch item.kind {
        case .worldClock:
            GridRow {
                caption(tr("Città", "City"))
                Picker(tr("Città", "City"), selection: $item.timeZone) {
                    ForEach(worldCities, id: \.tz) { Text($0.name).tag($0.tz) }
                }
                .labelsHidden()
                .fixedSize()
            }
        case .countdown:
            GridRow {
                caption(tr("Nome", "Name"))
                TextField(tr("Nome", "Name"), text: $item.label).labelsHidden().textFieldStyle(.roundedBorder).frame(width: 200)
            }
            GridRow {
                caption(tr("Data", "Date"))
                DatePicker(tr("Data", "Date"), selection: $item.date, displayedComponents: .date).labelsHidden().fixedSize()
            }
        case .note:
            GridRow {
                caption(tr("Colore", "Color"))
                ColorPicker(tr("Colore", "Color"), selection: color(\.color), supportsOpacity: false).labelsHidden()
            }
            GridRow(alignment: .top) {
                caption(tr("Testo", "Text"))
                TextField(tr("Testo della nota", "Note text"), text: $item.text, axis: .vertical)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...6)
                    .frame(width: 280)
            }
        case .photo:
            GridRow {
                caption(tr("Cartella", "Folder"))
                HStack(spacing: 8) {
                    Button(tr("Scegli…", "Choose…"), action: chooseFolder)
                    Text(URL(fileURLWithPath: item.folderPath).lastPathComponent)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            GridRow {
                caption(tr("Cambia ogni", "Change every"))
                Picker(tr("Cambia ogni", "Change every"), selection: $item.photoMinutes) {
                    ForEach([1, 5, 10, 30, 60], id: \.self) { Text("\($0) min").tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
        default:
            EmptyView()
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    private func color(_ key: WritableKeyPath<WidgetItem, RGBA>) -> Binding<Color> {
        Binding(get: { item[keyPath: key].color }, set: { item[keyPath: key] = RGBA($0) })
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

// MARK: - Appearance

struct AppearanceSettings: View {
    @EnvironmentObject var store: ConfigStore

    var body: some View {
        VStack(spacing: 0) {
            // Outside the Form: glass cards don't draw their contents inside a form row.
            AppearancePreview()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.top, 20)
            form
        }
        .frame(width: SettingsPane.size.width, height: SettingsPane.size.height)
    }

    private var form: some View {
        Form {
            Section {
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
                LabeledContent(tr("Dimensione", "Size")) {
                    HStack(spacing: 10) {
                        Slider(value: $store.config.scale, in: 0.6...1.4)
                        Text(store.config.scale, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            } footer: {
                Text(tr("Vetro e Vetro trasparente usano il Liquid Glass di macOS. Con “Riduci trasparenza” attivo diventano riquadri pieni.",
                        "Glass and Clear glass use macOS Liquid Glass. With Reduce Transparency on they turn solid."))
                    .foregroundStyle(.secondary)
            }

            LockGlassSection()

            Section {
                Toggle(tr("Allinea i widget alla griglia", "Snap widgets to the grid"), isOn: $store.config.snapToGrid)
            } footer: {
                Text(tr("Nello studio i widget scattano di casella in casella. Tieni premuto ⌥ per spostarli liberamente.",
                        "In the studio, widgets snap from cell to cell. Hold ⌥ to move them freely."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Two sample widgets on the wallpaper, drawn with the current style, font and color.
private struct AppearancePreview: View {
    @EnvironmentObject var store: ConfigStore

    private static let wallpaper: NSImage? = {
        guard !CommandLine.arguments.contains("--demo"),
              let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        return PhotoLibrary.shared.image(url)
    }()
    @EnvironmentObject private var capture: WallpaperCapture

    var body: some View {
        let m = Metrics(s: store.config.scale)
        let small = m.size(.small), medium = m.size(.medium)
        let height: CGFloat = 170
        let fit = min(1, (height - 36) / small.height)
        ZStack {
            if let image = (CommandLine.arguments.contains("--demo") ? nil : capture.image) ?? Self.wallpaper {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(red: 0.16, green: 0.22, blue: 0.42), Color(red: 0.93, green: 0.58, blue: 0.42)],
                               startPoint: .top, endPoint: .bottom)
            }
            HStack(spacing: m.gap) {
                WidgetCard(item: WidgetItem(kind: .analogClock, size: .small))
                WidgetCard(item: WidgetItem(kind: .battery, size: .medium))
            }
            .frame(width: small.width + m.gap + medium.width, height: small.height)
            .scaleEffect(fit)
            .allowsHitTesting(false)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

/// The option for real glass on the lock screen, with the Screen Recording permission it needs.
private struct LockGlassSection: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var wallpaper: WallpaperCapture

    var body: some View {
        Section {
            Toggle(tr("Vetro vero sulla schermata di blocco", "Real glass on the lock screen"), isOn: Binding(
                get: { store.config.lockGlassCapture },
                set: { on in
                    store.config.lockGlassCapture = on
                    if on {
                        wallpaper.requestPermission()
                        wallpaper.refresh()
                    }
                }))
            if store.config.lockGlassCapture {
                LabeledContent(tr("Registrazione schermo", "Screen Recording")) {
                    if wallpaper.hasPermission {
                        Label(wallpaper.image == nil ? tr("Consentita", "Allowed") : tr("Sfondo catturato", "Wallpaper captured"),
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(SystemColor.green)
                    } else {
                        Button(tr("Apri Impostazioni di Sistema…", "Open System Settings…")) { WallpaperCapture.openPrivacySettings() }
                    }
                }
            }
        } footer: {
            Text(tr("Sopra la schermata di blocco macOS non lascia vedere cosa c'è dietro, e senza questa opzione i widget di vetro diventano pannelli traslucidi. Con l'opzione attiva Bacheca cattura solo lo sfondo, mai le finestre, mentre il Mac è sbloccato, e lo usa per disegnare il vetro vero. Serve il permesso Registrazione schermo; dopo averlo dato, riapri Bacheca.",
                    "Over the lock screen macOS hides what is behind, so without this option glass widgets become translucent panels. With it on, Bacheca captures only the wallpaper, never your windows, while the Mac is unlocked, and uses it to draw real glass. It needs the Screen Recording permission; after granting it, reopen Bacheca."))
                .foregroundStyle(.secondary)
        }
    }
}
