import SwiftUI

enum CityRegionLevel: String, Hashable {
    case country = "全国", province = "省份", city = "城市", district = "区县"

    var childTitle: String? {
        switch self {
        case .country: "选择省份"
        case .province: "下辖城市"
        case .city: "下辖区县"
        case .district: nil
        }
    }
}

struct CityRegion: Identifiable, Hashable {
    var id: String { String(adcode) }
    let adcode: Int
    let parentAdcode: Int?
    let name: String
    let level: CityRegionLevel
    let children: [CityRegion]
}

struct CityRegionJourney: Equatable {
    private(set) var path: [CityRegion]

    init(path: [CityRegion] = []) { self.path = path }

    var current: CityRegion { path.last ?? CityRegions.root }
    var parent: CityRegion? {
        guard !path.isEmpty else { return nil }
        return path.dropLast().last ?? CityRegions.root
    }
    var canGoBack: Bool { !path.isEmpty }
    var mapScope: CityRegion {
        let current = current
        if current.children.isEmpty {
            return parent ?? current
        }
        return current
    }
    var mapRegions: [CityRegion] { mapScope.children }
    var selectedMapRegionID: String? { current.id == mapScope.id ? nil : current.id }

    @discardableResult
    mutating func enter(_ region: CityRegion) -> Bool {
        guard let child = current.children.first(where: { $0.id == region.id }) else { return false }
        path.append(child)
        return true
    }

    @discardableResult
    mutating func selectPeer(_ region: CityRegion) -> Bool {
        guard region.id != current.id,
              let peer = parent?.children.first(where: { $0.id == region.id })
        else { return false }
        path[path.count - 1] = peer
        return true
    }

    @discardableResult
    mutating func goBack() -> Bool {
        path.popLast() != nil
    }
}

enum CityRegions {
    static let root = CityMapRepository.shared.rootRegion()

    static func path(to adcode: Int) -> [CityRegion] {
        findPath(in: root, to: adcode) ?? []
    }

    private static func findPath(in region: CityRegion, to adcode: Int) -> [CityRegion]? {
        for child in region.children {
            if child.adcode == adcode { return [child] }
            if let suffix = findPath(in: child, to: adcode) { return [child] + suffix }
        }
        return nil
    }
}

private enum CityDashboardTab: String, CaseIterable, Identifiable {
    case overview = "概览", cities = "城市", data = "数据", industry = "产业", transport = "交通", culture = "文旅"
    var id: String { rawValue }
}

private enum CityMapNavigationDirection {
    case forward
    case backward
    case lateral
}

struct CityNewsView: View {
    @Environment(\.rootBottomChromeHeight) private var bottomChromeHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var journey: CityRegionJourney
    @State private var selectedID: String?
    @State private var selectedTab: CityDashboardTab = .overview
    @State private var showsList = false
    @State private var showsMap = false
    @State private var mapNavigationDirection: CityMapNavigationDirection = .forward

