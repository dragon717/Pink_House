//
//  AuthenticationManager.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/28/26.
//

import Foundation
import AuthenticationServices
import SwiftUI
import Combine

@MainActor
class AuthenticationManager: NSObject, ObservableObject {
    static let shared = AuthenticationManager()
    
    @AppStorage("userIdentifier") var userIdentifier: String = ""
    @AppStorage("userGivenName") var givenName: String = ""
    @AppStorage("userFamilyName") var familyName: String = ""
    @AppStorage("userEmail") var email: String = ""
    
    // 缓存用户信息，用于在 Apple 不返回姓名时（非首次登录）恢复数据
    @AppStorage("cachedUserIdentifier") private var cachedUserIdentifier: String = ""
    @AppStorage("cachedGivenName") private var cachedGivenName: String = ""
    @AppStorage("cachedFamilyName") private var cachedFamilyName: String = ""
    @AppStorage("cachedEmail") private var cachedEmail: String = ""
    
    @Published var isAuthenticated: Bool = false
    @Published var isLoggingIn: Bool = false
    @Published var errorMessage: String?
    
    override private init() {
        super.init()
        checkCredentialState()
    }
    
    // 检查用户的 Apple ID 凭证状态
    func checkCredentialState() {
        // 清除之前的错误信息
        errorMessage = nil
        
        guard !userIdentifier.isEmpty else {
            isAuthenticated = false
            return
        }
        
        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: userIdentifier) { [weak self] state, error in
            DispatchQueue.main.async {
                switch state {
                case .authorized:
                    self?.isAuthenticated = true
                case .revoked, .notFound, .transferred:
                    self?.isAuthenticated = false
                    // 可选：如果需要，可以在此处清除存储的数据，但在重新登录场景下保留数据可能更好
                @unknown default:
                    self?.isAuthenticated = false
                }
            }
        }
    }
    
    func signOut() {
        userIdentifier = ""
        givenName = ""
        familyName = ""
        email = ""
        isAuthenticated = false
        errorMessage = nil
    }
    
    // MARK: - 登录流程
    
    func handleSignIn(result: Result<ASAuthorization, Error>) {
        // 重置错误信息
        errorMessage = nil
        isLoggingIn = true
        
        switch result {
        case .success(let authorization):
            handleAuthorization(authorization)
        case .failure(let error):
            isLoggingIn = false
            // 处理错误，忽略用户取消的情况
            if let asError = error as? ASAuthorizationError, asError.code == .canceled {
                AppLogger.info("用户取消了登录")
                return
            }
            
            self.errorMessage = "登录失败: \(error.localizedDescription)"
            AppLogger.error("登录失败: \(error.localizedDescription)")
        }
    }
    
    private func handleAuthorization(_ authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            self.isLoggingIn = false
            self.errorMessage = "登录失败: 无效的凭证"
            return
        }
        
        let userId = appleIDCredential.user
        
        // 获取 Identity Token 用于后端验证
        guard let identityTokenData = appleIDCredential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            self.isLoggingIn = false
            self.errorMessage = "登录失败: 无法获取身份令牌"
            return
        }
        
        Task {
            do {
                // 执行网络验证
                try await verifyUserWithBackend(identityToken: identityToken, userIdentifier: userId)
                
                // 验证成功，保存用户信息
                await MainActor.run {
                    self.saveUserInfo(credential: appleIDCredential)
                    self.isAuthenticated = true
                    self.isLoggingIn = false
                    AppLogger.info("登录成功: \(userId)")
                }
            } catch {
                await MainActor.run {
                    self.isLoggingIn = false
                    self.errorMessage = "登录验证失败: \(error.localizedDescription)"
                    AppLogger.error("登录验证失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func saveUserInfo(credential: ASAuthorizationAppleIDCredential) {
        let userId = credential.user
        self.userIdentifier = userId
        
        // 姓名和电子邮件仅在第一次登录时返回。
        // 我们应该将它们持久化保存。
        if let name = credential.fullName {
            if let given = name.givenName {
                self.givenName = given
                self.cachedGivenName = given
            }
            if let family = name.familyName {
                self.familyName = family
                self.cachedFamilyName = family
            }
        } else if userId == self.cachedUserIdentifier {
            // 如果是同一个用户且 Apple 没返回名字，尝试从缓存恢复
            if self.givenName.isEmpty { self.givenName = self.cachedGivenName }
            if self.familyName.isEmpty { self.familyName = self.cachedFamilyName }
        }
        
        if let email = credential.email {
            self.email = email
            self.cachedEmail = email
        } else if userId == self.cachedUserIdentifier {
            // 尝试从缓存恢复邮箱
            if self.email.isEmpty { self.email = self.cachedEmail }
        }
        
        // 更新缓存的 ID
        self.cachedUserIdentifier = userId
    }
    
    // 模拟后端验证接口
    private func verifyUserWithBackend(identityToken: String, userIdentifier: String) async throws {
        // 模拟网络延迟
        try await Task.sleep(nanoseconds: 1 * 1_000_000_000) // 1秒
        
        // 模拟验证逻辑
        // 在实际项目中，这里应该发送 HTTP 请求将 identityToken 发送给后端
        // 后端验证 token 的签名和有效期
        
        AppLogger.info("模拟后端验证成功: Token长度 \(identityToken.count)")
        
        // 如果验证失败，抛出错误
        // throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "后端验证失败"])
    }

}
