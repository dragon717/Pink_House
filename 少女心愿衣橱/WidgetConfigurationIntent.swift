//
//  WidgetConfigurationIntent.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/20/26.
//

import WidgetKit
import AppIntents

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "配置衣橱小组件"
    static var description = IntentDescription("展示衣橱统计数据。")
}

