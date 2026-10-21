import Foundation

enum ParseOutcome {
    case event(ScheduleEvent)
    case deleted([ScheduleEvent])
    case recolored([ScheduleEvent], String)
    case cleared
    case help
    case message(String)
    case error(String)
    case empty
}

enum ScheduleParser {
    static let helpText = """
    Формат строк (месяц → неделя → день → время):
      октябрь / неделя 4 / вторник / 09:00 Урок немецкого #зелёный
      2026 октябрь неделя 3 пн 10:00-11:00 Планерка #синий
      21.10.2026 14:00-15:30 Совещание с командой #оранжевый
      2026-10-21 18:00 Ужин

    Если конец не указан, событие длится 1 час.
    Цвет: #синий #зелёный #красный #оранжевый #фиолетовый #розовый #бирюзовый #жёлтый или #5B8CFF

    Команды:
      удалить 21.10 14:00     — снять событие
      цвет 21.10 14:00 розовый
      очистить
      помощь
    """

    static func parseBlock(_ text: String, store: EventStore) -> [ParseOutcome] {
        text.split(whereSeparator: \.isNewline)
            .map { parseLine(String($0), store: store) }
    }

    static func parseLine(_ raw: String, store: EventStore) -> ParseOutcome {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { return .empty }

        let lower = line.lowercased()
        if ["помощь", "help", "?"].contains(lower) { return .help }
        if ["очистить", "clear"].contains(lower) { return .cleared }

        if lower.hasPrefix("удалить") || lower.hasPrefix("delete") {
            let query = line.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
            let matches = find(query: query, in: store.events)
            if matches.isEmpty { return .error("Ничего не найдено для удаления: «\(query)»") }
            return .deleted(matches)
        }

        if lower.hasPrefix("цвет") || lower.hasPrefix("color") {
            return parseColorCommand(line, store: store)
        }

        if let event = parseEvent(line, defaultColor: store.defaultColorHex) {
            return .event(event)
        }

        return .error("Не понял строку. Образец: 21.10.2026 14:00 Название #синий")
    }

    private static func parseColorCommand(_ line: String, store: EventStore) -> ParseOutcome {
        var rest = line.split(separator: " ").dropFirst().map(String.init)
        guard rest.count >= 2 else {
            return .error("Формат: цвет 21.10 14:00 розовый")
        }
        let colorToken = rest.removeLast()
        guard let hex = Palette.resolve(colorToken) else {
            return .error("Неизвестный цвет «\(colorToken)»")
        }
        let query = rest.joined(separator: " ")
        let matches = find(query: query, in: store.events)
        if matches.isEmpty { return .error("Событие не найдено: «\(query)»") }
        return .recolored(matches, hex)
    }

    static func parseEvent(_ line: String, defaultColor: String, now: Date = Date()) -> ScheduleEvent? {
        let (titleAndTime, color) = extractColor(from: line)
        let hex = color.flatMap(Palette.resolve) ?? defaultColor
        let cal = AppCalendar.ru
        let yearNow = cal.component(.year, from: now)

        if let parsed = parseDotted(titleAndTime, yearNow: yearNow, calendar: cal, color: hex) {
            return parsed
        }
        if let parsed = parseISO(titleAndTime, calendar: cal, color: hex) {
            return parsed
        }
        if let parsed = parseHierarchy(titleAndTime, yearNow: yearNow, calendar: cal, color: hex) {
            return parsed
        }
        return nil
    }

    private static func extractColor(from line: String) -> (String, String?) {
        guard let hash = line.lastIndex(of: "#") else { return (line, nil) }
        let color = String(line[line.index(after: hash)...]).trimmingCharacters(in: .whitespaces)
        let head = String(line[..<hash]).trimmingCharacters(in: .whitespaces)
        if color.isEmpty { return (line, nil) }
        return (head, color)
    }

