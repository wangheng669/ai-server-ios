import SwiftUI
import UIKit

struct PeopleView: View {
    private let store: PeopleStore
    @State private var selectedPerson: SpecialPerson?
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
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
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
    @GestureState private var focusTranslation: CGSize = .zero
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
        ZStack(alignment: .top) {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                utilityBar

                ScrollView {
                    LazyVStack(spacing: 14) {
                        focusedPersonHero

                        if lanes.isEmpty {
                            emptyRelationships
                        } else {
                            ForEach(Array(lanes.enumerated()), id: \.element.id) { index, lane in
                                relationshipLane(lane, index: index)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, 94)
                }
                .scrollIndicators(.hidden)
            }

            if showsSearch {
                searchPanel
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
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
            VStack(alignment: .leading, spacing: 1) {
                Text("人物关系")
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                Text("从一个人，看见他的关系网络")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

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
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel("更多")

            Button {
                withAnimation(animation) { showsSearch = true }
                Task { @MainActor in searchIsFocused = true }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("搜索人物")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var focusedPersonHero: some View {
        Button {
            onOpenPerson(focusedPerson)
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 14) {
                    AvatarView(
                        url: focusedPerson.avatarURL(baseURL: store.baseURL),
                        name: focusedPerson.name,
                        size: 68,
                        assetName: focusedPerson.avatarAssetName
                    )
                    .overlay {
                        Circle()
                            .stroke(Color(uiColor: .secondarySystemGroupedBackground), lineWidth: 4)
                            .overlay { Circle().stroke(Color.accentColor.opacity(0.7), lineWidth: 2) }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(focusedPerson.name)
                            .font(.system(size: 23, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(focusedPersonHeroSubtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 0) {
                    heroMetric(value: "\(relationshipCount)", label: "关联人物")
                    heroDivider
                    heroMetric(value: "\(lanes.count)", label: "关系分组")
                    heroDivider
                    heroMetric(value: "\(focusedPerson.todayCount)", label: "今日动态")
                }

                HStack(spacing: 8) {
                    sidePerson(previousPerson)

                    Label("左右滑动切换人物", systemImage: "arrow.left.and.right")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)

                    sidePerson(nextPerson)
                }
                .padding(.top, -3)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.055), lineWidth: 0.7)
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PeoplePressStyle())
        .offset(x: focusPreviewOffset)
        .highPriorityGesture(focusGesture)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(focusedPerson.name)，\(focusedPersonHeroSubtitle)，\(relationshipCount) 位关联人物")
        .accessibilityHint("点击查看详情，左右滑动切换人物")
        .accessibilityAction(named: "上一个人物") { moveFocus(by: -1) }
        .accessibilityAction(named: "下一个人物") { moveFocus(by: 1) }
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

    private func heroMetric(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var heroDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 0.7, height: 30)
    }

    private var emptyRelationships: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.tertiary)

            Text("暂无已核实关系")
                .font(.system(size: 16, weight: .semibold))

            Text("暂未收录可核实的直接关系")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Button("搜索其他人物") {
                withAnimation(animation) { showsSearch = true }
                Task { @MainActor in searchIsFocused = true }
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var focusDock: some View {
        HStack(spacing: 14) {
            sidePerson(previousPerson)

            HStack(spacing: 11) {
                AvatarView(
                    url: focusedPerson.avatarURL(baseURL: store.baseURL),
                    name: focusedPerson.name,
                    size: 48,
                    assetName: focusedPerson.avatarAssetName
                )
                .overlay {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.55), lineWidth: 2)
                        .padding(-3)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(focusedPerson.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(focusedPerson.organizationName ?? focusedPerson.roles.first?.title ?? focusedPerson.topic.rawValue)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.76))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            sidePerson(nextPerson)
        }
        .padding(.horizontal, 22)
        .offset(x: focusPreviewOffset)
        .frame(maxWidth: .infinity)
        .frame(height: 78)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
        .overlay(alignment: .top) {
            Capsule()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 24, height: 3)
                .offset(y: 6)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .clipped()
        .highPriorityGesture(focusGesture)
        .onTapGesture { onOpenPerson(focusedPerson) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(focusedPerson.name)，\(relationshipCount) 位关联人物")
        .accessibilityHint("点击或上滑查看详情，左右滑动切换人物")
        .accessibilityAction(named: "上一个人物") { moveFocus(by: -1) }
        .accessibilityAction(named: "下一个人物") { moveFocus(by: 1) }
    }

    private func sidePerson(_ person: SpecialPerson) -> some View {
        AvatarView(
            url: person.avatarURL(baseURL: store.baseURL),
            name: person.name,
            size: 30,
            assetName: person.avatarAssetName
        )
        .opacity(0.28)
        .accessibilityHidden(true)
    }

    private var previousPerson: SpecialPerson {
        adjacentPerson(by: -1)
    }

    private var nextPerson: SpecialPerson {
        adjacentPerson(by: 1)
    }

    private func adjacentPerson(by offset: Int) -> SpecialPerson {
        let orderedPeople = orderedPeople
        guard let currentIndex = orderedPeople.firstIndex(where: { $0.id == focusedPerson.id }) else {
            return focusedPerson
        }
        let index = (currentIndex + offset + orderedPeople.count) % orderedPeople.count
        return orderedPeople[index]
    }

    private var focusPreviewOffset: CGFloat {
        max(-18, min(18, focusTranslation.width * 0.18))
    }

    private var relationshipCount: Int {
        Set(lanes.flatMap(\.members).map(\.id)).count
    }

    private var focusGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .updating($focusTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
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
    }

    private func relationshipLane(
        _ lane: PeopleRelationshipCluster,
        index: Int
    ) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(lane.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(lane.memberCount) 位")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(lane.members) { member in
                    relationshipNode(member)
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.7)
        }
    }

    private func relationshipNode(_ member: PeopleRelationshipMember) -> some View {
        return Button {
            if let person = member.person {
                focus(on: person)
            }
        } label: {
            HStack(spacing: 10) {
                AvatarView(
                    url: member.avatarURL(baseURL: store.baseURL),
                    name: member.name,
                    size: 42,
                    assetName: member.person?.avatarAssetName ?? member.avatarAssetName
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(member.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(member.relationship)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(PeoplePressStyle())
        .accessibilityLabel("\(member.name)，与\(focusedPerson.name)的关系：\(member.relationship)")
        .accessibilityHint(member.person != nil ? "点击设为当前人物" : "")
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 22, y: 8)
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
