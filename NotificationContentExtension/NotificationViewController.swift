import UIKit
import UserNotifications
import UserNotificationsUI

final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private let symbolView = UIImageView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private lazy var textStack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
    private lazy var stack = UIStackView(arrangedSubviews: [symbolView, textStack])

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

        symbolView.contentMode = .scaleAspectFit
        symbolView.tintColor = .secondaryLabel
        textStack.axis = .vertical
        textStack.spacing = 4
        stack.alignment = .top
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            symbolView.widthAnchor.constraint(equalToConstant: 24),
            symbolView.heightAnchor.constraint(equalToConstant: 24),
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
        symbolView.image = UIImage(systemName: symbol(for: content))
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

    private func symbol(for content: UNNotificationContent) -> String {
        switch content.categoryIdentifier {
        case "person-post": return "person.crop.circle"
        case "focus-post": return "newspaper"
        default:
            switch content.userInfo["kind"] as? String {
            case "flash": return "bolt.fill"
            case "observability", "flash-health", "ai-usage": return "exclamationmark.triangle"
            case "translation-cost": return "chart.bar.xaxis"
            case "market-sentiment", "ashare", "sec13f": return "chart.line.uptrend.xyaxis"
            case "reading", "arxiv": return "book"
            default: return "doc.text"
            }
        }
    }
}
