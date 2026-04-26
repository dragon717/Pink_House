//
//  ShareSheet.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 2024/02/14.
//

import SwiftUI
import UIKit
import MessageUI

// ShareSheet 包装器，用于在 SwiftUI 中使用 UIActivityViewController
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct MailAttachment {
    let data: Data
    let mimeType: String
    let fileName: String

    init(fileURL: URL, mimeType: String, fileName: String? = nil) throws {
        self.data = try Data(contentsOf: fileURL)
        self.mimeType = mimeType
        self.fileName = fileName ?? fileURL.lastPathComponent
    }
}

struct MailComposer: UIViewControllerRepresentable {
    let subject: String
    let recipients: [String]
    let messageBody: String
    let attachments: [MailAttachment]
    let onFinish: (MFMailComposeResult, Error?) -> Void

    static func canSendMail() -> Bool {
        MFMailComposeViewController.canSendMail()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setSubject(subject)
        controller.setToRecipients(recipients)
        controller.setMessageBody(messageBody, isHTML: false)

        for attachment in attachments {
            controller.addAttachmentData(
                attachment.data,
                mimeType: attachment.mimeType,
                fileName: attachment.fileName
            )
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: (MFMailComposeResult, Error?) -> Void

        init(onFinish: @escaping (MFMailComposeResult, Error?) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onFinish(result, error)
            controller.dismiss(animated: true)
        }
    }
}
