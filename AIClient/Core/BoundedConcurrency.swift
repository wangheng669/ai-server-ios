func runWithLimitedConcurrency<Element>(
    _ elements: [Element],
    maximumConcurrentRequests: Int = 3,
    operation: @escaping @Sendable (Element) async -> Void
) async {
    guard !Task.isCancelled, !elements.isEmpty else { return }
    let limit = max(maximumConcurrentRequests, 1)
    await withTaskGroup(of: Void.self) { group in
        for (index, element) in elements.enumerated() {
            if index >= limit { _ = await group.next() }
            guard group.addTaskUnlessCancelled(operation: { await operation(element) }) else { break }
        }
    }
}
