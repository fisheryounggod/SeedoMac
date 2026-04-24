// Seedo/Views/Dashboard/AIReviewView.swift
import SwiftUI

struct AIReviewView: View {
    @State private var internalContent: String
    let label: String
    let onSave: ((String) -> Void)?
    let onClose: () -> Void
    
    @State private var isEditing: Bool = false
    
    init(content: String, label: String, onSave: ((String) -> Void)? = nil, onClose: @escaping () -> Void) {
        _internalContent = State(initialValue: content)
        self.label = label
        self.onSave = onSave
        self.onClose = onClose
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(isEditing ? "编辑复盘报告: \(label)" : "AI 深度复盘: \(label)", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.purple)
                Spacer()
                
                if onSave != nil {
                    Button(action: { 
                        if isEditing {
                            onSave?(internalContent)
                            isEditing = false
                        } else {
                            isEditing = true
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil.circle")
                            Text(isEditing ? "完成" : "编辑")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isEditing ? .green : .blue)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                }

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)
            
            Divider()
            
            if isEditing {
                TextEditor(text: $internalContent)
                    .font(.system(size: 14))
                    .padding(8)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))
            } else {
                ScrollView {
                    MarkdownView(text: internalContent)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            
            Spacer()
            
            HStack {
                Spacer()
                Text(onSave == nil ? "此结果为展示项，修改需通过历史记录" : "修改内容将同步至数据库")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(minWidth: 550, minHeight: 650)
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
