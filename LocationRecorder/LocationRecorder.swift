import CoreLocation
import Foundation

// MARK: - 单条定位记录模型
struct LocationRecord: Codable, Identifiable {
    var id = UUID()
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontalAccuracy: Double
    let speed: Double
}

// MARK: - 本地持久化（JSON Lines：每行一条 JSON 记录，存于沙盒 Documents）
final class RecordStore {
    static let shared = RecordStore()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocationRecords.jsonl")
    }

    func append(_ record: LocationRecord) {
        guard let data = try? encoder.encode(record),
              let line = String(data: data, encoding: .utf8) else { return }
        let out = line + "\n"
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(Data(out.utf8))
            try? handle.close()
        } else {
            try? Data(out.utf8).write(to: fileURL, options: .atomic)
        }
    }

    func readAll() -> [LocationRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap {
            try? decoder.decode(LocationRecord.self, from: Data($0.utf8))
        }
    }
}

// MARK: - 定位记录器（核心逻辑）
final class LocationRecorder: NSObject, ObservableObject {
    static let shared = LocationRecorder()

    // MARK: 对外状态（驱动 UI）
    @Published private(set) var isRunning = false
    @Published private(set) var records: [LocationRecord] = []
    @Published private(set) var lastLocation: CLLocation?
    @Published var statusMessage = ""

    // MARK: 私有成员
    private let locationManager = CLLocationManager()
    private var timer: Timer?
    private let recordInterval: TimeInterval = 30      // 记录间隔：30 秒
    private var shouldStartAfterAuthorization = false  // 授权成功后自动开始

    override private init() {
        super.init()
        records = RecordStore.shared.readAll()   // 启动时载入历史记录
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone          // 不按距离过滤，统一由定时器取样
        locationManager.pausesLocationUpdatesAutomatically = false      // 禁止系统自动暂停定位
        locationManager.activityType = .otherNavigation
    }

    // MARK: 开关统一入口
    func setRunning(_ enabled: Bool) {
        enabled ? start() : stop()
    }

    func start() {
        // 权限检查
        switch locationManager.authorizationStatus {
        case .notDetermined:
            shouldStartAfterAuthorization = true
            statusMessage = "正在请求定位权限…"
            locationManager.requestWhenInUseAuthorization()
            return
        case .denied, .restricted:
            statusMessage = "定位权限被拒绝，请到「设置 › 隐私与安全性 › 定位服务」中开启"
            return
        default:
            break
        }

        guard timer == nil else { return }

        // 关键：允许后台定位更新
        // 必须配合 Xcode 中 Background Modes 勾选 Location updates，否则会崩溃
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
        locationManager.startUpdatingLocation()

        // 每 30 秒取样一次；后台定位运行期间 App 保持活跃，Timer 会持续触发
        let timer = Timer(timeInterval: recordInterval,
                          target: self,
                          selector: #selector(recordOnce),
                          userInfo: nil,
                          repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        recordOnce()   // 开启后立即记录一次
        isRunning = true
        statusMessage = ""
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
        shouldStartAfterAuthorization = false
        isRunning = false
    }

    // MARK: 记录逻辑
    @objc private func recordOnce() {
        guard let location = locationManager.location else {
            statusMessage = "尚未获取到有效定位（请在开阔地带稍等片刻）"
            return
        }
        let record = LocationRecord(
            timestamp: Date(),
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            speed: location.speed
        )
        records.append(record)
        RecordStore.shared.append(record)
        lastLocation = location
        statusMessage = ""
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationRecorder: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            // 用户刚授权完毕且此前打开了开关 → 自动开始记录
            if shouldStartAfterAuthorization {
                shouldStartAfterAuthorization = false
                start()
            }
        case .denied, .restricted:
            if isRunning { stop() }
            statusMessage = "定位权限被拒绝，请到「设置 › 隐私与安全性 › 定位服务」中开启"
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        statusMessage = "定位出错：\(error.localizedDescription)"
    }
}
