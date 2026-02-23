//
//  MoneyCountingView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/24/26.
//

import SwiftUI

struct MoneyCountingView: View {
    let amount: Decimal // 这里的amount应该是这一堆纸币的总额
    let denomination: Denomination // 纸币的面额
    let currency: CurrencyType // 货币类型
    let onComplete: () -> Void
    let onSkip: () -> Void
    
    @State private var remainingBills: Int
    @State private var flyingBills: [FlyingBill] = []
    @State private var lastInteractionTime: Date = Date()
    @State private var stackScale: CGFloat = 1.0
    
    // 纸币堆的随机偏移和旋转（只生成一次）
    @State private var pileOffsets: [CGSize] = []
    @State private var pileRotations: [Double] = []
    
    // 拖拽状态
    @State private var topBillOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    
    struct FlyingBill: Identifiable {
        let id = UUID()
        var offset: CGSize
        var rotation: Double
        var opacity: Double = 1.0
    }
    
    init(amount: Decimal, denomination: Denomination, currency: CurrencyType, onComplete: @escaping () -> Void, onSkip: @escaping () -> Void) {
        self.amount = amount
        self.denomination = denomination
        self.currency = currency
        self.onComplete = onComplete
        self.onSkip = onSkip
        
        // 计算需要的纸币数量 = 总额 / 面额
        let totalValue = NSDecimalNumber(decimal: amount).doubleValue
        let billVal = Double(denomination.value)
        let bills = billVal > 0 ? Int(totalValue / billVal) : 0
        
        _remainingBills = State(initialValue: max(1, bills)) // 至少展示1张以便体验
        
        // 初始化随机偏移和旋转
        var offsets: [CGSize] = []
        var rotations: [Double] = []
        for _ in 0..<10 { // 预生成足够多的随机数
            offsets.append(CGSize(width: Double.random(in: -5...5), height: Double.random(in: -5...5)))
            rotations.append(Double.random(in: -3...3))
        }
        _pileOffsets = State(initialValue: offsets)
        _pileRotations = State(initialValue: rotations)
    }
    
    var body: some View {
        ZStack {
            // 应用全局背景
            LiquidBackground()
                .ignoresSafeArea()
            
            // 背景遮罩（稍微降低透明度以便透出背景，同时保持点击交互）
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    // 点击背景也可以抽取（为了方便）
                    extractBill()
                }
            
            VStack {
                // 顶部状态栏
                HStack {
                    VStack(alignment: .leading) {
                        Text("剩余金额")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("¥\(remainingBills * denomination.value)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .monospacedDigit()
                    }
                    
                    Spacer()
                    
                    Button(action: onSkip) {
                        Text("跳过")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Capsule())
                            .foregroundStyle(.white)
                    }
                }
                .padding()
                .padding(.top, 40)
                
                Spacer()
                
                // 纸币交互区域
                ZStack {
                    // 底部占位文字，当钱数完时显示
                    if remainingBills == 0 {
                        Text("数钱数到手抽筋 🎉")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.white.opacity(0.8))
                            .transition(.scale.combined(with: .opacity))
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    onComplete()
                                }
                            }
                    }
                    
