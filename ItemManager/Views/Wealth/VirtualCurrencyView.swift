import SwiftUI
import Combine
import SpriteKit
import CoreMotion

// MARK: - 虚拟币纹理生成器

class VirtualCoinTextureGenerator {
    static let shared = VirtualCoinTextureGenerator()

    private var meowTexture: SKTexture?
    private var fishTexture: SKTexture?
    private var boneTexture: SKTexture?

    // 喵币纹理 - 金色质感
    func getMeowTexture() -> SKTexture {
        if let cached = meowTexture {
            return cached
        }

        let size = CGSize(width: 128, height: 128)
        let renderer = UIGraphicsImageRenderer(size: size)

        let image = renderer.image { context in
            let cgContext = context.cgContext
            let rect = CGRect(origin: .zero, size: size)

            // 径向渐变模拟3D球体
            let gradientCenter = CGPoint(x: size.width * 0.35, y: size.height * 0.35)
            let radius = size.width * 0.5

            let colors = [
                UIColor(red: 1.0, green: 0.95, blue: 0.7, alpha: 1.0).cgColor, // 高光中心
                UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0).cgColor, // 金黄色
                UIColor(red: 0.9, green: 0.7, blue: 0.1, alpha: 1.0).cgColor,  // 暗部
                UIColor(red: 0.7, green: 0.5, blue: 0.05, alpha: 1.0).cgColor   // 边缘
            ] as CFArray

            let locations: [CGFloat] = [0.0, 0.4, 0.7, 1.0]

            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
                cgContext.drawRadialGradient(
                    gradient,
                    startCenter: gradientCenter,
                    startRadius: 0,
                    endCenter: CGPoint(x: size.width * 0.5, y: size.height * 0.5),
                    endRadius: radius,
                    options: .drawsBeforeStartLocation
                )
            }

