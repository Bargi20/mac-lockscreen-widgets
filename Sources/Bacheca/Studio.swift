import SwiftUI
import UniformTypeIdentifiers

/// State of the layout studio (the interactive preview).
@MainActor
final class EditState: ObservableObject {
    @Published var selected: UUID?
    @Published var message: String?
    @Published var centerGuide = false
    @Published var overTrash = false
    /// Grid cells are drawn while a card is being moved or resized.
    @Published var showGrid = false
    /// Widget whose size gallery is open in the bottom bar.
    @Published var gallery: WidgetKind?
    /// Size shown in a badge while a corner handle is dragged.
    @Published var resizing: WidgetSize?
    var trashFrame: CGRect = .zero

    func flash(_ text: String) {
        message = text
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if message == text { message = nil }
        }
    }
}

private let newPrefix = "new:"
private let fullMessage = tr("Hai già \(Config.maxItems) widget: togline uno prima", "You already have \(Config.maxItems) widgets: remove one first")

/// Drag payload for a new widget: "new:<kind>" or "new:<kind>:<size>".
private func newPayload(_ kind: WidgetKind, _ size: WidgetSize? = nil) -> NSString {
    (newPrefix + kind.rawValue + (size.map { ":" + $0.rawValue } ?? "")) as NSString
}

private func parsePayload(_ s: String) -> (WidgetKind, WidgetSize?)? {
    guard s.hasPrefix(newPrefix) else { return nil }
    let parts = s.dropFirst(newPrefix.count).split(separator: ":").map(String.init)
    guard let kind = parts.first.flatMap(WidgetKind.init(rawValue:)) else { return nil }
    return (kind, parts.count > 1 ? WidgetSize(rawValue: parts[1]) : nil)
}

/// Puts the newest widget on the grid, when the grid is on.
@MainActor
private func snapNewest(_ store: ConfigStore, _ screen: CGSize) {
    guard store.config.snapToGrid, let i = store.config.items.indices.last else { return }
    let item = store.config.items[i]
    let p = LayoutGrid(m: Metrics(s: store.config.scale), screen: screen)
        .snap(center: CGPoint(x: item.x * screen.width, y: item.y * screen.height), size: item.size)
    store.config.items[i].x = Double(p.x / screen.width)
    store.config.items[i].y = Double(p.y / screen.height)
}

// MARK: - Canvas

struct StudioCanvas: View {
    let screen: CGSize
    let onClose: () -> Void
    @EnvironmentObject var store: ConfigStore
    @StateObject private var edit = EditState()

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    edit.selected = nil
                    edit.gallery = nil
                }
                .onDrop(of: [.plainText], delegate: PaletteDrop(store: store, edit: edit, screen: screen))

            if edit.showGrid {
                GridOverlay(grid: LayoutGrid(m: Metrics(s: store.config.scale), screen: screen))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            if edit.centerGuide {
                Rectangle().fill(.yellow.opacity(0.8))
                    .frame(width: 1, height: screen.height)
                    .position(x: screen.width / 2, y: screen.height / 2)
                    .allowsHitTesting(false)
            }

            ForEach(store.config.items) { item in
                DraggableCard(item: item, screen: screen, edit: edit)
            }

            StudioBar(edit: edit, screen: screen, onClose: onClose)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: screen.width, height: screen.height)
        .coordinateSpace(name: "studio")
        .animation(.easeOut(duration: 0.15), value: edit.showGrid)
        .onAppear {
            // Development aids: `--gallery` opens the size gallery and selects the first widget,
            // `--grid` shows the grid cells.
            if CommandLine.arguments.contains("--gallery") {
                edit.gallery = .weather
                edit.selected = store.config.items.first?.id
            }
            if CommandLine.arguments.contains("--grid") { edit.showGrid = true }
        }
    }
}

/// Palette entries dropped anywhere on the canvas land where they were dropped.
private struct PaletteDrop: DropDelegate {
    let store: ConfigStore
    let edit: EditState
    let screen: CGSize

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        let point = CGPoint(x: info.location.x / screen.width, y: info.location.y / screen.height)
        _ = provider.loadObject(ofClass: NSString.self) { obj, _ in
            guard let s = obj as? NSString, let (kind, size) = parsePayload(String(s)) else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    withAnimation(.snappy) {
                        if store.add(kind, size: size, at: point) {
                            snapNewest(store, screen)
                            edit.selected = store.config.items.last?.id
                            edit.gallery = nil
                        } else {
                            edit.flash(fullMessage)
                        }
                    }
                }
            }
        }
        return true
    }
}

