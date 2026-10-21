// Color Picker widget (2026-10-20), 4 cells (200 pt) × 202 pt. Apple-style per
// Support/NookWidgetChrome.swift:
//   - a swatch of the current colour: its HEX value, the eyedropper (NSColorSampler — the notch
//     stays open while the loupe is up), and "Aa" in white and in black with the WCAG contrast
//     ratio of each, drawn on the colour itself;
//   - the value in the chosen format (Settings ▸ Widgets ▸ Color Picker); click copies, the context
//     menu copies any other format;
//   - the recent colours (up to 12, two rows): click makes one current and copies it again.
import SwiftUI
import AppKit

struct ColorPickerWidgetView: View {
    @State private var store = ColorPickerHistoryStore.shared
    @StoredSetting(.colorPickerWidgetSettings) private var settings
    @State private var copiedFlash: UUID?

    private let swatchHeight: CGFloat = 88
    private let historyDiameter: CGFloat = 22
    private let historyColumns = 6

    var body: some View {
        VStack(alignment: .leading, spacing: NookWidgetMetrics.spacing) {
            swatch
            valueRow
            history
        }
        .nookWidgetFrame()
        .onAppear { store.start() }
        .onChange(of: settings.historyLimit) { _, _ in store.trim() }
        .onChange(of: store.lastCopied?.date) { _, _ in
            guard let id = store.lastCopied?.id else { return }
            withAnimation(.easeOut(duration: 0.15)) { copiedFlash = id }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                if copiedFlash == id { withAnimation(.easeOut(duration: 0.2)) { copiedFlash = nil } }
            }
        }
        .nookWidgetGalleryHook()
        .colorPickerDebugHook()
    }

    // MARK: - Swatch

    @ViewBuilder
    private var swatch: some View {
        let shape = RoundedRectangle(cornerRadius: NookWidgetMetrics.cornerRadius, style: .continuous)
        if let color = store.current {
            let text: Color = color.prefersDarkText ? .black : .white
            ZStack(alignment: .topLeading) {
                shape.fill(color.color)
                shape.strokeBorder(.primary.opacity(0.12), lineWidth: 1)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 4) {
                        Text(color.hex(uppercase: settings.uppercaseHex))
                            .font(.system(.headline, design: .monospaced).weight(.semibold))
                            .foregroundStyle(text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .textSelection(.enabled)
                        Spacer(minLength: 2)
                        pickButton
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        contrastLabel(ratio: color.contrastOnWhite, foreground: .white)
                        Spacer(minLength: 2)
                        contrastLabel(ratio: color.contrastOnBlack, foreground: .black)
                    }
                    .help(String(localized: "Contrast of white and black text on this color (WCAG)"))
                }
                .padding(NookWidgetMetrics.padding)
            }
            .frame(height: swatchHeight)
        } else {
            Button { store.pick() } label: {
                VStack(spacing: 6) {
                    Image(systemName: "eyedropper")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                    Text("Pick a Color")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: swatchHeight)
                .background(shape.fill(.quinary))
                .overlay(shape.strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .contentShape(shape)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Pick a color anywhere on screen"))
        }
    }

    private var pickButton: some View {
        NookRoundIconButton(
            systemImage: store.isSampling ? "eyedropper.full" : "eyedropper",
            label: Text("Pick a Color"),
            diameter: 26,
            prominent: store.isSampling
        ) { store.pick() }
    }

    private func contrastLabel(ratio: Double, foreground: Color) -> some View {
        HStack(spacing: 3) {
            Text(verbatim: "Aa").font(.caption.weight(.bold))
            Text(PickedColor.ratioText(ratio))
                .font(.caption2.weight(.medium))
                .monospacedDigit()
            if let level = PickedColor.wcagLevel(ratio) {
                Text(level)
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .overlay(Capsule().strokeBorder(foreground.opacity(0.7), lineWidth: 0.75))
            } else {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
            }
        }
        .foregroundStyle(foreground)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    // MARK: - Value row

    @ViewBuilder
    private var valueRow: some View {
        if let color = store.current {
            let value = color.formatted(settings.format, uppercaseHex: settings.uppercaseHex)
            let copied = copiedFlash == color.id
            Button { store.copy(color) } label: {
                HStack(spacing: 6) {
                    Text(value)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(copied ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
                        .contentTransition(.symbolEffect(.replace))
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 30)
                .nookCard(cornerRadius: NookWidgetMetrics.rowCornerRadius, highlighted: copied)
                .contentShape(RoundedRectangle(cornerRadius: NookWidgetMetrics.rowCornerRadius))
            }
            .buttonStyle(.plain)
            .help(copied ? String(localized: "Copied") : String(localized: "Copy \(settings.format.title) value"))
            .contextMenu { copyMenu(color) }
        } else {
            Text("Click the eyedropper, then click any pixel. Esc cancels.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        }
    }

    @ViewBuilder
    private func copyMenu(_ color: PickedColor) -> some View {
        ForEach(ColorCopyFormat.allCases) { format in
            Button {
                store.copy(color, format: format)
            } label: {
                Text("Copy as \(format.title)")
                Text(color.formatted(format, uppercaseHex: settings.uppercaseHex))
            }
        }
    }

    // MARK: - History

    @ViewBuilder
    private var history: some View {
        let colors = Array(store.colors.prefix(settings.historyLimit))
        if colors.isEmpty {
            Text("Recent colors appear here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(historyDiameter), spacing: 8), count: historyColumns),
                      alignment: .leading, spacing: 6) {
                ForEach(colors) { color in
                    historySwatch(color, isCurrent: color.id == store.current?.id)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func historySwatch(_ color: PickedColor, isCurrent: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { store.select(color) }
        } label: {
            Circle()
                .fill(color.color)
                .overlay(Circle().strokeBorder(.primary.opacity(0.18), lineWidth: 1))
                .padding(isCurrent ? 3 : 0)
                .overlay {
                    if isCurrent { Circle().strokeBorder(Color.accentColor, lineWidth: 2) }
                }
                .frame(width: historyDiameter, height: historyDiameter)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(color.hex(uppercase: settings.uppercaseHex))
        .accessibilityLabel(Text(color.hex(uppercase: settings.uppercaseHex)))
        .contextMenu {
            copyMenu(color)
            Divider()
            Button("Remove") { withAnimation { store.remove(color) } }
            Button("Clear History", role: .destructive) { withAnimation { store.clear() } }
        }
    }
}

extension View {
    /// DEBUG: installs the Color Picker preview listener (Support/DebugHooks-ColorPicker.swift).
    func colorPickerDebugHook() -> some View {
        #if DEBUG
        return onAppear { ColorPickerDebug.install() }
        #else
        return self
        #endif
    }
}
