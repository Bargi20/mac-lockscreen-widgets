import AppKit
import Foundation
import SwiftUI

enum WidgetSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large, wide
    var id: String { rawValue }

    /// Footprint in grid units (columns × rows).
    var cols: Int { self == .small ? 1 : self == .wide ? 4 : 2 }
    var rows: Int { self == .large || self == .wide ? 2 : 1 }

    var title: String {
        switch self {
        case .small: tr("Piccolo", "Small")
        case .medium: tr("Medio", "Medium")
        case .large: tr("Grande", "Large")
        case .wide: tr("Extra grande", "Extra large")
        }
    }

    var short: String {
        switch self {
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        case .wide: "XL"
        }
    }
}

enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case weather, nowPlaying, lyrics, calendar, nextEvent, reminders, photo, note
    case analogClock, battery, dayProgress, moon, worldClock, countdown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weather: tr("Meteo", "Weather")
        case .nowPlaying: tr("In riproduzione", "Now Playing")
        case .lyrics: tr("Testo della canzone", "Lyrics")
        case .calendar: tr("Calendario", "Calendar")
        case .nextEvent: tr("Prossimo evento", "Up Next")
        case .reminders: tr("Promemoria", "Reminders")
        case .photo: tr("Foto", "Photos")
        case .note: tr("Nota adesiva", "Sticky Note")
        case .analogClock: tr("Orologio", "Clock")
        case .battery: tr("Batteria", "Battery")
        case .dayProgress: tr("Giornata", "Day")
        case .moon: tr("Fase lunare", "Moon Phase")
        case .worldClock: tr("Fuso orario", "World Clock")
        case .countdown: tr("Conto alla rovescia", "Countdown")
        }
    }

    var symbol: String {
        switch self {
        case .weather: "cloud.sun"
        case .nowPlaying: "music.note"
        case .lyrics: "quote.bubble"
        case .calendar: "calendar"
        case .nextEvent: "calendar.badge.clock"
        case .reminders: "checklist"
        case .photo: "photo"
        case .note: "note.text"
        case .analogClock: "clock"
        case .battery: "battery.75percent"
        case .dayProgress: "sun.horizon"
        case .moon: "moon"
        case .worldClock: "globe"
        case .countdown: "flag.checkered"
        }
    }

    /// Like iPhone widgets, every kind comes in every size.
    var sizes: [WidgetSize] { WidgetSize.allCases }

    var defaultSize: WidgetSize {
        switch self {
        case .weather: .large
        case .nowPlaying, .lyrics, .calendar: .wide
        case .note, .nextEvent, .reminders, .photo: .medium
        default: .small
        }
    }

    /// Lyrics read best as bare lines on the wallpaper.
    var defaultBare: Bool { self == .lyrics }
}

struct WidgetItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: WidgetKind
    var size: WidgetSize
    /// Center of the card as a fraction of the screen (0…1).
    var x: Double = 0.5
    var y: Double = 0.55
    /// Drawn straight on the wallpaper, without a card.
    var bare = false
    var color: RGBA = .noteCoral
    var timeZone: String = "Asia/Tokyo"
    var label: String = tr("Natale", "Christmas")
    var date: Date = WidgetItem.nextChristmas()
    var text: String = tr("Ricorda:\nPortatile\nPortafoglio\nChiavi", "Remember:\nLaptop\nWallet\nKeys")
    var folderPath: String = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures").path
    var photoMinutes: Int = 10
    /// What fills the card when it has one (see `retro`).
    var backdrop: CardBackdrop = .style
    var backdropColor: RGBA = RGBA(r: 0.20, g: 0.22, b: 0.30, a: 1)
    var backdropImage: String = ""

    init(kind: WidgetKind, size: WidgetSize? = nil, x: Double = 0.5, y: Double = 0.55) {
        self.kind = kind
        self.size = size ?? kind.defaultSize
        self.x = x
        self.y = y
        self.bare = kind.defaultBare
    }

    static func nextChristmas() -> Date {
        let cal = Calendar.current
        let now = Date()
        var comps = DateComponents(year: cal.component(.year, from: now), month: 12, day: 25)
        if let d = cal.date(from: comps), d >= cal.startOfDay(for: now) { return d }
        comps.year! += 1
        return cal.date(from: comps) ?? now
    }
}