// MARK: - Cards

private struct DraggableCard: View {
    let item: WidgetItem
    let screen: CGSize
    @ObservedObject var edit: EditState
    @EnvironmentObject var store: ConfigStore
    @State private var drag: CGSize = .zero
    @State private var dragging = false
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Critically damped spring: settles without overshoot, as Apple recommends for repositioning.
    static let settle = Animation.spring(response: 0.3, dampingFraction: 1)

    var body: some View {
        let m = Metrics(s: store.config.scale)
        let size = m.size(item.size)
        let selected = edit.selected == item.id
        WidgetCard(item: item)
            .overlay {
                RoundedRectangle(cornerRadius: m.radius + 5, style: .continuous)
                    .strokeBorder(.white.opacity(selected ? 0.9 : hover ? 0.35 : 0), lineWidth: 2)
                    .padding(-5)
            }
            .scaleEffect(dragging && !reduceMotion ? 1.03 : 1)
            .shadow(color: .black.opacity(dragging ? 0.4 : 0), radius: 18, y: 8)
            .opacity(dragging && edit.overTrash ? 0.45 : 1)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture { edit.selected = item.id }
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named("studio"))
                    .onChanged { v in
                        dragging = true
                        edit.selected = item.id
                        let start = CGPoint(x: item.x * screen.width, y: item.y * screen.height)
                        var target = CGPoint(x: start.x + v.translation.width, y: start.y + v.translation.height)
                        // Hold Option to place a card freely, off the grid.
                        let free = !store.config.snapToGrid || NSEvent.modifierFlags.contains(.option)
                        if free {
                            // Snap to the horizontal center of the screen.
                            edit.centerGuide = abs(target.x - screen.width / 2) < 8
                            if edit.centerGuide { target.x = screen.width / 2 }
                            edit.showGrid = false
                        } else {
                            target = LayoutGrid(m: m, screen: screen).snap(center: target, size: item.size)
                            edit.centerGuide = false
                            edit.showGrid = true
                        }
                        let next = CGSize(width: target.x - start.x, height: target.y - start.y)
                        if next != drag {
                            withAnimation(free || reduceMotion ? nil : Self.settle) { drag = next }
                        }
                        edit.overTrash = edit.trashFrame.contains(v.location)
                    }
                    .onEnded { v in
                        defer {
                            drag = .zero
                            dragging = false
                            edit.centerGuide = false
                            edit.showGrid = false
                            edit.overTrash = false
                        }
                        if edit.trashFrame.contains(v.location) {
                            withAnimation(.snappy) { store.config.items.removeAll { $0.id == item.id } }
                            edit.selected = nil
                            return
                        }
                        let cx = clamp(item.x * screen.width + drag.width, size.width / 2, screen.width - size.width / 2)
                        let cy = clamp(item.y * screen.height + drag.height, size.height / 2, screen.height - size.height / 2)
                        guard let i = store.config.items.firstIndex(where: { $0.id == item.id }) else { return }
                        var moved = store.config.items.remove(at: i)
                        moved.x = Double(cx / screen.width)
                        moved.y = Double(cy / screen.height)
                        store.config.items.append(moved) // dragged card comes to the front
                    }
            )
            // Controls go after the card's hit shape and gestures: the toolbar sits outside the
            // card's bounds, and the card's drag must not swallow clicks on its buttons.
            .overlay(alignment: .top) {
                if selected && !dragging {
                    CardToolbar(item: item, edit: edit, screen: screen)
                        .fixedSize()
                        .offset(y: -50)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if selected && !dragging {
                    ResizeHandle(item: item, screen: screen, edit: edit).offset(x: 10, y: 10)
                }
            }
            .overlay {
                if selected, let size = edit.resizing {
                    Text("\(size.short) · \(size.title)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.black.opacity(0.6), in: Capsule())
                        .allowsHitTesting(false)
                }
            }
            .position(x: item.x * screen.width + drag.width, y: item.y * screen.height + drag.height)
    }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), hi) }
}

