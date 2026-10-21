import Foundation
import AppKit

enum ExportService {
    static func ics(from events: [ScheduleEvent]) -> String {
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//График Плюс//RU",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH"
        ]
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd'T'HHmmss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current

        for event in events.sorted(by: { $0.start < $1.start }) {
            lines.append("BEGIN:VEVENT")
            lines.append("UID:\(event.id.uuidString)@grafikplus")
            lines.append("DTSTAMP:\(fmt.string(from: Date()))")
            lines.append("DTSTART:\(fmt.string(from: event.start))")
            lines.append("DTEND:\(fmt.string(from: event.end))")
            lines.append("SUMMARY:\(escapeICS(event.title))")
            if !event.notes.isEmpty {
                lines.append("DESCRIPTION:\(escapeICS(event.notes))")
            }
            lines.append("COLOR:#\(event.colorHex)")
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func parseICS(_ text: String) -> [ScheduleEvent] {
        var events: [ScheduleEvent] = []
        let blocks = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "BEGIN:VEVENT")
        let fmtZ = DateFormatter()
        fmtZ.locale = Locale(identifier: "en_US_POSIX")
        fmtZ.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        fmtZ.timeZone = TimeZone(secondsFromGMT: 0)
        let fmtL = DateFormatter()
        fmtL.locale = Locale(identifier: "en_US_POSIX")
        fmtL.dateFormat = "yyyyMMdd'T'HHmmss"
        fmtL.timeZone = TimeZone.current
        let fmtD = DateFormatter()
        fmtD.locale = Locale(identifier: "en_US_POSIX")
        fmtD.dateFormat = "yyyyMMdd"
        fmtD.timeZone = TimeZone.current

        for block in blocks.dropFirst() {
            let body = block.components(separatedBy: "END:VEVENT").first ?? block
            var title = "Событие"
            var start: Date?
            var end: Date?
            var color = Palette.defaultHex
            var notes = ""
            for rawLine in body.components(separatedBy: "\n") {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("SUMMARY:") {
                    title = unescapeICS(String(line.dropFirst(8)))
                } else if line.hasPrefix("DESCRIPTION:") {
                    notes = unescapeICS(String(line.dropFirst(12)))
                } else if line.hasPrefix("DTSTART") {
                    start = parseICSDate(line, fmtZ: fmtZ, fmtL: fmtL, fmtD: fmtD)
                } else if line.hasPrefix("DTEND") {
                    end = parseICSDate(line, fmtZ: fmtZ, fmtL: fmtL, fmtD: fmtD)
                } else if line.uppercased().hasPrefix("COLOR:") {
                    color = Palette.resolve(String(line.split(separator: ":").last ?? "")) ?? color
                }
            }
            if let start {
                events.append(ScheduleEvent(
                    title: title,
                    start: start,
                    end: end ?? start.addingTimeInterval(3600),
                    colorHex: color,
                    notes: notes
                ))
            }
        }
        return events
    }

    private static func parseICSDate(_ line: String, fmtZ: DateFormatter, fmtL: DateFormatter, fmtD: DateFormatter) -> Date? {
        let value = String(line.split(separator: ":").last ?? "")
        return fmtZ.date(from: value) ?? fmtL.date(from: value) ?? fmtD.date(from: value)
    }

    private static func escapeICS(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func unescapeICS(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    static func writePDF(events: [ScheduleEvent], month: Date, to url: URL) throws {
        let page = CGRect(x: 0, y: 0, width: 842, height: 595)
        var mediaBox = page
        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "GrafikPlus", code: 1, userInfo: [NSLocalizedDescriptionKey: "Не удалось создать PDF"])
        }
        ctx.beginPDFPage(nil)
        ctx.setFillColor(NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.14, alpha: 1).cgColor)
        ctx.fill(page)

        let title = "График Плюс — \(AppCalendar.monthTitle(month))"
        drawText(title, in: ctx, rect: CGRect(x: 36, y: 545, width: 770, height: 28), font: NSFont.systemFont(ofSize: 22, weight: .semibold), color: .white)

        let cal = AppCalendar.ru
        let start = AppCalendar.startOfMonth(month)
        let weekdayOfFirst = cal.component(.weekday, from: start)
        // Monday=2 → offset 0
        let offset = (weekdayOfFirst + 5) % 7
        let days = cal.range(of: .day, in: .month, for: start)?.count ?? 30

        let gridX: CGFloat = 36
        let gridY: CGFloat = 48
        let gridW: CGFloat = 770
        let gridH: CGFloat = 480
        let cellW = gridW / 7
        let cellH = gridH / 6

        for (i, name) in AppCalendar.weekdayShort.enumerated() {
            drawText(
                name.uppercased(),
                in: ctx,
                rect: CGRect(x: gridX + CGFloat(i) * cellW, y: gridY + gridH, width: cellW, height: 16),
                font: NSFont.systemFont(ofSize: 10, weight: .medium),
                color: NSColor(white: 0.7, alpha: 1),
                align: .center
            )
        }

        for day in 1...days {
            let idx = offset + day - 1
            let row = 5 - idx / 7
            let col = idx % 7
            let rect = CGRect(x: gridX + CGFloat(col) * cellW + 3, y: gridY + CGFloat(row) * cellH + 3, width: cellW - 6, height: cellH - 6)
            ctx.setFillColor(NSColor(calibratedWhite: 1, alpha: 0.06).cgColor)
            ctx.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.08).cgColor)
            let path = CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
            ctx.addPath(path)
            ctx.drawPath(using: .fillStroke)

            drawText(
                "\(day)",
                in: ctx,
                rect: CGRect(x: rect.minX + 8, y: rect.maxY - 20, width: 40, height: 16),
                font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                color: .white
            )

            var comps = cal.dateComponents([.year, .month], from: start)
            comps.day = day
            guard let date = cal.date(from: comps) else { continue }
            let dayEvents = events.filter { cal.isDate($0.start, inSameDayAs: date) }.sorted { $0.start < $1.start }
            var y = rect.maxY - 36
            for ev in dayEvents.prefix(4) {
                ctx.setFillColor(NSColor(hex: ev.colorHex).cgColor)
                let pill = CGRect(x: rect.minX + 6, y: y, width: rect.width - 12, height: 14)
                ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 4, cornerHeight: 4, transform: nil))
                ctx.fillPath()
                drawText(
                    "\(AppCalendar.time(ev.start)) \(ev.title)",
                    in: ctx,
                    rect: pill.insetBy(dx: 4, dy: 0),
                    font: NSFont.systemFont(ofSize: 8, weight: .medium),
                    color: .white
                )
                y -= 16
            }
            if dayEvents.count > 4 {
                drawText("+\(dayEvents.count - 4)", in: ctx, rect: CGRect(x: rect.minX + 8, y: y, width: 40, height: 12), font: NSFont.systemFont(ofSize: 8), color: NSColor(white: 0.8, alpha: 1))
            }
        }

        ctx.endPDFPage()
        ctx.closePDF()
    }

    private static func drawText(
        _ string: String,
        in ctx: CGContext,
        rect: CGRect,
        font: NSFont,
        color: NSColor,
        align: NSTextAlignment = .left
    ) {
        let para = NSMutableParagraphStyle()
        para.alignment = align
        para.lineBreakMode = .byTruncatingTail
        let attr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: para
        ]
        ctx.saveGState()
        ctx.translateBy(x: 0, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        NSAttributedString(string: string, attributes: attr).draw(in: CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }
}
