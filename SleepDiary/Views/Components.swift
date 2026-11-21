import SwiftUI

/// A rounded card on the night background.
struct Card<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
    }
}

/// A pill-shaped toggle button; amber with a check mark when selected.
struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if selected { Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)) }
                Text(title)
            }
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .foregroundStyle(selected ? Theme.onAccent : Theme.text)
            .background(selected ? Theme.accent : Theme.cardRaised, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Full-width primary (amber) or secondary button.
struct WideButtonStyle: ButtonStyle {
    var primary = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: primary ? 17 : 16, weight: primary ? .semibold : .medium))
            .frame(maxWidth: .infinity)
            .frame(height: primary ? 54 : 50)
            .foregroundStyle(primary ? Theme.onAccent : Theme.text)
            .background(primary ? Theme.accent : Theme.cardRaised, in: RoundedRectangle(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// A labelled time with an optional hint underneath ("Health: 9:52 pm").
/// A nil time shows an "Add time" button.
struct TimeRow: View {
    let title: String
    var hint: String? = nil
    @Binding var time: Date?
    var defaultTime: Date = Date()

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .medium))
                if let hint {
                    Text(hint).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
            }
            Spacer()
            if let value = time {
                DatePicker(title, selection: Binding(get: { value }, set: { time = $0 }),
                           displayedComponents: .hourAndMinute)
                    .labelsHidden()
            } else {
                Button("Add time") { time = defaultTime }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
                    .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10))
                    .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 44)
    }
}

/// A small numbered amber circle, matching the pins on the hypnogram.
struct NumberBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Theme.onAccent)
            .frame(width: 24, height: 24)
            .background(Theme.accent, in: Circle())
    }
}

/// The common layout of a check-in step: progress dots in the navigation bar,
/// a heading, then the step's cards.
struct StepScaffold<Content: View>: View {
    let step: CheckInStep
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Theme.headingFont)
                    Text(subtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondary)
                }
                content
            }
            .padding(20)
        }
        .nightStyle()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { StepDots(current: step) }
        }
    }
}

struct StepDots: View {
    let current: CheckInStep

    var body: some View {
        HStack(spacing: 6) {
            ForEach(CheckInStep.allCases) { step in
                Capsule()
                    .fill(step.rawValue <= current.rawValue ? Theme.accent : Theme.line)
                    .frame(width: step == current ? 22 : 8, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current.rawValue + 1) of \(CheckInStep.allCases.count)")
    }
}

/// A small uppercase card heading.
struct CardLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(Theme.secondary)
    }
}

/// A card title with an amber icon in front.
struct IconTitle: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            Text(title).font(Theme.cardTitleFont)
        }
    }
}

extension View {
    /// Night background, light text, amber tint, dark controls.
    func nightStyle() -> some View {
        self
            .foregroundStyle(Theme.text)
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .tint(Theme.accent)
            .toolbarBackground(Theme.background, for: .navigationBar)
    }
}

/// A trash-can icon button with a 44 pt target.
struct DeleteButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .foregroundStyle(Theme.secondary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
