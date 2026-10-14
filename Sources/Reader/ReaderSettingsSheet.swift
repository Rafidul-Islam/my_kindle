import SwiftUI

/// The Kindle-style `Aa` panel.
struct ReaderSettingsSheet: View {

    @State private var settings: ReaderSettings
    @State private var mode: ReaderDocument.Mode
    let onApply: (ReaderSettings, ReaderDocument.Mode?) -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        settings: ReaderSettings,
        mode: ReaderDocument.Mode,
        onApply: @escaping (ReaderSettings, ReaderDocument.Mode?) -> Void
    ) {
        _settings = State(initialValue: settings)
        _mode = State(initialValue: mode)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Page") {
                    Picker("Theme", selection: $settings.theme) {
                        ForEach(ThemeID.allCases, id: \.self) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Typeface", selection: $settings.fontFamily) {
                        ForEach(FontFamilyID.allCases, id: \.self) { family in
                            Text(family.title).tag(family)
                        }
                    }
                    .pickerStyle(.segmented)

                    stepperRow(
                        title: "Text size",
                        value: $settings.fontStep,
                        range: 0...(ReaderSettings.fontSizes.count - 1),
                        label: { settings.fontSizeLabel }
                    )

                    stepperRow(
                        title: "Margins",
                        value: $settings.marginStep,
                        range: 0...2,
                        label: { settings.marginLabel }
                    )

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Line spacing")
                            Spacer()
                            Text(String(format: "%.0f", settings.extraLineSpacing))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.extraLineSpacing, in: 0...14, step: 1)
                    }
                }

                Section("Justification") {
                    Toggle("Full justification", isOn: $settings.justified)
                    Toggle("Hyphenation", isOn: $settings.hyphenation)
                }

                Section("Rendering") {
                    Picker("Mode", selection: $mode) {
                        Text("Reflow text").tag(ReaderDocument.Mode.reflow)
                        Text("Original pages").tag(ReaderDocument.Mode.pageImage)
                    }
                    .pickerStyle(.segmented)
                    Text(modeHelp)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Reset to defaults") {
                        settings = .default
                    }
                }
            }
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onApply(settings, mode)
                        dismiss()
                    }
                }
            }
        }
    }

    private var modeHelp: String {
        switch mode {
        case .reflow:
            return "Text is re-typeset with your typeface and size. Scanned or multi-column pages are inserted as images."
        case .pageImage:
            return "Pages are shown exactly as they appear in the PDF. Pinch to zoom, press and drag to highlight."
        }
    }

    private func stepperRow(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        label: @escaping () -> String
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(label())
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Stepper(title, value: value, in: range)
                .labelsHidden()
        }
    }
}