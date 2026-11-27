import SwiftUI

enum CityRegionLevel: String, Decodable, Hashable {
    case country, province, city, district

    var title: String {
        switch self {
        case .country: "全国"
        case .province: "省级"
        case .city: "地市级"
        case .district: "区县级"
        }
    }
}

struct CityRegion: Decodable, Identifiable, Hashable {
    var id: String { String(adcode) }
    let adcode: Int
    let name: String
    let level: CityRegionLevel
    let children: [CityRegion]

    var childTitle: String {
        if children.first?.level == .district { return "下辖区县" }
        switch level {
        case .country: return "选择省份"
        case .province: return "下辖地区"
        case .city, .district: return "区域地图"
        }
    }

    func path(to adcode: Int) -> [CityRegion]? {
        if self.adcode == adcode { return [] }
        for child in children {
            if let path = child.path(to: adcode) { return [child] + path }
        }
        return nil
    }
}

struct CityRegionJourney: Equatable {
    let root: CityRegion
    private(set) var path: [CityRegion]

    init(root: CityRegion, startingAdcode: Int) {
        self.root = root
        self.path = root.path(to: startingAdcode) ?? []
    }

    var current: CityRegion { path.last ?? root }
    var parent: CityRegion? {
        guard !path.isEmpty else { return nil }
        return path.dropLast().last ?? root
    }
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

private enum CityDashboardTab: String, CaseIterable, Identifiable {
    case map = "地图", data = "数据", industry = "产业", transport = "交通", culture = "文旅"
    var id: String { rawValue }
    var showsMap: Bool { self == .map }

    func showsSection(_ section: CityObservationStatistics.Section) -> Bool {
        let keywords: [String]
        switch self {
        case .map: return false
        case .data: return true
        case .industry: keywords = ["农业", "工业", "产业", "建筑业", "服务业", "投资"]
        case .transport: keywords = ["交通", "运输", "邮电"]
        case .culture: keywords = ["文化", "旅游", "文旅", "体育"]
        }
        let title = section.title.filter { !$0.isWhitespace }
        return keywords.contains(where: title.contains)
    }

    func includes(_ metric: CityObservationStatistics.Metric) -> Bool {
        switch self {
        case .map: false
        case .data: true
        case .industry: ["industry", "agriculture", "investment"].contains(metric.group)
        case .transport: metric.group == "transport"
        case .culture: metric.group == "culture"
        }
    }
}

private enum CityContentLoad<Value> {
    case loading
    case loaded(Value)
    case failed
}

private enum CityMapNavigationDirection {
    case forward
    case backward
    case lateral
}

struct CityNewsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var catalog: CityContentLoad<CityRegion> = .loading
    @State private var catalogRetry = 0

    var body: some View {
        Group {
            switch catalog {
            case .loading:
                ProgressView("正在载入城市目录")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                CityLoadFailure(title: "城市目录载入失败") { catalogRetry += 1 }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(root):
                CityObservationView(root: root)
            }
        }
        .floatingSheetClose("关闭城市观察", action: dismiss.callAsFunction)
        .task(id: catalogRetry) {
            catalog = .loading
            do {
                let root = try await CityObservationService().catalog()
                try Task.checkCancellation()
                catalog = .loaded(root)
            } catch {
                if !Task.isCancelled { catalog = .failed }
            }
        }
    }
}

