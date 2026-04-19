// SeedoMac/Views/Dashboard/AIReviewView.swift
import SwiftUI

struct AIReviewView: View {
    let content: String
    let label: String
    let onClose: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("AI 深度复盘: \(label)", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.purple)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)
            
            Divider()
            
            ScrollView {
                MarkdownView(text: content)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Spacer()
            
            HStack {
                Spacer()
                Text("此结果为临时生成，未保存至数据库或记录本")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(minWidth: 500, minHeight: 600)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
