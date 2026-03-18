import SwiftUI

struct PetChatHistorySearchSheet: View {
    private static let pageSize = 20
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    @Environment(\.dismiss) private var dismiss

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
                    Text("可复用 \(PetChatTranscriptStore.count(onlyUserMessages: true)) 条")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    Spacer()
                    Text(timeText(message.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
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

    private func reload() {
        isLoading = true
        page = 0
        let batch = PetChatTranscriptStore.query(
            keyword: keyword.trimmingCharacters(in: .whitespacesAndNewlines),
            page: page,
            pageSize: Self.pageSize,
            onlyUserMessages: true
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
            onlyUserMessages: true
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
