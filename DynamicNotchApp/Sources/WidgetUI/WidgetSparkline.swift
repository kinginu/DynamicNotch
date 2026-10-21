// Sparkline chrome shared by the Network and System widgets (refactor R13, 2026-10-20):
// Swift Charts with no axes / legend on a rounded plot background, a placeholder line until there
// is data, and the same line / area styling for the marks.
import SwiftUI
import Charts

enum NookSparklineStyle {
    /// Stroke of a sparkline's line marks.
    static let lineStroke = StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)

    /// Vertical fade under a filled sparkline (`top` / `bottom` = opacity of `color`).
    static func areaGradient(_ color: Color, top: Double, bottom: Double) -> LinearGradient {
        LinearGradient(colors: [color.opacity(top), color.opacity(bottom)], startPoint: .top, endPoint: .bottom)
    }
}

extension View {
    /// Chart chrome of a widget sparkline: hidden axes and legend, the plot area on a rounded
    /// `plotFill`, and `placeholder` centred over it while `showsPlaceholder`.
    func nookSparklineChrome<Fill: ShapeStyle>(cornerRadius: CGFloat, plotFill: Fill,
                                               showsPlaceholder: Bool, placeholder: Text,
                                               placeholderFont: Font) -> some View {
        chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartPlotStyle { plot in
                plot.background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(plotFill))
            }
            .overlay {
                if showsPlaceholder {
                    placeholder
                        .font(placeholderFont)
                        .foregroundStyle(.tertiary)
                }
            }
    }
}