    private static func parseDotted(_ line: String, yearNow: Int, calendar: Calendar, color: String) -> ScheduleEvent? {
        // 21.10.2026 14:00-15:30 Title   or  21.10 14:00 Title
        let pattern = #"^(\d{1,2})\.(\d{1,2})(?:\.(\d{2,4}))?\s+(\d{1,2}:\d{2})(?:\s*[-–]\s*(\d{1,2}:\d{2}))?\s+(.+)$"#
        guard let m = match(pattern, line) else { return nil }
        let day = Int(m[1]) ?? 1
        let month = Int(m[2]) ?? 1
        var year = m[3].isEmpty ? yearNow : (Int(m[3]) ?? yearNow)
        if year < 100 { year += 2000 }
        guard let startClock = parseClock(m[4]) else { return nil }
        let endClock = m[5].isEmpty ? nil : parseClock(m[5])
        let title = m[6].trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return makeEvent(year: year, month: month, day: day, start: startClock, end: endClock, title: title, color: color, calendar: calendar)
    }

    private static func parseISO(_ line: String, calendar: Calendar, color: String) -> ScheduleEvent? {
        let pattern = #"^(\d{4})-(\d{2})-(\d{2})\s+(\d{1,2}:\d{2})(?:\s*[-–]\s*(\d{1,2}:\d{2}))?\s+(.+)$"#
        guard let m = match(pattern, line) else { return nil }
        let year = Int(m[1]) ?? 2026
        let month = Int(m[2]) ?? 1
        let day = Int(m[3]) ?? 1
        guard let startClock = parseClock(m[4]) else { return nil }
        let endClock = m[5].isEmpty ? nil : parseClock(m[5])
        let title = m[6].trimmingCharacters(in: .whitespaces)
        return makeEvent(year: year, month: month, day: day, start: startClock, end: endClock, title: title, color: color, calendar: calendar)
    }

    private static func parseHierarchy(_ line: String, yearNow: Int, calendar: Calendar, color: String) -> ScheduleEvent? {
        var s = line.lowercased()
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: ",", with: " ")
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        s = s.trimmingCharacters(in: .whitespaces)

        var year = yearNow
        if let yMatch = match(#"^(\d{4})\s+(.*)$"#, s) {
            year = Int(yMatch[1]) ?? yearNow
            s = yMatch[2]
        }

        guard let month = detectMonth(in: s) else { return nil }
        s = stripMonth(s)

        var week = 0
        if let wMatch = match(#"(?:неделя|нед\.?)\s*(\d)"#, s) {
            week = Int(wMatch[1]) ?? 0
            s = s.replacingOccurrences(of: wMatch[0], with: " ")
        }

        guard let weekday = detectWeekday(in: s) else { return nil }
        s = stripWeekday(s)
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        s = s.trimmingCharacters(in: .whitespaces)

        guard let tMatch = match(#"^(\d{1,2}:\d{2})(?:\s*[-–]\s*(\d{1,2}:\d{2}))?\s+(.+)$"#, s) else { return nil }
        guard let startClock = parseClock(tMatch[1]) else { return nil }
        let endClock = tMatch[2].isEmpty ? nil : parseClock(tMatch[2])
        let title = tMatch[3].trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }

