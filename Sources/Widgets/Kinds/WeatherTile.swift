import SwiftUI

/// Current conditions for one city: symbol, temperature and either the city
/// name, the condition text, or a short hourly strip.
struct WeatherTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    /// Warm card. The weather tile is the one tinted widget in the shelf, and
    /// the tint is part of how it reads at a glance.
    private static let sample = WeatherNow(temperatureC: 18,
                                           symbolName: "cloud.sun.fill",
                                           condition: "Partly Cloudy")

    private var layout: String { instance.config.string("layout", default: "current") }
    private var fahrenheit: Bool { instance.config.bool("fahrenheit") }

    /// An empty `city` means "wherever I am".
    ///
    /// That is the default now. The shipped default was "Oslo" - the city in
    /// the reference screenshots - and a widget that confidently reports the
    /// weather somewhere the user has never been is worse than one that asks.
    private var city: String {
        let stored = instance.config.string("city").trimmingCharacters(in: .whitespaces)
        if !stored.isEmpty { return stored }
        return LocationService.shared.city ?? ""
    }

    /// What the tile says where the city goes.
    ///
    /// Never blank. This app is an accessory and never becomes frontmost, so
    /// a location prompt can go unseen the same way the automation one does -
    /// and a widget showing "--°" under no name at all gives the user nothing
    /// to act on. Say which of the two states it is in.
    private var placeCaption: String {
        if !city.isEmpty { return city }
        let service = LocationService.shared
        return (service.denied || service.unavailable) ? "Set a city…" : "Locating…"
    }

    /// The library has no live data, so it shows the reference sample.
    private var weather: WeatherNow? {
        context.isPreview ? Self.sample : WeatherService.shared.current
    }

    private var hours: [WeatherHour] {
        context.isPreview ? Self.sampleHours(from: context.now) : WeatherService.shared.hourly
    }

    var body: some View {
        // No tint of its own. Weather ran an orange card while the clock,
        // battery and activity tiles beside it used the neutral recess, which
        // is the inconsistency - the reference shelf tints only what is
        // genuinely coloured (a sticky note's paper), never a readout.
        WidgetSurface {
            if context.position.isVertical {
                column
            } else {
                switch layout {
                case "hourly": hourlyStrip
                case "conditions": wide(caption: weather?.condition ?? "-", size: 12, lines: 2)
                default: wide(caption: placeCaption, size: 14, lines: 1)
                }
            }
        }
        .onAppear { load() }
        .onChange(of: city) { load() }
        // `now` ticks every second; only act when the 15-minute bucket turns
        // over, which is the cadence MET asks for anyway.
        .onChange(of: Int(context.now.timeIntervalSince1970) / 900) {
            guard !context.isPreview else { return }
            Task { await WeatherService.shared.refresh() }
        }
    }

    private func load() {
        guard !context.isPreview else { return }
        // Asked for only because a weather widget is on the shelf, and only
        // when no city has been typed in.
        if instance.config.string("city").trimmingCharacters(in: .whitespaces).isEmpty {
            LocationService.shared.start()
        }
        let city = city
        guard !city.isEmpty else { return }
        Task { await WeatherService.shared.setLocation(city: city) }
    }

    // MARK: - Layouts

    /// Symbol left, temperature and a caption stacked on the right.
    private func wide(caption: String, size: CGFloat, lines: Int) -> some View {
        HStack(spacing: 9) {
            icon(size: 30)
            VStack(alignment: .leading, spacing: 1) {
                temperature(weather?.temperatureC, size: 22)
                Text(caption)
                    .font(WidgetStyle.caption(size))
                    .foregroundStyle(WidgetStyle.secondary)
                    .lineLimit(lines)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    /// The next few hours, each a small symbol over its temperature. Falls
    /// back to the single reading while the forecast is still empty.
    @ViewBuilder private var hourlyStrip: some View {
        if hours.isEmpty {
            wide(caption: placeCaption, size: 14, lines: 1)
        } else {
            HStack(spacing: 0) {
                ForEach(hours.prefix(5), id: \.date) { hour in
                    VStack(spacing: 1) {
                        Text(hour.date.formatted(.dateTime.hour()))
                            .font(WidgetStyle.caption(10))
                            .foregroundStyle(WidgetStyle.secondary)
                            .monospacedDigit()
                        Image(systemName: hour.symbolName)
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 15))
                        Text(degrees(hour.temperatureC))
                            .font(WidgetStyle.label(12))
                            .foregroundStyle(WidgetStyle.primary)
                            .monospacedDigit()
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// 56pt of usable width: everything centred and stacked, the symbol
    /// smaller and the caption down to a single tight line.
    private var column: some View {
        VStack(spacing: 2) {
            icon(size: 21)
            temperature(weather?.temperatureC, size: 17)
            Text(columnCaption)
                .font(WidgetStyle.caption(10))
                .foregroundStyle(WidgetStyle.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    /// What the third line says on a 76pt column.
    ///
    /// Hourly used to fall through to the city, so on a side shelf it was
    /// indistinguishable from Current and the style picker appeared to do
    /// nothing. Eight columns of forecast genuinely do not fit here, so it
    /// shows the part of the forecast that does: the next hour.
    private var columnCaption: String {
        switch layout {
        case "conditions":
            return weather?.condition ?? "-"
        case "hourly":
            guard let next = hours.first else { return city }
            let hour = next.date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)))
            return "\(hour)  \(degrees(next.temperatureC))"
        default:
            return city
        }
    }

    // MARK: - Pieces

    private func icon(size: CGFloat) -> some View {
        Image(systemName: weather?.symbolName ?? "cloud.sun.fill")
            .symbolRenderingMode(.multicolor)
            .font(.system(size: size))
            .frame(height: size)
    }

    /// Big figure with a lighter degree mark riding on top of it. A missing
    /// reading shows dashes - never a zero that could pass for real weather.
    private func temperature(_ celsius: Double?, size: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(celsius.map { String(Int(converted($0).rounded())) } ?? "--")
                .font(WidgetStyle.value(size))
                .foregroundStyle(WidgetStyle.primary)
                .monospacedDigit()
            Text("°")
                .font(WidgetStyle.value(size * 0.7))
                .foregroundStyle(WidgetStyle.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private func degrees(_ celsius: Double) -> String {
        "\(Int(converted(celsius).rounded()))°"
    }

    private func converted(_ celsius: Double) -> Double {
        fahrenheit ? celsius * 9 / 5 + 32 : celsius
    }

    private static func sampleHours(from date: Date) -> [WeatherHour] {
        let temperatures: [Double] = [18, 19, 19, 17, 16]
        let symbols = ["cloud.sun.fill", "sun.max.fill", "cloud.sun.fill", "cloud.rain.fill", "cloud.fill"]
        return zip(temperatures, symbols).enumerated().map { index, pair in
            WeatherHour(date: date.addingTimeInterval(Double(index + 1) * 3600),
                        temperatureC: pair.0,
                        symbolName: pair.1)
        }
    }
}