extension WidgetItem {
    // Fields added in later versions fall back to their defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(kind: try c.decode(WidgetKind.self, forKey: .kind))
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? id
        if let s = try c.decodeIfPresent(WidgetSize.self, forKey: .size), kind.sizes.contains(s) { size = s }
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? -1
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? -1
        bare = try c.decodeIfPresent(Bool.self, forKey: .bare) ?? bare
        color = try c.decodeIfPresent(RGBA.self, forKey: .color) ?? color
        timeZone = try c.decodeIfPresent(String.self, forKey: .timeZone) ?? timeZone
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? label
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? date
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? text
        folderPath = try c.decodeIfPresent(String.self, forKey: .folderPath) ?? folderPath
        photoMinutes = try c.decodeIfPresent(Int.self, forKey: .photoMinutes) ?? photoMinutes
        backdrop = try c.decodeIfPresent(CardBackdrop.self, forKey: .backdrop) ?? backdrop
        backdropColor = try c.decodeIfPresent(RGBA.self, forKey: .backdropColor) ?? backdropColor
        backdropImage = try c.decodeIfPresent(String.self, forKey: .backdropImage) ?? backdropImage
    }

    /// The back of the widget as one choice: no card, or a card filled by the style, a color,
    /// the desktop wallpaper or an image.
    var retro: Retro {
        get { bare ? .none : Retro(rawValue: backdrop.rawValue) ?? .style }
        set {
            bare = newValue == .none
            if let b = CardBackdrop(rawValue: newValue.rawValue) { backdrop = b }
        }
    }

    /// Notes and photos fill their own card, so they keep it.
    var hasRetro: Bool { kind != .note && kind != .photo }

    /// Saved by a version without free positioning.
    var needsPlacement: Bool { x < 0 || y < 0 }
}

enum CardBackdrop: String, Codable {
    case style, color, wallpaper, image
}

enum Retro: String, CaseIterable, Identifiable {
    case style, none, color, wallpaper, image
    var id: String { rawValue }
    var title: String {
        switch self {
        case .style: tr("Stile generale", "Card style")
        case .none: tr("Nessuno", "None")
        case .color: tr("Colore", "Color")
        case .wallpaper: tr("Sfondo della scrivania", "Desktop wallpaper")
        case .image: tr("Immagine", "Image")
        }
    }
    var symbol: String {
        switch self {
        case .style: "square.fill"
        case .none: "square.dashed"
        case .color: "paintpalette"
        case .wallpaper: "photo.on.rectangle"
        case .image: "photo"
        }
    }
}

enum CardStyle: String, Codable, CaseIterable, Identifiable {
    case glass, tinted, dark, light, solid, outline, bare
    var id: String { rawValue }
    var title: String {
        switch self {
        case .glass: tr("Vetro", "Glass")
        case .tinted: tr("Vetro colorato", "Tinted glass")
        case .dark: tr("Scuro", "Dark")
        case .light: tr("Chiaro", "Light")
        case .solid: tr("Pieno", "Solid")
        case .outline: tr("Contorno", "Outline")
        case .bare: tr("Senza sfondo", "No background")
        }
    }
    var usesAccent: Bool { self == .tinted || self == .solid || self == .outline }
}

enum FontStyle: String, Codable, CaseIterable, Identifiable {
    case standard, rounded, serif, mono
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: "Standard"
        case .rounded: tr("Arrotondato", "Rounded")
        case .serif: "Serif"
        case .mono: "Mono"
        }
    }
    var design: Font.Design {
        switch self {
        case .standard: .default
        case .rounded: .rounded
        case .serif: .serif
        case .mono: .monospaced
        }
    }
}

struct RGBA: Codable, Hashable {
    var r: Double, g: Double, b: Double, a: Double

