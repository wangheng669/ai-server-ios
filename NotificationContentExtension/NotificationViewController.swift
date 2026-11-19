import ImageIO
import UIKit
import UserNotifications
import UserNotificationsUI

final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private lazy var textStack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
    private lazy var stack = UIStackView(arrangedSubviews: [iconView, textStack])
    private let iconSize: CGFloat = 24

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        bodyLabel.font = .preferredFont(forTextStyle: .body)
        bodyLabel.adjustsFontForContentSizeCategory = true
        bodyLabel.numberOfLines = 0

        iconView.contentMode = .scaleAspectFit
        iconView.layer.cornerCurve = .continuous
        iconView.layer.cornerRadius = 5
        iconView.clipsToBounds = true
        iconView.image = loadAppIcon()
        textStack.axis = .vertical
        textStack.spacing = 4
        stack.alignment = .top
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.bottomAnchor)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePreferredHeight()
    }

    func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        titleLabel.text = content.title
        titleLabel.isHidden = content.title.isEmpty
        bodyLabel.text = content.body
        bodyLabel.isHidden = content.body.isEmpty
        updatePreferredHeight()
    }

    private func updatePreferredHeight() {
        let margins = view.layoutMargins
        let width = view.bounds.width - margins.left - margins.right
        guard width > 0 else { return }
        let size = stack.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let preferredSize = CGSize(width: view.bounds.width, height: ceil(size.height + margins.top + margins.bottom))
        if preferredContentSize != preferredSize {
            preferredContentSize = preferredSize
        }
    }

    private func loadAppIcon() -> UIImage? {
        let scale = max(1, traitCollection.displayScale)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(ceil(iconSize * scale))
        ]
        guard let url = Bundle(for: Self.self).url(forResource: "AppIcon", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail, scale: scale, orientation: .up)
    }
}