private struct CityObservationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var journey: CityRegionJourney
    @State private var selectedID: String?
    @State private var selectedTab: CityDashboardTab = .map
    @State private var showsList = false
    @State private var showsMap = false
    @State private var mapNavigationDirection: CityMapNavigationDirection = .forward
    @State private var mapRetry = 0
    @State private var mapState: (scope: Int, result: CityContentLoad<[CityMapFeature]>)?
    private let service = CityObservationService()

    init(root: CityRegion) {
        var startingAdcode = 440000
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--city-district-preview") {
            startingAdcode = 440305
        } else if arguments.contains("--city-city-preview") {
            startingAdcode = 440300
        }
        #endif
        let journey = CityRegionJourney(root: root, startingAdcode: startingAdcode)
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
                observationPicker
                if selectedTab.showsMap {
                    mapSection(scope: scope, selected: selected)
                } else {
                    CityStatisticsView(adcode: region.adcode, tab: selectedTab, service: service)
                        .id(region.adcode)
                }
            }
            .frame(maxWidth: 650)
            .padding(.horizontal, 20)
            .padding(.top, 19)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(KnowledgePagePalette.canvas.ignoresSafeArea())
        .tint(CityDesign.accent)
        .sensoryFeedback(.selection, trigger: selectedID)
        .sensoryFeedback(.impact(weight: .light), trigger: journey.current.id)
        .accessibilityIdentifier("city-region-screen")
        .task(id: MapRequest(adcode: scope.adcode, retry: mapRetry)) {
            let adcode = scope.adcode
            mapState = (adcode, .loading)
            do {
                let features = try await service.boundaries(for: adcode)
                try Task.checkCancellation()
                mapState = (adcode, .loaded(features))
            } catch {
                if !Task.isCancelled { mapState = (adcode, .failed) }
            }
        }
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
            if let mapState, mapState.scope == scope.adcode, case let .loaded(features) = mapState.result {
                CityFullScreenMap(scope: scope, features: features, selection: $selectedID)
            }
        }
    }

    private struct MapRequest: Equatable {
        let adcode: Int
        let retry: Int
    }

    private var observationPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(CityDashboardTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.subheadline.weight(selectedTab == tab ? .semibold : .medium))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .foregroundStyle(selectedTab == tab ? CityDesign.accent : .secondary)
                            .background(selectedTab == tab ? CityDesign.accent.opacity(0.10) : .clear, in: Capsule())
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("城市资料栏目")
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
                 ? region.level.title
                 : "\(region.level.title) · \(region.children.count) 个下级地区")
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
                KnowledgeSectionHeading(scope.childTitle)
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
                    mapContent(scope: scope, selected: selected)
                        .id(scope.id)
                        .transition(mapTransition)
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

    @ViewBuilder
    private func mapContent(scope: CityRegion, selected: CityRegion?) -> some View {
        let result = mapState.flatMap { $0.scope == scope.adcode ? $0.result : nil } ?? .loading
        switch result {
        case .loading:
            ProgressView("正在载入地区地图")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            CityLoadFailure(title: "地区地图载入失败") { mapRetry += 1 }
        case let .loaded(features):
            ZStack(alignment: .bottomTrailing) {
                CityAdministrativeMap(scope: scope, features: features, selectedRegionID: selected?.id, onSelect: select)
                if !features.isEmpty {
                    Button { showsMap = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CityDesign.accent)
                            .frame(width: 44, height: 44)
                            .knowledgeCard(cornerRadius: 12)
                    }
                    .buttonStyle(CityPressStyle())
                    .accessibilityLabel("全屏地图")
                }
            }
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
                Text(region.id == journey.current.id ? "当前地区" : region.level.title)
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

private struct CityLoadFailure: View {
    let title: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "wifi.exclamationmark")
        } actions: {
            Button("重试", action: retry)
        }
    }
}

private struct CityStatisticsView: View {
    let adcode: Int
    let tab: CityDashboardTab
    let service: CityObservationService
    @State private var state: CityContentLoad<CityObservationStatistics> = .loading
    @State private var retry = 0

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView("正在载入统计资料")
                    .frame(maxWidth: .infinity, minHeight: 150)
            case .failed:
                CityLoadFailure(title: "统计资料载入失败") { retry += 1 }
            case let .loaded(statistics):
                content(statistics)
            }
        }
        .task(id: retry) {
            state = .loading
            do {
                let statistics = try await service.statistics(for: adcode)
                try Task.checkCancellation()
                state = .loaded(statistics)
            } catch {
                if !Task.isCancelled { state = .failed }
            }
        }
    }

    @ViewBuilder
    private func content(_ statistics: CityObservationStatistics) -> some View {
        let metrics = statistics.metrics.filter(tab.includes)
        let sections = statistics.sections.filter(tab.showsSection)
        if statistics.status == .notCovered {
            ContentUnavailableView("来源尚未收录该地区", systemImage: "chart.bar.xaxis")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                if metrics.isEmpty {
                    if sections.isEmpty {
                        ContentUnavailableView("暂无\(tab.rawValue)资料", systemImage: "chart.bar.xaxis")
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(metrics) { metric in
                            metricRow(metric)
                            if metric.id != metrics.last?.id { Divider() }
                        }
                    }
                    .padding(.horizontal, 14)
                    .knowledgeCard()
                }

                if tab == .data {
                    ForEach(Array(statistics.notes.enumerated()), id: \.offset) { _, note in
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if !sections.isEmpty {
                    Text("统计公报").font(.headline).accessibilityAddTraits(.isHeader)
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        DisclosureGroup(section.title) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                                    Text(paragraph).font(.subheadline).textSelection(.enabled)
                                }
                            }
                            .padding(.vertical, 10)
                        }
                    }
                }

                if let source = statistics.source {
                    Link(destination: source.url) {
                        Label(source.title, systemImage: "arrow.up.right.square")
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metricRow(_ metric: CityObservationStatistics.Metric) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(metric.label).font(.subheadline)
                Spacer(minLength: 4)
                Text([metric.value, metric.unit].filter { !$0.isEmpty }.joined(separator: " "))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            HStack(spacing: 8) {
                if metric.year > 0 {
                    Text("\(metric.year.formatted(.number.grouping(.never))) 年")
                }
                if let source = metric.source {
                    Link(source.publisher.isEmpty ? source.title : source.publisher, destination: source.url)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
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
        let title = scope.childTitle
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
    let features: [CityMapFeature]
    @Binding var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            KnowledgePageHeading(title: scope.name, icon: "map", tint: CityDesign.accent)
            if let selected = scope.children.first(where: { $0.id == selection }) {
                Label(selected.name, systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CityDesign.accent)
            }
            CityAdministrativeMap(scope: scope, features: features, selectedRegionID: selection) { selection = $0.id }
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
    let features: [CityMapFeature]
    let selectedRegionID: String?
    let onSelect: (CityRegion) -> Void

    var body: some View {
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
