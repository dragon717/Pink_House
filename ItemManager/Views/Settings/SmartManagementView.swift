import SwiftUI

struct SmartManagementView: View {
    // 存储模型优先级，以逗号分隔的字符串存储
    @AppStorage("visualModelPriority") private var visualModelPriorityRaw: String = "Qwen3-VL,Apple Vision"
    @AppStorage("textModelPriority") private var textModelPriorityRaw: String = "DeepSeek,Minimax"
    
    // 语音设置
    @AppStorage("voiceModelId") private var voiceModelId: String = "Volcengine" // 默认火山引擎
    @AppStorage("voiceToneId") private var voiceToneId: String = "SweetGirl" // 默认甜美女生
    
    @State private var visualModels: [String] = []
    @State private var textModels: [String] = []
    
    var body: some View {
        Form {
            Section {
                Text("拖拽可调整模型优先级，排名第一的模型将被优先使用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            
            Section("视觉识别模型优先级 (拖拽排序)") {
                List {
                    ForEach(visualModels, id: \.self) { model in
                        HStack {
                            Text(model)
                            Spacer()
                            if model == visualModels.first {
                                Text("当前首选")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                    .padding(.horizontal, 6)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.gray)
                        }
                    }
                    .onMove(perform: moveVisualModel)
                }
            }
            
            Section("文字思考模型优先级 (拖拽排序)") {
                List {
                    ForEach(textModels, id: \.self) { model in
                        HStack {
                            Text(model)
                            Spacer()
                            if model == textModels.first {
                                Text("当前首选")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                    .padding(.horizontal, 6)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.gray)
                        }
                    }
                    .onMove(perform: moveTextModel)
                }
            }
            
            Section("语音合成设置") {
                Picker("语音模型", selection: $voiceModelId) {
                    Text("火山引擎 (Volcengine)").tag("Volcengine")
                    Text("Apple 语音服务").tag("Apple")
                }
                
                Picker("音色选择", selection: $voiceToneId) {
                    Text("甜美女生 (灿灿)").tag("SweetGirl")
                    Text("温柔姐姐 (亲切)").tag("GentleSister")
                    Text("活泼少女 (元气)").tag("LivelyGirl")
                    Text("高冷御姐 (成熟)").tag("CoolLady")
                }
            }
            
            Section {
                NavigationLink("API Key 配置说明") {
                    APIKeyInfoView()
                }
            }
        }
        .navigationTitle("智能管理")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadPriorities()
        }
        .scrollContentBackground(.hidden)
        .background {
            LiquidBackground()
        }
    }
    
    private func loadPriorities() {
        visualModels = visualModelPriorityRaw.split(separator: ",").map { String($0) }
        textModels = textModelPriorityRaw.split(separator: ",").map { String($0) }
        
        // 确保默认值存在
        if visualModels.isEmpty {
            visualModels = ["Qwen3-VL", "Apple Vision"]
            saveVisualPriority()
        }
        
        // 确保必要的模型都在列表中
        let requiredTextModels = ["DeepSeek", "Minimax"]
        var needSave = false
        
        for model in requiredTextModels {
            if !textModels.contains(model) {
                textModels.append(model)
                needSave = true
            }
        }
        
        // 移除不再支持的模型 (Gemini, Doubao)
        let supportedModels = Set(requiredTextModels)
        let originalCount = textModels.count
        textModels.removeAll { !supportedModels.contains($0) }
        if textModels.count != originalCount {
            needSave = true
        }
        
        if textModels.isEmpty {
            textModels = ["DeepSeek", "Minimax"]
            needSave = true
        }
        
        if needSave {
            saveTextPriority()
        }
    }
    
    private func moveVisualModel(from source: IndexSet, to destination: Int) {
        visualModels.move(fromOffsets: source, toOffset: destination)
        saveVisualPriority()
    }
    
    private func moveTextModel(from source: IndexSet, to destination: Int) {
        textModels.move(fromOffsets: source, toOffset: destination)
        saveTextPriority()
    }
    
    private func saveVisualPriority() {
        visualModelPriorityRaw = visualModels.joined(separator: ",")
    }
    
    private func saveTextPriority() {
        textModelPriorityRaw = textModels.joined(separator: ",")
        // 发送通知，告知其他模块配置已更新
        NotificationCenter.default.post(name: Notification.Name("AISettingsChanged"), object: nil)
    }
}

struct APIKeyInfoView: View {
    var body: some View {
        List {
            Section("配置文件") {
                Text("API Key 请配置在项目目录下的:")
                Text("ItemManager/GenerativeAI-Info.plist")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            
            Section("支持的 Key") {
                VStack(alignment: .leading) {
                    Text("QWEN_API_KEY")
                        .font(.headline)
                    Text("用于 Qwen3-VL 视觉识别")
                        .font(.caption)
                }
                
                VStack(alignment: .leading) {
                    Text("DS_API_KEY")
                        .font(.headline)
                    Text("用于 DeepSeek 文字思考")
                        .font(.caption)
                }
                
                VStack(alignment: .leading) {
                    Text("MINIMAX_API_KEY")
                        .font(.headline)
                    Text("用于 Minimax 文字思考")
                        .font(.caption)
                }
            }
        }
        .navigationTitle("配置说明")
        .scrollContentBackground(.hidden)
        .background {
            LiquidBackground()
        }
    }
}
