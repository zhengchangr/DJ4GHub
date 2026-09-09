import SwiftUI

/// 样式兼容层：macOS 26+ 使用系统 Liquid Glass 玻璃样式；
/// macOS 15–25 自动回退到系统普通样式（磨砂材质圆角 / 普通按钮）。
extension View {
    /// 玻璃风格主按钮（macOS 26 的 `.glassProminent`；旧系统用 `.borderedProminent`）。
    @ViewBuilder
    func djGlassProminent() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// 玻璃风格次要按钮（macOS 26 的 `.glass`；旧系统用 `.bordered`）。
    @ViewBuilder
    func djGlass() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// 玻璃面板：macOS 26 用真实 Liquid Glass，旧系统用普通磨砂材质圆角。
    @ViewBuilder
    func djGlassPanel<S: InsettableShape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }
}
