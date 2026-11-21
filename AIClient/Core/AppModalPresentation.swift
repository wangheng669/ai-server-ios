import SwiftUI
import UIKit

enum AppModalMotion {
    static let duration: TimeInterval = 0.20
    static var animation: Animation { .easeOut(duration: UIAccessibility.isReduceMotionEnabled ? 0.12 : duration) }
}

extension View {
    func appSheet<Item: Identifiable, Sheet: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Sheet
    ) -> some View {
        appModal(item: item, fullscreen: false, onDismiss: onDismiss, content: content)
    }

    func appSheet<Sheet: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Sheet
    ) -> some View {
        appModal(isPresented: isPresented, fullscreen: false, onDismiss: onDismiss, content: content)
    }

    func appFullScreenCover<Item: Identifiable, Sheet: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Sheet
    ) -> some View {
        appModal(item: item, fullscreen: true, onDismiss: onDismiss, content: content)
    }

    func appFullScreenCover<Sheet: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Sheet
    ) -> some View {
        appModal(isPresented: isPresented, fullscreen: true, onDismiss: onDismiss, content: content)
    }

    private func appModal<Item: Identifiable, Sheet: View>(
        item: Binding<Item?>,
        fullscreen: Bool,
        onDismiss: (() -> Void)?,
        content: @escaping (Item) -> Sheet
    ) -> some View {
        modifier(AppModalModifier(selection: item, dismissedSelection: nil, fullscreen: fullscreen, onDismiss: onDismiss) {
            $0.map { item in (AnyHashable(item.id), content(item)) }
        })
    }

    private func appModal<Sheet: View>(
        isPresented: Binding<Bool>,
        fullscreen: Bool,
        onDismiss: (() -> Void)?,
        content: @escaping () -> Sheet
    ) -> some View {
        modifier(AppModalModifier(selection: isPresented, dismissedSelection: false, fullscreen: fullscreen, onDismiss: onDismiss) {
            $0 ? (AnyHashable(true), content()) : nil
        })
    }
}

// Bindings must be DynamicProperties in the presenting SwiftUI graph. Reading
// them in an escaping UIKit builder loses nested-sheet invalidation tracking.
private struct AppModalModifier<Selection, Sheet: View>: ViewModifier {
    @Binding var selection: Selection
    let dismissedSelection: Selection
    let fullscreen: Bool
    let onDismiss: (() -> Void)?
    let presentation: (Selection) -> (id: AnyHashable, view: Sheet)?

    func body(content: Content) -> some View {
        let presented = presentation(selection)
        return content.background(AppModalPresenter(
            identity: presented?.id,
            fullscreen: fullscreen,
            content: presented?.view,
            onDismiss: {
                selection = dismissedSelection
                onDismiss?()
            }
        ))
    }
}

