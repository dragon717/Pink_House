//
//  WidgetConfigurationIntent.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/20/26.
//

import WidgetKit
import AppIntents

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "配置衣橱小组件"
    static var description = IntentDescription("选择您希望展示的统计数据类型。")

    // 参数：统计类型
    @Parameter(title: "统计方式", default: .month)
    var statsType: StatsTypeIntent
}

enum StatsTypeIntent: String, AppEnum {
    case month
    case series
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "统计方式"
    
    static var caseDisplayRepresentations: [StatsTypeIntent : DisplayRepresentation] = [
        .month: "按月份 (本月新增/趋势)",
        .series: "按系列 (Top系列/列表)"
    ]
}
