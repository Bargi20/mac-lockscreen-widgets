import SwiftUI

// MARK: - Lock screen layout

struct LockScreenView: View {
    enum Mode { case lock, preview }
    let mode: Mode
    var onClose: () -> Void = {}

    @EnvironmentObject var store: ConfigStore

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if mode == .preview {
                    PreviewBackdrop()
                    StudioCanvas(screen: geo.size, onClose: onClose)
                } else {
                    ForEach(store.config.items) { item in
                        WidgetCard(item: item)
                            .position(x: item.x * geo.size.width, y: item.y * geo.size.height)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Stand-in for the lock screen: the desktop wallpaper, system clock and login, to judge placement.
struct PreviewBackdrop: View {
    private static let wallpaper: NSImage? = {
        // `--demo` keeps the neutral gradient, for screenshots that shouldn't show the user's wallpaper.
        guard !CommandLine.arguments.contains("--demo"),
              let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                if let image = Self.wallpaper {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                } else {
                    LinearGradient(colors: [Color(red: 0.16, green: 0.22, blue: 0.42), Color(red: 0.55, green: 0.36, blue: 0.52),
                                            Color(red: 0.93, green: 0.58, blue: 0.42)],
                                   startPoint: .top, endPoint: .bottom)
                }
                VStack(spacing: 2) {
                    Text(Date.now, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(.system(size: geo.size.height * 0.022, weight: .semibold))
                    Text(Date.now, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                        .font(.system(size: geo.size.height * 0.11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.3))
                .padding(.top, geo.size.height * 0.11)
                VStack(spacing: 6) {
                    Circle().fill(.white.opacity(0.25)).frame(width: 44, height: 44)
                    Capsule().fill(.white.opacity(0.18)).frame(width: 150, height: 24)
                }
                .padding(.top, geo.size.height * 0.80)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Card chrome

struct WidgetCard: View {
    let item: WidgetItem
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var weather: WeatherService

    var body: some View {
        let c = store.config
        let m = Metrics(s: c.scale)
        let size = m.size(item.size)
        let shape = RoundedRectangle(cornerRadius: m.radius, style: .continuous)
        let white = foreground(c) == .white
        WidgetContent(item: item, m: m, size: size)
            .foregroundStyle(foreground(c))
            .fontDesign(c.fontStyle.design)
            // A faint shadow keeps white text readable on light wallpapers seen through glass.
            .shadow(color: .black.opacity(white && item.kind != .photo ? 0.22 : 0), radius: 1.5, y: 0.5)
            .frame(width: size.width, height: size.height)
            .modifier(CardChrome(item: item, style: c.style, accent: c.accent.color, shape: shape, sky: sky(c)))
    }

    private func foreground(_ c: Config) -> Color {
        if item.bare { return .white }
        if item.kind == .note { return item.color.isLight ? .black.opacity(0.85) : .white }
        if item.hasRetro {
            switch item.backdrop {
            case .color: return item.backdropColor.isLight ? .black.opacity(0.85) : .white
            case .wallpaper, .image: return .white
            case .style: break
            }
        }
        if sky(c) != nil { return .white }
        return c.foreground
    }

    /// Weather cards take on the sky of the current conditions, except in styles with their own color.
    private func sky(_ c: Config) -> [Color]? {
        guard item.kind == .weather, !item.bare, item.backdrop == .style, let w = weather.now,
              [.glass, .tinted, .dark].contains(c.style) else { return nil }
        return w.sky
    }
}

/// Image behind a widget whose back is the desktop wallpaper or a chosen picture.
@MainActor
private func backdropImage(_ item: WidgetItem) -> NSImage? {
    switch item.backdrop {
    case .wallpaper:
        guard let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        return PhotoLibrary.shared.image(url)
    case .image:
        return item.backdropImage.isEmpty ? nil : PhotoLibrary.shared.image(URL(fileURLWithPath: item.backdropImage))
    default:
        return nil
    }
}

private struct CardChrome: ViewModifier {
    let item: WidgetItem
    let style: CardStyle
    let accent: Color
    let shape: RoundedRectangle
    let sky: [Color]?

    func body(content: Content) -> some View {
        if item.bare {
            content.shadow(color: .black.opacity(0.55), radius: 4, y: 1)
        } else if item.kind == .note {
            content
                .clipShape(shape)
                .background(
                    LinearGradient(colors: [item.color.color.opacity(0.92), item.color.color],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        } else if item.hasRetro && item.backdrop == .color {
            content
                .clipShape(shape)
                .background(item.backdropColor.color, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.15), lineWidth: 1))
        } else if item.hasRetro, item.backdrop == .wallpaper || item.backdrop == .image {
            content
                .background {
                    if let image = backdropImage(item) {
                        Image(nsImage: image).resizable().scaledToFill()
                            // A soft darkening at the bottom keeps text readable on any picture.
                            .overlay(LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                    } else {
                        Color.black.opacity(0.35)
                    }
                }
                .clipShape(shape)
                .overlay(shape.strokeBorder(.white.opacity(0.22), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        } else {
            content
                .background {
                    if let sky {
                        LinearGradient(colors: sky, startPoint: .top, endPoint: .bottom).opacity(0.8)
                    }
                }
                .clipShape(shape)
                .modifier(CardBackground(style: style, accent: accent, shape: shape))
        }
    }
}

private struct CardBackground: ViewModifier {
    let style: CardStyle
    let accent: Color
    let shape: RoundedRectangle

    func body(content: Content) -> some View {
        switch style {
        case .glass:
            // A light dark wash under the glass keeps white text legible on bright wallpapers.
            if #available(macOS 26.0, *) {
                content
                    .background(Color.black.opacity(0.1), in: shape)
                    .glassEffect(.regular, in: shape)
            } else {
                content
                    .background(Color.black.opacity(0.1), in: shape)
                    .background(.ultraThinMaterial, in: shape)
            }
        case .tinted:
            // A glass tint alone barely shows over the lock screen, so the color sits under a thin material.
            content
                .background(accent.opacity(0.5), in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 1))
        case .dark:
            content.background(Color.black.opacity(0.45), in: shape)
        case .light:
            content.background(Color.white.opacity(0.6), in: shape)
        case .solid:
            content.background(accent, in: shape)
        case .outline:
            content
                .background(Color.black.opacity(0.12), in: shape)
                .overlay(shape.strokeBorder(accent, lineWidth: 2))
        case .bare:
            content.shadow(color: .black.opacity(0.55), radius: 3, y: 1)
        }
    }
}

// MARK: - Widget bodies

private struct WidgetContent: View {
    let item: WidgetItem
    let m: Metrics
    let size: CGSize

    @EnvironmentObject var weather: WeatherService
    @EnvironmentObject var battery: BatteryService
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var store: ConfigStore

    var body: some View {
        switch item.kind {
        case .lyrics: LyricsWidget(item: item, m: m)
        case .nowPlaying: NowPlayingWidget(item: item, m: m, size: size)
        case .analogClock: ClockWidget(size: item.size, m: m, timeZone: .current, title: nil)
        case .worldClock:
            ClockWidget(size: item.size, m: m, timeZone: TimeZone(identifier: item.timeZone) ?? .current, title: cityName(item.timeZone))
        default:
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                content(now: ctx.date)
            }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let s = m.s
        let sz = item.size
        switch item.kind {
        case .weather:
            WeatherWidget(size: sz, m: m, city: store.config.weatherCity, weather: weather.now, failed: weather.failed, now: now)
        case .calendar:
            CalendarWidget(size: sz, m: m, now: now, events: calendar.hasAccess ? calendar.upcoming : [])
        case .nextEvent:
            EventsWidget(size: sz, m: m, now: now, access: calendar.hasAccess, events: calendar.upcoming)
        case .reminders:
            RemindersWidget(size: sz, m: m, now: now, access: calendar.hasRemindersAccess, reminders: calendar.reminders)
        case .photo:
            PhotoWidget(item: item, now: now, m: m, size: size)
        case .note:
            Text(item.text)
                .font(.system(size: (sz == .small ? 13 : sz == .medium ? 15 : 18) * s, weight: .medium))
                .lineSpacing(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(14 * s)
        case .battery:
            if let level = battery.level {
                Gauge(size: sz, m: m, progress: level, symbol: battery.charging ? "bolt.fill" : "battery.100",
                      value: "\(Int((level * 100).rounded()))%", label: tr("Batteria", "Battery"),
                      detail: battery.charging ? tr("In carica", "Charging") : level < 0.2 ? tr("Batteria scarica", "Low battery") : tr("Con batteria", "On battery"),
                      tint: AnyShapeStyle(level < 0.2 && !battery.charging ? Color.red : Color.green))
            } else {
                Gauge(size: sz, m: m, progress: 1, symbol: "powerplug.fill", value: "—", label: tr("Batteria", "Battery"), detail: tr("Alimentato dalla rete", "On power adapter"))
            }
        case .dayProgress:
            let p = now.timeIntervalSince(Calendar.current.startOfDay(for: now)) / 86400
            let left = Int((1 - p) * 24 * 60)
            Gauge(size: sz, m: m, progress: p, symbol: "sun.horizon.fill", value: "\(Int(p * 100))%", label: tr("Giornata", "Day"),
                  detail: tr("Mancano \(left / 60) h \(left % 60) min", "\(left / 60) h \(left % 60) min left"),
                  tint: AnyShapeStyle(AngularGradient(colors: [.yellow, .orange, .pink], center: .center,
                                                      startAngle: .degrees(0), endAngle: .degrees(360 * max(0.05, p)))))
        case .moon:
            MoonWidget(size: sz, m: m, now: now)
        case .countdown:
            CountdownWidget(size: sz, m: m, now: now, label: item.label, date: item.date)
        case .lyrics, .nowPlaying, .analogClock, .worldClock:
            EmptyView()
        }
    }
}

// MARK: Weather

private struct WeatherWidget: View {
    let size: WidgetSize
    let m: Metrics
    let city: String
    let weather: WeatherNow?
    let failed: Bool
    let now: Date

    var body: some View {
        let s = m.s
        if let w = weather {
            switch size {
            case .small:
                VStack(alignment: .leading, spacing: 2 * s) {
                    cityLabel
                    Text("\(Int(w.temperature.rounded()))°").font(.system(size: 30 * s, weight: .light))
                    Spacer(minLength: 0)
                    Image(systemName: w.symbol).symbolRenderingMode(.multicolor).font(.system(size: 14 * s))
                    Text("↑\(Int(w.max.rounded()))° ↓\(Int(w.min.rounded()))°").font(.system(size: 10 * s, weight: .semibold)).opacity(0.85)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(11 * s)
            case .medium:
                HStack {
                    VStack(alignment: .leading, spacing: 2 * s) {
                        cityLabel
                        Text("\(Int(w.temperature.rounded()))°").font(.system(size: 32 * s, weight: .light))
                        Text("\(w.label) · ↑\(Int(w.max.rounded()))° ↓\(Int(w.min.rounded()))°")
                            .font(.system(size: 10.5 * s, weight: .semibold)).opacity(0.85).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: w.symbol).symbolRenderingMode(.multicolor).font(.system(size: 30 * s))
                }
                .padding(.horizontal, 14 * s)
            case .large:
                VStack(alignment: .leading, spacing: 5 * s) {
                    headline(w, temp: 36)
                    TempRange(min: w.min, max: w.max, current: w.temperature, s: s)
                    stats(w)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(14 * s)
            case .wide:
                HStack(alignment: .top, spacing: 18 * s) {
                    VStack(alignment: .leading, spacing: 6 * s) {
                        headline(w, temp: 46)
                        Spacer(minLength: 0)
                        TempRange(min: w.min, max: w.max, current: w.temperature, s: s)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 8 * s) {
                        Text(tr("DETTAGLI", "DETAILS")).font(.system(size: 9 * s, weight: .bold)).opacity(0.6)
                        stats(w, spacing: 9)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(16 * s)
            }
        } else {
            VStack(spacing: 4 * s) {
                Image(systemName: "cloud").font(.system(size: 20 * s))
                Text(failed ? tr("Meteo non disponibile", "Weather unavailable") : tr("Caricamento…", "Loading…")).font(.system(size: 11 * s, weight: .semibold))
            }
        }
    }

    private var cityLabel: some View {
        Label(city, systemImage: "location.fill")
            .font(.system(size: 11 * m.s, weight: .semibold))
            .lineLimit(1)
    }

    private func headline(_ w: WeatherNow, temp: Double) -> some View {
        VStack(alignment: .leading, spacing: 3 * m.s) {
            cityLabel
            HStack(alignment: .top) {
                Text("\(Int(w.temperature.rounded()))°").font(.system(size: temp * m.s, weight: .light))
                Spacer(minLength: 0)
                Image(systemName: w.symbol).symbolRenderingMode(.multicolor).font(.system(size: 28 * m.s)).padding(.top, 4 * m.s)
            }
            Text(w.label).font(.system(size: 12 * m.s, weight: .semibold)).opacity(0.9)
        }
    }

    private func stats(_ w: WeatherNow, spacing: Double = 4) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 10 * m.s, verticalSpacing: spacing * m.s) {
            GridRow {
                Stat(symbol: "thermometer.medium", text: "\(Int(w.feelsLike.rounded()))°", s: m.s)
                Stat(symbol: "humidity.fill", text: "\(Int(w.humidity))%", s: m.s)
            }
            GridRow {
                Stat(symbol: "wind", text: "\(Int(w.wind.rounded())) km/h", s: m.s)
                Stat(symbol: "sun.max.fill", text: "UV \(Int(w.uv.rounded()))", s: m.s)
            }
            GridRow {
                Stat(symbol: "cloud.rain.fill", text: "\(Int(w.rainChance))%", s: m.s)
                sunStat(w)
            }
        }
    }

    /// Whichever of sunrise and sunset comes next.
    private func sunStat(_ w: WeatherNow) -> Stat {
        let f = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        if let rise = w.sunrise, now < rise { return Stat(symbol: "sunrise.fill", text: rise.formatted(f), s: m.s) }
        if let set = w.sunset { return Stat(symbol: now < set ? "sunset.fill" : "moon.fill", text: set.formatted(f), s: m.s) }
        return Stat(symbol: "sunset.fill", text: "—", s: m.s)
    }
}

private struct Stat: View {
    let symbol: String
    let text: String
    let s: Double
    var body: some View {
        HStack(spacing: 5 * s) {
            Image(systemName: symbol).symbolRenderingMode(.multicolor).frame(width: 14 * s)
            Text(text).lineLimit(1)
        }
        .font(.system(size: 11 * s, weight: .semibold))
    }
}

private struct TempRange: View {
    let min: Double, max: Double, current: Double, s: Double
    var body: some View {
        HStack(spacing: 6 * s) {
            Text("\(Int(min.rounded()))°")
            GeometryReader { geo in
                let p = max > min ? (current - min) / (max - min) : 0.5
                ZStack(alignment: .leading) {
                    Capsule().fill(LinearGradient(colors: [.cyan.opacity(0.9), .yellow.opacity(0.9), .orange], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 4 * s)
                    Circle().fill(.white).frame(width: 7 * s, height: 7 * s)
                        .offset(x: (geo.size.width - 7 * s) * Swift.min(1, Swift.max(0, p)))
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 8 * s)
            Text("\(Int(max.rounded()))°")
        }
        .font(.system(size: 10 * s, weight: .semibold))
        .opacity(0.9)
    }
}

// MARK: Calendar, events, reminders

private let hm = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)

private func eventTime(_ e: CalendarService.Event) -> String {
    let day = Calendar.current.isDateInToday(e.start) ? "" : tr("Domani ", "Tomorrow ")
    return "\(day)\(e.start.formatted(hm))–\(e.end.formatted(hm))"
}

/// The user's own calendar: first day of the week and weekday names follow the system.
private func localCalendar() -> Calendar {
    var cal = Calendar.current
    cal.locale = .current
    return cal
}

/// One-letter weekday names, starting from the calendar's first day of the week.
private func weekdayInitials(_ cal: Calendar) -> [String] {
    let symbols = cal.veryShortStandaloneWeekdaySymbols
    let first = cal.firstWeekday - 1
    return Array(symbols[first...] + symbols[..<first])
}

private struct CalendarWidget: View {
    let size: WidgetSize
    let m: Metrics
    let now: Date
    let events: [CalendarService.Event]

    var body: some View {
        let s = m.s
        switch size {
        case .small:
            VStack(alignment: .leading, spacing: 0) {
                weekday
                Text(now, format: .dateTime.day()).font(.system(size: 40 * s, weight: .light))
                Spacer(minLength: 0)
                Text(events.first.map { "\($0.start.formatted(hm)) \($0.title)" } ?? tr("Nessun evento", "No events"))
                    .font(.system(size: 10 * s, weight: .semibold)).lineLimit(2).opacity(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12 * s)
        case .medium:
            HStack(spacing: 8 * s) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(now, format: .dateTime.weekday(.abbreviated)).textCase(.uppercase)
                        .font(.system(size: 10 * s, weight: .bold)).foregroundStyle(.red)
                    Text(now, format: .dateTime.day()).font(.system(size: 34 * s, weight: .light))
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                .fixedSize()
                WeekStrip(now: now, s: s)
            }
            .padding(.horizontal, 12 * s)
        case .large:
            MonthGrid(now: now, s: s, cell: 20).padding(14 * s).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .wide:
            HStack(alignment: .top, spacing: 16 * s) {
                VStack(alignment: .leading, spacing: 0) {
                    weekday
                    Text(now, format: .dateTime.day()).font(.system(size: 54 * s, weight: .light))
                    Text(now, format: .dateTime.month(.wide).year()).font(.system(size: 11 * s, weight: .semibold)).opacity(0.75)
                    Spacer(minLength: 0)
                    if let e = events.first {
                        Text(e.title).font(.system(size: 11 * s, weight: .bold)).lineLimit(1)
                        Text(eventTime(e)).font(.system(size: 10 * s, weight: .medium)).opacity(0.75)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                MonthGrid(now: now, s: s)
            }
            .padding(16 * s)
        }
    }

    private var weekday: some View {
        Text(now, format: .dateTime.weekday(.wide)).textCase(.uppercase)
            .font(.system(size: 10 * m.s, weight: .bold)).foregroundStyle(.red)
    }
}

private struct WeekStrip: View {
    let now: Date
    let s: Double
    var body: some View {
        let cal = localCalendar()
        let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        HStack(spacing: 1 * s) {
            ForEach(Array(zip(weekdayInitials(cal), days).enumerated()), id: \.offset) { _, pair in
                let today = cal.isDate(pair.1, inSameDayAs: now)
                VStack(spacing: 4 * s) {
                    Text(pair.0).font(.system(size: 8 * s, weight: .bold)).opacity(0.55)
                    Text("\(cal.component(.day, from: pair.1))")
                        .font(.system(size: 10 * s, weight: today ? .bold : .medium))
                        .frame(width: 16 * s, height: 16 * s)
                        .background(today ? Circle().fill(.red) : nil)
                        .foregroundStyle(today ? .white : .primary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MonthGrid: View {
    let now: Date
    let s: Double
    var cell: Double = 16

    var body: some View {
        let cal = localCalendar()
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        let days = cal.range(of: .day, in: .month, for: start)!.count
        let lead = (cal.component(.weekday, from: start) - cal.firstWeekday + 7) % 7
        let today = cal.component(.day, from: now)
        let cells: [Int?] = Array(repeating: nil, count: lead) + (1...days).map { $0 }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2 * s), count: 7)

        VStack(alignment: .leading, spacing: 4 * s) {
            Text(now, format: .dateTime.month(.wide).year())
                .font(.system(size: 10 * s, weight: .bold)).textCase(.uppercase).foregroundStyle(.red)
            LazyVGrid(columns: columns, spacing: 3 * s) {
                ForEach(Array(weekdayInitials(cal).enumerated()), id: \.offset) { _, d in
                    Text(d).font(.system(size: 8 * s, weight: .bold)).opacity(0.55)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        Text("\(day)")
                            .font(.system(size: cell * 0.56 * s, weight: day == today ? .bold : .medium))
                            .frame(width: cell * s, height: cell * s)
                            .background(day == today ? Circle().fill(.red) : nil)
                            .foregroundStyle(day == today ? .white : .primary)
                    } else {
                        Color.clear.frame(height: cell * s)
                    }
                }
            }
        }
    }
}

private struct EventsWidget: View {
    let size: WidgetSize
    let m: Metrics
    let now: Date
    let access: Bool
    let events: [CalendarService.Event]

    var body: some View {
        let s = m.s
        VStack(alignment: .leading, spacing: 4 * s) {
            Label(tr("Prossimi eventi", "Up Next"), systemImage: "calendar")
                .font(.system(size: 10 * s, weight: .bold)).textCase(.uppercase).opacity(0.75).lineLimit(1)
            if !access {
                Text(tr("Consenti l'accesso dalle impostazioni", "Allow access in Settings")).font(.system(size: 12 * s, weight: .semibold))
            } else if events.isEmpty {
                Text(tr("Niente in agenda", "Nothing scheduled")).font(.system(size: 14 * s, weight: .bold))
            } else if size == .small {
                let e = events[0]
                Text(e.start.formatted(hm)).font(.system(size: 22 * s, weight: .light))
                Text(e.title).font(.system(size: 13 * s, weight: .bold)).lineLimit(3)
            } else {
                let limit = size == .medium ? 1 : 3
                let columns = size == .wide ? 2 : 1
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: columns), alignment: .leading, spacing: 8 * s) {
                    ForEach(Array(events.prefix(limit).enumerated()), id: \.offset) { _, e in
                        HStack(alignment: .top, spacing: 7 * s) {
                            Capsule().fill(.red).frame(width: 3 * s)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(e.title).font(.system(size: 13.5 * s, weight: .bold)).lineLimit(1)
                                Text(eventTime(e)).font(.system(size: 10.5 * s, weight: .medium)).opacity(0.75).lineLimit(1)
                                if size != .medium, let loc = e.location, !loc.isEmpty {
                                    Text(loc).font(.system(size: 10 * s)).opacity(0.6).lineLimit(1)
                                }
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: size == .medium ? .leading : .topLeading)
        .padding(14 * s)
    }
}

private struct RemindersWidget: View {
    let size: WidgetSize
    let m: Metrics
    let now: Date
    let access: Bool
    let reminders: [CalendarService.Reminder]

    var body: some View {
        let s = m.s
        if size == .small {
            VStack(alignment: .leading, spacing: 2 * s) {
                Image(systemName: "checklist").font(.system(size: 16 * s, weight: .semibold))
                Spacer(minLength: 0)
                Text(access ? "\(reminders.count)" : "—").font(.system(size: 30 * s, weight: .light))
                Text(access ? (reminders.first?.title ?? tr("Tutto fatto", "All done")) : tr("Consenti l'accesso", "Allow access"))
                    .font(.system(size: 10.5 * s, weight: .semibold)).lineLimit(2).opacity(0.85)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12 * s)
        } else {
            VStack(alignment: .leading, spacing: 4 * s) {
                Label(tr("Promemoria", "Reminders"), systemImage: "checklist")
                    .font(.system(size: 10 * s, weight: .bold)).textCase(.uppercase).opacity(0.75)
                if !access {
                    Text(tr("Consenti l'accesso dalle impostazioni", "Allow access in Settings")).font(.system(size: 12 * s, weight: .semibold))
                } else if reminders.isEmpty {
                    Text(tr("Tutto fatto", "All done")).font(.system(size: 14 * s, weight: .bold))
                } else {
                    let limit = size == .medium ? 2 : size == .large ? 6 : 8
                    let columns = size == .wide ? 2 : 1
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: columns), alignment: .leading, spacing: 5 * s) {
                        ForEach(reminders.prefix(limit)) { r in
                            HStack(spacing: 6 * s) {
                                Image(systemName: "circle").font(.system(size: 9 * s, weight: .bold)).opacity(0.7)
                                Text(r.title).lineLimit(1)
                                if let due = r.due, due < now {
                                    Image(systemName: "exclamationmark").font(.system(size: 9 * s, weight: .heavy)).foregroundStyle(.orange)
                                }
                            }
                            .font(.system(size: 12.5 * s, weight: .semibold))
                        }
                    }
                    if reminders.count > limit {
                        Text(tr("altri \(reminders.count - limit)", "\(reminders.count - limit) more")).font(.system(size: 10 * s, weight: .medium)).opacity(0.65)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: size == .medium ? .leading : .topLeading)
            .padding(14 * s)
        }
    }
}

// MARK: Gauges, moon, countdown

/// Ring gauge for battery and day progress, laid out per size.
private struct Gauge: View {
    let size: WidgetSize
    let m: Metrics
    let progress: Double
    let symbol: String
    let value: String
    let label: String
    let detail: String
    var tint: AnyShapeStyle? = nil

    var body: some View {
        let s = m.s
        switch size {
        case .small:
            Ring(progress: progress, m: m, lineWidth: 6, tint: tint) {
                Image(systemName: symbol).font(.system(size: 10 * s))
                Text(value).font(.system(size: 17 * s, weight: .bold))
            }
            .padding(12 * s)
        case .large:
            VStack(spacing: 10 * s) {
                Ring(progress: progress, m: m, lineWidth: 11, tint: tint) {
                    Image(systemName: symbol).font(.system(size: 16 * s))
                    Text(value).font(.system(size: 30 * s, weight: .bold))
                }
                .frame(width: 112 * s, height: 112 * s)
                Text(detail).font(.system(size: 11 * s, weight: .semibold)).opacity(0.8).lineLimit(1)
            }
        case .medium, .wide:
            HStack(spacing: 14 * s) {
                Ring(progress: progress, m: m, lineWidth: 6, tint: tint) {
                    Image(systemName: symbol).font(.system(size: 14 * s))
                }
                .frame(width: 60 * s, height: 60 * s)
                VStack(alignment: .leading, spacing: 2 * s) {
                    Text(label).font(.system(size: 10 * s, weight: .bold)).textCase(.uppercase).opacity(0.7)
                    Text(value).font(.system(size: (size == .wide ? 40 : 26) * s, weight: .light))
                    Text(detail).font(.system(size: 10.5 * s, weight: .semibold)).opacity(0.8).lineLimit(1).minimumScaleFactor(0.75)
                    if size == .wide {
                        LinearBar(progress: progress, s: s, tint: tint).padding(.top, 10 * s)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16 * s)
        }
    }
}

private struct LinearBar: View {
    let progress: Double
    let s: Double
    var tint: AnyShapeStyle? = nil
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.22))
                Capsule().fill(tint ?? AnyShapeStyle(.foreground)).frame(width: geo.size.width * min(1, max(0, progress)))
            }
        }
        .frame(height: 5 * s)
    }
}

private struct MoonWidget: View {
    let size: WidgetSize
    let m: Metrics
    let now: Date

    var body: some View {
        let s = m.s
        let p = moonPhase(now)
        let lit = Int(((1 - cos(2 * .pi * p)) / 2 * 100).rounded())
        let toFull = Int((((0.5 - p) + 1).truncatingRemainder(dividingBy: 1) * 29.53).rounded())
        switch size {
        case .small:
            MoonView(phase: p).padding(18 * s)
        case .large:
            VStack(spacing: 10 * s) {
                MoonView(phase: p).frame(width: 110 * s, height: 110 * s)
                Text(moonName(p)).font(.system(size: 14 * s, weight: .semibold))
                Text(tr("Illuminata al \(lit)%", "\(lit)% illuminated")).font(.system(size: 10.5 * s, weight: .medium)).opacity(0.75)
            }
        case .medium, .wide:
            HStack(spacing: 16 * s) {
                MoonView(phase: p).frame(width: (size == .wide ? 150 : 64) * s, height: (size == .wide ? 150 : 64) * s)
                VStack(alignment: .leading, spacing: 3 * s) {
                    Text(tr("LUNA", "MOON")).font(.system(size: 10 * s, weight: .bold)).opacity(0.7)
                    Text(moonName(p)).font(.system(size: (size == .wide ? 22 : 15) * s, weight: .semibold))
                    Text(tr("Illuminata al \(lit)%", "\(lit)% illuminated")).font(.system(size: 10.5 * s, weight: .medium)).opacity(0.8)
                    Text(toFull == 0 ? tr("Luna piena oggi", "Full moon today")
                                     : tr("Luna piena tra \(toFull) giorni", "Full moon in \(toFull) days"))
                        .font(.system(size: 10.5 * s, weight: .medium)).opacity(0.65)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16 * s)
        }
    }
}

private struct CountdownWidget: View {
    let size: WidgetSize
    let m: Metrics
    let now: Date
    let label: String
    let date: Date

    var body: some View {
        let s = m.s
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        let unit = days < 0 ? tr("giorni fa", "days ago") : days == 1 ? tr("giorno", "day") : tr("giorni", "days")
        let dateText = date.formatted(.dateTime.weekday(.abbreviated).day().month(.wide))
        switch size {
        case .small:
            VStack(spacing: 2 * s) {
                Text("\(abs(days))").font(.system(size: 30 * s, weight: .bold))
                Text(unit.uppercased()).font(.system(size: 8 * s, weight: .bold)).opacity(0.75)
                Text(label).font(.system(size: 10 * s, weight: .semibold)).lineLimit(1).opacity(0.85)
            }
            .padding(.horizontal, 8 * s)
        case .large:
            VStack(spacing: 4 * s) {
                Image(systemName: "flag.checkered").font(.system(size: 18 * s))
                Text("\(abs(days))").font(.system(size: 64 * s, weight: .light))
                Text(unit.uppercased()).font(.system(size: 10 * s, weight: .bold)).opacity(0.75)
                Text(label).font(.system(size: 15 * s, weight: .semibold)).lineLimit(1)
                Text(dateText).font(.system(size: 10.5 * s, weight: .medium)).opacity(0.7)
            }
            .padding(12 * s)
        case .medium, .wide:
            HStack {
                VStack(alignment: .leading, spacing: 2 * s) {
                    Label(label, systemImage: "flag.checkered")
                        .font(.system(size: 10 * s, weight: .bold)).textCase(.uppercase).opacity(0.75).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(dateText).font(.system(size: 11 * s, weight: .semibold)).opacity(0.8)
                }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 4 * s) {
                    Text("\(abs(days))").font(.system(size: (size == .wide ? 80 : 40) * s, weight: .light))
                    Text(unit).font(.system(size: 12 * s, weight: .semibold)).opacity(0.75)
                }
            }
            .padding(16 * s)
        }
    }
}

// MARK: Music and lyrics

private struct NowPlayingWidget: View {
    let item: WidgetItem
    let m: Metrics
    let size: CGSize
    @EnvironmentObject var music: NowPlayingService

    var body: some View {
        let s = m.s
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            switch item.size {
            case .small:
                ZStack(alignment: .bottomLeading) {
                    Artwork(image: music.artwork, side: size.width, corner: 0)
                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(music.title ?? tr("Niente in riproduzione", "Nothing playing")).font(.system(size: 11 * s, weight: .bold)).lineLimit(1)
                        Text(music.artist ?? "").font(.system(size: 9 * s, weight: .semibold)).opacity(0.8).lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(9 * s)
                }
            case .large:
                VStack(alignment: .leading, spacing: 6 * s) {
                    Artwork(image: music.artwork, side: size.height * 0.5, corner: 0.1)
                    Spacer(minLength: 0)
                    trackInfo(titleSize: 15, artistSize: 10.5)
                    progress(at: ctx.date, times: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14 * s)
            case .medium, .wide:
                let wide = item.size == .wide
                HStack(spacing: 14 * s) {
                    Artwork(image: music.artwork, side: size.height - 28 * s, corner: 0.12)
                    VStack(alignment: .leading, spacing: (wide ? 5 : 2) * s) {
                        trackInfo(titleSize: wide ? 17 : 13, artistSize: wide ? 11 : 9.5)
                        progress(at: ctx.date, times: wide).padding(.top, (wide ? 10 : 4) * s)
                        if wide, music.title != nil {
                            Text(music.isPlaying ? tr("In riproduzione su \(music.source)", "Playing on \(music.source)")
                                                 : tr("In pausa · \(music.source)", "Paused · \(music.source)"))
                                .font(.system(size: 10 * s, weight: .medium)).opacity(0.6).padding(.top, 6 * s)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14 * s)
            }
        }
    }

    @ViewBuilder
    private func trackInfo(titleSize: Double, artistSize: Double) -> some View {
        let s = m.s
        if let t = music.title {
            HStack {
                Text(t).font(.system(size: titleSize * s, weight: .bold)).lineLimit(1)
                Spacer(minLength: 0)
                if music.isPlaying {
                    Image(systemName: "waveform").font(.system(size: 12 * s, weight: .semibold)).opacity(0.8)
                }
            }
            Text(music.artist ?? "").textCase(.uppercase)
                .font(.system(size: artistSize * s, weight: .semibold)).opacity(0.7).lineLimit(1)
        } else {
            Text(tr("Niente in riproduzione", "Nothing playing")).font(.system(size: 14 * s, weight: .bold))
            Text(tr("Musica o Spotify", "Music or Spotify")).font(.system(size: 11 * s)).opacity(0.7)
        }
    }

    @ViewBuilder
    private func progress(at date: Date, times: Bool) -> some View {
        if music.title != nil, let d = music.duration, d > 0 {
            Progress(position: music.position(at: date), duration: d, s: m.s, showTimes: times)
        }
    }
}

private struct Artwork: View {
    let image: NSImage?
    let side: CGFloat
    /// Corner radius as a fraction of the side.
    let corner: CGFloat
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [.pink.opacity(0.7), .orange.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").font(.system(size: side * 0.35, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * corner, style: .continuous))
    }
}

private struct Progress: View {
    let position: Double
    let duration: Double
    let s: Double
    let showTimes: Bool

    var body: some View {
        VStack(spacing: 3 * s) {
            LinearBar(progress: position / duration, s: s * 0.8)
            if showTimes {
                HStack {
                    Text(time(position))
                    Spacer()
                    Text(time(duration))
                }
                .font(.system(size: 9 * s, weight: .semibold).monospacedDigit())
                .opacity(0.65)
            }
        }
    }

    private func time(_ t: Double) -> String {
        let t = max(0, Int(t))
        return "\(t / 60):" + String(format: "%02d", t % 60)
    }
}

private struct LyricsWidget: View {
    let item: WidgetItem
    let m: Metrics
    @EnvironmentObject var music: NowPlayingService
    @EnvironmentObject var lyrics: LyricsService

    var body: some View {
        let s = m.s
        let sz = item.size
        let center = item.bare
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let pos = music.position(at: ctx.date)
            let (before, after) = sz == .large ? (2, 3) : sz == .wide ? (1, 1) : (0, sz == .medium ? 1 : 0)
            let window = lyrics.window(at: pos, before: before, after: after)
            let current = window.first(where: \.current)?.text
            VStack(alignment: center ? .center : .leading, spacing: (sz == .wide || sz == .large ? 10 : 5) * s) {
                if !item.bare && sz != .small {
                    Label(header, systemImage: "quote.bubble")
                        .font(.system(size: 10 * s, weight: .bold)).textCase(.uppercase).opacity(0.75).lineLimit(1)
                }
                switch (music.title == nil, lyrics.state) {
                case (true, _):
                    Text(item.bare ? "" : tr("Niente in riproduzione", "Nothing playing")).font(.system(size: 14 * s, weight: .bold))
                case (_, .loading), (_, .idle):
                    Text(tr("Cerco il testo…", "Finding lyrics…")).font(.system(size: 14 * s, weight: .bold)).opacity(0.8)
                case (_, .missing):
                    Text(item.bare ? "" : tr("Testo non trovato", "No lyrics found")).font(.system(size: 14 * s, weight: .bold)).opacity(0.8)
                case (_, .plain):
                    Text(lyrics.lines.first?.text ?? "").font(.system(size: 14 * s, weight: .bold)).lineLimit(2)
                    Text(tr("Testo non sincronizzato", "Lyrics not synced")).font(.system(size: 10 * s, weight: .medium)).opacity(0.6)
                case (_, .synced):
                    ForEach(Array(window.enumerated()), id: \.offset) { _, line in
                        Text(line.current && line.text.trimmingCharacters(in: .whitespaces).isEmpty ? "♪" : line.text)
                            .font(.system(size: (line.current ? (sz == .wide ? 19 : sz == .small ? 14 : 16) : (sz == .wide ? 15 : 12)) * s,
                                          weight: line.current ? .bold : .semibold))
                            .opacity(line.current ? 1 : 0.45)
                            .lineLimit(sz == .small ? 4 : line.current ? 2 : 1)
                    }
                }
            }
            .multilineTextAlignment(center ? .center : .leading)
            .animation(.easeOut(duration: 0.35), value: current)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: center ? .center : .leading)
            .padding(.horizontal, 14 * s)
        }
    }

    private var header: String {
        guard let t = music.title else { return tr("Testo", "Lyrics") }
        if let a = music.artist, !a.isEmpty { return "\(t) · \(a)" }
        return t
    }
}

// MARK: Clocks

/// Analog face for the local clock and world clocks, laid out per size.
private struct ClockWidget: View {
    let size: WidgetSize
    let m: Metrics
    let timeZone: TimeZone
    let title: String?

    var body: some View {
        let s = m.s
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let digital = Date.FormatStyle(timeZone: timeZone).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
            switch size {
            case .small:
                ZStack {
                    ClockFace(date: ctx.date, timeZone: timeZone, seconds: title == nil)
                    if let title {
                        Text(String(title.prefix(3)).uppercased())
                            .font(.system(size: 8 * s, weight: .bold)).opacity(0.75)
                            .offset(y: 22 * s)
                    }
                }
                .padding(10 * s)
            case .large:
                VStack(spacing: 6 * s) {
                    ClockFace(date: ctx.date, timeZone: timeZone, seconds: true).frame(width: 140 * s, height: 140 * s)
                    Text(title ?? ctx.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.system(size: 12 * s, weight: .semibold)).lineLimit(1)
                }
            case .medium, .wide:
                HStack(spacing: (size == .wide ? 16 : 10) * s) {
                    ClockFace(date: ctx.date, timeZone: timeZone, seconds: true)
                        .frame(width: (size == .wide ? 160 : 62) * s, height: (size == .wide ? 160 : 62) * s)
                    VStack(alignment: .leading, spacing: 2 * s) {
                        Text((title ?? tr("Ora locale", "Local time")).uppercased()).font(.system(size: 10 * s, weight: .bold)).opacity(0.7).lineLimit(1)
                        Text(ctx.date, format: digital).font(.system(size: (size == .wide ? 52 : 26) * s, weight: .light))
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text(title == nil ? ctx.date.formatted(.dateTime.weekday(.wide).day().month(.wide)) : offsetText(timeZone, now: ctx.date))
                            .font(.system(size: 10.5 * s, weight: .medium)).opacity(0.75).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, (size == .wide ? 16 : 12) * s)
            }
        }
    }
}

private struct ClockFace: View {
    let date: Date
    let timeZone: TimeZone
    let seconds: Bool

    var body: some View {
        Canvas { g, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func point(_ angle: Double, _ len: Double) -> CGPoint {
                CGPoint(x: c.x + len * sin(angle), y: c.y - len * cos(angle))
            }
            var dial = g
            dial.opacity = 0.07
            dial.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .foreground)
            for i in 0..<60 {
                let a = Double(i) / 60 * 2 * .pi
                let major = i % 5 == 0
                var p = Path()
                p.move(to: point(a, r * (major ? 0.82 : 0.88)))
                p.addLine(to: point(a, r * 0.94))
                var tick = g
                tick.opacity = major ? 0.9 : 0.35
                tick.stroke(p, with: .foreground, lineWidth: major ? 2 : 1)
            }
            if r > 50 {
                for (n, hour) in [(12, 0.0), (3, 3.0), (6, 6.0), (9, 9.0)] {
                    g.draw(Text("\(n)").font(.system(size: r * 0.17, weight: .semibold, design: .rounded)).foregroundStyle(.foreground),
                           at: point(hour / 12 * 2 * .pi, r * 0.64))
                }
            }
            var cal = Calendar.current
            cal.timeZone = timeZone
            let comps = cal.dateComponents([.hour, .minute, .second], from: date)
            let sec = Double(comps.second ?? 0)
            let min = Double(comps.minute ?? 0) + sec / 60
            let hour = Double((comps.hour ?? 0) % 12) + min / 60
            for (angle, len, width) in [(hour / 12, 0.5, max(3, r * 0.06)), (min / 60, 0.74, max(2, r * 0.045))] {
                var p = Path()
                p.move(to: c)
                p.addLine(to: point(angle * 2 * .pi, r * len))
                g.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
            if seconds {
                var sp = Path()
                sp.move(to: point(sec / 60 * 2 * .pi + .pi, r * 0.15))
                sp.addLine(to: point(sec / 60 * 2 * .pi, r * 0.84))
                g.stroke(sp, with: .color(.orange), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
            let dot = max(3, r * 0.05)
            g.fill(Path(ellipseIn: CGRect(x: c.x - dot, y: c.y - dot, width: dot * 2, height: dot * 2)), with: .color(seconds ? .orange : .white))
        }
    }
}

// MARK: Photo and shared pieces

private struct PhotoWidget: View {
    let item: WidgetItem
    let now: Date
    let m: Metrics
    let size: CGSize

    var body: some View {
        let files = PhotoLibrary.shared.files(in: item.folderPath)
        if files.isEmpty {
            VStack(spacing: 4 * m.s) {
                Image(systemName: "photo.on.rectangle").font(.system(size: 18 * m.s))
                Text(tr("Nessuna foto nella cartella", "No photos in this folder")).font(.system(size: 11 * m.s, weight: .semibold)).multilineTextAlignment(.center)
            }
            .padding(8 * m.s)
        } else {
            let slot = Int(now.timeIntervalSince1970 / Double(max(1, item.photoMinutes) * 60))
            if let img = PhotoLibrary.shared.image(files[slot % files.count]) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            }
        }
    }
}

private struct Ring<Inner: View>: View {
    let progress: Double
    let m: Metrics
    var lineWidth: Double = 6
    /// Color of the filled arc; the text color when nil.
    var tint: AnyShapeStyle? = nil
    @ViewBuilder let inner: Inner

    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.22), lineWidth: lineWidth * m.s)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(tint ?? AnyShapeStyle(.foreground), style: StrokeStyle(lineWidth: lineWidth * m.s, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) { inner }
        }
    }
}

struct MoonView: View {
    let phase: Double

    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let disk = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            var dark = ctx
            dark.opacity = 0.16
            dark.fill(disk, with: .color(.white))
            dark.opacity = 0.3
            dark.stroke(disk, with: .color(.white), lineWidth: max(1, r * 0.02))
            // Lit side: right while waxing, left while waning. The terminator is the limb squashed by k.
            let side: Double = phase < 0.5 ? 1 : -1
            let k = cos(2 * .pi * phase)
            var lit = Path()
            let steps = 48
            for i in 0...steps {
                let t = -Double.pi / 2 + .pi * Double(i) / Double(steps)
                let p = CGPoint(x: c.x + side * r * cos(t), y: c.y + r * sin(t))
                i == 0 ? lit.move(to: p) : lit.addLine(to: p)
            }
            for i in (0...steps).reversed() {
                let t = -Double.pi / 2 + .pi * Double(i) / Double(steps)
                lit.addLine(to: CGPoint(x: c.x + side * r * cos(t) * k, y: c.y + r * sin(t)))
            }
            lit.closeSubpath()
            var glow = ctx
            glow.addFilter(.shadow(color: .white.opacity(0.45), radius: r * 0.18))
            glow.fill(lit, with: .radialGradient(
                Gradient(colors: [.white, Color(white: 0.86), Color(white: 0.72)]),
                center: CGPoint(x: c.x - side * r * 0.25, y: c.y - r * 0.3), startRadius: 0, endRadius: r * 1.4))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Helpers

func moonPhase(_ d: Date) -> Double {
    let synodic = 29.530588853
    let reference = Date(timeIntervalSince1970: 947_182_440) // new moon, 2000-01-06 18:14 UTC
    let days = d.timeIntervalSince(reference) / 86400
    return (days.truncatingRemainder(dividingBy: synodic) + synodic).truncatingRemainder(dividingBy: synodic) / synodic
}

func moonName(_ p: Double) -> String {
    [tr("Luna nuova", "New Moon"), tr("Falce crescente", "Waxing Crescent"), tr("Primo quarto", "First Quarter"), tr("Gibbosa crescente", "Waxing Gibbous"),
     tr("Luna piena", "Full Moon"), tr("Gibbosa calante", "Waning Gibbous"), tr("Ultimo quarto", "Last Quarter"), tr("Falce calante", "Waning Crescent")][Int(p * 8 + 0.5) % 8]
}

let worldCities: [(tz: String, name: String)] = [
    ("Europe/Rome", tr("Roma", "Rome")), ("Europe/London", tr("Londra", "London")), ("America/New_York", "New York"),
    ("America/Los_Angeles", "Los Angeles"), ("America/Sao_Paulo", tr("San Paolo", "São Paulo")), ("Asia/Dubai", "Dubai"),
    ("Asia/Tokyo", "Tokyo"), ("Australia/Sydney", "Sydney"),
]

func cityName(_ tz: String) -> String {
    worldCities.first { $0.tz == tz }?.name ?? tz
}

func offsetText(_ tz: TimeZone, now: Date) -> String {
    let diff = tz.secondsFromGMT(for: now) - TimeZone.current.secondsFromGMT(for: now)
    if diff == 0 { return tr("stessa ora", "same time") }
    let h = Double(diff) / 3600
    let v = h == h.rounded() ? String(Int(abs(h))) : abs(h).formatted(.number.precision(.fractionLength(1)))
    return (diff > 0 ? "+" : "−") + v + " h"
}
