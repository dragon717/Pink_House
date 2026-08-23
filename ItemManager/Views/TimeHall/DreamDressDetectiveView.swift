import SwiftUI
import SwiftData
import WebKit

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

enum DreamDressResultFilter: String, CaseIterable, Identifiable {
  case unsold = "未售出"
  case sold = "已售出"
  case unverified = "未验证"

  var id: Self { self }

  func includes(_ candidate: DreamDressCandidate, verifiedIDs: Set<String>) -> Bool {
    guard verifiedIDs.contains(candidate.id) else { return self == .unverified }
    return self == (candidate.availability == .sold ? .sold : .unsold)
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
  @State private var resultFilter: DreamDressResultFilter = .unsold
  @State private var hasMoreCandidates = false
  @State private var isLoadingMoreCandidates = false
  @State private var investigationID = UUID()
  @State private var investigationTask: Task<Void, Never>?
  @State private var loadMoreTask: Task<Void, Never>?
  @State private var scrollTargetCandidateID: String?
  @State private var newCandidateNoticeTask: Task<Void, Never>?
  @State private var newCandidateNoticeCount = 0
  @State private var isNewCandidateNoticeExpanded = false

  @ScaledMetric(relativeTo: .body) private var expandedSearchHeight: CGFloat = 354

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

      if isInvestigating && foundCount > 0 {
        DreamDressSearchProgressPill(
          newCandidateCount: newCandidateNoticeCount,
          isExpanded: isNewCandidateNoticeExpanded
        )
        .padding(.horizontal, 20)
        .padding(.top, 66)
        .zIndex(3)
      }
    }
    .overlay {
      if isInvestigating && foundCount == 0 {
        ShareLoadingOverlay(
          message: phase.rawValue,
          title: "小侦探正在搜索".appLocalized,
          detail: "正在核对商品页面、价格与图片，请稍候。".appLocalized,
          estimatedSeconds: 20...60,
          systemImage: "magnifyingglass"
        )
      }
    }
  }

  private var detectiveScrollView: some View {
    ScrollViewReader { proxy in
      Group {
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
      .onChange(of: scrollTargetCandidateID) { _, candidateID in
        guard let candidateID else { return }
        Task { @MainActor in
          await Task.yield()
          withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(candidateID, anchor: .center)
          }
          scrollTargetCandidateID = nil
        }
      }
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
            filter: resultFilter,
            hasMore: hasMoreCandidates,
            isLoadingMore: isLoadingMoreCandidates,
            onRefresh: { startInvestigation(forceRefresh: true) },
            onLoadMore: loadMoreCandidates,
            onCandidateUpdated: updateCandidate
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
      if phase == .completed && foundCount > 0 {
        Picker("筛选候选".appLocalized, selection: $resultFilter) {
          ForEach(DreamDressResultFilter.allCases) { filter in
            Text(filter.rawValue.appLocalized).tag(filter)
          }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("dreamDressDetective.resultFilter")
      } else {
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
    investigationTask?.cancel()
    loadMoreTask?.cancel()
    newCandidateNoticeTask?.cancel()
    isNewCandidateNoticeExpanded = false
    let rawURL = productURL.trimmingCharacters(in: .whitespacesAndNewlines)
    if !rawURL.isEmpty, let normalizedURL = DreamDressDetectiveService.productURL(from: rawURL) {
      productURL = normalizedURL.absoluteString
    }
    let requestID = UUID()
    investigationID = requestID
    investigationTask = Task {
      await investigate(forceRefresh: forceRefresh, requestID: requestID)
    }
  }

  private func investigate(forceRefresh: Bool, requestID: UUID) async {
    if !forceRefresh {
      allCandidates = []
      candidates = []
      foundCount = 0
      cachedAt = nil
      sourceUpdatedAt = nil
      isFromCache = false
      hasMoreCandidates = false
    }
    isLoadingMoreCandidates = false
    errorMessage = nil
    if !forceRefresh { resultFilter = .unsold }
    phase = productURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? .planning
      : .fetching

    do {
      let page = try await DreamDressDetectiveService.shared.investigatePage(
        input,
        requestedCount: DreamDressPagination.pageSize,
        forceRefresh: forceRefresh,
        onCandidatesFound: { discovered in
          guard requestID == investigationID else { return }
          applyDiscovered(discovered)
        }
      )
      guard requestID == investigationID else { return }
      apply(page)
      phase = .completed
    } catch {
      guard requestID == investigationID else { return }
      phase = .idle
      errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
  }

  private func loadMoreCandidates() {
    guard phase == .completed, hasMoreCandidates, !isLoadingMoreCandidates else { return }
    let requestedInput = input
    let requestedCount = foundCount + DreamDressPagination.pageSize
    let requestID = investigationID
    isLoadingMoreCandidates = true
    loadMoreTask = Task {
      defer {
        if requestID == investigationID {
          isLoadingMoreCandidates = false
          loadMoreTask = nil
        }
      }
      do {
        let page = try await DreamDressDetectiveService.shared.investigatePage(
          requestedInput,
          requestedCount: requestedCount,
          onCandidatesFound: { discovered in
            guard requestID == investigationID, requestedInput == input else { return }
            applyDiscovered(discovered)
          }
        )
        guard requestID == investigationID, requestedInput == input else { return }
        apply(page)
      } catch {
        guard requestID == investigationID else { return }
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      }
    }
  }

  private func apply(_ page: DreamDressInvestigationPage) {
    let result = page.result
    foundCount = result.foundCount
    allCandidates = result.allCandidates
    candidates = result.validCandidates
    cachedAt = result.cachedAt
    sourceUpdatedAt = result.sourceUpdatedAt
    isFromCache = result.isFromCache
    hasMoreCandidates = page.hasMore
  }

  private func applyDiscovered(_ discovered: [DreamDressCandidate]) {
    let previousIDs = Set(allCandidates.map(\.id))
    let existing = Dictionary(uniqueKeysWithValues: allCandidates.map { ($0.id, $0) })
    allCandidates = discovered.map { incoming in
      guard let current = existing[incoming.id] else { return incoming }
      return current.enriched(
        imageURL: incoming.imageURL,
        availability: incoming.availability == .unknown ? current.availability : incoming.availability,
        brand: incoming.brand,
        category: incoming.category,
        price: incoming.price,
        details: incoming.details
      )
    }
    let currentIDs = Set(allCandidates.map(\.id))
    candidates.removeAll { !currentIDs.contains($0.id) }
    foundCount = allCandidates.count
    let addedCount = currentIDs.subtracting(previousIDs).count
    if addedCount > 0 { showNewCandidateNotice(count: addedCount) }
  }

  private func showNewCandidateNotice(count: Int) {
    newCandidateNoticeTask?.cancel()
    newCandidateNoticeCount = count
    isNewCandidateNoticeExpanded = true
    newCandidateNoticeTask = Task {
      try? await Task.sleep(nanoseconds: 2_200_000_000)
      guard !Task.isCancelled else { return }
      isNewCandidateNoticeExpanded = false
    }
  }

  private func updateCandidate(_ updated: DreamDressCandidate) {
    guard let index = allCandidates.firstIndex(where: { $0.id == updated.id }) else { return }
    allCandidates[index] = updated

    if let validIndex = candidates.firstIndex(where: { $0.id == updated.id }) {
      candidates[validIndex] = updated
    } else if updated.imageURL != nil {
      candidates.append(updated)
      let order = Dictionary(uniqueKeysWithValues: allCandidates.enumerated().map { ($0.element.id, $0.offset) })
      candidates.sort { order[$0.id, default: .max] < order[$1.id, default: .max] }
    }
    scrollTargetCandidateID = updated.id
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
              productURL = DreamDressDetectiveService.productURL(from: value)?.absoluteString ?? value
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

private struct DreamDressSearchProgressPill: View {
  let newCandidateCount: Int
  let isExpanded: Bool

  var body: some View {
    HStack(spacing: 8) {
      ProgressView()
        .controlSize(.small)
        .tint(.pink)

      if isExpanded {
        Text("发现 \(newCandidateCount) 个新商品，向下滑查看".appLocalized)
          .font(.caption.weight(.semibold))
          .foregroundStyle(Color.pink)
          .lineLimit(1)
          .transition(.opacity.combined(with: .move(edge: .trailing)))
      }
    }
    .padding(.horizontal, isExpanded ? 14 : 12)
    .frame(height: 42)
    .background(.regularMaterial, in: Capsule())
    .overlay(Capsule().stroke(Color.pink.opacity(0.35), lineWidth: 1))
    .shadow(color: Color.black.opacity(0.08), radius: 8, y: 3)
    .frame(maxWidth: .infinity, alignment: .trailing)
    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isExpanded)
    .accessibilityLabel(
      isExpanded
        ? "发现 \(newCandidateCount) 个新商品，向下滑查看".appLocalized
        : "小侦探正在搜索".appLocalized
    )
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
  let filter: DreamDressResultFilter
  let hasMore: Bool
  let isLoadingMore: Bool
  let onRefresh: () -> Void
  let onLoadMore: () -> Void
  let onCandidateUpdated: (DreamDressCandidate) -> Void

  private var verifiedIDs: Set<String> {
    Set(validCandidates.map(\.id))
  }

  private var filteredCandidates: [DreamDressCandidate] {
    allCandidates.filter { filter.includes($0, verifiedIDs: verifiedIDs) }
  }

  var body: some View {
    LazyVStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("找到 \(foundCount) 个候选，\(validCandidates.count) 个图片已验证".appLocalized)
          .font(.system(.title3, design: .serif).weight(.semibold))
        Spacer(minLength: 4)
        Button(action: onRefresh) {
          Label("重新侦查".appLocalized, systemImage: "arrow.clockwise")
        }
        .font(.caption.weight(.semibold))
        .fixedSize(horizontal: true, vertical: false)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .disabled(isLoadingMore)
        .accessibilityIdentifier("dreamDressDetective.refresh")
      }

      Text("图片已验证商品优先展示；其余候选来自公开索引，可能过期。".appLocalized)
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

      if filteredCandidates.isEmpty {
        Text("暂无\(filter.rawValue)候选".appLocalized)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 24)
      } else {
        ForEach(filteredCandidates) { candidate in
          DreamDressDetectiveCandidateCard(
            candidate: candidate,
            isImageVerified: verifiedIDs.contains(candidate.id),
            onCandidateUpdated: onCandidateUpdated
          )
            .id(candidate.id)
            .onAppear { prefetchIfNeeded(candidateID: candidate.id) }
        }
      }

      if isLoadingMore {
        HStack(spacing: 8) {
          ProgressView()
          Text("后台继续查找…".appLocalized)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityIdentifier("dreamDressDetective.loadingMore")
      }
    }
  }

  private func prefetchIfNeeded(candidateID: String) {
    guard let visibleIndex = allCandidates.firstIndex(where: { $0.id == candidateID }) else { return }
    guard hasMore,
          DreamDressPagination.shouldPrefetch(
            visibleIndex: visibleIndex,
            totalCount: allCandidates.count
          )
    else { return }
    onLoadMore()
  }
}

private struct DreamDressDetectiveCandidateCard: View {
  let candidate: DreamDressCandidate
  let isImageVerified: Bool
  let onCandidateUpdated: (DreamDressCandidate) -> Void
  @Environment(\.modelContext) private var modelContext
  @State private var wardrobeDraft: ClothingEditDraft?
  @State private var isShowingWardrobeCreation = false
  @State private var isShowingWebVerification = false
  @State private var remoteImage: UIImage?
  @State private var isLoadingImage = false

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

        if candidate.imageURL == nil || candidate.price == nil {
          Button {
            isShowingWebVerification = true
          } label: {
            Label("验证网页以获取图片和价格".appLocalized, systemImage: "hand.draw")
          }
          .font(.caption.weight(.semibold))
          .buttonStyle(.bordered)
          .buttonBorderShape(.capsule)
        }

        Link(destination: candidate.sourceURL) {
          Label(candidate.sourceURL.absoluteString, systemImage: "arrow.up.right.square")
            .font(.caption)
            .lineLimit(2)
        }

        Button {
          addToWardrobe()
        } label: {
          Label(
            "用此商品创建裙装".appLocalized,
            systemImage: "plus.circle.fill"
          )
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
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
    .sheet(isPresented: $isShowingWebVerification) {
      DreamDressWebVerificationSheet(candidate: candidate, onCompleted: onCandidateUpdated)
    }
  }

  @ViewBuilder
  private var candidateImage: some View {
    if let imageURL = candidate.imageURL {
      Group {
        if let remoteImage {
          Image(uiImage: remoteImage)
            .resizable()
            .scaledToFill()
        } else if isLoadingImage {
          ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          imagePlaceholder
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: 190)
      .clipped()
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .task(id: imageURL) {
        isLoadingImage = true
        remoteImage = await DreamDressDetectiveService.shared.productImage(
          at: imageURL,
          referer: candidate.sourceURL
        )
        isLoadingImage = false
      }
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

  private func addToWardrobe() {
    let imagePaths = remoteImage.flatMap { ImageManager.shared.saveImage($0, context: modelContext) }.map { [$0] } ?? []
    let amount = candidate.price.flatMap(DreamDressDetectiveService.priceAmount) ?? 0
    let currency = candidate.price.flatMap {
      DreamDressDetectiveService.priceCurrency(for: $0, sourceURL: candidate.sourceURL)
    } ?? .cny
    let details = candidate.details ?? DreamDressProductDetails.extract(
      from: candidate.title,
      category: candidate.category
    )
    let now = Date()
    let draft = ClothingEditDraft(
      name: candidate.title,
      brandName: candidate.brand ?? "",
      types: Self.wardrobeType(for: candidate),
      colors: details?.colors.joined(separator: ", ") ?? "",
      sizes: details?.sizes.joined(separator: ", ") ?? "",
      length: details?.length ?? "",
      condition: details?.condition ?? "",
      accessories: details?.accessories.joined(separator: ", ") ?? "",
      imagePaths: imagePaths,
      isShared: false,
      originalPrice: currency == .cny ? amount : 0,
      originalPriceJPY: currency == .jpy ? amount : nil,
      originalPriceCurrencyCode: currency.rawValue,
      priceTotal: currency == .cny ? amount : 0,
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
    wardrobeDraft = draft
    isShowingWardrobeCreation = true
  }

  private static func wardrobeType(for candidate: DreamDressCandidate) -> String {
    if let types = candidate.details?.types, !types.isEmpty {
      return types.joined(separator: ", ")
    }
    if let category = candidate.category?.trimmingCharacters(in: .whitespacesAndNewlines), !category.isEmpty {
      let inferred = DreamDressProductDetails.extract(from: category, category: category)?.types ?? []
      return inferred.isEmpty ? category.uppercased() : inferred.joined(separator: ", ")
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

private struct DreamDressWebVerificationSheet: View {
  @Environment(\.dismiss) private var dismiss
  let candidate: DreamDressCandidate
  let onCompleted: (DreamDressCandidate) -> Void
  @State private var captureRequestID: UUID?
  @State private var isCapturing = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      DreamDressWebVerificationView(
        url: DreamDressDynamicPageLoader.renderURL(for: candidate.sourceURL),
        captureRequestID: captureRequestID,
        onCapture: finishCapture
      )
        .navigationTitle("验证商品网页".appLocalized)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
          if let errorMessage {
            Text(errorMessage)
              .font(.caption)
              .foregroundStyle(.red)
              .padding(.horizontal)
              .padding(.vertical, 8)
              .frame(maxWidth: .infinity)
              .background(.regularMaterial)
          }
        }
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button {
              errorMessage = nil
              isCapturing = true
              captureRequestID = UUID()
            } label: {
              if isCapturing {
                ProgressView()
              } else {
                Text("读取当前网页".appLocalized)
              }
            }
            .disabled(isCapturing)
          }
        }
    }
  }

  private func finishCapture(_ page: DreamDressRenderedPage?) {
    isCapturing = false
    guard let page else {
      errorMessage = "暂未读取到商品信息，请等待网页加载完成后重试。".appLocalized
      return
    }
    let updated = candidate.enrichedFromRenderedPage(
      imageURL: page.imageURL,
      availability: page.availability,
      price: DreamDressDetectiveService.price(in: page.visibleText),
      details: DreamDressProductDetails.extract(
        from: "\(page.title ?? candidate.title) \(String(page.visibleText.prefix(2_000)))",
        category: candidate.category
      )
    )
    onCompleted(updated)
    dismiss()
  }
}

private struct DreamDressWebVerificationView: UIViewRepresentable {
  let url: URL
  let captureRequestID: UUID?
  let onCapture: (DreamDressRenderedPage?) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

  func makeUIView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .default()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    configuration.userContentController.addUserScript(WKUserScript(
      source: DreamDressDynamicPageLoader.networkCaptureScript,
      injectionTime: .atDocumentStart,
      forMainFrameOnly: false
    ))
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = context.coordinator
    webView.customUserAgent = DreamDressDetectiveService.browserUserAgent
    webView.load(URLRequest(url: url))
    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {
    guard let captureRequestID,
          captureRequestID != context.coordinator.lastCaptureRequestID else { return }
    context.coordinator.lastCaptureRequestID = captureRequestID
    webView.evaluateJavaScript(DreamDressDynamicPageLoader.pageCaptureScript) { value, _ in
      context.coordinator.onCapture(
        DreamDressDynamicPageLoader.parseCapture(value, finalURL: webView.url)
      )
    }
  }

  final class Coordinator: NSObject, WKNavigationDelegate {
    var lastCaptureRequestID: UUID?
    let onCapture: (DreamDressRenderedPage?) -> Void

    init(onCapture: @escaping (DreamDressRenderedPage?) -> Void) {
      self.onCapture = onCapture
    }

    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
      guard let url = navigationAction.request.url,
            DreamDressDetectiveService.isAllowedHTTPSURL(url) else {
        decisionHandler(.cancel)
        return
      }
      decisionHandler(.allow)
    }
  }
}

#Preview {
  DreamDressDetectiveView()
}
