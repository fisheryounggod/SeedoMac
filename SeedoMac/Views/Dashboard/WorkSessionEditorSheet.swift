// SeedoMac/Views/Dashboard/WorkSessionEditorSheet.swift
import SwiftUI

struct WorkSessionEditorSheet: View {
    @State var session: WorkSession
    let onSave: (WorkSession) -> Void
    let onCancel: () -> Void

    private var startDate: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: Double(session.startTs) / 1000) },
            set: { session.startTs = Int64($0.timeIntervalSince1970 * 1000) }
        )
    }

    private var endDate: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: Double(session.endTs) / 1000) },
            set: { session.endTs = Int64($0.timeIntervalSince1970 * 1000) }
        )
    }

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
                
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("开始时间").font(.caption).foregroundStyle(.secondary)
                        DatePicker("", selection: startDate, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .datePickerStyle(.compact)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("结束时间").font(.caption).foregroundStyle(.secondary)
                        DatePicker("", selection: endDate, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .datePickerStyle(.compact)
                    }
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

            HStack {
                Spacer()
                Button("取消") { onCancel() }
                Button("保存") {
                    // Update duration based on final start/end times before saving
                    session.durationSecs = Double(session.endTs - session.startTs) / 1000.0
                    onSave(session)
                }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
