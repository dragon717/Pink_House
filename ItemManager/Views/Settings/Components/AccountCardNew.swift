//
//  AccountCardNew.swift
//  ItemManager
//
//  新的账户卡片 - 用于 MeView 网格
//

import SwiftUI

struct AccountCardNew: View {
    @StateObject private var userProfileManager = UserProfileManager.shared
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var cloudManager = CloudSyncManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    if let avatarData = userProfileManager.userAvatar,
                       let avatarImage = UIImage(data: avatarData) {
                        Image(uiImage: avatarImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    } else {
                        // 默认头像
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.pink.opacity(0.8), Color.purple.opacity(0.6)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 40, height: 40)
                            
                            Text(userProfileManager.userName.prefix(1).uppercased())
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                
                Spacer()
                
                // 右上角状态标
                if authManager.isAuthenticated {
                    if cloudManager.isSyncing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if cloudManager.syncError != nil {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    } else {
                        Image(systemName: "icloud.fill")
                            .foregroundStyle(.blue)
                    }
                } else {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .foregroundStyle(.gray)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(userProfileManager.userName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text(icloudStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(1.0, contentMode: .fill)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var icloudStatusText: String {
        if !authManager.isAuthenticated {
            return "点击登录以同步数据"
        }
        if cloudManager.isSyncing { return "正在同步..." }
        if cloudManager.syncError != nil { return "同步出错" }
        if let date = cloudManager.lastCloudBackupDate {
            return "备份于 " + date.formatted(date: .abbreviated, time: .shortened)
        }
        return "iCloud 就绪"
    }
}

// MARK: - 预览
#Preview {
    AccountCardNew()
        .frame(width: 150, height: 150)
        .padding()
        .background(Color.gray.opacity(0.1))
}