    static let defaultAccent = RGBA(r: 0.36, g: 0.55, b: 1.0, a: 1)
    static let noteCoral = RGBA(r: 0.80, g: 0.42, b: 0.40, a: 1)

    init(r: Double, g: Double, b: Double, a: Double) { self.r = r; self.g = g; self.b = b; self.a = a }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .systemBlue
        self.init(r: ns.redComponent, g: ns.greenComponent, b: ns.blueComponent, a: ns.alphaComponent)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var isLight: Bool { 0.299 * r + 0.587 * g + 0.114 * b > 0.62 }
}

struct Config: Codable {
    var items: [WidgetItem] = Config.starterLayout
    var scale: Double = 1.0
    var style: CardStyle = .glass
    var accent: RGBA = .defaultAccent
    var fontStyle: FontStyle = .standard
    /// Widgets snap to a centered grid in the studio, like iPhone home screen icons.
    var snapToGrid = true
    var weatherCity: String = tr("Milano", "Milan")
    var latitude: Double = 45.4643
    var longitude: Double = 9.1895

    static let maxItems = 16

    /// Similar to a classic lock screen: weather on the left, music in the middle,
    /// note, clock and calendar on the right, lyrics under the time.
    static var starterLayout: [WidgetItem] {
        [
            WidgetItem(kind: .lyrics, size: .wide, x: 0.5, y: 0.40),
            WidgetItem(kind: .weather, size: .large, x: 0.13, y: 0.74),
            WidgetItem(kind: .nowPlaying, size: .wide, x: 0.5, y: 0.64),
            WidgetItem(kind: .note, size: .large, x: 0.79, y: 0.62),
            WidgetItem(kind: .analogClock, size: .large, x: 0.93, y: 0.62),
            WidgetItem(kind: .calendar, size: .wide, x: 0.86, y: 0.84),
        ]
    }

    var hasLyrics: Bool { items.contains { $0.kind == .lyrics } }
    var canAddMore: Bool { items.count < Config.maxItems }

    /// Text color that reads on the chosen card background.
    var foreground: Color {
        switch style {
        case .light: .black.opacity(0.85)
        case .solid: accent.isLight ? .black.opacity(0.85) : .white
        default: .white
        }
    }
}

extension Config {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        items = try c.decodeIfPresent([WidgetItem].self, forKey: .items) ?? items
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? scale
        style = try c.decodeIfPresent(CardStyle.self, forKey: .style) ?? style
        accent = try c.decodeIfPresent(RGBA.self, forKey: .accent) ?? accent
        fontStyle = try c.decodeIfPresent(FontStyle.self, forKey: .fontStyle) ?? fontStyle
        snapToGrid = try c.decodeIfPresent(Bool.self, forKey: .snapToGrid) ?? snapToGrid
        weatherCity = try c.decodeIfPresent(String.self, forKey: .weatherCity) ?? weatherCity
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude) ?? latitude
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude) ?? longitude
        if items.contains(where: \.needsPlacement) { arrangeInRows() }
    }

    /// Lays widgets out in centered rows under the clock (used for old configs and "Disponi in righe").
    mutating func arrangeInRows(screen: CGSize? = nil) {
        let screen = screen ?? NSScreen.main?.frame.size ?? CGSize(width: 1512, height: 982)
        let m = Metrics(s: scale)
        let maxWidth = screen.width * 0.8
        var rows: [[Int]] = [[]]
        var rowWidth: CGFloat = 0
        for i in items.indices {
            let w = m.size(items[i].size).width
            if rowWidth > 0, rowWidth + m.gap + w > maxWidth { rows.append([]); rowWidth = 0 }
            rows[rows.count - 1].append(i)
            rowWidth += (rowWidth > 0 ? m.gap : 0) + w
        }
        var top = screen.height * 0.36
        for row in rows where !row.isEmpty {
            let widths = row.map { m.size(items[$0].size).width }
            let height = row.map { m.size(items[$0].size).height }.max() ?? m.unit
            var left = (screen.width - (widths.reduce(0, +) + m.gap * CGFloat(row.count - 1))) / 2
            for (k, i) in row.enumerated() {
                let size = m.size(items[i].size)
                items[i].x = Double((left + size.width / 2) / screen.width)
                items[i].y = Double((top + height / 2) / screen.height)
                left += widths[k] + m.gap
            }
            top += height + m.gap
        }
    }
}

