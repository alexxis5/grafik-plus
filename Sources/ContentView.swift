import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var store: EventStore
    @State private var mode: CalendarMode = .month
    @State private var draft: String = ""
    @State private var showHelp = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ColorBar()
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            Divider().opacity(0.15)
            HStack(spacing: 0) {
                CalendarPane(mode: mode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider().opacity(0.15)
                Inspector()
            }
            Divider().opacity(0.15)
            ConsolePanel(draft: $draft, onRun: runConsole)
        }
        .background(Color(hex: "0E1116"))
        .onAppear { insertSampleHint() }
        .onReceive(NotificationCenter.default.publisher(for: .importRequested)) { _ in importFile() }
        .onReceive(NotificationCenter.default.publisher(for: .exportICSRequested)) { _ in exportICS() }
        .onReceive(NotificationCenter.default.publisher(for: .exportPDFRequested)) { _ in exportPDF() }
        .sheet(isPresented: $showHelp) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Как вводить расписание").font(.title2.bold())
                Text(ScheduleParser.helpText)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                Button("Закрыть") { showHelp = false }
            }
            .padding(24)
            .frame(width: 640, height: 420)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: "5B8CFF"))
                Text("График Плюс")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }

            Picker("", selection: $mode) {
                ForEach(CalendarMode.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)

            Spacer()

            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)

            Text(AppCalendar.monthTitle(store.focusedDay))
                .font(.system(size: 16, weight: .semibold))
                .frame(minWidth: 180)

            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)

            Button("Сегодня") { store.focusedDay = Date() }
                .buttonStyle(.bordered)

            Menu("Файл") {
                Button("Импортировать .ics / .txt…") { importFile() }
                Button("Экспорт в календарь (.ics)…") { exportICS() }
                Button("Открыть в Календаре macOS") { openInCalendar() }
                Button("Экспорт в PDF…") { exportPDF() }
            }
            Button {
                showHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Справка по формату")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.25))
    }

    private func shiftMonth(_ delta: Int) {
        if let next = AppCalendar.ru.date(byAdding: .month, value: delta, to: store.focusedDay) {
            store.focusedDay = next
        }
    }

    private func insertSampleHint() {
        if draft.isEmpty {
            draft = """
            октябрь / неделя 4 / вторник / 09:00 Урок немецкого #зелёный
            21.10.2026 14:00-15:30 Совещание с командой #синий
            """
        }
    }

    private func runConsole() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.appendLog(LogLine(kind: .command, text: text.replacingOccurrences(of: "\n", with: " · ")))
        for outcome in ScheduleParser.parseBlock(text, store: store) {
            apply(outcome)
        }
        draft = ""
    }

    private func apply(_ outcome: ParseOutcome) {
        switch outcome {
        case .empty:
            break
        case .help:
            showHelp = true
            store.appendLog(LogLine(kind: .info, text: "Открыл справку по формату."))
        case .cleared:
            store.clearAll()
            store.appendLog(LogLine(kind: .ok, text: "График очищен."))
        case .event(let event):
            store.add(event)
            store.appendLog(LogLine(
                kind: .ok,
                text: "Добавлено: \(event.title) · \(AppCalendar.dayTitle(event.start)) \(AppCalendar.time(event.start))–\(AppCalendar.time(event.end))"
            ))
        case .deleted(let items):
            items.forEach { store.delete(id: $0.id) }
            store.appendLog(LogLine(kind: .ok, text: "Удалено: \(items.map(\.title).joined(separator: ", "))"))
        case .recolored(let items, let hex):
            for var item in items {
                item.colorHex = hex
                store.update(item)
            }
            store.defaultColorHex = hex
            store.appendLog(LogLine(kind: .ok, text: "Цвет обновлён у \(items.count) событ."))
        case .message(let text):
            store.appendLog(LogLine(kind: .info, text: text))
        case .error(let text):
            store.appendLog(LogLine(kind: .error, text: text))
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.calendarEvent, .plainText, .commaSeparatedText, UTType(filenameExtension: "ics") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Импорт расписания из ICS или текстового файла"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            if url.pathExtension.lowercased() == "ics" {
                let imported = ExportService.parseICS(text)
                imported.forEach { store.add($0) }
                store.appendLog(LogLine(kind: .ok, text: "Импортировано из календаря: \(imported.count)"))
            } else {
                store.appendLog(LogLine(kind: .command, text: "импорт \(url.lastPathComponent)"))
                for outcome in ScheduleParser.parseBlock(text, store: store) {
                    apply(outcome)
                }
            }
        } catch {
            store.appendLog(LogLine(kind: .error, text: "Импорт не удался: \(error.localizedDescription)"))
        }
    }

    private func exportICS() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ics") ?? .data]
        panel.nameFieldStringValue = "grafik-plus.ics"
        panel.title = "Экспорт в календарь"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ExportService.ics(from: store.events).write(to: url, atomically: true, encoding: .utf8)
            store.appendLog(LogLine(kind: .ok, text: "ICS сохранён: \(url.lastPathComponent)"))
        } catch {
            store.appendLog(LogLine(kind: .error, text: error.localizedDescription))
        }
    }

    private func openInCalendar() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("grafik-plus.ics")
        do {
            try ExportService.ics(from: store.events).write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(url)
            store.appendLog(LogLine(kind: .ok, text: "Файл открыт в Календаре macOS."))
        } catch {
            store.appendLog(LogLine(kind: .error, text: error.localizedDescription))
        }
    }

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "График \(AppCalendar.monthTitle(store.focusedDay)).pdf"
        panel.title = "Экспорт в PDF"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ExportService.writePDF(events: store.events, month: store.focusedDay, to: url)
            store.appendLog(LogLine(kind: .ok, text: "PDF сохранён: \(url.lastPathComponent)"))
            NSWorkspace.shared.open(url)
        } catch {
            store.appendLog(LogLine(kind: .error, text: error.localizedDescription))
        }
    }
}
