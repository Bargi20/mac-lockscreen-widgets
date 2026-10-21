import AppKit
import Combine
import EventKit
import ImageIO
import IOKit.ps
import SwiftUI

// MARK: - Weather (Open-Meteo, no API key)

struct WeatherNow {
    var temperature: Double
    var code: Int
    var max: Double
    var min: Double
    var feelsLike: Double
    var humidity: Double
    var wind: Double
    var uv: Double
    var rainChance: Double
    var dewPoint: Double
    var isDay: Bool
    var sunrise: Date?
    var sunset: Date?

    var label: String {
        switch code {
        case 0: tr("Sereno", "Clear")
        case 1, 2: tr("Poco nuvoloso", "Partly cloudy")
        case 3: tr("Coperto", "Overcast")
        case 45, 48: tr("Nebbia", "Fog")
        case 51...57: tr("Pioviggine", "Drizzle")
        case 61...67, 80...82: tr("Pioggia", "Rain")
        case 71...77, 85, 86: tr("Neve", "Snow")
        case 95...99: tr("Temporale", "Thunderstorm")
        default: "—"
        }
    }

    /// Background colors for the weather card, top to bottom.
    var sky: [Color] {
        if !isDay { return [Color(red: 0.05, green: 0.09, blue: 0.24), Color(red: 0.17, green: 0.20, blue: 0.40)] }
        switch code {
        case 0, 1: return [Color(red: 0.16, green: 0.46, blue: 0.88), Color(red: 0.42, green: 0.70, blue: 0.97)]
        case 51...67, 80...82, 95...99: return [Color(red: 0.20, green: 0.27, blue: 0.38), Color(red: 0.36, green: 0.44, blue: 0.56)]
        case 71...77, 85, 86: return [Color(red: 0.48, green: 0.58, blue: 0.72), Color(red: 0.74, green: 0.81, blue: 0.90)]
        default: return [Color(red: 0.33, green: 0.40, blue: 0.51), Color(red: 0.55, green: 0.62, blue: 0.71)]
        }
    }

    var symbol: String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67, 80...82: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }
}

@MainActor
final class WeatherService: ObservableObject {
    @Published var now: WeatherNow?
    @Published var failed = false

    private struct Forecast: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let apparent_temperature: Double?
            let relative_humidity_2m: Double?
            let wind_speed_10m: Double?
            let uv_index: Double?
            let precipitation_probability: Double?
            let dew_point_2m: Double?
            let is_day: Int?
        }
        struct Daily: Decodable {
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            let sunrise: [String]?
            let sunset: [String]?
        }
        let timezone: String?
        let current: Current
        let daily: Daily
    }

    struct Place: Decodable { let name: String; let latitude: Double; let longitude: Double; let country: String? }
    private struct GeoResult: Decodable { let results: [Place]? }

    func refresh(latitude: Double, longitude: Double) async {
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,apparent_temperature,relative_humidity_2m,wind_speed_10m,uv_index,precipitation_probability,dew_point_2m,is_day"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,sunrise,sunset"),
            .init(name: "forecast_days", value: "1"),
            .init(name: "timezone", value: "auto"),
        ]
        do {
            let (data, _) = try await URLSession.shared.data(from: url.url!)
            let f = try JSONDecoder().decode(Forecast.self, from: data)
            let c = f.current
            // Sun times come as local "yyyy-MM-ddTHH:mm" in the place's own time zone.
            let parser = DateFormatter()
            parser.dateFormat = "yyyy-MM-dd'T'HH:mm"
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.timeZone = f.timezone.flatMap(TimeZone.init(identifier:)) ?? .current
            now = WeatherNow(
                temperature: c.temperature_2m, code: c.weather_code,
                max: f.daily.temperature_2m_max.first ?? c.temperature_2m,
                min: f.daily.temperature_2m_min.first ?? c.temperature_2m,
                feelsLike: c.apparent_temperature ?? c.temperature_2m,
                humidity: c.relative_humidity_2m ?? 0,
                wind: c.wind_speed_10m ?? 0,
                uv: c.uv_index ?? 0,
                rainChance: c.precipitation_probability ?? 0,
                dewPoint: c.dew_point_2m ?? c.temperature_2m,
                isDay: (c.is_day ?? 1) == 1,
                sunrise: f.daily.sunrise?.first.flatMap(parser.date(from:)),
                sunset: f.daily.sunset?.first.flatMap(parser.date(from:)))
            failed = false
        } catch {
            failed = true
        }
    }

    static func search(_ name: String) async -> Place? {
        var url = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        url.queryItems = [.init(name: "name", value: name), .init(name: "count", value: "1"), .init(name: "language", value: L10n.code)]
        guard let (data, _) = try? await URLSession.shared.data(from: url.url!),
              let r = try? JSONDecoder().decode(GeoResult.self, from: data) else { return nil }
        return r.results?.first
    }
}

