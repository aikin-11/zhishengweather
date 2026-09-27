import SwiftUI

private enum TerminalStyle {
    static let background = Color(red: 0.025, green: 0.04, blue: 0.045)
    static let panel = Color(red: 0.055, green: 0.08, blue: 0.08)
    static let mint = Color(red: 0.30, green: 0.94, blue: 0.72)
    static let muted = Color(red: 0.48, green: 0.61, blue: 0.58)
    static let line = Color(red: 0.16, green: 0.25, blue: 0.23)
}

struct WeatherHomeView: View {
    @ObservedObject var model: WeatherViewModel
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    search
                    if let error = model.error { Text(error).font(.footnote).foregroundStyle(.orange) }
                    if let data = model.weather {
                        current(data.current)
                        telemetry(data.current)
                        hourly(data.hourly)
                        daily(data.daily)
                        air
                        attribution
                    } else if model.isLoading {
                        ProgressView("正在接收天气信号…").tint(TerminalStyle.mint).frame(maxWidth: .infinity).padding(50)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .background(TerminalStyle.background.ignoresSafeArea())
            .refreshable { await model.refresh() }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(TerminalStyle.mint)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("枳生天气").font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(TerminalStyle.mint)
                Text("ATMOSPHERIC TELEMETRY").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.4).foregroundStyle(TerminalStyle.muted)
            }
            Spacer()
            Button { Task { await model.refresh() } } label: {
                Image(systemName: model.isLoading ? "arrow.trianglehead.2.clockwise.rotate.90" : "arrow.clockwise")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(TerminalStyle.mint).padding(11)
                    .background(TerminalStyle.panel, in: Circle()).overlay(Circle().stroke(TerminalStyle.line))
            }
            .accessibilityLabel("刷新天气")
        }
    }

    private var search: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "location.fill").foregroundStyle(TerminalStyle.mint).font(.caption)
                TextField("搜索城市", text: $searchText)
                    .font(.system(size: 14, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .onChange(of: searchText) { value in Task { await model.search(value) } }
                Text(model.city.components(separatedBy: " · ").first ?? model.city)
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(TerminalStyle.muted).lineLimit(1)
            }
            .padding(13).background(TerminalStyle.panel)
            if !model.matches.isEmpty {
                ForEach(model.matches) { result in
                    Button { model.select(result); searchText = "" } label: {
                        HStack { Text(result.displayName); Spacer(); Image(systemName: "arrow.up.left") }
                            .font(.system(size: 13, design: .monospaced)).foregroundStyle(.white.opacity(0.85)).padding(12)
                    }.buttonStyle(.plain)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(TerminalStyle.line))
    }

    private func current(_ weather: CurrentWeather?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("LIVE CONDITIONS", systemImage: "dot.radiowaves.left.and.right")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(TerminalStyle.muted)
                Spacer(); Circle().fill(TerminalStyle.mint).frame(width: 6, height: 6)
            }
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(weather?.temperature2m.map { "\(Int($0.rounded()))°" } ?? "--°")
                        .font(.system(size: 82, weight: .light, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                    Text(WeatherCode.label(weather?.weatherCode)).font(.system(size: 16, weight: .medium)).foregroundStyle(TerminalStyle.mint)
                    if let feels = weather?.apparentTemperature { Text("体感 \(Int(feels.rounded()))°").font(.system(size: 12, design: .monospaced)).foregroundStyle(TerminalStyle.muted) }
                }
                Spacer(minLength: 0)
                Image(systemName: WeatherCode.symbol(weather?.weatherCode))
                    .symbolRenderingMode(.hierarchical).font(.system(size: 54, weight: .ultraLight)).foregroundStyle(TerminalStyle.mint)
                    .frame(width: 94, height: 94).background(TerminalStyle.mint.opacity(0.07), in: Circle())
            }
            Rectangle().fill(TerminalStyle.line).frame(height: 1)
            Text(Date.now.formatted(date: .complete, time: .shortened).uppercased())
                .font(.system(size: 9, design: .monospaced)).tracking(1).foregroundStyle(TerminalStyle.muted)
        }
        .padding(17).background(TerminalStyle.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(TerminalStyle.line))
    }

    private func telemetry(_ weather: CurrentWeather?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("遥测数据", detail: "SENSOR ARRAY")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 1) {
                metric("湿度", value(weather?.relativeHumidity2m, suffix: "%"), symbol: "humidity.fill")
                metric("风速", value(weather?.windSpeed10m, suffix: " km/h"), symbol: "wind")
                metric("气压", value(weather?.surfacePressure, suffix: " hPa"), symbol: "gauge.with.needle")
                metric("空气指数", model.air?.current?.usAqi.map(String.init) ?? "--", symbol: "aqi.medium")
            }
            .background(TerminalStyle.line, in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func hourly(_ hourly: HourlyWeather?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("逐时预报", detail: "NEXT 24 HOURS")
            if let times = hourly?.time, let temps = hourly?.temperature2m {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 17) {
                        ForEach(Array(times.prefix(24).enumerated()), id: \.offset) { index, time in
                            VStack(spacing: 8) {
                                Text(index == 0 ? "现在" : String(time.suffix(5))).font(.system(size: 10, design: .monospaced)).foregroundStyle(TerminalStyle.muted)
                                Image(systemName: WeatherCode.symbol(hourly?.weatherCode?.element(at: index))).font(.system(size: 16)).foregroundStyle(TerminalStyle.mint)
                                Text(temps.element(at: index).map { "\(Int($0.rounded()))°" } ?? "--°").font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundStyle(.white)
                                if let chance = hourly?.precipitationProbability?.element(at: index), chance > 0 {
                                    Text("\(chance)%").font(.system(size: 9, design: .monospaced)).foregroundStyle(.cyan)
                                } else { Text(" ").font(.system(size: 9)) }
                            }.frame(width: 48)
                        }
                    }.padding(14)
                }.background(TerminalStyle.panel, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(TerminalStyle.line))
            }
        }
    }

    private func daily(_ daily: DailyWeather?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("未来七日", detail: "7-DAY OUTLOOK")
            VStack(spacing: 0) {
                ForEach(Array((daily?.time ?? []).prefix(7).enumerated()), id: \.offset) { index, day in
                    HStack(spacing: 10) {
                        Text(index == 0 ? "今天" : String(day.suffix(5))).font(.system(size: 11, design: .monospaced)).foregroundStyle(TerminalStyle.muted).frame(width: 54, alignment: .leading)
                        Image(systemName: WeatherCode.symbol(daily?.weatherCode?.element(at: index))).foregroundStyle(TerminalStyle.mint).frame(width: 22)
                        Text(WeatherCode.label(daily?.weatherCode?.element(at: index))).font(.system(size: 11)).foregroundStyle(.white.opacity(0.8)).frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(daily?.temperature2mMin?.element(at: index).map { Int($0.rounded()) } ?? 0)°")
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(TerminalStyle.muted)
                        Capsule().fill(TerminalStyle.mint.opacity(0.18)).frame(width: 36, height: 3)
                        Text("\(daily?.temperature2mMax?.element(at: index).map { Int($0.rounded()) } ?? 0)°")
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.white)
                    }.padding(.vertical, 11).padding(.horizontal, 12)
                    if index < min((daily?.time?.count ?? 0), 7) - 1 { Rectangle().fill(TerminalStyle.line).frame(height: 1).padding(.leading, 12) }
                }
            }
            .background(TerminalStyle.panel, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(TerminalStyle.line))
        }
    }

    private var air: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("空气质量", detail: "AIR QUALITY")
            HStack {
                metric("US AQI", model.air?.current?.usAqi.map(String.init) ?? "--", symbol: "aqi.medium")
                metric("PM2.5", value(model.air?.current?.pm2_5, suffix: " μg/m³"), symbol: "aqi.low")
                metric("PM10", value(model.air?.current?.pm10, suffix: " μg/m³"), symbol: "aqi.low")
            }
        }
    }

    private var attribution: some View {
        HStack { Text("DATA: OPEN-METEO"); Spacer(); Text("枳生天气 · iOS") }
            .font(.system(size: 9, design: .monospaced)).tracking(0.7).foregroundStyle(TerminalStyle.muted.opacity(0.8))
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            Spacer(); Text(detail).font(.system(size: 9, design: .monospaced)).tracking(0.8).foregroundStyle(TerminalStyle.muted)
        }
    }

    private func metric(_ title: String, _ value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) { Image(systemName: symbol); Text(title) }.font(.system(size: 10)).foregroundStyle(TerminalStyle.muted)
            Text(value).font(.system(size: 16, weight: .medium, design: .monospaced)).foregroundStyle(TerminalStyle.mint).lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12).background(TerminalStyle.panel)
    }

    private func value(_ number: Double?, suffix: String) -> String {
        number.map { "\(Int($0.rounded()))\(suffix)" } ?? "--"
    }
    private func value(_ number: Int?, suffix: String) -> String { number.map { "\($0)\(suffix)" } ?? "--" }
}

private extension Array {
    func element(at index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
