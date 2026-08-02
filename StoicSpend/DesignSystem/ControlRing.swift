import SwiftUI

/// 控制环 — 品牌签名视觉元素
/// 圆环 + 顶部刻度 + 中心实心圆点
/// 用 Circle() + .trim() + .stroke() 实现，不使用图片资源
/// 复用位置：启动加载态、首页小徽章、仪表盘大图、分享卡片
struct ControlRing: View {
    let progress: Double          // 0.0 ~ 1.0，可控支出占比
    let size: CGFloat
    let animated: Bool

    init(
        progress: Double = 0.0,
        size: CGFloat = DesignTokens.ControlRing.defaultSize,
        animated: Bool = true
    ) {
        self.progress = progress
        self.size = size
        self.animated = animated
    }

    @State private var displayProgress: Double = 0

    var body: some View {
        ZStack {
            // 背景环
            Circle()
                .stroke(DesignTokens.stoneDim, lineWidth: DesignTokens.ControlRing.lineWidth)
                .frame(width: size, height: size)

            // 进度环 — 可控部分（verdigris）
            if displayProgress > 0 {
                Circle()
                    .trim(from: 0, to: displayProgress)
                    .stroke(
                        DesignTokens.verdigris,
                        style: StrokeStyle(
                            lineWidth: DesignTokens.ControlRing.lineWidth,
                            lineCap: .round
                        )
                    )
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
            }

            // 顶部刻度 — stone 色，与图标一致，坐落在环上 12 点位置
            Rectangle()
                .fill(DesignTokens.stone)
                .frame(
                    width: DesignTokens.ControlRing.tickWidth,
                    height: DesignTokens.ControlRing.tickHeight
                )
                .offset(y: -size / 2)

            // 中心实心圆点 — stone 色，与图标一致
            Circle()
                .fill(DesignTokens.stone)
                .frame(width: size * 0.12, height: size * 0.12)

            // 中心百分比文字（仅大尺寸时显示）
            if size >= DesignTokens.ControlRing.dashboardSize * 0.7 {
                VStack(spacing: 2) {
                    Text("\(Int(displayProgress * 100))%")
                        .serifTitle(size * 0.18, weight: .bold)
                        .foregroundStyle(DesignTokens.ink)
                    Text("in control")
                        .sansBody(size * 0.07)
                        .foregroundStyle(DesignTokens.ash)
                }
                .offset(y: size * 0.15)
            }
        }
        .onAppear {
            if animated {
                withAnimation(.easeInOut(duration: 1.2)) {
                    displayProgress = progress
                }
            } else {
                displayProgress = progress
            }
        }
    }
}

// MARK: - 控制环加载态（Onboarding 用）

struct ControlRingLoading: View {
    let size: CGFloat

    @State private var rotation: Double = 0

    init(size: CGFloat = 80) {
        self.size = size
    }

    var body: some View {
        ZStack {
            // 背景环
            Circle()
                .stroke(DesignTokens.stoneDim.opacity(0.3), lineWidth: 3)
                .frame(width: size, height: size)

            // 旋转弧
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(DesignTokens.bronze, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(rotation))

            // 中心点
            Circle()
                .fill(DesignTokens.stone)
                .frame(width: size * 0.1, height: size * 0.1)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - 控制环小徽章（首页用）

struct ControlRingBadge: View {
    let progress: Double

    var body: some View {
        ControlRing(
            progress: progress,
            size: 60,
            animated: false
        )
    }
}