// MARK: - Now playing

/// Music and Spotify broadcast track changes without any permission. Playback position
/// and the state at launch come from AppleScript, which asks for Automation access once.
@MainActor
final class NowPlayingService: ObservableObject {
    @Published var title: String?
    @Published var artist: String?
    @Published var album: String?
    @Published var duration: Double?
    @Published var isPlaying = false
    @Published var source = ""
    @Published var artwork: NSImage?
    private var position: Double = 0
    private var positionAt = Date()

    var onTrackChange: (() -> Void)?

    private static let players: [(bundle: String, name: String, appName: String, durationInMs: Bool)] = [
        ("com.apple.Music", tr("Musica", "Music"), "Music", false),
        ("com.spotify.client", "Spotify", "Spotify", true),
    ]

    init() {
        let center = DistributedNotificationCenter.default()
        for (name, app) in [("com.apple.Music.playerInfo", tr("Musica", "Music")), ("com.spotify.client.PlaybackStateChanged", "Spotify")] {
            center.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] note in
                let info = note.userInfo ?? [:]
                MainActor.assumeIsolated { self?.handle(info, app: app) }
            }
        }
    }

    func position(at date: Date) -> Double {
        isPlaying ? position + date.timeIntervalSince(positionAt) : position
    }

    private func handle(_ info: [AnyHashable: Any], app: String) {
        let state = info["Player State"] as? String ?? ""
        if state == "Stopped" {
            update(title: nil, artist: nil, album: nil, duration: nil, playing: false, position: 0, source: app)
            return
        }
        let ms = (info["Total Time"] as? Double) ?? (info["Duration"] as? Double)
        let changed = (info["Name"] as? String) != title
        update(
            title: info["Name"] as? String ?? title,
            artist: info["Artist"] as? String ?? artist,
            album: info["Album"] as? String ?? album,
            duration: ms.map { $0 / 1000 } ?? duration,
            playing: state == "Playing",
            position: (info["Playback Position"] as? Double) ?? (changed ? 0 : position(at: Date())),
            source: app)
        // Music's broadcast carries no position: ask for it.
        if info["Playback Position"] == nil { sync() }
    }

    private func update(title: String?, artist: String?, album: String?, duration: Double?, playing: Bool, position: Double, source: String) {
        let trackChanged = title != self.title || artist != self.artist
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.isPlaying = playing
        self.position = position
        self.positionAt = Date()
        self.source = source
        if trackChanged {
            artwork = nil
            loadArtwork()
            onTrackChange?()
        }
    }

    private var trackKey: String { "\(title ?? "")|\(artist ?? "")" }

    /// Spotify exposes an artwork URL; Music hands over the image data itself.
    private func loadArtwork() {
        guard title != nil else { return }
        let spotify = source == "Spotify"
        let bundle = spotify ? "com.spotify.client" : "com.apple.Music"
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundle }) else { return }
        let key = trackKey
        Self.scriptQueue.async {
            var image: NSImage?
            if spotify {
                if let s = Self.run(#"tell application "Spotify" to return artwork url of current track"#)?.stringValue,
                   let url = URL(string: s), let data = try? Data(contentsOf: url) {
                    image = NSImage(data: data)
                }
            } else if let data = Self.run(#"tell application "Music" to return raw data of artwork 1 of current track"#)?.data {
                image = NSImage(data: data)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if self.trackKey == key { self.artwork = image }
                }
            }
        }
    }

    nonisolated private static func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&error)
    }

    /// AppleScript runs on its own serial queue: the first call can wait on a permission prompt.
    private static let scriptQueue = DispatchQueue(label: "bacheca.applescript")
    private var syncing = false

    /// Reads the current track from a running player. Never launches a player.
    func sync() {
        guard !syncing else { return }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let players = Self.players.filter { running.contains($0.bundle) }
        guard !players.isEmpty else { return }
        syncing = true
        Self.scriptQueue.async {
            var chosen: (Snapshot, String)?
            for p in players {
                guard let snap = Self.query(p.appName, durationInMs: p.durationInMs) else { continue }
                if snap.playing { chosen = (snap, p.name); break }
                chosen = chosen ?? (snap, p.name)
            }
            let result = chosen
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.syncing = false
                    if let (s, name) = result {
                        self.update(title: s.title, artist: s.artist, album: s.album, duration: s.duration,
                                    playing: s.playing, position: s.position, source: name)
                    }
                }
            }
        }
    }

    private struct Snapshot { let title: String; let artist: String; let album: String; let duration: Double; let position: Double; let playing: Bool }

    nonisolated private static func query(_ app: String, durationInMs: Bool) -> Snapshot? {
        let source = """
        tell application "\(app)"
            if player state is stopped then return {"stopped"}
            set t to current track
            return {player state as string, name of t, artist of t, album of t, duration of t, player position}
        end tell
        """
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error),
              result.numberOfItems >= 6,
              let state = result.atIndex(1)?.stringValue,
              let title = result.atIndex(2)?.stringValue else { return nil }
        let rawDuration = result.atIndex(5)?.doubleValue ?? 0
        return Snapshot(
            title: title,
            artist: result.atIndex(3)?.stringValue ?? "",
            album: result.atIndex(4)?.stringValue ?? "",
            duration: durationInMs ? rawDuration / 1000 : rawDuration,
            position: result.atIndex(6)?.doubleValue ?? 0,
            playing: state == "playing" || state == "kPSP")
    }
}

