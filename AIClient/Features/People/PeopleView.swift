import SwiftUI
import UIKit

struct PeopleView: View {
    private let store: PeopleStore
    @State private var selectedPerson: SpecialPerson?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.rootTabIsActive) private var rootTabIsActive

    init(store: PeopleStore) {
        self.store = store
    }

    var body: some View {
        NavigationStack {
            Group {
                if !store.hasLoadedDirectory && store.errorMessage == nil {
                    PeopleLoadingTimeline()
                } else if let error = store.errorMessage, store.people.isEmpty {
                    ContentUnavailableView {
                        Label("载入失败", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("重试") { Task { await store.load(force: true) } }
                    }
                } else if store.people.isEmpty {
                    ContentUnavailableView(
                        "暂无人物",
                        systemImage: "person.2",
                        description: Text("人物资料正在整理中")
                    )
                } else {
                    PeopleSwimlaneExplorer(people: store.people, store: store) {
                        selectedPerson = $0
                    }
                }
            }
            .background(KnowledgePagePalette.canvas.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                KnowledgePageHeading(title: "人物", icon: "person.2")
                    .frame(maxWidth: 610)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(KnowledgePagePalette.canvas)
            }
            .floatingSheetClose("关闭人物", action: dismiss.callAsFunction)
            .navigationBarHidden(true)
        }
        .appSheet(isPresented: detailIsPresented) {
            PersonDetailSheet(
                selectedPerson: $selectedPerson,
                people: store.people,
                onClose: { selectedPerson = nil }
            )
            .appPresentationDetents([.large])
            .appPresentationCornerRadius(28)
            .appPresentationScrollsWithoutExpanding()
        }
        .task(id: rootTabIsActive) {
            guard rootTabIsActive else { return }
            await store.load()
            openRequestedPersonIfNeeded()
        }
        .onChange(of: store.people.map(\.id)) { _, _ in
            openRequestedPersonIfNeeded()
        }
    }

    private func openRequestedPersonIfNeeded() {
        #if DEBUG
        guard rootTabIsActive, selectedPerson == nil else { return }
        if ProcessInfo.processInfo.arguments.contains("--person-detail-preview") ||
            ProcessInfo.processInfo.arguments.contains("--article-detail-preview") {
            selectedPerson = store.people.first { $0.name == "Sam Altman" }
        }
        #endif
    }

    private var detailIsPresented: Binding<Bool> {
        Binding(
            get: { selectedPerson != nil },
            set: { isPresented in
                if !isPresented {
                    selectedPerson = nil
                }
            }
        )
    }
}

enum PeopleSearchSource: String, CaseIterable, Identifiable {
    case all
    case directory
    case x
    case wikipedia

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .directory: "人物库"
        case .x: "X"
        case .wikipedia: "维基百科"
        }
    }

    var prompt: String {
        switch self {
        case .all: "搜索人物、公司或领域"
        case .directory: "搜索人物、公司或领域"
        case .x: "搜索 X 平台账号"
        case .wikipedia: "搜索维基百科人物"
        }
    }
}

struct PeopleSearchRequest: Hashable {
    let isPresented: Bool
    let source: PeopleSearchSource
    let query: String
    let revision: Int

    init(isPresented: Bool, source: PeopleSearchSource, query: String, revision: Int = 0) {
        self.isPresented = isPresented
        self.source = source
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.revision = revision
    }

    var searchesX: Bool {
        isPresented && query.count >= 2 && (source == .all || source == .x)
    }

    var searchesWikipedia: Bool {
        isPresented && query.count >= 2 && (source == .all || source == .wikipedia)
    }
}

private struct PeopleSwimlaneExplorer: View {
    let people: [SpecialPerson]
    let store: PeopleStore
    let onOpenPerson: (SpecialPerson) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchIsFocused: Bool
    @State private var focusedPersonID: String?
    @State private var searchText = ""
    @State private var searchSource: PeopleSearchSource = .all
    @State private var searchRevision = 0
    @State private var showsSearch = false
    @State private var isRefreshing = false

    private var focusedPerson: SpecialPerson {
        if let focusedPersonID,
           let person = people.first(where: { $0.id == focusedPersonID }) {
            return person
        }
        return defaultCenter
    }

