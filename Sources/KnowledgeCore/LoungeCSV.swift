import Foundation

public enum LoungeCSV {
    public static func rows(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            text.formIndex(after: &index)
            if char == "\"" {
                if quoted, index < text.endIndex, text[index] == "\"" {
                    field.append(char)
                    text.formIndex(after: &index)
                } else if field.isEmpty || quoted {
                    quoted.toggle()
                } else { field.append(char) }
            } else if char == ",", !quoted {
                row.append(field)
                field = ""
            } else if char.isNewline, !quoted {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(char)
            }
        }
        guard !quoted else { throw LibraryError.invalid("CSV 的引号未闭合") }
        if !field.isEmpty || !row.isEmpty { rows.append(row + [field]) }
        return rows
    }
}
