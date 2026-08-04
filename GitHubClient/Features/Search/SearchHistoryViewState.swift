nonisolated enum SearchHistoryOperation: Equatable, Sendable {
  case load
  case record(String)
  case clear
}

nonisolated enum SearchHistoryViewState: Equatable, Sendable {
  case idle
  case loading
  case loaded([SearchHistoryEntry])
  case updating([SearchHistoryEntry], SearchHistoryOperation)
  case failed(
    [SearchHistoryEntry],
    AppError,
    SearchHistoryOperation
  )
}
