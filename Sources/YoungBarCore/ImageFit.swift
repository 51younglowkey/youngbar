// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation // CGFloat / CGRect on Linux, where only the core is built and tested
#endif

/// Fitting a picture into a square button without distorting it.
public enum ImageFit {
    /// `size` scaled to fit inside `box`, keeping its proportions, centred.
    /// A degenerate size fills the box.
    public static func aspectFit(_ size: CGSize, in box: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0, box.width > 0, box.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: box.midX - fitted.width / 2, y: box.midY - fitted.height / 2,
                      width: fitted.width, height: fitted.height)
    }
}
