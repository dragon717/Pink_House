import Foundation

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
        return "这里是\(status.displayName)现在的状态总览，饱食、饮水、清洁、心情和亲密度都在这儿啦。"
    case .hunger:
        return "\(status.displayName)现在的饱食度在这里，想喂点东西的话我可以直接打开背包。"
    case .hydration:
        return "\(status.displayName)的饮水状态在这里，要不要马上喂它喝一点？"
    case .hygiene:
        return "\(status.displayName)的清洁状态在这里，要不要顺手给它洗香香？"
    case .mood:
        return "\(status.displayName)现在的心情，我单独给你看看。"
    case .intimacy:
        return "亲密度用桃心进度来展示，你们的关系正在慢慢变深。"
    }
}

private func petChatStatusOptions(for kind: PetStatusPanelKind) -> [PetWidgetOption] {
    switch kind {
    case .all:
        return [
            PetWidgetOption(title: "打开萌宠背包", command: "pet_inventory_panel", icon: "shippingbox.fill"),
            PetWidgetOption(title: "打开萌宠商店", command: "pet_shop_panel", icon: "cart.fill"),
            PetWidgetOption(title: "数数我的裙装总价值", command: "pet_money_counter", icon: "yensign.circle.fill")
        ]
    case .hunger:
        return [
            PetWidgetOption(title: "打开背包喂点吃的", command: "pet_inventory_panel", icon: "fork.knife.circle.fill"),
            PetWidgetOption(title: "去商店补充食物", command: "pet_shop_panel", icon: "cart.fill"),
            PetWidgetOption(title: "顺便看看饮水状态", command: "pet_status_hydration", icon: "drop.circle.fill")
        ]
    case .hydration:
        return [
            PetWidgetOption(title: "打开背包喂点喝的", command: "pet_inventory_panel", icon: "drop.circle.fill"),
            PetWidgetOption(title: "去商店补充饮品", command: "pet_shop_panel", icon: "cart.fill"),
            PetWidgetOption(title: "顺便看看饱食状态", command: "pet_status_hunger", icon: "fork.knife.circle.fill")
        ]
    case .hygiene:
        return [
            PetWidgetOption(title: "帮它清洁一下", command: "pet_clean_now", icon: "sparkles"),
            PetWidgetOption(title: "看看全部状态", command: "pet_status_all", icon: "rectangle.stack.fill")
        ]
    case .mood:
        return [
            PetWidgetOption(title: "打开背包陪它玩", command: "pet_inventory_panel", icon: "gamecontroller.fill"),
            PetWidgetOption(title: "聊聊天安慰它", command: "mood_support", icon: "bubble.left.and.bubble.right.fill")
        ]
    case .intimacy:
        return [
            PetWidgetOption(title: "看看全部状态", command: "pet_status_all", icon: "rectangle.stack.fill"),
            PetWidgetOption(title: "切换一下宠物管家", command: "pet_switch", icon: "arrow.triangle.2.circlepath")
        ]
    }
}

func makeStatusPanelWidget(status: PetStatus, kind: PetStatusPanelKind, feedback: String? = nil) -> PetWidgetData {
    PetWidgetData(
        type: .statusPanel,
        title: kind == .all ? "\(status.displayName)的状态总览" : "\(status.displayName)的\(kind.title)",
        subtitle: feedback ?? petChatStatusSubtitle(for: status, kind: kind),
        options: petChatStatusOptions(for: kind),
        metrics: petChatStatusMetrics(for: status, kind: kind)
    )
}
