
import SwiftUI
import Combine

struct AutoCompleteTextField: View {
    var title: String
    var placeholder: String
    @Binding var text: String
    var field: SuggestionField
    var isRequired: Bool = false
    var externalSearch: ((String) async -> [String])? = nil // 新增外部搜索回调
    
    @State private var suggestions: [String] = []
    @State private var showSuggestions: Bool = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            if !title.isEmpty {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    if isRequired {
                        Text("*")
                        .foregroundStyle(.red)
                    }
                }
                .padding(.leading, 4)
            }
            
            // TextField + Inline Suggestions
            VStack(spacing: 0) {
                HStack {
                    TextField(placeholder, text: $text)
                        .focused($isFocused)
                        .padding()
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(12)
                        .onChange(of: text) { _, newValue in
                            performSearch(query: newValue)
                        }
                        .onChange(of: isFocused) { _, focused in
                            if focused {
                                performSearch(query: text)
                            } else {
                                // 失去焦点时延迟隐藏
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    showSuggestions = false
                                }
                            }
                        }
                        .onSubmit {
                            if let first = suggestions.first, showSuggestions {
                                selectSuggestion(first)
                            }
                        }
                    
                    if !text.isEmpty {
                        Button(action: {
                            text = ""
                            suggestions = []
                            showSuggestions = false
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .padding(.trailing, 8)
                    }
                }
                
                // Inline Suggestions List (Not floating)
                if showSuggestions && !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(action: {
                                selectSuggestion(suggestion)
                            }) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(suggestion)
                                        .foregroundStyle(.primary)
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 16)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    if suggestion != suggestions.last {
                                        Divider()
                                            .padding(.leading, 16)
                                    }
                                }
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                            }
                        }
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showSuggestions)
        }
    }
    
    private func performSearch(query: String) {
        searchTask?.cancel()
        
        let currentToken = getCurrentToken(from: query)
        print("AutoComplete: performSearch query='\(query)', token='\(currentToken)'")
        
        // 用户输入1个及以上字符时触发补全建议 (放宽限制以便测试)
        if currentToken.isEmpty {
             self.suggestions = []
             self.showSuggestions = false
             return
        }
        
        searchTask = Task {
            // 防抖
            try? await Task.sleep(nanoseconds: 100 * 1_000_000) // 缩短防抖时间以便测试
            if Task.isCancelled { return }
            
            let results = SuggestionManager.shared.getSuggestions(for: field, query: currentToken)
            print("AutoComplete: results for '\(currentToken)': \(results)")
            
            await MainActor.run {
                self.suggestions = results
                self.showSuggestions = !results.isEmpty
            }
        }
    }
    
    private func getCurrentToken(from text: String) -> String {
        if field == .name || field == .brand || field == .condition {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // 取最后一个逗号后的部分
            // 注意：这里简单的取 split last 可能不准确，如果用户输入 "A, B,"，last是 nil (如果是 split(separator:))
            // 或者 split(omittingEmptySubsequences: false)
            let components = text.split(separator: ",", omittingEmptySubsequences: false)
            return String(components.last ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    private func selectSuggestion(_ suggestion: String) {
        if field == .name || field == .brand || field == .condition {
            text = suggestion
        } else {
            // 多值字段
            var components = text.split(separator: ",", omittingEmptySubsequences: false).map { String($0) }
            
            // 替换最后一个
            if !components.isEmpty {
                components.removeLast()
            }
            components.append(suggestion)
            
            // 重新组合，并在末尾添加逗号
            // 需求：选择后自动添加逗号
            text = components.joined(separator: ",") + ","
        }
        
        showSuggestions = false
        suggestions = []
    }
}