private struct AppModalPresenter<Sheet: View>: UIViewControllerRepresentable {
    let identity: AnyHashable?
    let fullscreen: Bool
    let content: Sheet?
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.onReady = { [weak coordinator = context.coordinator, weak anchor] in
            guard let anchor else { return }
            coordinator?.update(from: anchor)
        }
        return anchor
    }
    func updateUIViewController(_ anchor: Anchor, context: Context) {
        let coordinator = context.coordinator
        coordinator.fullscreen = fullscreen
        let openURL = context.environment.openURL
        let scenePhase = context.environment.scenePhase
        coordinator.content = content.map { content in
            ContentView(content: content, identity: identity, openURL: openURL, scenePhase: scenePhase) { [weak coordinator] options in
                coordinator?.updateOptions(options)
            }
        }
        coordinator.onDismiss = onDismiss
        coordinator.update(from: anchor)
    }
    static func dismantleUIViewController(_ anchor: Anchor, coordinator: Coordinator) {
        if let host = coordinator.host, !host.isBeingDismissed { host.dismiss(animated: false) }
    }

    final class Anchor: UIViewController {
        var onReady: (() -> Void)?
        var presentationOwner: UIViewController {
            var owner: UIViewController = self
            while let parent = owner.parent { owner = parent }
            while let presented = owner.presentedViewController { owner = presented }
            return owner
        }
        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onReady?()
        }
    }

    struct ContentView: View {
        let content: Sheet
        let identity: AnyHashable?
        let openURL: OpenURLAction
        let scenePhase: ScenePhase
        let onOptions: (AppModalOptions) -> Void
        var body: some View {
            content
                .id(identity)
                .scrollBounceBehavior(.basedOnSize, axes: [.vertical, .horizontal])
                .onPreferenceChange(AppModalOptionsKey.self, perform: onOptions)
                .environment(\.openURL, openURL)
                .environment(\.scenePhase, scenePhase)
                .environment(\.rootTabIsActive, true)
                .environment(\.rootBottomChromeHeight, 0)
        }
    }

    final class Host: UIHostingController<ContentView> {
        var onClosed: (() -> Void)?
        private var start: CFTimeInterval = 0
        override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); start = CACurrentMediaTime() }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); record("present") }
        override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); start = CACurrentMediaTime() }
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            record("dismiss")
            if isBeingDismissed || presentingViewController == nil { onClosed?() }
        }
        private func record(_ phase: String) {
            #if DEBUG
            guard ProcessInfo.processInfo.arguments.contains("--modal-timing") else { return }
            var line = "\(phase),\((CACurrentMediaTime() - start) * 1000)\n"
            if phase == "present", let request = AppModalTiming.requestedAt {
                line += "from-tap,\((CACurrentMediaTime() - request) * 1000)\n"
                AppModalTiming.requestedAt = nil
            }
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("modal-timing.csv")
            if let file = try? FileHandle(forWritingTo: url) {
                _ = try? file.seekToEnd()
                try? file.write(contentsOf: Data(line.utf8))
                try? file.close()
            } else { try? Data(line.utf8).write(to: url) }
            #endif
        }
    }

    @MainActor final class Coordinator: NSObject, UIViewControllerTransitioningDelegate, UISheetPresentationControllerDelegate {
        var content: ContentView?
        var fullscreen = false
        private var options = AppModalOptions()
        var onDismiss: (() -> Void)?
        var host: Host?
        private var closing = false

        func update(from anchor: Anchor) {
            guard anchor.viewIfLoaded?.window != nil else { return }
            guard let content else {
                if let host, !closing {
                    closing = true
                    if host.presentingViewController == nil { host.onClosed?() }
                    else { host.dismiss(animated: true) }
                }
                return
            }
            if let host {
                if !closing { host.rootView = content }
                return
            }
            guard anchor.presentationOwner.presentedViewController == nil else { return }
            let host = Host(rootView: content)
            host.modalPresentationStyle = .custom
            host.transitioningDelegate = self
            host.view.backgroundColor = .systemBackground
            host.view.accessibilityViewIsModal = true
            host.onClosed = { [weak self] in
                guard let self else { return }
                self.host = nil
                self.closing = false
                self.onDismiss?()
            }
            self.host = host
            host.modalPresentationCapturesStatusBarAppearance = true
            host.view.frame = anchor.view.window?.bounds ?? anchor.view.bounds
            DispatchQueue.main.async { [weak self, weak anchor, weak host] in
                guard let self, let anchor, let host, self.content != nil, !self.closing,
                      anchor.viewIfLoaded?.window != nil else { return }
                anchor.presentationOwner.present(host, animated: true)
            }
        }

        func updateOptions(_ updated: AppModalOptions) {
            let previous = options
            options = updated
            guard updated != previous, let host else { return }
            if let sheet = host.presentationController as? UISheetPresentationController {
                applyOptions(to: sheet)
            }
            host.view.backgroundColor = updated.background.map(UIColor.init) ?? .systemBackground
        }

        private func applyOptions(to sheet: UISheetPresentationController) {
            let detents = (options.detents ?? [.large]).sorted { $0.rawValue < $1.rawValue }
            let identifiers = detents.map(\.identifier)
            if sheet.detents.map(\.identifier) != identifiers {
                sheet.detents = detents.map(\.native)
                if options.selection == nil { sheet.selectedDetentIdentifier = detents.first?.identifier }
            }
            if let selected = options.selection, sheet.selectedDetentIdentifier != selected.identifier {
                sheet.selectedDetentIdentifier = selected.identifier
            }
            sheet.prefersGrabberVisible = options.showsGrabber
            if let radius = options.cornerRadius { sheet.preferredCornerRadius = radius }
            sheet.prefersScrollingExpandsWhenScrolledToEdge = !options.scrollsWithoutExpanding
        }

        func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
            if fullscreen { return AppFullScreenPresentationController(presentedViewController: presented, presenting: presenting) }
            let sheet = UISheetPresentationController(presentedViewController: presented, presenting: presenting)
            sheet.delegate = self
            applyOptions(to: sheet)
            return sheet
        }

        func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheetPresentationController: UISheetPresentationController) {
            guard let id = sheetPresentationController.selectedDetentIdentifier,
                  let detent = options.detents?.first(where: { $0.identifier == id }) else { return }
            options.onSelectionChange?(detent)
        }
        func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
            AppModalAnimator(presenting: true)
        }
        func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
            AppModalAnimator(presenting: false)
        }
    }
}

