import SwiftUI
import SwiftData

private enum DreamDressScrollRange: Equatable {
  case top
  case middle
  case collapsed

  init(distance: CGFloat) {
    if distance <= 16 {
      self = .top
    } else if distance >= 88 {
      self = .collapsed
    } else {
      self = .middle
    }
  }
}

struct DreamDressDetectiveView: View {
  @State private var brandName = ""
  @State private var productName = ""
  @State private var productURL = ""
  @State private var phase: DreamDressDetectivePhase = .idle
  @State private var allCandidates: [DreamDressCandidate] = []
  @State private var candidates: [DreamDressCandidate] = []
  @State private var foundCount = 0
  @State private var cachedAt: Date?
  @State private var sourceUpdatedAt: Date?
  @State private var isFromCache = false
  @State private var errorMessage: String?
  @State private var isSearchCollapsed = false
  @State private var areUnverifiedCandidatesExpanded = false

  @ScaledMetric(relativeTo: .body) private var expandedSearchHeight: CGFloat = 326

  private var input: DreamDressDetectiveInput {
    DreamDressDetectiveInput(
      brandName: brandName,
      productName: productName,
      productURL: productURL
    )
  }

  private var isInvestigating: Bool {
    phase != .idle && phase != .completed
  }

  var body: some View {
    ZStack(alignment: .top) {
      detectiveScrollView
        .zIndex(0)

      expandedSearchChrome
        .opacity(isSearchCollapsed ? 0 : 1)
        .allowsHitTesting(!isSearchCollapsed)
        .accessibilityHidden(isSearchCollapsed)
        .animation(.easeOut(duration: 0.16), value: isSearchCollapsed)
        .zIndex(1)

      compactSearchChrome
        .opacity(isSearchCollapsed ? 1 : 0)
        .allowsHitTesting(isSearchCollapsed)
        .accessibilityHidden(!isSearchCollapsed)
        .animation(.easeOut(duration: 0.16), value: isSearchCollapsed)
        .zIndex(2)
    }
    .overlay {
      if isInvestigating {
        ShareLoadingOverlay(message: phase.rawValue)
      }
    }
  }

  @ViewBuilder
  private var detectiveScrollView: some View {
    if #available(iOS 18.0, *) {
      detectiveScrollViewBody
        .onScrollGeometryChange(for: DreamDressScrollRange.self) { geometry in
          DreamDressScrollRange(
            distance: geometry.contentOffset.y + geometry.contentInsets.top
          )
        } action: { _, range in
          handleScrollRange(range)
        }
    } else {
      detectiveScrollViewBody
    }
  }

  private var detectiveScrollViewBody: some View {
    ScrollView {
      if #unavailable(iOS 18.0) {
        ScrollViewThresholdObserver { distance in
          handleScrollRange(DreamDressScrollRange(distance: distance))
        }
        .frame(width: 1, height: 1)
        .opacity(0)
        .accessibilityHidden(true)
      }

      VStack(alignment: .leading, spacing: 16) {
        if let errorMessage {
          DreamDressDetectiveErrorCard(message: errorMessage)
        }

        if foundCount > 0 {
          DreamDressDetectiveResultsSection(
            foundCount: foundCount,
            allCandidates: allCandidates,
            validCandidates: candidates,
            cachedAt: cachedAt,
            sourceUpdatedAt: sourceUpdatedAt,
            isFromCache: isFromCache,
            areUnverifiedCandidatesExpanded: $areUnverifiedCandidatesExpanded,
            onRefresh: { startInvestigation(forceRefresh: true) }
          )
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, expandedSearchHeight)
      .padding(.bottom, 32)
    }
    .scrollIndicators(.hidden)
  }

  private var expandedSearchChrome: some View {
    VStack(alignment: .leading, spacing: 16) {
      DreamDressDetectiveHeader()
      DreamDressDetectiveInputSection(
        brandName: $brandName,
        productName: $productName,
        productURL: $productURL
      )
      DreamDressDetectiveActionSection(
        phase: phase,
        isInvestigating: isInvestigating,
        isEnabled: input.hasAnyValue,
        onInvestigate: { startInvestigation() }
      )
    }
    .padding(.horizontal, 20)
    .padding(.top, 8)
    .frame(height: expandedSearchHeight, alignment: .top)
    .accessibilityIdentifier("dreamDressDetective.expandedSearch")
  }

  private var compactSearchChrome: some View {
    GlassCard(cornerRadius: 18, padding: 10) {
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(Color.pink)

        VStack(alignment: .leading, spacing: 1) {
          Text("梦裙侦探".appLocalized)
            .font(.subheadline.weight(.semibold))
          Text(compactSearchSummary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        Spacer(minLength: 8)

        if foundCount > 0 {
          Text("\(foundCount)候选 · \(candidates.count)有效")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.pink)
        }
      }
    }
    .frame(height: 54)
    .padding(.horizontal, 20)
    .padding(.top, 6)
    .accessibilityIdentifier("dreamDressDetective.compactSearch")
  }

  private var compactSearchSummary: String {
    [brandName, productName]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first(where: { !$0.isEmpty })
      ?? (productURL.isEmpty ? "向下滑回顶部编辑搜索".appLocalized : productURL)
  }

  private func handleScrollRange(_ range: DreamDressScrollRange) {
    let shouldCollapse: Bool?
    switch range {
    case .top: shouldCollapse = false
    case .middle: shouldCollapse = nil
    case .collapsed: shouldCollapse = true
    }
    guard let shouldCollapse, shouldCollapse != isSearchCollapsed else { return }
    isSearchCollapsed = shouldCollapse
  }

  private func startInvestigation(forceRefresh: Bool = false) {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    Task { await investigate(forceRefresh: forceRefresh) }
  }

  private func investigate(forceRefresh: Bool) async {
    if !forceRefresh {
      allCandidates = []
      candidates = []
      foundCount = 0
      cachedAt = nil
      sourceUpdatedAt = nil
      isFromCache = false
    }
    errorMessage = nil
    areUnverifiedCandidatesExpanded = false
    phase = productURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? .planning
      : .fetching

    do {
      let result = try await DreamDressDetectiveService.shared.investigate(
        input,
        forceRefresh: forceRefresh
      )
      foundCount = result.foundCount
      allCandidates = result.allCandidates
      candidates = result.validCandidates
      cachedAt = result.cachedAt
      sourceUpdatedAt = result.sourceUpdatedAt
      isFromCache = result.isFromCache
      phase = .completed
    } catch {
      phase = .idle
      errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
  }

}

