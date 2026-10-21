import SwiftUI
import UniformTypeIdentifiers

/// State of the layout studio (the interactive preview).
@MainActor
final class EditState: ObservableObject {
    @Published var selected: UUID?
    @Published var message: String?
    @Published var centerGuide = false
    @Published var overTrash = false
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
private let fullMessage = "Hai già \(Config.maxItems) widget: togline uno prima"

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
        .onAppear {
            // Development aid: `--gallery` opens the size gallery and selects the first widget.
            if CommandLine.arguments.contains("--gallery") {
                edit.gallery = .weather
                edit.selected = store.config.items.first?.id
            }
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
                }
            }
            .scaleEffect(dragging ? 1.03 : 1)
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
                        var t = v.translation
                        // Snap to the horizontal center of the screen.
                        let cx = item.x * screen.width + t.width
                        edit.centerGuide = abs(cx - screen.width / 2) < 8
                        if edit.centerGuide { t.width = screen.width / 2 - item.x * screen.width }
                        drag = t
                        edit.overTrash = edit.trashFrame.contains(v.location)
                    }
                    .onEnded { v in
                        defer {
                            drag = .zero
                            dragging = false
                            edit.centerGuide = false
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
                        moved.x = Double((cx / 4).rounded() * 4 / screen.width)
                        moved.y = Double((cy / 4).rounded() * 4 / screen.height)
                        store.config.items.append(moved) // dragged card comes to the front
                    }
            )
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

    var body: some View {
        let m = Metrics(s: store.config.scale)
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: 22, height: 22)
            .background(.white, in: Circle())
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .contentShape(Circle().inset(by: -6))
            .help("Trascina per cambiare dimensione")
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
                        guard best != item.size,
                              let i = store.config.items.firstIndex(where: { $0.id == item.id }) else { return }
                        let ns = m.size(best)
                        withAnimation(.snappy(duration: 0.2)) {
                            store.config.items[i].size = best
                            store.config.items[i].x = Double((start.topLeft.x + ns.width / 2) / screen.width)
                            store.config.items[i].y = Double((start.topLeft.y + ns.height / 2) / screen.height)
                        }
                    }
                    .onEnded { _ in
                        start = nil
                        edit.resizing = nil
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

    private static let noteColors: [RGBA] = [
        .noteCoral, RGBA(r: 0.96, g: 0.80, b: 0.35, a: 1), RGBA(r: 0.55, g: 0.78, b: 0.52, a: 1),
        RGBA(r: 0.45, g: 0.65, b: 0.92, a: 1), RGBA(r: 0.72, g: 0.55, b: 0.88, a: 1), RGBA(r: 0.95, g: 0.95, b: 0.92, a: 1),
    ]

    var body: some View {
        HStack(spacing: 10) {
            Text(item.kind.title).font(.system(size: 12, weight: .semibold))
            Picker("Dimensione", selection: binding(\.size)) {
                ForEach(item.kind.sizes) { Text($0.short).help($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if item.kind != .note && item.kind != .photo {
                Toggle(isOn: binding(\.bare)) { Image(systemName: "square.dashed") }
                    .toggleStyle(.button)
                    .help("Senza riquadro: il widget sta direttamente sullo sfondo")
            }
            if item.kind == .note {
                HStack(spacing: 5) {
                    ForEach(Self.noteColors, id: \.self) { c in
                        Circle().fill(c.color)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(.white, lineWidth: item.color == c ? 2 : 0))
                            .onTapGesture { update { $0.color = c } }
                    }
                }
            }
            Button(role: .destructive) {
                withAnimation(.snappy) { store.config.items.removeAll { $0.id == item.id } }
                edit.selected = nil
            } label: {
                Image(systemName: "trash")
            }
            .help("Rimuovi")
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

                Button {
                    withAnimation(.snappy) { store.config.arrangeInRows(screen: screen) }
                } label: {
                    Label("In righe", systemImage: "square.grid.2x2")
                }
                .help("Rimetti i widget in righe ordinate sotto l'orologio")

                Image(systemName: edit.overTrash ? "trash.fill" : "trash")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(edit.overTrash ? Color.red.opacity(0.75) : Color.white.opacity(0.12), in: Circle())
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("studio")) }) { edit.trashFrame = $0.insetBy(dx: -12, dy: -12) }
                    .help("Trascina qui un widget per toglierlo")

                Button("Fine", action: onClose)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text("Trascina i widget dove vuoi · tira l'angolo per cambiare dimensione · clic per le opzioni · sul cestino per toglierli · Esc per chiudere")
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
        .help("Fai clic per scegliere la dimensione di \(kind.title), o trascinalo sullo schermo")
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
                    .help("Chiudi")
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
                    .help("Aggiungi \(kind.title) \(size.title.lowercased())")
                }
            }
            .scaleEffect(fit)
            .frame(width: total * fit, height: (m.size(.large).height + 30 / fit) * fit)
            Text("Fai clic su una dimensione per aggiungerla al centro, o trascinala dove la vuoi")
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
                edit.selected = store.config.items.last?.id
                edit.gallery = nil
            } else {
                edit.flash(fullMessage)
            }
        }
    }
}
