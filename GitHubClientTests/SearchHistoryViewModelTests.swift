import Testing

@testable import GitHubClient

@Suite("Search History ViewModel lifecycle and FIFO")
struct SearchHistoryViewModelTests {
  @MainActor
  @Test("Selecting history starts immediately without the typing debounce")
  func selectionStartsImmediately() async {
    let searchRepository = ControlledInitialSearchRepository()
    let historyRepository = ControlledSearchHistoryRepository()
    let viewModel = makeSearchHistoryViewModel(
      historyRepository: historyRepository,
      repository: searchRepository,
      debounceDuration: .seconds(3_600)
    )

    viewModel.updateQuery("pending")
    viewModel.selectSearchHistoryEntry(
      SearchHistoryEntry(query: "SwiftUI")
    )

    #expect(viewModel.state.query == "SwiftUI")
    await searchRepository.waitForInvocationCount(1)
    #expect(await searchRepository.queries() == ["SwiftUI"])
    #expect(
      await searchRepository.complete(query: "SwiftUI", with: .cancellation)
    )
    await waitForPrimarySearchState(viewModel) { $0.phase == .idle }
    #expect(await searchRepository.outstandingOperationCount() == 0)
  }

  @MainActor
  @Test("Selected entry moves only after accepted search and record success")
  func selectionMovesAfterAcceptedSuccess() async {
    let searchRepository = ControlledInitialSearchRepository()
    let historyRepository = ControlledSearchHistoryRepository()
    let viewModel = makeSearchHistoryViewModel(
      historyRepository: historyRepository,
      repository: searchRepository,
      debounceDuration: .seconds(3_600)
    )
    let existing = [
      SearchHistoryEntry(query: "Swift"),
      SearchHistoryEntry(query: "Kotlin"),
    ]

    viewModel.loadSearchHistory()
    await historyRepository.waitForInvocationCount(1)
    #expect(await historyRepository.completeNext(with: .success(existing)))
    await waitForHistoryState(viewModel) { $0 == .loaded(existing) }

    viewModel.selectSearchHistoryEntry(existing[1])
    await searchRepository.waitForInvocationCount(1)
    #expect(viewModel.historyState == .loaded(existing))
    #expect(
      await searchRepository.complete(
        query: "Kotlin",
        with: .failure(.offline)
      )
    )
    await waitForPrimarySearchState(viewModel) { $0.phase == .failed }
    #expect(viewModel.historyState == .loaded(existing))

    viewModel.selectSearchHistoryEntry(existing[1])
    await searchRepository.waitForInvocationCount(2)
    let page = RepositoryPage(
      items: [searchHistoryRepositorySummary(id: 1)],
      currentPage: 1,
      hasNextPage: false,
      totalCount: 1
    )
    #expect(
      await searchRepository.complete(query: "Kotlin", with: .success(page))
    )
    await waitForHistoryState(viewModel) {
      $0 == .updating(existing, .record("Kotlin"))
    }
    let reordered = [
      SearchHistoryEntry(query: "Kotlin"),
      SearchHistoryEntry(query: "Swift"),
    ]
    await historyRepository.waitForInvocationCount(2)
    #expect(
      await historyRepository.completeNext(with: .success(reordered))
    )
    await waitForHistoryState(viewModel) { $0 == .loaded(reordered) }
  }

  @MainActor
  @Test("Clear preserves entries until success and on failure")
  func clearPreservesEntriesUntilCompletion() async {
    let historyRepository = ControlledSearchHistoryRepository()
    let viewModel = makeSearchHistoryViewModel(
      historyRepository: historyRepository
    )
    let existing = [
      SearchHistoryEntry(query: "Swift"),
      SearchHistoryEntry(query: "Kotlin"),
    ]

    viewModel.loadSearchHistory()
    await historyRepository.waitForInvocationCount(1)
    #expect(await historyRepository.completeNext(with: .success(existing)))
    await waitForHistoryState(viewModel) { $0 == .loaded(existing) }

    viewModel.clearSearchHistory()
    #expect(viewModel.historyState == .updating(existing, .clear))
    await historyRepository.waitForInvocationCount(2)
    #expect(
      await historyRepository.completeNext(with: .failure(.persistence))
    )
    await waitForHistoryState(viewModel) {
      $0 == .failed(existing, .persistence, .clear)
    }

    viewModel.clearSearchHistory()
    #expect(viewModel.historyState == .updating(existing, .clear))
    await historyRepository.waitForInvocationCount(3)
    #expect(await historyRepository.completeNext(with: .success([])))
    await waitForHistoryState(viewModel) { $0 == .loaded([]) }
  }

  @MainActor
  @Test("Retry repeats only a failed load")
  func retryRepeatsFailedLoad() async {
    let historyRepository = ControlledSearchHistoryRepository()
    let viewModel = makeSearchHistoryViewModel(
      historyRepository: historyRepository
    )

    viewModel.loadSearchHistory()
    await historyRepository.waitForInvocationCount(1)
    #expect(
      await historyRepository.completeNext(with: .failure(.persistence))
    )
    await waitForHistoryState(viewModel) {
      $0 == .failed([], .persistence, .load)
    }

    viewModel.retrySearchHistory()
    #expect(viewModel.historyState == .loading)
    await historyRepository.waitForInvocationCount(2)
    #expect(await historyRepository.invocations() == [.load, .load])
    #expect(await historyRepository.completeNext(with: .success([])))
    await waitForHistoryState(viewModel) { $0 == .loaded([]) }
  }

  @MainActor
  @Test("Retry repeats only a failed clear")
  func retryRepeatsFailedClear() async {
    let historyRepository = ControlledSearchHistoryRepository()
    let viewModel = makeSearchHistoryViewModel(
      historyRepository: historyRepository
    )
    let existing = [SearchHistoryEntry(query: "Swift")]

    viewModel.loadSearchHistory()
    await historyRepository.waitForInvocationCount(1)
    #expect(await historyRepository.completeNext(with: .success(existing)))
    await waitForHistoryState(viewModel) { $0 == .loaded(existing) }
    viewModel.clearSearchHistory()
    await historyRepository.waitForInvocationCount(2)
    #expect(
      await historyRepository.completeNext(with: .failure(.persistence))
    )
    await waitForHistoryState(viewModel) {
      $0 == .failed(existing, .persistence, .clear)
    }

    viewModel.retrySearchHistory()
    #expect(viewModel.historyState == .updating(existing, .clear))
    await historyRepository.waitForInvocationCount(3)
    #expect(
      await historyRepository.invocations() == [.load, .clear, .clear]
    )
    #expect(await historyRepository.completeNext(with: .success([])))
    await waitForHistoryState(viewModel) { $0 == .loaded([]) }
  }

  @MainActor
  @Test("Retry repeats only a failed record")
  func retryRepeatsFailedRecord() async {
    let searchRepository = ControlledInitialSearchRepository()
    let historyRepository = ControlledSearchHistoryRepository()
    let viewModel = makeSearchHistoryViewModel(
      historyRepository: historyRepository,
      repository: searchRepository
    )
    let existing = [SearchHistoryEntry(query: "Kotlin")]

    viewModel.loadSearchHistory()
    await historyRepository.waitForInvocationCount(1)
    #expect(await historyRepository.completeNext(with: .success(existing)))
    await waitForHistoryState(viewModel) { $0 == .loaded(existing) }
    viewModel.updateQuery("swift")
    await searchRepository.waitForInvocationCount(1)
    let page = RepositoryPage(
      items: [searchHistoryRepositorySummary(id: 1)],
      currentPage: 1,
      hasNextPage: false,
      totalCount: 1
    )
    #expect(
      await searchRepository.complete(query: "swift", with: .success(page))
    )
    await historyRepository.waitForInvocationCount(2)
    #expect(
      await historyRepository.completeNext(with: .failure(.persistence))
    )
    await waitForHistoryState(viewModel) {
      $0 == .failed(existing, .persistence, .record("swift"))
    }

    viewModel.retrySearchHistory()
    #expect(viewModel.historyState == .updating(existing, .record("swift")))
    await historyRepository.waitForInvocationCount(3)
    #expect(
      await historyRepository.invocations()
        == [.load, .record("swift"), .record("swift")]
    )
    let updated = [
      SearchHistoryEntry(query: "swift"),
      SearchHistoryEntry(query: "Kotlin"),
    ]
    #expect(await historyRepository.completeNext(with: .success(updated)))
    await waitForHistoryState(viewModel) { $0 == .loaded(updated) }
  }

  @MainActor
  @Test("Retry is a no-op after a later authoritative success")
  func retryDoesNotReplayObsoleteFailure() async {
    let historyRepository = ControlledSearchHistoryRepository()
    let viewModel = makeSearchHistoryViewModel(
      historyRepository: historyRepository
    )

    viewModel.loadSearchHistory()
    await historyRepository.waitForInvocationCount(1)
    viewModel.clearSearchHistory()
    #expect(
      await historyRepository.completeNext(with: .failure(.persistence))
    )
    await historyRepository.waitForInvocationCount(2)
    #expect(await historyRepository.completeNext(with: .success([])))
    await waitForHistoryState(viewModel) { $0 == .loaded([]) }

    viewModel.retrySearchHistory()
    #expect(await historyRepository.invocations() == [.load, .clear])
    #expect(viewModel.historyState == .loaded([]))
  }

  @MainActor
  @Test("Accepted non-empty initial search records its successful-flow query")
  func acceptedNonEmptySearchRecordsQuery() async {
    let searchRepository = ControlledInitialSearchRepository()
    let historyRepository = ControlledSearchHistoryRepository()
    let viewModel = makeSearchHistoryViewModel(
      historyRepository: historyRepository,
      repository: searchRepository
    )
    let page = RepositoryPage(
      items: [searchHistoryRepositorySummary(id: 1)],
      currentPage: 1,
      hasNextPage: false,
      totalCount: 1
    )

    viewModel.updateQuery(" SwiftUI ")
    await searchRepository.waitForInvocationCount(1)
    #expect(await searchRepository.queries() == ["SwiftUI"])
    #expect(
      await searchRepository.complete(query: "SwiftUI", with: .success(page))
    )
    await waitForPrimarySearchState(viewModel) { $0.phase == .loaded }

    let expected = SearchHistoryViewState.updating(
      [],
      .record("SwiftUI")
    )
    #expect(viewModel.historyState == expected)
    guard viewModel.historyState == expected else {
      return
    }
    await historyRepository.waitForInvocationCount(1)
    #expect(await historyRepository.invocations() == [.record("SwiftUI")])
    #expect(
      await historyRepository.completeNext(
        with: .success([SearchHistoryEntry(query: "SwiftUI")])
      )
    )
    await waitForHistoryState(viewModel) {
      $0 == .loaded([SearchHistoryEntry(query: "SwiftUI")])
    }
    #expect(viewModel.state.phase == .loaded)
  }

  @MainActor
  @Test("Accepted empty initial search records its query")
  func acceptedEmptySearchRecordsQuery() async {
    let searchRepository = ControlledInitialSearchRepository()
    let historyRepository = ControlledSearchHistoryRepository()
    let viewModel = makeSearchHistoryViewModel(
      historyRepository: historyRepository,
      repository: searchRepository
    )
    let page = RepositoryPage(
      items: [],
      currentPage: 1,
      hasNextPage: false,
      totalCount: 0
    )

    viewModel.updateQuery("swift")
    await searchRepository.waitForInvocationCount(1)
    #expect(
      await searchRepository.complete(query: "swift", with: .success(page))
    )
    await waitForPrimarySearchState(viewModel) { $0.phase == .empty }

    let expected = SearchHistoryViewState.updating([], .record("swift"))
    #expect(viewModel.historyState == expected)
    guard viewModel.historyState == expected else {
      return
    }
    await historyRepository.waitForInvocationCount(1)
    #expect(await historyRepository.invocations() == [.record("swift")])
    #expect(
      await historyRepository.completeNext(
        with: .success([SearchHistoryEntry(query: "swift")])
      )
    )
    await waitForHistoryState(viewModel) {
      $0 == .loaded([SearchHistoryEntry(query: "swift")])
    }
    #expect(viewModel.state.phase == .empty)
  }

  @MainActor
  @Test("History loads once and applies the authoritative list")
  func loadsOnce() async {
    let repository = ControlledSearchHistoryRepository()
    let viewModel = makeSearchHistoryViewModel(historyRepository: repository)
    let expected = [SearchHistoryEntry(query: "Swift")]

    viewModel.loadSearchHistory()
    viewModel.loadSearchHistory()

    #expect(viewModel.historyState == .loading)
    await repository.waitForInvocationCount(1)
    #expect(await repository.invocations() == [.load])
    #expect(await repository.completeNext(with: .success(expected)))
    await waitForHistoryState(viewModel) { $0 == .loaded(expected) }
    #expect(await repository.outstandingOperationCount() == 0)
    #expect(await repository.outstandingWaiterCount() == 0)
  }

  @MainActor
  @Test("Load failure is independent and exposes the failed operation")
  func loadFailure() async {
    let repository = ControlledSearchHistoryRepository()
    let viewModel = makeSearchHistoryViewModel(historyRepository: repository)

    viewModel.loadSearchHistory()
    await repository.waitForInvocationCount(1)
    #expect(
      await repository.completeNext(with: .failure(.persistence))
    )
    await waitForHistoryState(viewModel) {
      $0 == .failed([], .persistence, .load)
    }

    #expect(viewModel.state.phase == .idle)
    #expect(viewModel.state.error == nil)
    #expect(await repository.outstandingOperationCount() == 0)
    #expect(await repository.outstandingWaiterCount() == 0)
  }

  @MainActor
  @Test("Failed and cancelled initial searches do not record history")
  func failedAndCancelledSearchesDoNotRecord() async {
    let results: [ControlledInitialSearchResult] = [
      .failure(.offline),
      .failure(.server(statusCode: 500)),
      .failure(.decoding),
      .failure(.cancelled),
      .cancellation,
    ]

    for (index, result) in results.enumerated() {
      let searchRepository = ControlledInitialSearchRepository()
      let historyRepository = ControlledSearchHistoryRepository()
      let viewModel = makeSearchHistoryViewModel(
        historyRepository: historyRepository,
        repository: searchRepository
      )
      let query = "swift\(index)"

      viewModel.updateQuery(query)
      await searchRepository.waitForInvocationCount(1)
      #expect(await searchRepository.complete(query: query, with: result))
      await waitForPrimarySearchState(viewModel) {
        $0.phase != .initialLoading
      }

      #expect(await historyRepository.invocations().isEmpty)
      #expect(await searchRepository.outstandingOperationCount() == 0)
    }
  }

  @MainActor
  @Test("Discarded stale success does not record history")
  func staleSuccessDoesNotRecord() async {
    let searchRepository = ControlledInitialSearchRepository()
    let historyRepository = ControlledSearchHistoryRepository()
    let viewModel = makeSearchHistoryViewModel(
      historyRepository: historyRepository,
      repository: searchRepository
    )
    let stalePage = RepositoryPage(
      items: [searchHistoryRepositorySummary(id: 1)],
      currentPage: 1,
      hasNextPage: false,
      totalCount: 1
    )
    let currentPage = RepositoryPage(
      items: [searchHistoryRepositorySummary(id: 2)],
      currentPage: 1,
      hasNextPage: false,
      totalCount: 1
    )

    viewModel.updateQuery("swift")
    await searchRepository.waitForInvocationCount(1)
    viewModel.updateQuery("swiftui")
    await searchRepository.waitForInvocationCount(2)
    #expect(
      await searchRepository.complete(query: "swift", with: .success(stalePage))
    )
    #expect(
      await searchRepository.complete(
        query: "swiftui",
        with: .success(currentPage)
      )
    )
    await waitForPrimarySearchState(viewModel) { $0.items.map(\.id) == [2] }

    let expected = SearchHistoryViewState.updating(
      [],
      .record("swiftui")
    )
    #expect(viewModel.historyState == expected)
    guard viewModel.historyState == expected else {
      return
    }
    await historyRepository.waitForInvocationCount(1)
    #expect(await historyRepository.invocations() == [.record("swiftui")])
    #expect(
      await historyRepository.completeNext(
        with: .success([SearchHistoryEntry(query: "swiftui")])
      )
    )
    await waitForHistoryState(viewModel) {
      $0 == .loaded([SearchHistoryEntry(query: "swiftui")])
    }
    #expect(viewModel.state.items.map(\.id) == [2])
  }

  @MainActor
  @Test("Record failure preserves primary results and prior history")
  func recordFailureIsIndependent() async {
    let searchRepository = ControlledInitialSearchRepository()
    let historyRepository = ControlledSearchHistoryRepository()
    let viewModel = makeSearchHistoryViewModel(
      historyRepository: historyRepository,
      repository: searchRepository
    )
    let existing = [SearchHistoryEntry(query: "Kotlin")]
    let page = RepositoryPage(
      items: [searchHistoryRepositorySummary(id: 1)],
      currentPage: 1,
      hasNextPage: false,
      totalCount: 1
    )

    viewModel.loadSearchHistory()
    await historyRepository.waitForInvocationCount(1)
    #expect(await historyRepository.completeNext(with: .success(existing)))
    await waitForHistoryState(viewModel) { $0 == .loaded(existing) }

    viewModel.updateQuery("swift")
    await searchRepository.waitForInvocationCount(1)
    #expect(
      await searchRepository.complete(query: "swift", with: .success(page))
    )
    await waitForPrimarySearchState(viewModel) { $0.phase == .loaded }
    let expected = SearchHistoryViewState.updating(
      existing,
      .record("swift")
    )
    #expect(viewModel.historyState == expected)
    guard viewModel.historyState == expected else {
      return
    }
    await historyRepository.waitForInvocationCount(2)
    #expect(
      await historyRepository.completeNext(with: .failure(.persistence))
    )
    await waitForHistoryState(viewModel) {
      $0 == .failed(existing, .persistence, .record("swift"))
    }

    #expect(viewModel.state.phase == .loaded)
    #expect(viewModel.state.items.map(\.id) == [1])
    #expect(viewModel.state.error == nil)
  }

  @MainActor
  @Test("Successful pagination does not record another history entry")
  func paginationDoesNotRecordHistory() async {
    let historyRepository = ControlledSearchHistoryRepository()
    let viewModel = makeSearchHistoryViewModel(
      historyRepository: historyRepository,
      repository: SearchHistoryPagedRepository()
    )

    viewModel.updateQuery("swift")
    await waitForPrimarySearchState(viewModel) { $0.phase == .loaded }
    let expected = SearchHistoryViewState.updating([], .record("swift"))
    #expect(viewModel.historyState == expected)
    guard viewModel.historyState == expected else {
      return
    }
    await historyRepository.waitForInvocationCount(1)
    #expect(await historyRepository.invocations() == [.record("swift")])
    #expect(
      await historyRepository.completeNext(
        with: .success([SearchHistoryEntry(query: "swift")])
      )
    )
    await waitForHistoryState(viewModel) {
      $0 == .loaded([SearchHistoryEntry(query: "swift")])
    }

    viewModel.loadNextPage()
    await waitForPrimarySearchState(viewModel) {
      $0.items.map(\.id) == [1, 2]
    }
    #expect(await historyRepository.invocations() == [.record("swift")])
    #expect(await historyRepository.outstandingOperationCount() == 0)
  }

  @MainActor
  @Test("Accepted operations execute FIFO and clear becomes authoritative")
  func acceptedOperationsExecuteFIFO() async {
    let repository = ControlledSearchHistoryRepository()
    let viewModel = makeSearchHistoryViewModel(historyRepository: repository)
    let loaded = [SearchHistoryEntry(query: "Swift")]

    viewModel.loadSearchHistory()
    await repository.waitForInvocationCount(1)
    viewModel.clearSearchHistory()

    #expect(await repository.invocations() == [.load])
    #expect(await repository.completeNext(with: .success(loaded)))
    await repository.waitForInvocationCount(2)
    #expect(await repository.invocations() == [.load, .clear])
    #expect(await repository.completeNext(with: .success([])))
    await waitForHistoryState(viewModel) { $0 == .loaded([]) }
    #expect(await repository.outstandingOperationCount() == 0)
    #expect(await repository.outstandingWaiterCount() == 0)
  }

  @MainActor
  @Test("Failure does not block an operation accepted afterward")
  func failureDoesNotBlockAcceptedOperation() async {
    let repository = ControlledSearchHistoryRepository()
    let viewModel = makeSearchHistoryViewModel(historyRepository: repository)

    viewModel.loadSearchHistory()
    await repository.waitForInvocationCount(1)
    viewModel.clearSearchHistory()

    #expect(
      await repository.completeNext(with: .failure(.persistence))
    )
    await repository.waitForInvocationCount(2)
    #expect(await repository.invocations() == [.load, .clear])
    #expect(await repository.completeNext(with: .success([])))
    await waitForHistoryState(viewModel) { $0 == .loaded([]) }
    #expect(await repository.outstandingOperationCount() == 0)
    #expect(await repository.outstandingWaiterCount() == 0)
  }

  @MainActor
  @Test("ViewModel cancellation discards queued work and presentation updates")
  func cancellationDiscardsQueuedWork() async {
    let repository = ControlledSearchHistoryRepository()
    var viewModel: SearchViewModel? = makeSearchHistoryViewModel(
      historyRepository: repository
    )
    weak let weakViewModel = viewModel

    viewModel?.loadSearchHistory()
    await repository.waitForInvocationCount(1)
    viewModel?.clearSearchHistory()
    viewModel = nil

    await repository.waitForCancellationCount(1)
    #expect(weakViewModel == nil)
    #expect(await repository.invocations() == [.load])
    #expect(await repository.outstandingOperationCount() == 0)
    #expect(await repository.outstandingWaiterCount() == 0)
  }
}

private func searchHistoryRepositorySummary(id: Int) -> RepositorySummary {
  RepositorySummary(
    id: id,
    name: "repository-\(id)",
    fullName: "owner/repository-\(id)",
    owner: RepositoryOwner(
      id: 1,
      login: "owner",
      avatarURL: nil,
      profileURL: nil
    ),
    description: nil,
    starsCount: 0,
    forksCount: 0,
    language: nil,
    updatedAt: nil,
    repositoryURL: nil
  )
}
