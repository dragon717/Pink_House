//
//  WidgetTutorialView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/20/26.
//

import SwiftUI

struct WidgetTutorialView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("添加桌面小组件")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.brown)
                    
                    Text("让心愿衣橱随时可见 ✨")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.top)
                
                // Steps
                TutorialStep(
                    number: 1,
                    title: "回到主屏幕",
                    description: "按下 Home 键或上滑回到 iPhone 主屏幕，长按空白处直到图标开始抖动。",
                    icon: "iphone.homebutton"
                )
                
                TutorialStep(
                    number: 2,
                    title: "搜索添加",
                    description: "点击左上角的“+”号，搜索“少女心愿衣橱”。",
                    icon: "plus.app"
                )
                
                TutorialStep(
                    number: 3,
                    title: "选择尺寸",
                    description: "左右滑动选择您喜欢的尺寸（小/中/大），然后点击“添加小组件”。",
                    icon: "square.resize"
                )
                
                TutorialStep(
                    number: 4,
                    title: "个性化配置",
                    description: "长按已添加的小组件，选择“编辑小组件”，可以切换【按月份】或【按系列】统计。",
                    icon: "slider.horizontal.3"
                )
                
                // Tips
                VStack(alignment: .leading, spacing: 12) {
                    Text("💡 小贴士")
                        .font(.headline)
                        .foregroundStyle(.pink)
                    
                    Text("小组件支持深色模式，且在 iOS 17+ 待机模式下有更好的显示效果。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.pink.opacity(0.1))
                .cornerRadius(12)
                
                Spacer()
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TutorialStep: View {
    let number: Int
    let title: String
    let description: String
    let icon: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.brown.opacity(0.1))
                    .frame(width: 32, height: 32)
                Text("\(number)")
                    .font(.headline)
                    .foregroundStyle(.brown)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Image(systemName: icon)
                        .foregroundStyle(.pink)
                }
                
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    WidgetTutorialView()
}
