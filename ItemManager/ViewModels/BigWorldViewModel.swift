//
//  BigWorldViewModel.swift
//  ItemManager
//
//  大世界 - 业务逻辑管理
//

import Foundation
import SwiftUI
import CoreLocation
import Combine

@MainActor
class BigWorldViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var flightStatus: FlightStatus = .idle
    @Published var selectedLandmark: Landmark?
    @Published var flightRecords: [FlightRecord] = []
    @Published var unlockedBadges: [TeaPartyBadge] = []
    @Published var achievements: [Achievement] = []
    @Published var currentNarrative: String = ""
    @Published var flightProgress: Double = 0.0
    @Published var isDepartureHidden: Bool = true
    @Published var userLevel: Int = 1
    @Published var totalTeaParties: Int = 0
    @Published var currentBoardingPass: BoardingPass?
    
    // MARK: - Location
    @Published var currentLocation: String = "未知位置"
    @Published var departureCity: String? = nil
    @Published var userCoordinate: CLLocationCoordinate2D? = nil
    private let locationManager = CLLocationManager()
    
    // MARK: - Private Properties
    private var flightTimer: Timer?
    private var narrativeTimer: Timer?
    private let flightDuration: TimeInterval = 25 // 实际飞行时间25秒
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Seat Generation
    private let seatRows = ["01", "02", "03", "04", "05"]
    private let seatLetters = ["A", "C", "D", "F"]
    
    // MARK: - Initialization
    init() {
        loadData()
        requestLocation()
        setupAchievements()
    }
    
    // MARK: - Data Persistence
    private func loadData() {
        if let recordsData = UserDefaults.standard.data(forKey: "flightRecords"),
           let records = try? JSONDecoder().decode([FlightRecord].self, from: recordsData) {
            flightRecords = records
        }
        
        if let badgesData = UserDefaults.standard.data(forKey: "unlockedBadges"),
           let badges = try? JSONDecoder().decode([TeaPartyBadge].self, from: badgesData) {
            unlockedBadges = badges
        }
        
        userLevel = UserDefaults.standard.integer(forKey: "userLevel")
        if userLevel == 0 { userLevel = 1 }
        
        totalTeaParties = UserDefaults.standard.integer(forKey: "totalTeaParties")
        isDepartureHidden = UserDefaults.standard.bool(forKey: "isDepartureHidden")
        if UserDefaults.standard.object(forKey: "isDepartureHidden") == nil {
            isDepartureHidden = true // 默认隐藏出发地
        }
    }
    
    private func saveData() {
        if let recordsData = try? JSONEncoder().encode(flightRecords) {
            UserDefaults.standard.set(recordsData, forKey: "flightRecords")
        }
        
        if let badgesData = try? JSONEncoder().encode(unlockedBadges) {
            UserDefaults.standard.set(badgesData, forKey: "unlockedBadges")
        }
        
        UserDefaults.standard.set(userLevel, forKey: "userLevel")
        UserDefaults.standard.set(totalTeaParties, forKey: "totalTeaParties")
        UserDefaults.standard.set(isDepartureHidden, forKey: "isDepartureHidden")
    }
    
    // MARK: - Location Handling
    private func requestLocation() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        
        // 简化处理，使用模拟位置或获取城市名
        if let location = locationManager.location {
            reverseGeocode(location)
        } else {
            currentLocation = "梦幻之城"
        }
    }
    
    private func reverseGeocode(_ location: CLLocation) {
        userCoordinate = location.coordinate
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            if let city = placemarks?.first?.locality {
                self?.currentLocation = city
                self?.departureCity = city
            } else {
                self?.currentLocation = "当前城市"
                self?.departureCity = "当前城市"
            }
        }
    }
    
    // MARK: - Flight Logic
    func selectLandmark(_ landmark: Landmark) {
        guard landmark.requiredLevel <= userLevel else {
            // 等级不足提示
            return
        }
        selectedLandmark = landmark
        flightStatus = .selecting
    }
    
    func generateSeatNumber() -> String {
        let row = seatRows.randomElement() ?? "01"
        let letter = seatLetters.randomElement() ?? "A"
        return "\(row)\(letter)"
    }
    
    func startBoarding() {
        let seatNumber = generateSeatNumber()
        flightStatus = .boarding(seatNumber: seatNumber)
        
        // 生成登机牌
        generateCurrentBoardingPass(seatNumber: seatNumber)
        
        // 播放登机广播
        currentNarrative = FlightNarrative.boardingMessages.randomElement() ?? "欢迎登机"
        
        // 2秒后开始飞行
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.startFlight()
        }
    }
    
    func generateCurrentBoardingPass(seatNumber: String) {
        guard let landmark = selectedLandmark else { return }
        
        currentBoardingPass = BoardingPass(
            passengerName: "Lo同好",
            from: isDepartureHidden ? "???" : (departureCity ?? "出发地"),
            to: landmark.name,
            flightDate: Date(),
            seatNumber: seatNumber,
            gate: String(format: "%02d", Int.random(in: 1...20)),
            boardingTime: Date().addingTimeInterval(-1800),
            qrCodeData: "LOLITA-\(landmark.id.uuidString)",
            stampImage: "stamp_\(landmark.type.rawValue)",
            isDepartureHidden: isDepartureHidden
        )
    }
    
    func startFlight() {
        flightStatus = .flying(progress: 0, narrative: FlightNarrative.boardingMessages.randomElement() ?? "起飞")
        flightProgress = 0
        
        guard let landmark = selectedLandmark else { return }
        
        // 准备飞行叙事
        let messages = FlightNarrative.inFlightMessages(to: landmark)
        var messageIndex = 0
        
        // 更新叙事
        narrativeTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if messageIndex < messages.count {
                self.currentNarrative = messages[messageIndex]
                messageIndex += 1
            }
        }
        
        // 更新进度
        let progressInterval = flightDuration / 100
        flightTimer = Timer.scheduledTimer(withTimeInterval: progressInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            self.flightProgress += 0.01
            self.flightStatus = .flying(progress: self.flightProgress, narrative: self.currentNarrative)
            
            if self.flightProgress >= 1.0 {
                self.completeFlight()
            }
        }
    }
    
    private func completeFlight() {
        flightTimer?.invalidate()
        flightTimer = nil
        narrativeTimer?.invalidate()
        narrativeTimer = nil
        
        guard let landmark = selectedLandmark else { return }
        
        // 播放到达广播
        currentNarrative = FlightNarrative.arrivalMessages.randomElement() ?? "欢迎抵达"
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.flightStatus = .arrived(landmark: landmark)
        }
    }
    
    func checkIn() {
        guard let landmark = selectedLandmark else { return }
        
        // 创建徽章
        let badge = TeaPartyBadge(
            name: landmark.badgeName,
            description: landmark.badgeDescription,
            landmarkType: landmark.type,
            landmarkId: landmark.id,
            imageName: "badge_\(landmark.type.rawValue)",
            unlockDate: Date(),
            isLimited: false,
            specialEffect: nil,
            earnedDate: Date()
        )
        
        // 创建飞行记录
        let record = FlightRecord(
            landmark: landmark,
            departureLocation: currentLocation,
            flightDate: Date(),
            flightDuration: flightDuration,
            badgeEarned: badge,
            seatNumber: generateSeatNumber(),
            isDepartureHidden: isDepartureHidden
        )
        
        // 更新数据
        flightRecords.append(record)
        if !unlockedBadges.contains(where: { $0.name == badge.name }) {
            unlockedBadges.append(badge)
        }
        totalTeaParties += 1
        
        // 检查升级
        checkLevelUp()
        
        // 更新成就
        updateAchievements()
        
        // 保存数据
        saveData()
        
        // 更新状态
        flightStatus = .checkedIn(record: record)
    }
    
    func resetFlight() {
        flightTimer?.invalidate()
        flightTimer = nil
        narrativeTimer?.invalidate()
        narrativeTimer = nil
        flightStatus = .idle
        selectedLandmark = nil
        flightProgress = 0
        currentNarrative = ""
    }
    
    // MARK: - Level & Achievements
    private func checkLevelUp() {
        let newLevel: Int
        switch totalTeaParties {
        case 0...3: newLevel = 1
        case 4...7: newLevel = 2
        default: newLevel = 3
        }
        
        if newLevel > userLevel {
            userLevel = newLevel
        }
    }
    
    private func setupAchievements() {
        achievements = [
            Achievement(
                title: "初次起飞",
                description: "参加第一次茶会",
                requirement: 1,
                currentProgress: totalTeaParties,
                iconName: "airplane.departure",
                rewardBadge: nil,
                isUnlocked: totalTeaParties >= 1,
                themeColorName: "gold"
            ),
            Achievement(
                title: "环球旅行家",
                description: "参加5次不同地点的茶会",
                requirement: 5,
                currentProgress: totalTeaParties,
                iconName: "globe",
                rewardBadge: "环球旅行家",
                isUnlocked: totalTeaParties >= 5,
                themeColorName: "cinderella"
            ),
            Achievement(
                title: "徽章收藏家",
                description: "收集10个不同徽章",
                requirement: 10,
                currentProgress: unlockedBadges.count,
                iconName: "medal.fill",
                rewardBadge: nil,
                isUnlocked: unlockedBadges.count >= 10,
                themeColorName: "monica"
            ),
            Achievement(
                title: "极地探险家",
                description: "参加冰川和极光茶会",
                requirement: 2,
                currentProgress: unlockedBadges.filter { $0.landmarkType == .glacier || $0.landmarkType == .aurora }.count,
                iconName: "snowflake",
                rewardBadge: nil,
                isUnlocked: unlockedBadges.contains { $0.landmarkType == .glacier } && unlockedBadges.contains { $0.landmarkType == .aurora },
                themeColorName: "cinderella"
            ),
            Achievement(
                title: "花海漫步者",
                description: "参加樱花和薰衣草茶会",
                requirement: 2,
                currentProgress: unlockedBadges.filter { $0.landmarkType == .sakura || $0.landmarkType == .lavender }.count,
                iconName: "flower.fill",
                rewardBadge: nil,
                isUnlocked: unlockedBadges.contains { $0.landmarkType == .sakura } && unlockedBadges.contains { $0.landmarkType == .lavender },
                themeColorName: "hotpink"
            )
        ]
    }
    
    private func updateAchievements() {
        setupAchievements()
    }
    
    // MARK: - Boarding Pass Generation
    func generateBoardingPass(for record: FlightRecord) -> BoardingPass {
        BoardingPass(
            passengerName: "Lo同好",
            from: isDepartureHidden ? "???" : record.departureLocation,
            to: record.landmark.name,
            flightDate: record.flightDate,
            seatNumber: record.seatNumber,
            gate: String(format: "%02d", Int.random(in: 1...20)),
            boardingTime: record.flightDate.addingTimeInterval(-1800),
            qrCodeData: "LOLITA-\(record.id.uuidString)",
            stampImage: "stamp_\(record.landmark.type.rawValue)",
            isDepartureHidden: isDepartureHidden
        )
    }
    
    // MARK: - Available Landmarks
    var availableLandmarks: [Landmark] {
        Landmark.allLandmarks.filter { $0.requiredLevel <= userLevel }
    }
    
    var lockedLandmarks: [Landmark] {
        Landmark.allLandmarks.filter { $0.requiredLevel > userLevel }
    }
    
    // MARK: - Statistics
    var uniqueLocationsVisited: Int {
        Set(flightRecords.map { $0.landmark.id }).count
    }
    
    var favoriteLocation: Landmark? {
        let counts = flightRecords.reduce(into: [:]) { counts, record in
            counts[record.landmark.id, default: 0] += 1
        }
        guard let maxId = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        return flightRecords.first { $0.landmark.id == maxId }?.landmark
    }
}
