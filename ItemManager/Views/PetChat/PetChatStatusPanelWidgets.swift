import Foundation

func petChatShouldShowSleepyExpression(
    status: PetStatus,
    now: Date = Date(),
    calendar: Calendar = .current
) -> Bool {
    let hour = calendar.component(.hour, from: now)
    let lowEnergy = status.energy < 35
    let lateNight = hour >= 23 || hour < 6
    let earlyMorning = hour >= 6 && hour < 8
    return lowEnergy || lateNight || (earlyMorning && status.energy < 65)
}

private func petChatIntimacyHearts(for intimacy: Double) -> String {
    let value = max(0, min(100, intimacy))
    let filled = Int((value / 20).rounded(.down))
    let empty = max(0, 5 - filled)
    return String(repeating: "♥️", count: filled) + String(repeating: "♡", count: empty)
}

private func petChatMetricForStatus(_ status: PetStatus, kind: PetStatusPanelKind) -> PetWidgetMetric {
    switch kind {
    case .all:
        return PetWidgetMetric(name: "亲密度", value: petChatIntimacyHearts(for: status.intimacy))
    case .hunger:
        return PetWidgetMetric(name: "饱食", value: "\(Int(status.hunger))/100")
    case .hydration:
        return PetWidgetMetric(name: "饮水", value: "\(Int(status.energy))/100")
    case .hygiene:
        return PetWidgetMetric(name: "清洁", value: "\(Int(status.hygiene))/100")
    case .mood:
        return PetWidgetMetric(name: "心情", value: "\(Int(status.mood))/100")
    case .intimacy:
        return PetWidgetMetric(name: "亲密度", value: petChatIntimacyHearts(for: status.intimacy))
    }
}

private func petChatStatusMetrics(for status: PetStatus, kind: PetStatusPanelKind) -> [PetWidgetMetric] {
    switch kind {
    case .all:
        return [
            PetWidgetMetric(name: "饱食", value: "\(Int(status.hunger))/100"),
            PetWidgetMetric(name: "饮水", value: "\(Int(status.energy))/100"),
            PetWidgetMetric(name: "清洁", value: "\(Int(status.hygiene))/100"),
            PetWidgetMetric(name: "心情", value: "\(Int(status.mood))/100"),
            PetWidgetMetric(name: "亲密度", value: petChatIntimacyHearts(for: status.intimacy))
        ]
    default:
        return [petChatMetricForStatus(status, kind: kind)]
    }
}

private func petChatStatusSubtitle(for status: PetStatus, kind: PetStatusPanelKind) -> String {
    switch kind {
    case .all:
        return "这是我现在的状态总览，饱食、饮水、清洁、心情和亲密度都在这儿啦。"
    case .hunger:
        return "这是我现在的饱食度，想喂我点东西的话，可以直接打开我的背包。"
    case .hydration:
        return "这是我现在的饮水状态，要不要马上喂我喝一点呀？"
    case .hygiene:
        let cleaning = petCleaningContext(for: status)
        return "这是我现在的清洁状态，帮\(cleaning.petName)洗香香要花\(cleaning.cost)\(cleaning.currency.rawValue)，要不要现在就洗？"
    case .mood:
        return "这是我现在的心情，我单独给你看看。"
    case .intimacy:
        return "这是我和你的亲密度，桃心越满就代表我越黏你。"
    }
}

private func petChatStatusOptions(for status: PetStatus, kind: PetStatusPanelKind) -> [PetWidgetOption] {
    switch kind {
    case .all:
        return [
            PetWidgetOption(title: "看看我的背包", command: "pet_inventory_panel", icon: "shippingbox.fill"),
            PetWidgetOption(title: "带我逛逛商店", command: "pet_shop_panel", icon: "cart.fill"),
            PetWidgetOption(title: "数数我的裙装总价值", command: "pet_money_counter", icon: "yensign.circle.fill")
        ]
    case .hunger:
        return [
            PetWidgetOption(title: "打开背包喂我吃点", command: "pet_inventory_panel", icon: "fork.knife.circle.fill"),
            PetWidgetOption(title: "去商店给我补点吃的", command: "pet_shop_panel", icon: "cart.fill"),
            PetWidgetOption(title: "顺便看看我的饮水", command: "pet_status_hydration", icon: "drop.circle.fill")
        ]
    case .hydration:
        return [
            PetWidgetOption(title: "打开背包喂我喝点", command: "pet_inventory_panel", icon: "drop.circle.fill"),
            PetWidgetOption(title: "去商店给我补点喝的", command: "pet_shop_panel", icon: "cart.fill"),
            PetWidgetOption(title: "顺便看看我的饱食", command: "pet_status_hunger", icon: "fork.knife.circle.fill")
        ]
    case .hygiene:
        let cleaning = petCleaningContext(for: status)
        return [
            PetWidgetOption(title: "给我洗香香（\(cleaning.cost)\(cleaning.currency.rawValue)）", command: "pet_clean_now", icon: "sparkles"),
            PetWidgetOption(title: "看看我的全部状态", command: "pet_status_all", icon: "rectangle.stack.fill")
        ]
    case .mood:
        return [
            PetWidgetOption(title: "打开背包陪我玩", command: "pet_inventory_panel", icon: "gamecontroller.fill"),
            PetWidgetOption(title: "陪我聊聊天", command: "mood_support", icon: "bubble.left.and.bubble.right.fill")
        ]
    case .intimacy:
        return [
            PetWidgetOption(title: "看看我的全部状态", command: "pet_status_all", icon: "rectangle.stack.fill"),
            PetWidgetOption(title: "换个陪你的萌宠", command: "pet_switch", icon: "arrow.triangle.2.circlepath")
        ]
    }
}

func makeStatusPanelWidget(status: PetStatus, kind: PetStatusPanelKind, feedback: String? = nil) -> PetWidgetData {
    PetWidgetData(
        type: .statusPanel,
        title: kind == .all ? "我的状态总览" : "我的\(kind.title)",
        subtitle: feedback ?? petChatStatusSubtitle(for: status, kind: kind),
        options: petChatStatusOptions(for: status, kind: kind),
        metrics: petChatStatusMetrics(for: status, kind: kind)
    )
}

func petChatStatusExpressionImageName(status: PetStatus, kind: PetStatusPanelKind) -> String? {
    guard kind == .mood || kind == .all else { return nil }

    let character = PetCharacter(rawValue: status.selectedPetId ?? "") ?? .naicha
    if petChatShouldShowSleepyExpression(status: status) {
        return character.sleepyImageName
    }

    switch status.mood {
    case 80...:
        return character.happyImageName
    case 55..<80:
        return character.curiousImageName
    case 30..<55:
        return character.thinkingImageName
    default:
        return character.sleepyImageName
    }
}
