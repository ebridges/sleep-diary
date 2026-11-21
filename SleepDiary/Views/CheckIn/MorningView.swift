import SwiftUI

/// Check-in step 4: how rested (app only, 1 to 5) and how groggy (written to
/// Health as Fatigue at the final wake time), plus a note.
struct MorningView: View {
    @Bindable var checkIn: CheckIn
    let onDone: () -> Void

    @AppStorage(SettingsKeys.writeSleepToHealth) private var writeNaps = false
    @State private var rested: Int?
    @State private var groggy: Severity?
    @State private var saving = false

    var body: some View {
        StepScaffold(step: .morning, title: "This morning", subtitle: "Answer for how you felt when you got up.") {
            Card {
                Text("How rested do you feel?").font(Theme.cardTitleFont)
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { n in
                        choiceButton("\(n)", selected: rested == n, height: 56, font: .system(size: 22, weight: .semibold)) {
                            rested = n
                        }
                        .accessibilityLabel("\(n) of 5")
                    }
                }
                HStack {
                    Text("1 · Not at all")
                    Spacer()
                    Text("5 · Fully rested")
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
            }
            Card {
                Text("How groggy are you?").font(Theme.cardTitleFont)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                    ForEach(Severity.allCases) { s in
                        choiceButton(s.label, selected: groggy == s, height: 52, font: .system(size: 15, weight: .semibold)) {
                            groggy = s
                        }
                    }
                }
                Text("Same scale Apple Health uses for symptoms. Saved to Health as Fatigue at \(Fmt.time(checkIn.d.finalWake)).")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
            }
            Card {
                Text("Anything else?").font(.system(size: 15, weight: .semibold))
                TextField("e.g. dry mouth, vivid dreams, noise outside", text: $checkIn.d.notes, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(12)
                    .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12))
            }
            Button("Finish check-in") {
                guard let rested, let groggy else { return }
                checkIn.d.rested = rested
                checkIn.d.grogginess = groggy
                saving = true
                Task {
                    await checkIn.confirm(.morning, writeNaps: writeNaps)
                    saving = false
                    onDone()
                }
            }
            .buttonStyle(WideButtonStyle())
            .disabled(rested == nil || groggy == nil || saving)
            .opacity(rested == nil || groggy == nil ? 0.5 : 1)
        }
        .onAppear {
            guard rested == nil, checkIn.isDone(.morning) else { return }
            rested = checkIn.d.rested
            groggy = checkIn.d.grogginess
        }
    }

    private func choiceButton(_ title: String, selected: Bool, height: CGFloat, font: Font,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(font)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .foregroundStyle(selected ? Theme.onAccent : Theme.text)
                .background(selected ? Theme.accent : Theme.cardRaised, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
