import Foundation
import SwiftUI
import Combine
import AppKit

struct ScheduleEvent: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var start: Date
    var end: Date
    var colorHex: String
    var notes: String

    init(
        id: UUID = UUID(),
        title: String,
        start: Date,
        end: Date,
        colorHex: String,
        notes: String = ""
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.colorHex = colorHex
        self.notes = notes
    }

    var durationMinutes: Int {
        max(Int(end.timeIntervalSince(start) / 60), 15)
    }
}

enum Palette {
    static let named: [String: String] = [
        "красный": "E25555",
        "алый": "E25555",
        "синий": "5B8CFF",
        "голубой": "5B8CFF",
        "зелёный": "3DCF8A",
        "зеленый": "3DCF8A",
        "жёлтый": "F5C542",
        "желтый": "F5C542",
        "оранжевый": "FF8A4C",
        "фиолетовый": "A78BFA",
        "сиреневый": "A78BFA",
        "розовый": "F472B6",
        "бирюзовый": "2DD4BF",
        "мятный": "2DD4BF",
        "серый": "94A3B8",
        "белый": "E8EEF7"
    ]

    static let chips: [(name: String, hex: String)] = [
        ("синий", "5B8CFF"),
        ("зелёный", "3DCF8A"),
        ("оранжевый", "FF8A4C"),
        ("красный", "E25555"),
        ("фиолетовый", "A78BFA"),
        ("розовый", "F472B6"),
        ("бирюзовый", "2DD4BF"),
        ("жёлтый", "F5C542")
    ]

    static let defaultHex = "5B8CFF"

    static func resolve(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .lowercased()
        if let mapped = named[trimmed] { return mapped }
        let hex = trimmed.uppercased()
        if hex.range(of: "^[0-9A-F]{6}$", options: .regularExpression) != nil {
            return hex
        }
        return nil
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (91, 140, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}

extension NSColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r = CGFloat((int >> 16) & 0xFF) / 255
        let g = CGFloat((int >> 8) & 0xFF) / 255
        let b = CGFloat(int & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

final class EventStore: ObservableObject {
    @Published var events: [ScheduleEvent] = []
    @Published var selectedID: UUID?
    @Published var focusedDay: Date = Date()
    @Published var defaultColorHex: String = Palette.defaultHex
    @Published var log: [LogLine] = [
        LogLine(kind: .info, text: "График Плюс готов. Введите строки расписания по образцу и нажмите ⌘↩.")
    ]

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "ru_RU")
        cal.firstWeekday = 2
        return cal
    }()

    private var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("GrafikPlus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("events.json")
    }

    init() {
        load()
        if events.isEmpty {
            seedWelcome()
        }
    }

    var selectedEvent: ScheduleEvent? {
        events.first { $0.id == selectedID }
    }

    func events(on day: Date) -> [ScheduleEvent] {
        events
            .filter { calendar.isDate($0.start, inSameDayAs: day) }
            .sorted { $0.start < $1.start }
    }

    func events(inMonthOf date: Date) -> [ScheduleEvent] {
        events.filter { calendar.isDate($0.start, equalTo: date, toGranularity: .month) }
            .sorted { $0.start < $1.start }
    }

    func add(_ event: ScheduleEvent) {
        events.append(event)
        events.sort { $0.start < $1.start }
        selectedID = event.id
        focusedDay = event.start
        persist()
    }

    func update(_ event: ScheduleEvent) {
        guard let idx = events.firstIndex(where: { $0.id == event.id }) else { return }
        events[idx] = event
        persist()
    }

    func delete(id: UUID) {
        events.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
        persist()
    }

    func clearAll() {
        events.removeAll()
        selectedID = nil
        persist()
    }

    func appendLog(_ line: LogLine) {
        log.append(line)
        if log.count > 400 {
            log.removeFirst(log.count - 400)
        }
    }

    func persist() {
        do {
            let data = try JSONEncoder().encode(events)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            appendLog(LogLine(kind: .error, text: "Не удалось сохранить: \(error.localizedDescription)"))
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        events = (try? JSONDecoder().decode([ScheduleEvent].self, from: data)) ?? []
        events.sort { $0.start < $1.start }
    }

    private func seedWelcome() {
        appendLog(LogLine(kind: .info, text: "Пока пусто — можно вставить пример из панели «Образец»."))
    }
}

struct LogLine: Identifiable, Equatable {
    enum Kind { case info, ok, error, command }
    let id = UUID()
    let kind: Kind
    let text: String
}

enum AppCalendar {
    static var ru: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "ru_RU")
        cal.firstWeekday = 2
        return cal
    }

    static let monthSymbols = [
        "январь", "февраль", "март", "апрель", "май", "июнь",
        "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"
    ]

    static let weekdayShort = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]

    static func weekOfMonth(_ date: Date) -> Int {
        let day = ru.component(.day, from: date)
        return (day - 1) / 7 + 1
    }

    static func startOfMonth(_ date: Date) -> Date {
        ru.date(from: ru.dateComponents([.year, .month], from: date)) ?? date
    }

    static func startOfWeek(_ date: Date) -> Date {
        ru.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    static func startOfDay(_ date: Date) -> Date {
        ru.startOfDay(for: date)
    }

    static func monthTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: date).capitalized
    }

    static func dayTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EEEE, d MMMM"
        return f.string(from: date)
    }

    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