// MARK: - Lyrics (LRCLIB, free and keyless)

@MainActor
final class LyricsService: ObservableObject {
    enum State { case idle, loading, synced, plain, missing }

    @Published private(set) var state: State = .idle
    private(set) var lines: [(time: Double, text: String)] = []
    private var key = ""

    private struct Record: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
        var hasSynced: Bool { !(syncedLyrics ?? "").isEmpty }
        var hasText: Bool { hasSynced || !(plainLyrics ?? "").isEmpty }
    }

    func load(title: String?, artist: String?, album: String?, duration: Double?) async {
        guard let title, let artist, !title.isEmpty else {
            key = ""; lines = []; state = .idle
            return
        }
        let k = "\(title)|\(artist)"
        guard k != key else { return }
        key = k
        lines = []
        state = .loading

        let record = await Self.fetch(title: title, artist: artist, album: album, duration: duration)
        guard key == k else { return }
        if let synced = record?.syncedLyrics, case let parsed = Self.parse(synced), !parsed.isEmpty {
            lines = parsed
            state = .synced
        } else if let plain = record?.plainLyrics, !plain.isEmpty {
            lines = plain.split(separator: "\n").map { (0, String($0)) }
            state = .plain
        } else {
            state = .missing
        }
    }

    /// Lines around the current one; `current` marks the line being sung.
    func window(at position: Double, before: Int, after: Int) -> [(text: String, current: Bool)] {
        guard state == .synced, !lines.isEmpty else { return [] }
        let i = lines.lastIndex(where: { $0.time <= position + 0.25 }) ?? -1
        return ((i - before)...(i + after)).map { k in
            (lines.indices.contains(k) ? lines[k].text : " ", k == i)
        }
    }

    /// Previous, current and next line at a playback position, in seconds.
    func lines(at position: Double) -> (previous: String?, current: String?, next: String?) {
        guard state == .synced, !lines.isEmpty else { return (nil, nil, nil) }
        guard let i = lines.lastIndex(where: { $0.time <= position + 0.25 }) else { return (nil, nil, lines[0].text) }
        return (i > 0 ? lines[i - 1].text : nil, lines[i].text, i + 1 < lines.count ? lines[i + 1].text : nil)
    }

    /// Exact match first; then a search with the full title, then with "(feat. …)" and
    /// " - Remastered" style suffixes removed. Records without any text are skipped.
    private static func fetch(title: String, artist: String, album: String?, duration: Double?) async -> Record? {
        var get = URLComponents(string: "https://lrclib.net/api/get")!
        get.queryItems = [.init(name: "track_name", value: title), .init(name: "artist_name", value: artist)]
        if let album, !album.isEmpty { get.queryItems?.append(.init(name: "album_name", value: album)) }
        if let duration, duration > 0 { get.queryItems?.append(.init(name: "duration", value: String(Int(duration.rounded())))) }
        if let data = await request(get.url!), let r = try? JSONDecoder().decode(Record.self, from: data), r.hasSynced { return r }

        let mainArtist = artist.components(separatedBy: CharacterSet(charactersIn: ",&")).first?
            .trimmingCharacters(in: .whitespaces) ?? artist
        var fallback: Record?
        for t in Array(Set([title, cleanTitle(title)])).sorted(by: { $0.count > $1.count }) {
            var search = URLComponents(string: "https://lrclib.net/api/search")!
            search.queryItems = [.init(name: "track_name", value: t), .init(name: "artist_name", value: mainArtist)]
            guard let data = await request(search.url!),
                  let list = try? JSONDecoder().decode([Record].self, from: data) else { continue }
            if let synced = list.first(where: \.hasSynced) { return synced }
            fallback = fallback ?? list.first(where: \.hasText)
        }
        return fallback
    }

    static func cleanTitle(_ title: String) -> String {
        var t = title.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        if let dash = t.range(of: " - ") { t = String(t[..<dash.lowerBound]) }
        return t.trimmingCharacters(in: .whitespaces)
    }

    private static func request(_ url: URL) async -> Data? {
        var req = URLRequest(url: url)
        req.setValue("Bacheca/0.2 (macOS lock screen widgets)", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    /// Parses LRC lines such as "[01:23.45] text"; a line may carry several timestamps.
    static func parse(_ lrc: String) -> [(time: Double, text: String)] {
        let stamp = #/\[(\d+):(\d+(?:\.\d+)?)\]/#
        var out: [(Double, String)] = []
        for raw in lrc.split(separator: "\n") {
            let line = String(raw)
            let matches = line.matches(of: stamp)
            guard let last = matches.last else { continue }
            let text = String(line[last.range.upperBound...]).trimmingCharacters(in: .whitespaces)
            for m in matches {
                if let min = Double(m.1), let sec = Double(m.2) { out.append((min * 60 + sec, text.isEmpty ? "♪" : text)) }
            }
        }
        return out.sorted { $0.0 < $1.0 }
    }
}

// MARK: - Battery

@MainActor
final class BatteryService: ObservableObject {
    @Published var level: Double?
    @Published var charging = false

    func refresh() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { level = nil; return }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let cur = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            level = Double(cur) / Double(max)
            charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
            return
        }
        level = nil
    }
}

