import CoreLocation
import MapKit
import Security
import SwiftUI
import UserNotifications

// This is the existing, separately managed ZFxF treasure-map backend.
// The museum uses iOS CoreLocation; it does not replace or copy the ZFxF app.
@MainActor
final class ZFxFLocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = ZFxFLocationService()

    @Published private(set) var currentFix: CLLocation?
    @Published private(set) var permission: CLAuthorizationStatus
    @Published private(set) var isConnected: Bool
    @Published private(set) var automaticDiscoveryEnabled: Bool
    @Published private(set) var pendingLetters = 0
    @Published var message = "定位只在你主动使用时开启。"

    private let manager = CLLocationManager()
    private let endpoint = URL(string: "https://memory.ryanecho.xyz/zfxf/api/")!
    private static let prefix = "zfxf-letter-"
    private static let enabledKey = "museum.zfxf.backgroundRegionsOptIn"
    private static let keyService = "com.zfxf.museum.geofence"
    private static let keyAccount = "zfxfPassword"

    override private init() {
        permission = manager.authorizationStatus
        isConnected = Self.loadPassword() != nil
        automaticDiscoveryEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // No continuous background GPS. iOS manages circular geofences.
        if automaticDiscoveryEnabled && permission == .authorizedAlways && isConnected {
            Task { await refreshRegions() }
        }
    }

    func locateNow() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            message = "请在 iPhone 设置 → 隐私与安全性 → 定位服务中允许 ZFxF Museum 使用定位。"
        @unknown default:
            message = "暂时无法使用系统定位。"
        }
    }

    func connect(password: String) async -> Bool {
        let value = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { message = "请输入你的 ZFxF 私人访问密码。"; return false }
        do {
            let regions = try await fetchRegions(bearer: value)
            guard Self.savePassword(value) else {
                message = "密码无法安全存入 iPhone 钥匙串。"
                return false
            }
            isConnected = true
            pendingLetters = regions.count
            message = "连接成功。共有 \(regions.count) 封尚待发现的秘密信件。"
            if automaticDiscoveryEnabled && permission == .authorizedAlways {
                monitor(regions)
            }
            return true
        } catch {
            message = "连接失败。请检查原 ZFxF 密码和服务器网络。"
            return false
        }
    }

    func disconnect() {
        disableAutomatic()
        _ = Self.savePassword("")
        isConnected = false
        pendingLetters = 0
        message = "已断开 ZFxF 地图，并清除这台手机保存的密码。"
    }

    func refreshRegions() async {
        guard let key = Self.loadPassword() else { return }
        do {
            let regions = try await fetchRegions(bearer: key)
            pendingLetters = regions.count
            if automaticDiscoveryEnabled && manager.authorizationStatus == .authorizedAlways {
                monitor(regions)
                message = "已与 ZFxF 地图同步 \(regions.count) 处秘密地点，iOS 将负责附近发现。"
            }
        } catch {
            message = "暂时无法更新秘密地点。原地图和已藏的信不受影响。"
        }
    }

    func enableAutomatic() {
        guard isConnected else {
            message = "先连接已有的 ZFxF 私人地图，才能守护附近的信。"
            return
        }
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            message = "这台设备不支持原生地点围栏。"
            return
        }
        automaticDiscoveryEnabled = true
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        if manager.authorizationStatus == .authorizedAlways {
            Task { await refreshRegions() }
        } else {
            manager.requestAlwaysAuthorization()
            message = "已经向 iOS 申请始终允许定位。系统允许后才能在后台发现附近的信。"
        }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge]) { _, _ in }
    }

    func disableAutomatic() {
        pendingDiscoveries.removeAll()
        automaticDiscoveryEnabled = false
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        for region in manager.monitoredRegions where region.identifier.hasPrefix(Self.prefix) {
            manager.stopMonitoring(for: region)
        }
    }

    // The original ZFxF server deliberately never returns exact coordinates
    // for sealed letters. Its public map exposes only a deliberately blurred
    // search area; we monitor that approximate circle and let the server
    // decide whether a one-shot, opt-in location check actually reaches a letter.
    private struct SearchArea: Decodable {
        let lat: Double
        let lon: Double
        let r: Double
    }
    private struct SecretRegion: Decodable {
        let id: String
        let status: String
        let area: SearchArea
    }
    private struct Payload: Decodable {
        let letters: [SecretRegion]
    }

    private func fetchRegions(bearer: String) async throws -> [SecretRegion] {
        var request = URLRequest(url: endpoint.appendingPathComponent("travel-map"), timeoutInterval: 15)
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        let (bytes, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              bytes.count < 5_000_000 else { throw URLError(.userAuthenticationRequired) }
        return try JSONDecoder().decode(Payload.self, from: bytes).letters
            .filter { $0.status == "sealed" }
    }

    private func monitor(_ regions: [SecretRegion]) {
        guard automaticDiscoveryEnabled, manager.authorizationStatus == .authorizedAlways else { return }
        let here = currentFix
        let sorted = regions.filter {
            $0.area.lat.isFinite && $0.area.lon.isFinite && $0.area.r.isFinite &&
            abs($0.area.lat) <= 90 && abs($0.area.lon) <= 180 && $0.area.r > 0
        }.sorted {
            guard let here else { return $0.id < $1.id }
            let a = CLLocation(latitude: $0.area.lat, longitude: $0.area.lon)
            let b = CLLocation(latitude: $1.area.lat, longitude: $1.area.lon)
            return here.distance(from: a) < here.distance(from: b)
        }
        // CoreLocation allows at most ~20 monitored regions per app.
        let selection = Array(sorted.prefix(20))
        let desired = Set(selection.map { Self.prefix + $0.id })
        for region in manager.monitoredRegions
            where region.identifier.hasPrefix(Self.prefix) && !desired.contains(region.identifier) {
            manager.stopMonitoring(for: region)
        }
        for region in selection {
            let id = Self.prefix + region.id
            guard !manager.monitoredRegions.contains(where: { $0.identifier == id }) else { continue }
            let center = CLLocationCoordinate2D(latitude: region.area.lat, longitude: region.area.lon)
            let radius = min(max(160, region.area.r), manager.maximumRegionMonitoringDistance)
            guard radius > 0 else { continue }
            let circle = CLCircularRegion(center: center, radius: radius, identifier: id)
            circle.notifyOnEntry = true
            circle.notifyOnExit = false
            manager.startMonitoring(for: circle)
            manager.requestState(for: circle)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        permission = manager.authorizationStatus
        if permission == .authorizedAlways || permission == .authorizedWhenInUse {
            manager.requestLocation()
        }
        if automaticDiscoveryEnabled {
            if permission == .authorizedAlways {
                Task { await refreshRegions() }
            } else {
                message = "自动发现需要系统授予「始终允许」定位权限。你仍然可以手动查看位置。"
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last, last.horizontalAccuracy >= 0 else { return }
        currentFix = last
        // Manual map positioning never uploads coordinates. Only the separate
        // opt-in geofence flow sends a single fix to the original ZFxF server.
        if automaticDiscoveryEnabled && permission == .authorizedAlways &&
           !pendingDiscoveries.isEmpty && last.horizontalAccuracy <= 250 {
            let triggered = pendingDiscoveries
            pendingDiscoveries.removeAll()
            Task { await verifyNearbyLetters(at: last, triggered: triggered) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        pendingDiscoveries.removeAll()
        message = "当前定位暂不可用，可以稍后再试。"
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        discover(region: region)
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState,
                         for region: CLRegion) {
        if state == .inside { discover(region: region) }
    }

    private var pendingDiscoveries = Set<String>()

    private func discover(region: CLRegion) {
        guard automaticDiscoveryEnabled, region.identifier.hasPrefix(Self.prefix),
              manager.authorizationStatus == .authorizedAlways,
              Self.loadPassword() != nil else { return }
        let id = String(region.identifier.dropFirst(Self.prefix.count))
        guard !id.isEmpty, !pendingDiscoveries.contains(id) else { return }
        pendingDiscoveries.insert(id)
        // The public server deliberately hides the real letter coordinates.
        // A region entry alone is NOT proof. Ask iOS for a fresh, single fix;
        // the original /api/location endpoint validates the true distance.
        manager.requestLocation()
    }

    private func verifyNearbyLetters(at fix: CLLocation, triggered: Set<String>) async {
        guard automaticDiscoveryEnabled, manager.authorizationStatus == .authorizedAlways,
              let key = Self.loadPassword(), !triggered.isEmpty else { return }
        do {
            let before = Set((try await fetchRegions(bearer: key)).map(\.id))
            var request = URLRequest(url: endpoint.appendingPathComponent("location"), timeoutInterval: 15)
            request.httpMethod = "POST"
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "lat": fix.coordinate.latitude,
                "lon": fix.coordinate.longitude,
                "acc": fix.horizontalAccuracy
            ])
            let (_, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            // Server returns {ok:true}, not a per-letter discovery result.
            // Check the public map AFTER the location is verified.
            let after = try await fetchRegions(bearer: key)
            let stillSealed = Set(after.map(\.id))
            let justFound = triggered.intersection(before.subtracting(stillSealed))
            for id in justFound {
                let notifiedKey = "museum.zfxf.notified." + id
                guard !UserDefaults.standard.bool(forKey: notifiedKey) else { continue }
                let note = UNMutableNotificationContent()
                note.title = "ZFxF · 附近有封信"
                note.body = "一封提前藏好的信已经被发现。打开我们的秘密地图拆开它。"
                note.sound = .default
                try await UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: "zfxf-" + id, content: note, trigger: nil)
                )
                UserDefaults.standard.set(true, forKey: notifiedKey)
            }
            pendingLetters = after.count
            monitor(after)
            message = justFound.isEmpty
                ? "已与秘密地图核对附近位置，尚未发现新的信。"
                : "发现了一封藏好的信，已经通知你。"
        } catch {
            message = "附近定位核验暂时失败，原有信件没有被修改。"
        }
    }

    // Keychain is local to the device; the geofence API secret is not bundled
    // into the application, GitHub Pages, Info.plist, or iCloud backup.
    private static func loadPassword() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: keyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func savePassword(_ password: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: keyAccount
        ]
        if password.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        var attributes = query
        attributes[kSecValueData as String] = Data(password.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            return SecItemUpdate(query as CFDictionary,
                                 [kSecValueData as String: Data(password.utf8)] as CFDictionary) == errSecSuccess
        }
        return status == errSecSuccess
    }
}

struct MuseumLocationView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var geo = ZFxFLocationService.shared
    @State private var camera: MapCameraPosition = .automatic
    @State private var secret = ""
    @State private var connecting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Map(position: $camera) {
                    UserAnnotation()
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }
                .frame(maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    Button {
                        geo.locateNow()
                    } label: {
                        Label("定位到我", systemImage: "location.fill")
                            .padding(10)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .padding(14)
                }

                Form {
                    Section("原生定位") {
                        Text(geo.message)
                            .font(.footnote)
                        Button("重新定位") { geo.locateNow() }
                    }
                    Section("ZFxF 秘密地点 · 独立连接") {
                        if geo.isConnected {
                            Text("已连接已有的藏信地图，待发现 \(geo.pendingLetters) 封信。")
                            Button("更新秘密地点") {
                                Task { await geo.refreshRegions() }
                            }
                            if geo.automaticDiscoveryEnabled {
                                Button("关闭自动发现", role: .destructive) {
                                    geo.disableAutomatic()
                                }
                            } else {
                                Button("开启经过地点自动发现") {
                                    geo.enableAutomatic()
                                }
                            }
                            Button("断开地图", role: .destructive) {
                                geo.disconnect()
                            }
                        } else {
                            SecureField("ZFxF 原有的登录密码", text: $secret)
                                .textContentType(.password)
                            Button(connecting ? "连接中…" : "连接已有的秘密地图") {
                                connecting = true
                                Task {
                                    _ = await geo.connect(password: secret)
                                    secret = ""
                                    connecting = false
                                }
                            }
                            .disabled(secret.isEmpty || connecting)
                        }
                    }
                    Section {
                        Text("你的蓝点由 iOS MapKit 绘制。开启自动发现后，iOS 只监测原地图公开的模糊范围；进入范围时向原 ZFxF 服务发送一次当前位置，由服务端核验是否真的找到信。服务端可能保存这一次到访点，不会持续上传轨迹或提前显示信件的真实坐标。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .scrollContentBackground(.hidden)
                .frame(maxHeight: 350)
            }
            .navigationTitle("附近的信")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onChange(of: geo.currentFix?.timestamp) { _, _ in
                guard let fix = geo.currentFix else { return }
                camera = .region(MKCoordinateRegion(
                    center: fix.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
                ))
            }
        }
    }
}
