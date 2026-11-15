import os

enum Log {
    static let subsystem = "com.hashir.DynamicIsland"

    static let shelf = Logger(subsystem: subsystem, category: "shelf")
    static let media = Logger(subsystem: subsystem, category: "media")
    static let volume = Logger(subsystem: subsystem, category: "volume")
    static let window = Logger(subsystem: subsystem, category: "window")
    static let app = Logger(subsystem: subsystem, category: "app")
}
