// SeedoMac/Views/Dashboard/CategoryView.swift
import SwiftUI

// A single rule entry in the editor (not persisted directly — encoded to JSON)
struct RuleEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var field: String = "app"       // "app" | "title"
    var op: String    = "contains"  // "contains" | "equals"
    var value: String = ""
}

struct CategoryView: View {
    @State private var categories: [Category] = []
    @State private var selected: Category?
    @State private var editName: String = ""
    @State private var editColor: String = "#4A90D9"
    @State private var editRules: [RuleEntry] = []
    @State private var isDirty = false

    private let store = CategoryStore()

    var body: some View {
        HSplitView {
            categoryList
            if selected != nil {
                ruleEditor
            } else {
                Text("Select a category to edit")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { loadCategories() }
    }

    // MARK: - Left Panel: Category List

    private var categoryList: some View {
        VStack(spacing: 0) {
            List(categories, id: \.id, selection: $selected) { cat in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: cat.color))
                        .frame(width: 10, height: 10)
                    Text(cat.name)
                }
                .tag(cat)
            }
            .onChange(of: selected) { cat in loadEdit(cat) }

            Divider()

            HStack {
                Button {
                    addCategory()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .padding(4)

                Spacer()

                Button {
                    deleteSelected()
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selected == nil)
                .padding(4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(minWidth: 160, maxWidth: 220)
    }

    // MARK: - Right Panel: Rule Editor

    private var ruleEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Category")
                .font(.headline)

            // Name + Color
            HStack {
                TextField("Name", text: $editName)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: editName) { _ in isDirty = true }

                ColorPicker("", selection: Binding(
                    get: { Color(hex: editColor) },
                    set: { newColor in
                        editColor = newColor.toHex()
                        isDirty = true
                    }
                ))
                .frame(width: 36)
                .labelsHidden()
            }

            // Rules
            Text("Match Rules (OR logic)")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                ForEach($editRules) { $rule in
                    HStack(spacing: 6) {
                        Picker("", selection: $rule.field) {
                            Text("App Name").tag("app")
                            Text("Window Title").tag("title")
                        }
                        .frame(width: 120)
                        .onChange(of: rule.field) { _ in isDirty = true }

                        Picker("", selection: $rule.op) {
                            Text("contains").tag("contains")
                            Text("equals").tag("equals")
                        }
                        .frame(width: 90)
                        .onChange(of: rule.op) { _ in isDirty = true }

                        TextField("value", text: $rule.value)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: rule.value) { _ in isDirty = true }

                        Button {
                            editRules.removeAll { $0.id == rule.id }
                            isDirty = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Button("+ Add Rule") {
                editRules.append(RuleEntry())
                isDirty = true
            }
            .buttonStyle(.borderless)
            .font(.caption)

            Spacer()

            HStack {
                Spacer()
                Button("Save") { saveEdit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isDirty)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Actions

    private func loadCategories() {
        categories = (try? store.allCategories()) ?? []
    }

    private func loadEdit(_ cat: Category?) {
        guard let cat else {
            editRules = []; editName = ""; editColor = "#4A90D9"; isDirty = false
            return
        }
        editName  = cat.name
        editColor = cat.color
        let data  = Data(cat.rules.utf8)
        editRules = (try? JSONDecoder().decode([RuleEntry].self, from: data)) ?? []
        isDirty   = false
    }

    private func addCategory() {
        let newCat = Category(id: UUID().uuidString, name: "New Category",
                              color: "#4A90D9", rules: "[]")
        try? store.save(newCat)
        loadCategories()
        selected = categories.first(where: { $0.id == newCat.id })
    }

    private func deleteSelected() {
        guard let cat = selected else { return }
        try? store.delete(id: cat.id)
        selected = nil
        loadCategories()
    }

    private func saveEdit() {
        guard var cat = selected else { return }
        cat.name  = editName
        cat.color = editColor
        // Strip UUID before encoding (only store field/op/value)
        let stripped = editRules.map {
            CategoryRuleEntry(field: $0.field, op: $0.op, value: $0.value)
        }
        cat.rules = (try? String(data: JSONEncoder().encode(stripped), encoding: .utf8)) ?? "[]"
        try? store.save(cat)
        isDirty = false
        loadCategories()
        selected = categories.first(where: { $0.id == cat.id })
    }
}

// MARK: - Color.toHex() helper (AppKit-backed)

extension Color {
    func toHex() -> String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return String(format: "#%02X%02X%02X",
                      Int(ns.redComponent   * 255),
                      Int(ns.greenComponent * 255),
                      Int(ns.blueComponent  * 255))
    }
}
