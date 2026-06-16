import SwiftUI
import AppKit

/// 离屏把弹出面板渲染成 PNG —— 用于无需点击就能预览/迭代设计。
/// 用法:CoinBar --render-popover /tmp/out.png
enum Screenshot {
    @MainActor
    static func renderPopover(to path: String, skin: Skin = .lightNative) {
        let model = TickerModel.mock()
        let view = PopoverView(preview: true)
            .environmentObject(model)
            .environment(\.skin, skin)
            .frame(width: 330, height: 360)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        guard let img = renderer.nsImage,
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("render failed\n".utf8))
            exit(1)
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        } catch {
            FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
            exit(1)
        }
        exit(0)
    }
}
