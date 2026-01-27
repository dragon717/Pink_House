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
    
    @Published var isAuthenticated: Bool = false
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
        
        switch result {
        case .success(let authorization):
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                let userId = appleIDCredential.user
                
                // 更新存储的用户 ID
                self.userIdentifier = userId
                self.isAuthenticated = true
                
                // 姓名和电子邮件仅在第一次登录时返回。
                // 我们应该将它们持久化保存。
                if let name = appleIDCredential.fullName {
                    if let given = name.givenName { self.givenName = given }
                    if let family = name.familyName { self.familyName = family }
                }
                
                if let email = appleIDCredential.email {
                    self.email = email
                }
                
                AppLogger.info("登录成功: \(userId)")
            }
        case .failure(let error):
            // 处理错误，忽略用户取消的情况
            if let asError = error as? ASAuthorizationError, asError.code == .canceled {
                AppLogger.info("用户取消了登录")
                return
            }
            
            self.errorMessage = "登录失败: \(error.localizedDescription)"
            AppLogger.error("登录失败: \(error.localizedDescription)")
        }
    }
}