            // 高光
            cgContext.saveGState()
            cgContext.setBlendMode(.screen)
            let highlightColors = [
                UIColor(white: 1.0, alpha: 0.8).cgColor,
                UIColor(white: 1.0, alpha: 0.0).cgColor
            ] as CFArray
            if let highlightGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: highlightColors, locations: [0.0, 1.0]) {
                cgContext.drawRadialGradient(
                    highlightGradient,
                    startCenter: CGPoint(x: size.width * 0.3, y: size.height * 0.3),
                    startRadius: 0,
                    endCenter: CGPoint(x: size.width * 0.3, y: size.height * 0.3),
                    endRadius: size.width * 0.2,
                    options: .drawsBeforeStartLocation
                )
            }
            cgContext.restoreGState()

            // 爪子图案
            let pawConfig = UIImage.SymbolConfiguration(pointSize: size.width * 0.4, weight: .bold)
            if let pawImage = UIImage(systemName: "pawprint.fill", withConfiguration: pawConfig) {
                let pawRect = CGRect(
                    x: (size.width - pawImage.size.width) / 2,
                    y: (size.height - pawImage.size.height) / 2,
                    width: pawImage.size.width,
                    height: pawImage.size.height
                )
                pawImage.withTintColor(UIColor(red: 0.8, green: 0.6, blue: 0.0, alpha: 0.6)).draw(in: pawRect)
            }
        }

        let texture = SKTexture(image: image)
        self.meowTexture = texture
        return texture
    }

    // 鱼币纹理 - 橙色质感
    func getFishTexture() -> SKTexture {
        if let cached = fishTexture {
            return cached
        }

        let size = CGSize(width: 128, height: 128)
        let renderer = UIGraphicsImageRenderer(size: size)

        let image = renderer.image { context in
            let cgContext = context.cgContext

            // 径向渐变
            let gradientCenter = CGPoint(x: size.width * 0.35, y: size.height * 0.35)
            let radius = size.width * 0.5

            let colors = [
                UIColor(red: 1.0, green: 0.9, blue: 0.7, alpha: 1.0).cgColor, // 高光
                UIColor(red: 1.0, green: 0.65, blue: 0.0, alpha: 1.0).cgColor, // 橙色
                UIColor(red: 0.9, green: 0.5, blue: 0.0, alpha: 1.0).cgColor,  // 暗部
                UIColor(red: 0.7, green: 0.35, blue: 0.0, alpha: 1.0).cgColor   // 边缘
            ] as CFArray

            let locations: [CGFloat] = [0.0, 0.4, 0.7, 1.0]

            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
                cgContext.drawRadialGradient(
                    gradient,
                    startCenter: gradientCenter,
                    startRadius: 0,
                    endCenter: CGPoint(x: size.width * 0.5, y: size.height * 0.5),
                    endRadius: radius,
                    options: .drawsBeforeStartLocation
                )
            }

            // 高光
            cgContext.saveGState()
            cgContext.setBlendMode(.screen)
            let highlightColors = [
                UIColor(white: 1.0, alpha: 0.8).cgColor,
                UIColor(white: 1.0, alpha: 0.0).cgColor
            ] as CFArray
            if let highlightGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: highlightColors, locations: [0.0, 1.0]) {
                cgContext.drawRadialGradient(
                    highlightGradient,
                    startCenter: CGPoint(x: size.width * 0.3, y: size.height * 0.3),
                    startRadius: 0,
                    endCenter: CGPoint(x: size.width * 0.3, y: size.height * 0.3),
                    endRadius: size.width * 0.2,
                    options: .drawsBeforeStartLocation
                )
            }
            cgContext.restoreGState()

            // 鱼图案
            let fishConfig = UIImage.SymbolConfiguration(pointSize: size.width * 0.4, weight: .bold)
            if let fishImage = UIImage(systemName: "fish.fill", withConfiguration: fishConfig) {
                let fishRect = CGRect(
                    x: (size.width - fishImage.size.width) / 2,
                    y: (size.height - fishImage.size.height) / 2,
                    width: fishImage.size.width,
                    height: fishImage.size.height
                )
                fishImage.withTintColor(UIColor(red: 0.8, green: 0.4, blue: 0.0, alpha: 0.6)).draw(in: fishRect)
            }
        }

        let texture = SKTexture(image: image)
        self.fishTexture = texture
        return texture
    }

    // 骨头币纹理 - 铜色质感
    func getBoneTexture() -> SKTexture {
        if let cached = boneTexture {
            return cached
        }

        let size = CGSize(width: 128, height: 128)
        let renderer = UIGraphicsImageRenderer(size: size)

        let image = renderer.image { context in
            let cgContext = context.cgContext

            // 径向渐变
            let gradientCenter = CGPoint(x: size.width * 0.35, y: size.height * 0.35)
            let radius = size.width * 0.5

            let colors = [
                UIColor(red: 0.95, green: 0.85, blue: 0.7, alpha: 1.0).cgColor, // 高光
                UIColor(red: 0.8, green: 0.5, blue: 0.2, alpha: 1.0).cgColor,  // 铜色
                UIColor(red: 0.65, green: 0.4, blue: 0.15, alpha: 1.0).cgColor, // 暗部
                UIColor(red: 0.5, green: 0.3, blue: 0.1, alpha: 1.0).cgColor    // 边缘
            ] as CFArray

            let locations: [CGFloat] = [0.0, 0.4, 0.7, 1.0]

            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
                cgContext.drawRadialGradient(
                    gradient,
                    startCenter: gradientCenter,
                    startRadius: 0,
                    endCenter: CGPoint(x: size.width * 0.5, y: size.height * 0.5),
                    endRadius: radius,
                    options: .drawsBeforeStartLocation
                )
            }

            // 高光
            cgContext.saveGState()
            cgContext.setBlendMode(.screen)
            let highlightColors = [
                UIColor(white: 1.0, alpha: 0.7).cgColor,
                UIColor(white: 1.0, alpha: 0.0).cgColor
            ] as CFArray
            if let highlightGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: highlightColors, locations: [0.0, 1.0]) {
                cgContext.drawRadialGradient(
                    highlightGradient,
                    startCenter: CGPoint(x: size.width * 0.3, y: size.height * 0.3),
                    startRadius: 0,
                    endCenter: CGPoint(x: size.width * 0.3, y: size.height * 0.3),
                    endRadius: size.width * 0.2,
                    options: .drawsBeforeStartLocation
                )
            }
            cgContext.restoreGState()

            // 骨头图案
            let boneConfig = UIImage.SymbolConfiguration(pointSize: size.width * 0.4, weight: .bold)
            if let boneImage = UIImage(systemName: "bone.fill", withConfiguration: boneConfig) {
                let boneRect = CGRect(
                    x: (size.width - boneImage.size.width) / 2,
                    y: (size.height - boneImage.size.height) / 2,
                    width: boneImage.size.width,
                    height: boneImage.size.height
                )
                boneImage.withTintColor(UIColor(red: 0.6, green: 0.35, blue: 0.1, alpha: 0.6)).draw(in: boneRect)
            }
        }

        let texture = SKTexture(image: image)
        self.boneTexture = texture
        return texture
    }
}

