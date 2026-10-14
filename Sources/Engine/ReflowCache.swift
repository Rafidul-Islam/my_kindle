import Foundation

/// Disk cache for `ReflowModel`, so a book is only analysed once.
enum ReflowCache {

    static func url(for bookID: UUID) -> URL {
        AppPaths.reflowCache.appendingPathComponent("\(bookID.uuidString).reflow")
    }

    static func load(bookID: UUID, fingerprint: String) -> ReflowModel? {
        let fileURL = url(for: bookID)
        guard let raw = try? Data(contentsOf: fileURL) else { return nil }
        let data = decompress(raw) ?? raw
        guard let model = try? JSONDecoder.inwell.decode(ReflowModel.self, from: data) else { return nil }
        guard model.version == ReflowModel.currentVersion, model.fingerprint == fingerprint else { return nil }
        return model
    }

    static func save(_ model: ReflowModel) {
        guard let data = try? JSONEncoder.inwell.encode(model) else { return }
        let payload = ((try? (data as NSData).compressed(using: .zlib)) as Data?) ?? data
        try? payload.write(to: url(for: model.bookID), options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: AppPaths.reflowCache)
        AppPaths.ensureDirectories()
    }

    private static func decompress(_ data: Data) -> Data? {
        try? (data as NSData).decompressed(using: .zlib) as Data
    }
}