#if canImport(UIKit)
import UIKit

/// Core Graphics chart helpers for PDF report generation.
/// Draws line charts, bar charts, and horizontal bar charts directly into a CGContext.
struct PDFChartRenderer {

    // MARK: - Data Types

    struct DataPoint {
        let label: String
        let value: Double
    }

    struct BarItem {
        let label: String
        let value: Double   // 0.0–1.0 for percentage bars
    }

    // MARK: - Colors

    static let gridColor = UIColor(white: 0.85, alpha: 1.0)
    static let axisColor = UIColor(white: 0.4, alpha: 1.0)
    static let labelColor = UIColor(white: 0.45, alpha: 1.0)
    static let areaAlpha: CGFloat = 0.15

    // MARK: - Line Chart

    /// Draws a line chart with optional area fill. Returns the bottom Y of the chart.
    @discardableResult
    static func drawLineChart(
        context: CGContext,
        dataPoints: [DataPoint],
        rect: CGRect,
        lineColor: UIColor,
        yAxisLabel: String,
        yMin: Double = 0,
        yMax: Double = 5
    ) -> CGFloat {
        guard !dataPoints.isEmpty else { return rect.maxY }

        let labelFont = UIFont.systemFont(ofSize: 8)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: labelColor
        ]

        // Chart area inset for axis labels
        let leftInset: CGFloat = 30
        let bottomInset: CGFloat = 18
        let chartRect = CGRect(
            x: rect.minX + leftInset,
            y: rect.minY,
            width: rect.width - leftInset,
            height: rect.height - bottomInset
        )

        // Draw Y-axis label
        yAxisLabel.draw(at: CGPoint(x: rect.minX, y: rect.minY), withAttributes: labelAttrs)

        // Draw grid lines
        drawGrid(context: context, rect: chartRect, yMin: yMin, yMax: yMax)

        // Map data to points
        let points = mapDataToPoints(data: dataPoints, rect: chartRect, yMin: yMin, yMax: yMax)

        guard points.count > 0 else { return rect.maxY }

        // Draw area fill
        context.saveGState()
        context.setFillColor(lineColor.withAlphaComponent(areaAlpha).cgColor)
        context.beginPath()
        context.move(to: CGPoint(x: points[0].x, y: chartRect.maxY))
        for pt in points { context.addLine(to: pt) }
        context.addLine(to: CGPoint(x: points.last!.x, y: chartRect.maxY))
        context.closePath()
        context.fillPath()
        context.restoreGState()

        // Draw line
        context.saveGState()
        context.setStrokeColor(lineColor.cgColor)
        context.setLineWidth(1.5)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.beginPath()
        context.move(to: points[0])
        for pt in points.dropFirst() { context.addLine(to: pt) }
        context.strokePath()
        context.restoreGState()

        // Draw X-axis labels (show first, middle, last)
        let indices = xLabelIndices(count: dataPoints.count)
        for i in indices {
            let shortLabel = String(dataPoints[i].label.suffix(5))
            shortLabel.draw(at: CGPoint(x: points[i].x - 12, y: chartRect.maxY + 2), withAttributes: labelAttrs)
        }

