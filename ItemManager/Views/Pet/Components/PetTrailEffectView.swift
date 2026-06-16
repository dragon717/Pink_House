import SwiftUI
import Combine

// MARK: - 轨迹点数据结构

struct TrailPoint: Identifiable {
    let id = UUID()
    let location: CGPoint
    let timestamp: Date
}

// MARK: - 轨迹效果组件

struct PetTrailEffectView: View {
    // MARK: - Properties
    
    let trailPoints: [TrailPoint]
    let theme: PetTrailTheme
    let customColors: (String, String, String)
    let lineWidth: CGFloat
    let trailDuration: TimeInterval
    let showSparkles: Bool
    
    // MARK: - Initialization
    
    init(
        trailPoints: [TrailPoint],
        theme: PetTrailTheme = .defaultPink,
        customColors: (String, String, String) = ("FFC0CB", "D87093", "F5F5DC"),
        lineWidth: CGFloat = 4.0,
        trailDuration: TimeInterval = 2.0,
        showSparkles: Bool = true
    ) {
        self.trailPoints = trailPoints
        self.theme = theme
        self.customColors = customColors
        self.lineWidth = lineWidth
        self.trailDuration = trailDuration
        self.showSparkles = showSparkles
    }
    
    // MARK: - Body
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1/60)) { timeline in
            Canvas { context, size in
                drawTrail(in: context, at: timeline.date)
            }
        }
    }
    
    // MARK: - Drawing Methods
    
    private func drawTrail(in context: GraphicsContext, at date: Date) {
        let validPoints = filterValidPoints(at: date)
        guard validPoints.count > 1 else { return }
        
        // 绘制轨迹线
        drawTrailLine(in: context, points: validPoints)
        
        // 绘制闪烁点
        if showSparkles {
            drawSparkles(in: context, points: validPoints, at: date)
        }
    }
    
    private func filterValidPoints(at date: Date) -> [TrailPoint] {
        return trailPoints.filter { date.timeIntervalSince($0.timestamp) < trailDuration }
    }
    
    private func drawTrailLine(in context: GraphicsContext, points: [TrailPoint]) {
        var path = Path()
        path.move(to: points[0].location)
        
        for i in 1..<points.count {
            path.addLine(to: points[i].location)
        }
        
        let gradientColors = theme.colors(
            custom1: customColors.0,
            custom2: customColors.1,
            custom3: customColors.2
        )
        var colors = gradientColors
        colors.append(SwiftUI.Color.clear) // 渐变到透明
        
        context.stroke(
            path,
            with: .linearGradient(
                Gradient(colors: colors),
                startPoint: points.last!.location,
                endPoint: points.first!.location
            ),
            style: StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round,
                lineJoin: .round
            )
        )
    }
    
    private func drawSparkles(in context: GraphicsContext, points: [TrailPoint], at date: Date) {
        for point in points {
            let age = date.timeIntervalSince(point.timestamp)
            let opacity = 1.0 - (age / trailDuration)
            
            guard opacity > 0 else { continue }
            
            // 随机闪烁
            guard Int.random(in: 0...10) == 0 else { continue }
            
            let sparkleSize = Double.random(in: 2...5)
            let sparkleRect = CGRect(
                x: point.location.x - sparkleSize/2,
                y: point.location.y - sparkleSize/2,
                width: sparkleSize,
                height: sparkleSize
            )
            
            context.fill(
                Path(ellipseIn: sparkleRect),
                with: .color(.white.opacity(opacity))
            )
        }
    }
}

// MARK: - 轨迹效果修饰符

struct PetTrailEffectModifier: ViewModifier {
    let trailPoints: [TrailPoint]
    let theme: PetTrailTheme
    let customColors: (String, String, String)
    let isVisible: Bool
    
    func body(content: Content) -> some View {
        ZStack {
            if isVisible {
                PetTrailEffectView(
                    trailPoints: trailPoints,
                    theme: theme,
                    customColors: customColors
                )
            }
            content
        }
    }
}

// MARK: - View Extension

extension View {
    func petTrailEffect(
        trailPoints: [TrailPoint],
        theme: PetTrailTheme = .defaultPink,
        customColors: (String, String, String) = ("FFC0CB", "D87093", "F5F5DC"),
        isVisible: Bool = true
    ) -> some View {
        modifier(PetTrailEffectModifier(
            trailPoints: trailPoints,
            theme: theme,
            customColors: customColors,
            isVisible: isVisible
        ))
    }
}

// MARK: - 轨迹管理器

class PetTrailManager: ObservableObject {
    @Published var trailPoints: [TrailPoint] = []
    
    private let maxPoints: Int
    
    init(maxPoints: Int = 100) {
        self.maxPoints = maxPoints
    }
    
    func addPoint(_ location: CGPoint) {
        let point = TrailPoint(location: location, timestamp: Date())
        trailPoints.append(point)
        
        // 限制最大点数
        if trailPoints.count > maxPoints {
            trailPoints.removeFirst(trailPoints.count - maxPoints)
        }
    }
    
    func clear() {
        trailPoints.removeAll()
    }
    
    func cleanupExpired(duration: TimeInterval = 2.0) {
        let now = Date()
        trailPoints.removeAll { now.timeIntervalSince($0.timestamp) >= duration }
    }
}

// MARK: - 预览

#Preview {
    struct TrailPreview: View {
        @State private var trailPoints: [TrailPoint] = []
        @State private var selectedTheme: PetTrailTheme = .defaultPink
        
        var body: some View {
            ZStack {
                Color.black.opacity(0.1)
                
                PetTrailEffectView(
                    trailPoints: trailPoints,
                    theme: selectedTheme
                )
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let point = TrailPoint(
                            location: value.location,
                            timestamp: Date()
                        )
                        trailPoints.append(point)
                        
                        if trailPoints.count > 100 {
                            trailPoints.removeFirst(trailPoints.count - 100)
                        }
                    }
                    .onEnded { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            trailPoints.removeAll()
                        }
                    }
            )
            .overlay(alignment: .top) {
                Picker("主题".appLocalized, selection: $selectedTheme) {
                    ForEach(PetTrailTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .background(.ultraThinMaterial)
            }
        }
    }
    
    return TrailPreview()
}
