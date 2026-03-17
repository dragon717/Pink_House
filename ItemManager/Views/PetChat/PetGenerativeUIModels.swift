import Foundation

enum PetWidgetType: String, Codable {
    case quickOptions = "quick_options"
    case insightCard = "insight_card"
    case weatherCard = "weather_card"
    case container = "container"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = PetWidgetType(rawValue: rawValue) ?? .unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct PetWidgetOption: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let command: String
    let icon: String?

    init(id: String = UUID().uuidString, title: String, command: String, icon: String? = nil) {
        self.id = id
        self.title = title
        self.command = command
        self.icon = icon
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case text
        case command
        case action
        case icon
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decodeIfPresent(String.self, forKey: .text)
            ?? "继续"
        let command = try container.decodeIfPresent(String.self, forKey: .command)
            ?? container.decodeIfPresent(String.self, forKey: .action)
            ?? "noop"

        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.title = title
        self.command = command
        self.icon = try container.decodeIfPresent(String.self, forKey: .icon)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(command, forKey: .command)
        try container.encodeIfPresent(icon, forKey: .icon)
    }
}

struct PetWidgetMetric: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let value: String

    init(id: String = UUID().uuidString, name: String, value: String) {
        self.id = id
        self.name = name
        self.value = value
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case key
        case value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .key)
            ?? "指标"
        self.value = try container.decodeIfPresent(String.self, forKey: .value) ?? "-"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(value, forKey: .value)
    }
}

struct PetWidgetData: Identifiable, Codable, Equatable {
    let id: String
    let type: PetWidgetType
    let title: String?
    let subtitle: String?
    let options: [PetWidgetOption]
    let metrics: [PetWidgetMetric]
    let children: [PetWidgetData]

    init(
        id: String = UUID().uuidString,
        type: PetWidgetType,
        title: String? = nil,
        subtitle: String? = nil,
        options: [PetWidgetOption] = [],
        metrics: [PetWidgetMetric] = [],
        children: [PetWidgetData] = []
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.options = options
        self.metrics = metrics
        self.children = children
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case subtitle
        case options
        case actions
        case metrics
        case children
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.type = try container.decodeIfPresent(PetWidgetType.self, forKey: .type) ?? .unknown
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        self.options = try container.decodeIfPresent([PetWidgetOption].self, forKey: .options)
            ?? container.decodeIfPresent([PetWidgetOption].self, forKey: .actions)
            ?? []
        self.metrics = try container.decodeIfPresent([PetWidgetMetric].self, forKey: .metrics) ?? []
        self.children = try container.decodeIfPresent([PetWidgetData].self, forKey: .children) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(subtitle, forKey: .subtitle)
        try container.encode(options, forKey: .options)
        try container.encode(metrics, forKey: .metrics)
        try container.encode(children, forKey: .children)
    }
}

struct PetGenerativeRenderContent {
    let text: String
    let widgets: [PetWidgetData]
}

private struct PetGenerativeEnvelope: Codable {
    let text: String?
    let message: String?
    let widgets: [PetWidgetData]?
    let widget: PetWidgetData?
    let gui: [PetWidgetData]?
    let cards: [PetWidgetData]?
    let content: String?

    init(
        text: String? = nil,
        message: String? = nil,
        widgets: [PetWidgetData]? = nil,
        widget: PetWidgetData? = nil,
        gui: [PetWidgetData]? = nil,
        cards: [PetWidgetData]? = nil,
        content: String? = nil
    ) {
        self.text = text
        self.message = message
        self.widgets = widgets
        self.widget = widget
        self.gui = gui
        self.cards = cards
        self.content = content
    }

    var displayText: String? {
        [text, message, content].first(where: { $0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }) ?? nil
    }

    var resolvedWidgets: [PetWidgetData] {
        if let widgets, !widgets.isEmpty { return widgets }
        if let gui, !gui.isEmpty { return gui }
        if let cards, !cards.isEmpty { return cards }
        if let widget { return [widget] }
        return []
    }
}

enum PetGenerativeUIParser {
    static func buildRenderableContent(
        rawText: String,
        fallbackDisplayText: String,
        userQuery: String
    ) -> PetGenerativeRenderContent {
        let parsed = parseEnvelope(from: rawText)
        let parsedText = parsed?.displayText?.trimmingCharacters(in: .whitespacesAndNewlines)
        var resolvedWidgets = sanitizeWidgets(parsed?.resolvedWidgets ?? [])

        if resolvedWidgets.isEmpty {
            resolvedWidgets = PetWidgetSuggestionBuilder.suggestedWidgets(
                query: userQuery,
                aiResponse: fallbackDisplayText
            )
        }

        let baseText: String
        if let parsedText, !parsedText.isEmpty {
            baseText = parsedText
        } else {
            baseText = fallbackDisplayText
        }
        let resolvedText = PetResponseHumanizer.humanize(baseText)

        return PetGenerativeRenderContent(text: resolvedText, widgets: resolvedWidgets)
    }

