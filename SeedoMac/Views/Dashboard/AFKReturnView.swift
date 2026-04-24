// Seedo/Views/Dashboard/AFKReturnView.swift
import SwiftUI

struct AFKReturnView: View {
    let startTs: Int64
    let endTs: Int64
    let onSave: (WorkSession) -> Void
    let onDismiss: () -> Void
    
    @State private var summary: String = ""
    @State private var label: String = ""
    @State private var selectedCategoryId: String = "focus"
    @FocusState private var isFocused: Bool
    
    private var durationMins: Int {
        Int((endTs - startTs) / 60000)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("检测到一段离席/工作时间").font(.system(size: 14, weight: .bold))
                    Text("\(durationMins) 分钟 (\(formatTime(startTs)) - \(formatTime(endTs)))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("标题").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                TextField("这段时间在做什么？", text: $summary)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("分类").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(SessionCategory.all) { cat in
                        Button {
                            selectedCategoryId = cat.id
                        } label: {
                            HStack(spacing: 4) {
                                Circle().fill(cat.color).frame(width: 6, height: 6)
                                Text(cat.name).font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(selectedCategoryId == cat.id ? cat.color.opacity(0.15) : Color.primary.opacity(0.04))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(selectedCategoryId == cat.id ? cat.color.opacity(0.3) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Button(action: save) {
                Text("记录并关闭")
                    .font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(summary.isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(summary.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            isFocused = true
        }
    }
    
    private func save() {
        let session = WorkSession(
            startTs: startTs,
            endTs: endTs,
            topAppsJson: "[]",
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            outcome: "completed",
            createdAt: Int64(Date().timeIntervalSince1970 * 1000),
            isManual: true,
            title: "",
            categoryId: selectedCategoryId
        )
        onSave(session)
    }
    
    private func formatTime(_ ts: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(ts) / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
