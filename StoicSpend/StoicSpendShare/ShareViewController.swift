import UIKit
import SwiftUI
import Vision
import UniformTypeIdentifiers

/// FR-25 — 截图/分享扩展记账
/// 系统分享面板 → 本地 Vision OCR 提取金额（可选商户名）→ App Group 待处理队列 → 深链回主 App 确认
/// 全程设备端处理，截图不留存（只保留解析出的金额/商户名文本）
@objc(ShareViewController)
final class ShareViewController: UIViewController {

    let model = CaptureModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareCaptureView(model: model, controller: self))
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
        loadSharedItems()
    }

    // MARK: - 读取分享内容（图片 → OCR / 文本 → 直接解析）

    private func loadSharedItems() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }
        let providers = items.flatMap { $0.attachments ?? [] }

        var handled = false
        for provider in providers {
            if handled { break }
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                handled = true
                model.state = .recognizing
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
                    self?.recognizeAmount(in: data)
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                handled = true
                model.state = .recognizing
                provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { [weak self] item, _ in
                    let text = (item as? String) ?? (item as? NSURL)?.absoluteString ?? ""
                    self?.parse(lines: text.split(separator: "\n").map(String.init))
                }
            }
        }
        if !handled {
            model.state = .failed
        }
    }

    private func recognizeAmount(in data: Data?) {
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            parse(lines: [])
            return
        }

        let request = VNRecognizeTextRequest { [weak self] request, _ in
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            self?.parse(lines: lines)
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]

        do {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        } catch {
            parse(lines: [])
        }
    }

    private func parse(lines: [String]) {
        let capture = PendingCapture(
            id: UUID(),
            amount: ScreenshotParser.parseAmount(from: lines),
            merchant: ScreenshotParser.guessMerchant(from: lines),
            createdAt: .now
        )
        Task { @MainActor in
            PendingCaptureStore.append(capture)
            self.model.state = capture.amount == nil ? .failed : .recognized
        }
    }

    // MARK: - 深链回主 App（share extension 无 UIApplication.shared，走响应链 openURL）

    func openContainerApp() {
        guard let url = URL(string: "stoicspend://capture") else { return }
        var responder: UIResponder? = self
        let selector = sel_registerName("openURL:")
        while let r = responder {
            if r.responds(to: selector) {
                r.perform(selector, with: url)
                break
            }
            responder = r.next
        }
        extensionContext?.completeRequest(returningItems: nil)
    }

    func cancel() {
        PendingCaptureStore.clear()
        extensionContext?.completeRequest(returningItems: nil)
    }
}

// MARK: - 分享面板 UI（复用主工程 String Catalog 本地化）

@MainActor
final class CaptureModel: ObservableObject {
    enum State { case recognizing, recognized, failed }
    @Published var state: State = .recognizing
}

struct ShareCaptureView: View {
    @ObservedObject var model: CaptureModel
    let controller: ShareViewController

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            switch model.state {
            case .recognizing:
                Text("正在识别截图…")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.secondary)
            case .recognized:
                Text("已提取金额，打开 Stoic Spend 确认")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary)
            case .failed:
                Text("截图里没找到金额，打开 App 手动记一笔")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.secondary)
            }

            Button {
                controller.openContainerApp()
            } label: {
                Text("打开 Stoic Spend")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.561, green: 0.749, blue: 0.624))   // 主强调 #8FBF9F
                    .foregroundStyle(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(model.state == .recognizing)

            Button {
                controller.cancel()
            } label: {
                Text("取消")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.secondary)
            }

            Spacer()
        }
        .padding(24)
        .background(Color(UIColor.systemBackground))
    }
}
