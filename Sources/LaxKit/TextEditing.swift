/// Editing a draft by character offsets, which stay valid whatever happens to the string.
public enum TextEditing {
    /// `text` with the characters in `range` (clamped to the text) replaced by `insertion`,
    /// and the cursor's offset just after it.
    public static func replacing(_ range: Range<Int>, in text: String, with insertion: String) -> (
        text: String, cursor: Int
    ) {
        let lower = min(max(range.lowerBound, 0), text.count)
        let upper = min(max(range.upperBound, lower), text.count)
        let start = text.index(text.startIndex, offsetBy: lower)
        let end = text.index(start, offsetBy: upper - lower)
        return (String(text[..<start]) + insertion + text[end...], lower + insertion.count)
    }
}
