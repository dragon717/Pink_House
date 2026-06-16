import SwiftUI

// AI 内容举报弹窗
struct AIReportSheet: View {
    @Binding var selectedReason: AIReportReason?
    @Binding var description: String
    let onSubmit: () -> Void
    let onCancel: () -> Void
    
    @Environment(ThemeManager.self) private var themeManager
    
    var body: some View {
        NavigationStack {
            List {
                Section("举报原因".appLocalized) {
                    ForEach(AIReportReason.allCases, id: \.self) { reason in
                        Button(action: {
                            selectedReason = reason
                        }) {
                            HStack {
                                Image(systemName: reason.icon)
                                    .foregroundStyle(.pink)
                                    .frame(width: 24)
                                
                                Text(reason.rawValue.appLocalized)
                                    .foregroundStyle(.primary)
                                
                                Spacer()
                                
                                if selectedReason == reason {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.pink)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.gray.opacity(0.3))
                                }
                            }
                        }
                    }
                }
                
                Section("详细描述（可选）".appLocalized) {
                    TextEditor(text: $description)
                        .frame(minHeight: 80)
                        .overlay(alignment: .topLeading) {
                            if description.isEmpty {
                                Text("请描述您遇到的问题...".appLocalized)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                            }
                        }
                }
                
                Section {
                    Text("您的举报将帮助我们改进 AI 内容质量。我们不会将您的个人信息与举报内容关联。".appLocalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("举报 AI 内容".appLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消".appLocalized) {
                        onCancel()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("提交".appLocalized) {
                        onSubmit()
                    }
                    .disabled(selectedReason == nil)
                }
            }
        }
    }
}

#Preview {
    AIReportSheet(
        selectedReason: .constant(nil),
        description: .constant(""),
        onSubmit: {},
        onCancel: {}
    )
    .environment(ThemeManager())
}
