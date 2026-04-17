// SeedoMac/Views/Dashboard/WorkSessionEditorSheet.swift
import SwiftUI

struct WorkSessionEditorSheet: View {
    @State var session: WorkSession
    let onSave: (WorkSession) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(session.isManual ? "编辑手动活动" : "编辑专注段")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("标题").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $session.summary)
                        .font(.body)
                        .frame(minHeight: 80)
                        .padding(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3))
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("备注").font(.caption).foregroundStyle(.secondary)
                    TextField("输入具体活动或上下文", text: $session.title)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("类别").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $session.categoryId) {
                        Text("未分类").tag(nil as String?)
                        ForEach(SessionCategory.all) { cat in
                            Label {
                                Text(cat.name)
                            } icon: {
                                Circle().fill(cat.color).frame(width: 8, height: 8)
                            }
                            .tag(cat.id as String?)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }

            let date = Date(timeIntervalSince1970: Double(session.startTs) / 1000)
            Text("记录于: " + date.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            HStack {
                Spacer()
                Button("取消") { onCancel() }
                Button("保存") { onSave(session) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