// MARK: - 虚拟币物理碰撞类别

struct VirtualCoinPhysicsCategory {
    static let none: UInt32 = 0
    static let wall: UInt32 = 0b1
    static let coin: UInt32 = 0b10
}

// MARK: - 虚拟币视图

struct VirtualCurrencyView: View {
    @Bindable var viewModel: WealthViewModel
    let isActive: Bool

    // 环境变量 - 参考金豆银珠
    @Environment(\.isSimulationActive) var isSimulationActive
    @Environment(\.isWealthStorageActive) var isWealthStorageActive

    // 媒体状态管理器 - 参考金豆银珠
    @StateObject private var mediaStateManager = MediaStateManager.shared

    @ObservedObject private var petDataManager = PetDataManager.shared
    @State private var presentedDestination: VirtualCurrencyDestination?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 底层内容
                VStack(spacing: 0) {
                    // 标题
                    Text("萌宠世界货币")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.top, 16)

                    // 三种虚拟币展示
                    VStack(spacing: 20) {
                        VirtualCoinCard(
                            coinType: .meowCoin,
                            name: "喵币",
                            amount: petDataManager.status.meowCoin,
                            actionTitle: "点按充值"
                        ) {
                            presentedDestination = .meowCoinStore
                        }

                        VirtualCoinCard(
                            coinType: .fishCoin,
                            name: "鱼币",
                            amount: petDataManager.status.fishCoin,
                            actionTitle: "点按兑换"
                        ) {
                            presentedDestination = .currencyExchange(.meowToFish)
                        }

                        VirtualCoinCard(
                            coinType: .boneCoin,
                            name: "骨头币",
                            amount: petDataManager.status.boneCoin,
                            actionTitle: "点按兑换"
                        ) {
                            presentedDestination = .currencyExchange(.meowToBone)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)

                    Spacer()
                }

                // 上层物理容器 - 只在激活时显示
                if isActive {
                    VirtualCoinPhysicsContainer(
                        meowCoinCount: petDataManager.status.meowCoin,
                        fishCoinCount: petDataManager.status.fishCoin,
                        boneCoinCount: petDataManager.status.boneCoin
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(false)
                }
            }
        }
        .sheet(item: $presentedDestination) { destination in
            switch destination {
            case .meowCoinStore:
                MeowCoinStoreView()
            case .currencyExchange(let preferredDirection):
                PetCurrencyExchangeSheet(preferredDirection: preferredDirection)
                    .presentationDetents([.medium])
            }
        }
        .onChange(of: isActive) { _, newValue in
            if !newValue {
                // 当 Tab 不再激活时停止音效
                SoundManager.shared.stopAllSounds()
            }
        }
    }
}

// MARK: - 虚拟币类型枚举

enum VirtualCoinType {
    case fishCoin    // 鱼币
    case meowCoin    // 喵币
    case boneCoin    // 骨头币

