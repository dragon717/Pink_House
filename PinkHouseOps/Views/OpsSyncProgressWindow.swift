import AppKit
import SwiftUI

/// 独立的非模态进度窗。窗体只展示状态，隐藏/关闭均不持有或取消同步任务。
@MainActor
final class OpsSyncProgressWindowController: NSWindowController, NSWindowDelegate {
    static let shared = OpsSyncProgressWindowController(model: .shared)
    private let model: OpsCloudSyncModel
    private(set) var runsInBackground = false

    init(model: OpsCloudSyncModel) {
        self.model = model
        super.init(window: nil)
    }

    required init?(coder: NSCoder) { fatalError("不使用 storyboard 创建同步进度窗") }

    func syncDidStart() {
        // 用户收起后，后续保存排队同步也不再反复打断编辑。
        guard !runsInBackground, window?.isVisible != true else { return }
        showProgress(activate: false)
    }

    func showProgress(activate: Bool = true) {
        if window == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
                                styleMask: [.titled, .closable, .resizable, .utilityWindow],
                                backing: .buffered, defer: false)
            panel.title = "云端同步进度"
            panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = true
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = true
            panel.minSize = NSSize(width: 440, height: 300)
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: OpsSyncProgressWindowContent(
                model: model, onBackground: { [weak self] in self?.runInBackground() }))
            panel.center()
            panel.setFrameAutosaveName("OpsSyncProgressWindow")
            window = panel
        }
        if activate { window?.makeKeyAndOrderFront(nil) }
        else { window?.orderFront(nil) }
    }

    func runInBackground() {
        runsInBackground = true
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        runsInBackground = true
    }
}

struct OpsSyncProgressWindowContent: View {
    @ObservedObject var model: OpsCloudSyncModel
    let onBackground: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("可拖动窗口移开；收起后同步继续，可以回主窗口继续编辑。")
                    .font(.caption).foregroundStyle(.secondary)
                if let report = model.syncReport {
                    OpsSyncProgressView(report: report, onDismiss: onBackground)
                } else {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("正在准备同步…")
                        Spacer()
                        Button("后台运行", action: onBackground)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