extension Config {
    /// Moves every widget to the nearest grid cell.
    mutating func snapAll(screen: CGSize) {
        let grid = LayoutGrid(m: Metrics(s: scale), screen: screen)
        for i in items.indices {
            let p = grid.snap(center: CGPoint(x: items[i].x * screen.width, y: items[i].y * screen.height), size: items[i].size)
            items[i].x = Double(p.x / screen.width)
            items[i].y = Double(p.y / screen.height)
        }
    }
}

/// Grid of widget-sized cells, centered on the screen with an even number of columns,
/// so any group of medium, large or extra-large widgets can sit exactly in the middle.
struct LayoutGrid {
    let m: Metrics
    let screen: CGSize
    private let margin: CGFloat = 24

    var pitch: CGFloat { m.unit + m.gap }

    var columns: Int {
        var k = Int((screen.width - 2 * margin + m.gap) / pitch)
        if k % 2 == 1 { k -= 1 }
        return max(4, k)
    }

    var rows: Int { max(2, Int((screen.height - 2 * margin + m.gap) / pitch)) }

    var origin: CGPoint {
        CGPoint(x: (screen.width - (CGFloat(columns) * pitch - m.gap)) / 2,
                y: (screen.height - (CGFloat(rows) * pitch - m.gap)) / 2)
    }

    func cell(_ col: Int, _ row: Int) -> CGRect {
        CGRect(x: origin.x + CGFloat(col) * pitch, y: origin.y + CGFloat(row) * pitch, width: m.unit, height: m.unit)
    }

    /// Center of the card whose top-left corner sits on the cell nearest to it.
    func snap(center: CGPoint, size: WidgetSize) -> CGPoint {
        let s = m.size(size)
        let col = min(max(((center.x - s.width / 2 - origin.x) / pitch).rounded(), 0), CGFloat(max(0, columns - size.cols)))
        let row = min(max(((center.y - s.height / 2 - origin.y) / pitch).rounded(), 0), CGFloat(max(0, rows - size.rows)))
        return CGPoint(x: origin.x + col * pitch + s.width / 2, y: origin.y + row * pitch + s.height / 2)
    }
}

/// Card geometry shared by the lock screen, the studio and auto layout.
struct Metrics {
    /// Scale of everything inside a card. Contents are laid out against a 92 pt unit; the factor brings
    /// a small widget to 140 pt at scale 1, with spacing and corner radius in the proportions of macOS widgets.
    let s: Double

    init(s scale: Double) { s = scale * 140 / 92 }

    var unit: CGFloat { 92 * s }
    var gap: CGFloat { 10.5 * s }
    var radius: CGFloat { 12.5 * s }
    func size(_ size: WidgetSize) -> CGSize {
        CGSize(width: unit * CGFloat(size.cols) + gap * CGFloat(size.cols - 1),
               height: unit * CGFloat(size.rows) + gap * CGFloat(size.rows - 1))
    }
}

final class ConfigStore: ObservableObject {
    private static let key = "config.v1"

    @Published var config: Config {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(Config.self, from: data) {
            config = decoded
        } else {
            config = Config()
        }
    }

    var isFirstLaunch: Bool { UserDefaults.standard.data(forKey: Self.key) == nil }

    private func save() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// Adds a widget at a point (fractions of the screen), or near the middle.
    @discardableResult
    func add(_ kind: WidgetKind, size: WidgetSize? = nil, at point: CGPoint? = nil) -> Bool {
        guard config.canAddMore else { return false }
        let n = Double(config.items.count % 5)
        let p = point ?? CGPoint(x: 0.5 + (n - 2) * 0.03, y: 0.55 + (n - 2) * 0.03)
        config.items.append(WidgetItem(kind: kind, size: size, x: p.x, y: p.y))
        return true
    }
}
