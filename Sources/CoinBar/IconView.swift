import SwiftUI

extension Color {
    init(hex: UInt) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: 1)
    }
}

/// 1024×1024 应用图标:深色圆角方 + 上扬的行情曲线 + 末端发光价格点。
struct IconView: View {
    // 1024 画布内、居中 824 圆角矩形(x/y: 100…924)以内的折线点。
    private let pts: [CGPoint] = [
        CGPoint(x: 210, y: 720), CGPoint(x: 360, y: 560), CGPoint(x: 490, y: 645),
        CGPoint(x: 620, y: 415), CGPoint(x: 760, y: 500), CGPoint(x: 880, y: 300),
    ]
    private let green = Color(hex: 0x16C784)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x222C42), Color(hex: 0x0B0D13)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 2)
                        .frame(width: 824, height: 824)
                )
                .shadow(color: .black.opacity(0.35), radius: 30, y: 12)

            area.fill(LinearGradient(colors: [green.opacity(0.40), green.opacity(0.0)],
                                     startPoint: .top, endPoint: .bottom))
            line.stroke(green, style: StrokeStyle(lineWidth: 42, lineCap: .round, lineJoin: .round))

            // 末端价格点 + 柔光
            Circle().fill(green).frame(width: 70, height: 70)
                .position(pts.last!)
                .shadow(color: green.opacity(0.7), radius: 34)
            Circle().strokeBorder(.white.opacity(0.95), lineWidth: 9)
                .frame(width: 70, height: 70).position(pts.last!)
        }
        .frame(width: 1024, height: 1024)
    }

    private var line: Path {
        var p = Path()
        p.move(to: pts[0])
        pts.dropFirst().forEach { p.addLine(to: $0) }
        return p
    }
    private var area: Path {
        var p = line
        p.addLine(to: CGPoint(x: pts.last!.x, y: 820))
        p.addLine(to: CGPoint(x: pts.first!.x, y: 820))
        p.closeSubpath()
        return p
    }
}
