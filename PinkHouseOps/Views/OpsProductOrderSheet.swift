import SwiftUI
import SharedCatalog

/// 已提交/已发布商品同样可调整排序；工作副本只在保存成功后写回。
struct OpsProductOrderSheet: View {
    @ObservedObject var workspace: OpsWorkspace
    let seriesID: String
    private let draftID: String
    private let original: [CatalogProduct]
    @State private var categories: [String]
    @State private var orders: [String: [String]]
    @State private var selectedCategory: String?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(workspace: OpsWorkspace, seriesID: String) {
        self.workspace = workspace; self.seriesID = seriesID
        draftID = workspace.draft?.id ?? ""
        let products = CatalogProductOrdering.ordered(workspace.catalog.products.filter {
            $0.seriesID == seriesID && $0.archivedAt == nil
        })
        original = products
        let groups = CatalogProductOrdering.categories(in: products)
        _categories = State(initialValue: groups)
        _orders = State(initialValue: Dictionary(grouping: products, by: \.category).mapValues { $0.map(\.id) })
        _selectedCategory = State(initialValue: groups.first)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("调整商品排序 · " + workspace.seriesName(for: seriesID)).font(.title3.bold())
            Text("左侧调整类型顺序，右侧调整该类型内的商品。可拖动，也可用上下箭头；保存后自动同步。")
                .font(.callout).foregroundStyle(.secondary)
            HSplitView {
                VStack(alignment: .leading) {
                    Text("类型顺序").font(.headline)
                    List(selection: $selectedCategory) {
                        ForEach(categories, id: \.self) { category in
                            HStack {
                                Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                                Text(category.isEmpty ? "未分类" : category)
                                Spacer()
                                moveButtons(id: category, values: categories) { categories = $0 }
                            }.tag(category)
                        }.onMove { categories.move(fromOffsets: $0, toOffset: $1) }
                    }.listStyle(.inset)
                }.frame(minWidth: 220, idealWidth: 250)
                VStack(alignment: .leading) {
                    Text("商品顺序").font(.headline)
                    if let category = selectedCategory {
                        List {
                            ForEach(orders[category] ?? [], id: \.self) { id in
                                HStack {
                                    Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                                    Text(original.first(where: { $0.id == id })?.name ?? id).lineLimit(2)
                                    Spacer()
                                    moveButtons(id: id, values: orders[category] ?? []) { orders[category] = $0 }
                                }.padding(.vertical, 4)
                            }.onMove { source, destination in orders[category]?.move(fromOffsets: source, toOffset: destination) }
                        }.listStyle(.inset)
                    }
                }.frame(minWidth: 380)
            }
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                Text("仅调整顺序，商品图片、价格和名称保持原值。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存并同步") {
                    let ids = categories.flatMap { orders[$0] ?? [] }
                    if workspace.saveProductDisplayOrder(seriesID: seriesID, orderedIDs: ids,
                        expectedProducts: original, expectedDraftID: draftID) { dismiss() }
                    else { error = workspace.lastError ?? "保存失败，请重试。" }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(original.isEmpty)
            }
        }.padding(20).frame(minWidth: 780, idealWidth: 900, minHeight: 540, idealHeight: 620)
    }

    private func moveButtons(id: String, values: [String], update: @escaping ([String]) -> Void) -> some View {
        HStack(spacing: 6) {
            Button { move(id, delta: -1, values: values, update: update) } label: { Image(systemName: "arrow.up") }
                .help("上移").accessibilityLabel("上移 " + label(for: id))
                .disabled(values.first == id)
            Button { move(id, delta: 1, values: values, update: update) } label: { Image(systemName: "arrow.down") }
                .help("下移").accessibilityLabel("下移 " + label(for: id))
                .disabled(values.last == id)
        }.buttonStyle(.borderless)
    }

    private func label(for id: String) -> String { original.first(where: { $0.id == id })?.name ?? id }

    private func move(_ id: String, delta: Int, values: [String], update: ([String]) -> Void) {
        guard let index = values.firstIndex(of: id), values.indices.contains(index + delta) else { return }
        var result = values
        result.swapAt(index, index + delta)
        update(result)
    }
}
