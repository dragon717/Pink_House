//
//  UserProfileManager.swift
//  ItemManager
//
//  用户资料管理器 - 管理用户头像和用户名
//  支持 Apple ID 登录后独立记录头像和用户名
//

import Foundation
import SwiftUI
import Combine

@MainActor
class UserProfileManager: ObservableObject {
    static let shared = UserProfileManager()
    
    // MARK: - Published Properties
    @Published var userName: String = ""
    @Published var userAvatar: Data?
    @Published var isAuthenticated: Bool = false
    
    // MARK: - UserDefaults Keys
    private let userNameKey = "userProfileName"
    private let userAvatarKey = "userProfileAvatar"
    private let isAuthenticatedKey = "userProfileIsAuthenticated"
    private let appleUserIdentifierKey = "userProfileAppleIdentifier"
    
    // MARK: - Initialization
    private init() {
        loadUserProfile()
    }
    
    // MARK: - Load/Save
    func loadUserProfile() {
        userName = UserDefaults.standard.string(forKey: userNameKey) ?? ""
        userAvatar = UserDefaults.standard.data(forKey: userAvatarKey)
        isAuthenticated = UserDefaults.standard.bool(forKey: isAuthenticatedKey)
        
        // 如果没有设置用户名，使用默认名称
        if userName.isEmpty {
            userName = "用户"
        }
    }
    
    private func saveUserProfile() {
        UserDefaults.standard.set(userName, forKey: userNameKey)
        UserDefaults.standard.set(isAuthenticated, forKey: isAuthenticatedKey)
        if let avatar = userAvatar {
            UserDefaults.standard.set(avatar, forKey: userAvatarKey)
        } else {
            UserDefaults.standard.removeObject(forKey: userAvatarKey)
        }
    }
    
    // MARK: - Public Methods
    
    /// 更新用户名
    func updateUserName(_ name: String) {
        userName = name.isEmpty ? "用户" : name
        saveUserProfile()
    }
    
    /// 更新用户头像
    func updateUserAvatar(_ imageData: Data?) {
        userAvatar = imageData
        saveUserProfile()
    }
    
    /// 更新用户头像（从 UIImage）
    func updateUserAvatar(_ image: UIImage?) {
        if let image = image {
            // 压缩图片以节省存储空间
            let maxSize: CGFloat = 200
            let resizedImage = image.resized(toMaxDimension: maxSize)
            userAvatar = resizedImage.jpegData(compressionQuality: 0.8)
        } else {
            userAvatar = nil
        }
        saveUserProfile()
    }
    
    /// 设置登录状态
    func setAuthenticated(_ authenticated: Bool, appleUserIdentifier: String? = nil) {
        isAuthenticated = authenticated
        if let identifier = appleUserIdentifier {
            UserDefaults.standard.set(identifier, forKey: appleUserIdentifierKey)
        }
        saveUserProfile()
    }
    
    /// 获取 Apple User Identifier
    func getAppleUserIdentifier() -> String? {
        return UserDefaults.standard.string(forKey: appleUserIdentifierKey)
    }
    
    /// 从 Apple ID 登录信息同步用户名
    func syncFromAppleID(givenName: String?, familyName: String?) {
        // 如果当前用户名为空或默认值，则使用 Apple ID 的名称
        if userName == "用户" || userName.isEmpty {
            let name = [givenName, familyName].compactMap { $0 }.joined(separator: " ")
            if !name.isEmpty {
                userName = name
                saveUserProfile()
            }
        }
    }
    
    /// 清除用户资料（注销时使用）
    func clearUserProfile() {
        userName = "用户"
        userAvatar = nil
        isAuthenticated = false
        UserDefaults.standard.removeObject(forKey: userNameKey)
        UserDefaults.standard.removeObject(forKey: userAvatarKey)
        UserDefaults.standard.removeObject(forKey: isAuthenticatedKey)
        UserDefaults.standard.removeObject(forKey: appleUserIdentifierKey)
    }
    
    /// 重置为默认设置
    func resetToDefault() {
        userName = "用户"
        userAvatar = nil
        saveUserProfile()
    }
}


