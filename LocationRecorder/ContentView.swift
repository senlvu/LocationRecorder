import SwiftUI

struct ContentView: View {
    @StateObject private var recorder = LocationRecorder.shared

    var body: some View {
        NavigationView {
            List {
                // 开关
                Section {
                    Toggle(isOn: Binding(
                        get: { recorder.isRunning },
                        set: { recorder.setRunning($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("开启位置记录")
                                .font(.headline)
                            Text(recorder.isRunning
                                 ? "每 30 秒记录一次，切换到后台后继续运行"
                                 : "当前已停止")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(recorder.isRunning ? .green : .gray)
                }

                // 状态提示
                if !recorder.statusMessage.isEmpty {
                    Section {
                        Label(recorder.statusMessage, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                // 统计
                Section("统计") {
                    statRow(icon: "list.number", title: "已记录条数",
                            value: "\(recorder.records.count)")
                    statRow(icon: "clock", title: "最近一次记录",
                            value: recorder.records.last?.timestamp.formatted(date: .abbreviated, time: .standard) ?? "—")
                }

                // 最新位置
                Section("最新位置") {
                    if let loc = recorder.lastLocation {
                        statRow(icon: "location.north", title: "纬度",
                                value: String(format: "%.6f", loc.coordinate.latitude))
                        statRow(icon: "location.east", title: "经度",
                                value: String(format: "%.6f", loc.coordinate.longitude))
                        statRow(icon: "mountain.2", title: "海拔",
                                value: String(format: "%.1f m", loc.altitude))
                        statRow(icon: "scope", title: "水平精度",
                                value: String(format: "±%.1f m", loc.horizontalAccuracy))
                        statRow(icon: "speedometer", title: "速度",
                                value: String(format: "%.1f m/s", max(0, loc.speed)))
                    } else {
                        Text("暂无定位数据")
                            .foregroundStyle(.secondary)
                    }
                }

                // 最近记录
                Section("最近记录（最多显示 20 条）") {
                    let recent = recorder.records.suffix(20).reversed()
                    if recent.isEmpty {
                        Text("暂无记录")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(recent)) { record in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.timestamp.formatted(date: .abbreviated, time: .standard))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.6f, %.6f", record.latitude, record.longitude))
                                    .font(.callout.monospacedDigit())
                            }
                        }
                    }
                }
            }
            .navigationTitle("定位记录器")
            .navigationViewStyle(.stack)
        }
    }

    private func statRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.callout)
    }
}
