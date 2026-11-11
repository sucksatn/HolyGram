#if arch(arm64) || arch(x86_64)

// MARK: HolyGram: Home Screen and Lock Screen widget that shows ghost mode and toggles it on tap
import Foundation
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 14.0, iOS 14.0, *)
private struct HolyGramGhostEntry: TimelineEntry {
    let date: Date
    let isOn: Bool
    let until: Date?
}

@available(iOSApplicationExtension 14.0, iOS 14.0, *)
private func holyGramGhostDefaults() -> UserDefaults? {
    guard let bundleId = Bundle.main.bundleIdentifier, let lastDot = bundleId.range(of: ".", options: [.backwards]) else {
        return nil
    }
    return UserDefaults(suiteName: "group.\(String(bundleId[..<lastDot.lowerBound]))")
}

@available(iOSApplicationExtension 14.0, iOS 14.0, *)
private func holyGramGhostState(at date: Date) -> HolyGramGhostEntry {
    let defaults = holyGramGhostDefaults()
    let enabled = defaults?.bool(forKey: "holygram_ghost_on") ?? false
    let untilValue = defaults?.double(forKey: "holygram_ghost_until") ?? 0.0
    let until: Date? = untilValue > 0.0 ? Date(timeIntervalSince1970: untilValue) : nil
    if let until, until <= date {
        return HolyGramGhostEntry(date: date, isOn: false, until: nil)
    }
    return HolyGramGhostEntry(date: date, isOn: enabled, until: until)
}

@available(iOSApplicationExtension 14.0, iOS 14.0, *)
private struct HolyGramGhostProvider: TimelineProvider {
    func placeholder(in context: Context) -> HolyGramGhostEntry {
        return HolyGramGhostEntry(date: Date(), isOn: true, until: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (HolyGramGhostEntry) -> Void) {
        completion(holyGramGhostState(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HolyGramGhostEntry>) -> Void) {
        let now = Date()
        let current = holyGramGhostState(at: now)
        var entries = [current]
        // A timed ghost mode turns itself off: show that without waiting for the app.
        if current.isOn, let until = current.until {
            entries.append(HolyGramGhostEntry(date: until, isOn: false, until: nil))
        }
        completion(Timeline(entries: entries, policy: .never))
    }
}

@available(iOSApplicationExtension 14.0, iOS 14.0, *)
private var holyGramIsRussian: Bool {
    let language = Locale.preferredLanguages.first ?? ""
    return language.hasPrefix("ru") || language.hasPrefix("uk")
}

@available(iOSApplicationExtension 14.0, iOS 14.0, *)
private struct HolyGramGhostWidgetView: View {
    let entry: HolyGramGhostEntry
    @Environment(\.widgetFamily) private var family

    private var stateText: String {
        if entry.isOn {
            if let until = entry.until {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                formatter.dateStyle = .none
                return (holyGramIsRussian ? "Вкл до " : "On until ") + formatter.string(from: until)
            }
            return holyGramIsRussian ? "Включён" : "On"
        }
        return holyGramIsRussian ? "Выключен" : "Off"
    }

    var body: some View {
        content
            .widgetURL(URL(string: "holygram://sg/ghost"))
    }

    private var isCircular: Bool {
        if #available(iOSApplicationExtension 16.0, iOS 16.0, *) {
            return self.family == .accessoryCircular
        }
        return false
    }

    @ViewBuilder
    private var content: some View {
        if self.isCircular {
            ZStack {
                Circle().opacity(entry.isOn ? 0.35 : 0.12)
                Text("👻").font(.system(size: 26.0)).opacity(entry.isOn ? 1.0 : 0.4)
            }
        } else {
            ZStack {
                LinearGradient(gradient: Gradient(colors: entry.isOn
                    ? [Color(red: 0.16, green: 0.08, blue: 0.40), Color(red: 0.40, green: 0.18, blue: 0.70)]
                    : [Color(red: 0.12, green: 0.12, blue: 0.16), Color(red: 0.22, green: 0.22, blue: 0.28)]),
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 6.0) {
                    Text("👻").font(.system(size: 34.0)).opacity(entry.isOn ? 1.0 : 0.45)
                    Spacer(minLength: 0.0)
                    Text(holyGramIsRussian ? "Режим призрака" : "Ghost Mode")
                        .font(.system(size: 14.0, weight: .semibold))
                        .foregroundColor(.white)
                    Text(stateText)
                        .font(.system(size: 13.0))
                        .foregroundColor(entry.isOn ? Color(red: 1.0, green: 0.84, blue: 0.45) : Color.white.opacity(0.6))
                    Text(holyGramIsRussian ? "Нажмите, чтобы переключить" : "Tap to switch")
                        .font(.system(size: 10.0))
                        .foregroundColor(Color.white.opacity(0.5))
                }
                .padding(14.0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }
}

@available(iOSApplicationExtension 14.0, iOS 14.0, *)
struct HolyGramGhostWidget: Widget {
    private let kind: String = "HolyGramGhostWidget"

    private var families: [WidgetFamily] {
        if #available(iOSApplicationExtension 16.0, iOS 16.0, *) {
            return [.systemSmall, .accessoryCircular]
        }
        return [.systemSmall]
    }

    public var body: some WidgetConfiguration {
        if #available(iOSApplicationExtension 15.0, iOS 15.0, *) {
            return StaticConfiguration(kind: kind, provider: HolyGramGhostProvider(), content: { entry in
                HolyGramGhostWidgetView(entry: entry)
            })
            .supportedFamilies(families)
            .configurationDisplayName(holyGramIsRussian ? "Режим призрака" : "Ghost Mode")
            .contentMarginsDisabled()
            .description(holyGramIsRussian ? "Показывает режим призрака HolyGram и переключает его." : "Shows HolyGram ghost mode and switches it.")
        } else {
            return StaticConfiguration(kind: kind, provider: HolyGramGhostProvider(), content: { entry in
                HolyGramGhostWidgetView(entry: entry)
            })
            .supportedFamilies(families)
            .configurationDisplayName(holyGramIsRussian ? "Режим призрака" : "Ghost Mode")
            .description(holyGramIsRussian ? "Показывает режим призрака HolyGram и переключает его." : "Shows HolyGram ghost mode and switches it.")
        }
    }
}

#endif