        return rect.maxY
    }

    // MARK: - Bar Chart

    /// Draws a vertical bar chart. Returns the bottom Y.
    @discardableResult
    static func drawBarChart(
        context: CGContext,
        dataPoints: [DataPoint],
        rect: CGRect,
        barColor: UIColor,
        yAxisLabel: String,
        yMin: Double = 0,
        yMax: Double = 12
    ) -> CGFloat {
        guard !dataPoints.isEmpty else { return rect.maxY }

        let labelFont = UIFont.systemFont(ofSize: 8)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: labelColor
        ]

        let leftInset: CGFloat = 30
        let bottomInset: CGFloat = 18
        let chartRect = CGRect(
            x: rect.minX + leftInset,
            y: rect.minY,
            width: rect.width - leftInset,
            height: rect.height - bottomInset
        )

        yAxisLabel.draw(at: CGPoint(x: rect.minX, y: rect.minY), withAttributes: labelAttrs)
        drawGrid(context: context, rect: chartRect, yMin: yMin, yMax: yMax)

        let barCount = CGFloat(dataPoints.count)
        let spacing: CGFloat = max(1, chartRect.width / barCount * 0.2)
        let barWidth = (chartRect.width - spacing * (barCount + 1)) / barCount

        for (i, dp) in dataPoints.enumerated() {
            let normalized = min(max((dp.value - yMin) / (yMax - yMin), 0), 1)
            let barHeight = CGFloat(normalized) * chartRect.height
            let x = chartRect.minX + spacing + CGFloat(i) * (barWidth + spacing)
            let barRect = CGRect(
                x: x,
                y: chartRect.maxY - barHeight,
                width: barWidth,
                height: barHeight
            )

            context.setFillColor(barColor.cgColor)
            context.fill(barRect)
        }

        // X-axis labels
        let indices = xLabelIndices(count: dataPoints.count)
        for i in indices {
            let x = chartRect.minX + spacing + CGFloat(i) * (barWidth + spacing)
            let shortLabel = String(dataPoints[i].label.suffix(5))
            shortLabel.draw(at: CGPoint(x: x, y: chartRect.maxY + 2), withAttributes: labelAttrs)
        }

        return rect.maxY
    }

    // MARK: - Horizontal Bar Chart

    /// Draws a horizontal bar chart for per-item comparisons (e.g., medication adherence).
    @discardableResult
    static func drawHorizontalBarChart(
        context: CGContext,
        items: [BarItem],
        rect: CGRect,
        barColor: UIColor = UIColor.systemBlue
    ) -> CGFloat {
        guard !items.isEmpty else { return rect.minY }

        let labelFont = UIFont.systemFont(ofSize: 9)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: UIColor.darkGray
        ]
        let percentAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: UIColor.darkGray
        ]

        let labelWidth: CGFloat = 120
        let barHeight: CGFloat = 14
        let rowHeight: CGFloat = 22
        let maxBarWidth = rect.width - labelWidth - 50
        var y = rect.minY

        for item in items {
            // Label
            let truncated = item.label.count > 18 ? String(item.label.prefix(16)) + "…" : item.label
            truncated.draw(at: CGPoint(x: rect.minX, y: y), withAttributes: labelAttrs)

            // Bar background
            let bgRect = CGRect(x: rect.minX + labelWidth, y: y + 1, width: maxBarWidth, height: barHeight)
            context.setFillColor(UIColor(white: 0.92, alpha: 1).cgColor)
            context.fill(bgRect)

            // Bar fill
            let fillWidth = maxBarWidth * CGFloat(min(max(item.value, 0), 1))
            let fillRect = CGRect(x: rect.minX + labelWidth, y: y + 1, width: fillWidth, height: barHeight)
            context.setFillColor(barColor.cgColor)
            context.fill(fillRect)

            // Percentage label
            let pct = "\(Int((item.value * 100).rounded()))%"
            pct.draw(at: CGPoint(x: rect.minX + labelWidth + maxBarWidth + 6, y: y), withAttributes: percentAttrs)

            y += rowHeight
        }

        return y
    }

    // MARK: - Helpers

    /// Maps data values to CGPoint coordinates within the given rect.
    static func mapDataToPoints(
        data: [DataPoint],
        rect: CGRect,
        yMin: Double,
        yMax: Double
    ) -> [CGPoint] {
        guard !data.isEmpty else { return [] }
        guard data.count > 1 else {
            let normalized = min(max((data[0].value - yMin) / (yMax - yMin), 0), 1)
            return [CGPoint(x: rect.midX, y: rect.maxY - CGFloat(normalized) * rect.height)]
        }

        let xStep = rect.width / CGFloat(data.count - 1)
        let range = yMax - yMin
        guard range > 0 else {
            return data.enumerated().map { (i, _) in
                CGPoint(x: rect.minX + CGFloat(i) * xStep, y: rect.midY)
            }
        }

        return data.enumerated().map { (i, dp) in
            let normalized = min(max((dp.value - yMin) / range, 0), 1)
            return CGPoint(
                x: rect.minX + CGFloat(i) * xStep,
                y: rect.maxY - CGFloat(normalized) * rect.height
            )
        }
    }

    private static func drawGrid(context: CGContext, rect: CGRect, yMin: Double, yMax: Double) {
        context.saveGState()
        context.setStrokeColor(gridColor.cgColor)
        context.setLineWidth(0.5)

        let gridLines = 4
        for i in 0...gridLines {
            let y = rect.minY + CGFloat(i) * rect.height / CGFloat(gridLines)
            context.move(to: CGPoint(x: rect.minX, y: y))
            context.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        context.strokePath()

        // Y-axis labels
        let labelFont = UIFont.systemFont(ofSize: 7)
        let attrs: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: labelColor]
        for i in 0...gridLines {
            let val = yMax - (yMax - yMin) * Double(i) / Double(gridLines)
            let y = rect.minY + CGFloat(i) * rect.height / CGFloat(gridLines)
            String(format: "%.0f", val).draw(at: CGPoint(x: rect.minX - 18, y: y - 4), withAttributes: attrs)
        }

        context.restoreGState()
    }

    private static func xLabelIndices(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        if count <= 3 { return Array(0..<count) }
        return [0, count / 2, count - 1]
    }
}
#endif
