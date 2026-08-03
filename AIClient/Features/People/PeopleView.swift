import SwiftUI
import UIKit

struct PeopleView: View {
    @Binding private var showsDetail: Bool
    @Binding private var notificationPersonID: String?
    @Binding private var notificationVideoID: Int64?
    private let store: PeopleStore
    @State private var selectedPerson: SpecialPerson?
    @Environment(\.rootTabIsActive) private var rootTabIsActive

    init(
        store: PeopleStore,
        showsDetail: Binding<Bool> = .constant(false),
        notificationPersonID: Binding<String?> = .constant(nil),
        notificationVideoID: Binding<Int64?> = .constant(nil)
    ) {
        self.store = store
        _showsDetail = showsDetail
        _notificationPersonID = notificationPersonID
        _notificationVideoID = notificationVideoID
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    if store.isLoading && store.people.isEmpty {
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
                        PeopleSwimlaneExplorer(
                            people: store.people,
                            baseURL: store.baseURL,
                            xSearchResults: store.xSearchResults,
                            isSearchingX: store.isSearchingX,
                            xSearchErrorMessage: store.xSearchErrorMessage,
                            importingXUserIDs: store.importingXUserIDs,
                            wikipediaSearchResults: store.wikipediaSearchResults,
                            isSearchingWikipedia: store.isSearchingWikipedia,
                            wikipediaSearchErrorMessage: store.wikipediaSearchErrorMessage,
                            importingWikipediaIDs: store.importingWikipediaIDs,
                            onOpenPerson: { selectedPerson = $0 },
                            onRefresh: { await store.load(force: true) },
                            onSearchX: { await store.searchXPeople(query: $0) },
                            onImportX: { await store.importXPerson($0) },
                            onSearchWikipedia: { await store.searchWikipediaPeople(query: $0) },
                            onImportWikipedia: { await store.importWikipediaPerson($0) }
                        )
                    }
                }

            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .sheet(isPresented: detailIsPresented) {
            PersonDetailSheet(
                selectedPerson: $selectedPerson,
                people: store.people,
                notificationVideoID: $notificationVideoID,
                onClose: { selectedPerson = nil }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationContentInteraction(.scrolls)
        }
        .task(id: rootTabIsActive) {
            guard rootTabIsActive else { return }
            await store.load()
            openNotificationPersonIfNeeded()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--person-detail-preview") ||
                ProcessInfo.processInfo.arguments.contains("--article-detail-preview") ||
                ProcessInfo.processInfo.arguments.contains("--video-detail-preview") {
                selectedPerson = store.people.first { $0.name == "Sam Altman" }
            }
            #endif
        }
        .onAppear { showsDetail = selectedPerson != nil }
        .onChange(of: selectedPerson) { _, person in
            showsDetail = person != nil
        }
        .onChange(of: notificationPersonID) { _, _ in
            openNotificationPersonIfNeeded()
        }
        .onDisappear { showsDetail = false }
    }

    private func openNotificationPersonIfNeeded() {
        guard let personID = notificationPersonID, !personID.isEmpty,
              let person = store.people.first(where: { $0.id == personID }) else { return }
        selectedPerson = person
        notificationPersonID = nil
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
    let baseURL: URL
    let xSearchResults: [XPersonSearchResult]
    let isSearchingX: Bool
    let xSearchErrorMessage: String?
    let importingXUserIDs: Set<String>
    let wikipediaSearchResults: [WikipediaPersonSearchResult]
    let isSearchingWikipedia: Bool
    let wikipediaSearchErrorMessage: String?
    let importingWikipediaIDs: Set<String>
    let onOpenPerson: (SpecialPerson) -> Void
    let onRefresh: () async -> Void
    let onSearchX: (String) async -> Void
    let onImportX: (XPersonSearchResult) async -> SpecialPerson?
    let onSearchWikipedia: (String) async -> Void
    let onImportWikipedia: (WikipediaPersonSearchResult) async -> SpecialPerson?

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
        people.sorted {
            let lhs = ($0.todayCount, $0.relatedPeople.count, $0.totalCount)
            let rhs = ($1.todayCount, $1.relatedPeople.count, $1.totalCount)
            if lhs.0 != rhs.0 { return lhs.0 > rhs.0 }
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            if lhs.2 != rhs.2 { return lhs.2 > rhs.2 }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
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
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                utilityBar

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if lanes.isEmpty {
                            emptyRelationships
                        } else {
                            ForEach(Array(lanes.enumerated()), id: \.element.id) { index, lane in
                                relationshipLane(lane, index: index)
                            }
                        }
                    }
                    .padding(.bottom, 18)
                }
                .scrollIndicators(.hidden)

