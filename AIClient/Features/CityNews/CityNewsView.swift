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

private enum CityMapNavigationDirection {
    case forward
    case backward
    case lateral
}

struct CityNewsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var journey: CityRegionJourney
    @State private var selectedID: String?
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

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                KnowledgePageHeading(title: "城市观察", icon: "map", tint: CityDesign.accent)
                header(region)
                mapSection(scope: scope, selected: selected)
            }
            .frame(maxWidth: 650)
            .padding(.horizontal, 20)
            .padding(.top, 19)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(KnowledgePagePalette.canvas.ignoresSafeArea())
        .floatingSheetClose("关闭城市观察", action: dismiss.callAsFunction)
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

    private func header(_ region: CityRegion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let parent = journey.parent {
                Button {
                    navigateBack()
                } label: {
                    Label(parent.name, systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(CityPressStyle())
                .accessibilityLabel("返回\(parent.name)")
            }

            Text(region.name)
                .font(.title.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("city-current-title")

            Text(region.children.isEmpty
                 ? region.level.rawValue
                 : "\(region.level.rawValue) · \(region.children.count) 个下级地区")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 15)
        .padding(.top, journey.parent == nil ? 15 : 2)
        .padding(.bottom, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CityDesign.accent.opacity(0.085), in: .rect(cornerRadius: 16))
    }

    private func mapSection(scope: CityRegion, selected: CityRegion?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                KnowledgeSectionHeading(scope.level.childTitle ?? "区域地图")
                if !scope.children.isEmpty {
                    Button { showsList = true } label: {
                        Label("全部 \(scope.children.count) 个", systemImage: "list.bullet")
                            .font(.footnote.weight(.semibold))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(CityPressStyle())
                    .accessibilityLabel("查看全部 \(scope.children.count) 个地区")
                }
            }

            VStack(spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    CityDesign.mapBackground
                    CityAdministrativeMap(scope: scope, selectedRegionID: selected?.id, onSelect: select)
                        .id(scope.id)
                        .transition(mapTransition)
                        .padding(10)
                    Button { showsMap = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CityDesign.accent)
                            .frame(width: 44, height: 44)
                            .knowledgeCard(cornerRadius: 12)
                    }
                    .buttonStyle(CityPressStyle())
                    .accessibilityLabel("全屏地图")
                    .padding(10)
                }
                .frame(height: 260)
                .clipped()

                if let selected {
                    selectedCard(selected)
                        .id(selected.id)
                        .transition(.opacity)
                }
            }
            .knowledgeCard(cornerRadius: 18)
        }
    }

    private func selectedCard(_ region: CityRegion) -> some View {
        HStack(spacing: 10) {
            Group {
                if region.adcode == 440300 {
                    Image("ShenzhenSkyline")
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.title3)
                        .foregroundStyle(CityDesign.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(CityDesign.accent.opacity(0.10))
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(.rect(cornerRadius: 9))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(region.name)
                    .font(.headline)
                Text(region.id == journey.current.id ? "当前地区" : region.level.rawValue)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if region.id != journey.current.id {
                Button { navigate(to: region) } label: {
                    Label(navigationLabel(for: region), systemImage: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CityDesign.accent)
                        .padding(.horizontal, 9)
                        .frame(minHeight: 44)
                        .background(CityDesign.accent.opacity(0.10), in: .rect(cornerRadius: 10))
                }
                .buttonStyle(CityPressStyle())
                .accessibilityLabel("\(navigationLabel(for: region))\(region.name)")
            }
        }
        .padding(12)
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
    static let accent = KnowledgePagePalette.atlas
    static let mapBackground = KnowledgePagePalette.adaptive(light: 0xE5EEE8, dark: 0x203730)
    static let mapFill = KnowledgePagePalette.adaptive(light: 0x4B8B78, dark: 0x60AE9B)
    static let outline = KnowledgePagePalette.adaptive(light: 0xF4F7ED, dark: 0x22372F)
    static let marker = Color(red: 0.10, green: 0.34, blue: 0.32)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                KnowledgePageHeading(title: title, icon: "list.bullet", tint: CityDesign.accent)
                LazyVStack(spacing: 0) {
                    ForEach(scope.children) { region in
                        Button { onSelect(region) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundStyle(CityDesign.accent)
                                    .accessibilityHidden(true)
                                Text(region.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if region.id == selection {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(CityDesign.accent)
                                        .accessibilityHidden(true)
                                }
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(region.id == selection ? .isSelected : [])
                        if region.id != scope.children.last?.id {
                            Divider().padding(.leading, 40)
                        }
                    }
                }
                .knowledgeCard()
                .accessibilityIdentifier("city-region-list-\(title)")
            }
            .frame(maxWidth: 650)
            .padding(.horizontal, 20)
            .padding(.top, 19)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity)
        }
        .background(KnowledgePagePalette.canvas.ignoresSafeArea())
        .floatingSheetClose("关闭区域列表", action: dismiss.callAsFunction)
    }
}

private struct CityFullScreenMap: View {
    @Environment(\.dismiss) private var dismiss
    let scope: CityRegion
    @Binding var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            KnowledgePageHeading(title: scope.name, icon: "map", tint: CityDesign.accent)
            if let selected = scope.children.first(where: { $0.id == selection }) {
                Label(selected.name, systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CityDesign.accent)
            }
            CityAdministrativeMap(scope: scope, selectedRegionID: selection) { selection = $0.id }
                .padding(8)
                .background(CityDesign.mapBackground, in: .rect(cornerRadius: 18))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 76)
        .background(KnowledgePagePalette.canvas.ignoresSafeArea())
        .floatingSheetClose("关闭全屏地图", action: dismiss.callAsFunction)
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
                                ? CityDesign.mapFill.opacity(0.89)
                                : CityDesign.mapFill.opacity(regionByAdcode[feature.id] == nil ? 0.14 : 0.34)
                            projected.fill(path, with: .color(color), style: FillStyle(eoFill: true))
                            projected.stroke(path, with: .color(CityDesign.outline), lineWidth: 0.85 / projection.scale)
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
                .background(CityDesign.marker, in: Capsule())
                .shadow(color: CityDesign.accent.opacity(0.25), radius: 6, y: 3)
                .allowsHitTesting(false)
        } else {
            HStack(spacing: 3) {
                Circle().fill(CityDesign.accent.opacity(0.76)).frame(width: 4, height: 4)
                Text(value).font(.system(size: min(max(labelSize, 8), 12), weight: .semibold)).foregroundStyle(Color.primary.opacity(0.78))
            }
            .padding(.horizontal, 3).padding(.vertical, 2)
            .background(CityDesign.mapBackground.opacity(0.68), in: Capsule())
            .allowsHitTesting(false)
        }
    }
}