                    // 静态纸币堆（视觉厚度）
                    if remainingBills > 0 {
                        // 计算动态混乱度因子
                        // 10张以内因子为0.5（比较整齐）
                        // 100张以上因子为2.5（很乱）
                        // 线性插值
                        let messinessScale = 0.5 + min(2.0, Double(remainingBills) / 50.0)
                        
                        // 底部的纸币（除了最上面一张）
                        ForEach(1..<min(6, remainingBills), id: \.self) { index in
                            // 使用绝对索引确保纸币特征固定
                            let absoluteIndex = remainingBills - index
                            // 使用取模来复用随机数
                            let randomOffset = pileOffsets[absoluteIndex % pileOffsets.count]
                            let randomRotation = pileRotations[absoluteIndex % pileRotations.count]
                            
                            // 应用混乱度
                            let appliedOffset = CGSize(
                                width: randomOffset.width * messinessScale,
                                height: randomOffset.height * messinessScale
                            )
                            let appliedRotation = randomRotation * messinessScale
                            
                            BanknoteView(
                                denomination: denomination,
                                currency: currency
                            )
                            .frame(width: 160, height: 80)
                            .scaleEffect(2.0)
                            // 稍微缩小底层纸币，制造透视感
                            .scaleEffect(1.0 - CGFloat(index) * 0.02)
                            // 位置偏移：除了随机偏移，还有层级偏移
                            .offset(x: appliedOffset.width, y: CGFloat(index) * 2 + appliedOffset.height)
                            .rotationEffect(.degrees(appliedRotation))
                            .opacity(1.0 - Double(index) * 0.05)
                            .zIndex(Double(-index))
                        }
                        .transition(.opacity)
                        
                        // 最上面一张（可拖拽）
                        // 为了保持视觉连续性，最上面一张也需要应用基于 absoluteIndex 的随机偏移和旋转
                        // 这样当它从第二张变成第一张时，基础位置不会跳变
                        let topAbsoluteIndex = remainingBills
                        let topRandomOffset = pileOffsets[topAbsoluteIndex % pileOffsets.count]
                        let topRandomRotation = pileRotations[topAbsoluteIndex % pileRotations.count]
                        
                        let topAppliedOffset = CGSize(
                            width: topRandomOffset.width * messinessScale,
                            height: topRandomOffset.height * messinessScale
                        )
                        let topAppliedRotation = topRandomRotation * messinessScale
                        
                        BanknoteView(
                            denomination: denomination,
                            currency: currency
                        )
                        .frame(width: 160, height: 80)
                        .scaleEffect(2.0)
                        .rotationEffect(.degrees(topAppliedRotation + (isDragging ? Double(topBillOffset.width / 10) : 0))) // 叠加基础旋转和拖拽旋转
                        .offset(x: topAppliedOffset.width + topBillOffset.width, y: topAppliedOffset.height + topBillOffset.height) // 叠加基础偏移和拖拽偏移
                        .zIndex(1) // 确保在最上层
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    isDragging = true
                                    topBillOffset = value.translation
                                }
                                .onEnded { value in
                                    isDragging = false
                                    let translation = value.translation
                                    let distance = sqrt(pow(translation.width, 2) + pow(translation.height, 2))
                                    
                                    // 如果拖拽距离超过一定阈值（脱离中心点），则视为抽取
                                    if distance > 100 {
                                        extractBill(direction: translation)
                                        // 重置偏移，但因为extractBill会生成飞出动画并减少remainingBills，
                                        // 所以下一张纸币会立即补上来（或者显示动画衔接）
                                        topBillOffset = .zero
                                    } else {
                                        // 否则回弹
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                            topBillOffset = .zero
                                        }
                                    }
                                }
                        )
                        // 同时也支持点击（如果拖拽距离很小）
                        .onTapGesture {
                             extractBill()
                        }
                    }
                    
                    // 飞出的纸币动画
                    ForEach(flyingBills) { bill in
                        BanknoteView(
                            denomination: denomination,
                            currency: currency
                        )
                        .frame(width: 160, height: 80) // 显式设置尺寸
                        .scaleEffect(2.0)
                        .offset(bill.offset)
                        .rotationEffect(.degrees(bill.rotation))
                        .opacity(bill.opacity)
                        .zIndex(100) // 确保飞出的纸币在最上层
                    }
                    
                    // 顶层可交互区域（透明，覆盖在纸币堆上）
                    // 注意：现在交互直接绑定在最上层纸币上了，但为了更好的体验（比如拖拽边缘），
                    // 我们保留一个稍微大一点的透明区域，但只响应点击（如果点击空白处也算？）
                    // 或者，为了纯粹的拖拽体验，我们可以移除全屏的透明遮罩，只保留纸币的交互。
                    // 用户说：支持拖拽，脱离中心点后再松开。
                    // 之前的全屏透明层是用来拦截点击和滑动的。
                    // 既然现在纸币本身可拖拽，我们也许不需要那个全屏透明层了，
                    // 除非用户想在“非纸币区域”滑动也能数钱？
                    // 按照需求“点钞界面 钞票不规则叠放，支持拖拽”，通常意味着直接操作纸币。
                    // 为了防止误操作，保留点击背景空白处不触发数钱，或者点击背景也触发？
                    // 现在的逻辑是：
                    // 1. 最上层纸币支持 Drag & Tap
                    // 2. 背景支持 Tap (通过 ZStack 最底层的 Color.black.opacity(0.85).onTapGesture)
                    // 3. 移除之前的中间层透明遮罩，避免抢夺手势
                }
                .frame(height: 300)
                .scaleEffect(stackScale)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: stackScale)
                
                Spacer()
                
                // 提示文字
                if remainingBills > 0 {
                    Text("向上滑动或点击数钞")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.bottom, 40)
                }
            }
        }
    }
    
    private func extractBill(direction: CGSize = CGSize(width: 0, height: -500)) {
        guard remainingBills > 0 else { return }
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        // 减少数量
        remainingBills -= 1
        
        // 视觉缩放反馈
        stackScale = 0.95
        withAnimation {
            stackScale = 1.0
        }
        
        // 创建飞出的纸币
        // 归一化方向向量并放大
        let magnitude = sqrt(pow(direction.width, 2) + pow(direction.height, 2))
        let normalizedX = direction.width / (magnitude > 0 ? magnitude : 1)
        let normalizedY = direction.height / (magnitude > 0 ? magnitude : 1)
        
        // 随机一点偏移，让动画更自然
        let randomAngle = Double.random(in: -15...15)
        let endOffset = CGSize(
            width: normalizedX * 800 + Double.random(in: -100...100),
            height: normalizedY * 800 + Double.random(in: -100...100)
        )
        
        var newBill = FlyingBill(
            offset: .zero,
            rotation: 0
        )
        
        flyingBills.append(newBill)
        
        // 执行动画
        // 获取刚才添加的bill的index
        guard let index = flyingBills.indices.last else { return }
        
        withAnimation(.easeOut(duration: 0.6)) {
            flyingBills[index].offset = endOffset
            flyingBills[index].rotation = Double.random(in: -45...45)
            flyingBills[index].opacity = 0
        }
        
        // 清理
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if !flyingBills.isEmpty {
                flyingBills.removeFirst()
            }
        }
        
        // 如果数完了
        if remainingBills == 0 {
            let successGenerator = UINotificationFeedbackGenerator()
            successGenerator.notificationOccurred(.success)
        }
    }
}

