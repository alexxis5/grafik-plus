import SwiftUI
import AppKit

@main
struct GrafikPlusApp: App {
    @StateObject private var store = EventStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1100, minHeight: 720)
                .onAppear {
                    NSApp.appearance = NSAppearance(named: .darkAqua)
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1280, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("Импортировать файл…") {
                    NotificationCenter.default.post(name: .importRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])
                Button("Экспорт в календарь (.ics)…") {
                    NotificationCenter.default.post(name: .exportICSRequested, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command])
                Button("Экспорт в PDF…") {
                    NotificationCenter.default.post(name: .exportPDFRequested, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command])
            }
        }
    }
}

extension Notification.Name {
    static let importRequested = Notification.Name("grafikplus.import")
    static let exportICSRequested = Notification.Name("grafikplus.exportICS")
    static let exportPDFRequested = Notification.Name("grafikplus.exportPDF")
}