private final class AppModalAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let presenting: Bool
    private var animator: UIViewPropertyAnimator?
    init(presenting: Bool) { self.presenting = presenting }
    func transitionDuration(using context: UIViewControllerContextTransitioning?) -> TimeInterval {
        UIAccessibility.isReduceMotionEnabled ? 0.12 : AppModalMotion.duration
    }
    func animateTransition(using context: UIViewControllerContextTransitioning) {
        interruptibleAnimator(using: context).startAnimation()
    }

    func interruptibleAnimator(using context: UIViewControllerContextTransitioning) -> UIViewImplicitlyAnimating {
        if let animator { return animator }
        let key: UITransitionContextViewKey = presenting ? .to : .from
        guard let view = context.view(forKey: key) else {
            let animator = UIViewPropertyAnimator(duration: 0, curve: .easeOut)
            animator.addCompletion { _ in context.completeTransition(false) }
            self.animator = animator
            return animator
        }
        if presenting {
            if let controller = context.viewController(forKey: .to) { view.frame = context.finalFrame(for: controller) }
            context.containerView.addSubview(view)
        }
        let reducedMotion = UIAccessibility.isReduceMotionEnabled
        let offset = CGAffineTransform(translationX: 0, y: view.bounds.height)
        if presenting {
            if reducedMotion { view.alpha = 0 } else { view.transform = offset }
        }
        let animator = UIViewPropertyAnimator(duration: transitionDuration(using: context), curve: .easeOut) {
            if reducedMotion { view.alpha = self.presenting ? 1 : 0 }
            else { view.transform = self.presenting ? .identity : offset }
        }
        animator.addCompletion { _ in
            let completed = !context.transitionWasCancelled
            if !self.presenting && completed { view.removeFromSuperview() }
            view.transform = .identity
            view.alpha = 1
            context.completeTransition(completed)
        }
        self.animator = animator
        return animator
    }

    func animationEnded(_ transitionCompleted: Bool) {
        animator = nil
    }
}

private final class AppFullScreenPresentationController: UIPresentationController {
    // Keep the presenter's SwiftUI graph alive so binding-driven close actions
    // are delivered even while the full-screen content covers the entire window.
    override var shouldRemovePresentersView: Bool { false }

    override var frameOfPresentedViewInContainerView: CGRect {
        containerView?.bounds ?? .zero
    }

    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        presentedView?.frame = frameOfPresentedViewInContainerView
    }
}

/// Detents used by the shared presenter, including a two-way selection binding.
enum AppModalDetent: Int, Hashable {
    case medium, large

    fileprivate var identifier: UISheetPresentationController.Detent.Identifier {
        switch self {
        case .medium: .medium
        case .large: .large
        }
    }
    @MainActor fileprivate var native: UISheetPresentationController.Detent {
        switch self {
        case .medium: .medium()
        case .large: .large()
        }
    }
}

