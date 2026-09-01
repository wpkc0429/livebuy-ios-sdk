import Foundation

// MARK: - VTTSubtitleParser — WebVTT parsing pipeline (rb-ios-subtitle-vtt-caption-display)
//
// Spec: `reference-ui-rendering/spec.md` §「PlayerShellView 依 isLive 切 LIVE/VOD 版型並渲染 VOD
// chrome」「VOD 字幕來源（effectiveCaption）」子句.
//
// Core exposes only `SubtitleTrack.{available,enabled}` (booleans) — there is NO active-caption
// TEXT source. `channel.subtitle_url` points at a WebVTT file the turnkey container fetches and
// parses itself (see `LivebuyPlayer.fetchAndApplySubtitleCues`); this file is the pure, offline-
// testable parsing half of that pipeline. Deliberately dependency-free (no SwiftUI / Combine /
// reference-ui types) so it is trivial to unit test and easy for a future Android/RN/Flutter port
// to translate rule-for-rule (NOT code-for-code — see design.md Decision 3).

/// A single parsed WebVTT cue: a `[start, end)` time window and its display text.
public struct VTTCue: Equatable {
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String

    public init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// Pure WebVTT parsing + time-indexed cue lookup. No I/O, no side effects — the network fetch
/// lives in `LivebuyPlayer.swift` (the reference-ui container), which feeds this parser raw text.
enum VTTSubtitleParser {

    /// Parse raw WebVTT text into an ordered `[VTTCue]`. Decode-tolerant (mirrors the repo's
    /// existing JSON-decoder-fallback philosophy, CLAUDE.md "JSON decoder fallback"): a missing
    /// `WEBVTT` header, cue-identifier lines, `NOTE` blocks, and cue settings trailing the
    /// timestamp line (e.g. `align:middle`) are all tolerated; a single malformed cue block is
    /// skipped without discarding the rest of the file. Empty / entirely unparsable input -> `[]`.
    static func parse(_ raw: String) -> [VTTCue] {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        var cues: [VTTCue] = []
        for block in blocks {
            if let cue = parseBlock(block) {
                cues.append(cue)
            }
        }
        return cues
    }

    /// Parse ONE cue block (the lines between two blank-line separators). A block may open with
    /// a `WEBVTT` header line, a `NOTE` comment, or a bare cue-identifier line — all skipped while
    /// scanning forward for the first line containing `-->` (the timestamp line). Returns `nil`
    /// when no timestamp line is found, the timestamps fail to parse, or no non-empty text
    /// follows (all treated as "not a real cue", not a fatal error for the rest of `parse`).
    private static func parseBlock(_ block: String) -> VTTCue? {
        let lines = block.components(separatedBy: "\n")
        guard let timestampIndex = lines.firstIndex(where: { $0.contains("-->") }) else {
            return nil
        }
        let timestampLine = lines[timestampIndex]
        guard let (start, end) = parseTimestampLine(timestampLine) else { return nil }

        let text = lines[(timestampIndex + 1)...]
            .map(stripInlineTags)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !text.isEmpty else { return nil }
        return VTTCue(start: start, end: end, text: text)
    }

    /// Parse a `"<start> --> <end> [cue settings...]"` line into `(start, end)` seconds. Cue
    /// settings after the end timestamp (e.g. `align:middle line:90%`) are ignored — only the
    /// first two whitespace-separated tokens either side of `-->` are consumed.
    private static func parseTimestampLine(_ line: String) -> (TimeInterval, TimeInterval)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count >= 2 else { return nil }
        guard let start = parseTimestamp(parts[0]) else { return nil }
        // The end side may carry trailing cue settings after the timestamp token; take only
        // the first whitespace-separated token.
        let endToken = parts[1].trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces).first ?? ""
        guard let end = parseTimestamp(endToken) else { return nil }
        return (start, end)
    }

    /// Parse a single VTT timestamp token — `HH:MM:SS.mmm` or the shorter `MM:SS.mmm` — into
    /// seconds. Any other shape -> `nil` (the caller skips the enclosing cue, not the whole file).
    private static func parseTimestamp(_ raw: String) -> TimeInterval? {
        let token = raw.trimmingCharacters(in: .whitespaces)
        let secAndMs = token.split(separator: ".")
        guard secAndMs.count == 1 || secAndMs.count == 2 else { return nil }

        let hms = secAndMs[0].split(separator: ":").map(String.init)
        let milliseconds: TimeInterval
        if secAndMs.count == 2 {
            // Pad/truncate to exactly 3 digits so "5" -> 500ms, "500" -> 500ms, "5000" invalid.
            let msString = String(secAndMs[1])
            guard msString.count <= 3, let msValue = Double(msString) else { return nil }
            let scale = pow(10.0, Double(3 - msString.count))
            milliseconds = msValue * scale / 1000.0
        } else {
            milliseconds = 0
        }

        switch hms.count {
        case 3:
            guard let h = Double(hms[0]), let m = Double(hms[1]), let s = Double(hms[2]) else { return nil }
            return h * 3600 + m * 60 + s + milliseconds
        case 2:
            guard let m = Double(hms[0]), let s = Double(hms[1]) else { return nil }
            return m * 60 + s + milliseconds
        default:
            return nil
        }
    }

    /// Strip WebVTT inline cue-span tags (`<b>`, `</i>`, `<c.classname>`, `<00:00:01.000>`, ...)
    /// from a cue text line. The result feeds a plain SwiftUI `Text` (`CaptionOverlayView`), which
    /// does not interpret markup — leaving tags in would show literal `<i>...</i>` on screen. This
    /// is a simple regex strip, not full VTT cue-span style support (design.md Non-Goals).
    private static func stripInlineTags(_ line: String) -> String {
        guard line.contains("<") else { return line }
        var result = ""
        var insideTag = false
        for ch in line {
            if ch == "<" {
                insideTag = true
            } else if ch == ">" {
                insideTag = false
            } else if !insideTag {
                result.append(ch)
            }
        }
        return result
    }

    /// Find the cue whose `[start, end)` window contains `time` (start inclusive, end exclusive).
    /// `cues` need not be sorted. Multiple overlapping matches -> the first one found (overlapping
    /// cue stacking is out of scope, design.md Non-Goals). No match -> `nil`.
    static func activeCue(_ cues: [VTTCue], at time: TimeInterval) -> VTTCue? {
        cues.first { $0.start <= time && time < $0.end }
    }
}