private struct DreamDressDetectiveHeader: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("梦裙侦探".appLocalized)
        .font(.system(.largeTitle, design: .serif).weight(.semibold))
      Text("输入品牌或商品，从淘宝、闲鱼、小红书、抖音等平台寻找洛丽塔服饰。".appLocalized)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }
}

private struct DreamDressDetectiveInputSection: View {
  @Binding var brandName: String
  @Binding var productName: String
  @Binding var productURL: String

  var body: some View {
    GlassCard(cornerRadius: 20, padding: 16) {
      VStack(alignment: .leading, spacing: 12) {
        TextField("品牌名（可选）".appLocalized, text: $brandName)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .accessibilityIdentifier("dreamDressDetective.brand")

        TextField("商品名（可选）".appLocalized, text: $productName)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .accessibilityIdentifier("dreamDressDetective.product")

        HStack {
          TextField("商品链接（可选）".appLocalized, text: $productURL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .textContentType(.URL)
            .accessibilityIdentifier("dreamDressDetective.url")

          PasteButton(payloadType: String.self) { values in
            if let value = values.first {
              productURL = value
            }
          }
          .labelStyle(.iconOnly)
          .accessibilityLabel("粘贴商品链接".appLocalized)
        }

        Text("三者至少填写一项；链接仅抓取公开 HTTPS 页面。".appLocalized)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct DreamDressDetectiveActionSection: View {
  let phase: DreamDressDetectivePhase
  let isInvestigating: Bool
  let isEnabled: Bool
  let onInvestigate: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button(action: onInvestigate) {
        HStack {
          if isInvestigating {
            ProgressView()
          }
          Text(isInvestigating ? phase.rawValue : "开始侦查".appLocalized)
            .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
      }
      .buttonStyle(.borderedProminent)
      .buttonBorderShape(.capsule)
      .disabled(!isEnabled || isInvestigating)
      .accessibilityIdentifier("dreamDressDetective.start")

      if phase != .idle {
        Text(phase.rawValue)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct DreamDressDetectiveErrorCard: View {
  let message: String

  var body: some View {
    GlassCard(cornerRadius: 16, padding: 14) {
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .font(.subheadline)
        .foregroundStyle(.orange)
    }
  }
}

private struct DreamDressDetectiveResultsSection: View {
  let foundCount: Int
  let allCandidates: [DreamDressCandidate]
  let validCandidates: [DreamDressCandidate]
  let cachedAt: Date?
  let sourceUpdatedAt: Date?
  let isFromCache: Bool
  @Binding var areUnverifiedCandidatesExpanded: Bool
  let onRefresh: () -> Void

  private var unverifiedCandidates: [DreamDressCandidate] {
    let validIDs = Set(validCandidates.map(\.id))
    return allCandidates.filter { !validIDs.contains($0.id) }
  }

  var body: some View {
    LazyVStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("找到 \(foundCount) 个候选，\(validCandidates.count) 个有效".appLocalized)
          .font(.system(.title3, design: .serif).weight(.semibold))
        Spacer(minLength: 4)
        Button(action: onRefresh) {
          Label("刷新".appLocalized, systemImage: "arrow.clockwise")
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .accessibilityIdentifier("dreamDressDetective.refresh")
      }

      Text("已验证商品优先展示；可展开查看图片未验证的候选。".appLocalized)
        .font(.caption)
        .foregroundStyle(.secondary)

      if let cachedAt {
        Label {
          Text(isFromCache ? "本地缓存 · \(cachedAt.formatted(date: .abbreviated, time: .shortened))" : "更新于 \(cachedAt.formatted(date: .abbreviated, time: .shortened))")
        } icon: {
          Image(systemName: isFromCache ? "internaldrive" : "checkmark.arrow.trianglehead.counterclockwise")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
      }

      if let sourceUpdatedAt {
        Text("平台数据时间：\(sourceUpdatedAt.formatted(date: .abbreviated, time: .shortened))")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      ForEach(validCandidates) { candidate in
        DreamDressDetectiveCandidateCard(candidate: candidate, isImageVerified: true)
      }

      if !unverifiedCandidates.isEmpty {
        Button {
          areUnverifiedCandidatesExpanded.toggle()
        } label: {
          HStack {
            Label(
              areUnverifiedCandidatesExpanded
                ? "收起未验证候选".appLocalized
                : "查看 \(unverifiedCandidates.count) 个未验证候选".appLocalized,
              systemImage: "shippingbox"
            )
            Spacer()
            Image(systemName: areUnverifiedCandidatesExpanded ? "chevron.up" : "chevron.down")
          }
          .font(.subheadline.weight(.semibold))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(Color.pink)
        .accessibilityIdentifier("dreamDressDetective.unverifiedCandidates")

        if areUnverifiedCandidatesExpanded {
          ForEach(unverifiedCandidates) { candidate in
            DreamDressDetectiveCandidateCard(candidate: candidate, isImageVerified: false)
          }
        }
      }
    }
  }
}

private struct DreamDressDetectiveCandidateCard: View {
  let candidate: DreamDressCandidate
  let isImageVerified: Bool
  @Environment(\.modelContext) private var modelContext
  @State private var isAddingToWardrobe = false
  @State private var wardrobeDraft: ClothingEditDraft?
  @State private var isShowingWardrobeCreation = false

  var body: some View {
    GlassCard(cornerRadius: 16, padding: 14) {
      VStack(alignment: .leading, spacing: 8) {
        candidateImage

        Text(candidate.title)
          .font(.headline)
          .foregroundStyle(.primary)

        if let brand = candidate.brand, !brand.isEmpty {
          Label(brand, systemImage: "tag")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        if let price = candidate.price, !price.isEmpty {
          Label(price, systemImage: "banknote")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        Label(candidate.availability.rawValue, systemImage: availabilitySystemImage)
          .font(.caption.weight(.semibold))
          .foregroundStyle(availabilityColor)
          .accessibilityIdentifier("dreamDressDetective.availability")

        Label(candidate.evidenceType.rawValue, systemImage: "checkmark.seal")
          .font(.caption)
          .foregroundStyle(.secondary)

        if !isImageVerified {
          Label("候选商品·图片未验证".appLocalized, systemImage: "photo.badge.exclamationmark")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
        }

        Link(destination: candidate.sourceURL) {
          Label(candidate.sourceURL.absoluteString, systemImage: "arrow.up.right.square")
            .font(.caption)
            .lineLimit(2)
        }

        Button {
          Task { await addToWardrobe() }
        } label: {
          Label(
            isAddingToWardrobe ? "准备图片…".appLocalized : "用此商品创建裙装".appLocalized,
            systemImage: "plus.circle.fill"
          )
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .disabled(isAddingToWardrobe)
        .accessibilityIdentifier("dreamDressDetective.addToWardrobe")
      }
    }
    .sheet(isPresented: $isShowingWardrobeCreation) {
      if let wardrobeDraft {
        NavigationStack {
          ClothingEditView(
            clothing: nil,
            continueFromDraft: false,
            activityDraft: wardrobeDraft
          )
        }
      }
    }
  }

  @ViewBuilder
  private var candidateImage: some View {
    if let imageURL = candidate.imageURL {
      AsyncImage(url: imageURL) { phase in
        switch phase {
        case .success(let image):
          image.resizable().scaledToFill()
        case .empty:
          ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
          imagePlaceholder
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: 190)
      .clipped()
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    } else {
      imagePlaceholder
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
  }

  private var imagePlaceholder: some View {
    Rectangle()
      .fill(Color.pink.opacity(0.1))
      .overlay {
        VStack(spacing: 6) {
          Image(systemName: "photo")
          Text("平台未提供公开商品图".appLocalized)
            .font(.caption2)
        }
        .foregroundStyle(.secondary)
      }
  }

  private var availabilitySystemImage: String {
    switch candidate.availability {
    case .available: "checkmark.circle.fill"
    case .unknown: "questionmark.circle"
    case .sold: "person.crop.circle.badge.checkmark"
    case .delisted: "arrow.down.circle.fill"
    case .unavailable: "xmark.circle"
    }
  }

  private var availabilityColor: Color {
    switch candidate.availability {
    case .available: .green
    case .unknown: .orange
    case .sold, .delisted, .unavailable: .secondary
    }
  }

  @MainActor
  private func addToWardrobe() async {
    isAddingToWardrobe = true
    let image: UIImage?
    if let imageURL = candidate.imageURL,
       let (data, response) = try? await URLSession.shared.data(from: imageURL),
       data.count <= 12_000_000,
       (response as? HTTPURLResponse)?.statusCode == 200 {
      image = UIImage(data: data)
    } else {
      image = nil
    }

    let imagePaths = image.flatMap { ImageManager.shared.saveImage($0, context: modelContext) }.map { [$0] } ?? []
    let amount = candidate.price.flatMap(Self.priceAmount) ?? 0
    let isJPY = candidate.price?.uppercased().contains("JPY") == true
    let now = Date()
    let draft = ClothingEditDraft(
      name: candidate.title,
      brandName: candidate.brand ?? "",
      types: Self.wardrobeType(for: candidate),
      colors: "",
      sizes: "",
      length: "",
      condition: "",
      accessories: "",
      imagePaths: imagePaths,
      isShared: false,
      originalPrice: isJPY ? 0 : amount,
      originalPriceJPY: isJPY ? amount : nil,
      originalPriceCurrencyCode: isJPY ? ClothingPriceCurrency.jpy.rawValue : ClothingPriceCurrency.cny.rawValue,
      priceTotal: 0,
      deposit: 0,
      balance: 0,
      accessoriesPrice: 0,
      stock: 1,
      purchaseDate: now,
      depositDate: now,
      isDepositPlan: false,
      reservationKindRawValue: ClothingReservationKind.owned.rawValue,
      finalPaymentDate: now,
      finalPaymentEndDate: now,
      note: "商品链接：\(candidate.sourceURL.absoluteString)\n检索状态：\(candidate.availability.rawValue)",
      accessoryList: []
    )
    isAddingToWardrobe = false
    wardrobeDraft = draft
    isShowingWardrobeCreation = true
  }

  private static func priceAmount(_ value: String) -> Double? {
    guard let range = value.range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression) else { return nil }
    return Double(value[range])
  }

  private static func wardrobeType(for candidate: DreamDressCandidate) -> String {
    if let category = candidate.category?.trimmingCharacters(in: .whitespacesAndNewlines), !category.isEmpty {
      return category.uppercased()
    }
    let title = candidate.title.lowercased()
    for token in ["jsk", "op", "sk"] where title.range(of: "(?<![a-z])\(token)(?![a-z])", options: .regularExpression) != nil {
      return token.uppercased()
    }
    if title.contains("袜") || title.contains("sock") { return "袜子" }
    if title.contains("包") || title.contains("bag") { return "包" }
    if title.contains("丝带") || title.contains("蝴蝶结") || title.contains("ribbon") { return "小物" }
    return "裙装"
  }
}

#Preview {
  DreamDressDetectiveView()
}
