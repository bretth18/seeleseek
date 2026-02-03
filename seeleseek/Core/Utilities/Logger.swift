import Foundation
import os

extension Logger {
    static let network = Logger(subsystem: "com.seeleseek", category: "Network")
    static let ui = Logger(subsystem: "com.seeleseek", category: "UI")
    static let transfer = Logger(subsystem: "com.seeleseek", category: "Transfer")
    static let metadata = Logger(subsystem: "com.seeleseek", category: "Metadata")
}

struct SeeleLogger {
    private let logger: Logger

    init(category: String) {
        self.logger = Logger(subsystem: "com.seeleseek", category: category)
    }

    func debug(_ message: String) {
        logger.debug("\(message)")
    }

    func info(_ message: String) {
        logger.info("\(message)")
    }

    func warning(_ message: String) {
        logger.warning("\(message)")
    }

    func error(_ message: String) {
        logger.error("\(message)")
    }

    func fault(_ message: String) {
        logger.fault("\(message)")
    }
}
