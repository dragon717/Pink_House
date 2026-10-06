//
//  CatalogSizeSelectionPolicy.swift
//  SharedCatalog
//
//  「可售尺码」勾选的**唯一口径**（2026-10-07 用户需求）。
//
//  ## 用户原文
//
//    「实现尺码表识别上传成功后的自动勾选逻辑：当尺码表识别并上传成功后，
//      自动勾选下方对应的可售尺码选项，同时允许用户手动取消已勾选的尺码……
//      请明确勾选与取消的触发时机、颜色规格的显示规则。」
//
//  ## 为什么这条规则住在共享包，而不是 Mac 视图里
//
//  它是**判定**（哪些算已勾、什么时候该自动补齐），不是界面文案。
//  写在 Mac target 里就永远没有自动验证 —— `PinkHouseOpsTests` 是 App 宿主式，
//  本机 `xcodebuild test` 会永久挂起（见 skill `pink-house-xcodebuild-acceptance` §1f）。
//  放进共享包后，`swift test` 秒级覆盖；Mac 那边只剩「在哪些动作节点调它」。
//
//  ## 两个语义容易写错的点（都在下面的实现里被钉死）
//
//  1. **判据是「一个有效尺码都没勾」，不是「缺哪些就补哪些」。**
//     后一种会把用户**手动取消**掉的尺码又勾回来 —— 而取消是显式意图。
//     「一个都没勾」只可能是两种情况：颜色刚建、或原尺码表被整张换掉导致旧选择全部失效，
//     两种都该补；而「只勾了一部分」永远是人的选择，一律不动。
//  2. **顺序 = 尺码表原始顺序**，不是 `current` 的顺序、更不是集合遍历序。
//     勾选项在界面上就按这个顺序渲染；用无序集合派生顺序在本仓库是明令禁止的
//     （同一份数据每次渲染都可能不一样，看起来像随机抖动）。
//

import Foundation

public enum CatalogSizeSelectionPolicy {

    /// 归一：只保留**属于本尺码表**的标签，且按**尺码表原始顺序**返回。
    ///
    /// 用在保存路径上：换过尺码表的颜色可能留着上一张表的旧标签，
    /// 它们既渲染不出来、也不该参与「有没有勾过」的判定。
    public static func normalized(_ current: [String], allLabels: [String]) -> [String] {
        let picked = Set(current.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        return allLabels.filter { picked.contains($0) }
    }

    /// 该颜色**在当前这张尺码表下**一个有效尺码都没勾。
    /// 这是「要不要自动补齐」的**唯一判据**。
    public static func hasNoSelection(_ current: [String], allLabels: [String]) -> Bool {
        normalized(current, allLabels: allLabels).isEmpty
    }

    /// 自动勾选（**幂等**）：只有「一个有效尺码都没勾」时才补齐为整张尺码表，
    /// 否则只做归一、**绝不改动用户的选择**。
    ///
    /// 幂等意味着调用方可以在**任意多个动作节点**上安全地重复调它，
    /// 不必自己去记「这一步是不是第一次」——`f(f(x)) == f(x)`。
    /// （这是刻意的：要判断「刚刚识别成功」需要保存上一次的状态，
    ///  而那份状态一旦和真实数据不同步，就会静默做错事。）
    public static func autoFilled(_ current: [String], allLabels: [String]) -> [String] {
        guard !allLabels.isEmpty else { return [] }
        return hasNoSelection(current, allLabels: allLabels)
            ? allLabels
            : normalized(current, allLabels: allLabels)
    }

    /// 还差哪些尺码没勾（**只报事实**，界面据此给一句提示，绝不替用户决定）。
    /// 返回顺序同样是尺码表原始顺序。
    public static func missing(_ current: [String], allLabels: [String]) -> [String] {
        let picked = Set(normalized(current, allLabels: allLabels))
        return allLabels.filter { !picked.contains($0) }
    }

    /// 用户按下「全选」时该写入什么：**整张表**（这是显式动作，覆盖手动取消是用户自己要的）。
    /// 与 `autoFilled` 的差别只在这里 —— 一个只在空的时候补，一个无条件覆盖。
    public static func selectAll(allLabels: [String]) -> [String] { allLabels }
}
