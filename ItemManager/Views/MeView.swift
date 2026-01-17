
import SwiftUI

struct MeView: View {
    var body: some View {
        NavigationStack {
            List {
                // Section 1: Account Info
                Section {
                    HStack(spacing: 15) {
                        Image(systemName: "smiley")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 60)
                            .foregroundStyle(.gray)
                            .padding(10)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(Circle())
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("用户 6948")
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("189****6948")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.gray)
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                    
                    NavigationLink(destination: Text("退出登录")) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundStyle(.brown)
                                .frame(width: 24)
                            Text("退出登录")
                        }
                    }
                    
                    NavigationLink(destination: Text("注销账户")) {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.xmark")
                                .foregroundStyle(.red)
                                .frame(width: 24)
                            Text("注销账户")
                                .foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("账户信息")
                }
                
                // Section 2: Membership
                Section {
                    NavigationLink(destination: Text("开通会员")) {
                        HStack {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(.brown)
                                .font(.title2)
                                .frame(width: 40, height: 40)
                                .background(Color.brown.opacity(0.1))
                                .clipShape(Circle())
                            
                            VStack(alignment: .leading) {
                                Text("开通会员")
                                    .font(.headline)
                                    .foregroundStyle(.brown)
                                Text("解锁全部高级功能")
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listRowBackground(
                    LinearGradient(
                        colors: [Color.white, Color.pink.opacity(0.05)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                
                // Section 3: Feature Settings
                Section {
                    SettingsRow(icon: "slider.horizontal.3", title: "通用设置", subtitle: "语言、主题等")
                    SettingsRow(icon: "bell", title: "通知设置", subtitle: "管理通知提醒")
                    SettingsRow(icon: "lock", title: "隐私设置", subtitle: "数据与隐私")
                    SettingsRow(icon: "square.grid.2x2", title: "小组件设置", subtitle: "桌面小组件配置")
                    SettingsRow(icon: "tag", title: "标签设置", subtitle: "管理衣橱标签分类")
                } header: {
                    Label("功能设置", systemImage: "gearshape")
                }
            }
            .navigationTitle("我的")
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        NavigationLink(destination: Text(title)) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(.brown)
                    .font(.body)
                    .frame(width: 24)
                
                VStack(alignment: .leading) {
                    Text(title)
                        .font(.body)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

#Preview {
    MeView()
}