private struct AppModalOptions: Equatable {
    var detents: Set<AppModalDetent>?
    var selection: AppModalDetent?
    var onSelectionChange: ((AppModalDetent) -> Void)?
    var cornerRadius: CGFloat?
    var scrollsWithoutExpanding = false
    var showsGrabber = false
    var background: Color?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.detents == rhs.detents && lhs.selection == rhs.selection
            && lhs.cornerRadius == rhs.cornerRadius
            && lhs.scrollsWithoutExpanding == rhs.scrollsWithoutExpanding
            && lhs.showsGrabber == rhs.showsGrabber
            && lhs.background == rhs.background
    }
    mutating func merge(_ other: Self) {
        if let value = other.detents { detents = value; selection = other.selection; onSelectionChange = other.onSelectionChange }
        if let value = other.cornerRadius { cornerRadius = value }
        scrollsWithoutExpanding = scrollsWithoutExpanding || other.scrollsWithoutExpanding
        showsGrabber = showsGrabber || other.showsGrabber
        if let value = other.background { background = value }
    }
}

private struct AppModalOptionsKey: PreferenceKey {
    static let defaultValue = AppModalOptions()
    static func reduce(value: inout AppModalOptions, nextValue: () -> AppModalOptions) { value.merge(nextValue()) }
}

extension View {
    func appPresentationDetents(_ detents: Set<AppModalDetent>, selection: Binding<AppModalDetent>? = nil) -> some View {
        transformPreference(AppModalOptionsKey.self) {
            $0.merge(AppModalOptions(detents: detents, selection: selection?.wrappedValue, onSelectionChange: selection.map { binding in { binding.wrappedValue = $0 } }))
        }
    }
    func appPresentationCornerRadius(_ radius: CGFloat) -> some View {
        transformPreference(AppModalOptionsKey.self) { $0.cornerRadius = radius }
    }
    func appPresentationBackground(_ color: Color) -> some View {
        transformPreference(AppModalOptionsKey.self) { $0.background = color }
    }
    func appPresentationScrollsWithoutExpanding() -> some View {
        transformPreference(AppModalOptionsKey.self) { $0.scrollsWithoutExpanding = true }
    }
    func appPresentationDragIndicator() -> some View {
        transformPreference(AppModalOptionsKey.self) { $0.showsGrabber = true }
    }
}

#if DEBUG
@MainActor
enum AppModalTiming {
    static var requestedAt: CFTimeInterval?
    static func beginRequest() {
        guard ProcessInfo.processInfo.arguments.contains("--modal-timing") else { return }
        requestedAt = CACurrentMediaTime()
    }
}
#endif

#if DEBUG
/// Exercises the same public modal API without depending on changing feed data.
struct AppModalContractPreview: View {
    @State private var showsParent = false
    @State private var showsChild = false
    @State private var showsFullscreen = false
    @State private var gallery: ImageGallerySelection?
    @State private var showsNotice = false
    @State private var interactionCount = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Button("打开半屏") { showsParent = true }
                Button("打开全屏") { showsFullscreen = true }
                Button("打开图片预览") { gallery = ImageGallerySelection(urls: [], initialIndex: 0) }
                Button("显示错误提示") { showsNotice = true }
                Button("继续操作") { interactionCount += 1 }
                Text("已操作 \(interactionCount) 次")
                if showsNotice {
                    InlineActionNotice(message: "操作未完成，请重试", retry: { interactionCount += 1 }) {
                        showsNotice = false
                    }.padding(.horizontal, 20)
                }
            }
            .navigationTitle("弹窗验收")
        }
        .imageGallery(item: $gallery)
        .appSheet(isPresented: $showsParent) {
            parentContent
        }
        .appFullScreenCover(isPresented: $showsFullscreen) {
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                Button("关闭全屏") { showsFullscreen = false }
            }
        }
    }

    private var parentContent: some View {
        VStack(spacing: 0) {
            Button("打开子弹窗") { showsChild = true }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottomTrailing) {
            DetailSheetControls(closeLabel: "关闭父弹窗", onClose: { showsParent = false }).padding(12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("modal-contract-parent")
        .appPresentationDetents([.medium, .large])
        .appSheet(isPresented: $showsChild) { AppModalContractChild() }
    }
}

private struct AppModalContractChild: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            Text("子弹窗内容")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottomTrailing) {
            DetailSheetControls(closeLabel: "关闭子弹窗", onClose: dismiss.callAsFunction).padding(12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("modal-contract-child")
        .appPresentationDetents([.large])
    }
}
#endif
