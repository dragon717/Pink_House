//
//  ______LiveActivity.swift
//  少女心愿衣橱
//
//  Created by 木鸟 on 1/20/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct ______Attributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct ______LiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ______Attributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension ______Attributes {
    fileprivate static var preview: ______Attributes {
        ______Attributes(name: "World")
    }
}

extension ______Attributes.ContentState {
    fileprivate static var smiley: ______Attributes.ContentState {
        ______Attributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: ______Attributes.ContentState {
         ______Attributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: ______Attributes.preview) {
   ______LiveActivity()
} contentStates: {
    ______Attributes.ContentState.smiley
    ______Attributes.ContentState.starEyes
}