    // 图标容器
    @ViewBuilder
    var iconContainer: some View {
        switch self {
        case .fishCoin:
            Image(systemName: "fish.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.orange)
                .shadow(color: .orange.opacity(0.4), radius: 8, x: 0, y: 4)
        case .meowCoin:
            Image(systemName: "pawprint.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.yellow)
                .shadow(color: .yellow.opacity(0.4), radius: 8, x: 0, y: 4)
        case .boneCoin:
            ZStack {
                Image(systemName: "circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(Color(hex: "CD7F32"))
                Text("🦴")
                    .font(.system(size: 32))
            }
            .shadow(color: Color(hex: "CD7F32").opacity(0.4), radius: 8, x: 0, y: 4)
        }
    }

    // 背景渐变色
    var gradientColors: [Color] {
        switch self {
        case .fishCoin:
            return [Color.orange, Color.orange.opacity(0.7)]
        case .meowCoin:
            return [Color.yellow, Color.orange.opacity(0.6)]
        case .boneCoin:
            return [Color(hex: "CD7F32"), Color(hex: "8B4513")]
        }
    }
}

private enum VirtualCurrencyDestination: Identifiable, Equatable {
    case meowCoinStore
    case currencyExchange(PetCurrencyExchangeDirection)

    var id: String {
        switch self {
        case .meowCoinStore:
            return "meowCoinStore"
        case .currencyExchange(let direction):
            return "currencyExchange:\(direction.rawValue)"
        }
    }
}

// MARK: - 透明物理货币容器

struct VirtualCoinPhysicsContainer: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.isSimulationActive) var isSimulationActive
    @Environment(\.isWealthStorageActive) var isWealthStorageActive

    @StateObject private var mediaStateManager = MediaStateManager.shared
    @State private var scene: VirtualCoinScene?
    @State private var isViewVisible: Bool = false

    let meowCoinCount: Int
    let fishCoinCount: Int
    let boneCoinCount: Int

    // 计算是否应该暂停
    private var shouldPause: Bool {
        !isViewVisible || scenePhase != .active || !isSimulationActive || !isWealthStorageActive || mediaStateManager.isPhysicsPaused
    }

    var body: some View {
        GeometryReader { proxy in
            SpriteView(
                scene: createScene(size: proxy.size),
                isPaused: shouldPause,
                options: [.allowsTransparency]
            )
            .background(Color.clear)
            .onAppear {
                isViewVisible = true
                HapticEngineManager.shared.resumeHaptics()
            }
            .onDisappear {
                isViewVisible = false
                scene?.pauseSimulation()
                HapticEngineManager.shared.stopHaptics()
                SoundManager.shared.stopAllSounds()
            }
            .onChange(of: meowCoinCount) { _, newValue in
                scene?.updateMeowCoins(count: newValue)
            }
            .onChange(of: fishCoinCount) { _, newValue in
                scene?.updateFishCoins(count: newValue)
            }
            .onChange(of: boneCoinCount) { _, newValue in
                scene?.updateBoneCoins(count: newValue)
            }
            .onChange(of: colorScheme) { _, newScheme in
                scene?.updateBackgroundColor(for: newScheme)
            }
            .onChange(of: shouldPause) { _, newValue in
                if newValue {
                    scene?.pauseSimulation()
                } else {
                    scene?.resumeSimulation()
                }
            }
        }
    }

    private func createScene(size: CGSize) -> SKScene {
        if let existingScene = scene {
            if existingScene.size != size {
                existingScene.size = size
            }
            return existingScene
        }

        let newScene = VirtualCoinScene(size: size)
        newScene.scaleMode = .aspectFill
        newScene.updateBackgroundColor(for: colorScheme)

        // 初始化货币数量
        newScene.updateMeowCoins(count: meowCoinCount)
        newScene.updateFishCoins(count: fishCoinCount)
        newScene.updateBoneCoins(count: boneCoinCount)

        DispatchQueue.main.async {
            if self.scene == nil {
                self.scene = newScene
            }
        }

        return newScene
    }
}

// MARK: - 虚拟币物理场景

class VirtualCoinScene: SKScene, SKPhysicsContactDelegate {
    private let motionManager = CMMotionManager()