    init() {
        let journey: CityRegionJourney
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--city-district-preview") {
            journey = CityRegionJourney(path: CityRegions.path(to: 440305))
        } else if arguments.contains("--city-city-preview") {
            journey = CityRegionJourney(path: CityRegions.path(to: 440300))
        } else {
            journey = CityRegionJourney(path: CityRegions.path(to: 440000))
        }
        #else
        journey = CityRegionJourney(path: CityRegions.path(to: 440000))
        #endif
        _journey = State(initialValue: journey)
        _selectedID = State(initialValue: Self.defaultSelection(for: journey))
    }

    var body: some View {
        let region = journey.current
        let scope = journey.mapScope
        let selected = selectedRegion(in: scope.children)

        VStack(spacing: 0) {
            topBar

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header(region)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    tabBar
                        .padding(.top, 8)

                    Group {
                        switch selectedTab {
                        case .overview, .cities:
                            mapSection(scope: scope, selected: selected)
                        case .data, .industry, .transport, .culture:
                            ContentUnavailableView("\(selectedTab.rawValue)内容暂未接入", systemImage: "tray")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
                .padding(.bottom, max(bottomChromeHeight, 78) + 20)
            }
            .scrollIndicators(.hidden)
        }
        .background(CityDesign.canvas.ignoresSafeArea())
        .tint(CityDesign.accent)
        .sensoryFeedback(.selection, trigger: selectedID)
        .sensoryFeedback(.impact(weight: .light), trigger: journey.current.id)
        .accessibilityIdentifier("city-region-screen")
        .appSheet(isPresented: $showsList) {
            CityRegionList(
                scope: scope,
                selection: selectedID,
                onSelect: { region in
                    select(region)
                    showsList = false
                }
            )
        }
        .appFullScreenCover(isPresented: $showsMap) {
            CityFullScreenMap(scope: scope, selection: $selectedID)
        }
    }

    private var topBar: some View {
        Text("城市观察")
            .font(.headline.weight(.bold))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(CityDesign.canvas)
            .overlay(alignment: .bottom) {
                Rectangle().fill(CityDesign.divider).frame(height: 0.5)
            }
    }

    private static func defaultSelection(for journey: CityRegionJourney) -> String? {
        if journey.current.adcode == 440000 {
            return journey.current.children.first(where: { $0.adcode == 440300 })?.id
        }
        return journey.selectedMapRegionID ?? journey.current.children.first?.id
    }

    private func selectedRegion(in regions: [CityRegion]) -> CityRegion? {
        if let selectedID, let region = regions.first(where: { $0.id == selectedID }) { return region }
        if let current = regions.first(where: { $0.id == journey.current.id }) { return current }
        return regions.first
    }

    private var mapAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .spring(duration: 0.48, bounce: 0.12)
    }

    private var mapTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        switch mapNavigationDirection {
        case .forward:
            return .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.76)),
                removal: .opacity.combined(with: .scale(scale: 1.16))
            )
        case .backward:
            return .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 1.12)),
                removal: .opacity.combined(with: .scale(scale: 0.80))
            )
        case .lateral:
            return .opacity
        }
    }

    private func select(_ region: CityRegion) {
        if selectedID == region.id,
           journey.current.children.contains(where: { $0.id == region.id }) {
            navigate(to: region)
            return
        }
        withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.22)) {
            selectedID = region.id
        }
    }

    private func navigate(to region: CityRegion) {
        let isChild = journey.current.children.contains(where: { $0.id == region.id })
        mapNavigationDirection = isChild ? .forward : .lateral
        withAnimation(mapAnimation) {
            let didNavigate = isChild ? journey.enter(region) : journey.selectPeer(region)
            guard didNavigate else { return }
            selectedID = Self.defaultSelection(for: journey)
        }
    }

    private func navigateBack() {
        let leaving = journey.current
        mapNavigationDirection = .backward
        withAnimation(mapAnimation) {
            guard journey.goBack() else { return }
            selectedID = journey.mapRegions.first(where: { $0.id == leaving.id })?.id
                ?? Self.defaultSelection(for: journey)
        }
    }

    @ViewBuilder
    private func header(_ region: CityRegion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if journey.canGoBack {
                Button { navigateBack() } label: {
                    Label(journey.parent?.name ?? CityRegions.root.name, systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(CityPressStyle())
                .padding(.bottom, 2)
            }

            Text(eyebrow(region))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CityDesign.accent)

            Text(region.name)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .padding(.top, 5)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("city-current-title")

            factCard(region)
                .padding(.top, 9)
        }
    }

    private func eyebrow(_ region: CityRegion) -> String {
        if let parent = journey.parent {
            return "\(parent.name) · \(region.level.rawValue)"
        }
        return "中国"
    }

    private func headerFacts(_ region: CityRegion) -> [(String, String, String)] {
        var facts = [("级别", region.level.rawValue, "map.fill")]
        if let parent = journey.parent {
            facts.append(("所属", parent.name, "mappin.and.ellipse"))
        }
        if !region.children.isEmpty {
            facts.append(("地图收录", "\(region.children.count)个下级地区", "square.3.layers.3d"))
        }
        return facts
    }

    private func factCard(_ region: CityRegion) -> some View {
        let facts = headerFacts(region)
        return HStack(spacing: 0) {
            ForEach(Array(facts.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 9) {
                    Image(systemName: item.2)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CityDesign.accent)
                        .frame(width: 27, height: 27)
                        .background(CityDesign.accentSoft, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.0).font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(item.1).font(.system(size: 14, weight: .bold)).lineLimit(1).minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
                if index < facts.count - 1 {
                    Rectangle().fill(CityDesign.divider).frame(width: 1, height: 25).padding(.horizontal, 5)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CityDesign.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 15).stroke(Color.primary.opacity(0.04), lineWidth: 0.7) }
        .shadow(color: .black.opacity(0.035), radius: 8, y: 4)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(CityDashboardTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 5) {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: selectedTab == tab ? .bold : .medium))
                            .foregroundStyle(selectedTab == tab ? CityDesign.accent : .secondary)
                        Capsule().fill(selectedTab == tab ? CityDesign.accent : .clear).frame(width: 34, height: 2.5)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(CityPressStyle())
            }
        }
        .padding(.horizontal, 18)
        .overlay(alignment: .bottom) { Rectangle().fill(CityDesign.divider).frame(height: 0.5) }
    }

    private func mapSection(
        scope: CityRegion,
        selected: CityRegion?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(scope.level.childTitle ?? "区域地图").font(.system(size: 17, weight: .bold))
                Spacer()
                if !scope.children.isEmpty {
                    Button { showsList = true } label: {
                        HStack(spacing: 5) {
                            Text("查看全部 \(scope.children.count)个")
                            Image(systemName: "chevron.right").font(.caption.weight(.bold))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(CityPressStyle())
                    .accessibilityValue(showsList ? "已展开" : "已收起")
                }
            }

            VStack(spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    CityDesign.mapGradient.allowsHitTesting(false)
                    Circle().fill(.white.opacity(0.45)).frame(width: 240, height: 240).blur(radius: 10).offset(x: 100, y: -120)
                        .allowsHitTesting(false)
                    ZStack {
                        CityAdministrativeMap(
                            scope: scope,
                            selectedRegionID: selected?.id,
                            onSelect: select
                        )
                        .id(scope.id)
                        .transition(mapTransition)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 8)
                    .clipped()
                    Button { showsMap = true } label: {
                        Label("全屏地图", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(CityPressStyle())
                    .padding(9)
                }
                .frame(height: 190)
                .contentShape(Rectangle())

                if let selected {
                    selectedCard(selected)
                        .id(selected.id)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .background(CityDesign.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.04), lineWidth: 0.7) }
            .shadow(color: CityDesign.accent.opacity(0.075), radius: 11, y: 5)
        }
    }

    private func selectedCard(_ region: CityRegion) -> some View {
        HStack(spacing: 9) {
            Group {
                if region.adcode == 440300 {
                    Image("ShenzhenSkyline")
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(colors: [CityDesign.accent.opacity(0.85), .cyan.opacity(0.50)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: region.level == .district ? "building.columns.fill" : "building.2.fill")
                            .font(.system(size: 27, weight: .medium))
                            .foregroundStyle(.white)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .frame(width: 65, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(region.name).font(.system(size: 16, weight: .bold)).lineLimit(1)
                    Text(region.id == journey.current.id ? "当前地区" : "当前选择")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(CityDesign.accent)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(CityDesign.accentSoft, in: Capsule())
                }
                Text(region.level.rawValue).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if region.id != journey.current.id {
                Button { navigate(to: region) } label: {
                    HStack(spacing: 4) {
                        Text(navigationLabel(for: region))
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .fixedSize()
                    .frame(minWidth: 50, minHeight: 36)
                }
                .buttonStyle(CityPressStyle())
                .accessibilityLabel("\(navigationLabel(for: region))\(region.name)")
            }
        }
        .padding(8)
        .background(CityDesign.surface)
        .overlay(alignment: .top) { Rectangle().fill(CityDesign.divider).frame(height: 0.5) }
    }

    private func navigationLabel(for region: CityRegion) -> String {
        switch region.level {
        case .country: return "进入全国"
        case .province: return "进入省份"
        case .city: return "进入城市"
        case .district: return "查看区县"
        }
    }


}

private enum CityDesign {
    static let accent = Color(red: 0.04, green: 0.43, blue: 0.97)
    static let accentSoft = accent.opacity(0.10)
    static let canvas = Color(red: 0.982, green: 0.987, blue: 0.997)
    static let surface = Color(uiColor: .systemBackground)
    static let divider = Color(uiColor: .separator).opacity(0.18)
    static let mapFill = Color(red: 0.36, green: 0.63, blue: 0.94)
    static let mapGradient = LinearGradient(
        colors: [Color(red: 0.91, green: 0.96, blue: 1), Color(red: 0.85, green: 0.94, blue: 0.99), Color(red: 0.93, green: 0.98, blue: 1)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct CityPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct CityRegionList: View {
    @Environment(\.dismiss) private var dismiss
    let scope: CityRegion
    let selection: String?
    let onSelect: (CityRegion) -> Void

    var body: some View {
        let title = scope.level.childTitle ?? "区域列表"
        VStack(spacing: 0) {
            List(scope.children) { region in
                Button { onSelect(region) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(CityDesign.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(region.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                            Text(region.level.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if region.id == selection { Image(systemName: "checkmark.circle.fill").foregroundStyle(CityDesign.accent) }
                    }
                }
                .buttonStyle(.plain)
            }
            .accessibilityIdentifier("city-region-list-\(title)")
            .contentMargins(.bottom, 76, for: .scrollContent)
        }
        .overlay(alignment: .bottomTrailing) {
            DetailSheetControls(closeLabel: "完成", onClose: dismiss.callAsFunction).padding(12)
        }
    }
}

private struct CityFullScreenMap: View {
    @Environment(\.dismiss) private var dismiss
    let scope: CityRegion
    @Binding var selection: String?

    var body: some View {
        ZStack {
            CityDesign.mapGradient.ignoresSafeArea()
            CityAdministrativeMap(scope: scope, selectedRegionID: selection) { selection = $0.id }
                .padding(18)
        }
        .overlay(alignment: .topTrailing) {
            DetailSheetControls(closeLabel: "完成", onClose: dismiss.callAsFunction).padding(12)
        }
    }
}

private struct CityAdministrativeMap: View {
    @ScaledMetric(relativeTo: .caption2) private var labelSize: CGFloat = 9
    let scope: CityRegion
    let selectedRegionID: String?
    let onSelect: (CityRegion) -> Void

    var body: some View {
        let features = CityMapRepository.shared.features(for: scope)
        let regionByAdcode = Dictionary(uniqueKeysWithValues: scope.children.map { ($0.adcode, $0) })
        let selectedAdcode = scope.children.first { $0.id == selectedRegionID }?.adcode
        GeometryReader { geometry in
            if features.isEmpty {
                ContentUnavailableView("地图数据不可用", systemImage: "map")
            } else {
                let projection = CityMapProjection(features: features, size: geometry.size)
                ZStack {
                    Canvas { context, _ in
                        var projected = context
                        projected.concatenate(projection.transform)
                        for feature in features {
                            let path = feature.geometry.outline
                            let color = feature.id == selectedAdcode
                                ? CityDesign.accent.opacity(0.72)
                                : CityDesign.mapFill.opacity(regionByAdcode[feature.id] == nil ? 0.14 : 0.34)
                            projected.fill(path, with: .color(color), style: FillStyle(eoFill: true))
                            projected.stroke(path, with: .color(.white.opacity(0.92)), lineWidth: 0.85 / projection.scale)
                        }
                    }
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded {
                            select(at: $0.location, projection: projection, features: features, regions: regionByAdcode)
                        })
                        .accessibilityHidden(true)
                    ForEach(features) { feature in
                        if let coordinate = feature.labelCoordinate, let region = regionByAdcode[feature.id] {
                            mapLabel(feature.properties.name, selected: region.id == selectedRegionID)
                                .frame(minWidth: region.id == selectedRegionID ? 68 : 36, minHeight: 30)
                                .position(projection.point(for: coordinate))
                                .accessibilityLabel(region.id == selectedRegionID ? "\(region.name)，当前选择" : region.name)
                                .accessibilityHint(region.id == selectedRegionID ? "再次轻点进入\(region.name)" : "选择\(region.name)")
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { onSelect(region) }
                        }
                    }
                }
            }
        }
    }

    private func select(
        at point: CGPoint, projection: CityMapProjection,
        features: [CityMapFeature], regions: [Int: CityRegion]
    ) {
        let selectable = features.filter { regions[$0.id] != nil }
        if let feature = selectable.reversed().first(where: { projection.contains(point, in: $0) }),
           let region = regions[feature.id] {
            onSelect(region)
            return
        }
        let nearest = selectable.compactMap { feature -> (CityMapFeature, CGFloat)? in
            guard let coordinate = feature.labelCoordinate else { return nil }
            let location = projection.point(for: coordinate)
            return (feature, hypot(location.x - point.x, location.y - point.y))
        }.filter { $0.1 <= 30 }.min { $0.1 < $1.1 }
        if let feature = nearest?.0, let region = regions[feature.id] { onSelect(region) }
    }

    @ViewBuilder
    private func mapLabel(_ text: String, selected: Bool) -> some View {
        let value = text.replacingOccurrences(of: "省", with: "").replacingOccurrences(of: "市", with: "")
        if selected {
            Label(value, systemImage: "mappin.circle.fill")
                .font(.system(size: min(max(labelSize + 1, 10), 14), weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(CityDesign.accent, in: Capsule())
                .shadow(color: CityDesign.accent.opacity(0.25), radius: 6, y: 3)
                .allowsHitTesting(false)
        } else {
            HStack(spacing: 3) {
                Circle().fill(CityDesign.accent.opacity(0.76)).frame(width: 4, height: 4)
                Text(value).font(.system(size: min(max(labelSize, 8), 12), weight: .semibold)).foregroundStyle(Color.primary.opacity(0.78))
            }
            .padding(.horizontal, 3).padding(.vertical, 2)
            .background(.white.opacity(0.22), in: Capsule())
            .allowsHitTesting(false)
        }
    }
}