// MARK: - Calendar and Reminders

@MainActor
final class CalendarService: ObservableObject {
    struct Event { let title: String; let start: Date; let end: Date; let location: String? }
    struct Reminder: Identifiable { let id: String; let title: String; let due: Date? }

    @Published var upcoming: [Event] = []
    @Published var reminders: [Reminder] = []
    @Published var hasAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    @Published var hasRemindersAccess = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    private let store = EKEventStore()

    func requestAccess() async {
        hasAccess = (try? await store.requestFullAccessToEvents()) ?? false
        refresh()
    }

    func requestRemindersAccess() async {
        hasRemindersAccess = (try? await store.requestFullAccessToReminders()) ?? false
        refresh()
    }

    func refresh() {
        hasAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        hasRemindersAccess = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess

        if hasAccess {
            let now = Date()
            let pred = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(36 * 3600), calendars: nil)
            upcoming = store.events(matching: pred)
                .filter { !$0.isAllDay && $0.endDate > now }
                .sorted { $0.startDate < $1.startDate }
                .prefix(3)
                .map { Event(title: $0.title ?? tr("Evento", "Event"), start: $0.startDate, end: $0.endDate, location: $0.location) }
        } else {
            upcoming = []
        }

        guard hasRemindersAccess else { reminders = []; return }
        let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: pred) { items in
            let list = (items ?? [])
                .map { Reminder(id: $0.calendarItemIdentifier, title: $0.title ?? tr("Promemoria", "Reminder"), due: $0.dueDateComponents?.date) }
                .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            let top = Array(list.prefix(8))
            Task { @MainActor in self.reminders = top }
        }
    }
}