/// Corner handle: dragging it snaps the card to the nearest of S, M, L and XL, keeping its top-left corner.
private struct ResizeHandle: View {
    let item: WidgetItem
    let screen: CGSize
    @ObservedObject var edit: EditState
    @EnvironmentObject var store: ConfigStore
    @State private var start: (size: CGSize, topLeft: CGPoint)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let m = Metrics(s: store.config.scale)
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: 22, height: 22)
            .background(.white, in: Circle())
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .contentShape(Circle().inset(by: -6))
            .help(tr("Trascina per cambiare dimensione", "Drag to resize"))
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("studio"))
                    .onChanged { v in
                        if start == nil {
                            let s = m.size(item.size)
                            start = (s, CGPoint(x: item.x * screen.width - s.width / 2, y: item.y * screen.height - s.height / 2))
                        }
                        guard let start else { return }
                        let target = CGSize(width: start.size.width + v.translation.width, height: start.size.height + v.translation.height)
                        let best = WidgetSize.allCases.min {
                            distance(m.size($0), target) < distance(m.size($1), target)
                        } ?? item.size
                        edit.resizing = best
                        edit.showGrid = store.config.snapToGrid
                        guard best != item.size,
                              let i = store.config.items.firstIndex(where: { $0.id == item.id }) else { return }
                        let ns = m.size(best)
                        var center = CGPoint(x: start.topLeft.x + ns.width / 2, y: start.topLeft.y + ns.height / 2)
                        if store.config.snapToGrid {
                            // Keeps the grown card inside the grid when it would spill past an edge.
                            center = LayoutGrid(m: m, screen: screen).snap(center: center, size: best)
                        }
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1)) {
                            store.config.items[i].size = best
                            store.config.items[i].x = Double(center.x / screen.width)
                            store.config.items[i].y = Double(center.y / screen.height)
                        }
                    }
                    .onEnded { _ in
                        start = nil
                        edit.resizing = nil
                        edit.showGrid = false
                    }
            )
    }

    private func distance(_ a: CGSize, _ b: CGSize) -> CGFloat {
        hypot(a.width - b.width, a.height - b.height)
    }
}

/// Floating controls over the selected card.
private struct CardToolbar: View {
    let item: WidgetItem
    @ObservedObject var edit: EditState
    let screen: CGSize
    @EnvironmentObject var store: ConfigStore

    private static let backColors: [RGBA] = [
        RGBA(r: 0.20, g: 0.22, b: 0.30, a: 1), RGBA(r: 0.05, g: 0.05, b: 0.07, a: 1), RGBA(r: 0.10, g: 0.24, b: 0.52, a: 1),
        RGBA(r: 0.13, g: 0.36, b: 0.27, a: 1), RGBA(r: 0.48, g: 0.14, b: 0.20, a: 1), RGBA(r: 0.86, g: 0.78, b: 0.66, a: 1),
        RGBA(r: 0.96, g: 0.96, b: 0.95, a: 1),
    ]

    private static let noteColors: [RGBA] = [
        .noteCoral, RGBA(r: 0.96, g: 0.80, b: 0.35, a: 1), RGBA(r: 0.55, g: 0.78, b: 0.52, a: 1),
        RGBA(r: 0.45, g: 0.65, b: 0.92, a: 1), RGBA(r: 0.72, g: 0.55, b: 0.88, a: 1), RGBA(r: 0.95, g: 0.95, b: 0.92, a: 1),
    ]

