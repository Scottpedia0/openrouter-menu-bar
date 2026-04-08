import Foundation

final class ActivityFeedStore {
    private let fileURL: URL
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("OpenRouterMenuBar", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("activity-feed.json")
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> ActivityFeed? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(ActivityFeed.self, from: data)
    }

    var sampleFileURL: URL { fileURL }
}
