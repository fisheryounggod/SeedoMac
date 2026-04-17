import SwiftUI

struct AFKReturnView: View {
    let startTs: Int64
    let endTs: Int64
    let onSave: (String) -> Void
    let onDismiss: () -> Void
    
    @State private var summary: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.walk.arrow.right")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            
            VStack(spacing: 8) {
                Text("欢迎回来")
                    .font(.title)
                
                let start = Date(timeIntervalSince1970: Double(startTs) / 1000)
                let end = Date(timeIntervalSince1970: Double(endTs) / 1000)
                let durationMins = Int((endTs - startTs) / 60000)
                
                Text("你离开了大约 \(durationMins) 分钟\n(\(start.formatted(date: .omitted, time: .shortened)) - \(end.formatted(date: .omitted, time: .shortened)))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("这段时间你在做离线活动吗？").font(.headline)
                TextEditor(text: $summary)
                    .frame(height: 80)
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
            }
            
            HStack(spacing: 16) {
                Button("忽略 (只是休息)") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                
                Button("记录为离线活动") {
                    onSave(summary)
                }
                .buttonStyle(.borderedProminent)
                .disabled(summary.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(30)
        .frame(width: 400)
    }
}
