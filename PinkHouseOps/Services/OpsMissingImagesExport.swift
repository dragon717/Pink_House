//
//  OpsMissingImagesExport.swift
//  PinkHouseOps
//
//  把「缺图清单」写到运营挑的位置 —— **主窗口失败悬浮框**与**设置页**共用这一份实现。
//
//  ## 为什么需要它
//
//  「发布前校验未通过（284 条）」的大头是缺图：引用写着 `local:<名>`，
//  但本机 staging 里没有这个文件。这类问题**修不了**（图不在这台机器上，
//  代码不能凭空造图），只能补齐。而门禁日志只显示前几条阻断项 ——
//  运营拿不到完整名单就无从下手（2026-10-07 实测：284 条里只显示 3 条）。
//

import AppKit
// MemberImportVisibility：`UTType.plainText` 来自这个模块，不 import 会报
// "static property 'plainText' is not available"，那个报错看不出真正原因。
import UniformTypeIdentifiers

@MainActor
enum OpsMissingImagesExport {

    /// 弹保存面板，把清单写到用户挑的位置。
    /// - Returns: 给界面显示的结果文案；nil = 用户取消了面板（界面什么都不该说）。
    static func save(from workspace: OpsWorkspace) -> String? {
        let entries = workspace.missingStagedImages()
        guard !entries.isEmpty else { return "本机不缺图片文件，无需导出。" }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "缺图清单-\(entries.count).txt"
        panel.allowedContentTypes = [.plainText]
        panel.message = "导出 \(entries.count) 个缺图文件（每行「文件名 | 引用它的位置」）"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            try workspace.missingStagedImagesText.write(to: url, atomically: true, encoding: .utf8)
            return "已导出 \(entries.count) 个缺图文件到 \(url.lastPathComponent)"
                + "（每行「文件名 | 引用它的位置」）。"
        } catch {
            return "导出缺图清单失败：\(error.localizedDescription)"
        }
    }
}
