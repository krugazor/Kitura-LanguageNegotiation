import Foundation

// Workaround/hack for differing methods in macOS vs Linux.

#if os(Linux)
    extension TextCheckingResult {
        /// Add the `rangeAt` method as a wrapper around the `range` method; the
        /// former is available on macOS, but the latter is available on Linux.
        func rangeAt(_ idx: Int) -> Foundation.NSRange {
            return self.range(at: idx)
        }
    }
#endif