// MARK: - Photos from a folder

@MainActor
final class PhotoLibrary {
    static let shared = PhotoLibrary()
    private static let extensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "webp"]

    private var files: [String: [URL]] = [:]
    private var thumbs: [URL: NSImage] = [:]

    func files(in path: String) -> [URL] {
        if let cached = files[path] { return cached }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let list = urls.filter { Self.extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        files[path] = list
        return list
    }

    func image(_ url: URL) -> NSImage? {
        if let img = thumbs[url] { return img }
        let opts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 900,
        ] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts) else { return nil }
        if thumbs.count > 6 { thumbs.removeAll() }
        let img = NSImage(cgImage: cg, size: .zero)
        thumbs[url] = img
        return img
    }

    func reload() {
        files.removeAll()
        thumbs.removeAll()
    }
}

// MARK: - Ticker

/// The app's own clock for widgets that change over time (clock hands, lyrics, progress).
/// SwiftUI's TimelineView pauses in windows macOS considers hidden, and over the lock screen
/// the widget window counts as hidden, so updates are driven from here instead.
@MainActor
final class Ticker: ObservableObject {
    @Published private(set) var now = Date()
    private var timer: Timer?

    init() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Date() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

// MARK: - Shared environment

@MainActor
final class AppEnvironment {
    let store = ConfigStore()
    let weather = WeatherService()
    let music = NowPlayingService()
    let lyrics = LyricsService()
    let battery = BatteryService()
    let calendar = CalendarService()
    let ticker = Ticker()
    private var timers: [Timer] = []
    private var kindsWatch: AnyCancellable?

    func start() {
        music.onTrackChange = { [weak self] in self?.loadLyrics() }
        // Whichever screen adds a widget (settings or studio), ask for what it needs once.
        kindsWatch = store.$config
            .map { Set($0.items.map(\.kind)) }
            .removeDuplicates()
            .scan((Set<WidgetKind>(), Set<WidgetKind>())) { ($0.1, $1) }
            .dropFirst()
            .sink { [weak self] old, new in
                MainActor.assumeIsolated { self?.kindsAdded(new.subtracting(old)) }
            }
        refreshAll()
        timers.append(Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { _ in
            MainActor.assumeIsolated { self.refreshAll() }
        })
        // Keeps lyrics in step with the player's real position.
        timers.append(Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            MainActor.assumeIsolated {
                if self.store.config.hasLyrics, self.music.isPlaying { self.music.sync() }
            }
        })
    }

    func refreshAll() {
        battery.refresh()
        calendar.refresh()
        PhotoLibrary.shared.reload()
        let c = store.config
        if c.items.contains(where: { $0.kind == .nowPlaying || $0.kind == .lyrics }) { music.sync() }
        Task { await weather.refresh(latitude: c.latitude, longitude: c.longitude) }
    }

    private func loadLyrics() {
        guard store.config.hasLyrics else { return }
        let m = music
        Task { await lyrics.load(title: m.title, artist: m.artist, album: m.album, duration: m.duration) }
    }

    private func kindsAdded(_ kinds: Set<WidgetKind>) {
        if kinds.contains(.nextEvent), !calendar.hasAccess { Task { await calendar.requestAccess() } }
        if kinds.contains(.reminders), !calendar.hasRemindersAccess { Task { await calendar.requestRemindersAccess() } }
        if kinds.contains(.photo) { PhotoLibrary.shared.reload() }
        if !kinds.isDisjoint(with: [.lyrics, .nowPlaying]) {
            music.sync()
            // sync() is async; give it a moment before looking up lyrics for the current track.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { MainActor.assumeIsolated { self.loadLyrics() } }
        }
    }

    func inject<V: View>(_ view: V) -> some View {
        view
            .environmentObject(store)
            .environmentObject(weather)
            .environmentObject(music)
            .environmentObject(lyrics)
            .environmentObject(battery)
            .environmentObject(calendar)
            .environmentObject(ticker)
    }
}
