import UIKit

@MainActor
final class ShareViewController: UIViewController {
    private let caption = UILabel()
    private let save = UIButton(type: .system)
    private var isSaving = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let heading = UILabel()
        heading.text = "存入 Knowledge Studio"
        heading.font = .preferredFont(forTextStyle: .title2)
        heading.adjustsFontForContentSizeCategory = true
        caption.text = "打开书房后，可在资料库确认导入。"
        caption.textColor = .secondaryLabel
        caption.numberOfLines = 0
        caption.font = .preferredFont(forTextStyle: .body)
        caption.adjustsFontForContentSizeCategory = true
        save.setTitle("存入待导入", for: .normal)
        save.addTarget(self, action: #selector(stageFile), for: .touchUpInside)
        let cancel = UIButton(type: .system)
        cancel.setTitle("取消", for: .normal)
        cancel.addTarget(self, action: #selector(close), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [heading, caption, save, cancel])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 26),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -26),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            save.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            cancel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        preferredContentSize = CGSize(width: 415, height: 245)
    }

    @objc private func stageFile() {
        guard !isSaving else { return }
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        let supported = [("com.adobe.pdf", "pdf"), ("org.idpf.epub-container", "epub"),
            ("public.mpeg-4", "mp4"), ("com.apple.m4v-video", "m4v"), ("com.apple.quicktime-movie", "mov"),
            ("public.movie", nil), ("public.file-url", nil), ("public.data", nil)]
        guard let provider = providers.first(where: { provider in
            supported.contains { provider.hasItemConformingToTypeIdentifier($0.0) }
        }), let format = supported.first(where: { provider.hasItemConformingToTypeIdentifier($0.0) }) else {
            caption.text = "没有可导入的资料。"
            return
        }
        do {
            let inbox = try SharedDocumentInbox.configured()
            let name = provider.suggestedName
            let ext = format.1
            isSaving = true
            save.isEnabled = false
            caption.text = "正在接收资料…"
            provider.loadFileRepresentation(forTypeIdentifier: format.0) { [weak self] url, error in
                let failure: String?
                do {
                    guard let url else { throw error ?? CocoaError(.fileReadUnknown) }
                    _ = try inbox.stage(url, suggestedName: name, fallbackExtension: ext)
                    failure = nil
                } catch { failure = error.localizedDescription }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    isSaving = false
                    if let failure { caption.text = failure; save.isEnabled = true }
                    else { extensionContext?.completeRequest(returningItems: nil) }
                }
            }
        } catch { caption.text = error.localizedDescription }
    }

    @objc private func close() {
        guard !isSaving else { return }
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }
}
