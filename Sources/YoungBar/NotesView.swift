// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import YoungBarCore

/// Release notes drawn as a patch note: each section a small coloured
/// heading, each change one short line with a bullet.
struct NotesView: View {
    let blocks: [ReleaseNotes.Block]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                switch block {
                case .section(let title):
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                        .padding(.top, index == 0 ? 0 : 9)
                case .bullet(let text, let level):
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Circle().fill(.secondary).frame(width: 4, height: 4)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
                        Text(text).font(.system(size: 13))
                    }
                    .padding(.leading, CGFloat(level) * 14)
                case .text(let text):
                    Text(text).font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
