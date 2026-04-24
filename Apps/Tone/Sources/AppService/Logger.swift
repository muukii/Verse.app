import os.log

struct AppLog: Sendable {
  private let logger = Logger()

  nonisolated func debug(_ message: @autoclosure () -> String) {
    let message = message()
    logger.debug("\(message, privacy: .public)")
  }

  nonisolated func info(_ message: @autoclosure () -> String) {
    let message = message()
    logger.info("\(message, privacy: .public)")
  }

  nonisolated func warning(_ message: @autoclosure () -> String) {
    let message = message()
    logger.warning("\(message, privacy: .public)")
  }

  nonisolated func error(_ message: @autoclosure () -> String) {
    let message = message()
    logger.error("\(message, privacy: .public)")
  }
}

nonisolated let Log = AppLog()
