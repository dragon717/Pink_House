//
//  DataManagementView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/20/26.
//

import SwiftUI

struct DataManagementView: View {
    var body: some View {
        List {
            Section(header: Text("基础数据管理")) {
                NavigationLink(destination: TagModelManagementView()) {
                    Label("标签管理 (Tags)", systemImage: "tag")
                }
                NavigationLink(destination: BrandManagementView()) {
                    Label("品牌管理 (Brands)", systemImage: "crown")
                }
            }
            
            Section(header: Text("属性数据管理")) {
                NavigationLink(destination: FieldManagementView(title: "类型管理", keyPath: \.types, isCommaSeparated: true)) {
                    Label("类型 (Types)", systemImage: "tshirt")
                }
                
                NavigationLink(destination: FieldManagementView(title: "颜色管理", keyPath: \.colors, isCommaSeparated: true)) {
                    Label("颜色 (Colors)", systemImage: "paintpalette")
                }
                
                NavigationLink(destination: FieldManagementView(title: "尺码管理", keyPath: \.sizes, isCommaSeparated: true)) {
                    Label("尺码 (Sizes)", systemImage: "ruler")
                }
                
                NavigationLink(destination: FieldManagementView(title: "衣长管理", keyPath: \.length, isCommaSeparated: false)) {
                    Label("衣长 (Length)", systemImage: "arrow.up.and.down")
                }
                
                NavigationLink(destination: FieldManagementView(title: "状况管理", keyPath: \.condition, isCommaSeparated: false)) {
                    Label("状况 (Condition)", systemImage: "star")
                }
                
                NavigationLink(destination: FieldManagementView(title: "小物管理", keyPath: \.accessories, isCommaSeparated: true)) {
                    Label("小物 (Accessories)", systemImage: "bag")
                }
            }
        }
        .navigationTitle("数据管理")
    }
}
