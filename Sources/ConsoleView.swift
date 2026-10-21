import SwiftUI
import AppKit

struct ConsolePanel: View {
    @EnvironmentObject var store: EventStore
    @Binding var draft: String
    var onRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Консоль ввода", systemImage: "terminal.fill")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("⌘↩ поставить в график")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(store.log) { line in
                            HStack(alignment: .top, spacing: 8) {
                                Text(prefix(line.kind))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(color(line.kind))
                                Text(line.text)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(color(line.kind).opacity(0.95))
                                    .textSelection(.enabled)
                            }
                            .id(line.id)
                        }
                    }
                    .padding(10)
                }
                .frame(minHeight: 88, maxHeight: 120)
                .background(Color.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onChange(of: store.log.count) { _, _ in
                    if let last = store.log.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                Text("график+ ›")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "3DCF8A"))
                    .padding(.bottom, 10)

                TextEditor(text: $draft)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 54, maxHeight: 90)
                    .padding(8)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                Button(action: onRun) {
                    Text("В график")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "5B8CFF"))
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.035))
    }

    private func prefix(_ kind: LogLine.Kind) -> String {
        switch kind {
        case .info: return "··"
        case .ok: return "✓"
        case .error: return "✗"
        case .command: return "›"
        }
    }

    private func color(_ kind: LogLine.Kind) -> Color {
        switch kind {
        case .info: return Color(hex: "94A3B8")
        case .ok: return Color(hex: "3DCF8A")
        case .error: return Color(hex: "E25555")
        case .command: return Color(hex: "5B8CFF")
        }
    }
}

struct ColorBar: View {
    @EnvironmentObject var store: EventStore

    var body: some View {
        HStack(spacing: 8) {
            Text("Цвет события")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Palette.chips, id: \.hex) { chip in
                Button {
                    apply(hex: chip.hex)
                } label: {
                    Circle()
                        .fill(Color(hex: chip.hex))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle().stroke(Color.white.opacity(store.defaultColorHex == chip.hex ? 0.95 : 0.15), lineWidth: store.defaultColorHex == chip.hex ? 2 : 1)
                        )
                }
                .buttonStyle(.plain)
                .help(chip.name)
            }
            ColorPicker("", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 32)
            if let selected = store.selectedEvent {
                Text("выбрано: \(selected.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("для новых строк и выбранного события")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: store.selectedEvent?.colorHex ?? store.defaultColorHex) },
            set: { newColor in
                let hex = hexString(from: newColor)
                apply(hex: hex)
            }
        )
    }

    private func apply(hex: String) {
        store.defaultColorHex = hex
        if var event = store.selectedEvent {
            event.colorHex = hex
            store.update(event)
        }
    }

    private func hexString(from color: Color) -> String {
        let ns = NSColor(color)
        guard let rgb = ns.usingColorSpace(.sRGB) else { return Palette.defaultHex }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }
}

struct Inspector: View {
    @EnvironmentObject var store: EventStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Событие")
                .font(.headline)
            if var event = store.selectedEvent {
                TextField("Название", text: Binding(
                    get: { event.title },
                    set: { event.title = $0; store.update(event) }
                ))
                .textFieldStyle(.roundedBorder)
                DatePicker("Начало", selection: Binding(
                    get: { event.start },
                    set: { event.start = $0; store.update(event) }
                ))
                DatePicker("Конец", selection: Binding(
                    get: { event.end },
                    set: { event.end = $0; store.update(event) }
                ))
                ColorPicker("Цвет", selection: Binding(
                    get: { Color(hex: event.colorHex) },
                    set: { event.colorHex = hexString(from: $0); store.update(event) }
                ))
                Button("Удалить событие", role: .destructive) {
                    store.delete(id: event.id)
                }
            } else {
                Text("Выберите событие на графике или добавьте строку через консоль.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Divider().opacity(0.2)
            Text("Образец")
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                sample("октябрь / неделя 4 / вторник / 09:00 Урок #зелёный")
                sample("21.10.2026 14:00-15:30 Совещание #синий")
                sample("цвет 21.10 14:00 оранжевый")
            }
            Spacer()
        }
        .padding(16)
        .frame(width: 300)
        .background(Color.white.opacity(0.03))
    }

    private func sample(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func hexString(from color: Color) -> String {
        let ns = NSColor(color)
        guard let rgb = ns.usingColorSpace(.sRGB) else { return Palette.defaultHex }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