        guard let day = resolveDay(year: year, month: month, weekOfMonth: week, weekday: weekday, calendar: calendar) else {
            return nil
        }
        return makeEvent(year: year, month: month, day: day, start: startClock, end: endClock, title: title, color: color, calendar: calendar)
    }

    private static func resolveDay(year: Int, month: Int, weekOfMonth: Int, weekday: Int, calendar: Calendar) -> Int? {
        // weekday: 1=Sunday ... 7=Saturday (Calendar)
        var candidates: [Int] = []
        for day in 1...31 {
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = day
            guard let date = calendar.date(from: comps), calendar.component(.month, from: date) == month else { break }
            if calendar.component(.weekday, from: date) == weekday {
                candidates.append(day)
            }
        }
        if weekOfMonth >= 1, weekOfMonth <= candidates.count {
            return candidates[weekOfMonth - 1]
        }
        if weekOfMonth >= 1 {
            // week-of-month by date ranges 1-7, 8-14...
            for day in candidates where AppCalendar.weekOfMonth(calendar.date(from: DateComponents(year: year, month: month, day: day))!) == weekOfMonth {
                return day
            }
        }
        return candidates.first
    }

    private static func makeEvent(
        year: Int, month: Int, day: Int,
        start: (Int, Int), end: (Int, Int)?,
        title: String, color: String, calendar: Calendar
    ) -> ScheduleEvent? {
        var sc = DateComponents()
        sc.year = year; sc.month = month; sc.day = day
        sc.hour = start.0; sc.minute = start.1
        guard let startDate = calendar.date(from: sc) else { return nil }
        let endDate: Date
        if let end {
            var ec = sc
            ec.hour = end.0; ec.minute = end.1
            endDate = calendar.date(from: ec) ?? startDate.addingTimeInterval(3600)
        } else {
            endDate = startDate.addingTimeInterval(3600)
        }
        return ScheduleEvent(title: title, start: startDate, end: max(endDate, startDate.addingTimeInterval(15 * 60)), colorHex: color)
    }

    private static func parseClock(_ raw: String) -> (Int, Int)? {
        let parts = raw.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0...23).contains(h), (0...59).contains(m) else {
            return nil
        }
        return (h, m)
    }

    private static let monthMap: [(Int, [String])] = [
        (1, ["январь", "января", "янв"]),
        (2, ["февраль", "февраля", "фев"]),
        (3, ["март", "марта", "мар"]),
        (4, ["апрель", "апреля", "апр"]),
        (5, ["май", "мая"]),
        (6, ["июнь", "июня", "июн"]),
        (7, ["июль", "июля", "июл"]),
        (8, ["август", "августа", "авг"]),
        (9, ["сентябрь", "сентября", "сен"]),
        (10, ["октябрь", "октября", "окт"]),
        (11, ["ноябрь", "ноября", "ноя"]),
        (12, ["декабрь", "декабря", "дек"])
    ]

    private static func detectMonth(in s: String) -> Int? {
        for (num, names) in monthMap {
            for name in names where s.contains(name) { return num }
        }
        return nil
    }

    private static func stripMonth(_ s: String) -> String {
        var out = s
        for (_, names) in monthMap {
            for name in names { out = out.replacingOccurrences(of: name, with: " ") }
        }
        return out
    }

    // Calendar weekday: 1 Sunday
    private static let weekdays: [(Int, [String])] = [
        (2, ["понедельник", "пн"]),
        (3, ["вторник", "вт"]),
        (4, ["среда", "среду", "ср"]),
        (5, ["четверг", "чт"]),
        (6, ["пятница", "пятницу", "пт"]),
        (7, ["суббота", "субботу", "сб"]),
        (1, ["воскресенье", "вс"])
    ]

    private static func detectWeekday(in s: String) -> Int? {
        let tokens = s.split(separator: " ").map(String.init)
        for (num, names) in weekdays {
            for name in names {
                if tokens.contains(name) || s.contains(" " + name + " ") || s.hasPrefix(name + " ") {
                    return num
                }
            }
        }
        return nil
    }

    private static func stripWeekday(_ s: String) -> String {
        var out = " " + s + " "
        for (_, names) in weekdays {
            for name in names.sorted(by: { $0.count > $1.count }) {
                out = out.replacingOccurrences(of: " " + name + " ", with: " ")
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    private static func match(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, range: range) else { return nil }
        var parts: [String] = []
        for i in 0..<m.numberOfRanges {
            if let r = Range(m.range(at: i), in: text) {
                parts.append(String(text[r]))
            } else {
                parts.append("")
            }
        }
        return parts
    }

    static func find(query: String, in events: [ScheduleEvent]) -> [ScheduleEvent] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return [] }

        if let dotted = parseEvent(q + " _", defaultColor: Palette.defaultHex) {
            return events.filter {
                AppCalendar.ru.isDate($0.start, inSameDayAs: dotted.start)
                    && AppCalendar.ru.component(.hour, from: $0.start) == AppCalendar.ru.component(.hour, from: dotted.start)
                    && AppCalendar.ru.component(.minute, from: $0.start) == AppCalendar.ru.component(.minute, from: dotted.start)
            }
        }

        let timePattern = #"(\d{1,2})\.(\d{1,2})(?:\.(\d{2,4}))?\s+(\d{1,2}:\d{2})"#
        if let m = match(timePattern, q), let clock = parseClock(m[4]) {
            let day = Int(m[1]) ?? 0
            let month = Int(m[2]) ?? 0
            return events.filter {
                let c = AppCalendar.ru.dateComponents([.day, .month, .hour, .minute], from: $0.start)
                return c.day == day && c.month == month && c.hour == clock.0 && c.minute == clock.1
            }
        }

        return events.filter { $0.title.lowercased().contains(q) }
    }
}
