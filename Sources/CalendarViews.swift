import SwiftUI

enum CalendarMode: String, CaseIterable {
    case month = "Месяц"
    case week = "Неделя"
    case day = "День"
}

struct CalendarPane: View {
    @EnvironmentObject var store: EventStore
    let mode: CalendarMode

    var body: some View {
        Group {
            switch mode {
            case .month: MonthGrid()
            case .week: WeekGrid()
            case .day: DayTimeline()
            }
        }
    }
}

struct MonthGrid: View {
    @EnvironmentObject var store: EventStore
    private let cal = AppCalendar.ru

    var body: some View {
        let monthStart = AppCalendar.startOfMonth(store.focusedDay)
        let daysInMonth = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let firstWeekday = cal.component(.weekday, from: monthStart)
        let offset = (firstWeekday + 5) % 7
        let total = offset + daysInMonth
        let rows = Int(ceil(Double(total) / 7.0))

        VStack(spacing: 8) {
            HStack {
                ForEach(AppCalendar.weekdayShort, id: \.self) { name in
                    Text(name.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(0..<(rows * 7), id: \.self) { idx in
                    let day = idx - offset + 1
                    if day >= 1 && day <= daysInMonth, let date = date(monthStart, day: day) {
                        DayCell(date: date, events: store.events(on: date))
                    } else {
                        Color.clear.frame(minHeight: 92)
                    }
                }
            }
        }
        .padding(16)
    }

    private func date(_ start: Date, day: Int) -> Date? {
        cal.date(byAdding: .day, value: day - 1, to: start)
    }
}

struct DayCell: View {
    @EnvironmentObject var store: EventStore
    let date: Date
    let events: [ScheduleEvent]
    private let cal = AppCalendar.ru

    var isToday: Bool { cal.isDateInToday(date) }
    var isFocused: Bool { cal.isDate(date, inSameDayAs: store.focusedDay) }

    var body: some View {
        Button {
            store.focusedDay = date
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(cal.component(.day, from: date))")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(isToday ? Color.black : Color.white)
                        .padding(.horizontal, isToday ? 7 : 0)
                        .padding(.vertical, isToday ? 2 : 0)
                        .background(isToday ? Color(hex: "5B8CFF") : Color.clear)
                        .clipShape(Capsule())
                    Spacer()
                    Text("нед. \(AppCalendar.weekOfMonth(date))")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                ForEach(events.prefix(3)) { event in
                    Text("\(AppCalendar.time(event.start)) \(event.title)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: event.colorHex).opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                if events.count > 3 {
                    Text("+\(events.count - 3)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .background(Color.white.opacity(isFocused ? 0.10 : 0.045))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isFocused ? Color(hex: "5B8CFF").opacity(0.7) : Color.white.opacity(0.05), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct WeekGrid: View {
    @EnvironmentObject var store: EventStore
    private let hours = Array(7..<22)

    var body: some View {
        let start = AppCalendar.startOfWeek(store.focusedDay)
        let days = (0..<7).compactMap { AppCalendar.ru.date(byAdding: .day, value: $0, to: start) }

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 52)
                ForEach(days, id: \.self) { day in
                    VStack(spacing: 2) {
                        Text(AppCalendar.weekdayShort[weekdayIndex(day)].capitalized)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("\(AppCalendar.ru.component(.day, from: day))")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(AppCalendar.ru.isDate(day, inSameDayAs: store.focusedDay) ? Color(hex: "5B8CFF") : .white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture { store.focusedDay = day }
                }
            }
            Divider().opacity(0.2)
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(hours, id: \.self) { hour in
                            Text(String(format: "%02d:00", hour))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 52, height: 56, alignment: .topTrailing)
                                .padding(.trailing, 6)
                        }
                    }
                    ForEach(days, id: \.self) { day in
                        ZStack(alignment: .topLeading) {
                            VStack(spacing: 0) {
                                ForEach(hours, id: \.self) { _ in
                                    Rectangle()
                                        .fill(Color.white.opacity(0.03))
                                        .frame(height: 55)
                                        .overlay(Rectangle().stroke(Color.white.opacity(0.05), lineWidth: 0.5))
                                }
                            }
                            ForEach(store.events(on: day)) { event in
                                weekBlock(event, day: day)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .padding(12)
    }

    private func weekdayIndex(_ date: Date) -> Int {
        (AppCalendar.ru.component(.weekday, from: date) + 5) % 7
    }

    @ViewBuilder
    private func weekBlock(_ event: ScheduleEvent, day: Date) -> some View {
        let startHour = 7.0
        let hour = Double(AppCalendar.ru.component(.hour, from: event.start))
        let minute = Double(AppCalendar.ru.component(.minute, from: event.start))
        let y = ((hour + minute / 60) - startHour) * 56
        let h = max(Double(event.durationMinutes) / 60 * 56, 22)
        Button {
            store.selectedID = event.id
            store.focusedDay = day
        } label: {
            Text("\(AppCalendar.time(event.start))  \(event.title)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(6)
                .frame(maxWidth: .infinity, minHeight: h, alignment: .topLeading)
                .background(Color(hex: event.colorHex).opacity(store.selectedID == event.id ? 1 : 0.88))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .offset(y: max(y, 0))
        .padding(.horizontal, 3)
    }
}

struct DayTimeline: View {
    @EnvironmentObject var store: EventStore
    private let hours = Array(7..<23)

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ScrollView {
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        ForEach(hours, id: \.self) { hour in
                            HStack(alignment: .top, spacing: 12) {
                                Text(String(format: "%02d:00", hour))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 52, alignment: .trailing)
                                Rectangle()
                                    .fill(Color.white.opacity(0.06))
                                    .frame(height: 1)
                                    .padding(.top, 8)
                            }
                            .frame(height: 72)
                        }
                    }
                    ForEach(store.events(on: store.focusedDay)) { event in
                        dayBlock(event)
                    }
                }
                .padding(20)
            }
            EventList(day: store.focusedDay)
                .frame(width: 280)
                .padding(.trailing, 12)
                .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func dayBlock(_ event: ScheduleEvent) -> some View {
        let startHour = 7.0
        let hour = Double(AppCalendar.ru.component(.hour, from: event.start))
        let minute = Double(AppCalendar.ru.component(.minute, from: event.start))
        let y = ((hour + minute / 60) - startHour) * 72
        let h = max(Double(event.durationMinutes) / 60 * 72, 28)
        Button {
            store.selectedID = event.id
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.system(size: 14, weight: .semibold))
                Text("\(AppCalendar.time(event.start)) – \(AppCalendar.time(event.end))")
                    .font(.caption)
                    .opacity(0.9)
            }
            .foregroundStyle(.white)
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: h, alignment: .topLeading)
            .background(Color(hex: event.colorHex))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.leading, 72)
        .offset(y: max(y, 0))
    }
}

struct EventList: View {
    @EnvironmentObject var store: EventStore
    let day: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppCalendar.dayTitle(day).capitalized)
                .font(.headline)
            let items = store.events(on: day)
            if items.isEmpty {
                Text("В этот день событий нет.\nДобавьте строку в консоли.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            ForEach(items) { event in
                Button {
                    store.selectedID = event.id
                } label: {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: event.colorHex))
                            .frame(width: 4, height: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("\(AppCalendar.time(event.start)) – \(AppCalendar.time(event.end))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(store.selectedID == event.id ? Color.white.opacity(0.08) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}
