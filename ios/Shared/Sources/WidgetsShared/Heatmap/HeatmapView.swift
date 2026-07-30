import SwiftUI

public struct HeatmapView: View {
    public let metric: SnapshotMetric
    public let weeks: Int
    public let endDate: Date
    public let cellSize: CGFloat
    public let cellSpacing: CGFloat
    public let cornerRadius: CGFloat
    public let timeZone: TimeZone

    public init(
        metric: SnapshotMetric,
        weeks: Int = 53,
        endDate: Date = Date(),
        cellSize: CGFloat = 11,
        cellSpacing: CGFloat = 2,
        cornerRadius: CGFloat = 2,
        timeZone: TimeZone = .current
    ) {
        self.metric = metric
        self.weeks = weeks
        self.endDate = endDate
        self.cellSize = cellSize
        self.cellSpacing = cellSpacing
        self.cornerRadius = cornerRadius
        self.timeZone = timeZone
    }

    public var body: some View {
        let palette = Palette.resolve(metric.color)
        let cells = computeCells()
        let total = metric.totalLastYear()

        HStack(alignment: .top, spacing: cellSpacing) {
            ForEach(0..<weeks, id: \.self) { week in
                VStack(spacing: cellSpacing) {
                    ForEach(0..<7, id: \.self) { day in
                        let cell = cells[week][day]
                        if cell.isPlaceholder {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(.clear)
                                .frame(width: cellSize, height: cellSize)
                        } else {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(palette.color(for: cell.bucket))
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
        }
        // VoiceOver: combine the 365 cells into one summary so it's not read
        // cell-by-cell. Adds an actionless overview the user can navigate past.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.name) heatmap, \(weeks) weeks, \(Int(total)) total entries")
    }

    /// Builds a [weeks][7] grid where the rightmost column ends on `endDate`.
    /// Days are aligned by weekday (Sunday-first). Cells before metric start render as placeholders.
    private func computeCells() -> [[Cell]] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.firstWeekday = 1

        let endWeekday = cal.component(.weekday, from: endDate)
        let trailingPlaceholders = 7 - endWeekday
        let totalDays = weeks * 7

        var grid = Array(repeating: Array(repeating: Cell(bucket: 0, isPlaceholder: true), count: 7), count: weeks)

        for index in 0..<totalDays {
            let dayOffset = (totalDays - 1 - trailingPlaceholders) - index
            guard dayOffset >= 0 else { continue }
            guard let date = cal.date(byAdding: .day, value: -dayOffset, to: endDate) else { continue }
            let count = metric.count(on: date, timeZone: timeZone)
            let bucket = Thresholds.bucket(for: count, thresholds: metric.thresholds)

            let week = index / 7
            let day = index % 7
            grid[week][day] = Cell(bucket: bucket, isPlaceholder: false)
        }
        return grid
    }

    private struct Cell {
        let bucket: Int
        let isPlaceholder: Bool
    }
}

#Preview("GitHub Green — full year") {
    HeatmapView(metric: .preview)
        .padding()
}

#Preview("Small — 13 weeks") {
    HeatmapView(metric: .preview, weeks: 13, cellSize: 9, cellSpacing: 2)
        .padding()
}

public extension SnapshotMetric {
    static var preview: SnapshotMetric {
        var days: [String: Double] = [:]
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let today = Date()
        for offset in 0..<365 {
            if let d = cal.date(byAdding: .day, value: -offset, to: today) {
                let key = SnapshotMetric.dateKey(for: d)
                let bucket = Int.random(in: 0...4)
                let value: Double
                switch bucket {
                case 0: value = 0
                case 1: value = 1
                case 2: value = 3
                case 3: value = 5
                default: value = 8
                }
                days[key] = value
            }
        }
        return SnapshotMetric(
            id: "preview",
            name: "Sales calls",
            kind: .manual,
            color: .githubGreen,
            thresholds: MetricKind.manual.defaultThresholds,
            days: days
        )
    }
}
