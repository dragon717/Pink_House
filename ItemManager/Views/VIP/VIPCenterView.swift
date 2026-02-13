import SwiftUI

struct VIPCenterView: View {
    @ObservedObject var vipManager = VIPManager.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var showingPurchaseAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        ZStack {
            // Dark Theme Background
            Color(hex: "121212")
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 30) {
                    // Title
                    Text("会员中心")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.top)
                    
                    // Card
                    VIPCardView(
                        vipNumber: vipManager.vipNumber ?? "00000000",
                        expireDate: vipManager.vipExpireDate,
                        isVIP: vipManager.isVIP
                    )
                    .padding(.horizontal)
                    
                    // Privileges
                    VStack(alignment: .leading, spacing: 20) {
                        Text("会员特权")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(Color(hex: "FFD700"))
                        
                        privilegeRow(icon: "brain.head.profile", title: "智能对话", desc: "解锁基于 DeepSeek 的超强 AI 对话能力，萌宠变身贴心闺蜜。")
                        privilegeRow(icon: "mic.fill", title: "语音交互", desc: "支持自然语言语音对话，无需打字。")
                        privilegeRow(icon: "crown.fill", title: "尊贵身份", desc: "拥有独一无二的黑金靓号卡片。")
                    }
                    .padding()
                    .background(Color(hex: "1E1E1E"))
                    .cornerRadius(16)
                    .padding(.horizontal)
                    
                    // Purchase Action
                    VStack(spacing: 16) {
                        Button {
                            handlePurchase()
                        } label: {
                            HStack {
                                Text(vipManager.isVIP ? "续费会员" : "立即开通")
                                    .fontWeight(.bold)
                                Spacer()
                                Text("\(VIPManager.monthlyPrice) 喵币 / 月")
                                    .font(.subheadline)
                            }
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "FFD700"), Color(hex: "B8860B")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        
                        Text("喵币不足？前往商店充值")
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .underline()
                            .onTapGesture {
                                // TODO: Navigate to shop or show recharge sheet
                                // For now, maybe just show a hint
                            }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("关闭") {
                    dismiss()
                }
                .foregroundStyle(.white)
            }
        }
        .alert("会员订阅", isPresented: $showingPurchaseAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func privilegeRow(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color(hex: "FFD700"))
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
        }
    }
    
    private func handlePurchase() {
        let result = vipManager.purchaseVIP()
        alertMessage = result.message
        showingPurchaseAlert = true
    }
}

#Preview {
    VIPCenterView()
}
