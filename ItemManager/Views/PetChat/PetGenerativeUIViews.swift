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
    let widget: PetWidgetData
    let onAction: (PetWidgetOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = widget.title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.pink.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }
}

private struct PetWeatherWidget: View {
    let widget: PetWidgetData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = widget.title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            if let subtitle = widget.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !widget.metrics.isEmpty {
                HStack(spacing: 8) {
                    ForEach(widget.metrics) { metric in
                        VStack(spacing: 2) {
                            Text(metric.name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(metric.value)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(10)
        .background(Color.blue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct PetInsightCardWidget: View {
    let widget: PetWidgetData

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title = widget.title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            if let subtitle = widget.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct PetContainerWidget: View {
    let widget: PetWidgetData
    let onAction: (PetWidgetOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = widget.title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            if let subtitle = widget.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !widget.children.isEmpty {
                PetGenerativeWidgetHost(widgets: widget.children, onAction: onAction)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
