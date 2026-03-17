import Foundation

enum SmallWorldDestination {
    case menu
    case ootd
    case ootdDefaultBook // OOTD直达默认手帐
    case pet
    case wealth(WealthMainTab? = nil) // 来财，可选指定子页签
    case calendar
    case bigWorld
    case perler // 拼豆
    case wardrobe // 衣橱
    case depositPlan // 心愿尾款
    case recycleBin // 回收站
    case dressStock // 裙装股市
}
