//
//  AccountSyncView.swift
//  ItemManager
//
//  账号与同步页面 - 支持修改头像和用户名
//

import SwiftUI
import PhotosUI
import AuthenticationServices

struct AccountSyncView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var userProfileManager = UserProfileManager.shared
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var cloudManager = CloudSyncManager.shared
    
    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var showingImagePicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingSignOutAlert = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                LiquidBackground()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // 头像区域
                        avatarSection
                            .padding(.top, 20)
                        
                        // 用户名区域
                        nameSection
                        
                        // 登录状态区域
                        loginStatusSection
                        
                        // iCloud 同步区域
                        cloudSyncSection
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("账号与同步")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker { image in
                    if let image = image {
                        userProfileManager.updateUserAvatar(image)
                    }
                }
            }
            .alert("确认退出登录？", isPresented: $showingSignOutAlert) {
                Button("取消", role: .cancel) { }
                Button("退出", role: .destructive) {
                    authManager.signOut()
                    userProfileManager.clearUserProfile()
                }
            } message: {
                Text("退出登录后，您的本地数据不会丢失，但 iCloud 同步功能将暂停。")
            }
        }
    }
    
    // MARK: - 头像区域
    private var avatarSection: some View {
        VStack(spacing: 16) {
            // 头像
            ZStack {
                if let avatarData = userProfileManager.userAvatar,
                   let avatarImage = UIImage(data: avatarData) {
                    Image(uiImage: avatarImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.8), lineWidth: 4)
                        )
                        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
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
                            .frame(width: 120, height: 120)
                        
                        Text(userProfileManager.userName.prefix(1).uppercased())
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.8), lineWidth: 4)
                    )
                    .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
                }
                
                // 编辑按钮
                Button(action: { showingImagePicker = true }) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "camera.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.pink)
                    }
                }
                .offset(x: 40, y: 40)
            }
            
            Text("点击相机更换头像")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - 用户名区域
    private var nameSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("用户名")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                if isEditingName {
                    HStack {
                        TextField("输入用户名", text: $editedName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button("保存") {
                            userProfileManager.updateUserName(editedName)
                            isEditingName = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.pink)
                        
                        Button("取消") {
                            isEditingName = false
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    HStack {
                        Text(userProfileManager.userName)
                            .font(.title3)
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        Button(action: {
                            editedName = userProfileManager.userName
                            isEditingName = true
                        }) {
                            Image(systemName: "pencil")
                                .foregroundStyle(.pink)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 登录状态区域
    private var loginStatusSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Apple ID")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                if authManager.isAuthenticated {
                    // 已登录状态
                    HStack {
                        Image(systemName: "apple.logo")
                            .font(.title2)
                            .foregroundStyle(.primary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("已登录")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            
                            if !authManager.givenName.isEmpty {
                                Text(authManager.givenName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    
                    Button(action: { showingSignOutAlert = true }) {
                        Label("退出登录", systemImage: "arrow.right.circle")
                            .foregroundStyle(.red)
                    }
                    .padding(.top, 8)
                } else {
                    // 未登录状态
                    SignInWithAppleButton(
                        onRequest: { request in
                            request.requestedScopes = [.fullName, .email]
                        },
                        onCompletion: { result in
                            authManager.handleSignIn(result: result)
                            
                            // 同步用户名
                            if case .success(let authorization) = result,
                               let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                                userProfileManager.syncFromAppleID(
                                    givenName: credential.fullName?.givenName,
                                    familyName: credential.fullName?.familyName
                                )
                                userProfileManager.setAuthenticated(
                                    true,
                                    appleUserIdentifier: credential.user
                                )
                            }
                        }
                    )
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .cornerRadius(12)
                }
            }
        }
    }
    
    // MARK: - iCloud 同步区域
    private var cloudSyncSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("iCloud 同步")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                HStack {
                    Image(systemName: "icloud")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        if cloudManager.isSyncing {
                            Text("正在同步...")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        } else if let error = cloudManager.syncError {
                            Text("同步失败")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        } else if let date = cloudManager.lastCloudBackupDate {
                            Text("上次同步")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("未同步")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Text("登录后可启用 iCloud 同步")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if cloudManager.isSyncing {
                        ProgressView()
                    } else if authManager.isAuthenticated {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.gray)
                    }
                }
                
                if authManager.isAuthenticated {
                    Button(action: {
                        Task {
                            await cloudManager.syncNow()
                        }
                    }) {
                        Label("立即同步", systemImage: "arrow.clockwise")
                            .foregroundStyle(.pink)
                    }
                    .disabled(cloudManager.isSyncing)
                    .padding(.top, 8)
                }
            }
        }
    }
}

// MARK: - 预览
#Preview {
    AccountSyncView()
        .environment(ThemeManager())
}