    var body: some View {
        HStack(spacing: 10) {
            Text(item.kind.title).font(.system(size: 12, weight: .semibold))
            Picker(tr("Dimensione", "Size"), selection: binding(\.size)) {
                ForEach(item.kind.sizes) { Text($0.short).help($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if item.hasRetro {
                Menu {
                    ForEach(Retro.allCases) { retro in
                        Button {
                            if retro == .image, item.backdropImage.isEmpty {
                                guard let path = chooseImage(startingAt: nil) else { return }
                                update { $0.backdropImage = path }
                            }
                            update { $0.retro = retro }
                        } label: {
                            Label(retro.title, systemImage: item.retro == retro ? "checkmark" : retro.symbol)
                        }
                    }
                    if item.retro == .image {
                        Divider()
                        Button(tr("Cambia immagine…", "Change Image…")) {
                            if let path = chooseImage(startingAt: item.backdropImage) { update { $0.backdropImage = path } }
                        }
                    }
                } label: {
                    Image(systemName: item.retro.symbol)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(tr("Retro: cosa c'è dietro il widget", "Back: what sits behind the widget"))
            }
            if item.kind == .note {
                Swatches(colors: Self.noteColors, selected: item.color) { c in update { $0.color = c } }
            } else if item.hasRetro && item.retro == .color {
                Swatches(colors: Self.backColors, selected: item.backdropColor) { c in update { $0.backdropColor = c } }
            }
            Button(role: .destructive) {
                withAnimation(.snappy) { store.config.items.removeAll { $0.id == item.id } }
                edit.selected = nil
            } label: {
                Image(systemName: "trash")
            }
            .help(tr("Rimuovi", "Remove"))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
    }

    private func update(_ change: (inout WidgetItem) -> Void) {
        guard let i = store.config.items.firstIndex(where: { $0.id == item.id }) else { return }
        change(&store.config.items[i])
    }

    private func binding<T>(_ key: WritableKeyPath<WidgetItem, T>) -> Binding<T> {
        Binding(get: { item[keyPath: key] }, set: { v in update { $0[keyPath: key] = v } })
    }
}

private struct Swatches: View {
    let colors: [RGBA]
    let selected: RGBA
    let pick: (RGBA) -> Void

    var body: some View {
        HStack(spacing: 5) {
            ForEach(colors, id: \.self) { c in
                Circle().fill(c.color)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(.white, lineWidth: selected == c ? 2 : 0.5))
                    .onTapGesture { pick(c) }
            }
        }
    }
}

/// Asks for a picture file. The panel is raised above the studio, which covers the whole screen.
@MainActor
func chooseImage(startingAt path: String?) -> String? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = false
    panel.prompt = tr("Usa questa immagine", "Use This Image")
    panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
    if let path, !path.isEmpty { panel.directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent() }
    return panel.runModal() == .OK ? panel.url?.path : nil
}

// MARK: - Bottom bar: palette, arrange, trash

private struct StudioBar: View {
    @ObservedObject var edit: EditState
    let screen: CGSize
    let onClose: () -> Void
    @EnvironmentObject var store: ConfigStore

    var body: some View {
        VStack(spacing: 10) {
            if let message = edit.message {
                Text(message)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(.orange.opacity(0.85), in: Capsule())
                    .transition(.opacity)
            }
            if let kind = edit.gallery {
                SizeGallery(kind: kind, edit: edit, screen: screen)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(WidgetKind.allCases) { PaletteChip(kind: $0, edit: edit) }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxWidth: 700)

                Divider().frame(height: 28)

                Toggle(isOn: $store.config.snapToGrid) {
                    Label(tr("Griglia", "Grid"), systemImage: "squareshape.split.3x3")
                }
                .toggleStyle(.button)
                .help(tr("Con la griglia i widget scattano di casella in casella e restano allineati. Tieni premuto ⌥ per spostarli liberamente", "With the grid, widgets snap from cell to cell and stay aligned. Hold ⌥ to move them freely"))

                Button {
                    withAnimation(.snappy) { store.config.snapAll(screen: screen) }
                } label: {
                    Label(tr("Allinea", "Align"), systemImage: "align.horizontal.center")
                }
                .help(tr("Sposta ogni widget sulla casella più vicina della griglia", "Move every widget to the nearest grid cell"))

                Button {
                    withAnimation(.snappy) {
                        store.config.arrangeInRows(screen: screen)
                        if store.config.snapToGrid { store.config.snapAll(screen: screen) }
                    }
                } label: {
                    Label(tr("In righe", "In rows"), systemImage: "square.grid.2x2")
                }
                .help(tr("Rimetti i widget in righe ordinate sotto l'orologio", "Put widgets back in tidy rows under the clock"))

                Image(systemName: edit.overTrash ? "trash.fill" : "trash")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(edit.overTrash ? Color.red.opacity(0.75) : Color.white.opacity(0.12), in: Circle())
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("studio")) }) { edit.trashFrame = $0.insetBy(dx: -12, dy: -12) }
                    .help(tr("Trascina qui un widget per toglierlo", "Drag a widget here to remove it"))

                Button(tr("Fine", "Done"), action: onClose)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text(tr("Trascina i widget sulla griglia (⌥ per muoverli liberamente) · tira l'angolo per cambiare dimensione · clic per le opzioni · sul cestino per toglierli · Esc per chiudere", "Drag widgets on the grid (⌥ to move freely) · pull the corner to resize · click for options · drop on the trash to remove · Esc to close"))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.2), value: edit.message)
        .animation(.snappy, value: edit.gallery)
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }
}

