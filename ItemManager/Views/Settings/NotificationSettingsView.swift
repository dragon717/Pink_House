//
//  NotificationSettingsView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/20/26.
//

import SwiftUI
import SwiftData
import UserNotifications

struct NotificationSettingsView: View {
    @AppStorage(NotificationManager.Keys.isDepositNotificationEnabled) private var isEnabled = false
    @State private var selectedDays: Set<Int> = []
    
    @State private var notificationTime: Date = Date()
    @State private var showPermissionAlert = false
    @State private var showTestScheduledAlert = false
    
    @Query(filter: #Predicate<Clothing> { $0.isDepositPlan == true }) private var depositPlans: [Clothing]
    
    var body: some View {
        Form {
            Section {
                Toggle("开启尾款天使提醒", isOn: $isEnabled)
                    .onChange(of: isEnabled) { oldValue, newValue in
                        handleSettingsChange()
                    }
            } header: {
                Text("尾款天使")
            } footer: {
                Text("开启后，将在到达预估补款时间时发送通知提醒。")
            }
            
            if isEnabled {
                Section {
                    ForEach([0, 1, 3, 7, 15, 30], id: \.self) { day in
                        Button {
                            toggleDay(day)
                        } label: {
                            HStack {
                                Text(dayText(for: day))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedDays.contains(day) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                    
                    DatePicker("每日提醒时间", selection: $notificationTime, displayedComponents: .hourAndMinute)
                        .onChange(of: notificationTime) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: NotificationManager.Keys.depositNotificationTime)
                            handleSettingsChange()
                        }
                } header: {
                    Text("提醒设置")
                } footer: {
                    Text("您可以选择多个提醒时间点。")
                }
            }
            
            // 测试结束，注释以便下次测试
            // Section {
            //     Button("发送测试通知 (5秒后)") {
            //         sendTestNotification()
            //     }
            // } header: {
            //     Text("调试")
            // }
        }
        .scrollContentBackground(.hidden)
        .background {
            LiquidBackground()
        }
        .navigationTitle("通知设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Load days
            selectedDays = Set(NotificationManager.shared.daysBeforeList)
            
            if let date = UserDefaults.standard.object(forKey: NotificationManager.Keys.depositNotificationTime) as? Date {
                notificationTime = date
            } else {
                // Default 9:00 AM
                notificationTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
            }
            
            checkPermissions()
        }
        .alert("需要通知权限", isPresented: $showPermissionAlert) {
            Button("去设置", role: .none) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("取消", role: .cancel) {
                isEnabled = false
            }
        } message: {
            Text("请在设置中允许 App 发送通知，以便接收补款提醒。")
        }
        .alert("测试通知已发送", isPresented: $showTestScheduledAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("请等待约 5 秒钟，通知将送达。\n如果在前台，您应该能看到顶部横幅。")
        }
    }
    
    private func toggleDay(_ day: Int) {
        if selectedDays.contains(day) {
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
        // Save immediately
        NotificationManager.shared.daysBeforeList = Array(selectedDays)
        handleSettingsChange()
    }
    
    private func dayText(for day: Int) -> String {
        switch day {
        case 0: return "当天"
        case 1: return "提前1天"
        case 3: return "提前3天"
        case 7: return "提前7天"
        case 15: return "提前15天"
        case 30: return "提前30天"
        default: return "提前\(day)天"
        }
    }

    private func checkPermissions() {
        Task {
            let status = await NotificationManager.shared.checkAuthorizationStatus()
            if status == .notDetermined {
                // Don't request immediately on appear, wait for user to enable toggle
            } else if status == .denied && isEnabled {
                showPermissionAlert = true
            }
        }
    }
    
    private func handleSettingsChange() {
        Task {
            // If enabling, check permission again
            if isEnabled {
                let status = await NotificationManager.shared.checkAuthorizationStatus()
                if status == .notDetermined {
                    let granted = try? await NotificationManager.shared.requestAuthorization()
                    if granted == false {
                        await MainActor.run {
                            isEnabled = false
                            showPermissionAlert = true
                        }
                        return
                    }
                } else if status == .denied {
                    await MainActor.run {
                        // isEnabled = false // Do not turn off, just warn
                        showPermissionAlert = true
                    }
                    return
                }
            }
            
            await NotificationManager.shared.rescheduleAllNotifications(clothings: depositPlans)
        }
    }
    
    private func sendTestNotification() {
        Task {
            let granted = try? await NotificationManager.shared.requestAuthorization()
            if granted == true {
                let content = UNMutableNotificationContent()
                content.title = "测试通知"
                content.body = "这是一条测试通知，证明通知权限已开启。"
                content.sound = .default
                
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
                
                try? await UNUserNotificationCenter.current().add(request)
                
                await MainActor.run {
                    showTestScheduledAlert = true
                }
            } else {
                showPermissionAlert = true
            }
        }
    }
}
