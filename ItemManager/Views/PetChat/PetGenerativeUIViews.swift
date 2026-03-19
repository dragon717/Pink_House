import SwiftUI

struct PetGenerativeWidgetHost: View {
    let widgets: [PetWidgetData]
    let onAction: (PetWidgetOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(widgets) { widget in
                PetWidgetRegistry.makeWidget(widget, onAction: onAction)
            }
        }
    }
}

enum PetWidgetRegistry {
    @ViewBuilder
    static func makeWidget(_ widget: PetWidgetData, onAction: @escaping (PetWidgetOption) -> Void) -> some View {
        switch widget.type {
        case .quickOptions:
            PetQuickOptionsWidget(widget: widget, onAction: onAction)
        case .weatherCard:
            PetWeatherWidget(widget: widget)
        case .container:
            PetContainerWidget(widget: widget, onAction: onAction)
        case .insightCard:
            PetInsightCardWidget(widget: widget)
        case .unknown:
            PetInsightCardWidget(widget: widget)
        }
    }
}

private struct PetQuickOptionsWidget: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    let widget: PetWidgetData
    let onAction: (PetWidgetOption) -> Void

    var body: some View {
        let skin = themeManager.petChatSkinTheme
        let optionFill = skin.resolvedQuickOptionFill(themeManager: themeManager, colorScheme: colorScheme)
        let optionStroke = skin.resolvedQuickOptionStroke(themeManager: themeManager, colorScheme: colorScheme)
        let optionText = MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme).quickOptionText

        VStack(alignment: .leading, spacing: 8) {
            if let title = widget.title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(themeManager.secondaryTextColor)
            }

            ForEach(widget.options) { option in
                Button {
                    onAction(option)
                } label: {
                    HStack(spacing: 8) {
                        if let icon = option.icon, !icon.isEmpty {
                            Image(systemName: icon)
                                .font(.caption)
                        }
                        Text(option.title)
                            .font(.caption)
                            .lineLimit(2)
                    }
                    .foregroundStyle(optionText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(optionFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(optionStroke, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }
}

private struct PetWeatherWidget: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    let widget: PetWidgetData

    var body: some View {
        let palette = MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
        VStack(alignment: .leading, spacing: 8) {
            if let title = widget.title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(palette.primaryText)
            }
            if let subtitle = widget.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
            }

            if !widget.metrics.isEmpty {
                HStack(spacing: 8) {
                    ForEach(widget.metrics) { metric in
                        VStack(spacing: 2) {
                            Text(metric.name)
                                .font(.caption2)
                                .foregroundStyle(palette.secondaryText)
                            Text(metric.value)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(palette.primaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(palette.quickOptionFill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(10)
        .background(palette.cardBackground.opacity(colorScheme == .dark ? 0.5 : 0.7))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(palette.quickOptionStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct PetInsightCardWidget: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    let widget: PetWidgetData

    var body: some View {
        let palette = MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
        VStack(alignment: .leading, spacing: 4) {
            if let title = widget.title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(palette.primaryText)
            }
            if let subtitle = widget.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.cardBackground.opacity(colorScheme == .dark ? 0.45 : 0.65))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(palette.quickOptionStroke.opacity(0.8), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct PetContainerWidget: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    let widget: PetWidgetData
    let onAction: (PetWidgetOption) -> Void

    var body: some View {
        let palette = MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
        VStack(alignment: .leading, spacing: 8) {
            if let title = widget.title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(palette.primaryText)
            }
            if let subtitle = widget.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
            }
            if !widget.children.isEmpty {
                PetGenerativeWidgetHost(widgets: widget.children, onAction: onAction)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(palette.quickOptionStroke.opacity(0.8), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