                focusDock
                    .padding(.bottom, 56)
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
            await PeopleImagePreheater.preheatDetail(for: focusedPerson, baseURL: baseURL)
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
                async let xSearch: Void = onSearchX(request.query)
                async let wikipediaSearch: Void = onSearchWikipedia(request.query)
                _ = await (xSearch, wikipediaSearch)
            } else if request.searchesX {
                await onSearchX(request.query)
            } else if request.searchesWikipedia {
                await onSearchWikipedia(request.query)
            }
        }
    }

    private var utilityBar: some View {
        HStack {
            Menu {
                Button {
                    guard !isRefreshing else { return }
                    isRefreshing = true
                    Task {
                        await onRefresh()
                        isRefreshing = false
                    }
                } label: {
                    Label(isRefreshing ? "正在刷新" : "刷新人物资料", systemImage: "arrow.clockwise")
                }
                .disabled(isRefreshing)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .accessibilityLabel("更多")

            Spacer()

            Button {
                withAnimation(animation) { showsSearch = true }
                Task { @MainActor in searchIsFocused = true }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("搜索人物")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .frame(height: 48)
    }

    private var emptyRelationships: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.tertiary)

            Text("暂无已核实关系")
                .font(.system(size: 16, weight: .semibold))

            Text("服务器尚未提供可核实的直接关系")
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
        .padding(.vertical, 48)
        .accessibilityElement(children: .combine)
    }

    private var focusDock: some View {
        HStack(spacing: 14) {
            sidePerson(previousPerson)

            HStack(spacing: 11) {
                AvatarView(
                    url: focusedPerson.avatarURL(baseURL: baseURL),
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
            url: person.avatarURL(baseURL: baseURL),
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
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(lane.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(lane.memberCount)")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 15) {
                    ForEach(lane.members) { member in
                        relationshipNode(member)
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, index == 0 ? 12 : 15)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.leading, 20)
        }
    }

    private func relationshipNode(_ member: PeopleRelationshipMember) -> some View {
        return Button {
            if let person = member.person {
                focus(on: person)
            }
        } label: {
            VStack(spacing: 5) {
                AvatarView(
                    url: member.avatarURL(baseURL: baseURL),
                    name: member.name,
                    size: 48,
                    assetName: member.person?.avatarAssetName ?? member.avatarAssetName
                )

                Text(member.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: 62)
            .contentShape(Rectangle())
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
                            url: person.avatarURL(baseURL: baseURL),
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
        if isSearchingX {
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
        } else if let xSearchErrorMessage {
            Label(xSearchErrorMessage, systemImage: "exclamationmark.triangle")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
        } else if xSearchResults.isEmpty {
            Text("X 平台没有找到相关账号")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
        } else {
            ForEach(xSearchResults) { result in
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
                        if importingXUserIDs.contains(result.id) {
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
                .disabled(importingXUserIDs.contains(result.id))
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
        if isSearchingWikipedia {
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
        } else if let wikipediaSearchErrorMessage {
            Label(wikipediaSearchErrorMessage, systemImage: "exclamationmark.triangle")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
        } else if wikipediaSearchResults.isEmpty {
            Text("维基百科没有找到相关人物")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
        } else {
            ForEach(wikipediaSearchResults) { result in
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
                        if importingWikipediaIDs.contains(result.id) {
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
                .disabled(importingWikipediaIDs.contains(result.id))
                .accessibilityLabel(
                    result.alreadyInDirectory
                        ? "查看人物库中的 \(result.name)"
                        : "将维基百科人物 \(result.name) 加入人物库"
                )
            }
        }
    }

    private func selectXSearchResult(_ result: XPersonSearchResult) {
        if let existing = people.first(where: { person in
            (result.personID.map { $0 == person.id } ?? false) ||
                person.xUserID == result.id ||
                person.xScreenName?.caseInsensitiveCompare(result.screenName) == .orderedSame
        }) {
            focus(on: existing)
            dismissSearch()
            return
        }
        Task {
            guard let person = await onImportX(result) else { return }
            focus(on: person)
            dismissSearch()
        }
    }

    private func selectWikipediaSearchResult(_ result: WikipediaPersonSearchResult) {
        if let personID = result.personID,
           let existing = people.first(where: { $0.id == personID }) {
            focus(on: existing)
            dismissSearch()
            return
        }
        Task {
            guard let person = await onImportWikipedia(result) else { return }
            focus(on: person)
            dismissSearch()
        }
    }

    private func moveFocus(by offset: Int) {
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
        reduceMotion ? nil : .snappy(duration: 0.32)
    }
}

private struct PeopleStarMapExplorer: View {
    let people: [SpecialPerson]
    let baseURL: URL
    let onOpenPerson: (SpecialPerson) -> Void
    let onRefresh: () async -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchIsFocused: Bool
    @State private var focusedPersonID: String?
    @State private var searchText = ""
    @State private var showsSearch = false
    @State private var isRefreshing = false

    private var focusedPerson: SpecialPerson {
        if let focusedPersonID, let person = people.first(where: { $0.id == focusedPersonID }) {
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

    private var clusters: [PeopleRelationshipCluster] {
        PeopleRelationshipPlanner.clusters(around: focusedPerson, allPeople: people)
    }

    private var orderedPeople: [SpecialPerson] {
        people.sorted(by: activityOrder)
    }

    private var searchResults: [SpecialPerson] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = query.isEmpty ? orderedPeople : people.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
                ($0.organizationName?.localizedCaseInsensitiveContains(query) ?? false) ||
                $0.focusTags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
        return Array(source.prefix(6))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()

                PeopleOrbitCanvas(
                    focusedPerson: focusedPerson,
                    clusters: clusters,
                    allPeople: people,
                    baseURL: baseURL,
                    onOpenCenter: { onOpenPerson(focusedPerson) },
                    onSelectMember: selectMember
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 36)
                        .onEnded(handleStarMapSwipe)
                )
                .animation(animation, value: focusedPerson.id)
                .accessibilityHint("左右滑动切换人物，上滑展开人物详情")

                if showsSearch {
                    searchPanel
                        .padding(.leading, 12)
                        .padding(.trailing, 52)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    Button {
                        withAnimation(animation) { showsSearch = true }
                        Task { @MainActor in searchIsFocused = true }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 48, height: 48)
                            .background(.regularMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                    }
                    .buttonStyle(PeoplePressStyle())
                    .padding(.trailing, 56)
                    .padding(.top, 10)
                    .accessibilityLabel("搜索人物")
                }

                VStack {
                    Spacer()
                    quickSwitcher
                        .padding(.horizontal, 12)
                        .padding(.bottom, 92)
                }
                .opacity(showsSearch ? 0 : 1)
                .allowsHitTesting(!showsSearch)
                .animation(animation, value: showsSearch)
            }
        }
        .onAppear {
            if focusedPersonID == nil {
                focusedPersonID = defaultCenter.id
            }
        }
        .task(id: focusedPerson.id) {
            await PeopleImagePreheater.preheatDetail(for: focusedPerson, baseURL: baseURL)
        }
    }

    private var quickSwitcher: some View {
        HStack(spacing: 9) {
            Text("\(people.count) 人")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .fixedSize()

            Divider()
                .frame(height: 28)

            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 7) {
                        ForEach(orderedPeople) { person in
                            let isFocused = person.id == focusedPerson.id
                            Button {
                                focus(on: person)
                            } label: {
                                HStack(spacing: 6) {
                                    AvatarView(
                                        url: person.avatarURL(baseURL: baseURL),
                                        name: person.name,
                                        size: 30,
                                        assetName: person.avatarAssetName
                                    )
                                    Text(person.name)
                                        .font(.system(size: 13, weight: isFocused ? .semibold : .medium))
                                        .foregroundStyle(isFocused ? Color.accentColor : Color.primary)
                                        .lineLimit(1)
                                }
                                .padding(.leading, 4)
                                .padding(.trailing, 10)
                                .frame(height: 40)
                                .background(
                                    isFocused ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.045),
                                    in: Capsule()
                                )
                                .overlay {
                                    if isFocused {
                                        Capsule()
                                            .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
                                    }
                                }
                            }
                            .id(person.id)
                            .buttonStyle(PeoplePressStyle())
                            .accessibilityLabel(
                                isFocused ? "\(person.name)，当前人物" : "切换到 \(person.name)"
                            )
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onChange(of: focusedPerson.id, initial: true) { _, personID in
                    withAnimation(animation) {
                        reader.scrollTo(personID, anchor: .center)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 14, y: 5)
    }

    private var searchPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索人物、公司或领域", text: $searchText)
                    .focused($searchIsFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
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
                Button("完成") {
                    dismissSearch()
                }
                .font(.system(size: 15, weight: .semibold))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)

            Divider()

            if searchResults.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(height: 170)
            } else {
                VStack(spacing: 0) {
                    ForEach(searchResults) { person in
                        Button {
                            focus(on: person)
                            dismissSearch()
                        } label: {
                            HStack(spacing: 11) {
                                AvatarView(
                                    url: person.avatarURL(baseURL: baseURL),
                                    name: person.name,
                                    size: 36,
                                    assetName: person.avatarAssetName
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(person.name)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(person.organizationName ?? person.topic.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PeoplePressStyle())
                    }
                }
            }

            Divider()
            Button {
                guard !isRefreshing else { return }
                isRefreshing = true
                Task {
                    await onRefresh()
                    isRefreshing = false
                }
            } label: {
                Label(isRefreshing ? "正在刷新" : "刷新人物资料", systemImage: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.1), radius: 18, y: 7)
    }

    private func selectMember(_ member: PeopleRelationshipMember) {
        guard let person = member.person else { return }
        focus(on: person)
    }

    private func focus(on person: SpecialPerson) {
        withAnimation(animation) {
            focusedPersonID = person.id
        }
    }

    private func handleStarMapSwipe(_ value: DragGesture.Value) {
        let horizontalDistance = value.translation.width
        let verticalDistance = value.translation.height

        if verticalDistance <= -64,
           abs(verticalDistance) > abs(horizontalDistance) * 1.15 {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            onOpenPerson(focusedPerson)
            return
        }

        guard abs(horizontalDistance) >= 56,
              abs(horizontalDistance) > abs(verticalDistance) * 1.25,
              let currentIndex = orderedPeople.firstIndex(where: { $0.id == focusedPerson.id }) else {
            return
        }

        let offset = horizontalDistance < 0 ? 1 : -1
        let nextIndex = (currentIndex + offset + orderedPeople.count) % orderedPeople.count
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        focus(on: orderedPeople[nextIndex])
    }

    private func dismissSearch() {
        searchIsFocused = false
        withAnimation(animation) { showsSearch = false }
    }

    private func activityOrder(_ lhs: SpecialPerson, _ rhs: SpecialPerson) -> Bool {
        let left = (lhs.todayCount, lhs.relatedPeople.count, lhs.totalCount)
        let right = (rhs.todayCount, rhs.relatedPeople.count, rhs.totalCount)
        if left.0 != right.0 { return left.0 > right.0 }
        if left.1 != right.1 { return left.1 > right.1 }
        if left.2 != right.2 { return left.2 > right.2 }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private var animation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.34)
    }
}

private struct PeopleOrbitCanvas: View {
    let focusedPerson: SpecialPerson
    let clusters: [PeopleRelationshipCluster]
    let allPeople: [SpecialPerson]
    let baseURL: URL
    let onOpenCenter: () -> Void
    let onSelectMember: (PeopleRelationshipMember) -> Void

    private let innerCount = 6
    private let maximumVisiblePeople = 14

    private struct OrbitItem: Identifiable {
        let member: PeopleRelationshipMember
        let relationshipGroup: String
        let colorIndex: Int

        var id: String { member.id }
    }

    private struct Placement: Identifiable {
        let item: OrbitItem
        let point: CGPoint
        let isInner: Bool

        var id: String { item.id }
    }

    private var orbitItems: [OrbitItem] {
        var seen = Set<String>()
        var items: [OrbitItem] = []
        for (colorIndex, cluster) in clusters.enumerated() {
            for member in cluster.members where seen.insert(member.id).inserted {
                items.append(
                    OrbitItem(
                        member: member,
                        relationshipGroup: cluster.title,
                        colorIndex: colorIndex
                    )
                )
            }
        }

        return Array(items.prefix(maximumVisiblePeople))
    }

    var body: some View {
        GeometryReader { proxy in
            let center = centerPoint(size: proxy.size)
            let placements = placements(size: proxy.size, center: center)

            ZStack {
                RadialGradient(
                    colors: [Color.accentColor.opacity(0.055), Color.clear],
                    center: UnitPoint(x: center.x / max(proxy.size.width, 1), y: center.y / max(proxy.size.height, 1)),
                    startRadius: 4,
                    endRadius: min(proxy.size.width, proxy.size.height) * 0.46
                )
                .accessibilityHidden(true)

                Canvas { context, _ in
                    drawOrbitGuides(context: context, center: center, size: proxy.size)
                    drawConnections(context: context, center: center, placements: placements)
                }
                .accessibilityHidden(true)

                centerNode
                    .position(center)

                ForEach(placements) { placement in
                    Button {
                        onSelectMember(placement.item.member)
                    } label: {
                        orbitNode(for: placement)
                    }
                    .buttonStyle(PeoplePressStyle())
                    .position(placement.point)
                    .accessibilityLabel(
                        "\(placement.item.member.name)，与\(focusedPerson.name)的关系：\(placement.item.member.relationship)"
                    )
                    .accessibilityHint(
                        placement.item.member.person == nil ? "此人物暂无完整档案" : "点击切换为中心人物"
                    )
                }

                ForEach(placements.filter(\.isInner)) { placement in
                    Text(placement.item.relationshipGroup)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(tint(for: placement.item.colorIndex))
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .frame(height: 17)
                        .background(.thinMaterial, in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(tint(for: placement.item.colorIndex).opacity(0.18), lineWidth: 0.5)
                        }
                        .position(
                            relationshipLabelPoint(
                                from: center,
                                to: placement.point
                            )
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var centerNode: some View {
        Button(action: onOpenCenter) {
            VStack(spacing: 9) {
                AvatarView(
                    url: focusedPerson.avatarURL(baseURL: baseURL),
                    name: focusedPerson.name,
                    size: 74,
                    assetName: focusedPerson.avatarAssetName
                )
                .overlay {
                    Circle()
                        .stroke(Color(uiColor: .systemBackground), lineWidth: 4)
                        .overlay {
                            Circle().stroke(Color.accentColor, lineWidth: 2.5)
                        }
                }
                .shadow(color: Color.accentColor.opacity(0.16), radius: 14, y: 5)

                Text(focusedPerson.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Capsule()
                    .fill(Color.secondary.opacity(0.28))
                    .frame(width: 28, height: 3)
            }
            .frame(width: 138)
        }
        .buttonStyle(PeoplePressStyle())
        .accessibilityLabel("\(focusedPerson.name)，点击查看完整档案")
    }

    @ViewBuilder
    private func orbitNode(for placement: Placement) -> some View {
        let member = placement.item.member
        let size: CGFloat = placement.isInner ? 39 : 30
        VStack(spacing: 3) {
            AvatarView(
                url: member.avatarURL(baseURL: baseURL),
                name: member.name,
                size: size,
                assetName: member.person?.avatarAssetName ?? member.avatarAssetName
            )
            .overlay {
                Circle()
                    .stroke(Color(uiColor: .systemBackground), lineWidth: 2.5)
                    .overlay {
                        Circle()
                            .stroke(
                                tint(for: placement.item.colorIndex).opacity(placement.isInner ? 0.62 : 0.28),
                                lineWidth: placement.isInner ? 1.5 : 0.8
                            )
                    }
            }
            .shadow(color: .black.opacity(0.09), radius: placement.isInner ? 7 : 4, y: 2)

            Text(member.name)
                .font(.system(size: placement.isInner ? 9 : 8, weight: .semibold))
                .foregroundStyle(placement.isInner ? Color.primary : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
        }
        .frame(width: placement.isInner ? 68 : 58)
    }

    private func centerPoint(size: CGSize) -> CGPoint {
        CGPoint(x: size.width * 0.5, y: size.height * 0.44)
    }

    private func placements(size: CGSize, center: CGPoint) -> [Placement] {
        let innerItems = Array(orbitItems.prefix(innerCount))
        let outerItems = Array(orbitItems.dropFirst(innerCount))
        let innerRadiusX = min(size.width * 0.30, 115)
        let innerRadiusY = min(size.height * 0.22, 178)

        let inner = innerItems.enumerated().map { index, item in
            let angle = (-Double.pi / 2) + (2 * Double.pi * Double(index) / Double(max(innerItems.count, 1)))
            return Placement(
                item: item,
                point: CGPoint(
                    x: center.x + CGFloat(cos(angle)) * innerRadiusX,
                    y: center.y + CGFloat(sin(angle)) * innerRadiusY
                ),
                isInner: true
            )
        }

        let outerPoints: [CGPoint] = [
            CGPoint(x: 0.34, y: 0.14),
            CGPoint(x: 0.66, y: 0.14),
            CGPoint(x: 0.09, y: 0.34),
            CGPoint(x: 0.91, y: 0.34),
            CGPoint(x: 0.09, y: 0.63),
            CGPoint(x: 0.91, y: 0.63),
            CGPoint(x: 0.34, y: 0.75),
            CGPoint(x: 0.66, y: 0.75)
        ]
        let outer = outerItems.enumerated().map { index, item in
            let normalizedPoint = outerPoints[index % outerPoints.count]
            return Placement(
                item: item,
                point: CGPoint(
                    x: size.width * normalizedPoint.x,
                    y: size.height * normalizedPoint.y
                ),
                isInner: false
            )
        }
        return inner + outer
    }

    private func relationshipLabelPoint(from center: CGPoint, to point: CGPoint) -> CGPoint {
        CGPoint(
            x: center.x + (point.x - center.x) * 0.72,
            y: center.y + (point.y - center.y) * 0.72
        )
    }

    private func drawOrbitGuides(context: GraphicsContext, center: CGPoint, size: CGSize) {
        let rect = CGRect(
            x: center.x - min(size.width * 0.405, 154),
            y: center.y - min(size.height * 0.335, 258),
            width: min(size.width * 0.405, 154) * 2,
            height: min(size.height * 0.335, 258) * 2
        )
        context.stroke(
            Path(ellipseIn: rect),
            with: .color(Color.secondary.opacity(0.07)),
            style: StrokeStyle(lineWidth: 0.7, dash: [2, 7])
        )
    }

    private func drawConnections(
        context: GraphicsContext,
        center: CGPoint,
        placements: [Placement]
    ) {
        for placement in placements {
            var path = Path()
            path.move(to: center)
            let bend = placement.isInner ? CGFloat(8) : CGFloat(18)
            path.addQuadCurve(
                to: placement.point,
                control: CGPoint(
                    x: (center.x + placement.point.x) / 2 + bend,
                    y: (center.y + placement.point.y) / 2 - bend * 0.45
                )
            )
            context.stroke(
                path,
                with: .color(
                    tint(for: placement.item.colorIndex)
                        .opacity(placement.isInner ? 0.24 : 0.10)
                ),
                style: StrokeStyle(
                    lineWidth: placement.isInner ? 1.15 : 0.7,
                    dash: placement.isInner ? [] : [2, 5]
                )
            )
        }
    }

    private func tint(for index: Int) -> Color {
        let colors: [Color] = [
            Color(red: 0.18, green: 0.47, blue: 0.88),
            Color(red: 0.18, green: 0.61, blue: 0.48),
            Color(red: 0.88, green: 0.54, blue: 0.20),
            Color(red: 0.55, green: 0.39, blue: 0.82),
            Color(red: 0.19, green: 0.61, blue: 0.72),
            Color(red: 0.79, green: 0.35, blue: 0.49)
        ]
        return colors[index % colors.count]
    }
}

private struct PeopleClusterCanvas: View {
    let focusedPerson: SpecialPerson
    let clusters: [PeopleRelationshipCluster]
    let expandedClusterID: String?
    let selectedMemberID: String?
    let clusterPage: Int
    let baseURL: URL
    let onOpenCenter: () -> Void
    let onSelectCluster: (PeopleRelationshipCluster) -> Void
    let onSelectMember: (PeopleRelationshipMember) -> Void
    let onShowMoreMembers: () -> Void

    private let pageSize = 5

    private var expandedCluster: PeopleRelationshipCluster? {
        expandedClusterID.flatMap { id in clusters.first { $0.id == id } }
    }

    var body: some View {
        GeometryReader { proxy in
            let center = centerPoint(size: proxy.size)
            let clusterPoints = pointsForClusters(size: proxy.size, center: center)
            let visibleMembers = pagedMembers
            let memberPoints = pointsForMembers(count: visibleMembers.count, size: proxy.size)

            ZStack {
                Canvas { context, _ in
                    drawClusterLines(context: context, center: center, clusterPoints: clusterPoints)
                    if let expandedCluster,
                       let hub = clusterPoints[expandedCluster.id] {
                        drawMemberLines(context: context, hub: hub, memberPoints: memberPoints)
                    }
                }
                .accessibilityHidden(true)

                centerNode
                    .position(center)

                ForEach(Array(clusters.enumerated()), id: \.element.id) { index, cluster in
                    Button {
                        onSelectCluster(cluster)
                    } label: {
                        RelationshipClusterNode(
                            cluster: cluster,
                            tint: tint(for: index),
                            isExpanded: expandedClusterID == cluster.id
                        )
                    }
                    .buttonStyle(PeoplePressStyle())
                    .position(clusterPoints[cluster.id] ?? center)
                    .accessibilityLabel(
                        "\(cluster.title)，\(cluster.memberCount) 位关联人物，\(expandedClusterID == cluster.id ? "已展开" : "点击展开")"
                    )
                }

                if let expandedCluster {
                    ForEach(Array(visibleMembers.enumerated()), id: \.element.id) { index, member in
                        Button {
                            onSelectMember(member)
                        } label: {
                            RelationshipMemberNode(
                                member: member,
                                baseURL: baseURL,
                                showsRelationship: selectedMemberID == member.id
                            )
                        }
                        .buttonStyle(PeoplePressStyle())
                        .position(memberPoints[index])
                        .accessibilityLabel(
                            "\(member.name)，与\(focusedPerson.name)的关系：\(member.relationship)"
                        )
                        .accessibilityHint(
                            selectedMemberID == member.id && member.person != nil
                                ? "再次点击，以此人物为中心"
                                : "点击显示关系"
                        )
                    }

                    if expandedCluster.memberCount > pageSize {
                        Button(action: onShowMoreMembers) {
                            Text(moreButtonTitle(cluster: expandedCluster))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 9)
                                .frame(height: 28)
                                .background(Color.accentColor.opacity(0.09), in: Capsule())
                        }
                        .buttonStyle(PeoplePressStyle())
                        .position(moreButtonPoint(size: proxy.size))
                        .accessibilityHint("循环查看这一组的全部关联人物")
                    }
                }
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var centerNode: some View {
        Button(action: onOpenCenter) {
            VStack(spacing: 7) {
                AvatarView(
                    url: focusedPerson.avatarURL(baseURL: baseURL),
                    name: focusedPerson.name,
                    size: 92,
                    assetName: focusedPerson.avatarAssetName
                )
                .overlay {
                    Circle().stroke(Color.accentColor, lineWidth: 3)
                }
                Text(focusedPerson.name)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(focusedPerson.organizationName ?? focusedPerson.topic.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 150)
        }
        .buttonStyle(PeoplePressStyle())
        .accessibilityLabel("\(focusedPerson.name)，点击查看完整档案")
    }

    private var pagedMembers: [PeopleRelationshipMember] {
        guard let expandedCluster, !expandedCluster.members.isEmpty else { return [] }
        let pageCount = max(1, Int(ceil(Double(expandedCluster.memberCount) / Double(pageSize))))
        let normalizedPage = clusterPage % pageCount
        let start = normalizedPage * pageSize
        let end = min(start + pageSize, expandedCluster.memberCount)
        return Array(expandedCluster.members[start..<end])
    }

    private func centerPoint(size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width * (expandedCluster == nil ? 0.5 : 0.36),
            y: size.height * 0.49
        )
    }

    private func pointsForClusters(size: CGSize, center: CGPoint) -> [String: CGPoint] {
        guard !clusters.isEmpty else { return [:] }
        if let expandedCluster {
            var result: [String: CGPoint] = [
                expandedCluster.id: CGPoint(x: size.width * 0.64, y: size.height * 0.49)
            ]
            let remaining = clusters.filter { $0.id != expandedCluster.id }
            let normalizedPoints: [CGPoint] = [
                CGPoint(x: 0.28, y: 0.20),
                CGPoint(x: 0.14, y: 0.37),
                CGPoint(x: 0.16, y: 0.68),
                CGPoint(x: 0.38, y: 0.81),
                CGPoint(x: 0.52, y: 0.22)
            ]
            for (cluster, point) in zip(remaining, normalizedPoints) {
                result[cluster.id] = CGPoint(x: size.width * point.x, y: size.height * point.y)
            }
            return result
        }

        let radiusX = min(size.width * 0.34, 132)
        let radiusY = min(size.height * 0.31, 218)
        return Dictionary(uniqueKeysWithValues: clusters.enumerated().map { index, cluster in
            let angle = (-Double.pi / 2) + (2 * Double.pi * Double(index) / Double(clusters.count))
            return (
                cluster.id,
                CGPoint(
                    x: center.x + CGFloat(cos(angle)) * radiusX,
                    y: center.y + CGFloat(sin(angle)) * radiusY
                )
            )
        })
    }

    private func pointsForMembers(count: Int, size: CGSize) -> [CGPoint] {
        guard count > 0 else { return [] }
        let startY = size.height * 0.20
        let endY = size.height * 0.78
        if count == 1 {
            return [CGPoint(x: size.width * 0.84, y: size.height * 0.49)]
        }
        return (0..<count).map { index in
            let progress = CGFloat(index) / CGFloat(count - 1)
            let curve = sin(progress * .pi) * size.width * 0.035
            return CGPoint(
                x: size.width * 0.82 + curve,
                y: startY + (endY - startY) * progress
            )
        }
    }

    private func moreButtonPoint(size: CGSize) -> CGPoint {
        CGPoint(x: size.width * 0.82, y: size.height * 0.88)
    }

    private func moreButtonTitle(cluster: PeopleRelationshipCluster) -> String {
        let pageCount = max(1, Int(ceil(Double(cluster.memberCount) / Double(pageSize))))
        let nextPage = (clusterPage + 1) % pageCount
        if nextPage == 0 {
            return "回到前 \(min(pageSize, cluster.memberCount)) 人"
        }
        let nextStart = nextPage * pageSize
        return "还有 \(cluster.memberCount - nextStart) 人"
    }

    private func drawClusterLines(
        context: GraphicsContext,
        center: CGPoint,
        clusterPoints: [String: CGPoint]
    ) {
        for (index, cluster) in clusters.enumerated() {
            guard let point = clusterPoints[cluster.id] else { continue }
            var path = Path()
            path.move(to: center)
            let control = CGPoint(
                x: (center.x + point.x) / 2,
                y: (center.y + point.y) / 2 - 10
            )
            path.addQuadCurve(to: point, control: control)
            context.stroke(
                path,
                with: .color(tint(for: index).opacity(expandedClusterID == cluster.id ? 0.42 : 0.22)),
                style: StrokeStyle(lineWidth: expandedClusterID == cluster.id ? 2.2 : 1.2)
            )
        }
    }

    private func drawMemberLines(
        context: GraphicsContext,
        hub: CGPoint,
        memberPoints: [CGPoint]
    ) {
        for point in memberPoints {
            var path = Path()
            path.move(to: hub)
            path.addQuadCurve(
                to: point,
                control: CGPoint(x: (hub.x + point.x) / 2 + 8, y: (hub.y + point.y) / 2)
            )
            context.stroke(
                path,
                with: .color(Color.secondary.opacity(0.22)),
                style: StrokeStyle(lineWidth: 0.8, dash: [2.5, 3.5])
            )
        }
    }

    private func tint(for index: Int) -> Color {
        let colors: [Color] = [
            Color(red: 0.23, green: 0.48, blue: 0.84),
            Color(red: 0.32, green: 0.58, blue: 0.42),
            Color(red: 0.70, green: 0.48, blue: 0.22),
            Color(red: 0.46, green: 0.39, blue: 0.69),
            Color(red: 0.28, green: 0.57, blue: 0.62)
        ]
        return colors[index % colors.count]
    }
}

private struct RelationshipClusterNode: View {
    let cluster: PeopleRelationshipCluster
    let tint: Color
    let isExpanded: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(cluster.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(cluster.memberCount)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
        }
        .foregroundStyle(isExpanded ? Color.white : Color.primary)
        .frame(width: 72, height: 72)
        .background(isExpanded ? tint : tint.opacity(0.1), in: Circle())
        .overlay {
            Circle().stroke(tint.opacity(isExpanded ? 0 : 0.34), lineWidth: 1)
        }
    }
}

private struct RelationshipMemberNode: View {
    let member: PeopleRelationshipMember
    let baseURL: URL
    let showsRelationship: Bool

    var body: some View {
        VStack(spacing: 4) {
            AvatarView(
                url: member.avatarURL(baseURL: baseURL),
                name: member.name,
                size: 42,
                assetName: member.person?.avatarAssetName ?? member.avatarAssetName
            )
            .overlay {
                Circle().stroke(
                    showsRelationship ? Color.accentColor : Color(uiColor: .systemBackground),
                    lineWidth: showsRelationship ? 2 : 2.5
                )
            }
            Text(member.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            if showsRelationship {
                Text(member.relationship)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(Color.accentColor.opacity(0.09), in: Capsule())
            }
        }
        .frame(width: 76)
    }
}

private struct PeopleRelationshipExplorer: View {
    let topic: PeopleTopic
    let people: [SpecialPerson]
    let allPeople: [SpecialPerson]
    let baseURL: URL
    let latestPost: (SpecialPerson) -> Post?
    let loadLatestPost: (SpecialPerson) async -> Void
    let onOpenPerson: (SpecialPerson) -> Void
    let onRefresh: () async -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focusedPersonID: String?
    @State private var selectedOrganization: String?
    @State private var showsList = false
    @State private var searchText = ""

    private var focusedPerson: SpecialPerson? {
        focusedPersonID.flatMap { id in allPeople.first { $0.id == id } }
    }

    private var lenses: [PeopleRelationshipLens] {
        PeopleRelationshipPlanner.lenses(for: people)
    }

    private var visiblePeople: [SpecialPerson] {
        PeopleRelationshipPlanner.visiblePeople(
            topicPeople: people,
            allPeople: allPeople,
            focusedPersonID: focusedPersonID,
            organization: selectedOrganization
        )
    }

    private var filteredListPeople: [SpecialPerson] {
        let source = selectedOrganization.map { organization in
            people.filter { PeopleRelationshipPlanner.primaryOrganization(for: $0) == organization }
        } ?? people
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return source }
        return source.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
                ($0.organizationName?.localizedCaseInsensitiveContains(query) ?? false) ||
                $0.focusTags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header
                organizationPicker
                if showsList {
                    listContent
                } else {
                    graphContent
                    if let focusedPerson {
                        focusedPersonCard(focusedPerson)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .padding(.bottom, 112)
        }
        .scrollIndicators(.hidden)
        .refreshable { await onRefresh() }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--people-relations-list-preview") {
                showsList = true
            }
            if ProcessInfo.processInfo.arguments.contains("--people-relations-focus-preview"),
               focusedPersonID == nil {
                focusedPersonID = people.first(where: { !$0.relatedPeople.isEmpty })?.id ?? people.first?.id
            }
            #endif
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("关系探索")
                    .font(.system(size: 28, weight: .bold))
                Text(breadcrumb)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                withAnimation(animation) {
                    showsList.toggle()
                    if showsList { focusedPersonID = nil }
                }
            } label: {
                Label(showsList ? "关系" : "列表", systemImage: showsList ? "point.3.connected.trianglepath.dotted" : "list.bullet")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 13)
                    .frame(height: 36)
                    .background(Color.accentColor.opacity(0.11), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint(showsList ? "切换到关系图" : "切换到人物列表")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var breadcrumb: String {
        if let focusedPerson {
            return "\(topic.rawValue) › \(focusedPerson.name)"
        }
        if let selectedOrganization {
            return "\(topic.rawValue) › \(selectedOrganization)"
        }
        return "\(topic.rawValue) › 局部关系镜头"
    }

    private var organizationPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                organizationButton(title: "全部", organization: nil, count: people.count)
                ForEach(lenses) { lens in
                    organizationButton(
                        title: lens.title,
                        organization: lens.title,
                        count: lens.memberCount
                    )
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }

    private func organizationButton(title: String, organization: String?, count: Int) -> some View {
        let isSelected = selectedOrganization == organization
        return Button {
            withAnimation(animation) {
                selectedOrganization = organization
                focusedPersonID = nil
            }
        } label: {
            HStack(spacing: 5) {
                Text(title)
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.82) : Color.secondary)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var graphContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(focusedPerson == nil ? "点击人物，展开一层关系" : "再次点击中心人物，进入完整档案")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("最多 \(visiblePeople.count) 个节点")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)

            PeopleRelationshipCanvas(
                topic: topic,
                organization: selectedOrganization,
                focusedPerson: focusedPerson,
                people: visiblePeople,
                baseURL: baseURL,
                onSelect: selectPerson,
                onOpenFocusedPerson: {
                    if let focusedPerson { onOpenPerson(focusedPerson) }
                }
            )
            .frame(height: 410)
            .background(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.09), Color(uiColor: .secondarySystemBackground).opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.12), lineWidth: 1)
            }
            .padding(.horizontal, 16)
        }
    }

    private var listContent: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索人物、机构或领域", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
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
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            if filteredListPeople.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .padding(.top, 36)
            } else {
                ForEach(filteredListPeople) { person in
                    Button { onOpenPerson(person) } label: {
                        PersonActivityRow(person: person, latestPost: latestPost(person))
                    }
                    .buttonStyle(PeoplePressStyle())
                    .task { await loadLatestPost(person) }
                    if person.id != filteredListPeople.last?.id {
                        Divider().padding(.leading, 84)
                    }
                }
            }
        }
    }

    private func focusedPersonCard(_ person: SpecialPerson) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 13) {
                AvatarView(
                    url: person.avatarURL(baseURL: baseURL),
                    name: person.name,
                    size: 58,
                    assetName: person.avatarAssetName
                )
                VStack(alignment: .leading, spacing: 5) {
                    Text(person.name)
                        .font(.system(size: 21, weight: .bold))
                    Text(person.organizationName ?? person.topic.rawValue)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    withAnimation(animation) { focusedPersonID = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Color.secondary.opacity(0.11), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭人物摘要")
            }

            Text(person.summary)
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(.primary)
                .lineLimit(3)

            if !person.relatedPeople.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(person.relatedPeople.prefix(3)) { related in
                            Text("\(related.name) · \(related.relationship)")
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(Color.secondary.opacity(0.09), in: Capsule())
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            Button {
                onOpenPerson(person)
            } label: {
                HStack {
                    Text("查看完整档案")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func selectPerson(_ person: SpecialPerson) {
        if focusedPersonID == person.id {
            onOpenPerson(person)
            return
        }
        withAnimation(animation) {
            focusedPersonID = person.id
            selectedOrganization = nil
        }
    }

    private var animation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.32)
    }
}

private struct PeopleRelationshipCanvas: View {
    let topic: PeopleTopic
    let organization: String?
    let focusedPerson: SpecialPerson?
    let people: [SpecialPerson]
    let baseURL: URL
    let onSelect: (SpecialPerson) -> Void
    let onOpenFocusedPerson: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let points = people.indices.map { point(for: $0, count: people.count, size: proxy.size) }

            ZStack {
                Canvas { context, _ in
                    for point in points {
                        var path = Path()
                        path.move(to: center)
                        path.addLine(to: point)
                        context.stroke(
                            path,
                            with: .color(Color.accentColor.opacity(focusedPerson == nil ? 0.22 : 0.38)),
                            style: StrokeStyle(lineWidth: focusedPerson == nil ? 1 : 1.5, dash: focusedPerson == nil ? [4, 5] : [])
                        )
                    }
                }
                .accessibilityHidden(true)

                centerNode
                    .position(center)

                ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                    Button {
                        onSelect(person)
                    } label: {
                        VStack(spacing: 6) {
                            AvatarView(
                                url: person.avatarURL(baseURL: baseURL),
                                name: person.name,
                                size: focusedPerson == nil ? 56 : 52,
                                assetName: person.avatarAssetName
                            )
                            .overlay {
                                Circle()
                                    .stroke(Color(uiColor: .systemBackground), lineWidth: 3)
                            }
                            Text(person.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.thinMaterial, in: Capsule())
                            if let focusedPerson {
                                Text(PeopleRelationshipPlanner.relationshipLabel(from: focusedPerson, to: person))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.65)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(.thinMaterial, in: Capsule())
                            }
                        }
                        .frame(width: 92)
                    }
                    .buttonStyle(PeoplePressStyle())
                    .position(points[index])
                    .accessibilityLabel(nodeAccessibilityLabel(person))
                }
            }
        }
    }

    @ViewBuilder
    private var centerNode: some View {
        if let focusedPerson {
            Button(action: onOpenFocusedPerson) {
                VStack(spacing: 7) {
                    AvatarView(
                        url: focusedPerson.avatarURL(baseURL: baseURL),
                        name: focusedPerson.name,
                        size: 80,
                        assetName: focusedPerson.avatarAssetName
                    )
                    .overlay {
                        Circle().stroke(Color.accentColor, lineWidth: 4)
                    }
                    Text(focusedPerson.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .frame(width: 112)
            }
            .buttonStyle(PeoplePressStyle())
            .accessibilityLabel("\(focusedPerson.name)，已聚焦，再次点击查看完整档案")
        } else {
            VStack(spacing: 5) {
                Image(systemName: organization == nil ? "point.3.connected.trianglepath.dotted" : "building.2.fill")
                    .font(.system(size: 24, weight: .semibold))
                Text(organization ?? topic.rawValue)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text("\(people.count) 位人物")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(Color.accentColor)
            .frame(width: 104, height: 104)
            .background(.regularMaterial, in: Circle())
            .overlay { Circle().stroke(Color.accentColor.opacity(0.25), lineWidth: 1) }
            .accessibilityElement(children: .combine)
        }
    }

    private func point(for index: Int, count: Int, size: CGSize) -> CGPoint {
        guard count > 0 else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        let angle = (-Double.pi / 2) + (2 * Double.pi * Double(index) / Double(count))
        let radiusX = min(max(108, size.width * 0.34), 138)
        let radiusY = min(max(126, size.height * 0.34), 150)
        return CGPoint(
            x: size.width / 2 + CGFloat(cos(angle)) * radiusX,
            y: size.height / 2 + CGFloat(sin(angle)) * radiusY
        )
    }

    private func nodeAccessibilityLabel(_ person: SpecialPerson) -> String {
        guard let focusedPerson else { return "\(person.name)，点击查看关系" }
        return "\(person.name)，与\(focusedPerson.name)的关系：\(PeopleRelationshipPlanner.relationshipLabel(from: focusedPerson, to: person))"
    }
}

private struct PersonActivityRow: View {
    let person: SpecialPerson
    let latestPost: Post?

    private var activityText: String {
        guard let latestPost, !latestPost.needsXTranslation else { return person.summary }
        return latestPost.isBilibili ? latestPost.bilibiliListContent : latestPost.displayContent
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AvatarView(
                url: person.avatarURL(baseURL: ServerConfiguration.currentURL),
                name: person.name,
                size: 50,
                assetName: person.avatarAssetName
            )
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(person.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(latestPost?.formattedTime ?? person.relativeTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(person.organizationName ?? person.secondaryLabel ?? person.topic.rawValue)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(activityText)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

private struct HistoricalPeopleGallery: View {
    let people: [SpecialPerson]
    let onSelect: (SpecialPerson) -> Void

    private var featuredPerson: SpecialPerson { people[0] }

    private var keyMilestones: [(person: SpecialPerson, milestone: PersonMilestone)] {
        people.prefix(2).compactMap { person in
            let preferredYear: String? = switch person.userID {
            case "curated:mao-zedong": "1949"
            case "curated:deng-xiaoping": "1978"
            default: nil
            }
            let milestone = preferredYear.flatMap { year in
                person.milestones.first { $0.year == year }
            } ?? person.milestones.first
            return milestone.map { (person, $0) }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("历史人物")
                        .font(.system(size: 28, weight: .bold))
                    Text("影像、事件与时代")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)

                historicalHero(featuredPerson)

                sectionHeader("人物档案")
                    .padding(.top, 22)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(people) { person in
                        Button { onSelect(person) } label: {
                            HistoricalPersonCard(person: person)
                        }
                        .buttonStyle(PeoplePressStyle())
                    }
                }
                .padding(.horizontal, 20)

                if !keyMilestones.isEmpty {
                    sectionHeader("关键节点")
                        .padding(.top, 22)
                    HistoricalMilestoneStrip(items: keyMilestones)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 104)
        }
        .scrollIndicators(.hidden)
    }

    private func historicalHero(_ person: SpecialPerson) -> some View {
        Button { onSelect(person) } label: {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let photo = person.photos.first,
                       let url = photo.imageURL(baseURL: ServerConfiguration.currentURL) {
                        RemoteImage(url: url, height: 226, cornerRadius: 18, contentMode: .fill)
                    } else {
                        AvatarView(
                            url: person.avatarURL(baseURL: ServerConfiguration.currentURL),
                            name: person.name,
                            size: 350,
                            assetName: person.avatarAssetName,
                            cornerRadius: 18
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 226)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                LinearGradient(
                    colors: [.clear, .black.opacity(0.78)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    if let photo = person.photos.first {
                        Text([photo.date, photo.title].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                    }
                    Text(person.name)
                        .font(.system(size: 27, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(18)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PeoplePressStyle())
        .padding(.horizontal, 20)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .bold))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 11)
    }
}

private struct HistoricalPersonCard: View {
    let person: SpecialPerson

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AvatarView(
                url: person.avatarURL(baseURL: ServerConfiguration.currentURL),
                name: person.name,
                size: 180,
                assetName: person.avatarAssetName,
                cornerRadius: 18
            )
            .frame(maxWidth: .infinity)
            .frame(height: 224)
            .scaleEffect(1.04)

            LinearGradient(
                colors: [.clear, .black.opacity(0.86)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(person.name)
                    .font(.system(size: 20, weight: .bold))
                if let lifeYears = person.lifeYears {
                    Text(lifeYears)
                        .font(.system(size: 13, weight: .medium))
                }
                Text(person.roles.first?.title ?? person.summary)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .lineSpacing(2)
            }
            .foregroundStyle(.white)
            .padding(14)
        }
        .frame(height: 224)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct HistoricalMilestoneStrip: View {
    let items: [(person: SpecialPerson, milestone: PersonMilestone)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.milestone.year)
                        .font(.system(size: 25, weight: .bold, design: .serif))
                    Text(shortTitle(item.milestone.title))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(item.person.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)

                if index < items.count - 1 {
                    Divider()
                        .frame(height: 62)
                }
            }
        }
        .padding(.vertical, 14)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private func shortTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: "中华人民共和国成立", with: "新中国成立")
            .replacingOccurrences(of: "推动改革开放历史进程", with: "改革开放")
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

struct PersonDetailSheet: View {
    @Binding var selectedPerson: SpecialPerson?
    let people: [SpecialPerson]
    @Binding var notificationVideoID: Int64?
    let onClose: () -> Void
    @GestureState private var isHorizontalDragging = false
    @State private var incomingEdge: Edge = .trailing

    init(
        selectedPerson: Binding<SpecialPerson?>,
        people: [SpecialPerson],
        notificationVideoID: Binding<Int64?> = .constant(nil),
        onClose: @escaping () -> Void
    ) {
        _selectedPerson = selectedPerson
        self.people = people
        _notificationVideoID = notificationVideoID
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            if let person = selectedPerson {
                ZStack(alignment: .topTrailing) {
                    Color(uiColor: .systemBackground)
                        .ignoresSafeArea()

                    PersonDetailPage(
                        person: person,
                        showsNavigationChrome: false,
                        usesSheetLayout: true,
                        notificationVideoID: notificationVideoID,
                        onNotificationVideoOpened: { notificationVideoID = nil }
                    )
                    .id(person.id)
                    .transition(personTransition)
                    .disabled(isHorizontalDragging)

                    closeButton
                        .padding(.top, 12)
                        .padding(.trailing, 15)
                }
                .clipped()
                .contentShape(Rectangle())
                .simultaneousGesture(personSwitchGesture)
                .accessibilityHint("左右滑动切换人物，下滑关闭人物详情")
            }
        }
        .task(id: selectedPerson?.id) {
            guard let selectedPerson else { return }
            await PeopleImagePreheater.preheatDetail(
                for: selectedPerson,
                baseURL: ServerConfiguration.currentURL
            )
            await preheatAdjacentPeople(around: selectedPerson)
        }
    }

    private var personTransition: AnyTransition {
        let outgoingEdge: Edge = incomingEdge == .trailing ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: incomingEdge).combined(with: .opacity),
            removal: .move(edge: outgoingEdge).combined(with: .opacity)
        )
    }

    private var personSwitchGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .updating($isHorizontalDragging) { value, isDragging, _ in
                let horizontalDistance = value.translation.width
                let verticalDistance = value.translation.height
                guard abs(horizontalDistance) > abs(verticalDistance) * 1.15 else { return }
                isDragging = true
            }
            .onEnded(switchPerson)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary.opacity(0.72))
                .frame(width: 34, height: 34)
                .background(.regularMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.09), radius: 8, y: 3)
        }
        .buttonStyle(PeoplePressStyle())
        .accessibilityLabel("关闭人物详情")
    }

    private func switchPerson(_ value: DragGesture.Value) {
        let horizontalDistance = value.translation.width
        let verticalDistance = value.translation.height
        guard orderedPeople.count > 1,
              abs(horizontalDistance) >= 64,
              abs(horizontalDistance) > abs(verticalDistance) * 1.25,
              let currentPerson = selectedPerson,
              let currentIndex = orderedPeople.firstIndex(where: { $0.id == currentPerson.id }) else {
            return
        }

        let indexOffset = horizontalDistance < 0 ? 1 : -1
        let nextIndex = (currentIndex + indexOffset + orderedPeople.count) % orderedPeople.count
        incomingEdge = horizontalDistance < 0 ? .trailing : .leading
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.snappy(duration: 0.3)) {
            selectedPerson = orderedPeople[nextIndex]
        }
    }

    private var orderedPeople: [SpecialPerson] {
        people.sorted {
            let lhs = ($0.todayCount, $0.relatedPeople.count, $0.totalCount)
            let rhs = ($1.todayCount, $1.relatedPeople.count, $1.totalCount)
            if lhs.0 != rhs.0 { return lhs.0 > rhs.0 }
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            if lhs.2 != rhs.2 { return lhs.2 > rhs.2 }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func preheatAdjacentPeople(around person: SpecialPerson) async {
        guard orderedPeople.count > 1,
              let currentIndex = orderedPeople.firstIndex(where: { $0.id == person.id }) else {
            return
        }
        let previousIndex = (currentIndex - 1 + orderedPeople.count) % orderedPeople.count
        let nextIndex = (currentIndex + 1) % orderedPeople.count
        await withTaskGroup(of: Void.self) { group in
            for index in Set([previousIndex, nextIndex]) {
                let adjacentPerson = orderedPeople[index]
                group.addTask {
                    await PeopleImagePreheater.preheatDetail(
                        for: adjacentPerson,
                        baseURL: ServerConfiguration.currentURL
                    )
                }
            }
        }
    }
}

private enum PeopleImagePreheater {
    @MainActor
    static func preheatDetail(for person: SpecialPerson, baseURL: URL) async {
        let avatarURL = person.avatarAssetName == nil ? person.avatarURL(baseURL: baseURL) : nil
        _ = await ImageLoader.load(
            avatarURL,
            targetSize: CGSize(width: 66, height: 66)
        )

        let thumbnailSize = CGSize(width: UIScreen.main.bounds.width, height: 132)
        let photoURLs = person.photos.prefix(3).compactMap { $0.imageURL(baseURL: baseURL) }
        await withTaskGroup(of: Void.self) { group in
            for url in photoURLs {
                group.addTask {
                    _ = await ImageLoader.load(url, targetSize: thumbnailSize)
                }
            }
        }
    }
}

enum PersonWikipediaPresentation {
    static func entity(
        for person: SpecialPerson,
        account: PersonSocialAccount
    ) -> WikipediaEntity? {
        guard let url = account.profileURL,
              let host = url.host?.lowercased(),
              host == "wikipedia.org" || host.hasSuffix(".wikipedia.org") else {
            return nil
        }
        return WikipediaEntity(
            id: account.id,
            term: person.name,
            title: account.displayHandle,
            summary: person.summary,
            url: url
        )
    }
}

private struct PersonDetailPage: View {
    private static let articleSearchAnchor = "person-article-search"

    let person: SpecialPerson
    let showsNavigationChrome: Bool
    let usesSheetLayout: Bool
    let notificationVideoID: Int64?
    let onNotificationVideoOpened: () -> Void
    @ObservedObject private var pushNotifications = PersonPushNotificationManager.shared
    @State private var store = PersonDetailStore()
    @State private var section: PersonDetailSection
    @State private var ownContentSection = PersonOwnContentSection.posts
    @State private var relatedSection = PersonRelatedSection.videos
    @State private var selectedPost: Post?
    @State private var selectedVideo: PersonVideo?
    @State private var selectedArticle: PersonArticle?
    @State private var articleSearchText = ""
    @State private var articleSheetDetent: PresentationDetent = .large
    @FocusState private var articleSearchIsFocused: Bool
    @State private var selectedPhoto: PersonPhoto?
    @State private var presentedWikipediaEntity: WikipediaEntity?

    init(
        person: SpecialPerson,
        showsNavigationChrome: Bool = true,
        usesSheetLayout: Bool = false,
        notificationVideoID: Int64? = nil,
        onNotificationVideoOpened: @escaping () -> Void = {}
    ) {
        self.person = person
        self.showsNavigationChrome = showsNavigationChrome
        self.usesSheetLayout = usesSheetLayout
        self.notificationVideoID = notificationVideoID
        self.onNotificationVideoOpened = onNotificationVideoOpened
        _section = State(initialValue: person.topic == .history ? .profile : .posts)
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    personHeader
                    if !person.photos.isEmpty {
                        if usesSheetLayout {
                            CompactPersonPhotoGallery(photos: person.photos) { selectedPhoto = $0 }
                        } else {
                            PersonPhotoGallery(photos: person.photos) { selectedPhoto = $0 }
                        }
                    }
                    Section {
                        sectionContent
                    } header: {
                        sectionPicker
                    }
                }
            }
            .onChange(of: articleSearchIsFocused) { _, isFocused in
                guard isFocused else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(180))
                    withAnimation(.snappy(duration: 0.28)) {
                        reader.scrollTo(Self.articleSearchAnchor, anchor: .center)
                    }
                }
            }
        }
        .background(
            Color(
                uiColor: usesSheetLayout
                    ? .systemGroupedBackground
                    : .systemBackground
            )
        )
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(showsNavigationChrome ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            if showsNavigationChrome {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(person.socialAccounts) { account in
                            if let entity = PersonWikipediaPresentation.entity(
                                for: person,
                                account: account
                            ) {
                                Button {
                                    presentedWikipediaEntity = entity
                                } label: {
                                    Label("在应用内查看维基百科", systemImage: "book.pages")
                                }
                            } else if let url = account.profileURL {
                                Link(destination: url) {
                                    Label("在 \(account.platform) 中打开", systemImage: "arrow.up.right.square")
                                }
                            }
                        }
                        ForEach(person.socialAccounts) { account in
                            Button {
                                UIPasteboard.general.string = account.displayHandle
                            } label: {
                                Label("复制\(account.platform)账号", systemImage: "doc.on.doc")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("更多")
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $selectedVideo) { video in
            NavigationStack {
                PersonVideoDetailView(video: video)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationContentInteraction(.scrolls)
        }
        .sheet(item: $selectedArticle) { article in
            NavigationStack {
                PersonArticleDetailView(
                    articles: filteredArticles,
                    initialArticleID: article.id
                )
            }
            .presentationDetents([.medium, .large], selection: $articleSheetDetent)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationContentInteraction(.scrolls)
        }
        .onChange(of: selectedArticle) { _, article in
            if article != nil {
                articleSheetDetent = .large
            }
        }
        .sheet(item: $selectedPost) { post in
            NavigationStack {
                PostDetailView(post: post, presentedAsSheet: true)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationContentInteraction(.scrolls)
        }
        .sheet(item: $selectedPhoto) { photo in
            PersonPhotoViewer(photos: person.photos, initialPhotoID: photo.id)
        }
        .sheet(item: $presentedWikipediaEntity) { entity in
            WikipediaReaderView(entity: entity)
                .wikipediaReaderPresentation()
        }
        .task(id: person.id) {
            await store.load(person: person)
            openNotificationVideoIfNeeded()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--article-detail-preview"),
               let article = store.articles.dropFirst().first ?? store.articles.first {
                ownContentSection = .articles
                selectedArticle = article
            }
            if ProcessInfo.processInfo.arguments.contains("--video-detail-preview"),
               let video = store.relatedVideos.first {
                section = .discussions
                selectedVideo = video
            }
            #endif
        }
        .onChange(of: notificationVideoID) { _, _ in
            openNotificationVideoIfNeeded()
        }
        .task(id: articleSearchText.trimmingCharacters(in: .whitespacesAndNewlines)) {
            let query = articleSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled else { return }
            await store.searchArticles(personID: person.id, query: query)
        }
    }

    private func openNotificationVideoIfNeeded() {
        guard let notificationVideoID,
              let video = store.relatedVideos.first(where: { $0.id == notificationVideoID }) else {
            return
        }
        section = .discussions
        relatedSection = .videos
        selectedVideo = video
        onNotificationVideoOpened()
    }

    @ViewBuilder
    private var personHeader: some View {
        if usesSheetLayout {
            sheetPersonHeader
        } else {
            standardPersonHeader
        }
    }

    private var sheetPersonHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                AvatarView(
                    url: person.avatarURL(baseURL: ServerConfiguration.currentURL),
                    name: person.name,
                    size: 72,
                    assetName: person.avatarAssetName
                )
                .overlay {
                    Circle()
                        .stroke(Color(uiColor: .systemBackground), lineWidth: 3)
                }
                .shadow(color: Color.accentColor.opacity(0.14), radius: 12, y: 5)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Text(person.name)
                            .font(.system(size: 23, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        if person.hasOwnPostSource {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.accentColor)
                        }
                    }

                    Text(personOrganizationLine)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 7) {
                        Text(person.topic.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 9)
                            .frame(height: 25)
                            .background(Color.accentColor.opacity(0.11), in: Capsule())

                        if let account = person.socialAccounts.first {
                            socialAccountDestination(account) {
                                HStack(spacing: 3) {
                                    Image(systemName: "at")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text(account.displayHandle.replacingOccurrences(of: "@", with: ""))
                                        .lineLimit(1)
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("在\(account.platform)中打开\(account.displayHandle)")
                        }
                    }
                }

                Spacer(minLength: 2)

                compactNotificationControl
                    .padding(.trailing, 38)
            }

            if !person.displayFocusTags.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(person.displayFocusTags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary.opacity(0.78))
                                .padding(.horizontal, 10)
                                .frame(height: 27)
                                .background(.thinMaterial, in: Capsule())
                                .overlay {
                                    Capsule()
                                        .stroke(Color.primary.opacity(0.055), lineWidth: 0.5)
                                }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 30)
        .padding(.bottom, 14)
        .background(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    Color(uiColor: .systemBackground),
                    Color.accentColor.opacity(0.055),
                    Color(uiColor: .systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var standardPersonHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                AvatarView(
                    url: person.avatarURL(baseURL: ServerConfiguration.currentURL),
                    name: person.name,
                    size: 82,
                    assetName: person.avatarAssetName
                )
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(person.name)
                            .font(.system(size: 24, weight: .bold))
                        if person.hasOwnPostSource {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(personOrganizationLine)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text("\(person.topic.rawValue) · \(person.displayFocusTags.first ?? "人物")")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    if let account = person.socialAccounts.first {
                        socialAccountDestination(account) {
                            HStack(spacing: 4) {
                                Text("\(account.platform) · \(account.displayHandle)")
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("在\(account.platform)中打开\(account.displayHandle)")
                    }
                }
            }

            HStack(spacing: 9) {
                ForEach(person.displayFocusTags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                    .background(Color.secondary.opacity(0.09), in: Capsule())
                }
            }

            personNotificationControl
        }
        .padding(.horizontal, 20)
        .padding(.top, 5)
        .padding(.bottom, 18)
    }

    private var personOrganizationLine: String {
        person.organizationName ?? (person.hasXSource ? "X 来源" : "人物资料")
    }

    @ViewBuilder
    private func socialAccountDestination<Label: View>(
        _ account: PersonSocialAccount,
        @ViewBuilder label: () -> Label
    ) -> some View {
        if let entity = PersonWikipediaPresentation.entity(for: person, account: account) {
            Button {
                presentedWikipediaEntity = entity
            } label: {
                label()
            }
        } else if let url = account.profileURL {
            Link(destination: url) {
                label()
            }
        }
    }

    private var personNotificationControl: some View {
        let isEnabled = pushNotifications.isEnabled(for: person.id)
        return Button {
            Task {
                await pushNotifications.setEnabled(!isEnabled, for: person.id)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isEnabled ? "bell.fill" : "bell")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        isEnabled ? Color.accentColor : Color.secondary
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(isEnabled ? "已开启本机提醒" : "开启本机提醒")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(pushNotifications.errorMessage ?? "本人动态或新视频访谈发布时通知")
                        .font(.system(size: 11.5))
                        .foregroundStyle(
                            pushNotifications.errorMessage == nil ? Color.secondary : Color.red
                        )
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if pushNotifications.isUpdating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.075), in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .disabled(pushNotifications.isUpdating)
        .accessibilityLabel(
            isEnabled ? "关闭\(person.name)本机提醒" : "开启\(person.name)本机提醒"
        )
    }

    private var compactNotificationControl: some View {
        let isEnabled = pushNotifications.isEnabled(for: person.id)
        return Button {
            Task {
                await pushNotifications.setEnabled(!isEnabled, for: person.id)
            }
        } label: {
            Group {
                if pushNotifications.isUpdating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: isEnabled ? "bell.fill" : "bell")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .foregroundStyle(
                pushNotifications.errorMessage == nil
                    ? (isEnabled ? Color.accentColor : Color.secondary)
                    : Color.red
            )
            .frame(width: 36, height: 36)
            .background(
                (isEnabled ? Color.accentColor : Color.secondary).opacity(0.1),
                in: Circle()
            )
            .overlay {
                Circle()
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
        }
        .buttonStyle(PeoplePressStyle())
        .disabled(pushNotifications.isUpdating)
        .accessibilityLabel(
            isEnabled ? "关闭\(person.name)本机提醒" : "开启\(person.name)本机提醒"
        )
        .accessibilityHint("本人动态或新视频访谈发布时通知")
    }

    private var sectionPicker: some View {
        HStack(spacing: 0) {
            ForEach(detailSections) { item in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { section = item }
                } label: {
                    VStack(spacing: 11) {
                        Text(sectionTitle(item))
                            .font(.system(size: 16, weight: section == item ? .semibold : .regular))
                            .foregroundStyle(section == item ? Color.accentColor : Color.secondary)
                        Capsule().fill(section == item ? Color.accentColor : Color.clear).frame(width: 42, height: 3)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .bottom) { Divider() }
        .padding(.top, usesSheetLayout ? 18 : 0)
        .background(.regularMaterial)
    }

    private var detailSections: [PersonDetailSection] {
        person.topic == .history ? [.profile, .discussions] : PersonDetailSection.allCases
    }

    private func sectionTitle(_ item: PersonDetailSection) -> String {
        if person.topic == .history, item == .profile { return "生平" }
        return item.title
    }

    @ViewBuilder
    private var sectionContent: some View {
        if section == .profile {
            PersonProfileView(person: person, usesCardLayout: usesSheetLayout) {
                presentedWikipediaEntity = $0
            }
        } else if section == .discussions {
            relatedContent
        } else if hasArticleSection {
            ownContent
        } else {
            ownPostsContent
        }
    }

    private var hasArticleSection: Bool {
        !store.articles.isEmpty
    }

    private var ownContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("本人内容", selection: $ownContentSection) {
                ForEach(PersonOwnContentSection.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            if ownContentSection == .articles {
                articlesContent
            } else {
                ownPostsContent
            }
        }
    }

    @ViewBuilder
    private var ownPostsContent: some View {
        if store.isLoadingOwnPosts {
            ProgressView("正在载入他的动态…")
                .frame(maxWidth: .infinity).padding(.top, 70)
        } else if let error = store.ownPostsError {
            ContentUnavailableView("载入失败", systemImage: "wifi.exclamationmark", description: Text(error))
                .padding(.top, 36)
        } else if store.ownPosts.isEmpty {
            ContentUnavailableView(
                "暂无本人动态",
                systemImage: "bubble.left",
                description: Text("内容库里还没有收录他本人发布的帖子")
            )
            .padding(.top, 36)
        } else {
            ForEach(store.ownPosts) { post in
                let displayPost = store.postForDisplay(post)
                PersonPostTimelineRow(post: displayPost, compact: false) { selectedPost = displayPost }
                    .task { await store.translateXPostIfNeeded(post) }
                    .task { await store.loadMoreOwnPostsIfNeeded(current: post, person: person) }
            }
            ownPostsPaginationStatus
        }
    }

    @ViewBuilder
    private var articlesContent: some View {
        if store.isLoadingArticles {
            ProgressView("正在载入文章…")
                .frame(maxWidth: .infinity)
                .padding(.top, 54)
        } else if let error = store.articlesError, store.articles.isEmpty {
            ContentUnavailableView("载入失败", systemImage: "wifi.exclamationmark", description: Text(error))
                .padding(.top, 30)
        } else if store.articles.isEmpty {
            ContentUnavailableView(
                "暂无文章",
                systemImage: "doc.text",
                description: Text("内容库里暂时没有收录这位人物的文章")
            )
            .padding(.top, 30)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索文章文字", text: $articleSearchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($articleSearchIsFocused)
                        .submitLabel(.search)
                        .onSubmit {
                            articleSearchIsFocused = false
                        }
                    if !articleSearchText.isEmpty {
                        Button {
                            articleSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除文章搜索")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .id(Self.articleSearchAnchor)
                .contentShape(Rectangle())
                .onTapGesture {
                    articleSearchIsFocused = true
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(articleSearchStatus)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Label("最新", systemImage: "chevron.down")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 14)

                if filteredArticles.isEmpty && store.isSearchingArticles {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在搜索文章正文…")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 42)
                } else if let error = store.articleSearchError {
                    ContentUnavailableView(
                        "搜索失败",
                        systemImage: "wifi.exclamationmark",
                        description: Text(error)
                    )
                    .padding(.vertical, 28)
                } else if filteredArticles.isEmpty {
                    ContentUnavailableView(
                        "没有找到相关文章",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("没有包含“\(articleSearchText)”的文章，试试其他关键词")
                    )
                    .padding(.vertical, 32)
                } else {
                    ForEach(Array(filteredArticles.enumerated()), id: \.element.id) { index, article in
                        PersonArticleRow(
                            article: article,
                            featured: articleSearchText.isEmpty && index == 0,
                            portraitURL: person.avatarURL(baseURL: ServerConfiguration.currentURL),
                            portraitAssetName: person.avatarAssetName,
                            personName: person.name
                        ) {
                            selectedArticle = article
                        }

                        if index < filteredArticles.count - 1 {
                            Divider()
                                .padding(.leading, 20)
                        }
                    }
                }
            }
            .padding(.bottom, 28)
        }
    }

    private var filteredArticles: [PersonArticle] {
        let query = articleSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.articles }
        return store.articleSearchResults ?? []
    }

    private var articleSearchStatus: String {
        guard !articleSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "文章 \(store.articles.count)"
        }
        if store.isSearchingArticles {
            return "正在搜索标题、摘要和正文…"
        }
        return "找到 \(filteredArticles.count) 篇"
    }

    private var relatedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            relatedSectionPicker
                .zIndex(1)

            Group {
                switch relatedSection {
                case .videos:
                    if store.isLoadingRelatedVideos {
                        ProgressView("正在载入相关视频…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 54)
                    } else if let error = store.relatedVideosError, store.relatedVideos.isEmpty {
                        ContentUnavailableView(
                            "载入失败",
                            systemImage: "wifi.exclamationmark",
                            description: Text(error)
                        )
                        .padding(.top, 30)
                    } else if store.relatedVideos.isEmpty {
                        ContentUnavailableView(
                            "暂无相关视频",
                            systemImage: "video",
                            description: Text("内容库里暂时没有收录这位人物的相关视频")
                        )
                        .padding(.top, 30)
                    } else {
                        ForEach(store.relatedVideos) { video in
                            PersonVideoCard(video: video) { selectedVideo = video }
                            Divider().padding(.leading, 20)
                        }
                    }
                case .posts:
                    if store.isLoadingDiscussions {
                        ProgressView("正在查找相关动态…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 54)
                    } else if let error = store.discussionsError, store.discussions.isEmpty {
                        ContentUnavailableView(
                            "载入失败",
                            systemImage: "wifi.exclamationmark",
                            description: Text(error)
                        )
                        .padding(.top, 30)
                    } else if store.discussions.isEmpty {
                        ContentUnavailableView(
                            "暂无相关动态",
                            systemImage: "bubble.left.and.bubble.right",
                            description: Text("内容库里暂时没有提到这位人物的动态")
                        )
                        .padding(.top, 30)
                    } else {
                        discussionContent(store.discussions)
                    }
                }
            }
            .padding(.top, 24)
            .zIndex(0)
        }
    }

    private var relatedSectionPicker: some View {
        Picker("相关内容", selection: $relatedSection) {
            ForEach(PersonRelatedSection.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: relatedSection) { _, newValue in
            if newValue == .posts {
                selectedVideo = nil
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(uiColor: .systemBackground))
    }

    @ViewBuilder
    private var ownPostsPaginationStatus: some View {
        if store.isLoadingMoreOwnPosts {
            ProgressView("正在载入更多动态…")
                .frame(maxWidth: .infinity)
                .padding(20)
        } else if store.ownPostsLoadMoreError != nil, let last = store.ownPosts.last {
            Button("加载失败，点按重试") {
                Task { await store.loadMoreOwnPostsIfNeeded(current: last, person: person) }
            }
            .font(.footnote)
            .frame(maxWidth: .infinity)
            .padding(20)
        } else if !store.canLoadMoreOwnPosts, !store.ownPosts.isEmpty {
            Text("已显示全部动态")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(20)
        }
    }

    private func discussionContent(_ posts: [Post]) -> some View {
        let today = posts.filter(\.isRecentDiscussion)
        let earlier = posts.filter { !$0.isRecentDiscussion }
        return VStack(alignment: .leading, spacing: 0) {
            if !today.isEmpty {
                discussionGroup(title: "今天", countLabel: "\(posts.count) 条相关讨论", posts: today)
            }
            if !earlier.isEmpty {
                discussionGroup(title: "本周", posts: earlier)
            }
        }
    }

    private func discussionGroup(title: String, countLabel: String? = nil, posts: [Post]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(title).font(.system(size: 20, weight: .bold))
                if let countLabel {
                    Text(countLabel).font(.system(size: 14)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20).padding(.top, 15).padding(.bottom, 7)
            ForEach(posts) { post in
                let displayPost = store.postForDisplay(post)
                PersonRelatedPostRow(post: displayPost) { selectedPost = displayPost }
                    .task { await store.translateXPostIfNeeded(post) }
            }
        }
    }
}

private struct PersonPhotoGallery: View {
    let photos: [PersonPhoto]
    let onSelect: (PersonPhoto) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("人物影像")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Text("\(photos.count) 张")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(photos) { photo in
                        Button { onSelect(photo) } label: {
                            PersonPhotoCard(photo: photo)
                        }
                        .buttonStyle(PeoplePressStyle())
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, 2)
        .padding(.bottom, 20)
    }
}

private struct CompactPersonPhotoGallery: View {
    let photos: [PersonPhoto]
    let onSelect: (PersonPhoto) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("人物影像")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Text("\(photos.count) 张")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(photos) { photo in
                        Button {
                            onSelect(photo)
                        } label: {
                            Group {
                                if let url = photo.imageURL(baseURL: ServerConfiguration.currentURL) {
                                    RemoteImage(
                                        url: url,
                                        height: 96,
                                        cornerRadius: 13,
                                        contentMode: .fill
                                    )
                                } else {
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .fill(Color.secondary.opacity(0.1))
                                        .overlay {
                                            Image(systemName: "photo")
                                                .foregroundStyle(.secondary)
                                        }
                                }
                            }
                            .frame(width: 154, height: 96)
                            .background(
                                Color(uiColor: .secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                        .buttonStyle(PeoplePressStyle())
                        .accessibilityLabel(photo.title)
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, 6)
        .padding(.bottom, 16)
        .background(Color(uiColor: .systemBackground))
    }
}

private struct PersonPhotoCard: View {
    let photo: PersonPhoto

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Group {
                if let url = photo.imageURL(baseURL: ServerConfiguration.currentURL) {
                    RemoteImage(
                        url: url,
                        height: 132,
                        cornerRadius: 14,
                        contentMode: .fit
                    )
                    .background(
                        Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.secondary.opacity(0.1))
                        .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
                }
            }
            .frame(width: 210, height: 132)
            .clipped()

            Text(photo.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text([photo.date, photo.source].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 210, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct PersonPhotoViewer: View {
    let photos: [PersonPhoto]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhotoID: PersonPhoto.ID

    init(photos: [PersonPhoto], initialPhotoID: PersonPhoto.ID) {
        self.photos = photos
        _selectedPhotoID = State(initialValue: initialPhotoID)
    }

    private var selectedIndex: Int {
        photos.firstIndex { $0.id == selectedPhotoID } ?? 0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $selectedPhotoID) {
                    ForEach(photos) { photo in
                        PersonPhotoPage(photo: photo)
                            .tag(photo.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                if photos.count > 1 {
                    HStack(spacing: 7) {
                        ForEach(photos) { photo in
                            Capsule()
                                .fill(photo.id == selectedPhotoID ? Color.accentColor : Color.secondary.opacity(0.25))
                                .frame(width: photo.id == selectedPhotoID ? 18 : 7, height: 7)
                                .animation(.snappy(duration: 0.2), value: selectedPhotoID)
                        }
                    }
                    .padding(.vertical, 12)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("第 \(selectedIndex + 1) 张，共 \(photos.count) 张")
                }
            }
            .navigationTitle(photos.count > 1 ? "人物影像 \(selectedIndex + 1)/\(photos.count)" : "人物影像")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct PersonPhotoPage: View {
    let photo: PersonPhoto

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let url = photo.imageURL(baseURL: ServerConfiguration.currentURL) {
                    RemoteImage(url: url, height: 430, cornerRadius: 0, contentMode: .fit)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(photo.title)
                        .font(.title2.bold())
                    if let caption = photo.caption {
                        Text(caption)
                            .font(.body)
                            .lineSpacing(4)
                    }
                    Text([photo.date, photo.author, photo.license].compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let sourceURL = photo.sourceURL {
                        Link(destination: sourceURL) {
                            Label("查看来源：\(photo.source)", systemImage: "arrow.up.right.square")
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
        }
    }
}

private struct PersonRelatedPostRow: View {
    let post: Post
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                AvatarView(
                    url: post.avatarURL,
                    name: post.authorName,
                    size: 42
                )

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(post.authorName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let handle = post.authorHandle {
                            Text(handle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Text(post.formattedTime ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if post.needsXTranslation {
                        HStack(spacing: 7) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在翻译为中文…")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 42, alignment: .leading)
                    } else {
                        Text(post.displayContent)
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                            .lineSpacing(3)
                            .lineLimit(6)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(post.needsXTranslation)
        .accessibilityLabel("\(post.authorName)，\(post.needsXTranslation ? "正在翻译为中文" : post.displayContent)")

        Divider()
            .padding(.leading, 74)
    }
}

private struct PersonVideoCard: View {
    let video: PersonVideo
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 9) {
            ZStack {
                if let coverURL = video.coverURL {
                    RemoteImage(url: coverURL, height: 190, cornerRadius: 12)
                }
                Image(systemName: "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(.black.opacity(0.68), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 2))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 190)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if !video.durationLabel.isEmpty {
                    Text(video.durationLabel)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 5))
                        .padding(8)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Text(video.channelName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 5))
                    .padding(8)
            }

            Text(video.displayTitle)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(2)
                .lineSpacing(2)

            HStack(spacing: 8) {
                Text(video.videoType == "speech" ? "演讲" : video.videoType == "podcast" ? "播客" : "访谈")
                Text("·")
                Text(video.channelName)
                if let date = video.publishedDateLabel {
                    Text("·")
                    Text(date)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

private struct PersonVideoDetailView: View {
    let video: PersonVideo
    @State private var cues: [PersonVideoSubtitleCue] = []
    @State private var subtitleStatus = "loading"
    @State private var subtitleError: String?
    @State private var currentMS: Int64 = 0
    @State private var isFullscreen = false
    @State private var isPlaying = false
    @State private var playbackFailed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            player(instanceID: "detail-inline")
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(Color.black)
                .clipped()
            .background(Color(uiColor: .systemBackground))

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(video.displayTitle)
                            .font(.system(size: 22, weight: .bold))
                            .lineSpacing(3)
                        Text([video.channelName, video.publishedDateLabel, video.durationLabel]
                            .compactMap { $0 }
                            .filter { !$0.isEmpty }
                            .joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let description = video.description, !description.isEmpty {
                            Text(description)
                                .font(.system(size: 15))
                                .lineSpacing(4)
                                .foregroundStyle(.secondary)
                                .lineLimit(5)
                        }
                    }
                    .padding(.horizontal, 18)

                    Text("中文字幕")
                        .font(.system(size: 20, weight: .bold))
                        .padding(.horizontal, 18)

                    if isSubtitlePending {
                        ProgressView(subtitleStatus == "loading" ? "正在载入字幕…" : "首次提取约需 10 秒…")
                            .padding(.horizontal, 18)
                    } else if let subtitleError {
                        ContentUnavailableView(
                            "字幕载入失败",
                            systemImage: "captions.bubble",
                            description: Text(subtitleError)
                        )
                        .padding(.horizontal, 18)
                    } else if cues.isEmpty {
                        ContentUnavailableView("暂无可用字幕", systemImage: "captions.bubble")
                            .padding(.horizontal, 18)
                    } else if let activeCue {
                        Section {
                            subtitleRows(excluding: activeCue.id)
                        } header: {
                            currentSubtitleCard(activeCue)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                                .background(Color(uiColor: .systemBackground))
                        }
                    } else {
                        subtitleRows(excluding: nil)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("视频详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("关闭视频详情")
            }
        }
        .task(id: video.id) { await loadSubtitles() }
        .fullScreenCover(isPresented: $isFullscreen) {
            ZStack {
                Color.black.ignoresSafeArea()
                player(instanceID: "detail-full", showsFullscreenButton: false)
                    .ignoresSafeArea()
                if let cue = activeCue {
                    Text(cue.text)
                        .font(.system(size: 22, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 34)
                        .padding(.bottom, 34)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                Button {
                    YouTubeWarmPlayerPool.shared.pause(
                        videoID: video.platformVideoID,
                        instanceID: "detail-full",
                        options: .customSubtitles
                    )
                    AppOrientationController.shared.setVideoFullscreen(false)
                    isFullscreen = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            .onAppear { AppOrientationController.shared.setVideoFullscreen(true) }
            .onDisappear { AppOrientationController.shared.setVideoFullscreen(false) }
        }
    }

    private func player(instanceID: String, showsFullscreenButton: Bool = true) -> some View {
        ZStack(alignment: .topTrailing) {
            YouTubeEmbeddedPlayer(
                videoID: video.platformVideoID,
                instanceID: instanceID,
                options: .customSubtitles,
                onPlaying: {
                    isPlaying = true
                    playbackFailed = false
                },
                onFailed: { playbackFailed = true },
                onTime: { seconds in
                    let isFullPlayer = instanceID == "detail-full"
                    guard isFullPlayer == isFullscreen else { return }
                    updatePlaybackTime(seconds)
                }
            )
            if !isPlaying {
                videoPoster(instanceID: instanceID)
            }
            if showsFullscreenButton {
                Button {
                    YouTubeWarmPlayerPool.shared.pause(
                        videoID: video.platformVideoID,
                        instanceID: "detail-inline",
                        options: .customSubtitles
                    )
                    AppOrientationController.shared.setVideoFullscreen(true)
                    isFullscreen = true
                    YouTubeWarmPlayerPool.shared.startPlayback(
                        videoID: video.platformVideoID,
                        instanceID: "detail-full",
                        options: .customSubtitles
                    )
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.62), in: Circle())
                }
                .accessibilityLabel("横屏全屏播放")
                .padding(10)
            }
        }
    }

    private func videoPoster(instanceID: String) -> some View {
        ZStack {
            AsyncImage(url: video.coverURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.black
                }
            }
            LinearGradient(
                colors: [.black.opacity(0.08), .black.opacity(0.42)],
                startPoint: .top,
                endPoint: .bottom
            )
            Button {
                playbackFailed = false
                YouTubeWarmPlayerPool.shared.startPlayback(
                    videoID: video.platformVideoID,
                    instanceID: instanceID,
                    options: .customSubtitles
                )
            } label: {
                Image(systemName: playbackFailed ? "arrow.clockwise" : "play.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(.black.opacity(0.68), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playbackFailed ? "重新加载视频" : "播放视频")
        }
        .clipped()
    }

    @ViewBuilder
    private func subtitleRows(excluding cueID: PersonVideoSubtitleCue.ID?) -> some View {
        ForEach(cues.filter { $0.id != cueID }) { cue in
            Button {
                seek(to: cue)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(timeLabel(for: cue.startMS))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 46, alignment: .leading)
                    Text(cue.text)
                        .font(.system(size: 16))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("跳转到 \(timeLabel(for: cue.startMS))，\(cue.text)")
            .padding(.horizontal, 18)
            Divider()
                .padding(.horizontal, 18)
        }
    }

    private func currentSubtitleCard(_ cue: PersonVideoSubtitleCue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                Text("正在播放 · \(timeLabel(for: cue.startMS))")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Text(cue.text)
                .font(.system(size: 16, weight: .medium))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在播放，\(timeLabel(for: cue.startMS))，\(cue.text)")
    }

    private var activeCue: PersonVideoSubtitleCue? {
        cue(at: currentMS)
    }

    private var isSubtitlePending: Bool {
        ["loading", "pending", "processing", "extracting", "queued"].contains(subtitleStatus)
    }

    private func cue(at timestamp: Int64) -> PersonVideoSubtitleCue? {
        guard !cues.isEmpty else { return nil }
        var lower = 0
        var upper = cues.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if cues[middle].startMS <= timestamp {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard lower > 0 else { return nil }
        let cue = cues[lower - 1]
        return timestamp < cue.endMS ? cue : nil
    }

    private func updatePlaybackTime(_ seconds: Double) {
        let nextMS = Int64(seconds * 1_000)
        guard cue(at: nextMS)?.id != activeCue?.id else { return }
        currentMS = nextMS
    }

    private func seek(to cue: PersonVideoSubtitleCue) {
        currentMS = cue.startMS
        YouTubeWarmPlayerPool.shared.seek(
            videoID: video.platformVideoID,
            instanceID: "detail-inline",
            options: .customSubtitles,
            seconds: Double(cue.startMS) / 1_000
        )
    }

    private func timeLabel(for milliseconds: Int64) -> String {
        let totalSeconds = max(0, milliseconds / 1_000)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    private func loadSubtitles() async {
        subtitleStatus = "loading"
        subtitleError = nil
        for attempt in 0..<5 {
            do {
                let payload = try await PeopleService().subtitles(videoID: video.id)
                guard !Task.isCancelled else { return }
                cues = payload.cues
                subtitleStatus = payload.status
                if !payload.cues.isEmpty || payload.status == "ready" {
                    return
                }
                guard attempt < 4 else { return }
                try await Task.sleep(for: .seconds(2))
            } catch is CancellationError {
                return
            } catch {
                subtitleStatus = "failed"
                subtitleError = error.localizedDescription
                return
            }
        }
    }
}

private enum PersonDetailSection: String, CaseIterable, Identifiable {
    case posts
    case discussions
    case profile
    var id: Self { self }
    var title: String {
        switch self {
        case .posts: "动态"
        case .discussions: "相关"
        case .profile: "简介"
        }
    }
}

private enum PersonOwnContentSection: String, CaseIterable, Identifiable {
    case posts
    case articles

    var id: Self { self }
    var title: String {
        switch self {
        case .posts: "动态"
        case .articles: "文章"
        }
    }
}

private enum PersonRelatedSection: String, CaseIterable, Identifiable {
    case videos
    case posts

    var id: Self { self }
    var title: String {
        switch self {
        case .videos: "视频"
        case .posts: "动态"
        }
    }
}

private struct PersonArticleRow: View {
    let article: PersonArticle
    let featured: Bool
    let portraitURL: URL?
    let portraitAssetName: String?
    let personName: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(listTitle)
                        .font(.system(size: featured ? 20 : 18, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineSpacing(2)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if !article.displaySummary.isEmpty {
                        Text(article.displaySummary)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.primary.opacity(0.72))
                            .lineSpacing(3)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    Text(metadataLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if featured {
                    AvatarView(
                        url: portraitURL,
                        name: personName,
                        size: 84,
                        assetName: portraitAssetName
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, featured ? 18 : 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("在应用内打开中文文章")
    }

    private var metadataLabel: String {
        [
            article.sourceName,
            article.publishedDateLabel,
            article.readingMinutes > 0 ? "\(article.readingMinutes) 分钟" : nil
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private var listTitle: String {
        let title = article.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title == "-" || title.isEmpty ? "\(personName) 最新文章" : title
    }
}

private struct PersonArticleDetailView: View {
    let articles: [PersonArticle]
    let initialArticleID: PersonArticle.ID
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var loadedArticle: PersonArticle?
    @State private var errorMessage: String?
    @State private var horizontalOffset: CGFloat = 0

    init(articles: [PersonArticle], initialArticleID: PersonArticle.ID) {
        self.articles = articles
        self.initialArticleID = initialArticleID
        _currentIndex = State(
            initialValue: articles.firstIndex { $0.id == initialArticleID } ?? 0
        )
    }

    private var article: PersonArticle {
        guard articles.indices.contains(currentIndex) else {
            return articles.first!
        }
        return articles[currentIndex]
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if canAdvance {
                Color.accentColor
                    .opacity(0.72)
                    .frame(width: 5)
                    .accessibilityHidden(true)
            }

            Group {
                if let loadedArticle {
                    articleBody(loadedArticle)
                } else if let errorMessage {
                    failureView(errorMessage)
                } else {
                    loadingView
                }
            }
            .offset(x: horizontalOffset)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Label("收起", systemImage: "chevron.down")
                }
                .accessibilityHint("收起文章阅读弹窗")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let url = article.canonicalURL {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Button { openURL(url) } label: {
                        Image(systemName: "safari")
                    }
                }
            }
        }
        .simultaneousGesture(pageGesture)
        .task(id: article.id) {
            loadedArticle = nil
            errorMessage = nil
            await load()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在载入中文正文")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text("中文正文暂时无法载入")
                .font(.system(size: 20, weight: .bold))
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重新加载") {
                Task { await load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func articleBody(_ article: PersonArticle) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(article.sourceName.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(Color.accentColor)

                    Text(displayTitle(for: article))
                        .font(.system(size: 32, weight: .bold, design: .serif))
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {
                        if let date = article.publishedDateLabel { Text(date) }
                        if article.readingMinutes > 0 {
                            Circle().fill(Color.secondary.opacity(0.4)).frame(width: 3, height: 3)
                            Text("\(article.readingMinutes) 分钟阅读")
                        }
                        Circle().fill(Color.secondary.opacity(0.4)).frame(width: 3, height: 3)
                        Text("\(currentIndex + 1) / \(articles.count)")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 26)

                VStack(alignment: .leading, spacing: 24) {
                    ForEach(Array(Self.paragraphs(from: article.displayContent).enumerated()), id: \.offset) { index, paragraph in
                        Text(paragraph)
                            .font(.system(size: index == 0 ? 19 : 18, weight: index == 0 ? .medium : .regular, design: .serif))
                            .foregroundStyle(Color.primary.opacity(0.9))
                            .lineSpacing(8)
                            .textSelection(.enabled)
                    }

                    if let url = article.canonicalURL {
                        Divider().padding(.top, 8)
                        Button { openURL(url) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("英文原文")
                                        .font(.system(size: 15, weight: .semibold))
                                    Text(article.sourceName)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }
                            .foregroundStyle(.primary)
                            .padding(16)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 26)
                .background(Color(uiColor: .systemBackground))
            }
            }

            articlePager
        }
    }

    private var articlePager: some View {
        HStack(spacing: 12) {
            if canGoBack {
                Text("向左滑 · 上一篇")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
                    .frame(maxWidth: .infinity)
            }

            if canAdvance {
                HStack(spacing: 5) {
                    Text("向右滑 · 下一篇")
                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .frame(minHeight: 48)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
    }

    private var pageGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.35 else {
                    return
                }
                let translation = value.translation.width
                if (translation > 0 && canAdvance) || (translation < 0 && canGoBack) {
                    horizontalOffset = translation * 0.22
                }
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let isHorizontal = abs(horizontal) > abs(value.translation.height) * 1.35
                let targetIndex: Int?
                if isHorizontal, horizontal > 72, canAdvance {
                    targetIndex = currentIndex + 1
                } else if isHorizontal, horizontal < -72, canGoBack {
                    targetIndex = currentIndex - 1
                } else {
                    targetIndex = nil
                }

                withAnimation(.snappy(duration: 0.28)) {
                    horizontalOffset = 0
                    if let targetIndex {
                        currentIndex = targetIndex
                    }
                }
            }
    }

    private var canAdvance: Bool { currentIndex < articles.count - 1 }
    private var canGoBack: Bool { currentIndex > 0 }

    private func load() async {
        errorMessage = nil
        do {
            let value = try await PeopleService().article(id: article.id)
            guard !Task.isCancelled else { return }
            loadedArticle = value
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func paragraphs(from text: String) -> [String] {
        text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func displayTitle(for article: PersonArticle) -> String {
        let title = article.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title == "-" || title.isEmpty else { return title }
        guard let firstParagraph = Self.paragraphs(from: article.displayContent).first else {
            return "未命名文章"
        }
        let sentence = firstParagraph
            .components(separatedBy: CharacterSet(charactersIn: "。！？"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let sentence, !sentence.isEmpty {
            return sentence
        }
        return "未命名文章"
    }
}

private struct PersonPostTimelineRow: View {
    let post: Post
    let compact: Bool
    let onOpen: () -> Void
    @State private var isExpanded = false

    private var displayContent: String {
        post.isBilibili ? post.bilibiliListContent : post.displayContent
    }

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 9, height: 9)
                    .padding(.top, 5)
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1)
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 10) {
                Text([post.formattedTime, post.sourceName].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Button(action: onOpen) {
                    Text(displayContent)
                        .font(.system(size: compact ? 15 : 16))
                        .lineSpacing(4)
                        .lineLimit(isExpanded ? nil : (compact ? 4 : 8))
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                if shouldOfferExpansion {
                    Button(isExpanded ? "收起" : "展开全文") { isExpanded.toggle() }
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                }

                if let quote = post.meta?.quotedTweet {
                    XQuotedPostCard(quote: quote)
                }

                if post.previewURL != nil || !post.videoURLs.isEmpty {
                    XFeedMediaView(post: post)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else if let link = post.externalURL {
                    Link(destination: link) {
                        Label(link.host() ?? "打开链接", systemImage: "link")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    }
                }

                Divider().padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, compact ? 14 : 18)
        .contentShape(Rectangle())
    }

    private var shouldOfferExpansion: Bool {
        displayContent.count > (compact ? 150 : 280) || displayContent.filter(\.isNewline).count > 4
    }
}

private struct PersonProfileView: View {
    let person: SpecialPerson
    let usesCardLayout: Bool
    let openWikipedia: (WikipediaEntity) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            profileSection("人物简介") {
                Text(person.summary)
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .foregroundStyle(.primary)
            }

            profileSection(person.topic == .history ? "主要职务" : "当前身份") {
                VStack(spacing: 0) {
                    ForEach(Array(person.roles.enumerated()), id: \.offset) { index, role in
                        HStack {
                            Text(role.organization)
                            Spacer()
                            Text(role.title).foregroundStyle(.secondary)
                        }
                        .font(.system(size: 15))
                        .padding(.vertical, 10)
                        if index < person.roles.count - 1 { Divider() }
                    }
                }
            }

            profileSection(person.topic == .history ? "历史主题" : "关注领域") {
                HStack(spacing: 8) {
                    ForEach(person.displayFocusTags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 11)
                            .frame(height: 27)
                            .background(Color.secondary.opacity(0.09), in: Capsule())
                    }
                }
            }

            if !person.socialAccounts.isEmpty {
                profileSection("社交媒体") {
                    VStack(spacing: 0) {
                        ForEach(Array(person.socialAccounts.enumerated()), id: \.element.id) { index, account in
                            socialAccountDestination(account)
                            if index < person.socialAccounts.count - 1 { Divider() }
                        }
                    }
                }
            }

            if !person.milestones.isEmpty {
                profileSection(person.topic == .history ? "生平时间线" : "重要经历") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(presentedMilestones.enumerated()), id: \.offset) { _, milestone in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                                Text(milestone.year)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 38, alignment: .leading)
                                Text(milestone.title).font(.system(size: 14))
                            }
                        }
                    }
                }
            }

            if !person.relatedPeople.isEmpty {
                profileSection("相关人物") {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(person.relatedPeople.prefix(3)) { related in
                            VStack(spacing: 6) {
                                AvatarView(
                                    url: related.avatarURL(baseURL: ServerConfiguration.currentURL),
                                    name: related.name,
                                    size: 46,
                                    assetName: related.avatarAssetName
                                )
                                Text(related.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                                Text(related.relationship)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }

            if let updatedAt = person.profileUpdatedAt {
                Text("资料更新于 \(updatedAt)")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 28)
            }
        }
    }

    @ViewBuilder
    private func socialAccountDestination(_ account: PersonSocialAccount) -> some View {
        if let entity = PersonWikipediaPresentation.entity(for: person, account: account) {
            Button {
                openWikipedia(entity)
            } label: {
                socialAccountRow(account, opensInApp: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("在应用内查看\(account.displayHandle)的维基百科词条")
        } else if let url = account.profileURL {
            Link(destination: url) {
                socialAccountRow(account, opensInApp: false)
            }
            .accessibilityLabel("在\(account.platform)中打开\(account.displayHandle)")
        }
    }

    private func socialAccountRow(
        _ account: PersonSocialAccount,
        opensInApp: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: socialIcon(for: account.platform))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(account.platform)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                Text(account.displayHandle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: opensInApp ? "chevron.right" : "arrow.up.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private var presentedMilestones: [PersonMilestone] {
        guard person.topic == .history else { return person.milestones }
        return person.milestones.sorted {
            (Int($0.year) ?? .max) < (Int($1.year) ?? .max)
        }
    }

    private func socialIcon(for platform: String) -> String {
        switch platform.lowercased() {
        case "微博": "message.fill"
        case "哔哩哔哩", "bilibili": "play.rectangle.fill"
        case "x": "at"
        default: "link"
        }
    }

    private func profileSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: usesCardLayout ? 18 : 17, weight: .bold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, usesCardLayout ? 16 : 20)
        .padding(.vertical, usesCardLayout ? 16 : 0)
        .padding(.top, usesCardLayout ? 0 : 16)
        .padding(.bottom, usesCardLayout ? 0 : 14)
        .background(
            usesCardLayout
                ? Color(uiColor: .secondarySystemGroupedBackground)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .padding(.horizontal, usesCardLayout ? 16 : 0)
        .padding(.top, usesCardLayout ? 10 : 0)
        .overlay(alignment: .bottom) {
            if !usesCardLayout {
                Divider().padding(.leading, 20)
            }
        }
    }
}

private struct XQuotedPostCard: View {
    let quote: XQuotedPost
    @State private var liveTranslation: String?
    @State private var showsOriginal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                if let avatar = quote.author?.profileImageURL.flatMap(MediaURL.image) {
                    RemoteImage(url: avatar, height: 24, cornerRadius: 12)
                        .frame(width: 24, height: 24).clipped()
                }
                Text(quote.author?.name ?? "引用动态").font(.subheadline.weight(.semibold)).lineLimit(1)
                if let handle = quote.author?.handle {
                    Text(handle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if let text = displayedText {
                Text(text).font(.subheadline).lineSpacing(2).foregroundStyle(.primary)
            }
            if hasTranslation, quote.originalText != nil {
                Button(showsOriginal ? "显示翻译" : "显示原文") {
                    showsOriginal.toggle()
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            let media = Array((quote.media ?? []).compactMap(\.displayURL).prefix(4))
            if !media.isEmpty {
                XQuotedMediaGrid(urls: media)
            }
        }
        .padding(11)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.18)))
        .task(id: quote.id) {
            await loadTranslationIfNeeded()
        }
    }

    private var displayedText: String? {
        if showsOriginal {
            return quote.originalText ?? quote.displayText
        }
        return nonempty(quote.textZH)
            ?? liveTranslation
            ?? quote.originalText
    }

    private var hasTranslation: Bool {
        nonempty(quote.textZH) != nil
            || liveTranslation != nil
    }

    private func loadTranslationIfNeeded() async {
        guard nonempty(quote.textZH) == nil,
              liveTranslation == nil,
              let tweetID = nonempty(quote.id),
              let original = quote.originalText else { return }
        if let cached = PersonDetailStore.cachedXTranslation(tweetID: tweetID) {
            liveTranslation = cached
            return
        }
        do {
            let result = try await APIClient(baseURL: ServerConfiguration.currentURL)
                .fetchXTranslation(tweetID: tweetID)
            guard !Task.isCancelled else { return }
            let value = PersonDetailStore.presentedTranslation(
                result.text.trimmingCharacters(in: .whitespacesAndNewlines),
                original: original
            )
            guard !value.isEmpty, value != original else { return }
            PersonDetailStore.cacheXTranslation(value, tweetID: tweetID)
            liveTranslation = value
        } catch {
            return
        }
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}

private struct XQuotedMediaGrid: View {
    let urls: [URL]

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 3
            let columnCount = urls.count == 1 ? 1 : 2
            let itemWidth = max(0, (proxy.size.width - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount))
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: columnCount),
                spacing: spacing
            ) {
                ForEach(urls, id: \.self) { url in
                    RemoteImage(
                        url: url,
                        height: itemHeight,
                        cornerRadius: 6,
                        contentMode: urls.count == 1 ? .fit : .fill
                    )
                    .frame(width: itemWidth, height: itemHeight)
                    .background(Color.secondary.opacity(0.05))
                    .clipped()
                }
            }
            .frame(width: proxy.size.width, alignment: .leading)
            .clipped()
        }
        .frame(height: gridHeight)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var itemHeight: CGFloat { urls.count == 1 ? 180 : 100 }
    private var gridHeight: CGFloat { urls.count > 2 ? itemHeight * 2 + 3 : itemHeight }
}

private extension Post {
    var isRecentDiscussion: Bool {
        guard let formattedTime else { return false }
        return formattedTime == "刚刚" || formattedTime.contains("分钟前") || formattedTime.contains("小时前")
    }
}

private struct PeoplePressStyle: ButtonStyle {
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
