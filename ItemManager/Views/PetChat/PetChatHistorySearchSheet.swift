import SwiftUI
import SwiftData

struct PetChatHistorySearchSheet: View {
    private static let pageSize = 20
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Clothing> { $0.deletedAt == nil }) var clothings: [Clothing]

    @State private var keyword = ""
    @State private var page = 0
    @State private var results: [PetChatMessage] = []
    @State private var isLoading = false
    @State private var hasMore = true

    let onReuseQuery: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索历史消息", text: $keyword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit {
                            reload()
                        }

                    if !keyword.isEmpty {
                        Button {
                            keyword = ""
                            reload()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                if results.isEmpty, !isLoading {
                    VStack(spacing: 8) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("没有匹配的历史消息")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("试试换个关键词，或者直接查看最新消息")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    List {
                        ForEach(results) { message in
                            historyRow(message)
                        }

                        if hasMore {
                            Button {
                                loadMore()
                            } label: {
                                HStack {
                                    Spacer()
                                    if isLoading {
                                        ProgressView()
                                    } else {
                                        Text("加载更多")
                                    }
                                    Spacer()
                                }
                            }
                            .disabled(isLoading)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("历史消息查询")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    let userCount = PetChatTranscriptStore.count(onlyUserMessages: true, clothings: clothings)
                    let totalCount = PetChatTranscriptStore.count(onlyUserMessages: false, clothings: clothings)
                    Button {
                        reload()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption2)
                            Text("\(userCount)/\(totalCount)条")
                                .font(.caption)
                        }
                        .foregroundStyle(.pink)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear {
                reload()
            }
        }
    }

    private func historyRow(_ message: PetChatMessage) -> some View {
        Button {
            if message.isUser {
                onReuseQuery(message.text)
                dismiss()
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: message.isUser ? "person.fill" : "pawprint.fill")
                        .font(.caption2)
                        .foregroundStyle(message.isUser ? .pink : .orange)
                    Text(message.isUser ? "你" : "萌宠")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if message.isAIGenerated {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.orange.opacity(0.8))
                    }
                    Spacer()
                    Text(timeText(message.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                // 显示嵌入式交互界面标签（萌宠回复中的 widgets）
                if let widgets = message.widgets, !widgets.isEmpty {
                    widgetsPreview(widgets)
                }

                if message.isUser {
                    Text("点按可复用这条提问")
                        .font(.caption2)
                        .foregroundStyle(.pink.opacity(0.9))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!message.isUser)
    }

    @ViewBuilder
    private func widgetsPreview(_ widgets: [PetWidgetData]) -> some View {
        HStack(spacing: 4) {
            ForEach(widgets.prefix(3)) { widget in
                widgetLabel(for: widget)
            }
        }
    }

    private func widgetLabel(for widget: PetWidgetData) -> some View {
        let (icon, label) = widgetTypeInfo(widget)
        return HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2)
        }
        .foregroundStyle(.pink.opacity(0.8))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.pink.opacity(0.08))
        .clipShape(Capsule())
    }

    private func widgetTypeInfo(_ widget: PetWidgetData) -> (icon: String, label: String) {
        switch widget.type {
        case .quickOptions:
            return ("rectangle.grid.1x2", "选项")
        case .weatherCard:
            return ("cloud.sun", "天气")
        case .container:
            return ("square.stack", "容器")
        case .insightCard:
            return ("lightbulb", "洞察")
        case .statusPanel:
            return ("chart.bar", "状态")
        case .currencyPanel:
            return ("dollarsign.circle", "货币")
        case .inventoryPanel:
            return ("backpack", "背包")
        case .shopPanel:
            return ("cart", "商店")
        case .moneyCounter:
            return ("banknote", "数钱")
        case .divinationPanel:
            return ("wand.and.stars", "求签")
        case .unknown:
            return ("questionmark.circle", "其他")
        }
    }

    private func reload() {
        isLoading = true
        page = 0
        // 查询所有消息（用户消息 + 萌宠回复），以显示完整的对话上下文和 widgets
        let batch = PetChatTranscriptStore.query(
            keyword: keyword.trimmingCharacters(in: .whitespacesAndNewlines),
            page: page,
            pageSize: Self.pageSize,
            onlyUserMessages: false,
            clothings: clothings
        )
        results = batch
        hasMore = batch.count == Self.pageSize
        isLoading = false
    }

    private func loadMore() {
        guard !isLoading else { return }
        isLoading = true
        let nextPage = page + 1
        let batch = PetChatTranscriptStore.query(
            keyword: keyword.trimmingCharacters(in: .whitespacesAndNewlines),
            page: nextPage,
            pageSize: Self.pageSize,
            onlyUserMessages: false,
            clothings: clothings
        )
        if batch.isEmpty {
            hasMore = false
        } else {
            page = nextPage
            results.append(contentsOf: batch)
            hasMore = batch.count == Self.pageSize
        }
        isLoading = false
    }

    private func timeText(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }
}
