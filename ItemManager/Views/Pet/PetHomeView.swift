import SwiftUI

struct PetHomeView: View {
    @StateObject private var viewModel = PetViewModel()
    @Environment(\.scenePhase) var scenePhase
    
    var body: some View {
        ZStack {
            // 背景
            Color("Background", bundle: nil) // 假设有背景色，如果没有则使用系统背景
                .ignoresSafeArea()
            
            VStack {
                // 顶部状态栏
                HStack(spacing: 20) {
                    StatusView(icon: "fork.knife", value: viewModel.status.hunger, color: .orange)
                    StatusView(icon: "shower.fill", value: viewModel.status.hygiene, color: .blue)
                }
                .padding(.top, 50)
                .padding(.horizontal)
                
                Spacer()
                
                // 中间萌宠区域
                ZStack {
                    PetVideoPlayer(
                        videoName: viewModel.currentState.videoFileName,
                        isLooping: viewModel.currentState.isLooping,
                        onFinished: {
                            viewModel.onAnimationFinished()
                        }
                    )
                    .frame(height: 400) // 根据视频比例调整
                    .clipShape(RoundedRectangle(cornerRadius: 20)) // 可选：圆角
                }
                
                Spacer()
                
                // 底部操作栏
                HStack(spacing: 40) {
                    ActionButton(title: "喂食", icon: "fork.knife") {
                        viewModel.feed()
                    }
                    .disabled(viewModel.currentState != .idle)
                    .opacity(viewModel.currentState != .idle ? 0.6 : 1.0)
                    
                    ActionButton(title: "清洁", icon: "shower.fill") {
                        viewModel.clean()
                    }
                    .disabled(viewModel.currentState != .idle)
                    .opacity(viewModel.currentState != .idle ? 0.6 : 1.0)
                }
                .padding(.bottom, 50)
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                viewModel.saveStatus()
            } else if newPhase == .active {
                // 可以在这里重新计算衰减，虽然 init 里已经做了
            }
        }
    }
}

// MARK: - Subviews

struct StatusView: View {
    let icon: String
    let value: Double
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .cornerRadius(5)
                    
                    Rectangle()
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(value / 100.0))
                        .cornerRadius(5)
                }
            }
            .frame(height: 10)
        }
        .padding(8)
        .background(Color.white.opacity(0.8))
        .cornerRadius(10)
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack {
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .frame(width: 60, height: 60)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(radius: 3)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
    }
}

#Preview {
    PetHomeView()
}