    private var defaultCenter: SpecialPerson {
        people.max {
            let lhs = ($0.relatedPeople.count, $0.todayCount, $0.totalCount)
            let rhs = ($1.relatedPeople.count, $1.todayCount, $1.totalCount)
            if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.2 < rhs.2
        } ?? people[0]
    }

    private var orderedPeople: [SpecialPerson] {
        people.sorted(by: SpecialPerson.activityOrder)
    }

    private var lanes: [PeopleRelationshipCluster] {
        PeopleRelationshipPlanner.clusters(
            around: focusedPerson,
            allPeople: people,
            maximumClusters: 4
        )
    }

    private var searchResults: [SpecialPerson] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = query.isEmpty ? orderedPeople : people.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
                ($0.organizationName?.localizedCaseInsensitiveContains(query) ?? false) ||
                $0.focusTags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
        return Array(source.prefix(query.isEmpty ? 7 : 5))
    }

    private var searchRequest: PeopleSearchRequest {
        PeopleSearchRequest(
            isPresented: showsSearch,
            source: searchSource,
            query: searchText,
            revision: searchRevision
        )
    }

    var body: some View {
        let lanes = lanes
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                utilityBar

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        focusedPersonHero(lanes: lanes)

                        if !lanes.isEmpty {
                            KnowledgeSectionHeading("关系网络")
                        }

                        if lanes.isEmpty {
                            emptyRelationships
                        } else {
                            ForEach(lanes) { lane in
                                relationshipLane(lane)
                            }
                        }
                    }
                    .frame(maxWidth: 610)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .padding(.bottom, 94)
                }
                .scrollIndicators(.hidden)
            }

            if showsSearch {
                searchPanel
                    .frame(maxWidth: 610)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            if focusedPersonID == nil {
                focusedPersonID = defaultCenter.id
            }
        }
        .task(id: focusedPerson.id) {
            await PeopleImagePreheater.preheatDetail(for: focusedPerson, baseURL: store.baseURL)
        }
        .task(id: searchRequest) {
            let request = searchRequest
            guard request.searchesX || request.searchesWikipedia else { return }
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            guard !Task.isCancelled, request == searchRequest else { return }
            if request.searchesX, request.searchesWikipedia {
                async let xSearch: Void = store.searchXPeople(query: request.query)
                async let wikipediaSearch: Void = store.searchWikipediaPeople(query: request.query)
                _ = await (xSearch, wikipediaSearch)
            } else if request.searchesX {
                await store.searchXPeople(query: request.query)
            } else if request.searchesWikipedia {
                await store.searchWikipediaPeople(query: request.query)
            }
        }
    }

    private var utilityBar: some View {
        HStack(spacing: 8) {
            Button {
                presentSearch()
            } label: {
                Label("搜索人物", systemImage: "magnifyingglass")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 13)
                    .frame(maxWidth: .infinity, minHeight: 45, alignment: .leading)
                    .knowledgeCard(cornerRadius: 13)
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    guard !isRefreshing else { return }
                    isRefreshing = true
                    Task {
                        await store.load(force: true)
                        isRefreshing = false
                    }
                } label: {
                    Label(isRefreshing ? "正在刷新" : "刷新人物资料", systemImage: "arrow.clockwise")
                }
                .disabled(isRefreshing)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .frame(width: 45, height: 45)
                    .knowledgeCard(cornerRadius: 13)
            }
            .accessibilityLabel("更多")
        }
        .foregroundStyle(KnowledgePagePalette.accent)
        .frame(maxWidth: 610)
        .padding(.horizontal, 20)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity)
    }

    private func presentSearch() {
        withAnimation(animation) { showsSearch = true }
        Task { @MainActor in searchIsFocused = true }
    }

    private func focusedPersonHero(lanes: [PeopleRelationshipCluster]) -> some View {
        let relationshipCount = Set(lanes.flatMap(\.members).map(\.id)).count

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                onOpenPerson(focusedPerson)
            } label: {
                HStack(spacing: 13) {
                    AvatarView(
                        url: focusedPerson.avatarURL(baseURL: store.baseURL),
                        name: focusedPerson.name,
                        size: 64,
                        assetName: focusedPerson.avatarAssetName
                    )
                    .overlay { Circle().strokeBorder(.white.opacity(0.32), lineWidth: 1) }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(focusedPerson.name)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(focusedPersonHeroSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(KnowledgePagePalette.heroTint)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }
                .padding(15)
            }
            .buttonStyle(PeoplePressStyle())
            .accessibilityHint("查看人物详情")

            Rectangle()
                .fill(.white.opacity(0.18))
                .frame(height: 1)
                .padding(.horizontal, 15)

            HStack(spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        heroMetric(value: relationshipCount, label: "关联人物")
                        heroMetric(value: focusedPerson.todayCount, label: "今日动态")
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        heroMetric(value: relationshipCount, label: "关联人物")
                        heroMetric(value: focusedPerson.todayCount, label: "今日动态")
                    }
                }
                Spacer(minLength: 0)
                if orderedPeople.count > 1 {
                    personArrow(-1, symbol: "chevron.left", label: "上一个人物")
                    personArrow(1, symbol: "chevron.right", label: "下一个人物")
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 15)
        }
        .background(KnowledgePagePalette.hero, in: .rect(cornerRadius: 18))
        .contentShape(Rectangle())
        .modifier(PeopleFocusSwipeModifier(onEnded: handleFocusSwipe))
    }

    private func personArrow(_ offset: Int, symbol: String, label: String) -> some View {
        Button {
            moveFocus(by: offset)
        } label: {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(alignment: .center) {
                    Circle()
                        .fill(.white.opacity(0.11))
                        .frame(width: 32, height: 32)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var focusedPersonHeroSubtitle: String {
        let role = focusedPerson.roles.first
        var parts: [String] = []
        if let organization = focusedPerson.organizationName ?? role?.organization,
           !organization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(organization)
        }
        if let title = role?.title,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !parts.contains(where: { $0.localizedCaseInsensitiveContains(title) }) {
            parts.append(title)
        }
        return parts.isEmpty ? focusedPerson.topic.rawValue : parts.joined(separator: " · ")
    }

    private func heroMetric(value: Int, label: String) -> some View {
        Text("\(value) \(label)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.88))
    }

    private var emptyRelationships: some View {
        ContentUnavailableView {
            Label("暂无已核实关系", systemImage: "person.2.slash")
        } actions: {
            Button("搜索其他人物", action: presentSearch)
        }
        .frame(maxWidth: .infinity)
        .knowledgeCard()
    }

    private func handleFocusSwipe(_ value: DragGesture.Value) {
        let horizontal = value.translation.width
        let vertical = value.translation.height
        let predictedHorizontal = value.predictedEndTranslation.width
        let horizontalIntent = abs(horizontal) > abs(vertical) * 0.75
        let shouldSwitch = abs(horizontal) >= 18 || abs(predictedHorizontal) >= 42

        if horizontalIntent, shouldSwitch {
            moveFocus(by: predictedHorizontal < 0 ? 1 : -1)
        } else if vertical <= -30, abs(vertical) > abs(horizontal) * 0.9 {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            onOpenPerson(focusedPerson)
        }
    }

    private func relationshipLane(_ lane: PeopleRelationshipCluster) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            KnowledgeSectionHeading(lane.title, detail: "\(lane.memberCount) 位")
                .padding(.horizontal, 13)
                .padding(.top, 13)

            ForEach(lane.members) { member in
                if let person = member.person {
                    Button {
                        focus(on: person)
                    } label: {
                        relationshipNode(member, isNavigable: true)
                    }
                    .buttonStyle(PeoplePressStyle())
                    .accessibilityHint("设为当前人物")
                } else {
                    relationshipNode(member, isNavigable: false)
                }
                if member.id != lane.members.last?.id {
                    Divider().padding(.leading, 62)
                }
            }
        }
        .padding(.bottom, 6)
        .knowledgeCard()
    }

    private func relationshipNode(_ member: PeopleRelationshipMember, isNavigable: Bool) -> some View {
        HStack(spacing: 10) {
            AvatarView(
                url: member.avatarURL(baseURL: store.baseURL),
                name: member.name,
                size: 38,
                assetName: member.person?.avatarAssetName ?? member.avatarAssetName
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(member.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(member.relationship)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.leading)

            Spacer(minLength: 4)
            if isNavigable {
                Image(systemName: "arrow.turn.up.right")
                    .font(.footnote)
                    .foregroundStyle(KnowledgePagePalette.accent)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 5)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var searchPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(searchSource.prompt, text: $searchText)
                    .focused($searchIsFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit {
                        searchRevision &+= 1
                    }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除搜索")
                }
                Button("完成") { dismissSearch() }
                    .font(.system(size: 15, weight: .semibold))
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)

            Picker("搜索来源", selection: $searchSource) {
                ForEach(PeopleSearchSource.allCases) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .accessibilityLabel("搜索来源")

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    switch searchSource {
                    case .all:
                        allSourcesSearchContent
                    case .directory:
                        directorySearchContent
                    case .x:
                        externalSearchContent(sourceName: "X 平台") {
                            xPlatformSearchContent
                        }
                    case .wikipedia:
                        externalSearchContent(sourceName: "维基百科") {
                            wikipediaSearchContent
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .frame(maxHeight: 520)
        }
        .knowledgeCard(cornerRadius: 17)
        .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
    }

    @ViewBuilder
    private var allSourcesSearchContent: some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.count < 2 {
            directorySearchContent
            if !query.isEmpty {
                Text("再输入一个字符，即可同时搜索 X 和维基百科")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
            }
        } else {
            searchSectionHeader("人物库")
            directorySearchContent
            searchSectionHeader("X 平台")
            xPlatformSearchContent
            searchSectionHeader("维基百科")
            wikipediaSearchContent
        }
    }

    @ViewBuilder
    private var directorySearchContent: some View {
        if searchResults.isEmpty {
            Text("人物库没有找到相关人物")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
        } else {
            ForEach(searchResults) { person in
                Button {
                    focus(on: person)
                    dismissSearch()
                } label: {
                    HStack(spacing: 11) {
                        AvatarView(
                            url: person.avatarURL(baseURL: store.baseURL),
                            name: person.name,
                            size: 38,
                            assetName: person.avatarAssetName
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.name)
                                .font(.system(size: 15, weight: .semibold))
                            Text(person.organizationName ?? person.topic.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 54)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func externalSearchContent<Content: View>(
        sourceName: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.count >= 2 {
            content()
        } else {
            Text(query.isEmpty ? "输入至少 2 个字符搜索\(sourceName)" : "再输入一个字符开始搜索\(sourceName)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
        }
    }

    private func searchSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Color.primary.opacity(0.025))
    }

    @ViewBuilder
    private var xPlatformSearchContent: some View {
        if store.isSearchingX || store.xSearchQuery != searchRequest.query {
            HStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)
                Text("正在搜索 X 平台…")
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .frame(height: 50)
        } else if let error = store.xSearchErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
        } else if store.xSearchResults.isEmpty {
            Text("X 平台没有找到相关账号")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
        } else {
            ForEach(store.xSearchResults) { result in
                Button {
                    selectXSearchResult(result)
                } label: {
                    HStack(spacing: 11) {
                        ZStack(alignment: .bottomTrailing) {
                            AvatarView(url: result.avatarURL, name: result.name, size: 40)
                            if !result.alreadyInDirectory {
                                Image(systemName: "plus")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 17, height: 17)
                                    .background(Color.accentColor, in: Circle())
                                    .overlay { Circle().stroke(.background, lineWidth: 2) }
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(result.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .lineLimit(1)
                                if result.verified {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.blue)
                                }
                            }
                            Text(
                                result.alreadyInDirectory
                                    ? "\(result.handle) · 已在人物库"
                                    : "\(result.handle) · 点击头像加入人物库"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }

                        Spacer()
                        if store.importingXUserIDs.contains(result.id) {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(result.alreadyInDirectory ? "查看" : "加入")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(result.alreadyInDirectory ? .secondary : Color.accentColor)
                        }
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 58)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(store.importingXUserIDs.contains(result.id))
                .accessibilityLabel(
                    result.alreadyInDirectory
                        ? "查看人物库中的 \(result.name)"
                        : "将 \(result.name) 加入人物库"
                )
            }
        }
    }

    @ViewBuilder
    private var wikipediaSearchContent: some View {
        if store.isSearchingWikipedia || store.wikipediaSearchQuery != searchRequest.query {
            HStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)
                Text("正在搜索维基百科人物…")
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .frame(height: 50)
        } else if let error = store.wikipediaSearchErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
        } else if store.wikipediaSearchResults.isEmpty {
            Text("维基百科没有找到相关人物")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
        } else {
            ForEach(store.wikipediaSearchResults) { result in
                Button {
                    selectWikipediaSearchResult(result)
                } label: {
                    HStack(spacing: 11) {
                        ZStack(alignment: .bottomTrailing) {
                            AvatarView(url: result.avatarURL, name: result.name, size: 40)
                            if !result.alreadyInDirectory {
                                Image(systemName: "plus")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 17, height: 17)
                                    .background(Color.accentColor, in: Circle())
                                    .overlay { Circle().stroke(.background, lineWidth: 2) }
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.name)
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(1)
                            Text(
                                result.alreadyInDirectory
                                    ? "\(result.sourceLabel) · 已在人物库"
                                    : "\(result.description ?? result.sourceLabel) · 点击头像加入人物库"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }

                        Spacer()
                        if store.importingWikipediaIDs.contains(result.id) {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(result.alreadyInDirectory ? "查看" : "加入")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(result.alreadyInDirectory ? .secondary : Color.accentColor)
                        }
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 58)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(store.importingWikipediaIDs.contains(result.id))
                .accessibilityLabel(
                    result.alreadyInDirectory
                        ? "查看人物库中的 \(result.name)"
                        : "将维基百科人物 \(result.name) 加入人物库"
                )
            }
        }
    }

    private func selectXSearchResult(_ result: XPersonSearchResult) {
        if let existing = store.existingPerson(for: result) {
            focus(on: existing)
            dismissSearch()
            return
        }
        Task {
            guard let person = await store.importXPerson(result) else { return }
            focus(on: person)
            dismissSearch()
        }
    }

    private func selectWikipediaSearchResult(_ result: WikipediaPersonSearchResult) {
        if let existing = store.existingPerson(for: result) {
            focus(on: existing)
            dismissSearch()
            return
        }
        Task {
            guard let person = await store.importWikipediaPerson(result) else { return }
            focus(on: person)
            dismissSearch()
        }
    }

    private func moveFocus(by offset: Int) {
        let orderedPeople = orderedPeople
        guard let currentIndex = orderedPeople.firstIndex(where: { $0.id == focusedPerson.id }) else {
            return
        }
        let nextIndex = (currentIndex + offset + orderedPeople.count) % orderedPeople.count
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        focus(on: orderedPeople[nextIndex])
    }

    private func focus(on person: SpecialPerson) {
        withAnimation(animation) {
            focusedPersonID = person.id
        }
    }

    private func dismissSearch() {
        searchIsFocused = false
        withAnimation(animation) {
            showsSearch = false
            searchText = ""
            searchSource = .all
        }
    }

    private var animation: Animation? {
        reduceMotion ? nil : AppModalMotion.animation
    }
}

private struct PeopleFocusSwipeModifier: ViewModifier {
    let onEnded: (DragGesture.Value) -> Void
    @GestureState private var horizontalOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: max(-18, min(18, horizontalOffset * 0.18)))
            .highPriorityGesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .local)
                    .updating($horizontalOffset) { value, offset, _ in offset = value.translation.width }
                    .onEnded(onEnded)
            )
    }
}

private struct PeopleLoadingTimeline: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 22) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(spacing: 10) {
                            Circle().frame(width: 82, height: 82)
                            Text("人物姓名").font(.caption)
                        }
                        .frame(width: 88)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
                Text("最新动态")
                    .font(.title2.bold())
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                ForEach(0..<4, id: \.self) { _ in
                    HStack(alignment: .top, spacing: 14) {
                        Circle().frame(width: 50, height: 50)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("人物姓名").font(.headline)
                            Text("人物的最新动态内容将在这里显示")
                            Text("更多动态摘要内容")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
            }
            .foregroundStyle(Color.secondary.opacity(0.28))
            .redacted(reason: .placeholder)
        }
    }
}

struct PeoplePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

#Preview("人物动态") {
    PeopleView(store: PeopleStore())
}
