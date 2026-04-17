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
        
        VStack(alignment: .leading, spacing: 12) { // Increased spacing between blocks
            ForEach(0..<blocks.count, id: \.self) { index in
                switch blocks[index] {
                case .text(let t):
                    let attr = parseAttributedString(t.trimmingCharacters(in: .newlines))
                    Text(attr)
                        .lineSpacing(6) // Improved line spacing
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
                }
            }
        }
    }
    
    // ... [rest of methods] ...
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
        options.interpretedSyntax = .full 
        var attrStr = (try? AttributedString(markdown: str, options: options)) ?? AttributedString(str)
        
        // 3. Styling passes
        for run in attrStr.runs {
            // Fix header sizes & weights
            if let intent = run.presentationIntent {
                for component in intent.components {
                    if case .header(let level) = component.kind {
                        let range = run.range
                        if level == 1 || level == 2 {
                            attrStr[range].font = .system(size: 18, weight: .bold, design: .rounded)
                            attrStr[range].foregroundColor = .primary
                        } else if level == 3 {
                            attrStr[range].font = .system(size: 15, weight: .bold, design: .rounded)
                            attrStr[range].foregroundColor = .secondary
                        }
                    }
                }
            }
            
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
        // Detect lines/segments starting with 🔴, 🟢, 🔵, 🟡 and color the whole run
        let runs = attrStr.runs
        for run in runs {
            let runText = String(attrStr[run.range].characters)
            if runText.starts(with: "🔴") {
                attrStr[run.range].foregroundColor = .red
            } else if runText.starts(with: "🟢") {
                attrStr[run.range].foregroundColor = .green
            } else if runText.starts(with: "🔵") {
                attrStr[run.range].foregroundColor = .blue
            } else if runText.starts(with: "🟡") {
                attrStr[run.range].foregroundColor = .orange
            }
        }
        
        return attrStr
    }
}
