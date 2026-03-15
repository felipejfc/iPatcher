import SwiftUI

private struct HideScrollContentBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content.onAppear {
                UITextView.appearance().backgroundColor = .clear
            }
        }
    }
}

struct HexInputField: View {
    @Binding var text: String
    var placeholder: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(IPTheme.monoMedium)
                        .foregroundColor(IPTheme.textSecondary.opacity(0.35))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                }

                TextEditor(text: $text)
                    .font(IPTheme.monoMedium)
                    .foregroundColor(IPTheme.textPrimary)
                    .modifier(HideScrollContentBackground())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 64)
            }
            .background(IPTheme.surface)
            .cornerRadius(12)

            if !text.isEmpty {
                let count = text.split(separator: " ")
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    .count
                Text("\(count) byte\(count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundColor(IPTheme.textSecondary.opacity(0.5))
                    .padding(.top, 4)
                    .padding(.leading, 4)
            }
        }
    }
}
