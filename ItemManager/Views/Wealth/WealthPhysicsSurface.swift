import SwiftUI
import SpriteKit

/// 场景由承载它的 SKView 唯一持有，不能在 SwiftUI body 中创建后异步写回 State。
@MainActor
protocol WealthPhysicsScene: AnyObject {
    func pauseSimulation()
    func resumeSimulation()
}

struct WealthPhysicsSurface<Scene: SKScene & WealthPhysicsScene>: UIViewRepresentable {
    let isActive: Bool
    let makeScene: (CGSize) -> Scene
    let configureScene: (Scene, CGSize) -> Void

    func makeUIView(context: Context) -> WealthPhysicsHost<Scene> {
        WealthPhysicsHost(makeScene: makeScene)
    }

    func updateUIView(_ view: WealthPhysicsHost<Scene>, context: Context) {
        view.update(isActive: isActive, configure: configureScene)
    }

    static func dismantleUIView(_ view: WealthPhysicsHost<Scene>, coordinator: ()) {
        view.tearDown()
    }
}

final class WealthPhysicsHost<Scene: SKScene & WealthPhysicsScene>: SKView {
    private let makeScene: (CGSize) -> Scene
    private var configure: ((Scene, CGSize) -> Void)?
    private var requestedActive = false
    private var isRunning = false
    private(set) var hostedScene: Scene?

    init(makeScene: @escaping (CGSize) -> Scene) {
        self.makeScene = makeScene
        super.init(frame: .zero)
        allowsTransparency = true
        isOpaque = false
        backgroundColor = .clear
        layer.backgroundColor = UIColor.clear.cgColor
        preferredFramesPerSecond = 60
        isPaused = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(isActive: Bool, configure: @escaping (Scene, CGSize) -> Void) {
        requestedActive = isActive
        self.configure = configure
        synchronizeScene()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        synchronizeScene()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        synchronizeScene()
    }

    private func synchronizeScene() {
        let size = bounds.size
        let hasLayout = size.width.isFinite && size.height.isFinite && size.width > 1 && size.height > 1
        if hasLayout, window != nil, let configure {
            if hostedScene == nil {
                let created = makeScene(size)
                created.scaleMode = .resizeFill
                created.backgroundColor = .clear
                created.isPaused = true
                configure(created, size)
                hostedScene = created
                presentScene(created)
                // SpriteKit 挂载会重置暂停状态；必须在 presentScene 后应用首帧状态。
                created.isPaused = !isRunning
                isPaused = !isRunning
            } else if let hostedScene {
                if hostedScene.size != size { hostedScene.size = size }
                configure(hostedScene, size)
            }
        }

        let shouldRun = requestedActive && window != nil && hasLayout && hostedScene != nil
        guard shouldRun != isRunning else { return }
        isRunning = shouldRun
        if shouldRun {
            HapticEngineManager.shared.resumeHaptics()
            hostedScene?.resumeSimulation()
            isPaused = false
        } else {
            hostedScene?.pauseSimulation()
            isPaused = true
        }
    }

    func tearDown() {
        requestedActive = false
        if isRunning { hostedScene?.pauseSimulation() }
        isRunning = false
        let detachedScene = hostedScene
        presentScene(nil)
        detachedScene?.isPaused = true
        isPaused = true
        hostedScene = nil
        configure = nil
    }
}

/// 金豆/银珠使用同一套图片布局和物理边界计算，忽略暂未完成的零尺寸布局。
struct WealthContainerLayout {
    let frame: CGRect

    init(size: CGSize, customImageSize: CGSize?) {
        let fullFrame = CGRect(origin: .zero, size: size)
        guard let imageSize = customImageSize,
              imageSize.width > 0, imageSize.height > 0,
              size.width > 0, size.height > 0 else {
            frame = fullFrame
            return
        }
        let scale = min(size.width / imageSize.width, size.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        frame = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2,
                       width: width, height: height)
    }

    func physicsBoundary(in size: CGSize) -> CGRect {
        CGRect(x: frame.minX, y: size.height - frame.maxY, width: frame.width, height: frame.height)
    }
}

enum WealthVisualCount {
    static func beans(totalWeight: Double, beanWeight: Double, limit: Int) -> Int {
        guard totalWeight.isFinite, beanWeight.isFinite, totalWeight > 0, beanWeight > 0 else { return 0 }
        // 先限幅再转 Int，避免异常金额导致溢出并中断渲染。
        return Int(min(totalWeight / beanWeight, Double(max(0, limit))))
    }
}
