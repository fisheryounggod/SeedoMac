// Seedo/Views/Dashboard/MarkdownView.swift
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
        
        VStack(alignment: .leading, spacing: 16) {
            ForEach(0..<blocks.count, id: \.self) { index in
                renderBlock(blocks[index])
            }
        }
    }
    
    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .header(let level, let t):
            VStack(alignment: .leading, spacing: 4) {
                Text(t)
                    .font(.system(size: level == 1 ? 22 : (level == 2 ? 18 : 16), weight: .bold, design: .rounded))
                    .foregroundStyle(level == 1 ? Color.primary : Color.primary.opacity(0.9))
                if level == 1 {
                    Divider().opacity(0.3)
                }
            }
            .padding(.top, level == 1 ? 8 : 4)
            .padding(.bottom, 4)
            
        case .text(let t):
            let attr = parseAttributedString(t.trimmingCharacters(in: .newlines))
            Text(attr)
                .lineSpacing(4)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: false)
                
        case .table(let t):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(t.trimmingCharacters(in: .newlines))
                    .font(.system(.caption, design: .monospaced))
                    .padding(12)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            }
            
        case .code(let t):
            Text(t.trimmingCharacters(in: .newlines))
                .font(.system(.subheadline, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(8)
                
        case .divider:
            Divider().opacity(0.2).padding(.vertical, 8)
            
        case .quote(let t):
            HStack(spacing: 12) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.5))
                    .frame(width: 3)
                Text(parseAttributedString(t))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
    
    private func computeBlocks(_ raw: String) -> [MarkdownBlock] {
        let lines = raw.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        
        var currentText = ""
        var currentTable = ""
        var isInTable = false
        var currentCode = ""
        var isInCode = false
        
        func flushText() {
            if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.text(currentText))
                currentText = ""
            }
        }
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Code block
            if trimmed.starts(with: "```") {
                if isInCode {
                    blocks.append(.code(currentCode))
                    currentCode = ""
                    isInCode = false
                } else {
                    flushText()
                    isInCode = true
                }
                continue
            }
            
            if isInCode {
                currentCode += line + "\n"
                continue
            }
            
            // Headers
            if trimmed.starts(with: "#") {
                flushText()
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let title = trimmed.drop(while: { $0 == "#" || $0 == " " })
                blocks.append(.header(level, String(title)))
                continue
            }
            
            // Divider
            if trimmed == "---" || trimmed == "***" || trimmed == "--- " {
                flushText()
                blocks.append(.divider)
                continue
            }
            
            // Quote
            if trimmed.starts(with: ">") {
                flushText()
                let content = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                blocks.append(.quote(content))
                continue
            }
            
            // Table
            if trimmed.starts(with: "|") {
                flushText()
                isInTable = true
                currentTable += line + "\n"
                continue
            } else if isInTable {
                blocks.append(.table(currentTable))
                currentTable = ""
                isInTable = false
            }
            
            currentText += line + "\n"
        }
        
        flushText()
        if isInTable { blocks.append(.table(currentTable)) }
        if isInCode { blocks.append(.code(currentCode)) }
        
        return blocks
    }
    
    private enum MarkdownBlock {
        case header(Int, String)
        case text(String)
        case table(String)
        case code(String)
        case quote(String)
        case divider
    }
    
    private func parseAttributedString(_ raw: String) -> AttributedString {
        var str = raw
        
        // 1. Convert [[link]] to markdown links with internal scheme
        str = str.replacingOccurrences(of: "\\[\\[(.*?)\\]\\]", with: "[$1](internal://$1)", options: .regularExpression)
        
        // 2. Initial MD parse
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full 
        var attrStr = (try? AttributedString(markdown: str, options: options)) ?? AttributedString(str)
        
        // 3. Styling passes
        for run in attrStr.runs {
            // Internal links
            if let url = run.link, url.scheme == "internal" {
                let range = run.range
                attrStr[range].link = nil 
                attrStr[range].foregroundColor = Color.accentColor
                attrStr[range].underlineStyle = Text.LineStyle.single
            }
        }
        
        // 4. Handle ==highlight==
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
                highlighted.inlinePresentationIntent = InlinePresentationIntent.stronglyEmphasized
                
                attrStr.replaceSubrange(range, with: highlighted)
            }
        }
        
        // 5. Emoji Semantic Coloring Pass
        let runs = attrStr.runs
        for run in runs {
            let runText = String(attrStr[run.range].characters)
            if runText.contains("🔴") || runText.contains("❌") {
                attrStr[run.range].foregroundColor = .red
            } else if runText.contains("🟢") || runText.contains("✅") {
                attrStr[run.range].foregroundColor = .green
            } else if runText.contains("🔵") {
                attrStr[run.range].foregroundColor = .blue
            } else if runText.contains("🟡") || runText.contains("⚠️") {
                attrStr[run.range].foregroundColor = .orange
            }
        }
        
        return attrStr
    }
}
