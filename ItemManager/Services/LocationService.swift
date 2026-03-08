import Foundation
import CoreLocation
import Combine

// MARK: - 位置服务管理器
@MainActor
class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()
    
    @Published var currentLocation: CLLocation?
    @Published var currentCity: String = "未知城市"
    @Published var currentProvince: String = "未知省份"
    @Published var locationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isLoading = false
    
    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?
    
    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }
    
    // MARK: - 请求位置权限
    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    // MARK: - 获取当前位置
    func getCurrentLocation() async -> CLLocation? {
        guard locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways else {
            requestAuthorization()
            return nil
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // 如果已经有位置，直接返回
        if let location = currentLocation {
            return location
        }
        
        // 请求新位置
        return await withCheckedContinuation { continuation in
            self.locationContinuation = continuation
            locationManager.startUpdatingLocation()
            
            // 5秒超时
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self = self else { return }
                if let continuation = self.locationContinuation {
                    self.locationContinuation = nil
                    continuation.resume(returning: self.currentLocation)
                }
                self.locationManager.stopUpdatingLocation()
            }
        }
    }
    
    // MARK: - 反向地理编码获取城市信息
    func reverseGeocode(_ location: CLLocation) async -> (city: String, province: String)? {
        let geocoder = CLGeocoder()
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }
            
            let city = placemark.locality ?? placemark.subLocality ?? "未知城市"
            let province = placemark.administrativeArea ?? "未知省份"
            
            return (city, province)
        } catch {
            print("反向地理编码失败: \(error)")
            return nil
        }
    }
    
    // MARK: - 获取季节
    func getCurrentSeason() -> Season {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: Date())
        
        switch month {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .autumn
        default: return .winter
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        Task { @MainActor in
            self.currentLocation = location
            
            // 获取城市信息
            if let cityInfo = await self.reverseGeocode(location) {
                self.currentCity = cityInfo.city
                self.currentProvince = cityInfo.province
            }
            
            // 恢复continuation
            if let continuation = self.locationContinuation {
                self.locationContinuation = nil
                continuation.resume(returning: location)
            }
            
            self.locationManager.stopUpdatingLocation()
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            print("获取位置失败: \(error)")
            
            if let continuation = self.locationContinuation {
                self.locationContinuation = nil
                continuation.resume(returning: nil)
            }
            
            self.locationManager.stopUpdatingLocation()
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.locationStatus = status
            
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.locationManager.startUpdatingLocation()
            }
        }
    }
}

// MARK: - 季节枚举
enum Season: String, CaseIterable {
    case spring = "春"
    case summer = "夏"
    case autumn = "秋"
    case winter = "冬"
    
    var displayName: String {
        return "\(rawValue)季"
    }
    
    // 季节对应的推荐色系
    var recommendedColors: [String] {
        switch self {
        case .spring:
            return ["樱花粉", "薄荷绿", "奶油白", "浅鹅黄", "薰衣草紫"]
        case .summer:
            return ["海洋蓝", "薄荷绿", "珍珠白", "天空蓝", "珊瑚粉"]
        case .autumn:
            return ["焦糖棕", "枫叶红", "奶茶色", "杏色", "酒红色"]
        case .winter:
            return ["雪白", "深红", "藏青", "银灰", "玫瑰粉"]
        }
    }
}
