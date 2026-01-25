//
//  ItemManagerWidget.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/20/26.
//

import WidgetKit
import SwiftUI

@main
struct ______Bundle: WidgetBundle {
    var body: some Widget {
        ItemManagerWidget()
    }
}

struct ItemManagerWidget: Widget {
    let kind: String = "_____"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("少女心愿衣橱")
        .description("高密度展示您的衣橱统计与近期动态。长按可配置统计方式。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled() // 允许背景充满
    }
}