private struct PaletteChip: View {
    let kind: WidgetKind
    @ObservedObject var edit: EditState
    @EnvironmentObject var store: ConfigStore

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: kind.symbol)
            Text(kind.title)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(edit.gallery == kind ? Color.white.opacity(0.35) : Color.white.opacity(0.14), in: Capsule())
        .opacity(store.config.canAddMore ? 1 : 0.4)
        .contentShape(Capsule())
        .onDrag { NSItemProvider(object: newPayload(kind)) }
        .onTapGesture { edit.gallery = edit.gallery == kind ? nil : kind }
        .help(tr("Fai clic per scegliere la dimensione di \(kind.title), o trascinalo sullo schermo", "Click to choose a size for \(kind.title), or drag it onto the screen"))
    }
}

/// iPhone-style picker: the widget drawn live in every size; click or drag one to add it.
private struct SizeGallery: View {
    let kind: WidgetKind
    @ObservedObject var edit: EditState
    let screen: CGSize
    @EnvironmentObject var store: ConfigStore

    var body: some View {
        let m = Metrics(s: store.config.scale)
        let spacing: CGFloat = 22
        let total = WidgetSize.allCases.reduce(0) { $0 + m.size($1).width } + spacing * 3
        let fit = min(1, (screen.width - 160) / total, (screen.height * 0.32) / m.size(.large).height)

        VStack(spacing: 14) {
            HStack {
                Label(kind.title, systemImage: kind.symbol).font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { edit.gallery = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help(tr("Chiudi", "Close"))
            }
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(WidgetSize.allCases) { size in
                    VStack(spacing: 8 / fit) {
                        WidgetCard(item: WidgetItem(kind: kind, size: size))
                            .allowsHitTesting(false)
                        Text("\(size.short) · \(size.title)")
                            .font(.system(size: 12 / fit, weight: .semibold))
                            .opacity(0.85)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { add(size) }
                    .onDrag { NSItemProvider(object: newPayload(kind, size)) }
                    .help(tr("Aggiungi \(kind.title) \(size.title.lowercased())", "Add \(kind.title) in \(size.title.lowercased())"))
                }
            }
            .scaleEffect(fit)
            .frame(width: total * fit, height: (m.size(.large).height + 30 / fit) * fit)
            Text(tr("Fai clic su una dimensione per aggiungerla al centro, o trascinala dove la vuoi", "Click a size to add it in the middle, or drag it where you want it"))
                .font(.caption)
                .opacity(0.65)
        }
        .padding(18)
        .fixedSize()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func add(_ size: WidgetSize) {
        withAnimation(.snappy) {
            if store.add(kind, size: size) {
                snapNewest(store, screen)
                edit.selected = store.config.items.last?.id
                edit.gallery = nil
            } else {
                edit.flash(fullMessage)
            }
        }
    }
}

/// Faint outline of every grid cell, shown while a card moves.
private struct GridOverlay: View {
    let grid: LayoutGrid

    var body: some View {
        Canvas { g, _ in
            for col in 0..<grid.columns {
                for row in 0..<grid.rows {
                    let cell = Path(roundedRect: grid.cell(col, row), cornerRadius: grid.m.radius * 0.6, style: .continuous)
                    g.fill(cell, with: .color(.white.opacity(0.06)))
                    g.stroke(cell, with: .color(.white.opacity(0.22)), lineWidth: 1)
                }
            }
            // The center line: groups placed across it come out symmetric.
            var mid = Path()
            mid.move(to: CGPoint(x: grid.screen.width / 2, y: grid.origin.y))
            mid.addLine(to: CGPoint(x: grid.screen.width / 2, y: grid.origin.y + CGFloat(grid.rows) * grid.pitch - grid.m.gap))
            g.stroke(mid, with: .color(.yellow.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }
}