    private static func parseEnvelope(from rawText: String) -> PetGenerativeEnvelope? {
        for candidate in jsonCandidates(from: rawText) {
            if let envelope = decodeEnvelope(from: candidate) {
                return envelope
            }
        }
        return nil
    }

    private static func decodeEnvelope(from candidate: String) -> PetGenerativeEnvelope? {
        guard let data = candidate.data(using: .utf8) else { return nil }

        if let envelope = try? JSONDecoder().decode(PetGenerativeEnvelope.self, from: data),
           !envelope.resolvedWidgets.isEmpty || envelope.displayText != nil {
            return envelope
        }

        if let widget = try? JSONDecoder().decode(PetWidgetData.self, from: data) {
            return PetGenerativeEnvelope(text: nil, message: nil, widgets: [widget], content: nil)
        }

        if let widgets = try? JSONDecoder().decode([PetWidgetData].self, from: data) {
            return PetGenerativeEnvelope(text: nil, message: nil, widgets: widgets, content: nil)
        }

        return nil
    }

    private static func jsonCandidates(from rawText: String) -> [String] {
        var candidates: [String] = []
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            candidates.append(trimmed)
        }

        if let fenced = extractFencedJSON(from: rawText), !fenced.isEmpty {
            candidates.append(fenced)
        }

        if let braces = extractJSONObjectCandidate(from: rawText), !braces.isEmpty {
            candidates.append(braces)
        }

        var deduped: [String] = []
        for value in candidates where !deduped.contains(value) {
            deduped.append(value)
        }
        return deduped
    }

    private static func extractFencedJSON(from text: String) -> String? {
        let pattern = "```(?:json|JSON)?\\s*([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractJSONObjectCandidate(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return nil
        }
        let value = String(text[start...end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func sanitizeWidgets(_ widgets: [PetWidgetData]) -> [PetWidgetData] {
        widgets.prefix(3).map { widget in
            PetWidgetData(
                id: widget.id,
                type: widget.type,
                title: widget.title,
                subtitle: widget.subtitle,
                options: Array(widget.options.prefix(4)),
                metrics: Array(widget.metrics.prefix(4)),
                children: sanitizeWidgets(Array(widget.children.prefix(3)))
            )
        }
    }
}

enum PetWidgetSuggestionBuilder {
    static func suggestedWidgets(query: String, aiResponse: String) -> [PetWidgetData] {
        let combinedText = "\(query.lowercased()) \(aiResponse.lowercased())"

        if combinedText.contains("天气") || combinedText.contains("下雨") || combinedText.contains("温度") {
            return [weatherQuickOptions()]
        }
        if combinedText.contains("穿搭") || combinedText.contains("搭配") || combinedText.contains("ootd") {
            return [outfitQuickOptions()]
        }
        return [defaultQuickOptions()]
    }

    static func onboardingWidgets() -> [PetWidgetData] {
        [defaultQuickOptions(title: "你想先聊哪一类呀？")]
    }

    private static func defaultQuickOptions(title: String = "喵，我准备了三种快捷方式：") -> PetWidgetData {
        PetWidgetData(
            type: .quickOptions,
            title: title,
            options: [
                PetWidgetOption(title: "A. 帮我搭一套", command: "outfit_suggest", icon: "wand.and.stars"),
                PetWidgetOption(title: "B. 看天气穿搭", command: "weather_guidance", icon: "cloud.sun"),
                PetWidgetOption(title: "C. 帮我找裙子", command: "search_prompt", icon: "magnifyingglass")
            ]
        )
    }

    private static func outfitQuickOptions() -> PetWidgetData {
        PetWidgetData(
            type: .quickOptions,
            title: "继续细化一下穿搭方向吧：",
            options: [
                PetWidgetOption(title: "A. 甜美约会", command: "ask:帮我搭配一套甜美约会风", icon: "heart"),
                PetWidgetOption(title: "B. 通勤日常", command: "ask:帮我搭配一套通勤日常风", icon: "briefcase"),
                PetWidgetOption(title: "C. 我有点焦虑，先聊聊", command: "mood_support", icon: "face.smiling")
            ]
        )
    }

    private static func weatherQuickOptions() -> PetWidgetData {
        PetWidgetData(
            type: .quickOptions,
            title: "根据天气我可以马上做这三件事：",
            options: [
                PetWidgetOption(title: "A. 直接给我穿搭建议", command: "weather_guidance", icon: "umbrella"),
                PetWidgetOption(title: "B. 只看雨天裙+鞋+伞", command: "weather_guidance", icon: "cloud.rain"),
                PetWidgetOption(title: "C. 先安慰我一下", command: "mood_support", icon: "sparkles")
            ]
        )
    }
}
