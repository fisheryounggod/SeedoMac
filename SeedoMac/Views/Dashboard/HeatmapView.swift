// SeedoMac/Views/Dashboard/HeatmapView.swift
import SwiftUI

struct HeatmapView: View {
    let days: [HeatmapDay]
    private let cellSize: CGFloat = 12
    private let cellSpacing: CGFloat = 2
    private let weekCount = 53

    // Sparse → dense 7×53 grid (nil = no data for that day)
    private var grid: [[HeatmapDay?]] {
        var byWeek: [[HeatmapDay?]] = Array(
            repeating: Array(repeating: nil, count: 7),
            count: weekCount
        )
        for day in days {
            let w = min(day.weekIndex, weekCount - 1)
            let d = min(day.weekdayIndex, 6)
            byWeek[w][d] = day
        }
        return byWeek
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: cellSpacing) {
                ForEach(0..<weekCount, id: \.self) { week in
                    VStack(spacing: cellSpacing) {
                        ForEach(0..<7, id: \.self) { day in
                            let entry = grid[week][day]
                            RoundedRectangle(cornerRadius: 2)
                                .fill(heatmapColor(for: entry?.totalSecs ?? 0))
                                .frame(width: cellSize, height: cellSize)
                                .help(entry.map {
                                    "\($0.date): \(heatmapLabel($0.totalSecs))"
                                } ?? "")
                        }
                    }
                }
            }
            .padding(4)
        }
    }

    private func heatmapColor(for secs: Double) -> Color {
        switch secs {
        case ..<1:       return Color.gray.opacity(0.15)
        case ..<1800:    return Color.green.opacity(0.3)   // < 30m
        case ..<7200:    return Color.green.opacity(0.6)   // < 2h
        case ..<14400:   return Color.green.opacity(0.85)  // < 4h
        default:         return Color.green
        }
    }

    private func heatmapLabel(_ secs: Double) -> String {
        let h = Int(secs) / 3600
        let m = (Int(secs) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
