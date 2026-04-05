import CoreLocation
import UserNotifications
import UIKit

struct SavedLocation: Codable, Identifiable {
    let id: String
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    var placeName: String

    var coordinateString: String {
        String(format: "%.5f, %.5f", latitude, longitude)
    }

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: timestamp)
    }

    var displayName: String {
        placeName.isEmpty ? coordinateString : placeName
    }
}

final class LocationRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var savedLocations: [SavedLocation] = []

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private static let storageKey = "saved_locations"
    private var lastRecordTime: Date = .distantPast
    private var isRecording = false
    var onRecorded: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        loadFromDisk()
        requestNotificationPermission()
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func recordCurrentLocation() {
        // 5초 이내 중복 호출 차단
        let now = Date()
        guard now.timeIntervalSince(lastRecordTime) > 5.0, !isRecording else { return }
        lastRecordTime = now
        isRecording = true
        requestPermission()
        manager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRecording, let loc = locations.last else { return }
        isRecording = false

        let entryId = UUID().uuidString

        // 역지오코딩 후 한 번에 저장
        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, _ in
            guard let self else { return }
            let name: String
            if let pm = placemarks?.first {
                name = [pm.locality, pm.subLocality, pm.thoroughfare]
                    .compactMap { $0 }
                    .joined(separator: " ")
            } else {
                name = ""
            }

            let entry = SavedLocation(
                id: entryId,
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude,
                timestamp: Date(),
                placeName: name
            )

            DispatchQueue.main.async {
                self.savedLocations.insert(entry, at: 0)
                self.saveToDisk()
                self.sendNotification(title: "위치 저장됨", body: entry.displayName)
                self.onRecorded?()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isRecording = false
        sendNotification(title: "위치 기록 실패", body: error.localizedDescription)
    }

    // MARK: - Delete

    func deleteByIDs(_ ids: Set<String>) {
        savedLocations.removeAll { ids.contains($0.id) }
        saveToDisk()
    }

    func deleteAll() {
        savedLocations.removeAll()
        saveToDisk()
    }

    // MARK: - Map

    enum MapApp: String, CaseIterable, Identifiable {
        case kakao = "kakao"
        case naver = "naver"
        case google = "google"
        case apple = "apple"

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .kakao: return "카카오맵"
            case .naver: return "네이버지도"
            case .google: return "구글맵"
            case .apple: return "기본 지도"
            }
        }
    }

    @Published var preferredMap: MapApp = {
        let raw = UserDefaults.standard.string(forKey: "kronaby_preferred_map") ?? "kakao"
        return MapApp(rawValue: raw) ?? .kakao
    }()

    func setPreferredMap(_ app: MapApp) {
        preferredMap = app
        UserDefaults.standard.set(app.rawValue, forKey: "kronaby_preferred_map")
    }

    func openInMap(_ location: SavedLocation) {
        let lat = location.latitude
        let lon = location.longitude
        let q = location.displayName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Pin"

        var url: URL?
        switch preferredMap {
        case .kakao:
            url = URL(string: "kakaomap://look?p=\(lat),\(lon)")
        case .naver:
            url = URL(string: "nmap://place?lat=\(lat)&lng=\(lon)&name=\(q)&appname=com.usbin.keepnaby")
        case .google:
            url = URL(string: "comgooglemaps://?q=\(lat),\(lon)")
        case .apple:
            url = URL(string: "maps://?ll=\(lat),\(lon)&q=\(q)")
        }

        if let url, UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return
        }
        // Fallback: Apple Maps
        if let apple = URL(string: "maps://?ll=\(lat),\(lon)&q=\(q)") {
            UIApplication.shared.open(apple)
        }
    }

    // MARK: - Persistence

    private func saveToDisk() {
        if let data = try? JSONEncoder().encode(savedLocations) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func loadFromDisk() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([SavedLocation].self, from: data) {
            savedLocations = decoded
        }
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