    // 配置参数
    private let coinRadius: CGFloat = 12.0
    private let maxCoinsPerType = 100 // 每种货币上限为100实体币

    // 货币节点数组
    private var meowCoinNodes: [SKNode] = []
    private var fishCoinNodes: [SKNode] = []
    private var boneCoinNodes: [SKNode] = []

    // 目标数量
    private var targetMeowCount: Int = 0
    private var targetFishCount: Int = 0
    private var targetBoneCount: Int = 0

    // 每帧处理数量
    private let coinsPerFrameAdd: Int = 20
    private let coinsPerFrameRemove: Int = 30

    // 震动控制 - 参考金豆银珠
    private var lastHapticTime: TimeInterval = 0
    private let hapticMinInterval: TimeInterval = 0.08
    private var frameMaxImpulse: CGFloat = 0.0
    private var frameContactPoint: CGPoint = .zero
    private var frameCollisionCount: Int = 0
    private var isWallCollisionFrame: Bool = false

    // 兑换比例：1喵币=1实体喵币，1000鱼币=1实体鱼币，1000骨头币=1实体骨头币
    func updateMeowCoins(count: Int) {
        self.targetMeowCount = min(count, maxCoinsPerType)
    }

    func updateFishCoins(count: Int) {
        // 1000虚拟鱼币 = 1实体鱼币
        let entityCount = count / 1000
        self.targetFishCount = min(entityCount, maxCoinsPerType)
    }

    func updateBoneCoins(count: Int) {
        // 1000虚拟骨头币 = 1实体骨头币
        let entityCount = count / 1000
        self.targetBoneCount = min(entityCount, maxCoinsPerType)
    }

    func pauseSimulation() {
        self.isPaused = true
        motionManager.stopDeviceMotionUpdates()
        HapticEngineManager.shared.updateHapticParameters(intensity: 0, sharpness: 0)
        HapticEngineManager.shared.stopHaptics()
        SoundManager.shared.stopAllSounds()
    }

    func resumeSimulation() {
        self.isPaused = false
        startMotionUpdates()
    }

    override func didMove(to view: SKView) {
        setupPhysicsBoundary()
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
        physicsWorld.contactDelegate = self
        startMotionUpdates()
    }

    override func update(_ currentTime: TimeInterval) {
        guard !isPaused else { return }

        // 处理货币队列
        processCoinQueues()

        // 处理碰撞震动 - 参考金豆银珠
        if frameCollisionCount > 0 {
            triggerAggregatedHaptic(currentTime: currentTime)
        }

        // 持续震动调制
        let currentEnergy = min(CGFloat(frameCollisionCount) * 0.1 + frameMaxImpulse * 0.5, 1.0)
        if currentEnergy > 0.05 {
            HapticEngineManager.shared.playRollingTexture(intensity: Float(currentEnergy))
        } else {
            HapticEngineManager.shared.playRollingTexture(intensity: 0)
        }

        // 重置帧数据
        frameMaxImpulse = 0.0
        frameContactPoint = .zero
        frameCollisionCount = 0
        isWallCollisionFrame = false
    }

    // MARK: - 碰撞检测

    func didBegin(_ contact: SKPhysicsContact) {
        let impulse = contact.collisionImpulse

        if impulse > 0.0001 {
            if impulse > frameMaxImpulse {
                frameMaxImpulse = impulse
                frameContactPoint = contact.contactPoint
            }
            frameCollisionCount += 1

            if (contact.bodyA.categoryBitMask == VirtualCoinPhysicsCategory.wall) ||
               (contact.bodyB.categoryBitMask == VirtualCoinPhysicsCategory.wall) {
                isWallCollisionFrame = true
            }
        }
    }

