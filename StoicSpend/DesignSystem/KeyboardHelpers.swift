import SwiftUI

// MARK: - 键盘交互统一优化
// 每个含输入框的页面顶层挂一次 .dismissKeyboardToolbar()：
// 键盘工具条右下角出现收起按钮，避免「键盘弹出挡内容且收不起来」。
// 可滚动页面（ScrollView/List/Form）另加 .scrollDismissesKeyboard(.interactively)，
// 手指下滑即可拖落键盘。

extension View {
    /// 收起键盘（resign first responder）
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// 键盘工具条：右下角收起按钮（每页只挂一次，多输入框不会重复出现）
    func dismissKeyboardToolbar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    hideKeyboard()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DesignTokens.ash)
                }
                .accessibilityLabel(Text("收起键盘"))
            }
        }
    }
}
