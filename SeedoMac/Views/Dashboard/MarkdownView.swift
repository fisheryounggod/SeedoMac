// SeedoMac/Views/Dashboard/MarkdownView.swift
import SwiftUI

struct MarkdownView: View {
    let text: String
    var lineLimit: Int? = nil
    
    var body: some View {
        renderContent(text)
    }
    
    @ViewBuilder
    private func renderContent(_ raw: String) -> some View {
        let blocks = computeBlocks(raw)
        
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<blocks.count, id: \.self) { index in
                switch blocks[index] {
                case .text(let t):
                    let attr = parseAttributedString(t.trimmingCharacters(in: .newlines))
                    Text(attr)
                        .lineLimit(lineLimit)
                        .fixedSize(horizontal: false, vertical: false) // Changed from vertical: true to allow expansion
                case .table(let t):
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(t.trimmingCharacters(in: .newlines))
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                            )
                    }
                }
            }
        }
    }
    
    private func computeBlocks(_ raw: String) -> [MarkdownBlock] {
        let lines = raw.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        
        var currentText = ""
        var isInTable = false
        var currentTable = ""
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.starts(with: "|") {
                if !currentText.isEmpty {
                    blocks.append(.text(currentText))
                    currentText = ""
                }
                isInTable = true
                currentTable += line + "\n"
            } else {
                if isInTable {
                    blocks.append(.table(currentTable))
                    currentTable = ""
                    isInTable = false
                }
                currentText += line + "\n"
            }
        }
        
        if !currentText.isEmpty {
            blocks.append(.text(currentText))
        }
        if isInTable {
            blocks.append(.table(currentTable))
        }
        return blocks
    }
    
    private enum MarkdownBlock {
        case text(String)
        case table(String)
    }
    
    private func parseAttributedString(_ raw: String) -> AttributedString {
        var str = raw
        
        // 1. Convert [[link]] to markdown links with internal scheme
        str = str.replacingOccurrences(of: "\\[\\[(.*?)\\]\\]", with: "[$1](internal://$1)", options: .regularExpression)
        
        // 2. Initial MD parse
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace // Back to safe one or use full name if I can find it
        var attrStr = (try? AttributedString(markdown: str, options: options)) ?? AttributedString(str)
        
        // 3. Handle ==highlight==
        let rawString = String(attrStr.characters)
        if let regex = try? NSRegularExpression(pattern: "==([^=]+)==", options: []) {
            let nsRange = NSRange(rawString.startIndex..<rawString.endIndex, in: rawString)
            let matches = regex.matches(in: rawString, options: [], range: nsRange).reversed()
            
            for match in matches {
                guard let range = Range(match.range, in: attrStr),
                      let innerRange = Range(match.range(at: 1), in: attrStr) else { continue }
                
                let content = attrStr[innerRange]
                var highlighted = AttributedString(content)
                highlighted.backgroundColor = Color.yellow.opacity(0.3)
                // Use a slightly bolder weight for highlights
                highlighted.inlinePresentationIntent = InlinePresentationIntent.stronglyEmphasized
                
                attrStr.replaceSubrange(range, with: highlighted)
            }
        }
        
        // 4. Style internal links
        for run in attrStr.runs {
            if let url = run.link, url.scheme == "internal" {
                let range = run.range
                attrStr[range].link = nil 
                attrStr[range].foregroundColor = Color.accentColor
                attrStr[range].underlineStyle = Text.LineStyle.single
            }
        }
        
        return attrStr
    }
}