    private func triggerAggregatedHaptic(currentTime: TimeInterval) {
        guard currentTime - lastHapticTime > hapticMinInterval else { return }

        lastHapticTime = currentTime

        let normalizedIntensity: Float
        let sharpness: Float
        let impactType: SoundManager.ImpactType

        if isWallCollisionFrame {
            normalizedIntensity = Float(min(frameMaxImpulse * 10.0, 1.0))
            sharpness = 0.9
            impactType = .hard
        } else {
            let baseIntensity = Float(min(frameMaxImpulse * 15.0, 1.0))
            normalizedIntensity = baseIntensity * 0.6
            sharpness = 0.4
            impactType = .soft
        }

        let normalizedX = frameContactPoint.x / self.size.width
        let normalizedY = frameContactPoint.y / self.size.height

        HapticEngineManager.shared.playCollisionHaptic(
            intensity: normalizedIntensity,
            sharpness: sharpness,
            position: CGPoint(x: normalizedX, y: normalizedY),
            type: impactType
        )
    }

    // MARK: - 货币队列处理

    private func processCoinQueues() {
        processCoinType(
            currentNodes: &meowCoinNodes,
            targetCount: targetMeowCount,
            createNode: { self.createMeowCoinNode() }
        )

        processCoinType(
            currentNodes: &fishCoinNodes,
            targetCount: targetFishCount,
            createNode: { self.createFishCoinNode() }
        )

        processCoinType(
            currentNodes: &boneCoinNodes,
            targetCount: targetBoneCount,
            createNode: { self.createBoneCoinNode() }
        )
    }

    private func processCoinType(
        currentNodes: inout [SKNode],
        targetCount: Int,
        createNode: () -> SKNode
    ) {
        let currentCount = currentNodes.count

        if currentCount < targetCount {
            let countToAdd = min(coinsPerFrameAdd, targetCount - currentCount)
            for _ in 0..<countToAdd {
                let node = createNode()
                spawnNode(node)
                currentNodes.append(node)
            }
        } else if currentCount > targetCount {
            let countToRemove = min(coinsPerFrameRemove, currentCount - targetCount)
            for _ in 0..<countToRemove {
                if let node = currentNodes.popLast() {
                    node.removeFromParent()
                }
            }
        }
    }

    private func spawnNode(_ node: SKNode) {
        let safeMinX = coinRadius
        let safeMaxX = size.width - coinRadius

        guard safeMaxX > safeMinX else { return }

        let randomX = CGFloat.random(in: safeMinX...safeMaxX)
        let spawnY = size.height - coinRadius - 20

        node.position = CGPoint(x: randomX, y: spawnY)
        addChild(node)
    }

    // MARK: - 创建货币节点（使用3D纹理）

    private func createMeowCoinNode() -> SKNode {
        let texture = VirtualCoinTextureGenerator.shared.getMeowTexture()
        let node = SKSpriteNode(texture: texture)
        let diameter = coinRadius * 2
        node.size = CGSize(width: diameter, height: diameter)

        let body = SKPhysicsBody(circleOfRadius: coinRadius)
        body.mass = 0.002
        body.restitution = 0.2
        body.friction = 0.5
        body.allowsRotation = true

        let isSensor = Int.random(in: 1...10) == 1
        body.categoryBitMask = VirtualCoinPhysicsCategory.coin
        body.collisionBitMask = VirtualCoinPhysicsCategory.coin | VirtualCoinPhysicsCategory.wall
        body.contactTestBitMask = isSensor ? (VirtualCoinPhysicsCategory.coin | VirtualCoinPhysicsCategory.wall) : 0

        node.physicsBody = body
        node.zRotation = CGFloat.random(in: 0...(2 * .pi))

        return node
    }

    private func createFishCoinNode() -> SKNode {
        let texture = VirtualCoinTextureGenerator.shared.getFishTexture()
        let node = SKSpriteNode(texture: texture)
        let diameter = coinRadius * 2
        node.size = CGSize(width: diameter, height: diameter)

        let body = SKPhysicsBody(circleOfRadius: coinRadius)
        body.mass = 0.002
        body.restitution = 0.2
        body.friction = 0.5
        body.allowsRotation = true

        let isSensor = Int.random(in: 1...10) == 1
        body.categoryBitMask = VirtualCoinPhysicsCategory.coin
        body.collisionBitMask = VirtualCoinPhysicsCategory.coin | VirtualCoinPhysicsCategory.wall
        body.contactTestBitMask = isSensor ? (VirtualCoinPhysicsCategory.coin | VirtualCoinPhysicsCategory.wall) : 0

        node.physicsBody = body
        node.zRotation = CGFloat.random(in: 0...(2 * .pi))

        return node
    }

