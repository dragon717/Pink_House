import SwiftUI
import SwiftData

struct DreamDressDetectiveView: View {
  @State private var brandName = ""
  @State private var productName = ""
  @State private var productURL = ""
  @State private var phase: DreamDressDetectivePhase = .idle
  @State private var candidates: [DreamDressCandidate] = []
  @State private var errorMessage: String?

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
    ScrollView {
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
          onInvestigate: { Task { await investigate() } }
        )

        if let errorMessage {
          DreamDressDetectiveErrorCard(message: errorMessage)
        }

        if !candidates.isEmpty {
          DreamDressDetectiveResultsSection(candidates: candidates)
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 8)
      .padding(.bottom, 32)
    }
    .scrollIndicators(.hidden)
  }

  private func investigate() async {
    candidates = []
    errorMessage = nil
    phase = productURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? .planning
      : .fetching

    do {
      let found = try await DreamDressDetectiveService.shared.investigate(input)
      candidates = Array(found.prefix(5))
      if candidates.isEmpty {
        errorMessage = DreamDressDetectiveError.noResults.localizedDescription
      } else {
        phase = .structuring
        await retryMissingCandidates()
      }
      phase = .completed
    } catch {
      phase = .idle
      errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
  }

  private func retryMissingCandidates() async {
    for index in candidates.indices {
      for attempt in 1...2 {
        let candidate = candidates[index]
        guard candidate.imageURL == nil || candidate.availability == .unknown else { break }
#if DEBUG
        print("[DreamDressDetective] auto_retry_start attempt=\(attempt) url=\(candidate.sourceURL.absoluteString)")
#endif
        guard let page = await DreamDressDynamicPageLoader.load(url: candidate.sourceURL) else {
#if DEBUG
          print("[DreamDressDetective] auto_retry_empty attempt=\(attempt) url=\(candidate.sourceURL.absoluteString)")
#endif
          continue
        }
        candidates[index] = candidate.enrichedFromRenderedPage(
          imageURL: page.imageURL,
          availability: page.availability
        )
#if DEBUG
        print("[DreamDressDetective] auto_retry_finish attempt=\(attempt) image=\(page.imageURL != nil) status=\(page.availability.rawValue)")
#endif
      }
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
  let candidates: [DreamDressCandidate]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("候选商品".appLocalized)
        .font(.system(.title3, design: .serif).weight(.semibold))

      Text("在售商品优先；动态平台无法公开核验时会标记为状态待确认。".appLocalized)
        .font(.caption)
        .foregroundStyle(.secondary)

      ForEach(candidates) { candidate in
        DreamDressDetectiveCandidateCard(candidate: candidate)
      }
    }
  }
}

private struct DreamDressDetectiveCandidateCard: View {
  let candidate: DreamDressCandidate
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