    private func createBoneCoinNode() -> SKNode {
        let texture = VirtualCoinTextureGenerator.shared.getBoneTexture()
        let node = SKSpriteNode(texture: texture)
        let diameter = coinRadius * 2
        node.size = CGSize(width: diameter, height: diameter)

        let body = SKPhysicsBody(circleOfRadius: coinRadius)
        body.mass = 0.002
        body.restitution = 0.2
        body.friction = 0.5
        body.allowsRotation = true

        let isSensor = Int.random(in: 1...10) == 1
        body.categoryBitMask = VirtualCoinPhysicsCategory.coin
        body.collisionBitMask = VirtualCoinPhysicsCategory.coin | VirtualCoinPhysicsCategory.wall
        body.contactTestBitMask = isSensor ? (VirtualCoinPhysicsCategory.coin | VirtualCoinPhysicsCategory.wall) : 0

        node.physicsBody = body
        node.zRotation = CGFloat.random(in: 0...(2 * .pi))

        return node
    }

    private func setupPhysicsBoundary() {
        let boundaryRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        physicsBody = SKPhysicsBody(edgeLoopFrom: boundaryRect)
        physicsBody?.categoryBitMask = VirtualCoinPhysicsCategory.wall
        physicsBody?.collisionBitMask = VirtualCoinPhysicsCategory.coin
        physicsBody?.contactTestBitMask = VirtualCoinPhysicsCategory.coin
        physicsBody?.restitution = 0.2
        physicsBody?.friction = 0.3
    }

    func updateBackgroundColor(for scheme: ColorScheme) {
        self.backgroundColor = .clear
    }

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }

        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] (data, error) in
            guard let data = data, let self = self else { return }

            let interfaceOrientation = self.view?.window?.windowScene?.interfaceOrientation ?? .portrait

            let gravityX: Double
            let gravityY: Double

            switch interfaceOrientation {
            case .landscapeLeft:
                gravityX = data.gravity.y
                gravityY = data.gravity.x
            case .landscapeRight:
                gravityX = -data.gravity.y
                gravityY = -data.gravity.x
            case .portraitUpsideDown:
                gravityX = -data.gravity.x
                gravityY = -data.gravity.y
            default:
                gravityX = data.gravity.x
                gravityY = data.gravity.y
            }

            self.physicsWorld.gravity = CGVector(dx: gravityX * 15, dy: gravityY * 15)
        }
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}

// MARK: - 虚拟币卡片

struct VirtualCoinCard: View {
    let coinType: VirtualCoinType
    let name: String
    let amount: Int
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                coinType.iconContainer
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 6) {
                    Text(name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        LiquidRollingNumber(
                            value: Double(amount),
                            exchangeRateToCNY: 1.0,
                            fixedTier: getTierForAmount(amount)
                        )
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                    }

                    Text(actionTitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(coinType.gradientColors[0].opacity(0.9))
                }

                Spacer()

                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                coinType.gradientColors[0].opacity(0.95),
                                coinType.gradientColors[1].opacity(0.75)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(uiColor: .secondarySystemBackground).opacity(0.6))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [
                                coinType.gradientColors[0].opacity(0.3),
                                coinType.gradientColors[1].opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private func getTierForAmount(_ amount: Int) -> WealthTier {
        switch amount {
        case 0..<1000:
            return .copper
        case 1000..<5000:
            return .silver
        case 5000..<50000:
            return .gold
        case 50000..<100000:
            return .emerald
        case 100000..<200000:
            return .platinum
        case 200000..<500000:
            return .diamond
        case 500000..<1000000:
            return .sparklingGold
        default:
            return .rainbow
        }
    }
}
