import SwiftUI
import AVKit
import PhotosUI
import Photos
import UniformTypeIdentifiers
import ImageIO
import Vision

enum LocalStorageKey {
    case oshis
    case chekis
    case lives
    case graduatedOshis
    case profile
    case chekiSaveSettings
    case chekiWatermarkText
    case penlightSheets

    var fileName: String {
        switch self {
        case .oshis: return "saved_oshis.json"
        case .chekis: return "saved_chekis.json"
        case .lives: return "saved_lives.json"
        case .graduatedOshis: return "graduated_oshis.json"
        case .profile: return "saved_profile.json"
        case .chekiSaveSettings: return "cheki_save_settings.json"
        case .chekiWatermarkText: return "cheki_watermark_text.json"
        case .penlightSheets: return "penlight_sheets.json"
        }
    }
}

enum LocalStorage {
    private static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    private static func fileURL(for key: LocalStorageKey) -> URL {
        documentsDirectory.appendingPathComponent(key.fileName)
    }

    static func load<T: Codable>(_ type: T.Type, for key: LocalStorageKey) -> T? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(type, from: data) else { return nil }
        return decoded
    }

    static func save<T: Encodable>(_ value: T, for key: LocalStorageKey) {
        let url = fileURL(for: key)

        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            print("保存失敗(\(key.fileName)): \(error)")
        }
    }

    static func delete(_ key: LocalStorageKey) {
        let url = fileURL(for: key)
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - 1. データ型
struct Cheki: Identifiable, Codable {
    var id = UUID()
    var oshiID: UUID
    var imageData: Data
    var thumbnailData: Data
    var date: Date?
    var isFavorite: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, oshiID, imageData, thumbnailData, date, isFavorite, rotationQuarterTurns
    }

    init(id: UUID = UUID(), oshiID: UUID, imageData: Data, thumbnailData: Data? = nil, date: Date? = nil, isFavorite: Bool = false) {
        self.id = id
        self.oshiID = oshiID
        self.imageData = imageData
        self.thumbnailData = thumbnailData ?? ChekiThumbnailHelper.thumbnailData(from: imageData)
        self.date = date
        self.isFavorite = isFavorite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        oshiID = try container.decode(UUID.self, forKey: .oshiID)
        let decodedImageData = try container.decode(Data.self, forKey: .imageData)
        date = try container.decodeIfPresent(Date.self, forKey: .date)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        let storedQuarterTurns = ChekiRotationHelper.normalizedQuarterTurns(
            try container.decodeIfPresent(Int.self, forKey: .rotationQuarterTurns) ?? 0
        )
        imageData = ChekiRotationHelper.rotatedImageData(from: decodedImageData, quarterTurns: storedQuarterTurns) ?? decodedImageData
        thumbnailData = try container.decodeIfPresent(Data.self, forKey: .thumbnailData) ?? ChekiThumbnailHelper.thumbnailData(from: imageData)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(oshiID, forKey: .oshiID)
        try container.encode(imageData, forKey: .imageData)
        try container.encode(thumbnailData, forKey: .thumbnailData)
        try container.encodeIfPresent(date, forKey: .date)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(0, forKey: .rotationQuarterTurns)
    }
}

private enum ChekiRotationHelper {
    static func normalizedQuarterTurns(_ rawValue: Int) -> Int {
        let normalized = rawValue % 4
        return normalized >= 0 ? normalized : normalized + 4
    }

    static func rotatedImage(from data: Data, quarterTurns: Int) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        return rotatedImage(image, quarterTurns: quarterTurns)
    }

    static func rotatedImage(_ image: UIImage, quarterTurns: Int) -> UIImage {
        let normalized = normalizedQuarterTurns(quarterTurns)
        guard normalized != 0 else { return image }

        let targetSize = normalized.isMultiple(of: 2)
            ? image.size
            : CGSize(width: image.size.height, height: image.size.width)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
            let cgContext = context.cgContext
            cgContext.translateBy(x: targetSize.width / 2, y: targetSize.height / 2)

            switch normalized {
            case 1:
                cgContext.rotate(by: .pi / 2)
            case 2:
                cgContext.rotate(by: .pi)
            case 3:
                cgContext.rotate(by: -.pi / 2)
            default:
                break
            }

            image.draw(in: CGRect(
                x: -image.size.width / 2,
                y: -image.size.height / 2,
                width: image.size.width,
                height: image.size.height
            ))
        }
    }

    static func rotatedImageData(from data: Data, quarterTurns: Int) -> Data? {
        let normalized = normalizedQuarterTurns(quarterTurns)
        guard normalized != 0, let image = UIImage(data: data) else { return data }

        let rotated = rotatedImage(image, quarterTurns: normalized)
        if image.hasAlphaChannel {
            return rotated.pngData()
        }
        return rotated.jpegData(compressionQuality: 0.98)
    }
}

private enum ChekiThumbnailHelper {
    static let maxLongEdge: CGFloat = 150
    static let compressionQuality: CGFloat = 0.78

    static func thumbnailData(from data: Data) -> Data {
        ImageResizer.resizedJPEGData(
            from: data,
            maxLongEdge: maxLongEdge,
            compressionQuality: compressionQuality
        ) ?? data
    }
}

private extension UIImage {
    var hasAlphaChannel: Bool {
        guard let alphaInfo = cgImage?.alphaInfo else { return false }
        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        default:
            return false
        }
    }
}

private func imageDataFingerprint(_ data: Data) -> String {
    guard !data.isEmpty else { return "empty" }

    var hasher = Hasher()
    hasher.combine(data.count)

    let sampleIndices: [Int] = [
        0,
        min(1, data.count - 1),
        min(2, data.count - 1),
        min(3, data.count - 1),
        max(0, data.count / 3),
        max(0, data.count / 2),
        max(0, (data.count * 2) / 3),
        max(0, data.count - 4),
        max(0, data.count - 3),
        max(0, data.count - 2),
        data.count - 1
    ]

    for index in Set(sampleIndices).sorted() {
        hasher.combine(data[index])
    }

    return String(hasher.finalize(), radix: 16)
}

private func chekiThumbnailFingerprint(_ cheki: Cheki) -> String {
    imageDataFingerprint(cheki.thumbnailData)
}

struct VenueInfo: Codable, Identifiable {
    let venueId: String?
    let name: String
    let address: String? // 将来用（空でもOK）
    let lat: Double?    // 将来用（空でもOK）
    let lng: Double?    // 将来用（空でもOK）
    let prefecture: String?
    let aliases: [String]?

    var id: String { venueId ?? name }

    var searchableTexts: [String] {
        var values = [name]
        if let address, !address.isEmpty { values.append(address) }
        if let prefecture, !prefecture.isEmpty { values.append(prefecture) }
        if let aliases {
            values.append(contentsOf: aliases.filter { !$0.isEmpty })
        }
        return values
    }
}

struct TimeTreeEventSuggestion: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let isAllDay: Bool
    let regionTimeZoneIdentifier: String?
    let locationName: String?
    let note: String?
    let extractedVenueName: String?
    let coverImageURL: URL?
    let eventURL: URL?

    var displayTimeText: String {
        guard !isAllDay else { return "終日" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        if let regionTimeZoneIdentifier,
           let timeZone = TimeZone(identifier: regionTimeZoneIdentifier) {
            formatter.timeZone = timeZone
        }
        formatter.dateFormat = "H:mm"
        return formatter.string(from: startDate)
    }
}

private enum TimeTreePublicCalendarClient {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    private struct PublicEventsResponse: Decodable {
        let publicEvents: [PublicEvent]

        enum CodingKeys: String, CodingKey {
            case publicEvents = "public_events"
        }
    }

    private struct PublicEvent: Decodable {
        let id: String
        let title: String
        let allDay: Bool
        let startAt: Int64
        let regionTimeZone: String?
        let note: String?
        let locationName: String?
        let images: PublicEventImages?
        let url: String?

        enum CodingKeys: String, CodingKey {
            case id, title
            case allDay = "all_day"
            case startAt = "start_at"
            case regionTimeZone = "region_timezone"
            case note
            case locationName = "location_name"
            case images
            case url
        }
    }

    private struct PublicEventImages: Decodable {
        let cover: [PublicEventImage]
    }

    private struct PublicEventImage: Decodable {
        let url: String?
        let thumbnailURL: String?

        enum CodingKeys: String, CodingKey {
            case url
            case thumbnailURL = "thumbnail_url"
        }
    }

    static func calendarIdentifier(from source: String) -> String? {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else { return nil }

        if !trimmedSource.contains("://") && !trimmedSource.contains("/") {
            return trimmedSource
        }

        guard let url = URL(string: trimmedSource) else { return nil }
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        if let publicIndex = pathComponents.firstIndex(of: "public_calendars"),
           pathComponents.indices.contains(publicIndex + 1) {
            return pathComponents[publicIndex + 1]
        }

        if let publicShortIndex = pathComponents.firstIndex(of: "p"),
           pathComponents.indices.contains(publicShortIndex + 1) {
            return pathComponents[publicShortIndex + 1]
        }

        return pathComponents.last
    }

    static func fetchSuggestions(aliasCode: String, date: Date) async throws -> [TimeTreeEventSuggestion] {
        let pageURL = URL(string: "https://timetreeapp.com/public_calendars/\(aliasCode)?locale=ja")!
        let csrfToken = try await fetchCSRFToken(pageURL: pageURL)
        let queryRange = queryRangeForSelectedDate(date)
        var components = URLComponents(string: "https://timetreeapp.com/api/v2/public_calendars/\(aliasCode)/public_events")!
        components.queryItems = [
            URLQueryItem(name: "from", value: String(Int64(queryRange.from.timeIntervalSince1970 * 1000))),
            URLQueryItem(name: "to", value: String(Int64(queryRange.to.timeIntervalSince1970 * 1000))),
            URLQueryItem(name: "utc_offset", value: String(TimeZone.current.secondsFromGMT(for: date) / 60)),
            URLQueryItem(name: "limit", value: "50")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token")
        request.setValue("web/2.1.0/oshi-life", forHTTPHeaderField: "X-TimeTreeA")
        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(PublicEventsResponse.self, from: data)
        let selectedDay = Calendar(identifier: .gregorian).startOfDay(for: date)

        return response.publicEvents.compactMap { event in
            let startDate = Date(timeIntervalSince1970: TimeInterval(event.startAt) / 1000)
            let eventDay = startOfDay(for: startDate, in: event.regionTimeZone)
            guard eventDay == selectedDay else { return nil }
            let locationName = normalizedVenueName(event.locationName)
            let extractedVenueName = extractVenueName(from: event.title) ?? extractVenueName(from: event.note)
            return TimeTreeEventSuggestion(
                id: event.id,
                title: event.title,
                startDate: startDate,
                isAllDay: event.allDay,
                regionTimeZoneIdentifier: event.regionTimeZone,
                locationName: locationName,
                note: event.note,
                extractedVenueName: locationName ?? extractedVenueName,
                coverImageURL: event.images?.cover.first.flatMap { image in
                    URL(string: image.url ?? image.thumbnailURL ?? "")
                },
                eventURL: event.url.flatMap(URL.init(string:))
            )
        }
        .sorted { $0.startDate < $1.startDate }
    }

    private static func fetchCSRFToken(pageURL: URL) async throws -> String {
        let (data, _) = try await session.data(from: pageURL)
        guard let html = String(data: data, encoding: .utf8),
              let range = html.range(of: #"<meta name="csrf-token" content="([^"]+)""#, options: .regularExpression)
        else {
            throw URLError(.cannotParseResponse)
        }

        let matched = String(html[range])
        guard let tokenRange = matched.range(of: #"content="([^"]+)""#, options: .regularExpression) else {
            throw URLError(.cannotParseResponse)
        }

        let tokenMatch = String(matched[tokenRange])
        return tokenMatch
            .replacingOccurrences(of: #"content=""#, with: "", options: .regularExpression)
            .dropLast()
            .description
    }

    private static func queryRangeForSelectedDate(_ date: Date) -> (from: Date, to: Date) {
        let calendar = Calendar(identifier: .gregorian)
        let startOfDay = calendar.startOfDay(for: date)
        let from = calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay
        let toBase = calendar.date(byAdding: .day, value: 2, to: startOfDay) ?? startOfDay
        let to = toBase.addingTimeInterval(-1)
        return (from, to)
    }

    private static func startOfDay(for date: Date, in regionTimeZoneIdentifier: String?) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        if let regionTimeZoneIdentifier,
           let timeZone = TimeZone(identifier: regionTimeZoneIdentifier) {
            calendar.timeZone = timeZone
        }
        return calendar.startOfDay(for: date)
    }

    private static func extractVenueName(from source: String?) -> String? {
        guard let source else { return nil }
        let separators = ["＠", "@"]
        for separator in separators {
            if let range = source.range(of: separator) {
                let candidate = source[range.upperBound...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: .newlines)
                    .first?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let candidate, !candidate.isEmpty {
                    return candidate
                }
            }
        }
        return nil
    }

    private static func normalizedVenueName(_ source: String?) -> String? {
        guard let trimmed = source?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

struct VideoRecord: Codable, Identifiable, Equatable {
    var id: String { videoID }
    let videoID: String
    var title: String = ""
}

struct LivePhotoItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var imageData: Data
    var date: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id, imageData, date
    }

    init(id: UUID = UUID(), imageData: Data, date: Date = Date()) {
        self.id = id
        self.imageData = imageData
        self.date = date
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        imageData = try container.decode(Data.self, forKey: .imageData)
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(imageData, forKey: .imageData)
        try container.encode(date, forKey: .date)
    }
}

struct LiveGroupReference: Identifiable, Codable, Equatable, Hashable {
    var groupId: String?
    var groupName: String
    var isOther: Bool = false

    var id: String {
        if isOther { return "other" }
        if let groupId, !groupId.isEmpty { return "id:\(groupId)" }
        return "name:\(groupName)"
    }
}

struct LiveRecord: Identifiable, Codable {
    static let defaultSectionOrder = ["photo", "video", "cheki", "memo"]

    var id = UUID()
    var appearingGroups: [LiveGroupReference] = []
    var date: Date
    var title: String
    var venue: String
    var memo: String
    var imageData: Data?
    var isPhotoSectionVisible: Bool = true
    var isVideoSectionVisible: Bool = true
    var isChekiSectionVisible: Bool = true
    var isMemoSectionVisible: Bool = true
    var sectionOrder: [String] = LiveRecord.defaultSectionOrder
    var galleryPhotos: [LivePhotoItem] = []
    var videoRecords: [VideoRecord] = []
    var isFavorite: Bool = false
    var legacyOshiIDs: [UUID] = []

    enum CodingKeys: String, CodingKey {
        case id, appearingGroups, oshiIDs, date, title, venue, memo, imageData, isPhotoSectionVisible, isVideoSectionVisible, isChekiSectionVisible, isMemoSectionVisible, sectionOrder, galleryPhotos, videoRecords, videoIDs, isFavorite
    }

    // デコード（読み込み）のルール
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        appearingGroups = try container.decodeIfPresent([LiveGroupReference].self, forKey: .appearingGroups) ?? []
        legacyOshiIDs = try container.decodeIfPresent([UUID].self, forKey: .oshiIDs) ?? []
        date = try container.decode(Date.self, forKey: .date)
        title = try container.decode(String.self, forKey: .title)
        venue = try container.decode(String.self, forKey: .venue)
        memo = try container.decode(String.self, forKey: .memo)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        isPhotoSectionVisible = try container.decodeIfPresent(Bool.self, forKey: .isPhotoSectionVisible) ?? true
        isVideoSectionVisible = try container.decodeIfPresent(Bool.self, forKey: .isVideoSectionVisible) ?? true
        isChekiSectionVisible = try container.decodeIfPresent(Bool.self, forKey: .isChekiSectionVisible) ?? true
        isMemoSectionVisible = try container.decodeIfPresent(Bool.self, forKey: .isMemoSectionVisible) ?? true
        sectionOrder = try container.decodeIfPresent([String].self, forKey: .sectionOrder) ?? LiveRecord.defaultSectionOrder
        galleryPhotos = try container.decodeIfPresent([LivePhotoItem].self, forKey: .galleryPhotos) ?? []
        
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        
        // ★ ここが重要：まず「videoRecords（曲名入り）」があるかチェック
        if container.contains(.videoRecords) {
            videoRecords = try container.decode([VideoRecord].self, forKey: .videoRecords)
        }
        // ★ 無ければ「videoIDs（古い形式）」を探して変換
        else if container.contains(.videoIDs) {
            let oldIDs = try container.decode([String].self, forKey: .videoIDs)
            videoRecords = oldIDs.map { VideoRecord(videoID: $0, title: "") }
        } else {
            videoRecords = []
        }
     }

    // 保存（エンコード）のルール
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(appearingGroups, forKey: .appearingGroups)
        if appearingGroups.isEmpty && !legacyOshiIDs.isEmpty {
            try container.encode(legacyOshiIDs, forKey: .oshiIDs)
        }
        try container.encode(date, forKey: .date)
        try container.encode(title, forKey: .title)
        try container.encode(venue, forKey: .venue)
        try container.encode(memo, forKey: .memo)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encode(isPhotoSectionVisible, forKey: .isPhotoSectionVisible)
        try container.encode(isVideoSectionVisible, forKey: .isVideoSectionVisible)
        try container.encode(isChekiSectionVisible, forKey: .isChekiSectionVisible)
        try container.encode(isMemoSectionVisible, forKey: .isMemoSectionVisible)
        try container.encode(sectionOrder, forKey: .sectionOrder)
        try container.encode(galleryPhotos, forKey: .galleryPhotos)
        try container.encode(isFavorite, forKey: .isFavorite)
        // 保存するときは新しい [VideoRecord] 形式だけを書き出す
        try container.encode(videoRecords, forKey: .videoRecords)
    }
    
    // 通常のイニシャライザ（AddLiveViewなどで使用）
    init(id: UUID = UUID(), appearingGroups: [LiveGroupReference] = [], date: Date, title: String, venue: String, memo: String, imageData: Data? = nil, isPhotoSectionVisible: Bool = true, isVideoSectionVisible: Bool = true, isChekiSectionVisible: Bool = true, isMemoSectionVisible: Bool = true, sectionOrder: [String] = LiveRecord.defaultSectionOrder, galleryPhotos: [LivePhotoItem] = [], videoRecords: [VideoRecord] = [], isFavorite: Bool = false) {
        self.id = id
        self.appearingGroups = appearingGroups
        self.date = date
        self.title = title
        self.venue = venue
        self.memo = memo
        self.imageData = imageData
        self.isPhotoSectionVisible = isPhotoSectionVisible
        self.isVideoSectionVisible = isVideoSectionVisible
        self.isChekiSectionVisible = isChekiSectionVisible
        self.isMemoSectionVisible = isMemoSectionVisible
        self.sectionOrder = sectionOrder
        self.galleryPhotos = galleryPhotos
        self.videoRecords = videoRecords
        self.isFavorite = isFavorite
    }
}

private func makeLiveGroupReference(groupId: String?, groupName: String, isOther: Bool = false) -> LiveGroupReference {
    LiveGroupReference(
        groupId: (groupId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? groupId : nil,
        groupName: groupName,
        isOther: isOther
    )
}

private func matchesLiveGroupReference(_ oshi: Oshi, reference: LiveGroupReference) -> Bool {
    if reference.isOther {
        return (oshi.group.isEmpty ? oshi.name : oshi.group) == "その他"
    }

    if let groupId = reference.groupId, !groupId.isEmpty {
        return oshi.groupId == groupId
    }

    return oshi.group == reference.groupName
}

private func resolvedLiveGroupReferences(for live: LiveRecord, myOshis: [Oshi]) -> [LiveGroupReference] {
    if !live.appearingGroups.isEmpty {
        return live.appearingGroups
    }

    var results: [LiveGroupReference] = []

    for oshi in myOshis where live.legacyOshiIDs.contains(oshi.id) {
        let groupName = oshi.group.isEmpty ? oshi.name : oshi.group
        let reference = makeLiveGroupReference(groupId: oshi.groupId, groupName: groupName)
        if !results.contains(reference) {
            results.append(reference)
        }
    }

    if live.legacyOshiIDs.contains(AppConfig.otherID) {
        let otherReference = makeLiveGroupReference(groupId: nil, groupName: "その他", isOther: true)
        if !results.contains(otherReference) {
            results.append(otherReference)
        }
    }

    return results
}

private func selectedOshis(for live: LiveRecord, myOshis: [Oshi]) -> [Oshi] {
    let references = resolvedLiveGroupReferences(for: live, myOshis: myOshis)
    return myOshis.filter { oshi in
        references.contains { reference in
            !reference.isOther && matchesLiveGroupReference(oshi, reference: reference)
        }
    }
}

private func liveIncludesOtherGroup(_ live: LiveRecord, myOshis: [Oshi]) -> Bool {
    resolvedLiveGroupReferences(for: live, myOshis: myOshis).contains(where: \.isOther)
}

private func resolvedLiveGroupDisplayItems(for live: LiveRecord, myOshis: [Oshi]) -> [(name: String, badges: [LiveGroupBadge])] {
    let references = resolvedLiveGroupReferences(for: live, myOshis: myOshis)

    return references.compactMap { reference in
        let name = reference.groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let badges = myOshis
            .filter { oshi in
                oshi.kind == .person && matchesLiveGroupReference(oshi, reference: reference)
            }
            .map { oshi in
                LiveGroupBadge(color: oshi.color, symbolName: "heart.fill")
            }

        return (name: name, badges: badges)
    }
}


// 卒業した推しの記録用モデル
struct GraduatedOshi: Identifiable, Codable {
    var id: UUID
    var name: String
    var group: String
    var daysCount: Int
    var graduationDate: Date
    var colorHex: String
}

struct UserProfile: Codable, Equatable {
    var displayName: String = ""
    var message: String = ""
    var iconImageData: Data? = nil
    var preferredAppFont: AppDisplayFontChoice = .yuseiMagic

    enum CodingKeys: String, CodingKey {
        case displayName
        case message
        case iconImageData
        case preferredAppFont
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        iconImageData = try container.decodeIfPresent(Data.self, forKey: .iconImageData)
        preferredAppFont = try container.decodeIfPresent(AppDisplayFontChoice.self, forKey: .preferredAppFont) ?? .yuseiMagic
    }
}

enum AppDisplayFontChoice: String, Codable, CaseIterable, Identifiable {
    case system
    case hachiMaruPop
    case humour
    case makinas
    case yuseiMagic
    case rondeB

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "標準"
        case .hachiMaruPop: return "Hachi Maru Pop"
        case .humour: return "ユムール"
        case .makinas: return "マキナス"
        case .yuseiMagic: return "Yusei Magic"
        case .rondeB: return "ロンドB"
        }
    }

    var bundledFileName: String? {
        switch self {
        case .system: return nil
        case .hachiMaruPop: return "HachiMaruPop-Regular.ttf"
        case .humour: return "Humour-Normal.ttf"
        case .makinas: return "Makinas-4-Flat.otf"
        case .yuseiMagic: return "YuseiMagic-Regular.ttf"
        case .rondeB: return "Ronde-B_square.otf"
        }
    }

    var candidateFontNames: [String] {
        switch self {
        case .system:
            return []
        case .hachiMaruPop:
            return ["HachiMaruPop-Regular", "HachiMaruPop"]
        case .humour:
            return ["Humour-Normal", "Humour Normal", "Humour"]
        case .makinas:
            return ["Makinas-4-Flat", "Makinas 4 Flat", "Makinas-4", "Makinas"]
        case .yuseiMagic:
            return ["YuseiMagic-Regular", "YuseiMagic", "Yusei Magic"]
        case .rondeB:
            return ["Ronde-B-Square", "Ronde B Square", "Ronde-B", "RondeB"]
        }
    }
}

enum AppTypography {
    private static func resolvedFontName(for choice: AppDisplayFontChoice, size: CGFloat) -> String? {
        for candidate in choice.candidateFontNames {
            if UIFont(name: candidate, size: size) != nil {
                return candidate
            }
        }
        return nil
    }

    static func navigationTitleFont(for choice: AppDisplayFontChoice, size: CGFloat = 18) -> Font {
        guard let resolvedName = resolvedFontName(for: choice, size: size) else {
            return .custom("HiraginoSans-W6", size: size)
        }
        return .custom(resolvedName, size: size)
    }

    static func navigationTitleUIFont(for choice: AppDisplayFontChoice, size: CGFloat = 18) -> UIFont {
        guard let resolvedName = resolvedFontName(for: choice, size: size),
              let font = UIFont(name: resolvedName, size: size) else {
            return UIFont(name: "HiraginoSans-W6", size: size) ?? .systemFont(ofSize: size, weight: .semibold)
        }
        return font
    }

    static func roundedDisplayFont(for choice: AppDisplayFontChoice, size: CGFloat, weight: Font.Weight = .bold) -> Font {
        guard let resolvedName = resolvedFontName(for: choice, size: size) else {
            return .system(size: size, weight: weight, design: .rounded)
        }
        return .custom(resolvedName, size: size)
    }

    static func bodyFont(for choice: AppDisplayFontChoice, size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard let resolvedName = resolvedFontName(for: choice, size: size) else {
            return .system(size: size, weight: weight)
        }
        return .custom(resolvedName, size: size)
    }

    static func penlightSheetFont(size: CGFloat) -> Font {
        if UIFont(name: "GenJyuuGothicX-Heavy", size: size) != nil {
            return .custom("GenJyuuGothicX-Heavy", size: size)
        }
        return .custom("YuseiMagic-Regular", size: size)
    }
}

enum ChekiWatermarkStyle: String, Codable, CaseIterable, Identifiable {
    case diagonalHearts
    case frame
    case logo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .diagonalHearts: return "斜めハート"
        case .frame: return "フレーム"
        case .logo: return "大きめロゴ"
        }
    }

    var subtitle: String {
        switch self {
        case .diagonalHearts: return "全体にふんわり入れる"
        case .frame: return "外周をかわいく飾る"
        case .logo: return "中央に大きくうっすら"
        }
    }
}

struct ChekiSaveSettings: Codable, Equatable {
    var isWatermarkEnabled: Bool = false
    var watermarkStyle: ChekiWatermarkStyle = .diagonalHearts
    var watermarkText: String = ""
    var excludesFacesFromWatermark: Bool = true
    var batchLayoutStyle: ChekiBatchLayoutStyle = .grid
    var corkTextureStyle: ChekiCorkTextureStyle = .cork004
}

enum ChekiBatchLayoutStyle: String, CaseIterable, Identifiable, Codable {
    case grid
    case corkboard
    case maskingTape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: return "通常"
        case .corkboard: return "ピン留め"
        case .maskingTape: return "マステ"
        }
    }
}

enum ChekiCorkTextureStyle: String, Identifiable, Codable, CaseIterable {
    case cork004
    case cork003
    case wood010
    case chalkboard
    case bricks101
    case planks022

    static var allCases: [ChekiCorkTextureStyle] {
        [.cork004, .wood010, .chalkboard, .bricks101, .planks022]
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cork004: return "コルク"
        case .cork003: return "コルク 003"
        case .wood010: return "木"
        case .chalkboard: return "黒板"
        case .bricks101: return "レンガ"
        case .planks022: return "板"
        }
    }

    var imageName: String {
        switch self {
        case .cork004: return "CorkBoardTexture"
        case .cork003: return "CorkBoardTexture003"
        case .wood010: return "WoodBoardTexture010"
        case .chalkboard: return "ChalkboardTexture"
        case .bricks101: return "BricksBoardTexture101"
        case .planks022: return "PlanksBoardTexture022"
        }
    }

    var backgroundBaseZoomScale: CGFloat {
        switch self {
        case .bricks101:
            return 1.12
        case .planks022:
            return 1.10
        default:
            return 1.0
        }
    }
}

enum ChekiWatermarkRenderer {
    // TODO: Bundle a fixed cute font for watermark rendering (candidate: Hachi Maru Pop or Yusei Magic).
    static func watermarkedImage(from image: UIImage, settings: ChekiSaveSettings, scale: CGFloat = 1.0) -> UIImage {
        guard settings.isWatermarkEnabled else { return image }

        let text = settings.watermarkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "推しライファー！"
            : settings.watermarkText.trimmingCharacters(in: .whitespacesAndNewlines)

        let size = image.size
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))

            switch settings.watermarkStyle {
            case .diagonalHearts:
                drawDiagonalPattern(
                    text: text,
                    image: image,
                    size: size,
                    scale: scale,
                    excludesFaces: settings.excludesFacesFromWatermark
                )
            case .frame:
                drawFramePattern(text: text, size: size, scale: scale)
            case .logo:
                drawLogoPattern(text: text, size: size, scale: scale)
            }
        }
    }

    private static func drawDiagonalPattern(
        text: String,
        image: UIImage,
        size: CGSize,
        scale: CGFloat,
        excludesFaces: Bool
    ) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let safeScale = max(scale, 0.45)
        let pitch = max(min(size.width, size.height) * 0.255 * safeScale, 92)
        let lineWidth = max(min(size.width, size.height) * 0.0022 * safeScale, 0.8)
        let lineGap = pitch * 0.18
        let gridExtent = Int((size.width + size.height) / pitch) + 6
        let excludedFaceRects = excludesFaces ? faceExclusionRects(for: image, canvasSize: size) : []
        let diagonalColor = UIColor(white: 0.66, alpha: 0.44)

        let diagonalA = CGVector(dx: pitch / 2, dy: pitch / 2)
        let diagonalB = CGVector(dx: pitch / 2, dy: -pitch / 2)
        let origin = CGPoint(x: size.width / 2, y: size.height / 2)
        let visibleRect = CGRect(x: -pitch, y: -pitch, width: size.width + pitch * 2, height: size.height + pitch * 2)

        context.saveGState()
        context.setLineWidth(lineWidth)
        context.setStrokeColor(diagonalColor.cgColor)
        context.setLineCap(.round)

        func point(i: Int, j: Int) -> CGPoint {
            CGPoint(
                x: origin.x + CGFloat(i) * diagonalA.dx + CGFloat(j) * diagonalB.dx,
                y: origin.y + CGFloat(i) * diagonalA.dy + CGFloat(j) * diagonalB.dy
            )
        }

        func midpoint(_ p1: CGPoint, _ p2: CGPoint) -> CGPoint {
            CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
        }

        func drawSegment(from start: CGPoint, to end: CGPoint) {
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = sqrt(dx * dx + dy * dy)
            guard length > lineGap * 2 else { return }

            let ux = dx / length
            let uy = dy / length
            let adjustedStart = CGPoint(x: start.x + ux * lineGap, y: start.y + uy * lineGap)
            let adjustedEnd = CGPoint(x: end.x - ux * lineGap, y: end.y - uy * lineGap)
            let mid = midpoint(adjustedStart, adjustedEnd)
            guard visibleRect.contains(mid) else { return }
            guard excludedFaceRects.allSatisfy({ !$0.contains(mid) }) else { return }

            context.move(to: adjustedStart)
            context.addLine(to: adjustedEnd)
            context.strokePath()
        }

        for i in -gridExtent...gridExtent {
            for j in -gridExtent...gridExtent {
                let current = point(i: i, j: j)
                drawSegment(from: current, to: point(i: i + 1, j: j))
                drawSegment(from: current, to: point(i: i, j: j + 1))
            }
        }

        context.restoreGState()

        let heartAttributes = watermarkAttributes(
            font: .systemFont(ofSize: max(pitch * 0.145, 11), weight: .regular),
            color: diagonalColor,
            shadowAlpha: 0.16,
            shadowBlurRadius: 12
        )
        let textAttributes = watermarkAttributes(
            font: .systemFont(ofSize: max(pitch * 0.105, 9), weight: .semibold),
            color: diagonalColor,
            shadowAlpha: 0.14,
            shadowBlurRadius: 10
        )

        let heartText = NSString(string: "♡")
        let heartSize = heartText.size(withAttributes: heartAttributes)
        let watermarkText = NSString(string: text)
        let watermarkSize = watermarkText.size(withAttributes: textAttributes)

        for i in -gridExtent...gridExtent {
            for j in -gridExtent...gridExtent {
                let current = point(i: i, j: j)
                guard visibleRect.contains(current) else { continue }

                if (i + j).isMultiple(of: 2) {
                    let rect = CGRect(
                        x: current.x - watermarkSize.width / 2,
                        y: current.y - watermarkSize.height / 2,
                        width: watermarkSize.width,
                        height: watermarkSize.height
                    )
                    guard excludedFaceRects.allSatisfy({ !$0.intersects(rect) }) else { continue }
                    watermarkText.draw(in: rect, withAttributes: textAttributes)
                } else {
                    let rect = CGRect(
                        x: current.x - heartSize.width / 2,
                        y: current.y - heartSize.height / 2,
                        width: heartSize.width,
                        height: heartSize.height
                    )
                    guard excludedFaceRects.allSatisfy({ !$0.intersects(rect) }) else { continue }
                    heartText.draw(in: rect, withAttributes: heartAttributes)
                }
            }
        }
    }

    private static func faceExclusionRects(for image: UIImage, canvasSize: CGSize) -> [CGRect] {
        guard let cgImage = image.cgImage else { return [] }

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: visionOrientation(for: image.imageOrientation))

        do {
            try handler.perform([request])
        } catch {
            return []
        }

        let observations = request.results ?? []
        guard !observations.isEmpty else { return [] }

        return observations.map { observation in
            let normalized = observation.boundingBox
            let rect = CGRect(
                x: normalized.minX * canvasSize.width,
                y: (1 - normalized.maxY) * canvasSize.height,
                width: normalized.width * canvasSize.width,
                height: normalized.height * canvasSize.height
            )

            return rect
        }
    }

    private static func visionOrientation(for orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    private static func drawFramePattern(text: String, size: CGSize, scale: CGFloat) {
        let safeScale = max(scale, 0.45)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let inset = max(min(size.width, size.height) * 0.045 * safeScale, 18)
        let horizontalInset = max(inset * 0.60, 10)
        let lineColor = UIColor.systemPink.withAlphaComponent(0.16)
        let lineWidth = max(min(size.width, size.height) * 0.0042 * safeScale, 1.2)
        let horizontalFont = max(min(size.width, size.height) * 0.036 * safeScale, 15)
        let horizontalAttributes = watermarkAttributes(
            font: .systemFont(ofSize: horizontalFont, weight: .semibold),
            color: UIColor.systemPink.withAlphaComponent(0.22),
            shadowAlpha: 0.10
        )
        let topText = NSString(string: "♡ \(text)")
        let bottomText = NSString(string: "\(text) ♡")
        let centerText = NSString(string: "♡ \(text) ♡")
        let topSize = topText.size(withAttributes: horizontalAttributes)
        let bottomSize = bottomText.size(withAttributes: horizontalAttributes)
        let centerSize = centerText.size(withAttributes: horizontalAttributes)
        let heartAttributes = watermarkAttributes(
            font: .systemFont(ofSize: max(horizontalFont * 1.05, 18), weight: .regular),
            color: UIColor.systemPink.withAlphaComponent(0.18),
            shadowAlpha: 0.08
        )
        let heartText = NSString(string: "♡")
        let heartSize = heartText.size(withAttributes: heartAttributes)
        let topLineY = inset + max(topSize.height, heartSize.height) / 2
        let bottomLineY = size.height - inset - max(bottomSize.height, heartSize.height) / 2
        let topTextRect = CGRect(
            x: horizontalInset,
            y: topLineY - topSize.height / 2,
            width: topSize.width,
            height: topSize.height
        )
        let bottomTextRect = CGRect(
            x: size.width - horizontalInset - bottomSize.width,
            y: bottomLineY - bottomSize.height / 2,
            width: bottomSize.width,
            height: bottomSize.height
        )
        let leftLineX = topTextRect.minX + heartSize.width / 2
        let rightLineX = bottomTextRect.maxX - heartSize.width / 2
        let topRightHeartRect = CGRect(
            x: rightLineX - heartSize.width / 2,
            y: topLineY - heartSize.height / 2,
            width: heartSize.width,
            height: heartSize.height
        )
        let bottomLeftHeartRect = CGRect(
            x: leftLineX - heartSize.width / 2,
            y: bottomLineY - heartSize.height / 2,
            width: heartSize.width,
            height: heartSize.height
        )
        let leftCenterTextRect = CGRect(
            x: leftLineX - centerSize.height / 2,
            y: size.height / 2 - centerSize.width / 2,
            width: centerSize.height,
            height: centerSize.width
        )
        let rightCenterTextRect = CGRect(
            x: rightLineX - centerSize.height / 2,
            y: size.height / 2 - centerSize.width / 2,
            width: centerSize.height,
            height: centerSize.width
        )

        context.saveGState()
        context.setStrokeColor(lineColor.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)

        drawHorizontalLine(
            context: context,
            y: topLineY,
            from: horizontalInset,
            to: size.width - horizontalInset,
            excluding: topTextRect.insetBy(dx: -12 * safeScale, dy: -6 * safeScale),
            excluding2: topRightHeartRect.insetBy(dx: -10 * safeScale, dy: -6 * safeScale)
        )
        drawHorizontalLine(
            context: context,
            y: bottomLineY,
            from: horizontalInset,
            to: size.width - horizontalInset,
            excluding: bottomLeftHeartRect.insetBy(dx: -10 * safeScale, dy: -6 * safeScale),
            excluding2: bottomTextRect.insetBy(dx: -12 * safeScale, dy: -6 * safeScale)
        )
        drawVerticalLine(
            context: context,
            x: leftLineX,
            from: inset,
            to: size.height - inset,
            excludingRects: [
                topTextRect.insetBy(dx: -12 * safeScale, dy: -6 * safeScale),
                leftCenterTextRect.insetBy(dx: -10 * safeScale, dy: -6 * safeScale),
                bottomLeftHeartRect.insetBy(dx: -10 * safeScale, dy: -6 * safeScale)
            ]
        )
        drawVerticalLine(
            context: context,
            x: rightLineX,
            from: inset,
            to: size.height - inset,
            excludingRects: [
                topRightHeartRect.insetBy(dx: -10 * safeScale, dy: -6 * safeScale),
                rightCenterTextRect.insetBy(dx: -10 * safeScale, dy: -6 * safeScale),
                bottomTextRect.insetBy(dx: -12 * safeScale, dy: -6 * safeScale)
            ]
        )
        context.restoreGState()

        topText.draw(
            in: topTextRect,
            withAttributes: horizontalAttributes
        )
        bottomText.draw(
            in: bottomTextRect,
            withAttributes: horizontalAttributes
        )

        heartText.draw(in: topRightHeartRect, withAttributes: heartAttributes)
        heartText.draw(in: bottomLeftHeartRect, withAttributes: heartAttributes)

        context.saveGState()
        context.translateBy(x: leftLineX, y: size.height / 2)
        context.rotate(by: -.pi / 2)
        centerText.draw(
            in: CGRect(
                x: -centerSize.width / 2,
                y: -centerSize.height / 2,
                width: centerSize.width,
                height: centerSize.height
            ),
            withAttributes: horizontalAttributes
        )
        context.restoreGState()

        context.saveGState()
        context.translateBy(x: rightLineX, y: size.height / 2)
        context.rotate(by: .pi / 2)
        centerText.draw(
            in: CGRect(
                x: -centerSize.width / 2,
                y: -centerSize.height / 2,
                width: centerSize.width,
                height: centerSize.height
            ),
            withAttributes: horizontalAttributes
        )
        context.restoreGState()
    }

    private static func drawHorizontalLine(
        context: CGContext,
        y: CGFloat,
        from startX: CGFloat,
        to endX: CGFloat,
        excluding rect: CGRect,
        excluding2 rect2: CGRect
    ) {
        let ranges = [rect, rect2]
            .map { CGRect(x: max(startX, $0.minX), y: $0.minY, width: min(endX, $0.maxX) - max(startX, $0.minX), height: $0.height) }
            .filter { $0.width > 0 }
            .sorted { $0.minX < $1.minX }
        var currentStart = startX
        for range in ranges {
            if range.minX > currentStart {
                context.move(to: CGPoint(x: currentStart, y: y))
                context.addLine(to: CGPoint(x: range.minX, y: y))
                context.strokePath()
            }
            currentStart = max(currentStart, range.maxX)
        }
        if currentStart < endX {
            context.move(to: CGPoint(x: currentStart, y: y))
            context.addLine(to: CGPoint(x: endX, y: y))
            context.strokePath()
        }
    }

    private static func drawVerticalLine(
        context: CGContext,
        x: CGFloat,
        from startY: CGFloat,
        to endY: CGFloat,
        excludingRects rects: [CGRect]
    ) {
        let ranges = rects
            .map { CGRect(x: $0.minX, y: max(startY, $0.minY), width: $0.width, height: min(endY, $0.maxY) - max(startY, $0.minY)) }
            .filter { $0.height > 0 }
            .sorted { $0.minY < $1.minY }
        var currentStart = startY
        for range in ranges {
            if range.minY > currentStart {
                context.move(to: CGPoint(x: x, y: currentStart))
                context.addLine(to: CGPoint(x: x, y: range.minY))
                context.strokePath()
            }
            currentStart = max(currentStart, range.maxY)
        }
        if currentStart < endY {
            context.move(to: CGPoint(x: x, y: currentStart))
            context.addLine(to: CGPoint(x: x, y: endY))
            context.strokePath()
        }
    }

    private static func drawLogoPattern(text: String, size: CGSize, scale: CGFloat) {
        let safeScale = max(scale, 0.45)
        let largeFont = max(min(size.width, size.height) * 0.118 * safeScale, 28)
        let logoColor = UIColor(white: 0.66, alpha: 0.44)

        let mainAttributes = watermarkAttributes(
            font: .systemFont(ofSize: largeFont, weight: .black),
            color: logoColor,
            shadowAlpha: 0.10
        )

        let mainText = NSString(string: text)
        let mainSize = mainText.size(withAttributes: mainAttributes)
        let centerRect = CGRect(
            x: (size.width - mainSize.width) / 2,
            y: (size.height - mainSize.height) / 2,
            width: mainSize.width,
            height: mainSize.height
        )
        mainText.draw(in: centerRect, withAttributes: mainAttributes)
    }

    private static func watermarkAttributes(
        font: UIFont,
        color: UIColor,
        shadowAlpha: CGFloat,
        shadowBlurRadius: CGFloat = 8
    ) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let shadow = NSShadow()
        shadow.shadowBlurRadius = shadowBlurRadius
        shadow.shadowOffset = CGSize(width: 0, height: 2)
        shadow.shadowColor = UIColor.black.withAlphaComponent(shadowAlpha)

        return [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
            .shadow: shadow
        ]
    }
}

private struct ChekiSavePreviewCard: View {
    let image: UIImage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("プレビュー")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
        .padding(.vertical, 4)
    }
}

enum ChekiBatchImageRenderer {
    private struct StyledFrame {
        let rect: CGRect
        let rotation: CGFloat
    }

    private static let chekiAspectRatio: CGFloat = 5.0 / 7.0
    private static let baseOuterMargin: CGFloat = 72
    private static let baseItemSpacing: CGFloat = 36

    static func compositeImage(
        from images: [UIImage],
        style: ChekiBatchLayoutStyle = .grid,
        corkTextureStyle: ChekiCorkTextureStyle = .cork004,
        renderScale: CGFloat = 1.0,
        rendererScale: CGFloat? = nil
    ) -> UIImage? {
        let images = Array(images.prefix(9))
        guard !images.isEmpty else { return nil }
        if images.count == 1, style == .grid {
            return images[0]
        }

        let rows = layoutRows(for: images.count)
        let baseCanvasSize = canvasSize(for: rows)
        let effectiveRenderScale = min(max(renderScale, 0.2), 1.0)
        let canvasSize = CGSize(
            width: max(1, (baseCanvasSize.width * effectiveRenderScale).rounded()),
            height: max(1, (baseCanvasSize.height * effectiveRenderScale).rounded())
        )
        let layoutScale = canvasSize.width / baseCanvasSize.width
        let format = UIGraphicsImageRendererFormat.default()
        if let rendererScale {
            format.scale = rendererScale
        }
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)

        return renderer.image { context in
            let cgContext = context.cgContext
            drawBackground(
                for: style,
                corkTextureStyle: corkTextureStyle,
                imageCount: images.count,
                canvasSize: canvasSize,
                in: cgContext
            )

            let frames = styledFrames(for: rows, canvasSize: canvasSize, style: style, layoutScale: layoutScale)
            let commonPinDiameter = pinDiameter(for: frames, layoutScale: layoutScale)
            for (image, frame) in zip(images, frames) {
                drawCard(
                    image: image,
                    in: frame.rect,
                    rotation: frame.rotation,
                    style: style,
                    pinDiameter: commonPinDiameter,
                    layoutScale: layoutScale,
                    context: cgContext
                )
            }
        }
    }

    private static func drawBackground(
        for style: ChekiBatchLayoutStyle,
        corkTextureStyle: ChekiCorkTextureStyle,
        imageCount: Int,
        canvasSize: CGSize,
        in context: CGContext
    ) {
        let rect = CGRect(origin: .zero, size: canvasSize)

        switch style {
        case .grid:
            UIColor(red: 0.992, green: 0.977, blue: 0.984, alpha: 1.0).setFill()
            context.fill(rect)
        case .corkboard, .maskingTape:
            if let texture = UIImage(named: corkTextureStyle.imageName) {
                let zoom = corkTextureStyle.backgroundBaseZoomScale * backgroundZoomAdjustment(for: imageCount)
                if zoom > 1.001 {
                    let drawSize = CGSize(width: rect.width * zoom, height: rect.height * zoom)
                    let drawRect = CGRect(
                        x: rect.midX - drawSize.width / 2,
                        y: rect.midY - drawSize.height / 2,
                        width: drawSize.width,
                        height: drawSize.height
                    )
                    texture.draw(in: drawRect)
                } else {
                    texture.draw(in: rect)
                }
                UIColor(red: 0.89, green: 0.80, blue: 0.67, alpha: 0.14).setFill()
                context.fill(rect)
            } else {
                UIColor(red: 0.84, green: 0.73, blue: 0.60, alpha: 1.0).setFill()
                context.fill(rect)
            }
            context.saveGState()
            for _ in 0..<260 {
                let speckRect = CGRect(
                    x: CGFloat.random(in: 0...canvasSize.width),
                    y: CGFloat.random(in: 0...canvasSize.height),
                    width: CGFloat.random(in: 4...14),
                    height: CGFloat.random(in: 2...8)
                )
                UIColor.black.withAlphaComponent(CGFloat.random(in: 0.03...0.08)).setFill()
                context.fillEllipse(in: speckRect)
            }
            context.restoreGState()
        }
    }

    private static func backgroundZoomAdjustment(for imageCount: Int) -> CGFloat {
        switch imageCount {
        case 1...2:
            return 1.06
        case 3...4:
            return 1.00
        case 5...6:
            return 0.96
        default:
            return 0.92
        }
    }

    private static func layoutRows(for count: Int) -> [Int] {
        switch count {
        case 1: return [1]
        case 2: return [2]
        case 3: return [1, 2]
        case 4: return [2, 2]
        case 5: return [2, 1, 2]
        case 6: return [2, 2, 2]
        case 7: return [2, 3, 2]
        case 8: return [3, 2, 3]
        default: return [3, 3, 3]
        }
    }

    private static func canvasSize(for rows: [Int]) -> CGSize {
        switch rows {
        case [1]:
            return CGSize(width: 1600, height: 2200)
        case [2]:
            return CGSize(width: 1850, height: 1500)
        case [1, 2], [2, 2]:
            return CGSize(width: 1480, height: 2000)
        case [2, 1, 2], [2, 2, 2]:
            return CGSize(width: 1238, height: 2300)
        case [2, 3, 2], [3, 2, 3]:
            return CGSize(width: 1900, height: 2350)
        case [3, 3, 3]:
            return CGSize(width: 1668, height: 2250)
        default:
            return CGSize(width: 1800, height: 2200)
        }
    }

    private static func outerMargin(for layoutScale: CGFloat) -> CGFloat {
        max(baseOuterMargin * layoutScale, 18)
    }

    private static func itemSpacing(for layoutScale: CGFloat) -> CGFloat {
        max(baseItemSpacing * layoutScale, 10)
    }

    private static func itemFrames(for rows: [Int], canvasSize: CGSize, layoutScale: CGFloat) -> [CGRect] {
        let outerMargin = outerMargin(for: layoutScale)
        let itemSpacing = itemSpacing(for: layoutScale)
        let innerWidth = canvasSize.width - (outerMargin * 2)
        let innerHeight = canvasSize.height - (outerMargin * 2)
        let rowCount = CGFloat(rows.count)
        let maxColumns = CGFloat(rows.max() ?? 1)

        let widthByColumns: CGFloat
        if maxColumns <= 1 {
            widthByColumns = innerWidth
        } else {
            widthByColumns = (innerWidth - itemSpacing * (maxColumns - 1)) / maxColumns
        }

        let widthByRows = ((innerHeight - itemSpacing * (rowCount - 1)) / rowCount) * chekiAspectRatio

        var cardWidth = min(widthByColumns, widthByRows)
        if rows == [1] {
            cardWidth = min(innerWidth, innerHeight * chekiAspectRatio)
        }

        let cardHeight = cardWidth / chekiAspectRatio
        let totalHeight = (CGFloat(rows.count) * cardHeight) + (CGFloat(rows.count - 1) * itemSpacing)
        var currentY = (canvasSize.height - totalHeight) / 2
        var frames: [CGRect] = []

        for columns in rows {
            let totalRowWidth = (CGFloat(columns) * cardWidth) + (CGFloat(columns - 1) * itemSpacing)
            var currentX = (canvasSize.width - totalRowWidth) / 2

            for _ in 0..<columns {
                frames.append(CGRect(x: currentX, y: currentY, width: cardWidth, height: cardHeight))
                currentX += cardWidth + itemSpacing
            }

            currentY += cardHeight + itemSpacing
        }

        return frames
    }

    private static func styledFrames(
        for rows: [Int],
        canvasSize: CGSize,
        style: ChekiBatchLayoutStyle,
        layoutScale: CGFloat
    ) -> [StyledFrame] {
        let frames = itemFrames(for: rows, canvasSize: canvasSize, layoutScale: layoutScale)
        if frames.count == 1 {
            return frames.map { frame in
                StyledFrame(rect: frame, rotation: 0)
            }
        }
        let rotations: [CGFloat]
        let offsets: [CGSize]

        switch style {
        case .grid:
            rotations = Array(repeating: 0, count: frames.count)
            offsets = Array(repeating: .zero, count: frames.count)
        case .corkboard:
            rotations = [-0.06, 0.045, -0.035, 0.055, -0.04, 0.05, -0.03, 0.04, -0.025]
            offsets = [
                CGSize(width: -18, height: -8),
                CGSize(width: 16, height: 4),
                CGSize(width: -12, height: 8),
                CGSize(width: 14, height: -6),
                CGSize(width: -10, height: 6),
                CGSize(width: 12, height: -4),
                CGSize(width: -9, height: 6),
                CGSize(width: 10, height: -3),
                CGSize(width: -8, height: 5)
            ]
        case .maskingTape:
            rotations = [-0.025, 0.03, -0.02, 0.025, -0.03, 0.02, -0.018, 0.022, -0.02]
            offsets = [
                CGSize(width: -10, height: 0),
                CGSize(width: 10, height: -2),
                CGSize(width: -8, height: 4),
                CGSize(width: 8, height: -4),
                CGSize(width: -6, height: 2),
                CGSize(width: 6, height: -2),
                CGSize(width: -5, height: 3),
                CGSize(width: 5, height: -3),
                CGSize(width: -4, height: 2)
            ]
        }

        return frames.enumerated().map { index, frame in
            let offset = offsets[index]
            return StyledFrame(
                rect: frame.offsetBy(
                    dx: offset.width * layoutScale,
                    dy: offset.height * layoutScale
                ),
                rotation: rotations[index]
            )
        }
    }

    private static func drawCard(
        image: UIImage,
        in frame: CGRect,
        rotation: CGFloat,
        style: ChekiBatchLayoutStyle,
        pinDiameter: CGFloat,
        layoutScale: CGFloat,
        context: CGContext
    ) {
        context.saveGState()
        context.translateBy(x: frame.midX, y: frame.midY)
        context.rotate(by: rotation)
        context.translateBy(x: -frame.midX, y: -frame.midY)

        let imageSize = image.size
        let scale = min(frame.width / imageSize.width, frame.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let imageRect = CGRect(
            x: frame.midX - drawSize.width / 2,
            y: frame.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: max(10 * layoutScale, 4)),
            blur: max(24 * layoutScale, 10),
            color: UIColor.black.withAlphaComponent(0.20).cgColor
        )
        image.draw(in: imageRect)
        context.restoreGState()

        switch style {
        case .grid:
            break
        case .corkboard:
            drawPin(in: imageRect, diameter: pinDiameter, layoutScale: layoutScale, context: context)
        case .maskingTape:
            drawTape(in: imageRect, layoutScale: layoutScale, atLeft: true, context: context)
            drawTape(in: imageRect, layoutScale: layoutScale, atLeft: false, context: context)
        }

        context.restoreGState()
    }

    private static func pinDiameter(for frames: [StyledFrame], layoutScale: CGFloat) -> CGFloat {
        guard !frames.isEmpty else { return 24 * layoutScale }
        let averageTapeWidth = frames
            .map { tapeGeometry(in: $0.rect, atLeft: true).size.width }
            .reduce(0, +) / CGFloat(frames.count)
        return min(max(averageTapeWidth * 0.16, 14), 30)
    }

    private static func drawPin(in frame: CGRect, diameter: CGFloat, layoutScale: CGFloat, context: CGContext) {
        let point = CGPoint(x: frame.midX, y: frame.minY + diameter)
        let pinRect = CGRect(
            x: point.x - diameter / 2,
            y: point.y - diameter / 2,
            width: diameter,
            height: diameter
        )
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: max(2 * layoutScale, 1)),
            blur: max(4 * layoutScale, 2),
            color: UIColor.black.withAlphaComponent(0.18).cgColor
        )
        UIColor(red: 0.93, green: 0.20, blue: 0.39, alpha: 1.0).setFill()
        context.fillEllipse(in: pinRect)
        context.restoreGState()

        UIColor.white.withAlphaComponent(0.35).setFill()
        let highlightDiameter = diameter * 0.38
        context.fillEllipse(in: CGRect(
            x: point.x - highlightDiameter * 0.55,
            y: point.y - highlightDiameter * 0.75,
            width: highlightDiameter,
            height: highlightDiameter
        ))
    }

    private static func drawTape(
        in frame: CGRect,
        layoutScale: CGFloat,
        atLeft: Bool,
        context: CGContext
    ) {
        let geometry = tapeGeometry(in: frame, atLeft: atLeft)
        let point = geometry.center
        let angle = geometry.angle
        let tapeSize = geometry.size
        let tapeHeight = tapeSize.height
        let tapeRect = CGRect(
            x: point.x - tapeSize.width / 2,
            y: point.y - tapeSize.height / 2,
            width: tapeSize.width,
            height: tapeSize.height
        )

        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        context.rotate(by: angle)
        context.translateBy(x: -point.x, y: -point.y)
        context.setShadow(
            offset: CGSize(width: 0, height: max(2 * layoutScale, 1)),
            blur: max(3 * layoutScale, 1.5),
            color: UIColor.black.withAlphaComponent(0.10).cgColor
        )
        UIColor(red: 0.98, green: 0.88, blue: 0.63, alpha: 0.88).setFill()
        UIBezierPath(roundedRect: tapeRect, cornerRadius: tapeHeight * 0.2).fill()
        context.restoreGState()
    }

    private static func tapeGeometry(in frame: CGRect, atLeft: Bool) -> (size: CGSize, center: CGPoint, angle: CGFloat) {
        let startPoint: CGPoint
        let endPoint: CGPoint

        if atLeft {
            startPoint = CGPoint(
                x: frame.minX - (frame.width * 0.025),
                y: frame.minY + (frame.height * 0.06)
            )
            endPoint = CGPoint(
                x: frame.minX + (frame.width * 0.17),
                y: frame.minY
            )
        } else {
            startPoint = CGPoint(
                x: frame.maxX - (frame.width * 0.17),
                y: frame.minY
            )
            endPoint = CGPoint(
                x: frame.maxX + (frame.width * 0.025),
                y: frame.minY + (frame.height * 0.06)
            )
        }

        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let tapeWidth = hypot(dx, dy)
        let tapeHeight = tapeWidth * 0.34
        let center = CGPoint(
            x: (startPoint.x + endPoint.x) / 2,
            y: (startPoint.y + endPoint.y) / 2
        )
        let angle = atan2(dy, dx)

        return (
            size: CGSize(width: tapeWidth, height: tapeHeight),
            center: center,
            angle: angle
        )
    }
}

private enum ChekiSaveCompositeRenderer {
    private static let previewMaxPixelSize: CGFloat = 720
    private static let previewCompositeRenderScale: CGFloat = 0.36

    private static func previewCacheKey(for data: Data, maxPixelSize: CGFloat) -> String {
        let prefix = data.prefix(16).map { String(format: "%02x", $0) }.joined()
        return "cheki-save-preview-\(data.count)-\(Int(maxPixelSize.rounded()))-\(prefix)"
    }

    static func previewImage(
        from imageDataList: [Data],
        settings: ChekiSaveSettings,
        watermarkScale: CGFloat
    ) -> UIImage? {
        outputImage(
            from: imageDataList,
            settings: settings,
            watermarkScale: watermarkScale,
            maxPixelSize: previewMaxPixelSize,
            useCacheForDecodedImages: true
        )
    }

    static func saveImage(
        from imageDataList: [Data],
        settings: ChekiSaveSettings,
        watermarkScale: CGFloat
    ) -> UIImage? {
        outputImage(
            from: imageDataList,
            settings: settings,
            watermarkScale: watermarkScale,
            maxPixelSize: saveMaxPixelSize(for: imageDataList.count, style: settings.batchLayoutStyle),
            useCacheForDecodedImages: false
        )
    }

    static func outputImage(
        from imageDataList: [Data],
        settings: ChekiSaveSettings,
        watermarkScale: CGFloat,
        maxPixelSize: CGFloat? = nil,
        useCacheForDecodedImages: Bool = true
    ) -> UIImage? {
        var imagesForLayout: [UIImage] = []
        imagesForLayout.reserveCapacity(imageDataList.count)

        for data in imageDataList {
            let decodedImage: UIImage? = autoreleasepool {
                if let maxPixelSize {
                    return DownsampledImageLoader.loadImage(
                        data: data,
                        cacheKey: previewCacheKey(for: data, maxPixelSize: maxPixelSize),
                        maxPixelSize: maxPixelSize,
                        useCache: useCacheForDecodedImages
                    )
                }
                return UIImage(data: data)
            }

            guard let decodedImage else { continue }

            let outputImage: UIImage
            if settings.isWatermarkEnabled {
                outputImage = autoreleasepool {
                    ChekiWatermarkRenderer.watermarkedImage(
                        from: decodedImage,
                        settings: settings,
                        scale: watermarkScale
                    )
                }
            } else {
                outputImage = decodedImage
            }

            imagesForLayout.append(outputImage)
        }

        guard !imagesForLayout.isEmpty else { return nil }

        return ChekiBatchImageRenderer.compositeImage(
            from: imagesForLayout,
            style: settings.batchLayoutStyle,
            corkTextureStyle: settings.corkTextureStyle,
            renderScale: maxPixelSize == nil ? 1.0 : previewCompositeRenderScale,
            rendererScale: maxPixelSize == nil ? nil : 1.0
        )
    }

    private static func saveMaxPixelSize(for imageCount: Int, style: ChekiBatchLayoutStyle) -> CGFloat {
        switch imageCount {
        case ...1:
            return style == .grid ? 2200 : 2000
        case 2:
            return 1800
        case 3...4:
            return 1600
        case 5...6:
            return 1400
        default:
            return 1280
        }
    }
}

enum OshiKind: String, Codable, CaseIterable, Identifiable {
    case person
    case group

    var id: String { rawValue }
    var title: String {
        switch self {
        case .person: return "個人"
        case .group: return "箱推し"
        }
    }
}

struct Oshi: Identifiable, Equatable, Codable {
    var id = UUID()
    var agencyId: String?
    var groupId: String?
    var masterId: String?
    var kind: OshiKind = .person
    var name: String
    var group: String
    var startDate: Date
    var colorHex: String
    var imageURL: String
    var selectedImageFileName: String?
    var localImageData: Data?
    var iconThumbnailData: Data?
    var originalImageData: Data?
    var backgroundImageData: Data?
    var isTextColorManual: Bool = false
    var textColorHex: String?
    var imagePlacement: OshiImagePlacement = .default
    var birthday: String?
    var seitansaiDate: Date?
    var debutDate: Date?
    var isDisplayed: Bool = true
    var isEffectEnabled: Bool = true // 背景エフェクトON/OFF
    var twitterID: String?
    var instagramID: String?
    var tiktokID: String?
    var timeTreeURL: String?

    var color: Color {
        let hex = colorHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b: UInt64
        switch hex.count {
        case 3:
            (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (128, 128, 128)
        }

        return Color(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }

    var textColor: Color {
        if isTextColorManual, let textColorHex, !textColorHex.isEmpty {
            return Color(hex: textColorHex)
        }
        return ColorUtils.recommendedTextColor(backgroundImageData: backgroundImageData, fallbackColor: color)
    }
    
    // 推し始めて何日
    var daysCount: Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: startDate), to: calendar.startOfDay(for: Date())).day ?? 0
    }
    
    // 🎂 誕生日カウントダウン
    var daysUntilBirthday: Int? {
        guard let birthday = birthday, !birthday.isEmpty else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let f = DateFormatter(); f.dateFormat = "MM-dd"
        guard let bDayThisYear = f.date(from: birthday) else { return nil }
        var comps = calendar.dateComponents([.month, .day], from: bDayThisYear)
        comps.year = calendar.component(.year, from: today)
        guard var next = calendar.date(from: comps) else { return nil }
        if next < today { next = calendar.date(byAdding: .year, value: 1, to: next)! }
        return calendar.dateComponents([.day], from: today, to: next).day
    }
    
    // 🎉 生誕祭カウントダウン
    var daysUntilSeitansai: Int? {
        guard let event = seitansaiDate else { return nil }
        let diff = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: event)).day ?? 0
        return diff >= 0 ? diff : nil
    }

    // 生誕祭当日を過ぎたか判定
    var isSeitansaiActive: Bool {
        guard let event = seitansaiDate else { return false }
        return Calendar.current.startOfDay(for: event) >= Calendar.current.startOfDay(for: Date())
    }
    
    // 🌟 次の周年記念日までの日数
    var daysUntilDebut: Int? {
        guard let debut = debutDate else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var comps = calendar.dateComponents([.month, .day], from: debut)
        comps.year = calendar.component(.year, from: today)
        guard var next = calendar.date(from: comps) else { return nil }
        if next < today { next = calendar.date(byAdding: .year, value: 1, to: next)! }
        return calendar.dateComponents([.day], from: today, to: next).day
    }

    // 🌟 次が何周年目か
    var nextAnniversaryCount: Int? {
        guard let debut = debutDate else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let debutYear = calendar.component(.year, from: debut)
        var count = calendar.component(.year, from: today) - debutYear
        var comps = calendar.dateComponents([.month, .day], from: debut)
        comps.year = calendar.component(.year, from: today)
        if let thisYear = calendar.date(from: comps), thisYear < today { count += 1 }
        return max(count, 1)
    }

    // 💝 推し記念日カウントダウン
    var daysUntilAnniversary: Int? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var comps = calendar.dateComponents([.month, .day], from: startDate)
        comps.year = calendar.component(.year, from: today)
        guard var next = calendar.date(from: comps) else { return nil }
        if next < today { next = calendar.date(byAdding: .year, value: 1, to: next)! }
        return calendar.dateComponents([.day], from: today, to: next).day
    }

    // 💝 推し何周年目か
    var nextAnniversaryYear: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startYear = calendar.component(.year, from: startDate)
        var count = calendar.component(.year, from: today) - startYear
        var comps = calendar.dateComponents([.month, .day], from: startDate)
        comps.year = calendar.component(.year, from: today)
        if let thisYear = calendar.date(from: comps), thisYear < today { count += 1 }
        return max(count, 1)
    }

    // 💝 今日が何か月記念か
    var currentMonthlyAnniversaryCount: Int? {
        guard let startOfDay = monthlyAnniversaryStartOfDay else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let elapsedMonths = calendar.dateComponents([.month], from: startOfDay, to: today).month ?? 0
        guard let currentMonthlyDate = calendar.date(byAdding: .month, value: elapsedMonths, to: startOfDay) else {
            return nil
        }
        if currentMonthlyDate == today && elapsedMonths > 0 {
            return elapsedMonths
        }
        return nil
    }

    private var monthlyAnniversaryStartOfDay: Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.startOfDay(for: startDate)
        return start <= today ? start : nil
    }
    // 今日が何かの記念日か（キラキラ判定用）
    var isAnyAnniversaryToday: Bool {
        daysUntilBirthday == 0 || daysUntilSeitansai == 0 || daysUntilDebut == 0 || daysUntilAnniversary == 0
    }

    var resolvedRemoteImageURL: String {
        if let selectedImageFileName,
           let agencyId, !agencyId.isEmpty,
           let masterId, !masterId.isEmpty,
           !selectedImageFileName.isEmpty {
            return AppConfig.candidateImageURL(
                agencyId: agencyId,
                masterId: masterId,
                fileName: selectedImageFileName
            )
        }
        return imageURL
    }

    // デコード（古いデータとの互換性確保）
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        agencyId = try container.decodeIfPresent(String.self, forKey: .agencyId)
        groupId = try container.decodeIfPresent(String.self, forKey: .groupId)
        masterId = try container.decodeIfPresent(String.self, forKey: .masterId)
        kind = try container.decodeIfPresent(OshiKind.self, forKey: .kind) ?? .person
        name = try container.decode(String.self, forKey: .name)
        group = try container.decode(String.self, forKey: .group)
        startDate = try container.decode(Date.self, forKey: .startDate)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        imageURL = try container.decode(String.self, forKey: .imageURL)
        selectedImageFileName = try container.decodeIfPresent(String.self, forKey: .selectedImageFileName)
        localImageData = try container.decodeIfPresent(Data.self, forKey: .localImageData)
        imagePlacement = try container.decodeIfPresent(OshiImagePlacement.self, forKey: .imagePlacement) ?? .default
        iconThumbnailData = try container.decodeIfPresent(Data.self, forKey: .iconThumbnailData)
            ?? OshiIconThumbnailHelper.thumbnailData(from: localImageData, placement: imagePlacement)
        originalImageData = try container.decodeIfPresent(Data.self, forKey: .originalImageData)
        backgroundImageData = try container.decodeIfPresent(Data.self, forKey: .backgroundImageData)
        textColorHex = try container.decodeIfPresent(String.self, forKey: .textColorHex)
        isTextColorManual = try container.decodeIfPresent(Bool.self, forKey: .isTextColorManual) ?? (textColorHex?.isEmpty == false)
        birthday = try container.decodeIfPresent(String.self, forKey: .birthday)
        seitansaiDate = try container.decodeIfPresent(Date.self, forKey: .seitansaiDate)
        debutDate = try container.decodeIfPresent(Date.self, forKey: .debutDate)
        isDisplayed = try container.decodeIfPresent(Bool.self, forKey: .isDisplayed) ?? true
        twitterID = try container.decodeIfPresent(String.self, forKey: .twitterID)
        instagramID = try container.decodeIfPresent(String.self, forKey: .instagramID)
        tiktokID = try container.decodeIfPresent(String.self, forKey: .tiktokID)
        timeTreeURL = try container.decodeIfPresent(String.self, forKey: .timeTreeURL)
        // ★ここ：古いデータに項目がなくても強制的にtrueにする
        isEffectEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEffectEnabled) ?? true
    }

    // 保存や新規作成用のイニシャライザ
    init(id: UUID = UUID(),
         agencyId: String? = nil,
         groupId: String? = nil,
         masterId: String? = nil,
         kind: OshiKind = .person,
         name: String,
         group: String,
         startDate: Date,
         colorHex: String,
         imageURL: String,
         selectedImageFileName: String? = nil,
         localImageData: Data? = nil,
         iconThumbnailData: Data? = nil,
         originalImageData: Data? = nil, // ★ここを追加
         backgroundImageData: Data? = nil,
         isTextColorManual: Bool = false,
         textColorHex: String? = nil,
         imagePlacement: OshiImagePlacement = .default,
         birthday: String? = nil,
         seitansaiDate: Date? = nil,
         debutDate: Date? = nil,
         isDisplayed: Bool = true,
         isEffectEnabled: Bool = true,
         twitterID: String? = nil,
         instagramID: String? = nil,
         tiktokID: String? = nil,
         timeTreeURL: String? = nil) {
         
        self.id = id
        self.agencyId = agencyId
        self.groupId = groupId
        self.masterId = masterId
        self.kind = kind
        self.name = name
        self.group = group
        self.startDate = startDate
        self.colorHex = colorHex
        self.imageURL = imageURL
        self.selectedImageFileName = selectedImageFileName
        self.localImageData = localImageData
        self.iconThumbnailData = iconThumbnailData
        self.originalImageData = originalImageData // ★ここを追加
        self.backgroundImageData = backgroundImageData
        self.isTextColorManual = isTextColorManual
        self.textColorHex = textColorHex
        self.imagePlacement = imagePlacement
        self.birthday = birthday
        self.seitansaiDate = seitansaiDate
        self.debutDate = debutDate
        self.isDisplayed = isDisplayed
        self.isEffectEnabled = isEffectEnabled
        self.twitterID = twitterID
        self.instagramID = instagramID
        self.tiktokID = tiktokID
        self.timeTreeURL = timeTreeURL
    }
}

// MARK: - 2. 画像管理
class LocalImageManager {
    static let instance = LocalImageManager()
    func saveImage(url: String) {
        guard let imageURL = URL(string: url), !url.isEmpty else { return }
        let path = getFilePath(fileName: getFileName(url: url))
        if FileManager.default.fileExists(atPath: path.path) { return }
        URLSession.shared.dataTask(with: imageURL) { d, _, _ in if let data = d { try? data.write(to: path) } }.resume()
    }
    func loadImage(url: String) -> UIImage? {
        if url.isEmpty { return nil }
        let path = getFilePath(fileName: getFileName(url: url))
        if let d = try? Data(contentsOf: path) { return UIImage(data: d) }
        return nil
    }
    func loadImageData(url: String) -> Data? {
        if url.isEmpty { return nil }
        let path = getFilePath(fileName: getFileName(url: url))
        return try? Data(contentsOf: path)
    }
    func saveImageData(_ data: Data, url: String) {
        guard !url.isEmpty else { return }
        let path = getFilePath(fileName: getFileName(url: url))
        try? data.write(to: path, options: .atomic)
    }
    private func getFileName(url: String) -> String { url.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_") }
    private func getFilePath(fileName: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent(fileName)
    }
}

final class MemoryImageCache {
    static let shared = MemoryImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private var notificationTokens: [NSObjectProtocol] = []

    private init() {
        cache.countLimit = 80
        cache.totalCostLimit = 40 * 1024 * 1024
        let center = NotificationCenter.default
        notificationTokens.append(
            center.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.removeAll()
            }
        )
        notificationTokens.append(
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.removeAll()
            }
        )
    }

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func set(_ image: UIImage, for key: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

final class DownsampledImageCache {
    static let shared = DownsampledImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private var notificationTokens: [NSObjectProtocol] = []

    private init() {
        cache.countLimit = 100
        cache.totalCostLimit = 28 * 1024 * 1024
        let center = NotificationCenter.default
        notificationTokens.append(
            center.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.removeAll()
            }
        )
        notificationTokens.append(
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.removeAll()
            }
        )
    }

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func set(_ image: UIImage, for key: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

enum DownsampledImageLoader {
    static func loadImage(data: Data, cacheKey: String, maxPixelSize: CGFloat, useCache: Bool = true) -> UIImage? {
        if useCache, let cached = DownsampledImageCache.shared.image(for: cacheKey) {
            return cached
        }

        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]

        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return UIImage(data: data)
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixelSize.rounded(.up)))
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return UIImage(data: data)
        }

        let image = UIImage(cgImage: cgImage)
        if useCache {
            DownsampledImageCache.shared.set(image, for: cacheKey)
        }
        return image
    }
}

private struct DownsampledDataImage: View {
    let cacheKey: String
    let data: Data
    let maxPixelSize: CGFloat
    let contentMode: ContentMode

    @State private var image: UIImage? = nil

    init(
        cacheKey: String,
        data: Data,
        maxPixelSize: CGFloat,
        contentMode: ContentMode
    ) {
        self.cacheKey = cacheKey
        self.data = data
        self.maxPixelSize = maxPixelSize
        self.contentMode = contentMode
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle()
                    .fill(Color(.systemGray6))
                    .overlay(ProgressView())
            }
        }
        .task(id: cacheKey) {
            if let cached = DownsampledImageCache.shared.image(for: cacheKey) {
                image = cached
                return
            }

            image = DownsampledImageLoader.loadImage(
                data: data,
                cacheKey: cacheKey,
                maxPixelSize: maxPixelSize
            )
        }
    }
}

struct OshiImagePlacement: Codable, Equatable {
    var scale: Double = 1
    var offsetXRatio: Double = 0
    var offsetYRatio: Double = 0

    static let `default` = OshiImagePlacement()
}

private enum OshiIconThumbnailHelper {
    static let pixelSize: CGFloat = 400
    static let compressionQuality: CGFloat = 0.82

    static func thumbnailData(from data: Data?, placement: OshiImagePlacement) -> Data? {
        guard let data, let image = UIImage(data: data) else { return nil }
        let rendered = renderedImage(from: image, placement: placement)
        return rendered.jpegData(compressionQuality: compressionQuality)
    }

    static func renderedImage(from image: UIImage, placement: OshiImagePlacement) -> UIImage {
        let canvasSize = CGSize(width: pixelSize, height: pixelSize)
        let frameSize = canvasSize
        let fillScale = max(
            frameSize.width / max(image.size.width, 1),
            frameSize.height / max(image.size.height, 1)
        )
        let displayedSize = CGSize(
            width: image.size.width * fillScale * placement.scale,
            height: image.size.height * fillScale * placement.scale
        )
        let isPortrait = image.size.height > image.size.width
        let baseOrigin = CGPoint(
            x: (frameSize.width - displayedSize.width) / 2,
            y: isPortrait ? 0 : (frameSize.height - displayedSize.height) / 2
        )
        let desiredOrigin = CGPoint(
            x: baseOrigin.x + (placement.offsetXRatio * frameSize.width),
            y: baseOrigin.y + (placement.offsetYRatio * frameSize.height)
        )
        let clampedOrigin = CGPoint(
            x: min(max(desiredOrigin.x, frameSize.width - displayedSize.width), 0),
            y: min(max(desiredOrigin.y, frameSize.height - displayedSize.height), 0)
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1

        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { _ in
            UIColor.clear.setFill()
            UIRectFill(CGRect(origin: .zero, size: canvasSize))
            image.draw(in: CGRect(origin: clampedOrigin, size: displayedSize))
        }
    }
}

// MARK: - 3. ビューパーツ (OshiImage, CachedOshiImage)
struct OshiFilledUIImageView: View {
    let image: UIImage
    let size: CGFloat
    let placement: OshiImagePlacement

    var body: some View {
        OshiPlacementPreviewImageView(
            image: image,
            canvasSize: CGSize(width: size, height: size),
            placement: placement
        )
    }
}

struct OshiPlacementPreviewImageView: View {
    enum BaseScaleMode {
        case fill
        case fit
    }

    let image: UIImage
    let canvasSize: CGSize
    let placement: OshiImagePlacement
    let baseScaleMode: BaseScaleMode

    init(
        image: UIImage,
        canvasSize: CGSize,
        placement: OshiImagePlacement,
        baseScaleMode: BaseScaleMode = BaseScaleMode.fill
    ) {
        self.image = image
        self.canvasSize = canvasSize
        self.placement = placement
        self.baseScaleMode = baseScaleMode
    }

    private var contentAlignment: Alignment {
        image.size.height > image.size.width ? .top : .center
    }

    var body: some View {
        GeometryReader { proxy in
            let frameSize = proxy.size
            let fillScale = max(
                frameSize.width / max(image.size.width, 1),
                frameSize.height / max(image.size.height, 1)
            )
            let fitScale = min(
                frameSize.width / max(image.size.width, 1),
                frameSize.height / max(image.size.height, 1)
            )
            let baseScale = baseScaleMode == BaseScaleMode.fill ? fillScale : fitScale
            let displayedSize = CGSize(
                width: image.size.width * baseScale * placement.scale,
                height: image.size.height * baseScale * placement.scale
            )
            let baseOrigin = CGPoint(
                x: (frameSize.width - displayedSize.width) / 2,
                y: contentAlignment == .top ? 0 : (frameSize.height - displayedSize.height) / 2
            )
            let desiredOrigin = CGPoint(
                x: baseOrigin.x + (placement.offsetXRatio * frameSize.width),
                y: baseOrigin.y + (placement.offsetYRatio * frameSize.height)
            )
            let clampedOrigin = CGPoint(
                x: clamp(desiredOrigin.x, lower: frameSize.width - displayedSize.width, upper: 0),
                y: clamp(desiredOrigin.y, lower: frameSize.height - displayedSize.height, upper: 0)
            )

            Image(uiImage: image)
                .resizable()
                .frame(width: displayedSize.width, height: displayedSize.height)
                .offset(x: clampedOrigin.x, y: clampedOrigin.y)
                .frame(width: frameSize.width, height: frameSize.height, alignment: .topLeading)
                .clipped()
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    private func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}

struct OshiImage: View {
    let oshi: Oshi
    let size: CGFloat

    var body: some View {
        Group {
            if let data = oshi.iconThumbnailData {
                CachedMemoryUIImageView(
                    cacheKey: "oshi-icon-\(oshi.id.uuidString)-\(imageDataFingerprint(data))",
                    data: data
                ) { ui in
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                }
            } else if let data = oshi.localImageData {
                CachedMemoryUIImageView(
                    cacheKey: "oshi-local-\(oshi.id.uuidString)-\(imageDataFingerprint(data))",
                    data: data
                ) { ui in
                    OshiFilledUIImageView(image: ui, size: size, placement: oshi.imagePlacement)
                }
            } else {
                CachedOshiImage(url: oshi.resolvedRemoteImageURL, size: size, placement: oshi.imagePlacement)
            }
        }
        .frame(width: size, height: size) // ここで枠のサイズを固定
        .clipShape(Circle()) // ★ ここ！これで丸く切り抜いてはみ出しを防ぎます
    }
}

private struct CachedMemoryUIImageView<Content: View>: View {
    let cacheKey: String
    let data: Data
    let content: (UIImage) -> Content

    @State private var image: UIImage? = nil

    init(
        cacheKey: String,
        data: Data,
        @ViewBuilder content: @escaping (UIImage) -> Content
    ) {
        self.cacheKey = cacheKey
        self.data = data
        self.content = content
    }

    var body: some View {
        Group {
            if let image {
                content(image)
            } else {
                Rectangle()
                    .fill(Color(.systemGray6))
                    .overlay(ProgressView())
            }
        }
        .task(id: cacheKey) {
            if let cached = MemoryImageCache.shared.image(for: cacheKey) {
                image = cached
                return
            }

            guard let decoded = UIImage(data: data) else {
                image = nil
                return
            }

            MemoryImageCache.shared.set(decoded, for: cacheKey)
            image = decoded
        }
    }
}

struct OshiOriginalImage: View {
    let oshi: Oshi

    var body: some View {
        Group {
            if let data = oshi.localImageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
            } else if oshi.resolvedRemoteImageURL.isEmpty {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.gray)
            } else {
                AsyncImage(url: URL(string: oshi.resolvedRemoteImageURL)) { phase in
                    switch phase {
                    case .success(let img):
                        img
                            .resizable()
                            .scaledToFit()
                    case .failure(_):
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.gray)
                    case .empty:
                        ProgressView()
                    @unknown default:
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.gray)
                    }
                }
            }
        }
    }
}

struct CachedOshiImage: View {
    let url: String
    let size: CGFloat
    let placement: OshiImagePlacement

    @State private var image: UIImage? = nil
    @State private var hasFailed = false

    var body: some View {
        Group {
            if let uiImage = image {
                OshiFilledUIImageView(image: uiImage, size: size, placement: placement)
            } else if hasFailed {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundColor(.gray)
            } else if url.isEmpty {
                Image(systemName: "person.circle.fill").resizable().foregroundColor(.gray)
            }
            else {
                ZStack {
                    Circle()
                        .fill(Color(.systemGray6))
                    ProgressView()
                }
            }
        }
        .frame(width: size, height: size)
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        hasFailed = false

        if let cached = LocalImageManager.instance.loadImage(url: url) {
            image = cached
            return
        }

        guard !url.isEmpty, let imageURL = URL(string: url) else {
            image = nil
            hasFailed = true
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: imageURL)
            guard !Task.isCancelled else { return }
            guard let decoded = UIImage(data: data) else {
                image = nil
                hasFailed = true
                return
            }
            LocalImageManager.instance.saveImageData(data, url: url)
            image = decoded
        } catch {
            image = nil
            hasFailed = true
        }
    }
}

private struct CachedCandidatePreviewImage: View {
    let url: String

    @State private var image: UIImage? = nil
    @State private var hasFailed = false

    private let maxPixelSize: CGFloat = 900

    private var cacheKey: String {
        "candidate-preview:\(url):\(Int(maxPixelSize))"
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if hasFailed {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.systemGray5))
                    .overlay(
                        Image(systemName: "person.crop.square")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    )
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.systemGray6))
                    .overlay(ProgressView())
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        hasFailed = false

        if let cached = DownsampledImageCache.shared.image(for: cacheKey) {
            image = cached
            return
        }

        if let cachedData = LocalImageManager.instance.loadImageData(url: url),
           let cached = DownsampledImageLoader.loadImage(
            data: cachedData,
            cacheKey: cacheKey,
            maxPixelSize: maxPixelSize
           ) {
            image = cached
            return
        }

        guard !url.isEmpty, let imageURL = URL(string: url) else {
            image = nil
            hasFailed = true
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: imageURL)
            guard !Task.isCancelled else { return }
            LocalImageManager.instance.saveImageData(data, url: url)
            guard let decoded = DownsampledImageLoader.loadImage(
                data: data,
                cacheKey: cacheKey,
                maxPixelSize: maxPixelSize
            ) else { return }
            image = decoded
        } catch {
            image = nil
            hasFailed = true
        }
    }
}

private struct OshiImageCandidateCard: View {
    let candidate: OshiImageCandidateOption
    let primaryText: String
    let secondaryText: String?
    let isSelected: Bool
    let cornerRadius: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CachedCandidatePreviewImage(url: candidate.url)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 160, maxHeight: 280)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.systemGray6))
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))

            Text(primaryText)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(2)

            if let secondaryText {
                Text(secondaryText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    isSelected ? Color.accentColor : Color.clear,
                    lineWidth: 2
                )
        )
    }
}

private struct CandidateLoadMoreButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("候補をもっと表示する")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct OshiImageCandidatePickerSheetView: View {
    let candidates: [OshiImageCandidateOption]
    let selectedFileName: String?
    let canShowMore: Bool
    let onSelect: (OshiImageCandidateOption) -> Void
    let onShowMore: () -> Void
    let primaryLabel: (OshiImageCandidateOption) -> String
    let secondaryLabel: (OshiImageCandidateOption) -> String?

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let horizontalPadding: CGFloat = 16
                let gridSpacing: CGFloat = 16
                let columns = makeCandidatePickerColumns(
                    containerWidth: proxy.size.width,
                    horizontalPadding: horizontalPadding,
                    gridSpacing: gridSpacing
                )

                ScrollView {
                    VStack(spacing: 0) {
                        LazyVGrid(columns: columns, spacing: gridSpacing) {
                            ForEach(candidates) { candidate in
                                Button {
                                    onSelect(candidate)
                                } label: {
                                    OshiImageCandidateCard(
                                        candidate: candidate,
                                        primaryText: primaryLabel(candidate),
                                        secondaryText: secondaryLabel(candidate),
                                        isSelected: selectedFileName == candidate.fileName,
                                        cornerRadius: 18
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if canShowMore {
                            CandidateLoadMoreButton(action: onShowMore)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("候補から選択")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private func makeCandidatePickerColumns(
    containerWidth: CGFloat,
    horizontalPadding: CGFloat = 16,
    gridSpacing: CGFloat = 16,
    cardMinWidth: CGFloat = 180,
    requireRegularWidthClass: Bool = false,
    horizontalSizeClass: UserInterfaceSizeClass? = nil
) -> [GridItem] {
    let availableWidth = max(containerWidth - (horizontalPadding * 2), 0)
    let canUseTwoColumns = availableWidth >= ((cardMinWidth * 2) + gridSpacing)
    let shouldUseTwoColumns: Bool
    if requireRegularWidthClass {
        shouldUseTwoColumns = horizontalSizeClass == .regular && canUseTwoColumns
    } else {
        shouldUseTwoColumns = canUseTwoColumns
    }

    return Array(
        repeating: GridItem(.flexible(), spacing: gridSpacing, alignment: .top),
        count: shouldUseTwoColumns ? 2 : 1
    )
}

struct OshiImagePlacementEditorView: View {
    enum PreviewMode: String, CaseIterable, Identifiable {
        case circle
        case full

        var id: String { rawValue }

        var title: String {
            switch self {
            case .circle: return "丸で確認"
            case .full: return "全体で確認"
            }
        }
    }

    let image: UIImage
    let initialPlacement: OshiImagePlacement
    let onApply: (OshiImagePlacement) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var previewMode: PreviewMode = .full
    @State private var workingPlacement: OshiImagePlacement
    @State private var dragBasePlacement: OshiImagePlacement?
    @State private var scaleBase: Double?
    @State private var previewInteractionResetToken = UUID()

    private let previewSize: CGFloat = 280
    private let fullPreviewMaxWidth: CGFloat = 320
    private let fullPreviewMaxHeight: CGFloat = 480

    init(image: UIImage, initialPlacement: OshiImagePlacement, onApply: @escaping (OshiImagePlacement) -> Void) {
        self.image = image
        self.initialPlacement = initialPlacement
        self.onApply = onApply
        _workingPlacement = State(initialValue: initialPlacement)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    previewModePicker
                        .zIndex(2)

                    previewCanvas
                        .id(previewInteractionResetToken)
                        .frame(width: previewCanvasSize.width, height: previewCanvasSize.height)
                        .clipped()
                        .overlay {
                            Rectangle()
                                .fill(Color.clear)
                                .id(previewInteractionResetToken)
                                .contentShape(Rectangle())
                                .gesture(magnificationGesture)
                                .simultaneousGesture(dragGesture)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: previewStageHeight, alignment: .top)
                        .zIndex(1)

                    VStack(spacing: 14) {
                        VStack(spacing: 8) {
                            Text("ドラッグで位置を調整")
                                .font(.subheadline.bold())
                            Text("ピンチで拡大縮小")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 12) {
                            Button("初期位置") {
                                workingPlacement = .default
                                dragBasePlacement = nil
                                scaleBase = nil
                                previewInteractionResetToken = UUID()
                            }
                            .buttonStyle(.bordered)

                            Button("リセット") {
                                workingPlacement = initialPlacement
                                dragBasePlacement = nil
                                scaleBase = nil
                                previewInteractionResetToken = UUID()
                            }
                            .buttonStyle(.bordered)

                            Button("保存") {
                                onApply(workingPlacement)
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )

                    Spacer(minLength: 0)
                }
            }
            .interactiveDismissDisabled()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 16)
            .padding(.top, 32)
            .padding(.bottom, 24)
            .navigationTitle("写真の位置を調整")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var orderedPreviewModes: [PreviewMode] {
        [.full, .circle]
    }

    private var previewCanvasSize: CGSize {
        fullPreviewFrameSize
    }

    private var gestureCanvasSize: CGSize {
        previewMode == .full
            ? fullPreviewFrameSize
            : CGSize(width: circlePreviewDiameter, height: circlePreviewDiameter)
    }

    private var previewStageHeight: CGFloat {
        fullPreviewFrameSize.height
    }

    private var previewModePicker: some View {
        HStack(spacing: 8) {
            ForEach(orderedPreviewModes) { mode in
                Button {
                    previewMode = mode
                } label: {
                    Text(mode.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(previewMode == mode ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(previewMode == mode ? Color.accentColor : Color(.tertiarySystemFill))
                )
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .compositingGroup()
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if dragBasePlacement == nil {
                    dragBasePlacement = workingPlacement
                }
                guard let dragBasePlacement else { return }
                let canvasSize = gestureCanvasSize
                workingPlacement.offsetXRatio = dragBasePlacement.offsetXRatio + Double(value.translation.width / max(canvasSize.width, 1))
                workingPlacement.offsetYRatio = dragBasePlacement.offsetYRatio + Double(value.translation.height / max(canvasSize.height, 1))
            }
            .onEnded { _ in
                dragBasePlacement = nil
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if scaleBase == nil {
                    scaleBase = workingPlacement.scale
                }
                let base = scaleBase ?? workingPlacement.scale
                workingPlacement.scale = min(max(base * value, 1), 4)
            }
            .onEnded { _ in
                scaleBase = nil
            }
    }

    @ViewBuilder
    private var previewCanvas: some View {
        switch previewMode {
        case .circle:
            ZStack {
                let circleFrame = fullPreviewCircleFrame

                OshiFilledUIImageView(image: image, size: circlePreviewDiameter, placement: workingPlacement)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    .frame(width: circlePreviewDiameter, height: circlePreviewDiameter)
                    .position(x: circleFrame.midX, y: circleFrame.midY)
                    .allowsHitTesting(false)
                    .shadow(color: .black.opacity(0.08), radius: 16, y: 10)
            }
            .frame(width: fullPreviewFrameSize.width, height: fullPreviewFrameSize.height)
        case .full:
            ZStack {
                Rectangle()
                    .fill(Color(.secondarySystemBackground))
                    .allowsHitTesting(false)

                let circleFrame = fullPreviewCircleFrame
                let imageLayout = fullPreviewImageLayout(for: circleFrame)

                Image(uiImage: image)
                    .resizable()
                    .frame(width: imageLayout.size.width, height: imageLayout.size.height)
                    .position(
                        x: imageLayout.origin.x + (imageLayout.size.width / 2),
                        y: imageLayout.origin.y + (imageLayout.size.height / 2)
                    )
                    .clipShape(Rectangle())
                    .allowsHitTesting(false)

                Circle()
                    .stroke(Color.white.opacity(0.95), lineWidth: 2)
                    .frame(width: circleFrame.width, height: circleFrame.height)
                    .position(x: circleFrame.midX, y: circleFrame.midY)
                    .allowsHitTesting(false)

                Circle()
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    .frame(width: circleFrame.width, height: circleFrame.height)
                    .position(x: circleFrame.midX, y: circleFrame.midY)
                    .allowsHitTesting(false)
            }
            .frame(width: fullPreviewFrameSize.width, height: fullPreviewFrameSize.height)
            .shadow(color: .black.opacity(0.08), radius: 16, y: 10)
        }
    }

    private var fullPreviewFrameSize: CGSize {
        let imageWidth = max(image.size.width, 1)
        let imageHeight = max(image.size.height, 1)
        let scale = min(fullPreviewMaxWidth / imageWidth, fullPreviewMaxHeight / imageHeight)
        return CGSize(width: imageWidth * scale, height: imageHeight * scale)
    }

    private var circlePreviewDiameter: CGFloat {
        fullPreviewCircleFrame.width
    }

    private func fullPreviewImageLayout(for circleFrame: CGRect) -> (origin: CGPoint, size: CGSize) {
        let avatarCanvasSize = CGSize(width: circlePreviewDiameter, height: circlePreviewDiameter)
        let avatarTransform = avatarPlacementTransform(in: avatarCanvasSize)
        let avatarVisibleRectInImage = CGRect(
            x: (0 - avatarTransform.origin.x) / avatarTransform.scale,
            y: (0 - avatarTransform.origin.y) / avatarTransform.scale,
            width: avatarCanvasSize.width / avatarTransform.scale,
            height: avatarCanvasSize.height / avatarTransform.scale
        )

        let previewScale = circleFrame.width / max(avatarVisibleRectInImage.width, 1)
        let displayedSize = CGSize(
            width: image.size.width * previewScale,
            height: image.size.height * previewScale
        )
        let origin = CGPoint(
            x: circleFrame.minX - (avatarVisibleRectInImage.minX * previewScale),
            y: circleFrame.minY - (avatarVisibleRectInImage.minY * previewScale)
        )
        return (origin, displayedSize)
    }

    private var fullPreviewCircleFrame: CGRect {
        let inset: CGFloat = 12
        let diameter = max(min(fullPreviewFrameSize.width, fullPreviewFrameSize.height) - (inset * 2), 0)
        let originX = (fullPreviewFrameSize.width - diameter) / 2
        let originY = image.size.height > image.size.width
            ? inset
            : (fullPreviewFrameSize.height - diameter) / 2
        return CGRect(x: originX, y: originY, width: diameter, height: diameter)
    }

    private func avatarPlacementTransform(in canvasSize: CGSize) -> (scale: CGFloat, origin: CGPoint) {
        let fillScale = max(
            canvasSize.width / max(image.size.width, 1),
            canvasSize.height / max(image.size.height, 1)
        )
        let displayScale = fillScale * CGFloat(workingPlacement.scale)
        let displayedSize = CGSize(
            width: image.size.width * displayScale,
            height: image.size.height * displayScale
        )
        let baseOrigin = CGPoint(
            x: (canvasSize.width - displayedSize.width) / 2,
            y: image.size.height > image.size.width ? 0 : (canvasSize.height - displayedSize.height) / 2
        )
        let desiredOrigin = CGPoint(
            x: baseOrigin.x + (workingPlacement.offsetXRatio * canvasSize.width),
            y: baseOrigin.y + (workingPlacement.offsetYRatio * canvasSize.height)
        )
        let clampedOrigin = CGPoint(
            x: clamp(desiredOrigin.x, lower: canvasSize.width - displayedSize.width, upper: 0),
            y: clamp(desiredOrigin.y, lower: canvasSize.height - displayedSize.height, upper: 0)
        )
        return (displayScale, clampedOrigin)
    }

    private func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}

struct OshiBackgroundImage: View {
    let oshiID: UUID
    let imageData: Data?
    @State private var image: UIImage? = nil

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    Color.clear
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            loadImage()
        }
        .onChange(of: imageData) { _, _ in
            loadImage()
        }
    }

    private func loadImage() {
        let fingerprint = imageData.map(imageDataFingerprint) ?? "none"
        let cacheKey = "\(oshiID.uuidString)-background-\(fingerprint)"
        if let cached = MemoryImageCache.shared.image(for: cacheKey) {
            image = cached
            return
        }

        guard let imageData, let decoded = UIImage(data: imageData) else {
            image = nil
            return
        }

        MemoryImageCache.shared.set(decoded, for: cacheKey)
        image = decoded
    }
}

// MARK: - 4. メイン画面
@MainActor
struct ContentView: View {
    enum RootTab: Hashable {
        case live
        case cheki
        case oshi
        case list
        case card
    }

    @State private var myOshis: [Oshi] = []
    @State private var myChekis: [Cheki] = []
    @State private var myLives: [LiveRecord] = []
    @State private var profile = UserProfile()
    @StateObject private var oshiLoader = OshiLoader()
    @State private var selectedTab: RootTab = .oshi
    @State private var hasPerformedInitialLoad = false
    @State private var selectedLiveID: UUID? = nil
    @State private var selectedLivePhotoIndex: Int? = nil

    private var accentColor: Color {
        myOshis.first?.color ?? .pink
    }

    private var tabBarBackgroundColor: UIColor {
        UIColor.systemBackground
    }

    private var tabBarNormalColor: UIColor {
        UIColor.label
    }
    
    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = UIColor.systemBackground

        let selectedColor = UIColor(red: 0.969, green: 0.659, blue: 0.769, alpha: 1.0)
        let normalColor = UIColor.secondaryLabel

        appearance.stackedLayoutAppearance.selected.iconColor = selectedColor
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]
        appearance.stackedLayoutAppearance.normal.iconColor = normalColor
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]

        appearance.inlineLayoutAppearance.selected.iconColor = selectedColor
        appearance.inlineLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]
        appearance.inlineLayoutAppearance.normal.iconColor = normalColor
        appearance.inlineLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]

        appearance.compactInlineLayoutAppearance.selected.iconColor = selectedColor
        appearance.compactInlineLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]
        appearance.compactInlineLayoutAppearance.normal.iconColor = normalColor
        appearance.compactInlineLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                LiveListView(
                    myLives: $myLives,
                    myOshis: $myOshis,
                    myChekis: $myChekis,
                    selectedLiveID: $selectedLiveID,
                    selectedLivePhotoIndex: $selectedLivePhotoIndex,
                    profile: $profile,
                    loader: oshiLoader
                )
            }
                .tabItem {
                    Label("現場", systemImage: "music.mic")
                }
                .tag(RootTab.live)

            NavigationStack {
                ChekiGalleryView(myOshis: $myOshis, myChekis: $myChekis, profile: $profile)
            }
                .tabItem {
                    Label("チェキ帳", systemImage: "person.crop.rectangle.stack.fill")
                }
                .tag(RootTab.cheki)

            MainSwipeView(
                myOshis: $myOshis,
                myChekis: $myChekis,
                myLives: $myLives,
                isOshiTabActive: selectedTab == .oshi,
                preferredFont: profile.preferredAppFont,
                loader: oshiLoader
            )
                .tabItem {
                    Label("", systemImage: "heart.fill")
                }
                .tag(RootTab.oshi)
            
            NavigationStack {
                OshiListView(
                    myOshis: $myOshis,
                    myChekis: $myChekis,
                    myLives: $myLives,
                    profile: $profile,
                    loader: oshiLoader
                )
            }
                .tabItem {
                    Label("一覧", systemImage: "list.bullet")
                }
                .tag(RootTab.list)

            NavigationStack {
                ToolsHomeView(profile: $profile, myOshis: $myOshis, myLives: $myLives, myChekis: $myChekis)
            }
                .tabItem {
                    Label("ツール", systemImage: "wand.and.stars")
            }
            .tag(RootTab.card)
        }
        .onAppear { performInitialLoadIfNeeded() }
        .task {
            if oshiLoader.agencies.isEmpty {
                await oshiLoader.fetchAgencies()
            }
        }
        .onChange(of: profile) { _, newProfile in
            LocalStorage.save(newProfile, for: .profile)
        }
    }
    
    func loadData() {
        if let dec = LocalStorage.load([Oshi].self, for: .oshis) {
            myOshis = dec
        }
        if let dec = LocalStorage.load([Cheki].self, for: .chekis) {
            myChekis = dec
        }
        // 期限切れの生誕祭を自動でリセット
        let today = Calendar.current.startOfDay(for: Date())
        for i in 0..<myOshis.count {
            if let event = myOshis[i].seitansaiDate, event < today {
                myOshis[i].seitansaiDate = nil
                // 必要に応じて「hasSeitansai」フラグなどもここで戻す
            }
        }
    }
    func loadLiveData() {
        if let decoded = LocalStorage.load([LiveRecord].self, for: .lives) {
            myLives = decoded
        }
    }
    func loadProfile() {
        profile = LocalStorage.load(UserProfile.self, for: .profile) ?? UserProfile()
    }
    func save() {
        LocalStorage.save(myOshis, for: .oshis)
    }

    func performInitialLoadIfNeeded() {
        guard !hasPerformedInitialLoad else { return }
        hasPerformedInitialLoad = true
        loadData()
        loadLiveData()
        loadProfile()
    }
}

@MainActor
struct MainSwipeView: View {
    @Binding var myOshis: [Oshi]
    @Binding var myChekis: [Cheki]
    @Binding var myLives: [LiveRecord]
    let isOshiTabActive: Bool
    let preferredFont: AppDisplayFontChoice
    @ObservedObject var loader: OshiLoader
    @State private var isAdd = false
    @State private var selectedOshiID: UUID?
    @State private var zoomingOshiID: UUID? = nil
    var visible: [Oshi] { myOshis.filter { $0.isDisplayed } }

    private var visibleIDs: [UUID] {
        visible.map(\.id)
    }

    private var sanitizedSelectedOshiID: UUID? {
        guard !visibleIDs.isEmpty else { return nil }
        if let selectedOshiID, visibleIDs.contains(selectedOshiID) {
            return selectedOshiID
        }
        return visibleIDs.first
    }

    private var selectedOshiBinding: Binding<UUID?> {
        Binding(
            get: { sanitizedSelectedOshiID },
            set: { selectedOshiID = $0 }
        )
    }

    var body: some View {
        if visible.isEmpty {
            ContentUnavailableView { Label(myOshis.isEmpty ? "未登録" : "非表示中", systemImage: "eye.slash") }
            description: { Text("追加または表示設定を確認してください") }
            actions: { if myOshis.isEmpty { Button("登録する") { isAdd = true }.buttonStyle(.borderedProminent) } }
            .sheet(isPresented: $isAdd) { AddEditOshiView(myOshis: $myOshis, editingOshi: nil, loader: loader) }
            .onAppear {
                selectedOshiID = nil
                zoomingOshiID = nil
            }
        } else {
            TabView(selection: selectedOshiBinding) {
                ForEach(visibleIDs, id: \.self) { id in
                    if let index = myOshis.firstIndex(where: { $0.id == id }) {
                        OshiDetailView(
                            oshi: $myOshis[index],
                            allChekis: $myChekis,
                            loader: loader,
                            preferredFont: preferredFont,
                            isCurrentPage: sanitizedSelectedOshiID == id,
                            isOshiTabActive: isOshiTabActive,
                            isImageZoomPresented: zoomingOshiID != nil,
                            onSave: save,
                            onOpenImageZoom: {
                                zoomingOshiID = id
                            },
                            onReturnToTop: {
                                selectedOshiID = visible.first?.id
                            }
                        )
                        .id(id)
                        .tag(id as UUID?)
                    }
                }
            }
            .id(visibleIDs)
            .tabViewStyle(.page(indexDisplayMode: .always))
            .ignoresSafeArea(edges: .top)
            .onAppear {
                selectedOshiID = sanitizedSelectedOshiID
            }
            .onChange(of: visibleIDs) { _, ids in
                selectedOshiID = ids.contains(selectedOshiID ?? UUID()) ? selectedOshiID : ids.first
            }
            .onChange(of: visibleIDs) { _, ids in
                if let zoomingOshiID, !ids.contains(zoomingOshiID) {
                    self.zoomingOshiID = nil
                }
            }
            .fullScreenCover(
                item: Binding(
                    get: { zoomingOshiID.map(IdentifiableUUID.init) },
                    set: { zoomingOshiID = $0?.value }
                )
            ) { item in
                if let index = myOshis.firstIndex(where: { $0.id == item.value }) {
                    OshiImageFullscreenView(
                        oshi: $myOshis[index],
                        loader: loader,
                        onSave: save,
                        onClose: {
                            zoomingOshiID = nil
                        }
                    )
                } else {
                    Color.clear
                        .ignoresSafeArea()
                        .onAppear {
                            zoomingOshiID = nil
                        }
                }
            }
        }
    }

    private func save() {
        LocalStorage.save(myOshis, for: .oshis)
    }
}

struct OshiDetailView: View {
    @Binding var oshi: Oshi
    @Binding var allChekis: [Cheki]
    @ObservedObject var loader: OshiLoader
    let preferredFont: AppDisplayFontChoice
    let isCurrentPage: Bool
    let isOshiTabActive: Bool
    let isImageZoomPresented: Bool
    let onSave: () -> Void
    let onOpenImageZoom: () -> Void
    let onReturnToTop: () -> Void
    @Environment(\.openURL) var openURL
    
    // 状態管理
    @State private var isZoomingOshiImage = false
    @State private var showingOshiImagePlacementEditor = false
    @State private var showingOshiImageCandidatePicker = false
    @State private var isPreparingOshiImageCandidatePicker = false
    @State private var selectedOshiPhotoItem: PhotosPickerItem? = nil
    @State private var selectedBackgroundPhotoItem: PhotosPickerItem? = nil
    @State private var closeZoomAfterPlacementSave = false
    @State private var placementEditorImage: UIImage? = nil
    @State private var oshiImageCandidatePickerOptions: [OshiImageCandidateOption] = []
    @State private var oshiImageCandidateDisplayLimit = AppConfig.imageCandidateSelectionLimit
    @State private var zoomCheki: Cheki? = nil
    @State private var showSaveAlert = false
    @State private var alertText = ""
    @State private var isCapturing = false
    @State private var confettiPoints: [CGPoint] = [] // クラッカー用
    @State private var sparkleRefreshID = UUID()

    private var screenshotDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: Date())
    }

    private var currentOshiUIImage: UIImage? {
        guard let data = oshi.localImageData else { return nil }
        return UIImage(data: data)
    }

    private var canChooseOshiCandidateImage: Bool {
        oshi.kind == .person &&
        (oshi.agencyId?.isEmpty == false) &&
        (oshi.masterId?.isEmpty == false)
    }

    private var visibleOshiImageCandidatePickerOptions: [OshiImageCandidateOption] {
        Array(oshiImageCandidatePickerOptions.prefix(oshiImageCandidateDisplayLimit))
    }

    private var canShowMoreOshiImageCandidates: Bool {
        oshiImageCandidateDisplayLimit < oshiImageCandidatePickerOptions.count
    }

    private var isStartingToday: Bool {
        Calendar.current.isDate(oshi.startDate, inSameDayAs: Date())
    }

    private var timeTreeResolutionTaskKey: String {
        [
            oshi.id.uuidString,
            oshi.agencyId ?? "",
            oshi.groupId ?? "",
            oshi.masterId ?? "",
            oshi.group,
            oshi.timeTreeURL ?? ""
        ].joined(separator: "|")
    }

    var body: some View {
        let txtCol: Color = oshi.textColor
        let birthdayCountdown = oshi.daysUntilBirthday
        let seitansaiCountdown = oshi.daysUntilSeitansai
        let debutCountdown = oshi.daysUntilDebut
        let debutAnniversaryCount = oshi.nextAnniversaryCount
        let oshiAnniversaryCountdown = oshi.daysUntilAnniversary
        let oshiAnniversaryYear = oshi.nextAnniversaryYear
        let oshiMonthlyAnniversaryCount = oshi.currentMonthlyAnniversaryCount
        let chekis = allChekis.filter { $0.oshiID == oshi.id }
        let isAnniversaryTapEffectEnabled = false
        let backgroundColor = oshi.color
        let darkOverlay = Color.black.opacity(0.22)
        let tintOverlay = backgroundColor.opacity(0.18)
        
        ZStack {
            // --- スクショ・演出対象エリア ---
            ZStack {
                if oshi.backgroundImageData != nil {
                    OshiBackgroundImage(
                        oshiID: oshi.id,
                        imageData: oshi.backgroundImageData
                    )
                    .ignoresSafeArea()

                    darkOverlay.ignoresSafeArea()
                    tintOverlay.ignoresSafeArea()
                } else {
                    backgroundColor.ignoresSafeArea()
                }

                #if false
                if oshi.isEffectEnabled && isCurrentPage && isOshiTabActive {
                    SparkleView(isOnLightBackground: ColorUtils.isLightColor(oshi.color))
                }
                #endif
                if oshi.isEffectEnabled {
                    let isLightBackground = ColorUtils.isLightColor(oshi.color)

                    SparkleView(oshiColor: oshi.color, isOnLightBackground: isLightBackground)
                        .id(sparkleRefreshID)
                        .opacity(0.6)
                        .blendMode(isLightBackground ? .normal : .screen)
                }

                // 2. クラッカーエフェクト（タップした位置から発生）
                ForEach(0..<confettiPoints.count, id: \.self) { i in
                    ConfettiView(origin: confettiPoints[i], color: txtCol)
                }

                if !isCapturing {
                    VStack(spacing: 0) {
                        HStack {
                            Spacer()

                            Button(action: takeScreenshot) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.title2)
                                    .bold()
                                    .foregroundColor(txtCol.opacity(0.6))
                                    .padding(20)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 0)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(30)
                } else {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(screenshotDateText)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(txtCol.opacity(0.85))
                                .padding(.vertical, 8)
                                .padding(.horizontal, 14)
                                .background(Color.black.opacity(ColorUtils.isLightColor(oshi.color) ? 0.18 : 0.28))
                                .clipShape(Capsule())
                                .padding(.trailing, 20)
                                .padding(.bottom, 28)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(30)
                }
                
                VStack(spacing: 15) {
                    Spacer()
                    
                    // 推し画像
                    OshiImage(oshi: oshi, size: 200)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(oshi.color.opacity(0.6), lineWidth: 4))
                        .shadow(radius: 10)
                        .contentShape(Circle())
                        .onTapGesture {
                            onOpenImageZoom()
                        }
                    
                    // 名前とグループ
                    VStack(spacing: 2) {
                        Text(oshi.name)
                            .font(AppTypography.roundedDisplayFont(for: preferredFont, size: 42, weight: .black))
                            .shadow(color: txtCol.opacity(0.3), radius: 5)
                        Text(oshi.group)
                            .font(AppTypography.bodyFont(for: preferredFont, size: 17, weight: .semibold))
                            .opacity(0.8)
                    }.foregroundColor(txtCol)
                    
                    // 推し歴
                    Text("\(oshi.daysCount)日目")
                        .font(AppTypography.roundedDisplayFont(for: preferredFont, size: 50, weight: .black))
                        .foregroundColor(txtCol)
                    
                    // 3. 記念日カウントダウン（2段レイアウト）
                    VStack(spacing: 8) {
                        HStack(spacing: 10) {
                            if let days = birthdayCountdown {
                                countdownCapsule(text: days == 0 ? "🎂 HAPPY BIRTHDAY!" : "🎂 あと \(days)日", color: txtCol, isToday: days == 0, fontChoice: preferredFont)
                            }
                            if oshi.isSeitansaiActive, let days = seitansaiCountdown {
                                countdownCapsule(text: days == 0 ? "🎉 本日生誕祭" : "🎉 生誕祭まで \(days)日", color: txtCol, isToday: days == 0, fontChoice: preferredFont)
                            }
                        }
                        HStack(spacing: 10) {
                            if let days = debutCountdown, let count = debutAnniversaryCount {
                                countdownCapsule(text: days == 0 ? "👑 本日 デビュー\(count)周年" : "👑 デビュー\(count)周年まで \(days)日", color: txtCol, isToday: days == 0, fontChoice: preferredFont)
                            }
                            if isStartingToday {
                                countdownCapsule(text: "💝 今日からよろしくね！", color: txtCol, isToday: true, fontChoice: preferredFont)
                            } else if let monthCount = oshiMonthlyAnniversaryCount, (oshiAnniversaryCountdown ?? -1) != 0 {
                                countdownCapsule(text: "💝 本日で推し\(monthCount)か月", color: txtCol, isToday: true, fontChoice: preferredFont)
                            } else if oshiAnniversaryYear > 0, let days = oshiAnniversaryCountdown {
                                let year = oshiAnniversaryYear
                                countdownCapsule(text: days == 0 ? "💝 本日 推し\(year)周年" : "💝 推し\(year)周年まで \(days)日", color: txtCol, isToday: days == 0, fontChoice: preferredFont)
                            }
                        }
                    }
                    .padding(.top, 2)

                    if !chekis.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(chekis) { c in
                                    DownsampledDataImage(
                                        cacheKey: "oshi-cheki-strip-\(c.id.uuidString)-\(chekiThumbnailFingerprint(c))",
                                        data: c.thumbnailData,
                                        maxPixelSize: 150,
                                        contentMode: .fit
                                    )
                                    .frame(width: 70, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                    .onTapGesture { withAnimation(.spring()) { zoomCheki = c } }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    if !isCapturing {
                        // SNSボタン
                        HStack(spacing: 25) {
                            if let tw = oshi.twitterID, !tw.isEmpty { SNSBtn(icon: "bird.fill", label: "X", color: txtCol) { openSNS(host: "x.com", id: tw) } }
                            if let ins = oshi.instagramID, !ins.isEmpty { SNSBtn(icon: "camera.fill", label: "Insta", color: txtCol) { openSNS(host: "instagram.com", id: ins) } }
                            if let tik = oshi.tiktokID, !tik.isEmpty { SNSBtn(icon: "music.note", label: "TikTok", color: txtCol) { openSNS(host: "tiktok.com", id: tik, pathPrefix: "@") } }
                            if let timeTreeURL = resolvedGroupTimeTreeURL { SNSBtn(icon: "calendar", label: "TimeTree", color: txtCol) { openURL(timeTreeURL) } }
                        }
                    }
                    Spacer()
                }
            }
            .compositingGroup()
            .task(id: timeTreeResolutionTaskKey) {
                await ensureGroupTimeTreeURLLoaded()
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard isAnniversaryTapEffectEnabled, oshi.isAnyAnniversaryToday else { return }
                        confettiPoints.append(value.location)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            if !confettiPoints.isEmpty { confettiPoints.removeFirst() }
                        }
                    }
            )
            
            // 保存完了通知
            if showSaveAlert {
                VStack {
                    Spacer()
                    Text(alertText).font(.subheadline).bold().foregroundColor(.white).padding(.vertical, 12).padding(.horizontal, 24)
                        .background(Color.black.opacity(0.7)).clipShape(Capsule()).padding(.bottom, 50)
                }.transition(.move(edge: .bottom).combined(with: .opacity)).zIndex(5)
            }

            // チェキ拡大プレビュー
            if let cheki = zoomCheki {
                ChekiFullscreenSaveView(
                    imageData: cheki.imageData,
                    isPresented: Binding(
                        get: { zoomCheki != nil },
                        set: { newValue in
                            if !newValue {
                                withAnimation {
                                    zoomCheki = nil
                                }
                            }
                        }
                    )
                )
                .zIndex(10)
            }

        }
        .onDisappear {
            isZoomingOshiImage = false
            zoomCheki = nil
        }
        .onAppear {
            guard isCurrentPage, oshi.isEffectEnabled else { return }
            sparkleRefreshID = UUID()
        }
        .onChange(of: isCurrentPage) { _, isCurrent in
            guard isCurrent, oshi.isEffectEnabled else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                sparkleRefreshID = UUID()
            }
        }
        .onChange(of: isOshiTabActive) { _, isActive in
            guard isActive, isCurrentPage, oshi.isEffectEnabled else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                sparkleRefreshID = UUID()
            }
        }
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    onReturnToTop()
                }
        )
        .onChange(of: selectedOshiPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let resizedData = ImageResizer.resizedJPEGData(
                    from: data,
                    maxLongEdge: 1200,
                    compressionQuality: 0.80
                   ),
                   UIImage(data: resizedData) != nil {
                    await MainActor.run {
                        oshi.selectedImageFileName = nil
                        oshi.localImageData = resizedData
                        oshi.iconThumbnailData = OshiIconThumbnailHelper.thumbnailData(
                            from: resizedData,
                            placement: .default
                        )
                        oshi.imagePlacement = .default
                        isZoomingOshiImage = false
                        selectedOshiPhotoItem = nil
                        onSave()
                        showingOshiImagePlacementEditor = true
                    }
                } else {
                    await MainActor.run {
                        selectedOshiPhotoItem = nil
                    }
                }
            }
        }
        .onChange(of: selectedBackgroundPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let resizedData = ImageResizer.resizedJPEGData(from: data),
                   UIImage(data: resizedData) != nil {
                    await MainActor.run {
                        oshi.backgroundImageData = resizedData
                        selectedBackgroundPhotoItem = nil
                        alertText = "背景画を変更しました"
                        onSave()
                        withAnimation { showSaveAlert = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            withAnimation { showSaveAlert = false }
                        }
                    }
                } else {
                    await MainActor.run {
                        selectedBackgroundPhotoItem = nil
                    }
                }
            }
        }
        .onChange(of: oshi.id) { _, _ in
            isZoomingOshiImage = false
            showingOshiImagePlacementEditor = false
            showingOshiImageCandidatePicker = false
            isPreparingOshiImageCandidatePicker = false
            selectedOshiPhotoItem = nil
            selectedBackgroundPhotoItem = nil
            oshiImageCandidatePickerOptions = []
            oshiImageCandidateDisplayLimit = AppConfig.imageCandidateSelectionLimit
            zoomCheki = nil
            showSaveAlert = false
            if oshi.isEffectEnabled {
                sparkleRefreshID = UUID()
            }
        }
        .onChange(of: oshi.isEffectEnabled) { _, isEnabled in
            guard isEnabled else { return }
            sparkleRefreshID = UUID()
        }
        .onChange(of: isImageZoomPresented) { _, isPresented in
            guard !isPresented, oshi.isEffectEnabled else { return }
            sparkleRefreshID = UUID()
        }
        .onChange(of: showingOshiImagePlacementEditor) { _, isPresented in
            guard !isPresented, closeZoomAfterPlacementSave else { return }
            closeZoomAfterPlacementSave = false
            isZoomingOshiImage = false
        }
        .sheet(isPresented: $showingOshiImageCandidatePicker) {
            OshiImageCandidatePickerSheetView(
                candidates: visibleOshiImageCandidatePickerOptions,
                selectedFileName: oshi.selectedImageFileName,
                canShowMore: canShowMoreOshiImageCandidates,
                onSelect: { candidate in
                    showingOshiImageCandidatePicker = false
                    Task {
                        await applyOshiImageCandidate(candidate)
                    }
                },
                onShowMore: {
                    oshiImageCandidateDisplayLimit += AppConfig.imageCandidateSelectionLimit
                },
                primaryLabel: oshiImageCandidatePrimaryLabel,
                secondaryLabel: oshiImageCandidateSecondaryLabel
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        showingOshiImageCandidatePicker = false
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $isZoomingOshiImage) {
            ZStack {
                Color.black.opacity(0.85)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isZoomingOshiImage = false
                    }

                VStack {
                    HStack {
                        Button(action: {
                            isZoomingOshiImage = false
                        }) {
                            Image(systemName: "xmark")
                                .font(.title3)
                                .bold()
                                .foregroundColor(.white)
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .padding()

                        Spacer()

                        HStack(spacing: 12) {
                            PhotosPicker(selection: $selectedOshiPhotoItem, matching: .images) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.title3)
                                    .bold()
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }

                            Menu {
                                if canChooseOshiCandidateImage {
                                    Button {
                                        Task {
                                            await openOshiImageCandidatePicker()
                                        }
                                    } label: {
                                        Label("候補から選択", systemImage: "sparkles.square.filled.on.square")
                                    }
                                .disabled(isPreparingOshiImageCandidatePicker || loader.isLoadingImageCandidates(for: oshi.agencyId))
                                }

                                Button {
                                    Task {
                                        await openCurrentOshiImagePlacementEditor()
                                    }
                                } label: {
                                    Label("位置を調整する", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
                                }

                                Button(role: .destructive) {
                                    restoreDefaultOshiImage()
                                } label: {
                                    Label("デフォルト画像に戻す", systemImage: "arrow.uturn.backward")
                                }
                            } label: {
                                oshiImageActionsMenuLabel
                            }
                        }
                        .padding()
                    }

                    Spacer()

                    OshiOriginalImage(oshi: oshi)
                        .frame(maxWidth: UIScreen.main.bounds.width - 48, maxHeight: UIScreen.main.bounds.height * 0.6)
                        .shadow(radius: 20)
                        .padding(.horizontal, 24)
                        .gesture(
                            DragGesture(minimumDistance: 20)
                                .onEnded { value in
                                    if abs(value.translation.height) > 60 || abs(value.translation.width) > 60 {
                                        isZoomingOshiImage = false
                                    }
                                }
                        )

                    Spacer()
                }
            }
        }
        .fullScreenCover(isPresented: $showingOshiImagePlacementEditor) {
            if let placementEditorImage = placementEditorImage ?? currentOshiUIImage {
                OshiImagePlacementEditorView(
                    image: placementEditorImage,
                    initialPlacement: oshi.imagePlacement
                ) { updatedPlacement in
                    oshi.imagePlacement = updatedPlacement
                    oshi.iconThumbnailData = OshiIconThumbnailHelper.thumbnailData(
                        from: oshi.localImageData,
                        placement: updatedPlacement
                    )
                    onSave()
                    closeZoomAfterPlacementSave = true
                }
            }
        }
    }

    @MainActor
    private func openOshiImageCandidatePicker() async {
        guard let agencyId = oshi.agencyId, !agencyId.isEmpty,
              let masterId = oshi.masterId, !masterId.isEmpty else {
            return
        }

        isPreparingOshiImageCandidatePicker = true
        defer { isPreparingOshiImageCandidatePicker = false }

        var options = loader.imageCandidates(for: agencyId, masterId: masterId)
        if options.isEmpty {
            await loader.fetchImageCandidates(agencyId: agencyId)
            options = loader.imageCandidates(for: agencyId, masterId: masterId)
        }

        guard !options.isEmpty else { return }

        oshiImageCandidatePickerOptions = options
        oshiImageCandidateDisplayLimit = AppConfig.imageCandidateSelectionLimit
        showingOshiImageCandidatePicker = true
    }

    private func restoreDefaultOshiImage() {
        Task {
            await restoreDefaultOshiImageData()
        }
    }

    @MainActor
    private func openCurrentOshiImagePlacementEditor() async {
        if let currentOshiUIImage {
            placementEditorImage = currentOshiUIImage
            showingOshiImagePlacementEditor = true
            return
        }

        guard let imageURL = URL(string: oshi.resolvedRemoteImageURL), !oshi.resolvedRemoteImageURL.isEmpty else {
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: imageURL)
            guard let decoded = UIImage(data: data) else { return }
            placementEditorImage = decoded
            showingOshiImagePlacementEditor = true
        } catch {
        }
    }

    @MainActor
    private func applyOshiImageCandidate(_ candidate: OshiImageCandidateOption) async {
        guard let imageURL = URL(string: candidate.url) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: imageURL)
            guard UIImage(data: data) != nil else { return }

            oshi.selectedImageFileName = candidate.fileName
            oshi.localImageData = data
            oshi.iconThumbnailData = OshiIconThumbnailHelper.thumbnailData(
                from: data,
                placement: .default
            )
            oshi.imagePlacement = .default
            onSave()
            isZoomingOshiImage = false
            showingOshiImagePlacementEditor = true
        } catch {
        }
    }

    @MainActor
    private func restoreDefaultOshiImageData() async {
        let resolvedDefaultURLString = resolvedDefaultImageURLString()
        guard let defaultURL = URL(string: resolvedDefaultURLString), !resolvedDefaultURLString.isEmpty else {
            oshi.selectedImageFileName = nil
            oshi.localImageData = nil
            oshi.iconThumbnailData = nil
            oshi.originalImageData = nil
            oshi.imagePlacement = .default
            onSave()
            isZoomingOshiImage = false
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: defaultURL)
            guard let resizedData = ImageResizer.resizedJPEGData(
                from: data,
                maxLongEdge: 1200,
                compressionQuality: 0.80
            ),
            UIImage(data: resizedData) != nil else { return }
            oshi.imageURL = resolvedDefaultURLString
            oshi.selectedImageFileName = nil
            oshi.localImageData = resizedData
            oshi.iconThumbnailData = OshiIconThumbnailHelper.thumbnailData(
                from: resizedData,
                placement: .default
            )
            oshi.originalImageData = resizedData
            oshi.imagePlacement = .default
            onSave()
            isZoomingOshiImage = false
        } catch {
            isZoomingOshiImage = false
        }
    }

    private func resolvedDefaultImageURLString() -> String {
        if oshi.kind == .group,
           let masterId = oshi.masterId,
           let matched = loader.displayGroupOshis.first(where: { $0.masterId == masterId }) {
            return matched.imageURL
        }

        if let masterId = oshi.masterId,
           let matched = loader.displayOshis.first(where: { $0.masterId == masterId }) {
            return matched.imageURL
        }

        return oshi.imageURL
    }

    private var resolvedGroupTimeTreeURL: URL? {
        if let url = normalizedTimeTreeURL(from: oshi.timeTreeURL) {
            return url
        }

        if let groupId = oshi.groupId,
           let matched = loader.displayGroupOshis.first(where: { $0.groupId == groupId }),
           let url = normalizedTimeTreeURL(from: matched.timeTreeURL) {
            return url
        }

        if oshi.kind == .group,
           let masterId = oshi.masterId,
           let matched = loader.displayGroupOshis.first(where: { $0.masterId == masterId }),
           let url = normalizedTimeTreeURL(from: matched.timeTreeURL) {
            return url
        }

        let trimmedGroupName = oshi.group.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedGroupName.isEmpty,
           let matched = loader.displayGroupOshis.first(where: { $0.group == trimmedGroupName }),
           let url = normalizedTimeTreeURL(from: matched.timeTreeURL) {
            return url
        }

        return nil
    }

    private func normalizedTimeTreeURL(from value: String?) -> URL? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        return URL(string: trimmed)
    }

    private func ensureGroupTimeTreeURLLoaded() async {
        guard resolvedGroupTimeTreeURL == nil,
              let agencyId = oshi.agencyId,
              !agencyId.isEmpty else {
            return
        }

        if loader.agencies.isEmpty {
            await loader.fetchAgencies()
        }

        guard let agency = loader.agencies.first(where: { $0.agencyId == agencyId }) else {
            return
        }

        await loader.fetchAgencyDetail(url: agency.detailURL)
    }

    private func oshiImageCandidatePrimaryLabel(_ candidate: OshiImageCandidateOption) -> String {
        if let label = candidate.eventLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !label.isEmpty {
            return label
        }

        if let caption = meaningfulCandidateCaption(candidate.caption) {
            return caption
        }

        if let yearMonth = formattedCandidateYearMonth(candidate.yearMonth) {
            return yearMonth
        }

        return candidate.fileName
    }

    private func oshiImageCandidateSecondaryLabel(_ candidate: OshiImageCandidateOption) -> String? {
        if candidate.eventLabel != nil,
           let caption = meaningfulCandidateCaption(candidate.caption),
           caption != oshiImageCandidatePrimaryLabel(candidate) {
            return caption
        }

        return formattedCandidateYearMonth(candidate.yearMonth)
    }

    private func meaningfulCandidateCaption(_ caption: String?) -> String? {
        guard let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              Int(trimmed) == nil else {
            return nil
        }
        return trimmed
    }

    private func formattedCandidateYearMonth(_ yearMonth: String?) -> String? {
        guard let value = yearMonth?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"

        guard let date = formatter.date(from: value) else {
            return value
        }

        let output = DateFormatter()
        output.locale = Locale(identifier: "en_US_POSIX")
        output.dateFormat = "MMM yyyy"
        return output.string(from: date)
    }

    // --- 各種関数 ---
    @ViewBuilder
    func countdownCapsule(text: String, color: Color, isToday: Bool, fontChoice: AppDisplayFontChoice) -> some View {
        Text(text)
            .font(AppTypography.bodyFont(for: fontChoice, size: isToday ? 13 : 11, weight: .black))
            .padding(.vertical, isToday ? 8 : 6).padding(.horizontal, isToday ? 18 : 12)
            .background(isToday ? color.opacity(0.8) : color.opacity(0.15))
            .foregroundColor(isToday ? (ColorUtils.isLightColor(color) ? .black : .white) : color)
            .clipShape(Capsule())
            .shadow(color: isToday ? color.opacity(0.5) : .clear, radius: isToday ? 10 : 0)
            .scaleEffect(isToday ? 1.1 : 1.0)
    }

    func takeScreenshot() {
        isCapturing = true; alertText = "画面を保存しました ✨"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let image = self.snapshot()
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            withAnimation { showSaveAlert = true }
            isCapturing = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { showSaveAlert = false } }
        }
    }

    func openSNS(host: String, id: String, pathPrefix: String = "") {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)

        if let directURL = URL(string: trimmed),
           let scheme = directURL.scheme,
           !scheme.isEmpty {
            openURL(directURL)
            return
        }

        let cleanID = id.trimmingCharacters(in: .init(charactersIn: "@ /"))
        var comp = URLComponents(); comp.scheme = "https"; comp.host = host; comp.path = "/\(pathPrefix)\(cleanID)"
        if let url = comp.url { openURL(url) }
    }
    
    func snapshot() -> UIImage {
        let targetSize = UIScreen.main.bounds.size
        let controller = UIHostingController(rootView: self.edgesIgnoringSafeArea(.all))
        let window = UIWindow(frame: CGRect(origin: .zero, size: targetSize))
        window.rootViewController = controller
        window.isHidden = false

        let view = controller.view
        view?.frame = window.bounds
        view?.bounds = window.bounds
        view?.backgroundColor = .clear
        view?.setNeedsLayout()
        view?.layoutIfNeeded()
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let image = autoreleasepool {
            renderer.image { context in
                view?.layer.render(in: context.cgContext)
            }
        }
        window.isHidden = true
        window.rootViewController = nil
        return image
    }
}

private var oshiImageActionsMenuLabel: some View {
    Image(systemName: "ellipsis.circle")
        .font(.title3)
        .bold()
        .foregroundColor(.white)
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(Circle())
}

private struct ChekiWatermarkTextEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    let onSave: (String) -> Void

    init(initialText: String, onSave: @escaping (String) -> Void) {
        _text = State(initialValue: initialText)
        self.onSave = onSave
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                UIKitRoundedTextField(
                    text: $text,
                    placeholder: "透かしテキストを入力"
                )
                .frame(height: 36)

                if trimmedText.isEmpty {
                    Text("未入力の時は 推しライファー！ が表示されます。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
            .navigationTitle("透かしテキスト")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        onSave(text)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct UIKitRoundedTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.borderStyle = .roundedRect
        textField.placeholder = placeholder
        textField.clearButtonMode = .whileEditing
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.autocapitalizationType = .none
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.smartInsertDeleteType = .no
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        DispatchQueue.main.async {
            textField.becomeFirstResponder()
        }
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        if uiView.placeholder != placeholder {
            uiView.placeholder = placeholder
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        @objc func editingChanged(_ sender: UITextField) {
            text = sender.text ?? ""
        }
    }
}

private struct ChekiSaveSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = LocalStorage.load(ChekiSaveSettings.self, for: .chekiSaveSettings) ?? ChekiSaveSettings()
    @State private var previewOutputImage: UIImage? = nil
    @State private var showingWatermarkTextEditor = false
    @State private var pendingPreviewRefreshWorkItem: DispatchWorkItem? = nil
    let previewImage: UIImage?
    let previewProvider: ((ChekiSaveSettings) -> UIImage?)?
    let watermarkScale: CGFloat
    let showsBatchLayoutStyle: Bool
    let onSave: (ChekiSaveSettings) -> Void

    private var savedWatermarkText: String {
        LocalStorage.load(String.self, for: .chekiWatermarkText) ?? ""
    }

    var body: some View {
        NavigationStack {
            Form {
                if let previewOutputImage {
                    Section {
                        ChekiSavePreviewCard(image: previewOutputImage)
                    }
                }

                if showsBatchLayoutStyle {
                    Section("レイアウト") {
                        ForEach(ChekiBatchLayoutStyle.allCases) { style in
                            Button {
                                settings.batchLayoutStyle = style
                            } label: {
                                HStack(spacing: 12) {
                                    Text(style.title)
                                        .foregroundColor(.primary)

                                    Spacer()

                                    Image(systemName: settings.batchLayoutStyle == style ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(settings.batchLayoutStyle == style ? .accentColor : .secondary.opacity(0.35))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if settings.batchLayoutStyle == .corkboard || settings.batchLayoutStyle == .maskingTape {
                        Section("ボード背景") {
                            ForEach(ChekiCorkTextureStyle.allCases) { style in
                                Button {
                                    settings.corkTextureStyle = style
                                } label: {
                                    HStack {
                                        Text(style.title)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Image(systemName: settings.corkTextureStyle == style ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(settings.corkTextureStyle == style ? .accentColor : .secondary.opacity(0.35))
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("透かし") {
                    Toggle("透かしを入れる", isOn: $settings.isWatermarkEnabled)

                    if settings.isWatermarkEnabled && settings.watermarkStyle == .diagonalHearts {
                        Toggle("顔に透かしを入れない", isOn: $settings.excludesFacesFromWatermark)
                    }

                    ForEach(ChekiWatermarkStyle.allCases) { style in
                        Button {
                            settings.watermarkStyle = style
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(style.title)
                                        .foregroundColor(.primary)
                                    Text(style.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: settings.watermarkStyle == style ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(settings.watermarkStyle == style ? .accentColor : .secondary.opacity(0.35))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .disabled(!settings.isWatermarkEnabled)

                    Button {
                        showingWatermarkTextEditor = true
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("透かしテキスト")
                                    .foregroundColor(.primary)
                                Text(settings.watermarkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未入力" : settings.watermarkText)
                                    .font(.subheadline)
                                    .foregroundColor(settings.watermarkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .primary)
                                    .lineLimit(1)
                                if settings.watermarkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("未入力の時は 推しライファー！ が表示されます。")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!settings.isWatermarkEnabled)
                }
            }
            .navigationTitle("保存設定")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if settings.watermarkText != savedWatermarkText {
                    settings.watermarkText = savedWatermarkText
                }
                schedulePreviewRefresh(after: 0.12)
            }
            .onChange(of: settings) { oldValue, newValue in
                guard !settingsEqualIgnoringWatermarkText(oldValue, newValue) else { return }
                LocalStorage.save(newValue, for: .chekiSaveSettings)
                if oldValue.watermarkStyle != newValue.watermarkStyle ||
                    oldValue.isWatermarkEnabled != newValue.isWatermarkEnabled {
                    pendingPreviewRefreshWorkItem?.cancel()
                    pendingPreviewRefreshWorkItem = nil
                    previewOutputImage = nil
                    refreshPreview()
                } else {
                    schedulePreviewRefresh(after: 0.08)
                }
            }
            .onChange(of: showingWatermarkTextEditor) { _, isPresented in
                if isPresented {
                    pendingPreviewRefreshWorkItem?.cancel()
                    pendingPreviewRefreshWorkItem = nil
                    previewOutputImage = nil
                } else {
                    schedulePreviewRefresh(after: 0.12)
                }
            }
            .onDisappear {
                pendingPreviewRefreshWorkItem?.cancel()
                pendingPreviewRefreshWorkItem = nil
                previewOutputImage = nil
                DownsampledImageCache.shared.removeAll()
            }
            .sheet(isPresented: $showingWatermarkTextEditor) {
                ChekiWatermarkTextEditorSheet(initialText: settings.watermarkText) { newValue in
                    guard settings.watermarkText != newValue else { return }
                    settings.watermarkText = newValue
                    LocalStorage.save(settings, for: .chekiSaveSettings)
                    LocalStorage.save(newValue, for: .chekiWatermarkText)
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("写真に保存") {
                        previewOutputImage = nil
                        dismiss()
                        let finalSettings = settings
                        DispatchQueue.main.async {
                            onSave(finalSettings)
                        }
                    }
                }
            }
        }
    }

    private func refreshPreview() {
        if let previewProvider {
            previewOutputImage = previewProvider(settings)
            return
        }

        guard let previewImage else {
            previewOutputImage = nil
            return
        }

        previewOutputImage = ChekiWatermarkRenderer.watermarkedImage(
            from: previewImage,
            settings: settings,
            scale: watermarkScale
        )
    }

    private func schedulePreviewRefresh(after delay: TimeInterval) {
        pendingPreviewRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            refreshPreview()
        }
        pendingPreviewRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func settingsEqualIgnoringWatermarkText(_ lhs: ChekiSaveSettings, _ rhs: ChekiSaveSettings) -> Bool {
        lhs.isWatermarkEnabled == rhs.isWatermarkEnabled &&
        lhs.watermarkStyle == rhs.watermarkStyle &&
        lhs.excludesFacesFromWatermark == rhs.excludesFacesFromWatermark &&
        lhs.batchLayoutStyle == rhs.batchLayoutStyle &&
        lhs.corkTextureStyle == rhs.corkTextureStyle
    }
}

private struct ChekiFullscreenSaveView: View {
    let imageData: Data
    let rotationQuarterTurns: Int
    @Binding var isPresented: Bool

    @State private var showingChekiSaveSettings = false
    @State private var showSaveAlert = false
    @State private var saveAlertText = ""

    private let singleSaveWatermarkScale: CGFloat = 0.9

    init(
        imageData: Data,
        rotationQuarterTurns: Int = 0,
        isPresented: Binding<Bool>
    ) {
        self.imageData = imageData
        self.rotationQuarterTurns = rotationQuarterTurns
        self._isPresented = isPresented
    }

    private var effectiveImageData: Data {
        ChekiRotationHelper.rotatedImageData(from: imageData, quarterTurns: rotationQuarterTurns) ?? imageData
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation {
                        isPresented = false
                    }
                }

            VStack {
                HStack {
                    Button(action: {
                        withAnimation {
                            isPresented = false
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .bold()
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding()

                    Spacer()

                    Button(action: {
                        showingChekiSaveSettings = true
                    }) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.title3)
                            .bold()
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding()
                }

                Spacer()

                DownsampledDataImage(
                    cacheKey: "cheki-fullscreen-\(imageDataFingerprint(effectiveImageData))",
                    data: effectiveImageData,
                    maxPixelSize: 1800,
                    contentMode: .fit
                )
                .padding(10)

                Spacer()
            }

            if showSaveAlert {
                VStack {
                    Spacer()
                    Text(saveAlertText)
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                        .background(Color.black.opacity(0.7))
                        .clipShape(Capsule())
                        .padding(.bottom, 50)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(5)
            }
        }
        .sheet(isPresented: $showingChekiSaveSettings) {
            ChekiSaveSettingsView(
                previewImage: nil,
                previewProvider: { settings in
                    ChekiSaveCompositeRenderer.previewImage(
                        from: [effectiveImageData],
                        settings: settings,
                        watermarkScale: singleSaveWatermarkScale
                    )
                },
                watermarkScale: singleSaveWatermarkScale,
                showsBatchLayoutStyle: true
            ) { settings in
                guard let outputImage = ChekiSaveCompositeRenderer.saveImage(
                    from: [effectiveImageData],
                    settings: settings,
                    watermarkScale: singleSaveWatermarkScale
                ) else {
                    return
                }
                UIImageWriteToSavedPhotosAlbum(outputImage, nil, nil, nil)
                DownsampledImageCache.shared.removeAll()
                saveAlertText = settings.isWatermarkEnabled ? "透かし入りで保存しました" : "チェキを保存しました"
                withAnimation {
                    showSaveAlert = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation {
                        showSaveAlert = false
                        isPresented = false
                    }
                }
            }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onDisappear {
            showingChekiSaveSettings = false
            showSaveAlert = false
        }
    }
}

private struct OshiImageFullscreenView: View {
    @Binding var oshi: Oshi
    @ObservedObject var loader: OshiLoader
    let onSave: () -> Void
    let onClose: () -> Void

    @State private var showingOshiImagePlacementEditor = false
    @State private var showingOshiImageCandidatePicker = false
    @State private var isPreparingOshiImageCandidatePicker = false
    @State private var selectedOshiPhotoItem: PhotosPickerItem? = nil
    @State private var closeFullscreenAfterPlacementSave = false
    @State private var placementEditorImage: UIImage? = nil
    @State private var oshiImageCandidatePickerOptions: [OshiImageCandidateOption] = []
    @State private var oshiImageCandidateDisplayLimit = AppConfig.imageCandidateSelectionLimit

    private var currentOshiUIImage: UIImage? {
        guard let data = oshi.localImageData else { return nil }
        return UIImage(data: data)
    }

    private var canChooseOshiCandidateImage: Bool {
        oshi.kind == .person &&
        (oshi.agencyId?.isEmpty == false) &&
        (oshi.masterId?.isEmpty == false)
    }

    private var visibleOshiImageCandidatePickerOptions: [OshiImageCandidateOption] {
        Array(oshiImageCandidatePickerOptions.prefix(oshiImageCandidateDisplayLimit))
    }

    private var canShowMoreOshiImageCandidates: Bool {
        oshiImageCandidateDisplayLimit < oshiImageCandidatePickerOptions.count
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    onClose()
                }

            VStack {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .bold()
                            .foregroundColor(.white)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .padding()

                    Spacer()

                    HStack(spacing: 12) {
                        PhotosPicker(selection: $selectedOshiPhotoItem, matching: .images) {
                            Image(systemName: "photo.badge.plus")
                                .font(.title3)
                                .bold()
                                .foregroundColor(.white)
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }

                        Menu {
                            if canChooseOshiCandidateImage {
                                Button {
                                    Task {
                                        await openOshiImageCandidatePicker()
                                    }
                                } label: {
                                    Label("候補から選択", systemImage: "sparkles.square.filled.on.square")
                                }
                                .disabled(isPreparingOshiImageCandidatePicker || loader.isLoadingImageCandidates(for: oshi.agencyId))
                            }

                            Button {
                                Task {
                                    await openCurrentOshiImagePlacementEditor()
                                }
                            } label: {
                                Label("位置を調整する", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
                            }

                            Button(role: .destructive) {
                                restoreDefaultOshiImage()
                            } label: {
                                Label("デフォルト画像に戻す", systemImage: "arrow.uturn.backward")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                                .bold()
                                .foregroundColor(.white)
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                    }
                    .padding()
                }

                Spacer()

                OshiOriginalImage(oshi: oshi)
                    .frame(maxWidth: UIScreen.main.bounds.width - 48, maxHeight: UIScreen.main.bounds.height * 0.6)
                    .shadow(radius: 20)
                    .padding(.horizontal, 24)
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onEnded { value in
                                if abs(value.translation.height) > 60 || abs(value.translation.width) > 60 {
                                    onClose()
                                }
                            }
                    )

                Spacer()
            }
        }
        .onChange(of: selectedOshiPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let resizedData = ImageResizer.resizedJPEGData(
                    from: data,
                    maxLongEdge: 1200,
                    compressionQuality: 0.80
                   ),
                   UIImage(data: resizedData) != nil {
                    await MainActor.run {
                        oshi.selectedImageFileName = nil
                        oshi.localImageData = resizedData
                        oshi.iconThumbnailData = OshiIconThumbnailHelper.thumbnailData(
                            from: resizedData,
                            placement: .default
                        )
                        oshi.imagePlacement = .default
                        selectedOshiPhotoItem = nil
                        onSave()
                        showingOshiImagePlacementEditor = true
                    }
                } else {
                    await MainActor.run {
                        selectedOshiPhotoItem = nil
                    }
                }
            }
        }
        .onChange(of: showingOshiImagePlacementEditor) { _, isPresented in
            guard !isPresented, closeFullscreenAfterPlacementSave else { return }
            closeFullscreenAfterPlacementSave = false
            onClose()
        }
        .sheet(isPresented: $showingOshiImageCandidatePicker) {
            NavigationStack {
                GeometryReader { proxy in
                    let horizontalPadding: CGFloat = 16
                    let gridSpacing: CGFloat = 16
                    let columns = makeCandidatePickerColumns(
                        containerWidth: proxy.size.width,
                        horizontalPadding: horizontalPadding,
                        gridSpacing: gridSpacing
                    )

                    ScrollView {
                        VStack(spacing: 0) {
                            LazyVGrid(columns: columns, spacing: gridSpacing) {
                                ForEach(visibleOshiImageCandidatePickerOptions) { candidate in
                                    Button {
                                        showingOshiImageCandidatePicker = false
                                        Task {
                                            await applyOshiImageCandidate(candidate)
                                        }
                                    } label: {
                                        OshiImageCandidateCard(
                                            candidate: candidate,
                                            primaryText: oshiImageCandidatePrimaryLabel(candidate),
                                            secondaryText: oshiImageCandidateSecondaryLabel(candidate),
                                            isSelected: oshi.selectedImageFileName == candidate.fileName,
                                            cornerRadius: 18
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            if canShowMoreOshiImageCandidates {
                                CandidateLoadMoreButton {
                                    oshiImageCandidateDisplayLimit += AppConfig.imageCandidateSelectionLimit
                                }
                                .padding(.top, 4)
                            }
                        }
                        .padding(.horizontal, horizontalPadding)
                        .padding(.vertical, 20)
                    }
                }
                .navigationTitle("候補から選択")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") {
                            showingOshiImageCandidatePicker = false
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingOshiImagePlacementEditor) {
            if let placementEditorImage = placementEditorImage ?? currentOshiUIImage {
                OshiImagePlacementEditorView(
                    image: placementEditorImage,
                    initialPlacement: oshi.imagePlacement
                ) { updatedPlacement in
                    oshi.imagePlacement = updatedPlacement
                    oshi.iconThumbnailData = OshiIconThumbnailHelper.thumbnailData(
                        from: oshi.localImageData,
                        placement: updatedPlacement
                    )
                    onSave()
                    closeFullscreenAfterPlacementSave = true
                }
            }
        }
    }

    @MainActor
    private func openOshiImageCandidatePicker() async {
        guard let agencyId = oshi.agencyId, !agencyId.isEmpty,
              let masterId = oshi.masterId, !masterId.isEmpty else {
            return
        }

        isPreparingOshiImageCandidatePicker = true
        defer { isPreparingOshiImageCandidatePicker = false }

        var options = loader.imageCandidates(for: agencyId, masterId: masterId)
        if options.isEmpty {
            await loader.fetchImageCandidates(agencyId: agencyId)
            options = loader.imageCandidates(for: agencyId, masterId: masterId)
        }

        guard !options.isEmpty else { return }

        oshiImageCandidatePickerOptions = options
        oshiImageCandidateDisplayLimit = AppConfig.imageCandidateSelectionLimit
        showingOshiImageCandidatePicker = true
    }

    private func restoreDefaultOshiImage() {
        Task {
            await restoreDefaultOshiImageData()
        }
    }

    @MainActor
    private func openCurrentOshiImagePlacementEditor() async {
        if let currentOshiUIImage {
            placementEditorImage = currentOshiUIImage
            showingOshiImagePlacementEditor = true
            return
        }

        guard let imageURL = URL(string: oshi.resolvedRemoteImageURL), !oshi.resolvedRemoteImageURL.isEmpty else {
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: imageURL)
            guard let decoded = UIImage(data: data) else { return }
            placementEditorImage = decoded
            showingOshiImagePlacementEditor = true
        } catch {
        }
    }

    @MainActor
    private func applyOshiImageCandidate(_ candidate: OshiImageCandidateOption) async {
        guard let imageURL = URL(string: candidate.url) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: imageURL)
            guard UIImage(data: data) != nil else { return }

            oshi.selectedImageFileName = candidate.fileName
            oshi.localImageData = data
            oshi.iconThumbnailData = OshiIconThumbnailHelper.thumbnailData(
                from: data,
                placement: .default
            )
            oshi.imagePlacement = .default
            onSave()
            showingOshiImagePlacementEditor = true
        } catch {
        }
    }

    @MainActor
    private func restoreDefaultOshiImageData() async {
        let resolvedDefaultURLString = resolvedDefaultImageURLString()
        guard let defaultURL = URL(string: resolvedDefaultURLString), !resolvedDefaultURLString.isEmpty else {
            oshi.selectedImageFileName = nil
            oshi.localImageData = nil
            oshi.iconThumbnailData = nil
            oshi.originalImageData = nil
            oshi.imagePlacement = .default
            onSave()
            onClose()
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: defaultURL)
            guard let resizedData = ImageResizer.resizedJPEGData(
                from: data,
                maxLongEdge: 1200,
                compressionQuality: 0.80
            ),
            UIImage(data: resizedData) != nil else { return }
            oshi.imageURL = resolvedDefaultURLString
            oshi.selectedImageFileName = nil
            oshi.localImageData = resizedData
            oshi.iconThumbnailData = OshiIconThumbnailHelper.thumbnailData(
                from: resizedData,
                placement: .default
            )
            oshi.originalImageData = resizedData
            oshi.imagePlacement = .default
            onSave()
            onClose()
        } catch {
            onClose()
        }
    }

    private func resolvedDefaultImageURLString() -> String {
        if oshi.kind == .group,
           let masterId = oshi.masterId,
           let matched = loader.displayGroupOshis.first(where: { $0.masterId == masterId }) {
            return matched.imageURL
        }

        if let masterId = oshi.masterId,
           let matched = loader.displayOshis.first(where: { $0.masterId == masterId }) {
            return matched.imageURL
        }

        return oshi.imageURL
    }

    private func oshiImageCandidatePrimaryLabel(_ candidate: OshiImageCandidateOption) -> String {
        if let label = candidate.eventLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !label.isEmpty {
            return label
        }

        if let caption = meaningfulCandidateCaption(candidate.caption) {
            return caption
        }

        if let yearMonth = formattedCandidateYearMonth(candidate.yearMonth) {
            return yearMonth
        }

        return candidate.fileName
    }

    private func oshiImageCandidateSecondaryLabel(_ candidate: OshiImageCandidateOption) -> String? {
        if candidate.eventLabel != nil,
           let caption = meaningfulCandidateCaption(candidate.caption),
           caption != oshiImageCandidatePrimaryLabel(candidate) {
            return caption
        }

        return formattedCandidateYearMonth(candidate.yearMonth)
    }

    private func meaningfulCandidateCaption(_ caption: String?) -> String? {
        guard let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              Int(trimmed) == nil else {
            return nil
        }
        return trimmed
    }

    private func formattedCandidateYearMonth(_ yearMonth: String?) -> String? {
        guard let value = yearMonth?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"

        guard let date = formatter.date(from: value) else {
            return value
        }

        let output = DateFormatter()
        output.locale = Locale(identifier: "en_US_POSIX")
        output.dateFormat = "MMM yyyy"
        return output.string(from: date)
    }
}

// キラキラ演出ビュー（比較用の軽量版を残す）
#if false
private struct SparkleViewPulseCanvas: View {
    let isOnLightBackground: Bool
    private enum SymbolID: Hashable {
        case heart
    }

    struct Sparkle: Identifiable {
        let id = UUID()
        let backgroundSize: CGFloat
        let middleSize: CGFloat
        let foregroundSize: CGFloat
        let x: CGFloat
        let y: CGFloat
        let duration: Double
        let delay: Double
    }

    let screenW = UIScreen.main.bounds.width
    let screenH = UIScreen.main.bounds.height
    private let sparkles: [Sparkle]

    private var foregroundColor: Color {
        isOnLightBackground ? Color(red: 0.95, green: 0.54, blue: 0.74) : .white
    }

    init(isOnLightBackground: Bool = false) {
        self.isOnLightBackground = isOnLightBackground
        let screenW = UIScreen.main.bounds.width
        let screenH = UIScreen.main.bounds.height
        self.sparkles = (0..<40).map { _ in
            Sparkle(
                backgroundSize: CGFloat.random(in: 30...60),
                middleSize: CGFloat.random(in: 15...35),
                foregroundSize: CGFloat.random(in: 10...25),
                x: CGFloat.random(in: 0...screenW),
                y: CGFloat.random(in: 0...screenH),
                duration: Double.random(in: 6.0...10.0),
                delay: Double.random(in: 0...4.0)
            )
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { timeline in
            Canvas { context, size in
                guard let heart = context.resolveSymbol(id: SymbolID.heart) else { return }

                let now = timeline.date.timeIntervalSinceReferenceDate

                for sparkle in sparkles {
                    let delayedTime = max(0, now - sparkle.delay)
                    let cycle = delayedTime / sparkle.duration
                    let oscillation = 0.5 - (0.5 * cos(cycle * .pi * 2))
                    let pulse = 0.8 + (0.4 * oscillation)
                    let alpha = 0.4 + (0.6 * oscillation)

                    let drawSide = sparkle.foregroundSize * pulse
                    let drawSize = CGSize(width: drawSide, height: drawSide)
                    let origin = CGPoint(
                        x: sparkle.x - drawSize.width / 2,
                        y: sparkle.y - drawSize.height / 2
                    )

                    context.opacity = alpha
                    context.draw(heart, in: CGRect(origin: origin, size: drawSize))
                }
            } symbols: {
                Image(systemName: "heart.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(foregroundColor.opacity(0.78))
                    .tag(SymbolID.heart)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct SparkleViewDriftCanvas: View {
    let oshiColor: Color
    let isOnLightBackground: Bool
    
    private enum SymbolID: Hashable {
        case background, middle, foreground
    }

    struct Sparkle: Identifiable {
        let id = UUID()
        let bgSize: CGFloat
        let mdSize: CGFloat
        let fgSize: CGFloat
        let x: CGFloat
        let y: CGFloat
        let duration: Double
        let delay: Double
        let driftX: CGFloat
        let driftY: CGFloat
    }

    private let sparkles: [Sparkle]

    init(oshiColor: Color, isOnLightBackground: Bool = false) {
        self.oshiColor = oshiColor
        self.isOnLightBackground = isOnLightBackground
        let screenW = UIScreen.main.bounds.width
        let screenH = UIScreen.main.bounds.height
        
        self.sparkles = (0..<40).map { _ in
            let baseSize = CGFloat.random(in: 15...30)
            return Sparkle(
                bgSize: baseSize * 2.5,
                mdSize: baseSize * 1.4,
                fgSize: baseSize,
                x: CGFloat.random(in: 0...screenW),
                y: CGFloat.random(in: 0...screenH),
                duration: Double.random(in: 4.0...7.0),
                delay: Double.random(in: 0...4.0),
                driftX: CGFloat.random(in: -40...40),
                driftY: CGFloat.random(in: -70 ... -30)
            )
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                guard let bg = context.resolveSymbol(id: SymbolID.background),
                      let md = context.resolveSymbol(id: SymbolID.middle),
                      let fg = context.resolveSymbol(id: SymbolID.foreground) else { return }

                let now = timeline.date.timeIntervalSinceReferenceDate

                for sparkle in sparkles {
                    let time = max(0, now - sparkle.delay)
                    let t = (time.truncatingRemainder(dividingBy: sparkle.duration)) / sparkle.duration
                    let alpha = sin(t * .pi) 
                    
                    // 浮遊ロジック：左右にゆらぎつつ上昇
                    let currentX = sparkle.x + (sparkle.driftX * sin(t * .pi))
                    let currentY = sparkle.y + (sparkle.driftY * t)
                    let scale = 0.8 + (0.4 * alpha) 
                    let center = CGPoint(x: currentX, y: currentY)

                    // 1. 最背面：広範囲に広がる「光のぼかし」
                    context.opacity = alpha * (isOnLightBackground ? 0.2 : 0.3)
                    drawSymbol(context, symbol: bg, center: center, size: sparkle.bgSize * scale)

                    // 2. 中間：ネオンのような光の輪
                    context.opacity = alpha * (isOnLightBackground ? 0.8 : 0.6)
                    drawSymbol(context, symbol: md, center: center, size: sparkle.mdSize * scale)

                    // 3. 最前面：パキッとした芯
                    context.opacity = alpha
                    drawSymbol(context, symbol: fg, center: center, size: sparkle.fgSize * scale)
                }
            } symbols: {
                // 3つの層を定義
                Image(systemName: "heart.fill")
                    .resizable()
                    .foregroundStyle(oshiColor)
                    .blur(radius: 12)
                    .tag(SymbolID.background)

                Image(systemName: "heart.fill")
                    .resizable()
                    .foregroundStyle(oshiColor)
                    .blur(radius: 4)
                    .tag(SymbolID.middle)

                Image(systemName: "heart.fill")
                    .resizable()
                    .foregroundStyle(isOnLightBackground ? oshiColor : .white)
                    .tag(SymbolID.foreground)
            }
        }
        .allowsHitTesting(false)
    }

    // 描画用の補助関数
    private func drawSymbol(_ context: GraphicsContext, symbol: GraphicsContext.ResolvedSymbol, center: CGPoint, size: CGFloat) {
        context.draw(symbol, in: CGRect(x: center.x - size/2, y: center.y - size/2, width: size, height: size))
    }
}

private struct SparkleViewRebirthCanvas: View {
    @Environment(\.scenePhase) private var scenePhase
    let isOnLightBackground: Bool

    private enum SymbolID: Hashable {
        case backgroundHeart
        case middleHeart
        case foregroundHeart
    }

    struct Sparkle: Identifiable {
        let id = UUID()
        let backgroundSize: CGFloat
        let middleSize: CGFloat
        let foregroundSize: CGFloat
        let x: CGFloat
        let y: CGFloat
        let duration: Double
        let delay: Double
    }

    @State private var animate = false
    @State private var animationStartDate = Date()

    let screenW = UIScreen.main.bounds.width
    let screenH = UIScreen.main.bounds.height
    private let sparkles: [Sparkle]

    private var backgroundGlowColor: Color {
        isOnLightBackground ? Color(red: 0.995, green: 0.72, blue: 0.84) : .white
    }

    private var middleGlowColor: Color {
        isOnLightBackground ? Color(red: 0.97, green: 0.54, blue: 0.74) : .white
    }

    private var foregroundColor: Color {
        isOnLightBackground ? Color(red: 0.95, green: 0.54, blue: 0.74) : .white
    }

    private var outlineShadowColor: Color {
        isOnLightBackground ? Color.black.opacity(0.04) : Color.white.opacity(0.85)
    }

    init(isOnLightBackground: Bool = false) {
        self.isOnLightBackground = isOnLightBackground
        let screenW = UIScreen.main.bounds.width
        let screenH = UIScreen.main.bounds.height
        self.sparkles = (0..<40).map { _ in
            Sparkle(
                backgroundSize: CGFloat.random(in: 30...60),
                middleSize: CGFloat.random(in: 15...35),
                foregroundSize: CGFloat.random(in: 10...25),
                x: CGFloat.random(in: 0...screenW),
                y: CGFloat.random(in: 0...screenH),
                duration: Double.random(in: 2.5...4.5),
                delay: Double.random(in: 0...3.0)
            )
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { timeline in
            Canvas { context, size in
                guard
                    let backgroundHeart = context.resolveSymbol(id: SymbolID.backgroundHeart),
                    let middleHeart = context.resolveSymbol(id: SymbolID.middleHeart),
                    let foregroundHeart = context.resolveSymbol(id: SymbolID.foregroundHeart)
                else { return }

                let now = timeline.date

                for sparkle in sparkles {
                    let pulse: CGFloat
                    let alpha: CGFloat

                    if animate {
                        let elapsed = max(0, now.timeIntervalSince(animationStartDate) - sparkle.delay)
                        let cycleProgress = elapsed / (sparkle.duration * 2.0)
                        let oscillation = 0.5 - (0.5 * cos(cycleProgress * .pi * 2))
                        pulse = 0.8 + (0.4 * oscillation)
                        alpha = 0.4 + (0.6 * oscillation)
                    } else {
                        pulse = 0.8
                        alpha = 0.4
                    }

                    let center = CGPoint(x: sparkle.x, y: sparkle.y)
                    let backgroundSide = sparkle.backgroundSize * pulse
                    let middleSide = sparkle.middleSize * pulse
                    let foregroundSide = sparkle.foregroundSize * pulse

                    context.opacity = alpha * (isOnLightBackground ? 0.22 : 0.30)
                    context.draw(
                        backgroundHeart,
                        in: CGRect(
                            x: center.x - backgroundSide / 2,
                            y: center.y - backgroundSide / 2,
                            width: backgroundSide,
                            height: backgroundSide
                        )
                    )

                    context.opacity = alpha * (isOnLightBackground ? 0.82 : 0.60)
                    context.draw(
                        middleHeart,
                        in: CGRect(
                            x: center.x - middleSide / 2,
                            y: center.y - middleSide / 2,
                            width: middleSide,
                            height: middleSide
                        )
                    )

                    context.opacity = alpha
                    context.draw(
                        foregroundHeart,
                        in: CGRect(
                            x: center.x - foregroundSide / 2,
                            y: center.y - foregroundSide / 2,
                            width: foregroundSide,
                            height: foregroundSide
                        )
                    )
                }
            } symbols: {
                Image(systemName: "heart.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(backgroundGlowColor.opacity(isOnLightBackground ? 0.22 : 0.30))
                    .blur(radius: 10)
                    .tag(SymbolID.backgroundHeart)

                Image(systemName: "heart.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(middleGlowColor.opacity(isOnLightBackground ? 0.82 : 0.60))
                    .shadow(color: outlineShadowColor, radius: 8)
                    .tag(SymbolID.middleHeart)

                Image(systemName: "heart.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(foregroundColor)
                    .tag(SymbolID.foregroundHeart)
            }
        }
        .onAppear {
            animate = false
            animationStartDate = Date()
            DispatchQueue.main.async {
                animationStartDate = Date()
                animate = true
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            animate = false
            animationStartDate = Date()
            DispatchQueue.main.async {
                animationStartDate = Date()
                animate = true
            }
        }
        .onDisappear {
            animate = false
        }
        .allowsHitTesting(false)
    }
}
#endif

private struct SparkleViewBackup: View {
    @Environment(\.scenePhase) private var scenePhase
    let isOnLightBackground: Bool
    struct Sparkle: Identifiable {
        let id = UUID()
        let backgroundSize: CGFloat
        let middleSize: CGFloat
        let foregroundSize: CGFloat
        let x: CGFloat
        let y: CGFloat
        let duration: Double
        let delay: Double
    }

    @State private var animate = false
    let screenW = UIScreen.main.bounds.width
    let screenH = UIScreen.main.bounds.height
    private let sparkles: [Sparkle]

    private var backgroundGlowColor: Color {
        isOnLightBackground ? Color(red: 0.995, green: 0.72, blue: 0.84) : .white
    }

    private var middleGlowColor: Color {
        isOnLightBackground ? Color(red: 0.97, green: 0.54, blue: 0.74) : .white
    }

    private var foregroundColor: Color {
        isOnLightBackground ? Color(red: 0.95, green: 0.54, blue: 0.74) : .white
    }

    private var outlineShadowColor: Color {
        isOnLightBackground ? Color.black.opacity(0.04) : Color.white.opacity(0.85)
    }

    init(isOnLightBackground: Bool = false) {
        self.isOnLightBackground = isOnLightBackground
        let screenW = UIScreen.main.bounds.width
        let screenH = UIScreen.main.bounds.height
        self.sparkles = (0..<40).map { _ in
            Sparkle(
                backgroundSize: CGFloat.random(in: 30...60),
                middleSize: CGFloat.random(in: 15...35),
                foregroundSize: CGFloat.random(in: 10...25),
                x: CGFloat.random(in: 0...screenW),
                y: CGFloat.random(in: 0...screenH),
                duration: Double.random(in: 2.5...4.5),
                delay: Double.random(in: 0...3)
            )
        }
    }

    var body: some View {
        ZStack {
            ForEach(sparkles) { sparkle in
                ZStack {
                    // 1. 最背面：広範囲に広がる「光のぼかし」
                    Image(systemName: "heart.fill")
                        .font(.system(size: sparkle.backgroundSize))
                        .foregroundColor(backgroundGlowColor.opacity(isOnLightBackground ? 0.22 : 0.3))
                        .blur(radius: 10)

                    // 2. 中間：ネオンのような光の輪
                    Image(systemName: "heart.fill")
                        .font(.system(size: sparkle.middleSize))
                        .foregroundColor(middleGlowColor.opacity(isOnLightBackground ? 0.82 : 0.6))
                        .shadow(color: outlineShadowColor, radius: 8)

                    // 3. 最前面：パキッとした白い芯
                    Image(systemName: "heart.fill")
                        .font(.system(size: sparkle.foregroundSize))
                        .foregroundColor(foregroundColor)
                }
                .position(
                    x: sparkle.x,
                    y: sparkle.y
                )
                // ふわふわ・チカチカの強調
                .scaleEffect(animate ? 1.2 : 0.8)
                .opacity(animate ? 1.0 : 0.4)
                .animation(
                    Animation.easeInOut(duration: sparkle.duration)
                        .repeatForever(autoreverses: true)
                        .delay(sparkle.delay),
                    value: animate
                )
            }
        }
        .onAppear {
            animate = false
            DispatchQueue.main.async {
                animate = true
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            animate = false
            DispatchQueue.main.async {
                animate = true
            }
        }
        .onDisappear {
            animate = false
        }
        .allowsHitTesting(false)
    }
}

struct SparkleViewRebirth: View {
    @Environment(\.scenePhase) private var scenePhase
    let isOnLightBackground: Bool

    private enum SymbolID: Hashable {
        case backgroundHeart
        case middleHeart
        case foregroundHeart
    }

    struct Sparkle: Identifiable {
        let id = UUID()
        let backgroundSize: CGFloat
        let middleSize: CGFloat
        let foregroundSize: CGFloat
        let x: CGFloat
        let y: CGFloat
        let duration: Double
        let delay: Double
    }

    @State private var animationStartDate = Date()
    @State private var animate = false

    private let screenW = UIScreen.main.bounds.width
    private let screenH = UIScreen.main.bounds.height
    private let sparkleCount = 40
    private let rebirthInterval: TimeInterval = 2.4
    private let rebirthTransitionDuration: TimeInterval = 0.8

    private var backgroundGlowColor: Color {
        isOnLightBackground ? Color(red: 0.995, green: 0.72, blue: 0.84) : .white
    }

    private var middleGlowColor: Color {
        isOnLightBackground ? Color(red: 0.97, green: 0.54, blue: 0.74) : .white
    }

    private var foregroundColor: Color {
        isOnLightBackground ? Color(red: 0.95, green: 0.54, blue: 0.74) : .white
    }

    private var outlineShadowColor: Color {
        isOnLightBackground ? Color.black.opacity(0.04) : Color.white.opacity(0.85)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { timeline in
            Canvas { context, size in
                guard
                    let backgroundHeart = context.resolveSymbol(id: SymbolID.backgroundHeart),
                    let middleHeart = context.resolveSymbol(id: SymbolID.middleHeart),
                    let foregroundHeart = context.resolveSymbol(id: SymbolID.foregroundHeart)
                else { return }

                let now = timeline.date
                let elapsed = max(0, now.timeIntervalSince(animationStartDate))
                let rebirthPhase = elapsed / rebirthInterval
                let rebirthIndex = Int(floor(rebirthPhase))
                let rebirthCycleProgress = rebirthPhase - floor(rebirthPhase)
                let rebirthProgress = min(1, rebirthCycleProgress / rebirthTransitionDuration)
                let easedRebirthProgress = rebirthProgress * rebirthProgress * (3 - 2 * rebirthProgress)

                let currentLayout = sparkleLayout(seed: rebirthIndex)
                let nextLayout = sparkleLayout(seed: rebirthIndex + 1)

                for index in 0..<sparkleCount {
                    let current = currentLayout[index]
                    let next = nextLayout[index]

                    let pulse: CGFloat
                    let alpha: CGFloat

                    if animate {
                        let sparkleElapsed = max(0, elapsed - current.delay)
                        let cycleProgress = sparkleElapsed / (current.duration * 2.0)
                        let oscillation = 0.5 - (0.5 * cos(cycleProgress * .pi * 2))
                        pulse = 0.8 + (0.4 * oscillation)
                        alpha = 0.4 + (0.6 * oscillation)
                    } else {
                        pulse = 0.8
                        alpha = 0.4
                    }

                    let center = CGPoint(
                        x: lerp(current.x, next.x, easedRebirthProgress),
                        y: lerp(current.y, next.y, easedRebirthProgress)
                    )

                    let backgroundSize = lerp(current.backgroundSize, next.backgroundSize, easedRebirthProgress) * pulse
                    let middleSize = lerp(current.middleSize, next.middleSize, easedRebirthProgress) * pulse
                    let foregroundSize = lerp(current.foregroundSize, next.foregroundSize, easedRebirthProgress) * pulse

                    context.opacity = alpha * (isOnLightBackground ? 0.22 : 0.30)
                    context.draw(
                        backgroundHeart,
                        in: CGRect(
                            x: center.x - backgroundSize / 2,
                            y: center.y - backgroundSize / 2,
                            width: backgroundSize,
                            height: backgroundSize
                        )
                    )

                    context.opacity = alpha * (isOnLightBackground ? 0.82 : 0.60)
                    context.draw(
                        middleHeart,
                        in: CGRect(
                            x: center.x - middleSize / 2,
                            y: center.y - middleSize / 2,
                            width: middleSize,
                            height: middleSize
                        )
                    )

                    context.opacity = alpha
                    context.draw(
                        foregroundHeart,
                        in: CGRect(
                            x: center.x - foregroundSize / 2,
                            y: center.y - foregroundSize / 2,
                            width: foregroundSize,
                            height: foregroundSize
                        )
                    )
                }
            } symbols: {
                Image(systemName: "heart.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(backgroundGlowColor.opacity(isOnLightBackground ? 0.22 : 0.30))
                    .blur(radius: 10)
                    .tag(SymbolID.backgroundHeart)

                Image(systemName: "heart.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(middleGlowColor.opacity(isOnLightBackground ? 0.82 : 0.60))
                    .shadow(color: outlineShadowColor, radius: 8)
                    .tag(SymbolID.middleHeart)

                Image(systemName: "heart.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(foregroundColor)
                    .tag(SymbolID.foregroundHeart)
            }
        }
        .onAppear {
            animationStartDate = Date()
            animate = false
            DispatchQueue.main.async {
                animationStartDate = Date()
                animate = true
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            animationStartDate = Date()
            animate = false
            DispatchQueue.main.async {
                animationStartDate = Date()
                animate = true
            }
        }
        .onDisappear {
            animate = false
        }
        .allowsHitTesting(false)
    }

    private func sparkleLayout(seed: Int) -> [Sparkle] {
        var generator = SeededGenerator(seed: UInt64(max(seed, 0) + 1))
        return (0..<sparkleCount).map { _ in
            Sparkle(
                backgroundSize: CGFloat.random(in: 30...60, using: &generator),
                middleSize: CGFloat.random(in: 15...35, using: &generator),
                foregroundSize: CGFloat.random(in: 10...25, using: &generator),
                x: CGFloat.random(in: 0...screenW, using: &generator),
                y: CGFloat.random(in: 0...screenH, using: &generator),
                duration: Double.random(in: 2.5...4.5, using: &generator),
                delay: Double.random(in: 0...3, using: &generator)
            )
        }
    }

    private func lerp(_ from: CGFloat, _ to: CGFloat, _ progress: CGFloat) -> CGFloat {
        from + ((to - from) * progress)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

struct SparkleView: View {
    let oshiColor: Color
    let isOnLightBackground: Bool

    private enum SymbolID: Hashable {
        case backgroundHeart
        case foregroundHeart
    }

    struct Sparkle: Identifiable {
        let id = UUID()
        let sizeBase: CGFloat
        let x: CGFloat
        let y: CGFloat
        let duration: Double
        let delay: Double
        let travelY: CGFloat
    }

    private let sparkles: [Sparkle]

    init(oshiColor: Color, isOnLightBackground: Bool = false) {
        self.oshiColor = oshiColor
        self.isOnLightBackground = isOnLightBackground
        let screenW = UIScreen.main.bounds.width
        let screenH = UIScreen.main.bounds.height

        self.sparkles = (0..<40).map { _ in
            Sparkle(
                sizeBase: CGFloat.random(in: 15...35),
                x: CGFloat.random(in: 0...screenW),
                y: CGFloat.random(in: 0...screenH),
                duration: Double.random(in: 3.0...5.0),
                delay: Double.random(in: 0...3.0),
                travelY: CGFloat.random(in: -50 ... -30)
            )
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                guard
                    let backgroundHeart = context.resolveSymbol(id: SymbolID.backgroundHeart),
                    let foregroundHeart = context.resolveSymbol(id: SymbolID.foregroundHeart)
                else { return }

                let now = timeline.date.timeIntervalSinceReferenceDate

                for sparkle in sparkles {
                    let relativeTime = max(0, now - sparkle.delay)
                    let progress = (relativeTime.truncatingRemainder(dividingBy: sparkle.duration)) / sparkle.duration

                    let currentY = sparkle.y + (sparkle.travelY * progress)
                    let alpha = sin(progress * .pi)
                    let scale = 0.8 + (0.4 * alpha)

                    let center = CGPoint(x: sparkle.x, y: currentY)
                    let drawSize = sparkle.sizeBase * scale

                    context.opacity = alpha * (isOnLightBackground ? 0.22 : 0.30)
                    context.draw(
                        backgroundHeart,
                        in: CGRect(
                            x: center.x - drawSize,
                            y: center.y - drawSize,
                            width: drawSize * 2,
                            height: drawSize * 2
                        )
                    )

                    context.opacity = alpha
                    context.draw(
                        foregroundHeart,
                        in: CGRect(
                            x: center.x - drawSize / 2,
                            y: center.y - drawSize / 2,
                            width: drawSize,
                            height: drawSize
                        )
                    )
                }
            } symbols: {
                Image(systemName: "heart.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(oshiColor)
                    .blur(radius: 6)
                    .tag(SymbolID.backgroundHeart)

                Image(systemName: "heart.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(oshiColor)
                    .tag(SymbolID.foregroundHeart)
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    func snapshot() -> UIImage {
        let controller = UIHostingController(rootView: self)
        let view = controller.view

        let targetSize = controller.view.intrinsicContentSize
        view?.bounds = CGRect(origin: .zero, size: targetSize)
        view?.backgroundColor = .clear

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            view?.drawHierarchy(in: view?.bounds ?? .zero, afterScreenUpdates: true)
        }
    }
}

enum ImageResizer {
    static func resizedJPEGData(from data: Data, maxLongEdge: CGFloat = 1600, compressionQuality: CGFloat = 0.82) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        let originalSize = image.size
        let longEdge = max(originalSize.width, originalSize.height)

        guard longEdge > maxLongEdge else {
            return image.jpegData(compressionQuality: compressionQuality) ?? data
        }

        let scale = maxLongEdge / longEdge
        let targetSize = CGSize(width: originalSize.width * scale, height: originalSize.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return resizedImage.jpegData(compressionQuality: compressionQuality)
    }
}

struct ConfettiPiece: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let endX: CGFloat
    let endY: CGFloat
    let color: Color
    let size: CGFloat
    let symbolName: String
}

struct ConfettiView: View {
    @State private var animate = false
    private let pieces: [ConfettiPiece]
    let origin: CGPoint // タップした位置
    let color: Color

    init(origin: CGPoint, color: Color) {
        self.origin = origin
        self.color = color
        self.pieces = (0..<22).map { _ in
            let velocity = CGSize(width: .random(in: -300...300), height: .random(in: -500...100))
            return ConfettiPiece(
                x: origin.x,
                y: origin.y,
                endX: origin.x + velocity.width,
                endY: origin.y + velocity.height + 600,
                color: [color, .white, .yellow].randomElement()!,
                size: .random(in: 10...25),
                symbolName: ["heart.fill", "sparkles", "star.fill"].randomElement()!
            )
        }
    }

    var body: some View {
        ZStack {
            ForEach(pieces) { piece in
                Image(systemName: piece.symbolName)
                    .font(.system(size: piece.size))
                    .foregroundColor(piece.color)
                    .position(
                        x: animate ? piece.endX : piece.x,
                        y: animate ? piece.endY : piece.y
                    )
            }
        }
        .onAppear {
            animate = false
            withAnimation(.easeOut(duration: 1.5)) {
                animate = true
            }
        }
        .onDisappear {
            animate = false
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 5. チェキ帳
private enum ChekiSelectionPurpose {
    case delete
    case screenshot
}

private struct ChekiBatchSaveContext: Identifiable {
    let id = UUID()
    let imageDataList: [Data]

    var selectionCount: Int {
        imageDataList.count
    }

    var watermarkScale: CGFloat {
        switch selectionCount {
        case 0, 1: return 0.9
        case 2: return 0.82
        case 3, 4: return 0.74
        case 5, 6: return 0.66
        default: return 0.58
        }
    }
}

struct ChekiGalleryView: View {
    private enum ChekiDisplayMode: Int, CaseIterable, Hashable {
        case byOshi
        case favorites
        case byMonth
    }

    @Binding var myOshis: [Oshi]
    @Binding var myChekis: [Cheki]
    @Binding var profile: UserProfile
    
    @State private var isScan = false
    @State private var tmpImg: Data? = nil
    @State private var tmpDateString: String? = nil
    @State private var tmpScanDebugMessage: String? = nil
    @State private var isAssign = false
    @State private var selectedCheki: Cheki? = nil
    
    @State private var displayMode: ChekiDisplayMode = .byOshi
    @State private var isAscending = false // 月別用のソート順
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var isSelectingChekis = false
    @State private var chekiSelectionPurpose: ChekiSelectionPurpose = .delete
    @State private var selectedChekiIDs: Set<UUID> = []
    @State private var selectedChekiOrder: [UUID] = []
    @State private var showingBulkDeleteAlert = false
    @State private var chekiBatchSaveContext: ChekiBatchSaveContext? = nil
    @State private var showingChekiSelectionLimitAlert = false
    @State private var showChekiBatchSaveAlert = false
    @State private var chekiBatchSaveAlertText = ""
    @State private var chekiGalleryRefreshToken = UUID()

    private let maxChekiBatchSelectionCount = 9

    private var displayedChekis: [Cheki] {
        switch displayMode {
        case .favorites:
            return myChekis.filter(\.isFavorite)
        default:
            return myChekis
        }
    }

    private var allVisibleChekisSelected: Bool {
        let visibleIDs = Set(displayedChekis.map(\.id))
        return !visibleIDs.isEmpty && visibleIDs.isSubset(of: selectedChekiIDs)
    }

    private var visibleChekisInDisplayOrder: [Cheki] {
        switch displayMode {
        case .byOshi:
            let groupedByOshi = Dictionary(grouping: myChekis) { $0.oshiID }
            var result: [Cheki] = []

            for oshi in myOshis {
                if let chekis = groupedByOshi[oshi.id] {
                    result.append(contentsOf: sortedChekisForDisplay(chekis))
                }
            }

            if let otherChekis = groupedByOshi[AppConfig.otherID] {
                result.append(contentsOf: sortedChekisForDisplay(otherChekis))
            }

            return result

        case .byMonth:
            let groupedByMonth = Dictionary(grouping: myChekis) { formatMonth($0.date) }
            let sortedMonths = groupedByMonth.keys.sorted { a, b in
                if isAscending {
                    if a == "日付なし" { return true }
                    if b == "日付なし" { return false }
                    return a < b
                } else {
                    if a == "日付なし" { return false }
                    if b == "日付なし" { return true }
                    return a > b
                }
            }

            return sortedMonths.flatMap { month in
                sortedChekisForDisplay(groupedByMonth[month] ?? [])
            }

        case .favorites:
            let favoriteChekis = myChekis.filter(\.isFavorite)
            let groupedByOshi = Dictionary(grouping: favoriteChekis) { $0.oshiID }
            var result: [Cheki] = []

            for oshi in myOshis {
                if let chekis = groupedByOshi[oshi.id] {
                    result.append(contentsOf: sortedChekisForDisplay(chekis))
                }
            }

            if let otherChekis = groupedByOshi[AppConfig.otherID] {
                result.append(contentsOf: sortedChekisForDisplay(otherChekis))
            }

            return result
        }
    }

    private var screenshotSelectableIDs: [UUID] {
        Array(visibleChekisInDisplayOrder.map(\.id).prefix(maxChekiBatchSelectionCount))
    }

    private var allSelectableScreenshotChekisSelected: Bool {
        let selectable = Set(screenshotSelectableIDs)
        return !selectable.isEmpty && selectable.isSubset(of: selectedChekiIDs)
    }

    private var selectedChekiCountText: String {
        if chekiSelectionPurpose == .screenshot {
            return "\(selectedChekiOrder.count)/\(maxChekiBatchSelectionCount)枚選択中"
        }
        return "\(selectedChekiIDs.count)件選択中"
    }

    private var batchSaveButtonTitle: String {
        if selectedChekiOrder.count == 1 {
            return "1枚を保存"
        }
        return "\(selectedChekiOrder.count)枚をまとめて保存"
    }

    private var chekiGalleryTitleView: some View {
        Text("チェキ帳")
            .font(AppTypography.navigationTitleFont(for: profile.preferredAppFont, size: 18))
            .foregroundColor(.primary)
            .tracking(-0.5)
    }

    private var chekiGalleryTrailingToolbar: some View {
        HStack(spacing: 15) {
            if !isSelectingChekis {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Image(systemName: "photo.badge.plus")
                }
                Button { isScan = true } label: {
                    Image(systemName: "camera.fill")
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var chekiGalleryToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            chekiGalleryTitleView
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            chekiGalleryTrailingToolbar
        }
    }

    private var chekiBulkDeleteMessage: Text {
        Text("選択したチェキが削除されます。この操作は取り消せません。")
    }

    private func applyChekiGalleryPresentations<Content: View>(to view: Content) -> some View {
        view
            .onChange(of: selectedItem) { _, newItem in
                handleSelectedChekiPhotoItemChange(newItem)
            }
            .sheet(isPresented: $isScan) {
                ScanIdolCheki(
                    scannedData: $tmpImg,
                    detectedDateString: $tmpDateString,
                    debugMessage: $tmpScanDebugMessage
                )
            }
            .onChange(of: tmpImg) { _, nv in
                handleTmpChekiImageChange(nv)
            }
            .sheet(isPresented: $isAssign) {
                AssignChekiView(
                    myOshis: $myOshis,
                    myChekis: $myChekis,
                    imageData: $tmpImg,
                    detectedDateString: $tmpDateString,
                    scanDebugMessage: $tmpScanDebugMessage
                )
            }
            .sheet(item: $selectedCheki, onDismiss: refreshChekiGalleryLayout) { cheki in
                ChekiDetailView(cheki: cheki, myOshis: $myOshis, myChekis: $myChekis)
            }
            .sheet(item: $chekiBatchSaveContext, onDismiss: refreshChekiGalleryLayout) { context in
                ChekiSaveSettingsView(
                    previewImage: nil,
                    previewProvider: { settings in
                        ChekiSaveCompositeRenderer.previewImage(
                            from: context.imageDataList,
                            settings: settings,
                            watermarkScale: context.watermarkScale
                        )
                    },
                    watermarkScale: context.watermarkScale,
                    showsBatchLayoutStyle: true
                ) { settings in
                    let selectionCount = context.selectionCount
                    guard let outputImage = ChekiSaveCompositeRenderer.saveImage(
                        from: context.imageDataList,
                        settings: settings,
                        watermarkScale: context.watermarkScale
                    ) else {
                        return
                    }
                    UIImageWriteToSavedPhotosAlbum(outputImage, nil, nil, nil)
                    DownsampledImageCache.shared.removeAll()
                    if selectionCount == 1 {
                        chekiBatchSaveAlertText = settings.isWatermarkEnabled ? "透かし入りで保存しました" : "保存しました"
                    } else {
                        chekiBatchSaveAlertText = settings.isWatermarkEnabled ? "まとめて透かし入りで保存しました" : "まとめて保存しました"
                    }
                    withAnimation {
                        showChekiBatchSaveAlert = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation {
                            showChekiBatchSaveAlert = false
                        }
                    }
                    resetChekiSelection()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .onChange(of: myChekis.map(\.id)) { _, _ in
                handleChekiListChange(myChekis)
            }
            .alert("選択したチェキを削除しますか？", isPresented: $showingBulkDeleteAlert) {
                Button("削除", role: .destructive) {
                    deleteSelectedChekis()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                chekiBulkDeleteMessage
            }
            .alert("まとめて保存は9枚までです", isPresented: $showingChekiSelectionLimitAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("スクショ用のまとめ保存は一度に9枚まで選択できます。")
            }
    }

    private var chekiGalleryBaseView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 15) {
                Picker("表示モード", selection: $displayMode) {
                    Text("推し別").tag(ChekiDisplayMode.byOshi)
                    Image(systemName: "star.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.yellow)
                        .tag(ChekiDisplayMode.favorites)
                    Text("月別").tag(ChekiDisplayMode.byMonth)
                }
                .pickerStyle(.segmented)

                HStack {
                    if !myChekis.isEmpty {
                        Button {
                            withAnimation {
                                activateChekiSelection(.screenshot)
                            }
                        } label: {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(isSelectingChekis && chekiSelectionPurpose == .screenshot ? .pink : .secondary)
                        }
                    }

                    Spacer()

                    HStack(spacing: 15) {
                        if displayMode == .byMonth {
                            Button {
                                withAnimation { isAscending.toggle() }
                            } label: {
                                Image(systemName: "arrow.up.arrow.down.circle")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                            .transition(.opacity)
                        }

                        if !myChekis.isEmpty {
                            Button {
                                withAnimation {
                                    activateChekiSelection(.delete)
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(isSelectingChekis && chekiSelectionPurpose == .delete ? .pink : .secondary)
                            }
                        }
                    }
                }
                .frame(height: 20)
                .padding(.trailing, 5)

                if isSelectingChekis {
                    HStack {
                        Text(selectedChekiCountText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .transition(.opacity)
                }
            }
            .padding([.horizontal, .top])

            if myChekis.isEmpty {
                ScrollView {
                    ContentUnavailableView("チェキがありません", systemImage: "camera.filters")
                }
            } else {
                TabView(selection: $displayMode) {
                    chekiGalleryPage(for: .byOshi)
                        .tag(ChekiDisplayMode.byOshi)
                    chekiGalleryPage(for: .favorites)
                        .tag(ChekiDisplayMode.favorites)
                    chekiGalleryPage(for: .byMonth)
                        .tag(ChekiDisplayMode.byMonth)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            if isSelectingChekis {
                Divider()
                    .padding(.top, 12)

                chekiSelectionActionBar
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .background(Color(.systemBackground))
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { chekiGalleryToolbarContent }
        .overlay(alignment: .bottom) {
            if showChekiBatchSaveAlert {
                Text(chekiBatchSaveAlertText)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(Color.black.opacity(0.7))
                    .clipShape(Capsule())
                    .padding(.bottom, isSelectingChekis ? 108 : 34)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var chekiSelectionActionBar: some View {
        if chekiSelectionPurpose == .delete {
            HStack(spacing: 12) {
                Button(allVisibleChekisSelected ? "選択を解除" : "すべて選択") {
                    withAnimation {
                        if allVisibleChekisSelected {
                            selectedChekiIDs.subtract(displayedChekis.map(\.id))
                            selectedChekiOrder.removeAll { displayedChekis.map(\.id).contains($0) }
                        } else {
                            selectedChekiIDs.formUnion(displayedChekis.map(\.id))
                        }
                    }
                }

                Spacer()

                Button("\(selectedChekiIDs.count)件を削除", role: .destructive) {
                    showingBulkDeleteAlert = true
                }
                .disabled(selectedChekiIDs.isEmpty)
            }
        } else {
            HStack(spacing: 12) {
                Button(allSelectableScreenshotChekisSelected ? "選択を解除" : "すべて選択（最大9枚）") {
                    withAnimation {
                        if allSelectableScreenshotChekisSelected {
                            selectedChekiIDs.subtract(screenshotSelectableIDs)
                            selectedChekiOrder.removeAll { screenshotSelectableIDs.contains($0) }
                        } else {
                            selectedChekiIDs.subtract(screenshotSelectableIDs)
                            selectedChekiOrder.removeAll { screenshotSelectableIDs.contains($0) }
                            selectedChekiIDs.formUnion(screenshotSelectableIDs)
                            selectedChekiOrder.append(contentsOf: screenshotSelectableIDs)
                        }
                    }
                }

                Spacer()

                Button(batchSaveButtonTitle) {
                    prepareBatchChekiSave()
                }
                .disabled(selectedChekiOrder.isEmpty)
            }
        }
    }

    @ViewBuilder
    private func chekiGalleryPage(for mode: ChekiDisplayMode) -> some View {
        ScrollView {
            chekiGalleryContent(for: mode)
                .id("\(chekiGalleryRefreshToken.uuidString)-\(mode.rawValue)")
        }
    }

    @ViewBuilder
    private func chekiGalleryContent(for mode: ChekiDisplayMode) -> some View {
        if mode == .byOshi {
            let groupedByOshi = Dictionary(grouping: myChekis) { $0.oshiID }

            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(myOshis) { oshi in
                    if let chekis = groupedByOshi[oshi.id] {
                        Section(header: sectionHeader(oshi.name, useCustomFont: true)) {
                            chekiGrid(chekis, displayMode: mode)
                        }
                    }
                }

                if let otherChekis = groupedByOshi[AppConfig.otherID] {
                    Section(header: sectionHeader("その他", useCustomFont: true)) {
                        chekiGrid(otherChekis, displayMode: mode)
                    }
                }
            }
        } else if mode == .byMonth {
            let groupedByMonth = Dictionary(grouping: myChekis) { c in
                formatMonth(c.date)
            }

            let sortedMonths = groupedByMonth.keys.sorted { a, b in
                if isAscending {
                    if a == "日付なし" { return true }
                    if b == "日付なし" { return false }
                    return a < b
                } else {
                    if a == "日付なし" { return false }
                    if b == "日付なし" { return true }
                    return a > b
                }
            }

            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(sortedMonths, id: \.self) { month in
                    Section(header: sectionHeader(month, useCustomFont: false)) {
                        chekiGrid(groupedByMonth[month] ?? [], displayMode: mode)
                    }
                }
            }
        } else {
            let favoriteChekis = myChekis.filter(\.isFavorite)

            if favoriteChekis.isEmpty {
                ContentUnavailableView("お気に入りがありません", systemImage: "star")
                    .padding(.top, 60)
            } else {
                let groupedByOshi = Dictionary(grouping: favoriteChekis) { $0.oshiID }

                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(myOshis) { oshi in
                        if let chekis = groupedByOshi[oshi.id] {
                            Section(header: sectionHeader(oshi.name, useCustomFont: true)) {
                                chekiGrid(chekis, displayMode: mode)
                            }
                        }
                    }

                    if let otherChekis = groupedByOshi[AppConfig.otherID] {
                        Section(header: sectionHeader("その他", useCustomFont: true)) {
                            chekiGrid(otherChekis, displayMode: mode)
                        }
                    }
                }
            }
        }
    }

    var body: some View {
        applyChekiGalleryPresentations(to: chekiGalleryBaseView)
    }

    func sectionHeader(_ title: String, useCustomFont: Bool) -> some View {
        Text(title)
            .font(useCustomFont ? AppTypography.bodyFont(for: profile.preferredAppFont, size: 17, weight: .semibold) : .headline)
            .foregroundColor(.secondary)
            .padding(.horizontal)
            .padding(.top, 10)
    }

    @ViewBuilder
    private func chekiGrid(_ chekis: [Cheki], displayMode: ChekiDisplayMode) -> some View {
        // 表示モードに応じたソート
        let sorted = chekis.sorted(by: {
            if displayMode == .byMonth { // 月別の時は設定に従う
                if isAscending {
                    return ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast)
                } else {
                    return ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast)
                }
            } else { // 推し別の時は常に新しい順
                return ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast)
            }
        })
        let oshiNameByID = Dictionary(uniqueKeysWithValues: myOshis.map { ($0.id, $0.name) })
        
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 15)], spacing: 20) {
            ForEach(sorted) { c in
                VStack(spacing: 8) {
                    ZStack(alignment: .topTrailing) {
                    DownsampledDataImage(
                        cacheKey: "cheki-grid-\(c.id.uuidString)-\(chekiThumbnailFingerprint(c))",
                        data: c.thumbnailData,
                        maxPixelSize: 150,
                        contentMode: .fit
                    )
                        .frame(width: 100, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(radius: 3)

                        if isSelectingChekis {
                            Image(systemName: selectedChekiIDs.contains(c.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(selectedChekiIDs.contains(c.id) ? .pink : .white.opacity(0.95))
                                .padding(8)
                        } else {
                            Button {
                                toggleChekiFavorite(id: c.id)
                            } label: {
                                Image(systemName: c.isFavorite ? "star.fill" : "star")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(c.isFavorite ? .yellow : .white)
                                    .padding(6)
                            }
                        }
                    }

                    // 名前の判定ロジック
                    let name: String = {
                        if c.oshiID == AppConfig.otherID {
                            return "" // その他は何も表示しない
                        } else {
                            return oshiNameByID[c.oshiID] ?? ""
                        }
                    }()

                    let footerText: String = {
                        switch displayMode {
                        case .byOshi:
                            return formatShortDate(c.date)
                        case .byMonth:
                            return name
                        case .favorites:
                            return formatShortDate(c.date)
                        }
                    }()

                    Text(footerText)
                        .font(displayMode == .byMonth
                              ? AppTypography.bodyFont(for: profile.preferredAppFont, size: 11, weight: .semibold)
                              : .caption2)
                        .foregroundColor(displayMode == .byMonth ? .primary : .secondary)
                        .lineLimit(1)
                        .frame(height: 14)
                }
                .onTapGesture {
                    if isSelectingChekis {
                        toggleChekiSelection(id: c.id)
                    } else {
                        selectedCheki = c
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    func toggleChekiFavorite(id: UUID) {
        guard let index = myChekis.firstIndex(where: { $0.id == id }) else { return }
        myChekis[index].isFavorite.toggle()
        saveData()
    }

    func formatMonth(_ date: Date?) -> String {
        guard let d = date else { return "日付なし" }
        let f = DateFormatter()
        f.dateFormat = "yyyy年MM月"
        return f.string(from: d)
    }
    
    func formatShortDate(_ date: Date?) -> String {
        guard let d = date else { return "----/--/--" }
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd"
        return f.string(from: d)
    }

    func saveData() {
        LocalStorage.save(myChekis, for: .chekis)
    }

    private func sortedChekisForDisplay(_ chekis: [Cheki]) -> [Cheki] {
        chekis.sorted {
            if displayMode == .byMonth {
                if isAscending {
                    return ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast)
                } else {
                    return ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast)
                }
            } else {
                return ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast)
            }
        }
    }

    func toggleChekiSelection(id: UUID) {
        if selectedChekiIDs.contains(id) {
            selectedChekiIDs.remove(id)
            selectedChekiOrder.removeAll { $0 == id }
        } else {
            if chekiSelectionPurpose == .screenshot && selectedChekiOrder.count >= maxChekiBatchSelectionCount {
                showingChekiSelectionLimitAlert = true
                return
            }
            selectedChekiIDs.insert(id)
            selectedChekiOrder.append(id)
        }
    }

    func handleChekiListChange(_ newValue: [Cheki]) {
        let validIDs = Set(newValue.map { $0.id })
        selectedChekiIDs = selectedChekiIDs.intersection(validIDs)
        selectedChekiOrder = selectedChekiOrder.filter { validIDs.contains($0) }

        if newValue.isEmpty {
            resetChekiSelection()
        }
    }

    func handleTmpChekiImageChange(_ newValue: Data?) {
        guard newValue != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isAssign = true
        }
    }

    func handleSelectedChekiPhotoItemChange(_ newItem: PhotosPickerItem?) {
        Task {
            guard let data = try? await newItem?.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else { return }

            ChekiDateScanner.scan(from: uiImage) { foundDate in
                self.tmpImg = data
                self.tmpDateString = foundDate
                self.tmpScanDebugMessage = nil
                self.selectedItem = nil
            }
        }
    }

    func deleteSelectedChekis() {
        myChekis.removeAll { selectedChekiIDs.contains($0.id) }
        resetChekiSelection()
        saveData()
    }

    private func activateChekiSelection(_ purpose: ChekiSelectionPurpose) {
        if isSelectingChekis && chekiSelectionPurpose == purpose {
            resetChekiSelection()
            return
        }

        chekiSelectionPurpose = purpose
        isSelectingChekis = true
        selectedChekiIDs.removeAll()
        selectedChekiOrder.removeAll()
    }

    private func resetChekiSelection() {
        isSelectingChekis = false
        chekiSelectionPurpose = .delete
        selectedChekiIDs.removeAll()
        selectedChekiOrder.removeAll()
        chekiBatchSaveContext = nil
    }

    private func prepareBatchChekiSave() {
        let selectedImageDataList = selectedChekiOrder.compactMap { id in
            myChekis.first(where: { $0.id == id })?.imageData
        }

        guard !selectedImageDataList.isEmpty else { return }
        chekiBatchSaveContext = ChekiBatchSaveContext(imageDataList: selectedImageDataList)
    }

    private func refreshChekiGalleryLayout() {
        chekiGalleryRefreshToken = UUID()
    }
}

struct ChekiDetailView: View {
    let cheki: Cheki
    @Binding var myOshis: [Oshi]
    @Binding var myChekis: [Cheki]
    @Environment(\.dismiss) var dismiss
    
    @State private var selID: UUID
    @State private var hasDate: Bool // 日付あり・なしの状態
    @State private var selDate: Date // 日付自体の状態
    @State private var showingDeleteAlert = false // ★アラート表示フラグ
    @State private var isShowingChekiFullscreen = false
    @State private var rotationQuarterTurns: Int
    
    init(cheki: Cheki, myOshis: Binding<[Oshi]>, myChekis: Binding<[Cheki]>) {
        self.cheki = cheki
        self._myOshis = myOshis
        self._myChekis = myChekis
        self._selID = State(initialValue: cheki.oshiID)
        // 日付が入っていればON、なければOFFで初期化
        self._hasDate = State(initialValue: cheki.date != nil)
        self._selDate = State(initialValue: cheki.date ?? Date())
        self._rotationQuarterTurns = State(initialValue: 0)
    }

    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                if let baseImage = UIImage(data: cheki.imageData) {
                    let previewCanvasSize = UIScreen.main.bounds.width - 32
                    let baseSize = baseImage.size
                    let longestEdge = max(baseSize.width, baseSize.height)
                    let previewScale = longestEdge > 0 ? previewCanvasSize / longestEdge : 1
                    let previewWidth = baseSize.width * previewScale
                    let previewHeight = baseSize.height * previewScale
                    VStack(spacing: 10) {
                        ZStack {
                            Color.clear

                            Image(uiImage: baseImage)
                                .resizable()
                                .frame(
                                    width: previewWidth,
                                    height: previewHeight
                                )
                                .rotationEffect(.degrees(Double(rotationQuarterTurns * 90)))
                        }
                        .frame(width: previewCanvasSize, height: previewCanvasSize)
                        .clipped()
                        .cornerRadius(15)
                        .shadow(radius: 10)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isShowingChekiFullscreen = true
                        }

                        HStack {
                            Spacer()

                            Button {
                                rotationQuarterTurns = ChekiRotationHelper.normalizedQuarterTurns(rotationQuarterTurns + 1)
                            } label: {
                                Image(systemName: "rotate.right")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 42, height: 42)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .shadow(radius: 6)
                            }
                        }
                        .frame(width: previewCanvasSize)
                    }
                    .padding()
                }
                
                Form {
                    Section("情報を編集") {
                        Picker("推し", selection: $selID) {
                            // 1. 登録済みの推しリスト
                            ForEach(myOshis) { o in
                                Text(o.name).tag(o.id)
                            }
                            
                            // 2. ★ 「その他」を最後に追加
                            Text("その他").tag(AppConfig.otherID)
                        }
                        
                        Toggle("日付を記録する", isOn: $hasDate)
                        if hasDate {
                            DatePicker("撮影日", selection: $selDate, displayedComponents: .date)
                        }
                    }
                    
                    Section {
                        Button(role: .destructive) {
                            showingDeleteAlert = true // ★アラートを呼び出す
                        } label: {
                            Label("チェキを削除", systemImage: "trash")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("チェキ詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let i = myChekis.firstIndex(where: { $0.id == cheki.id }) {
                            var updatedCheki = myChekis[i]
                            if let rotatedData = ChekiRotationHelper.rotatedImageData(
                                from: updatedCheki.imageData,
                                quarterTurns: rotationQuarterTurns
                            ) {
                                updatedCheki.imageData = rotatedData
                                updatedCheki.thumbnailData = ChekiThumbnailHelper.thumbnailData(from: rotatedData)
                            }
                            updatedCheki.oshiID = selID
                            updatedCheki.date = hasDate ? selDate : nil // スイッチに合わせて保存
                            myChekis[i] = updatedCheki
                            saveData()
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .alert("チェキの削除", isPresented: $showingDeleteAlert) {
                    Button("削除する", role: .destructive) {
                        // ここで本当の削除処理を実行
                        myChekis.removeAll { $0.id == cheki.id }
                        saveData()
                        dismiss()
                    }
                    Button("キャンセル", role: .cancel) { }
                } message: {
                    Text("このチェキを削除してもよろしいですか？\nこの操作は取り消せません。")
                }
            .fullScreenCover(isPresented: $isShowingChekiFullscreen) {
                ChekiFullscreenSaveView(
                    imageData: cheki.imageData,
                    rotationQuarterTurns: rotationQuarterTurns,
                    isPresented: $isShowingChekiFullscreen
                )
            }
        }
    }

    func saveData() {
        LocalStorage.save(myChekis, for: .chekis)
    }
}

struct AssignChekiView: View {
    @Binding var myOshis: [Oshi]
    @Binding var myChekis: [Cheki]
    @Binding var imageData: Data?
    @Binding var detectedDateString: String?
    @Binding var scanDebugMessage: String?
    @Environment(\.dismiss) var dismiss
    
    @State private var selID: UUID?
    @State private var hasDate = true
    @State private var chekiDate = Date()
    @State private var datePickerID = UUID()

    var body: some View {
        NavigationStack {
            VStack {
                if let d = imageData, let ui = UIImage(data: d) {
                    Image(uiImage: ui).resizable().scaledToFit().frame(height: 200).cornerRadius(10).padding()
                }
                Form {
                    if let scanDebugMessage {
                        Section("圧縮ログ") {
                            Text(scanDebugMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Section("日付設定") {
                        Toggle("日付を記録する", isOn: $hasDate)
                        if hasDate {
                            DatePicker("撮影日", selection: $chekiDate, displayedComponents: .date)
                                .id(datePickerID)
                            
                            if let detected = detectedDateString {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("スキャン結果: \(detected)")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    
                                    // 親切な注釈を追加
                                    Text("※スキャンが正しくない場合は、上のカレンダーから修正してください")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    Section("誰のチェキ？") {
                        // 1. 登録済みの推しリスト
                        ForEach(myOshis) { o in
                            HStack {
                                // グループ名があれば併記すると分かりやすい
                                Text(o.group.isEmpty ? o.name : "\(o.group) / \(o.name)")
                                    .foregroundColor(selID == o.id ? .primary : .secondary)
                                Spacer()
                                if selID == o.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(o.color)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { selID = o.id }
                        }
                        
                        // 2. ★「その他」の選択肢を最後に追加
                        HStack {
                            Text("その他（特定の推し以外）")
                                .foregroundColor(selID == AppConfig.otherID ? .primary : .secondary)
                            Spacer()
                            if selID == AppConfig.otherID {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.gray)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selID = AppConfig.otherID } // 固定のotherIDをセット
                    }
                }
            }
            .navigationTitle("保存設定")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let id = selID, let d = imageData {
                            myChekis.append(Cheki(oshiID: id, imageData: d, date: hasDate ? chekiDate : nil))
                            saveData()
                            imageData = nil; detectedDateString = nil; scanDebugMessage = nil; dismiss()
                        }
                    }.disabled(selID == nil)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { imageData = nil; detectedDateString = nil; scanDebugMessage = nil; dismiss() }
                }
            }
            .onChange(of: detectedDateString) { _, newValue in
                if let ds = newValue, let parsed = parseDate(ds) {
                    DispatchQueue.main.async {
                        self.chekiDate = parsed
                        self.hasDate = true
                        self.datePickerID = UUID()
                    }
                }
            }
            .onAppear {
                if let ds = detectedDateString, let parsed = parseDate(ds) {
                    self.chekiDate = parsed
                    self.hasDate = true
                    self.datePickerID = UUID()
                }
            }
        }
    }

    func parseDate(_ str: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        let cleaned = str.replacingOccurrences(of: "[,/-]", with: ".", options: .regularExpression)
                         .trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. 年ありパターン
        let fullFormats = ["yyyy.M.d", "yy.M.d", "yyyy.MM.dd", "yy.MM.dd"]
        for fmt in fullFormats {
            f.dateFormat = fmt
            if let date = f.date(from: cleaned) { return date }
        }
        
        // 2. 年なしパターン（今年の年を補完）
        let shortFormats = ["M.d", "MM.dd"]
        for fmt in shortFormats {
            f.dateFormat = fmt
            if let date = f.date(from: cleaned) {
                let currentYear = Calendar.current.component(.year, from: Date())
                var comps = Calendar.current.dateComponents([.month, .day], from: date)
                comps.year = currentYear
                return Calendar.current.date(from: comps)
            }
        }
        return nil
    }

    func saveData() {
        LocalStorage.save(myChekis, for: .chekis)
    }
}

// MARK: - 6. 一覧・追加

@MainActor
struct OshiListView: View {
    @Binding var myOshis: [Oshi]
    @Binding var myChekis: [Cheki]
    @Binding var myLives: [LiveRecord]
    @Binding var profile: UserProfile
    @ObservedObject var loader: OshiLoader
    @State private var target: Oshi? = nil
    @Environment(\.editMode) var editMode
    
    @State private var showingDeleteAlert = false
    @State private var indexToDelete: Int? = nil
    @State private var graduatedOshis: [GraduatedOshi] = []
    @State private var isFarewellProcess = false
    @State private var selectedOshiForEffect: Oshi? = nil
    @State private var showingGraduatedDeleteAlert = false
    @State private var graduatedIndexSetToDelete: IndexSet?
    @State private var isEditingGraduatedMemories = false
    @State private var selectedGraduatedIDs: Set<UUID> = []
    @State private var showingBulkGraduatedDeleteAlert = false
    @State private var showingAdditionalOshiAlert = false

    var body: some View {
        ZStack {
            NavigationStack {
                List {
                    // --- 1. 現在の推しセクション（編集・並び替え・削除が可能） ---
                    Section {
                        ForEach(myOshis) { o in
                            OshiRow(
                                oshi: o,
                                preferredFont: profile.preferredAppFont,
                                isEditing: editMode?.wrappedValue.isEditing ?? false
                            ) {
                                target = o
                            }
                        }
                        .onDelete { indexSet in
                            indexToDelete = indexSet.first
                            showingDeleteAlert = true
                        }
                        .onMove { from, to in
                            myOshis.move(fromOffsets: from, toOffset: to)
                            save()
                        }
                    }

                    // --- 2. 追加ボタンセクション（Sectionを分けて、標準的な「意味のある隙間」を確保） ---
                    if !isFarewellProcess {
                        Section {
                            HStack(spacing: 15) {
                                // 他の行と100%同じ45pxの丸型
                                ZStack {
                                    Circle()
                                        .fill(Color.secondary.opacity(0.1))
                                        .frame(width: 45, height: 45)
                                    
                                    Image(systemName: "person.badge.plus")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary.opacity(0.5))
                                        .offset(x: 1)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("推しを追加")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    
                                    Text("新しい推しとの思い出を刻もう！")
                                        .font(.caption)
                                        .foregroundColor(.secondary.opacity(0.6))
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.footnote.bold())
                                    .foregroundColor(Color(.systemGray4))
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if myOshis.count == 1 {
                                    showingAdditionalOshiAlert = true
                                } else {
                                    target = Oshi(name: "", group: "", startDate: Date(), colorHex: "FFC0CB", imageURL: "")
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                            .listRowBackground(Color(.secondarySystemGroupedBackground))
                        }
                    }

                    // --- 3. 思い出セクション ---
                    if !graduatedOshis.isEmpty {
                        Section(
                            header: HStack {
                                Text("思い出")
                                Spacer()
                                Button(isEditingGraduatedMemories ? "完了" : "編集") {
                                    isEditingGraduatedMemories.toggle()
                                    if !isEditingGraduatedMemories {
                                        selectedGraduatedIDs.removeAll()
                                    }
                                }
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                                .buttonStyle(.plain)
                            }
                        ) {
                            ForEach(graduatedOshis) { history in
                                HStack(spacing: 12) {
                                    if isEditingMemories {
                                        Button {
                                            toggleGraduatedSelection(history.id)
                                        } label: {
                                            Image(systemName: selectedGraduatedIDs.contains(history.id) ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 20))
                                                .foregroundColor(selectedGraduatedIDs.contains(history.id) ? .accentColor : .secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    GraduatedRow(history: history)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if isEditingMemories {
                                        toggleGraduatedSelection(history.id)
                                    }
                                }
                            }
                            .onDelete { indexSet in
                                graduatedIndexSetToDelete = indexSet
                                showingGraduatedDeleteAlert = true
                            }
                        }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        if !isFarewellProcess {
                            Text("推し一覧")
                                .font(AppTypography.navigationTitleFont(for: profile.preferredAppFont, size: 18))
                                .tracking(-0.5)
                        }
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        if !isFarewellProcess {
                            EditButton().font(.system(size: 16, design: .rounded))
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if !isFarewellProcess {
                            EmptyView()
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if isEditingMemories {
                        HStack(spacing: 12) {
                            Button(allGraduatedSelected ? "選択を解除" : "すべて選択") {
                                if allGraduatedSelected {
                                    selectedGraduatedIDs.removeAll()
                                } else {
                                    selectedGraduatedIDs = Set(graduatedOshis.map(\.id))
                                }
                            }
                            .font(.subheadline.bold())
                            .foregroundColor(.secondary)

                            Spacer()

                            Button {
                                showingBulkGraduatedDeleteAlert = true
                            } label: {
                                Text("\(selectedGraduatedIDs.count)件を削除")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(
                                        Capsule()
                                            .fill(Color.red)
                                    )
                            }
                            .disabled(selectedGraduatedIDs.isEmpty)
                            .opacity(selectedGraduatedIDs.isEmpty ? 0.45 : 1)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 10)
                        .background(.ultraThinMaterial)
                    }
                }
            }
            
            if isFarewellProcess, let o = selectedOshiForEffect {
                FarewellView(oshi: o, chekis: myChekis.filter { $0.oshiID == o.id }) {
                    finalizeFarewell(o)
                    isFarewellProcess = false
                }
                .zIndex(100)
            }
        }
        .onAppear { loadGraduatedData() }
        .toolbar(isFarewellProcess ? .hidden : .visible, for: .tabBar)
        .sheet(item: $target) { o in
            AddEditOshiView(myOshis: $myOshis, editingOshi: o.name.isEmpty ? nil : o, loader: loader)
        }
        .alert("DDは推しが悲しみませんか？", isPresented: $showingAdditionalOshiAlert) {
            Button("やっぱりやめる", role: .cancel) { }
            Button("OK") {
                target = Oshi(name: "", group: "", startDate: Date(), colorHex: "FFC0CB", imageURL: "")
            }
        }
        .alert("担降りしますか？", isPresented: $showingDeleteAlert) {
            Button("キャンセル", role: .cancel) { }
            Button("担降りする", role: .destructive) {
                if let idx = indexToDelete {
                    selectedOshiForEffect = myOshis[idx]
                    isFarewellProcess = true
                }
            }
        } message: {
            Text("推しの名前や推し日数は『思い出』として残ります。\n\n※本アプリでスキャンしたチェキは削除されますが、『写真』から追加した元画像は削除されません。")
        }
        .alert("思い出を完全に消しますか？", isPresented: $showingGraduatedDeleteAlert) {
            Button("キャンセル", role: .cancel) { graduatedIndexSetToDelete = nil }
            Button("消す", role: .destructive) {
                if let indexSet = graduatedIndexSetToDelete {
                    let deletedIDs = indexSet.compactMap {
                        graduatedOshis.indices.contains($0) ? graduatedOshis[$0].id : nil
                    }
                    graduatedOshis.remove(atOffsets: indexSet)
                    selectedGraduatedIDs.subtract(deletedIDs)
                    if graduatedOshis.isEmpty {
                        isEditingGraduatedMemories = false
                    }
                    save()
                }
            }
        } message: {
            Text("この操作は取り消せません。大切に刻んだ思い出が完全に失われます。")
        }
        .alert("選択した思い出を完全に消しますか？", isPresented: $showingBulkGraduatedDeleteAlert) {
            Button("キャンセル", role: .cancel) { }
            Button("消す", role: .destructive) {
                deleteSelectedGraduatedOshis()
            }
        } message: {
            Text("選択した思い出が完全に失われます。この操作は取り消せません。")
        }
    }

    // --- 保存・読み込みロジック ---
    private var isEditingMemories: Bool {
        isEditingGraduatedMemories && !graduatedOshis.isEmpty
    }

    private var allGraduatedSelected: Bool {
        !graduatedOshis.isEmpty && selectedGraduatedIDs.count == graduatedOshis.count
    }

    func save() {
        LocalStorage.save(myOshis, for: .oshis)
        LocalStorage.save(graduatedOshis, for: .graduatedOshis)
    }
    
    func loadGraduatedData() {
        if let data = LocalStorage.load([GraduatedOshi].self, for: .graduatedOshis) {
            self.graduatedOshis = data
        }
    }

    func deleteSelectedGraduatedOshis() {
        graduatedOshis.removeAll { selectedGraduatedIDs.contains($0.id) }
        selectedGraduatedIDs.removeAll()
        if graduatedOshis.isEmpty {
            isEditingGraduatedMemories = false
        }
        save()
    }

    func toggleGraduatedSelection(_ id: UUID) {
        if selectedGraduatedIDs.contains(id) {
            selectedGraduatedIDs.remove(id)
        } else {
            selectedGraduatedIDs.insert(id)
        }
    }

    func finalizeFarewell(_ target: Oshi) {
        let history = GraduatedOshi(id: target.id, name: target.name, group: target.group, daysCount: target.daysCount, graduationDate: Date(), colorHex: target.colorHex)
        graduatedOshis.append(history)
        myOshis.removeAll { $0.id == target.id }
        myChekis.removeAll { $0.oshiID == target.id }
        save()
    }
}

// 現役推しの行
struct OshiRow: View {
    let oshi: Oshi
    let preferredFont: AppDisplayFontChoice
    let isEditing: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 15) {
            OshiImage(oshi: oshi, size: 45).clipShape(Circle())
            VStack(alignment: .leading) {
                HStack {
                    Text(oshi.name)
                        .font(AppTypography.bodyFont(for: preferredFont, size: 17, weight: .bold))
                    if !oshi.isDisplayed { Image(systemName: "eye.slash").font(.caption).opacity(0.6) }
                }
                Text(oshi.group)
                    .font(AppTypography.bodyFont(for: preferredFont, size: 12, weight: .regular))
                    .opacity(0.8)
            }
            .foregroundColor(ColorUtils.isLightColor(oshi.color) ? .black : .white)
            Spacer()
            Text("\(oshi.daysCount)日")
        }
        .listRowBackground(oshi.color)
        .opacity(oshi.isDisplayed ? 1.0 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture { if !isEditing { onTap() } }
    }
}

// 殿堂入りの行
struct GraduatedRow: View {
    let history: GraduatedOshi
    var body: some View {
        HStack {
            Circle().fill(Color(hex: history.colorHex)).frame(width: 8, height: 8)
            VStack(alignment: .leading) {
                Text(history.name).font(.subheadline).bold()
                Text("\(history.graduationDate, style: .date) 担降り").font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Text("\(history.daysCount)日").font(.caption).bold().foregroundColor(.secondary)
        }
    }
}

@MainActor
struct AddEditOshiView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var myOshis: [Oshi]
    let editingOshi: Oshi?
    @ObservedObject var loader: OshiLoader

    // 事務所・グループ・メンバー選択用の追加
    @State private var selectedAgency: GitHubAgencyInfo? = nil
    
    @State private var name = ""
    @State private var group = ""
    @State private var start = Date()
    @State private var col = Color.pink
    @State private var textCol = Color.white
    @State private var isTextColorManual = false
    @State private var imgU = ""
    @State private var locD: Data? = nil
    @State private var originalD: Data? = nil
    @State private var backgroundD: Data? = nil
    @State private var bDayInput = ""
    @State private var selectedImageFileName: String? = nil
    @State private var imagePlacement: OshiImagePlacement = .default
    
    @State private var sDate = Date()
    @State private var hasS = false // 生誕祭
    @State private var dDate = Date()
    @State private var hasD = false // デビュー記念日
    
    @State private var isDisp = true
    @State private var tw = ""
    @State private var ins = ""
    @State private var tik = ""
    @State private var selI: PhotosPickerItem? = nil
    @State private var selectedBackgroundItem: PhotosPickerItem? = nil
    @State private var selG = ""
    
    @State private var isEffectEnabled = true
    @State private var isLoadingProfileImage = false
    @State private var isLoadingBackgroundImage = false
    @State private var profileImageLoadFailed = false
    @State private var showingDuplicateAlert = false
    @State private var showingSimilarAlert = false
    @State private var showingImageCandidatePicker = false
    @State private var showingImagePlacementEditor = false
    @State private var imageCandidatePickerOptions: [OshiImageCandidateOption] = []
    @State private var imageCandidateDisplayLimit = AppConfig.imageCandidateSelectionLimit
    @State private var isPreparingImageCandidatePicker = false
    @State private var pendingOshiToSave: Oshi? = nil
    @State private var selectedKind: OshiKind = .person
    @State private var draftAgencyId: String? = nil
    @State private var draftGroupId: String? = nil
    @State private var draftMasterId: String? = nil
  
    private var sortedAgencies: [GitHubAgencyInfo] {
        loader.agencies.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var activeGroups: [String] {
        if selectedAgency == nil {
            return []
        }
        return Array(Set(loader.displayGroupOshis.map { $0.group }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var visibleImageCandidatePickerOptions: [OshiImageCandidateOption] {
        Array(imageCandidatePickerOptions.prefix(imageCandidateDisplayLimit))
    }

    private var canShowMoreImageCandidates: Bool {
        imageCandidateDisplayLimit < imageCandidatePickerOptions.count
    }

    private var safeSelectedGroup: Binding<String> {
        Binding(
            get: {
                if let draftGroupId,
                   let matchedGroup = findGroup(byGroupId: draftGroupId) {
                    return matchedGroup.group
                }
                return activeGroups.contains(selG) ? selG : ""
            },
            set: { selG = $0 }
        )
    }

    private var safeSelectedName: Binding<String> {
        Binding(
            get: { selectableIdols.contains(where: { $0.name == name }) ? name : "" },
            set: { name = $0 }
        )
    }

    private func normalizedCandidateText(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        if trimmed.range(of: #"^\d+$"#, options: .regularExpression) != nil {
            return nil
        }
        return trimmed
    }

    private func formattedCandidateYearMonth(_ value: String?) -> String? {
        guard let value = normalizedCandidateText(value) else {
            return nil
        }

        let parts = value.split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              (1...12).contains(month) else {
            return value
        }

        let symbols = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(symbols[month - 1]) \(year)"
    }

    private func imageCandidatePrimaryLabel(_ candidate: OshiImageCandidateOption) -> String {
        normalizedCandidateText(candidate.eventLabel)
        ?? normalizedCandidateText(candidate.caption)
        ?? formattedCandidateYearMonth(candidate.yearMonth)
        ?? candidate.fileName
    }

    private func imageCandidateSecondaryLabel(_ candidate: OshiImageCandidateOption) -> String? {
        guard let yearMonth = formattedCandidateYearMonth(candidate.yearMonth),
              yearMonth != imageCandidatePrimaryLabel(candidate) else {
            return nil
        }
        return yearMonth
    }

    private var selectableIdols: [Oshi] {
        loader.displayOshis.filter { i in
            guard i.group == selG else { return false }

            if let editingOshi,
               (editingOshi.masterId != nil && editingOshi.masterId == i.masterId ||
                editingOshi.name == i.name && editingOshi.group == i.group) {
                return true
            }

            return !myOshis.contains {
                if let existingMasterId = $0.masterId, let candidateMasterId = i.masterId {
                    return existingMasterId == candidateMasterId
                }
                return $0.name == i.name && $0.group == i.group
            }
        }
    }

    private var currentImageCandidates: [OshiImageCandidateOption] {
        loader.imageCandidates(for: draftAgencyId, masterId: draftMasterId)
    }

    private var canChooseCandidateImage: Bool {
        selectedKind == .person && draftAgencyId != nil && draftMasterId != nil
    }

    private var defaultTextColorSelection: Color {
        ColorUtils.recommendedTextColor(backgroundImageData: backgroundD, fallbackColor: col)
    }

    @ViewBuilder
    private var groupSelectionPicker: some View {
        Picker("グループ", selection: safeSelectedGroup) {
            Text("選択").tag("")
            ForEach(activeGroups, id: \.self) { groupName in
                Text(groupName).tag(groupName)
            }
        }
        .disabled(selectedAgency == nil || loader.isLoading)
    }

    @ViewBuilder
    private var agencySelectionPicker: some View {
        Picker("ユニット", selection: $selectedAgency) {
            Text("選択").tag(nil as GitHubAgencyInfo?)
            ForEach(sortedAgencies) { agency in
                Text(agency.name).tag(agency as GitHubAgencyInfo?)
            }
        }
        .onChange(of: selectedAgency) { _, newValue in
            handleSelectedAgencyChange(newValue)
        }
    }

    @ViewBuilder
    private var memberSelectionPicker: some View {
        Picker("メンバー", selection: safeSelectedName) {
            Text("選択").tag("")
            ForEach(selectableIdols) { idol in
                Text(idol.name).tag(idol.name)
            }
        }
        .disabled(selG.isEmpty || loader.isLoading)
        .onChange(of: name) { _, newValue in
            handleSelectedMemberChange(newValue)
        }
    }

    private var currentProfileUIImage: UIImage? {
        guard let locD else { return nil }
        return UIImage(data: locD)
    }

    @ViewBuilder
    private var displaySettingsSection: some View {
        Section("表示設定") {
            Toggle("推しに表示する", isOn: $isDisp)
            Toggle("推しの背景をエフェクトする", isOn: $isEffectEnabled)
        }
    }

    @ViewBuilder
    private var registrationTypeSection: some View {
        if editingOshi == nil {
            Section("登録タイプ") {
                Picker("種類", selection: $selectedKind) {
                    ForEach(OshiKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedKind) { _, _ in
                    selG = ""
                    resetImportedOshiFields()
                }
            }
        }
    }

    @ViewBuilder
    private var selectionSection: some View {
        Section(editingOshi == nil ? "一覧から推しを選ぶ" : "推しのグループを変更") {
            if loader.agencies.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("ユニット一覧を準備中...")
                        .foregroundColor(.secondary)
                }
            } else {
                agencySelectionPicker
            }

            groupSelectionPicker
                .onChange(of: selG) { _, newGroup in
                    handleSelectedGroupChange(newGroup)
                }

            if selectedKind == .person && (editingOshi == nil || editingOshi?.masterId == nil) {
                memberSelectionPicker
            }
        }
    }

    @ViewBuilder
    private var profileImagePreview: some View {
        if let d = locD, let ui = UIImage(data: d) {
            OshiFilledUIImageView(image: ui, size: 92, placement: imagePlacement)
                .clipShape(Circle())
        } else if isLoadingProfileImage {
            ZStack {
                Circle()
                    .fill(Color(.systemGray6))
                ProgressView()
            }
            .frame(width: 92, height: 92)
        } else if profileImageLoadFailed {
            Image(systemName: "person.circle.fill")
                .resizable()
                .scaledToFill()
                .frame(width: 92, height: 92)
                .foregroundColor(.gray)
                .clipShape(Circle())
        } else if imgU.isEmpty {
            ZStack {
                Circle()
                    .fill(Color(.systemGray6))
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.gray)
                    .padding(8)
            }
            .frame(width: 92, height: 92)
        } else {
            CachedOshiImage(url: imgU, size: 92, placement: imagePlacement)
                .clipShape(Circle())
        }
    }

    @ViewBuilder
    private var oshiInfoSection: some View {
        Section("推しの情報") {
            HStack(spacing: 24) {
                profileImagePreview
                VStack(alignment: .leading, spacing: 10) {
                    PhotosPicker(selection: $selI, matching: .images) {
                        Text("写真を選択").font(.subheadline).bold()
                    }
                    if canChooseCandidateImage {
                        Button {
                            Task {
                                await openImageCandidatePicker()
                            }
                        } label: {
                            Text("候補から選択").font(.subheadline).bold()
                        }
                        .buttonStyle(.borderless)
                        .disabled(isPreparingImageCandidatePicker || loader.isLoadingImageCandidates(for: draftAgencyId))

                        if isPreparingImageCandidatePicker || loader.isLoadingImageCandidates(for: draftAgencyId) {
                            Text("候補画像を読み込み中...")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else if currentImageCandidates.isEmpty {
                            Text("選べる候補画像はまだありません")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    if currentProfileUIImage != nil {
                        Button {
                            showingImagePlacementEditor = true
                        } label: {
                            Text("写真の位置を調整").font(.caption2).bold()
                        }
                        .buttonStyle(.borderless)
                    }
                    if isLoadingProfileImage {
                        Text("プロフィール画像を読み込み中...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else if profileImageLoadFailed {
                        Text("画像が見つからないため、あとから追加できます")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if locD != originalD {
                        Button(role: .destructive) {
                            Task {
                                await MainActor.run {
                                    selI = nil
                                    locD = originalD
                                    profileImageLoadFailed = originalD == nil
                                }
                                await loadProfileImage(from: imgU)
                            }
                        } label: {
                            Text("戻す").font(.caption2).bold()
                        }
                        .buttonStyle(.borderless)
                    }
                    if isUsingNonDefaultProfileImage {
                        Button(role: .destructive) {
                            restoreDefaultImageCandidate()
                        } label: {
                            Text("デフォルト画像に戻す").font(.caption2).bold()
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .padding(.vertical, 4)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .onChange(of: selI) { _, ni in
                guard let ni else { return }
                Task {
                    if let d = try? await ni.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            locD = d
                            imagePlacement = .default
                            profileImageLoadFailed = false
                            isLoadingProfileImage = false
                            showingImagePlacementEditor = true
                        }
                    }
                }
            }

            TextField("名前", text: $name)
                .disabled(shouldLockNameInput)
            TextField("グループ", text: $group)
                .disabled(shouldLockGroupInput)
                .foregroundStyle(shouldLockGroupInput ? Color.secondary : Color.primary)
            ColorPicker("メンカラ", selection: $col)
            DatePicker("推し始めた日", selection: $start, displayedComponents: .date)

            HStack {
                Text("誕生日")
                Spacer()
                TextField("月/日", text: $bDayInput)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numbersAndPunctuation)
                    .onChange(of: bDayInput) { _, nv in
                        let filtered = nv.filter { "0123456789/".contains($0) }
                        if filtered.count <= 5 { bDayInput = filtered }
                    }
            }
        }
    }

    @ViewBuilder
    private var anniversarySection: some View {
        Section("記念日設定") {
            Toggle("生誕祭あり", isOn: $hasS)
            if hasS {
                DatePicker("生誕祭の日付", selection: $sDate, displayedComponents: .date)
            }

            Toggle("デビュー記念日あり", isOn: $hasD)
            if hasD {
                DatePicker("デビューの日付", selection: $dDate, displayedComponents: .date)
            }
        }
    }

    @ViewBuilder
    private var backgroundImageSection: some View {
        Section("背景と文字色") {
            HStack(spacing: 20) {
                Group {
                    if let d = backgroundD, let ui = UIImage(data: d) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray6))
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                            )
                    }
                }
                .frame(width: 80, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $selectedBackgroundItem, matching: .images) {
                        Text("背景画像を選択").font(.subheadline).bold()
                    }
                    if isLoadingBackgroundImage {
                        Text("背景画像を読み込み中...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if backgroundD != nil {
                        Button(role: .destructive) {
                            selectedBackgroundItem = nil
                            backgroundD = nil
                            isLoadingBackgroundImage = false
                        } label: {
                            Text("削除").font(.caption2).bold()
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }

            VStack(alignment: .leading, spacing: 12) {
                Picker("文字色", selection: $isTextColorManual) {
                    Text("自動").tag(false)
                    Text("手動").tag(true)
                }
                .pickerStyle(.segmented)

                if isTextColorManual {
                    HStack {
                        ColorPicker("文字色", selection: $textCol)
                    }
                } else {
                    HStack {
                        Text("文字色")
                        Spacer()
                        Circle()
                            .fill(defaultTextColorSelection)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                            )
                        Text(backgroundD != nil ? "背景画像から自動" : "自動")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onChange(of: selectedBackgroundItem) { _, newItem in
                guard let newItem else { return }
                isLoadingBackgroundImage = true
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let resizedData = ImageResizer.resizedJPEGData(from: data),
                       UIImage(data: resizedData) != nil {
                        await MainActor.run {
                            backgroundD = resizedData
                            isLoadingBackgroundImage = false
                        }
                    } else {
                        await MainActor.run {
                            isLoadingBackgroundImage = false
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var snsSection: some View {
        Section("SNS") {
            HStack { Image(systemName: "bird.fill"); Text("X ID"); Spacer(); TextField("ID", text: $tw).multilineTextAlignment(.trailing).autocapitalization(.none) }
            HStack { Image(systemName: "camera.fill"); Text("Insta ID"); Spacer(); TextField("ID", text: $ins).multilineTextAlignment(.trailing).autocapitalization(.none) }
            HStack { Image(systemName: "music.note"); Text("TikTok ID"); Spacer(); TextField("ID", text: $tik).multilineTextAlignment(.trailing).autocapitalization(.none) }
        }
    }
    
    private func findIdol(named name: String, in groupName: String) -> Oshi? {
        loader.displayOshis.first { item in
            item.name == name && item.group == groupName
        }
    }

    private func findGroup(named groupName: String) -> Oshi? {
        loader.displayGroupOshis.first { item in
            item.group == groupName
        }
    }

    private func findGroup(byGroupId groupId: String?) -> Oshi? {
        guard let groupId, !groupId.isEmpty else { return nil }
        return loader.displayGroupOshis.first { item in
            item.groupId == groupId
        }
    }

    private func syncGroupNameFromDraftGroupId() {
        guard let matchedGroup = findGroup(byGroupId: draftGroupId) else { return }
        group = matchedGroup.group
        selG = matchedGroup.group
    }

    private var isUsingMasterGroupSelection: Bool {
        draftGroupId != nil
    }

    private var isUsingMasterMemberSelection: Bool {
        draftMasterId != nil
    }

    private var shouldLockNameInput: Bool {
        if selectedKind == .group { return true }
        if editingOshi == nil { return isUsingMasterMemberSelection }
        if editingOshi?.masterId == nil { return isUsingMasterMemberSelection }
        return false
    }

    private var shouldLockGroupInput: Bool {
        isUsingMasterGroupSelection
    }

    private func resetImportedOshiFields() {
        name = ""
        group = ""
        col = .pink
        textCol = ColorUtils.isLightColor(.pink) ? .black : .white
        isTextColorManual = false
        imgU = ""
        selectedImageFileName = nil
        imagePlacement = .default
        locD = nil
        originalD = nil
        bDayInput = ""
        tw = ""
        ins = ""
        tik = ""
        profileImageLoadFailed = false
        isLoadingProfileImage = false
        draftAgencyId = nil
        draftGroupId = nil
        draftMasterId = nil
    }

    private func applyImportedGroup(_ importedGroup: Oshi) {
        name = importedGroup.name
        group = importedGroup.group
        col = importedGroup.color
        textCol = importedGroup.textColor
        isTextColorManual = importedGroup.textColorHex?.isEmpty == false
        imgU = importedGroup.imageURL
        selectedImageFileName = nil
        imagePlacement = .default
        bDayInput = convertToDisplay(importedGroup.birthday)
        tw = importedGroup.twitterID ?? ""
        ins = importedGroup.instagramID ?? ""
        tik = importedGroup.tiktokID ?? ""
        draftAgencyId = importedGroup.agencyId
        draftGroupId = importedGroup.groupId
        draftMasterId = importedGroup.masterId
        Task { await loadProfileImage(from: importedGroup.imageURL) }
    }

    private func applyImportedMember(_ importedMember: Oshi) {
        name = importedMember.name
        group = importedMember.group
        col = importedMember.color
        textCol = importedMember.textColor
        isTextColorManual = importedMember.textColorHex?.isEmpty == false
        imgU = importedMember.imageURL
        selectedImageFileName = nil
        imagePlacement = .default
        bDayInput = convertToDisplay(importedMember.birthday)
        tw = importedMember.twitterID ?? ""
        ins = importedMember.instagramID ?? ""
        tik = importedMember.tiktokID ?? ""
        draftAgencyId = importedMember.agencyId
        draftGroupId = importedMember.groupId
        draftMasterId = importedMember.masterId
        Task {
            await loadProfileImage(from: importedMember.imageURL)
            if let agencyId = importedMember.agencyId, importedMember.masterId != nil {
                await loader.fetchImageCandidates(agencyId: agencyId)
            }
        }
    }

    private func returnToManualGroupInput() {
        selectedAgency = nil
        selG = ""
        draftAgencyId = editingOshi?.agencyId
        draftGroupId = nil
    }

    private func handleSelectedAgencyChange(_ newValue: GitHubAgencyInfo?) {
        selG = ""

        if editingOshi == nil {
            resetImportedOshiFields()
        } else {
            draftGroupId = nil
            if editingOshi?.masterId == nil {
                draftMasterId = nil
            }
        }

        if let url = newValue?.detailURL {
            Task {
                await loader.fetchAgencyDetail(url: url)
            }
        } else if editingOshi == nil {
            loader.displayOshis = []
            loader.displayGroupOshis = []
        }
    }

    private func handleSelectedMemberChange(_ newValue: String) {
        if let importedMember = findIdol(named: newValue, in: selG) {
            applyImportedMember(importedMember)
        } else if editingOshi == nil || editingOshi?.masterId == nil {
            draftMasterId = nil
            if editingOshi == nil {
                imgU = ""
                locD = nil
                originalD = nil
                profileImageLoadFailed = false
                isLoadingProfileImage = false
            }
        }
    }

    private func handleSelectedGroupChange(_ newGroup: String) {
        group = newGroup

        if let importedGroup = findGroup(named: newGroup) {
            draftAgencyId = importedGroup.agencyId
            draftGroupId = importedGroup.groupId
            if selectedKind == .group {
                applyImportedGroup(importedGroup)
            } else if editingOshi == nil {
                name = ""
                imgU = ""
                locD = nil
                originalD = nil
                bDayInput = ""
                tw = ""
                ins = ""
                tik = ""
                profileImageLoadFailed = false
                isLoadingProfileImage = false
            }
        } else if editingOshi == nil {
            name = ""
            imgU = ""
            locD = nil
            originalD = nil
            bDayInput = ""
            tw = ""
            ins = ""
            tik = ""
            profileImageLoadFailed = false
            isLoadingProfileImage = false
        }
    }

    private var isSaveDisabled: Bool {
        (selectedKind == .person ? name.isEmpty : group.isEmpty) || group.isEmpty || isLoadingProfileImage || isLoadingBackgroundImage
    }

    @MainActor
    private func saveCurrentOshi(finalLocal: Data?, finalOriginal: Data?) {
        let finalBDay = convertToInternal(bDayInput)
        let selectedIdol = selectedKind == .person ? findIdol(named: name, in: group) : nil
        let resolvedGroupRecord = findGroup(byGroupId: draftGroupId) ?? findGroup(named: group)

        let selectedGroup: Oshi?
        if selectedKind == .group {
            selectedGroup = resolvedGroupRecord
        } else {
            selectedGroup = nil
        }

        let resolvedMasterId: String?
        if let masterId = selectedIdol?.masterId {
            resolvedMasterId = masterId
        } else if let masterId = selectedGroup?.masterId {
            resolvedMasterId = masterId
        } else {
            resolvedMasterId = draftMasterId
        }

        let resolvedName: String
        if selectedKind == .group {
            resolvedName = selectedGroup?.name ?? group
        } else {
            resolvedName = name
        }

        let resolvedGroup = resolvedGroupRecord?.group ?? group

        let resolvedKind: OshiKind
        if selectedGroup != nil {
            resolvedKind = .group
        } else if selectedIdol != nil {
            resolvedKind = .person
        } else {
            resolvedKind = selectedKind
        }

        let resolvedAgencyId: String?
        if let agencyId = selectedIdol?.agencyId {
            resolvedAgencyId = agencyId
        } else if let agencyId = selectedGroup?.agencyId {
            resolvedAgencyId = agencyId
        } else if let agencyId = resolvedGroupRecord?.agencyId {
            resolvedAgencyId = agencyId
        } else {
            resolvedAgencyId = draftAgencyId
        }

        let resolvedGroupId: String?
        if let groupId = selectedIdol?.groupId {
            resolvedGroupId = groupId
        } else if let groupId = selectedGroup?.groupId {
            resolvedGroupId = groupId
        } else if let groupId = resolvedGroupRecord?.groupId {
            resolvedGroupId = groupId
        } else {
            resolvedGroupId = draftGroupId
        }

        let resolvedColorHex = ColorUtils.toHex(col)
        let resolvedTextColorHex = ColorUtils.toHex(textCol)
        let resolvedTimeTreeURL = selectedGroup?.timeTreeURL
            ?? resolvedGroupRecord?.timeTreeURL
            ?? editingOshi?.timeTreeURL

        let resolvedDefaultImageURL: String
        if resolvedKind == .group {
            if let imageURL = selectedGroup?.imageURL {
                resolvedDefaultImageURL = imageURL
            } else if let imageURL = resolvedGroupRecord?.imageURL {
                resolvedDefaultImageURL = imageURL
            } else if let imageURL = editingOshi?.imageURL {
                resolvedDefaultImageURL = imageURL
            } else {
                resolvedDefaultImageURL = imgU
            }
        } else if let imageURL = selectedIdol?.imageURL {
            resolvedDefaultImageURL = imageURL
        } else if let imageURL = editingOshi?.imageURL {
            resolvedDefaultImageURL = imageURL
        } else {
            resolvedDefaultImageURL = imgU
        }

        if hasDuplicateOshi(name: resolvedName, group: resolvedGroup, masterId: resolvedMasterId) {
            showingDuplicateAlert = true
            return
        }

        let resolvedIconThumbnailData = OshiIconThumbnailHelper.thumbnailData(
            from: finalLocal,
            placement: imagePlacement
        )

        let savedOshi = Oshi(
            id: editingOshi?.id ?? UUID(),
            agencyId: resolvedAgencyId,
            groupId: resolvedGroupId,
            masterId: resolvedMasterId,
            kind: resolvedKind,
            name: resolvedName,
            group: resolvedGroup,
            startDate: start,
            colorHex: resolvedColorHex,
            imageURL: resolvedDefaultImageURL,
            selectedImageFileName: selectedImageFileName,
            localImageData: finalLocal,
            iconThumbnailData: resolvedIconThumbnailData,
            originalImageData: finalOriginal,
            backgroundImageData: backgroundD,
            isTextColorManual: isTextColorManual,
            textColorHex: resolvedTextColorHex,
            imagePlacement: imagePlacement,
            birthday: finalBDay,
            seitansaiDate: hasS ? sDate : nil,
            debutDate: hasD ? dDate : nil,
            isDisplayed: isDisp,
            isEffectEnabled: isEffectEnabled,
            twitterID: tw,
            instagramID: ins,
            tiktokID: tik,
            timeTreeURL: resolvedKind == .group ? resolvedTimeTreeURL : nil
        )

        if hasSimilarOshi(name: resolvedName, group: resolvedGroup, masterId: resolvedMasterId) {
            pendingOshiToSave = savedOshi
            showingSimilarAlert = true
            return
        }

        saveOshi(savedOshi)
    }

    private func normalized(_ value: String) -> String {
        value
            .folding(options: [.widthInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "\u{3000}", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func katakanaNormalized(_ value: String) -> String {
        let converted = value.unicodeScalars.map { scalar -> Character in
            let hiraganaRange = 0x3041...0x3096
            if hiraganaRange.contains(Int(scalar.value)),
               let katakana = UnicodeScalar(scalar.value + 0x60) {
                return Character(katakana)
            }
            return Character(scalar)
        }
        return String(converted)
    }

    private func looseNormalized(_ value: String) -> String {
        let base = katakanaNormalized(normalized(value))
        return base.filter { char in
            char.isLetter || char.isNumber || ("一"..."龯").contains(String(char)) || ("ぁ"..."ん").contains(String(char)) || ("ァ"..."ヶ").contains(String(char))
        }
    }

    private func liveGroupKey(for oshi: Oshi) -> String? {
        if let groupId = oshi.groupId?.trimmingCharacters(in: .whitespacesAndNewlines), !groupId.isEmpty {
            return "id:\(groupId)"
        }

        let groupName = oshi.group.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !groupName.isEmpty else { return nil }
        return "name:\(normalized(groupName))"
    }

    private func hasDuplicateOshi(name: String, group: String, masterId: String?) -> Bool {
        let normalizedName = normalized(name)
        let normalizedGroup = normalized(group)

        return myOshis.contains { existing in
            if existing.id == editingOshi?.id {
                return false
            }

            if let masterId, let existingMasterId = existing.masterId {
                return existingMasterId == masterId
            }

            return normalized(existing.name) == normalizedName &&
                normalized(existing.group) == normalizedGroup
        }
    }

    private func hasSimilarOshi(name: String, group: String, masterId: String?) -> Bool {
        let looseName = looseNormalized(name)
        let looseGroup = looseNormalized(group)

        return myOshis.contains { existing in
            if existing.id == editingOshi?.id {
                return false
            }

            if let masterId, let existingMasterId = existing.masterId, existingMasterId == masterId {
                return false
            }

            return looseNormalized(existing.name) == looseName &&
                looseNormalized(existing.group) == looseGroup
        }
    }

    private func saveOshi(_ oshi: Oshi) {
        if let o = editingOshi, let i = myOshis.firstIndex(where: { $0.id == o.id }) {
            myOshis[i] = oshi
        } else {
            myOshis.append(oshi)
        }

        saveToUD()
        pendingOshiToSave = nil
        dismiss()
    }

    @MainActor
    private func loadProfileImage(from urlString: String) async {
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            isLoadingProfileImage = false
            profileImageLoadFailed = true
            locD = nil
            originalD = nil
            return
        }

        isLoadingProfileImage = true
        profileImageLoadFailed = false
        locD = nil
        originalD = nil

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200

            guard (200..<300).contains(statusCode),
                  UIImage(data: data) != nil else {
                profileImageLoadFailed = true
                isLoadingProfileImage = false
                return
            }

            locD = data
            originalD = data
            profileImageLoadFailed = false
        } catch {
            profileImageLoadFailed = true
        }

        isLoadingProfileImage = false
    }

    private func defaultImageURLForCurrentSelection() -> String {
        if let masterId = draftMasterId, !masterId.isEmpty,
           let matched = loader.displayOshis.first(where: { $0.masterId == masterId }) {
            return matched.imageURL
        }

        if let idol = findIdol(named: name, in: group) {
            return idol.imageURL
        }

        return editingOshi?.imageURL ?? ""
    }

    private var isUsingNonDefaultProfileImage: Bool {
        let defaultURL = defaultImageURLForCurrentSelection()
        if selectedImageFileName != nil {
            return true
        }
        if !imgU.isEmpty, !defaultURL.isEmpty, imgU != defaultURL {
            return true
        }
        if let locD = locD, let originalD = originalD {
            return locD != originalD
        }
        return false
    }

    private func applyImageCandidate(_ candidate: OshiImageCandidateOption) {
        selectedImageFileName = candidate.fileName
        imgU = candidate.url
        imagePlacement = .default
        Task {
            await loadProfileImage(from: candidate.url)
        }
    }

    private func restoreDefaultImageCandidate() {
        selectedImageFileName = nil
        let defaultURL = defaultImageURLForCurrentSelection()
        imgU = defaultURL
        imagePlacement = .default
        Task {
            await loadProfileImage(from: defaultURL)
        }
    }

    @MainActor
    private func openImageCandidatePicker() async {
        guard selectedKind == .person,
              let agencyId = draftAgencyId, !agencyId.isEmpty,
              let masterId = draftMasterId, !masterId.isEmpty else {
            return
        }

        isPreparingImageCandidatePicker = true
        defer { isPreparingImageCandidatePicker = false }

        var options = loader.imageCandidates(for: agencyId, masterId: masterId)
        if options.isEmpty {
            await loader.fetchImageCandidates(agencyId: agencyId)
            options = loader.imageCandidates(for: agencyId, masterId: masterId)
        }

        guard !options.isEmpty else { return }

        imageCandidatePickerOptions = options
        imageCandidateDisplayLimit = AppConfig.imageCandidateSelectionLimit
        showingImageCandidatePicker = true
    }

    // "05-19" を "5/19" に変換する
    private func convertToDisplay(_ raw: String?) -> String {
        guard let raw = raw, raw.contains("-") else { return raw ?? "" }
        let components = raw.split(separator: "-")
        if components.count == 2 {
            let month = Int(components[0]) ?? 0
            let day = Int(components[1]) ?? 0
            return "\(month)/\(day)" // 5/19 の形式にする
        }
        return raw
    }

    var body: some View {
        NavigationStack {
            Form {
                displaySettingsSection
                registrationTypeSection
                selectionSection
                oshiInfoSection
                anniversarySection
                backgroundImageSection
                snsSection
            }
            .navigationTitle(editingOshi == nil ? "推し選び" : "編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(editingOshi == nil ? "キャンセル" : "キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingOshi == nil ? "推しに決定！" : "更新") {
                        Task {
                            let finalLocal = locD
                            let finalOriginal = originalD
                            saveCurrentOshi(finalLocal: finalLocal, finalOriginal: finalOriginal)
                        }
                    }
                    .disabled(isSaveDisabled)
                }
            }

        }
        .onAppear {
            if let o = editingOshi {
                selectedKind = o.kind
                name = o.name; group = o.group; start = o.startDate; col = o.color
                textCol = (o.textColorHex?.isEmpty == false) ? Color(hex: o.textColorHex ?? "") : o.textColor
                isTextColorManual = o.isTextColorManual
                imgU = o.resolvedRemoteImageURL; locD = o.localImageData; bDayInput = convertToDisplay(o.birthday ?? "")
                isDisp = o.isDisplayed; tw = o.twitterID ?? ""; ins = o.instagramID ?? ""; tik = o.tiktokID ?? ""
                isEffectEnabled = o.isEffectEnabled
                if let sd = o.seitansaiDate { sDate = sd; hasS = true }
                if let dd = o.debutDate { dDate = dd; hasD = true }
                selG = o.group
                locD = o.localImageData
                originalD = o.originalImageData
                selectedImageFileName = o.selectedImageFileName
                backgroundD = o.backgroundImageData
                imagePlacement = o.imagePlacement
                profileImageLoadFailed = o.localImageData == nil && !o.imageURL.isEmpty
                draftAgencyId = o.agencyId
                draftGroupId = o.groupId
                draftMasterId = o.masterId
                if o.localImageData == nil && !o.resolvedRemoteImageURL.isEmpty {
                    Task {
                        await loadProfileImage(from: o.resolvedRemoteImageURL)
                    }
                }
            } else {
                selectedAgency = nil
                selG = ""
                resetImportedOshiFields()
                loader.displayOshis = []
                loader.displayGroupOshis = []
            }
        }
        .task {
            if loader.agencies.isEmpty {
                await loader.fetchAgencies()
            }
            if let agencyId = editingOshi?.agencyId,
               let agency = loader.agencies.first(where: { $0.agencyId == agencyId }) {
                selectedAgency = agency
                await loader.fetchAgencyDetail(url: agency.detailURL)
                syncGroupNameFromDraftGroupId()
                if editingOshi?.kind == .person, editingOshi?.masterId != nil {
                    await loader.fetchImageCandidates(agencyId: agencyId)
                }
            }
        }
        .sheet(isPresented: $showingImageCandidatePicker) {
            NavigationStack {
                GeometryReader { proxy in
                    let horizontalPadding: CGFloat = 16
                    let gridSpacing: CGFloat = 16
                    let columns = makeCandidatePickerColumns(
                        containerWidth: proxy.size.width,
                        horizontalPadding: horizontalPadding,
                        gridSpacing: gridSpacing,
                        requireRegularWidthClass: true,
                        horizontalSizeClass: horizontalSizeClass
                    )

                    ScrollView {
                        VStack(spacing: 0) {
                            LazyVGrid(columns: columns, spacing: gridSpacing) {
                                ForEach(visibleImageCandidatePickerOptions) { candidate in
                                    Button {
                                        applyImageCandidate(candidate)
                                        showingImageCandidatePicker = false
                                    } label: {
                                        OshiImageCandidateCard(
                                            candidate: candidate,
                                            primaryText: imageCandidatePrimaryLabel(candidate),
                                            secondaryText: imageCandidateSecondaryLabel(candidate),
                                            isSelected: selectedImageFileName == candidate.fileName,
                                            cornerRadius: 16
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            if canShowMoreImageCandidates {
                                CandidateLoadMoreButton {
                                    imageCandidateDisplayLimit += AppConfig.imageCandidateSelectionLimit
                                }
                                .padding(.top, 4)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.vertical, 12)
                    }
                }
                .navigationTitle("画像を選ぶ")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") {
                            showingImageCandidatePicker = false
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingImagePlacementEditor) {
            if let currentProfileUIImage {
                OshiImagePlacementEditorView(image: currentProfileUIImage, initialPlacement: imagePlacement) { updatedPlacement in
                    imagePlacement = updatedPlacement
                }
            }
        }
        .alert("同じ推しが登録済みです", isPresented: $showingDuplicateAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("同じ名前とグループ、または同じマスターIDの推しがすでに登録されています。")
        }
        .alert("似ている推しがいます", isPresented: $showingSimilarAlert) {
            Button("キャンセル", role: .cancel) {
                pendingOshiToSave = nil
            }
            Button("そのまま保存") {
                if let pendingOshiToSave {
                    saveOshi(pendingOshiToSave)
                }
            }
        } message: {
            Text("すでに似た推しが登録されています。そのまま保存すると別人として登録されます。")
        }
    }
    
    // --- ユーティリティ ---
    func isValid(_ s: String) -> Bool { s.isEmpty || s.range(of: #"^\d{1,2}/\d{1,2}$"#, options: .regularExpression) != nil }
    
    func convertToInternal(_ s: String) -> String {
        let p = s.split(separator: "/")
        guard p.count == 2, let m = Int(p[0]), let d = Int(p[1]) else { return "" }
        return String(format: "%02d-%02d", m, d)
    }
    
    func convertToDisplay(_ s: String) -> String {
        let p = s.split(separator: "-")
        guard p.count == 2, let m = Int(p[0]), let d = Int(p[1]) else { return s }
        return "\(m)/\(d)"
    }
    
    func saveToUD() {
        LocalStorage.save(myOshis, for: .oshis)
    }
}

struct FarewellView: View {
    let oshi: Oshi
    let chekis: [Cheki]
    var onComplete: () -> Void
    
    @State private var showText = false
    @State private var animateChekis = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // 過去のチェキが昇っていく演出
            ForEach(0..<chekis.count, id: \.self) { i in
                if let ui = UIImage(data: chekis[i].imageData) {
                    Image(uiImage: ui)
                        .resizable().scaledToFit()
                        .frame(width: 120)
                        .rotationEffect(.degrees(Double.random(in: -15...15)))
                        .position(
                            x: CGFloat.random(in: 50...(UIScreen.main.bounds.width - 50)),
                            y: animateChekis ? -200 : UIScreen.main.bounds.height + 200
                        )
                        .opacity(animateChekis ? 0 : 0.7)
                        .animation(.linear(duration: 5).delay(Double(i) * 0.4), value: animateChekis)
                }
            }
            
            VStack(spacing: 25) {
                Text("\(oshi.name) さんと過ごした")
                    .font(.system(size: 18, design: .rounded))
                Text("\(oshi.daysCount)日間")
                    .font(.system(size: 50, weight: .black, design: .rounded))
                Text("たくさんの幸せをありがとう")
                    .font(.system(size: 18, design: .rounded))
            }
            .foregroundColor(.white)
            .opacity(showText ? 1 : 0)
            .offset(y: showText ? 0 : 20)
            
            // 3. 完了ボタン（FarewellView 内）
            VStack {
                Spacer()
                if showText {
                    Button(action: { withAnimation { onComplete() } }) {
                        Text("思い出を胸に刻む")
                            .font(.headline).bold()
                            // ★ 背景色（oshi.color）が明るい色なら黒、濃い色なら白にする
                            .foregroundColor(ColorUtils.isLightColor(oshi.color) ? .black : .white)
                            .padding(.vertical, 15)
                            .padding(.horizontal, 40)
                            .background(oshi.color)
                            .clipShape(Capsule())
                            .shadow(radius: 10)
                    }
                    .padding(.bottom, 60)
                }
            }
        }
        .onAppear {
            withAnimation(.easeIn(duration: 2.0)) { showText = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { animateChekis = true }
        }
    }
}

import SwiftUI

private struct LiveListEntryLink: View {
    let liveID: UUID
    @ObservedObject var loader: OshiLoader
    let myOshis: [Oshi]
    @Binding var myChekis: [Cheki]
    @Binding var myLives: [LiveRecord]
    let startOfToday: Date
    var highlightScheduled: Bool = false
    @Binding var selectedLiveID: UUID?
    @Binding var selectedLivePhotoIndex: Int?

    private var resolvedLive: LiveRecord? {
        myLives.first(where: { $0.id == liveID })
    }

    private var resolvedOshi: Oshi? {
        guard let resolvedLive else { return nil }
        return selectedOshis(for: resolvedLive, myOshis: myOshis).first
    }

    private var isToday: Bool {
        guard highlightScheduled, let resolvedLive else { return false }
        return Calendar.current.isDate(resolvedLive.date, inSameDayAs: startOfToday)
    }

    private var scheduledDaysUntil: Int? {
        guard highlightScheduled, let resolvedLive else { return nil }
        return Calendar.current.dateComponents(
            [.day],
            from: startOfToday,
            to: Calendar.current.startOfDay(for: resolvedLive.date)
        ).day
    }

    var body: some View {
        if let resolvedLive {
            Button {
                selectedLivePhotoIndex = nil
                selectedLiveID = resolvedLive.id
            } label: {
                LiveRow(
                    live: resolvedLive,
                    myOshis: myOshis,
                    isToday: isToday,
                    highlightScheduled: highlightScheduled,
                    scheduledDaysUntil: scheduledDaysUntil
                )
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        }
    }
}

struct LiveListView: View {
    @Binding var myLives: [LiveRecord]
    @Binding var myOshis: [Oshi]
    @Binding var myChekis: [Cheki]
    @Binding var selectedLiveID: UUID?
    @Binding var selectedLivePhotoIndex: Int?
    @Binding var profile: UserProfile
    @ObservedObject var loader: OshiLoader
    
    @State private var showingAddLive = false
    @State private var isAscending = false // false: 新しい順, true: 古い順
    @State private var showingDeleteAlert = false
    @State private var indexSetToDelete: IndexSet? = nil
    @State private var idToDelete: UUID? = nil // 消したいライブのIDを直接保存する

    private var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    var sortedLives: [LiveRecord] {
        myLives.sorted { lhs, rhs in
            // お気に入りを最優先
            if lhs.isFavorite != rhs.isFavorite {
                return lhs.isFavorite
            }
            // 同じなら日付順
            return isAscending ? lhs.date < rhs.date : lhs.date > rhs.date
        }
    }
  
    // 1. お気に入りだけのリスト
    var favoriteLives: [LiveRecord] {
        sortedLives.filter { $0.isFavorite }
    }

    // 2. それ以外のリスト
    var regularLives: [LiveRecord] {
        sortedLives.filter { !$0.isFavorite }
    }

    var todayLives: [LiveRecord] {
        myLives
            .filter { Calendar.current.isDate($0.date, inSameDayAs: startOfToday) }
            .sorted { $0.date < $1.date }
    }

    var upcomingLives: [LiveRecord] {
        myLives
            .filter { $0.date > startOfToday && !Calendar.current.isDate($0.date, inSameDayAs: startOfToday) }
            .sorted { $0.date < $1.date }
    }

    var scheduledLives: [LiveRecord] {
        (todayLives + upcomingLives).sorted { lhs, rhs in
            let lhsIsToday = Calendar.current.isDate(lhs.date, inSameDayAs: startOfToday)
            let rhsIsToday = Calendar.current.isDate(rhs.date, inSameDayAs: startOfToday)
            if lhsIsToday != rhsIsToday {
                return lhsIsToday
            }
            return lhs.date < rhs.date
        }
    }

    private var excludedUpcomingIDs: Set<UUID> {
        Set(scheduledLives.map(\.id))
    }

    var favoritePastLives: [LiveRecord] {
        sortedLives.filter { $0.isFavorite && !excludedUpcomingIDs.contains($0.id) }
    }

    var regularPastLives: [LiveRecord] {
        sortedLives.filter { !$0.isFavorite && !excludedUpcomingIDs.contains($0.id) }
    }

    @ViewBuilder
    private func liveEntryLink(for live: LiveRecord, highlightScheduled: Bool = false) -> some View {
        LiveListEntryLink(
            liveID: live.id,
            loader: loader,
            myOshis: myOshis,
            myChekis: $myChekis,
            myLives: $myLives,
            startOfToday: startOfToday,
            highlightScheduled: highlightScheduled,
            selectedLiveID: $selectedLiveID,
            selectedLivePhotoIndex: $selectedLivePhotoIndex
        )
    }

    @ViewBuilder
    private var scheduledLivesSection: some View {
        if !scheduledLives.isEmpty {
            Section(header:
                Text("参戦予定")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.red)
            ) {
                ForEach(scheduledLives) { live in
                    liveEntryLink(for: live, highlightScheduled: true)
                }
                .onDelete { indexSet in
                    if let index = indexSet.first {
                        self.idToDelete = scheduledLives[index].id
                        self.showingDeleteAlert = true
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var favoriteLivesSection: some View {
        if !favoritePastLives.isEmpty {
            Section(header:
                Text("お気に入り")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.orange)
            ) {
                ForEach(favoritePastLives) { live in
                    liveEntryLink(for: live)
                }
                .onDelete { indexSet in
                    if let index = indexSet.first {
                        self.idToDelete = favoritePastLives[index].id
                        self.showingDeleteAlert = true
                    }
                }
            }
        }
    }

    private var regularLivesSection: some View {
        Section(header: Text("すべての記録").font(.system(size: 12, weight: .bold))) {
            ForEach(regularPastLives) { live in
                liveEntryLink(for: live)
            }
            .onDelete { indexSet in
                if let index = indexSet.first {
                    self.idToDelete = regularPastLives[index].id
                    self.showingDeleteAlert = true
                }
            }
        }
    }

    var body: some View {
        List {
            // 1. リストのすぐ右上に赤い文字でソートボタンを配置
            Section(header:
                HStack {
                    Spacer()
                    Button(action: {
                        withAnimation { isAscending.toggle() }
                    }) {
                        Text(isAscending ? "古い順" : "新しい順")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, -10)
                }
                .textCase(nil)
            ) {
                scheduledLivesSection
                favoriteLivesSection
                regularLivesSection
            }
        }
        .listStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
//            .background(Color(UIColor.systemBackground)) // 5. 全体の背景を白（またはダークモード色）にする
//            .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("参戦の記録")
                    .font(AppTypography.navigationTitleFont(for: profile.preferredAppFont, size: 18))
                    .foregroundColor(.primary)
                    .tracking(-0.5)
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAddLive = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
            }
        }
        .sheet(isPresented: $showingAddLive) {
            AddLiveView(myLives: $myLives, myOshis: $myOshis, editingLive: nil)
                .environmentObject(loader)
        }
        .navigationDestination(item: Binding(
            get: { selectedLiveID.map(IdentifiableUUID.init) },
            set: { selectedLiveID = $0?.value }
        )) { selectedLive in
            let selectedOshi = myLives
                .first(where: { $0.id == selectedLive.value })
                .flatMap { selectedOshis(for: $0, myOshis: myOshis).first }

            LiveDetailView(
                liveID: selectedLive.value,
                oshi: selectedOshi,
                loader: loader,
                allChekis: $myChekis,
                myLives: $myLives,
                myOshis: $myOshis,
                selectedLiveID: $selectedLiveID,
                selectedLivePhotoIndex: $selectedLivePhotoIndex
            )
        }
        .alert("参戦記録を削除しますか？", isPresented: $showingDeleteAlert) {
            Button("キャンセル", role: .cancel) { }
            Button("削除", role: .destructive) {
                if let targetID = idToDelete {
                    myLives.removeAll { $0.id == targetID }
                    if selectedLiveID == targetID {
                        selectedLiveID = nil
                        selectedLivePhotoIndex = nil
                    }
                    save()
                    self.idToDelete = nil
                }
            }
        } message: {
            Text("このアプリに登録したメモや写真は削除されます。\n（※iPhoneの写真アプリにある元の写真は消えません）")
        }
    }

    func save() {
        LocalStorage.save(myLives, for: .lives)
    }
}

// 1行分のデザイン（修正版）
struct LiveRow: View {
    let live: LiveRecord
    let myOshis: [Oshi]
    var isToday: Bool = false
    var highlightScheduled: Bool = false
    var scheduledDaysUntil: Int? = nil

    private var scheduledBadgeText: String? {
        guard let scheduledDaysUntil, scheduledDaysUntil > 0 else { return nil }
        return scheduledDaysUntil == 1 ? "明日" : "あと\(scheduledDaysUntil)日"
    }
    
    var body: some View {
        let selectedOshis = selectedOshis(for: live, myOshis: myOshis)
        let mainColor = selectedOshis.first?.color ?? .gray
        let cardColor = Color(UIColor.secondarySystemGroupedBackground)
        
        let displayGroupItems: [(name: String, badges: [LiveGroupBadge])] = {
            let resolvedItems = resolvedLiveGroupDisplayItems(for: live, myOshis: myOshis)
            var items: [(name: String, badges: [LiveGroupBadge])] = []

            if let firstItem = resolvedItems.first {
                items.append(firstItem)
            }

            if resolvedItems.count > 1 {
                items.append((name: "その他", badges: []))
            }

            return items
        }()
        
        HStack(spacing: 12) {
            // 写真またはアイコン表示
            if let data = live.imageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(mainColor.opacity(0.2))
                    Image(systemName: "music.mic").foregroundColor(mainColor)
                }
                .frame(width: 50, height: 50)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if isToday {
                        Text("本日")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(Capsule())
                    } else if highlightScheduled, let scheduledBadgeText {
                        Text(scheduledBadgeText)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }

                    if live.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.yellow)
                    }
                    
                    Text(live.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                
                if !displayGroupItems.isEmpty {
                    LiveGroupLabelStack(items: displayGroupItems, font: .caption, heartSize: 8)
                }
                
                HStack {
                    Text(live.date, style: .date)
                    Text("@ \(live.venue)")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardColor)
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                .overlay {
                    if highlightScheduled {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke((isToday ? Color.red : Color.orange).opacity(0.28), lineWidth: 1)
                    }
                }
        )
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
    }
}

private struct LiveGroupLabelStack: View {
    let items: [(name: String, badges: [LiveGroupBadge])]
    let font: Font
    var heartSize: CGFloat = 10

    var body: some View {
        HStack(spacing: 8) {
            let isSingleGroup = items.count == 1
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                let maxVisibleHearts = if isSingleGroup {
                    item.name.count <= 10 ? 7 : item.name.count <= 16 ? 5 : 3
                } else {
                    item.name.count <= 8 ? 3 : item.name.count <= 12 ? 2 : 1
                }
                let visibleBadges = Array(item.badges.prefix(maxVisibleHearts))
                let remainingCount = max(item.badges.count - visibleBadges.count, 0)

                HStack(spacing: 3) {
                    Text(item.name)
                        .font(font)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    if !visibleBadges.isEmpty {
                        ForEach(visibleBadges.indices, id: \.self) { colorIndex in
                            Image(systemName: visibleBadges[colorIndex].symbolName)
                                .font(.system(size: heartSize, weight: .bold))
                                .foregroundColor(visibleBadges[colorIndex].color)
                        }
                    }

                    if remainingCount > 0 {
                        Text("+\(remainingCount)")
                            .font(.system(size: max(heartSize - 1, 7), weight: .bold))
                            .foregroundColor(.secondary)
                        }
                }
            }
        }
    }
}

private struct LiveGroupDetailLabelStack: View {
    let items: [(name: String, badges: [LiveGroupBadge])]
    private let maxVisibleHearts = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                let visibleBadges = Array(item.badges.prefix(maxVisibleHearts))
                let remainingCount = max(item.badges.count - visibleBadges.count, 0)

                HStack(spacing: 4) {
                    Text(item.name)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    if !visibleBadges.isEmpty {
                        ForEach(visibleBadges.indices, id: \.self) { colorIndex in
                            Image(systemName: visibleBadges[colorIndex].symbolName)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(visibleBadges[colorIndex].color)
                        }
                    }

                    if remainingCount > 0 {
                        Text("+\(remainingCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

private struct LiveGroupBadge {
    let color: Color
    let symbolName: String
}

private struct LiveDetailToastOverlay: View {
    let message: String

    var body: some View {
        VStack {
            Spacer()
            Text(message)
                .font(.caption.bold())
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Capsule().fill(Color.black.opacity(0.8)))
                .padding(.bottom, 50)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .zIndex(999)
    }
}

struct LiveDetailView: View {
    let liveID: UUID
    let oshi: Oshi?
    @ObservedObject var loader: OshiLoader
    
    @Binding var allChekis: [Cheki]
    @Binding var myLives: [LiveRecord]
    @Binding var myOshis: [Oshi]
    @Binding var selectedLiveID: UUID?
    @Binding var selectedLivePhotoIndex: Int?
  
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var showingEditSheet = false
    @State private var selectedVideoItem: PhotosPickerItem? = nil
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isDeletingVideos = false
    @State private var isReorderingVideos = false
    @State private var draggedVideo: String? = nil
    @State private var isReorderingPhotos = false
    @State private var draggedPhotoID: UUID? = nil
    @State private var isVideoSortAscending = true
    @State private var isPhotoSortAscending = true
    @State private var selectedChekiData: Data? = nil
    @State private var showingToast = false
    @State private var toastMessage = "本体の動画は削除されません"
    @State private var isEditingMemo = false
    @State private var memoDraft = ""
    @FocusState private var isMemoEditorFocused: Bool

    // 新機能：カメラ・ジェスチャー用
    @State private var isShowingCamera = false
    @State private var capturedImageData: Data? = nil

    private func openVenueInMaps(_ venue: String) {
        let trimmedVenue = venue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedVenue.isEmpty else { return }

        var components = URLComponents(string: "https://www.google.com/maps/search/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: trimmedVenue)
        ]

        if let url = components?.url {
            openURL(url)
        }
    }

    private func scheduledBadgeDays(for date: Date) -> Int? {
        let today = Calendar.current.startOfDay(for: Date())
        let target = Calendar.current.startOfDay(for: date)
        return Calendar.current.dateComponents([.day], from: today, to: target).day
    }

    @ViewBuilder
    private func liveEditSheet(for index: Int) -> some View {
        AddLiveView(
            myLives: $myLives,
            myOshis: $myOshis,
            editingLive: myLives[index]
        )
        .environmentObject(loader)
    }

    private func scheduledBadgeText(for date: Date) -> String? {
        guard let days = scheduledBadgeDays(for: date), days > 0 else { return nil }
        return days == 1 ? "明日" : "あと\(days)日"
    }

    var body: some View {
        if let index = myLives.firstIndex(where: { $0.id == liveID }) {
            GeometryReader { proxy in
                let pageWidth = proxy.size.width

                ZStack(alignment: .top) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            
                            // 1. トップの写真 (myLives[index]を直接参照)
                            ZStack(alignment: .bottomTrailing) {
                                if let data = myLives[index].imageData, let ui = UIImage(data: data) {
                                    Image(uiImage: ui)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: pageWidth, height: 250)
                                        .clipped()
                                        .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
                                } else {
                                    // 写真がない時のデザイン
                                    NoPhotoView(color: oshi?.color ?? .gray)
                                        .frame(width: pageWidth, height: 250)
                                }
                                
                                // 右下のカメラボタン
                                Button { isShowingCamera = true } label: {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(10)
                                        .background(Circle().fill(Color.black.opacity(0.5)))
                                        .padding(12)
                                }
                            }
                            .frame(width: pageWidth, height: 250, alignment: .center)
                            .padding(.bottom, 10)
                            
                            // --- ライブ詳細の基本情報セクション ---
                            VStack(alignment: .leading, spacing: 8) {
                                let liveTitle = myLives[index].title
                                let isFavorite = myLives[index].isFavorite
                                
                                HStack(alignment: .center, spacing: 12) {
                                    // 1. 【お気に入りボタン】
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                            myLives[index].isFavorite.toggle()
                                            saveLives()
                                        }
                                    } label: {
                                        Image(systemName: isFavorite ? "star.fill" : "star")
                                            .font(.system(size: 24, weight: .bold))
                                            .foregroundColor(isFavorite ? .yellow : .secondary)
                                            .scaleEffect(isFavorite ? 1.1 : 1.0)
                                    }

                                    // 2. 【ライブ名】（ここはただのテキスト。タップしても何も起きない）
                                    Text(liveTitle)
                                        .font(.system(size: 26, weight: .black, design: .rounded))
                                        .fixedSize(horizontal: false, vertical: true)

                                    // 3. 【編集ボタン】（ここだけを狙って編集画面へ）
                                    Button {
                                        showingEditSheet = true
                                    } label: {
                                        SecondaryCircleIconButton(symbol: "square.and.pencil")
                                    }
                                }
                                .padding(.top, 20)
                                
                                let displayGroupItems = liveGroupDisplayItems(at: index)
                                
                                // 表示
                                if !displayGroupItems.isEmpty {
                                    LiveGroupDetailLabelStack(items: displayGroupItems)
                                }
                                
                                HStack(spacing: 15) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "calendar")

                                        if Calendar.current.isDate(myLives[index].date, inSameDayAs: Date()) {
                                            Text("本日")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.red)
                                                .clipShape(Capsule())
                                        } else if let scheduledText = scheduledBadgeText(for: myLives[index].date) {
                                            Text(scheduledText)
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.orange)
                                                .clipShape(Capsule())
                                        }

                                        Text(myLives[index].date.formatted(date: .long, time: .omitted))
                                    }

                                    if myLives[index].venue.isEmpty {
                                        Label("会場未設定", systemImage: "mappin.and.ellipse")
                                    } else {
                                        Button {
                                            openVenueInMaps(myLives[index].venue)
                                        } label: {
                                            Label(myLives[index].venue, systemImage: "mappin.and.ellipse")
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.top, 4) // 日付・会場のセットだけ少し離すと読みやすい
                            }
                            .padding(.leading, 12) // 写真の左端と合わせるための調整
                            .padding(.trailing, 12)
                            
                            // --- 4. チェキ連携（推しと「その他」の混合対応版） ---
                            let targetChekis = allChekis.filter { cheki in
                                guard let cDate = cheki.date else { return false }
                            
                                // 1. まず日付チェック（同じ日のみ）
                                let isSameDay = Calendar.current.isDate(cDate, inSameDayAs: myLives[index].date)
                                if !isSameDay { return false }
                            
                                // 2. 「選択した推しID」または「その他ID」のいずれかに合致するかチェック
                                // contains を使うことで、混合していても選んだものがすべて表示されます
                                return selectedOshis(for: myLives[index], myOshis: myOshis).contains(where: { $0.id == cheki.oshiID }) ||
                                    (cheki.oshiID == AppConfig.otherID && liveIncludesOtherGroup(myLives[index], myOshis: myOshis))
                            }

                            ForEach(myLives[index].sectionOrder, id: \.self) { sectionKey in
                                liveDetailSectionView(sectionKey, liveIndex: index, targetChekis: targetChekis)
                            }
                        }
                        .frame(width: pageWidth, alignment: .top)
                        .clipped()
                        .padding(.bottom, 28)
                    }
                    .frame(width: pageWidth)

                    // 浮いている「戻るボタン」
                    HStack {
                        Button {
                            selectedLivePhotoIndex = nil
                            selectedLiveID = nil
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Circle().fill(Color.black.opacity(0.5)))
                                .padding(.leading, 15)
                        }
                        Spacer()
                    }
                    .padding(.top, 44)
                    .onAppear {
                        setSwipeBackAction()
                    }
                    
                    if showingToast {
                        LiveDetailToastOverlay(message: toastMessage)
                    }
                }
            }
            .navigationBarBackButtonHidden(true)
            .edgesIgnoringSafeArea(.top)
            .sheet(isPresented: $showingEditSheet) {
                liveEditSheet(for: index)
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                ImagePicker(selectedData: $capturedImageData)
                    .ignoresSafeArea() // カメラを画面の端まで広げる
            }
            .fullScreenCover(item: Binding(get: { selectedChekiData.map { IdentifiableData(data: $0) } }, set: { selectedChekiData = $0?.data })) { identifiableData in
                ZStack {
                    Color.black.edgesIgnoringSafeArea(.all)
                    if let ui = UIImage(data: identifiableData.data) { Image(uiImage: ui).resizable().scaledToFit().padding(20) }
                    VStack { HStack { Spacer(); Button { selectedChekiData = nil } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 30)).foregroundColor(.white.opacity(0.6)) }.padding(20) }; Spacer() }
                }
            }
            .fullScreenCover(item: Binding(get: {
                selectedLivePhotoIndex.map { IdentifiableInt(value: $0) }
            }, set: { newValue in
                selectedLivePhotoIndex = newValue?.value
            })) { currentIndex in
                LivePhotoFullscreenViewer(
                    photos: myLives[index].galleryPhotos,
                    startIndex: currentIndex.value,
                    onClose: { selectedLivePhotoIndex = nil }
                )
            }
            .onChange(of: capturedImageData) { _, newValue in
                if let data = newValue {
                    myLives[index].imageData = data
                    saveLives()
                }
            }
            .onChange(of: selectedVideoItem) { oldValue, newValue in
                if let newValue = newValue {
                    Task {
                        if let id = newValue.itemIdentifier {
                            await MainActor.run {
                                let newRecord = VideoRecord(videoID: id, title: "")
                                if !myLives[index].videoRecords.contains(where: { $0.videoID == id }) {
                                    myLives[index].videoRecords.append(newRecord)
                                    saveLives()
                                }
                            }
                        }
                    }
                }
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    var appendedPhotos: [LivePhotoItem] = []
                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            appendedPhotos.append(LivePhotoItem(imageData: data, date: Date()))
                        }
                    }

                    await MainActor.run {
                        myLives[index].galleryPhotos.insert(contentsOf: appendedPhotos, at: 0)
                        selectedPhotoItems = []
                        saveLives()
                    }
                }
            }
            .onAppear {
                memoDraft = myLives[index].memo
            }
            .onDisappear {
                guard scenePhase == .active, selectedLiveID == liveID else { return }
                selectedLivePhotoIndex = nil
                selectedLiveID = nil
            }
        }
   }

    func saveLives() { LocalStorage.save(myLives, for: .lives) }

    private func liveGroupDisplayItems(at index: Int) -> [(name: String, badges: [LiveGroupBadge])] {
        resolvedLiveGroupDisplayItems(for: myLives[index], myOshis: myOshis)
    }

    private func beginMemoEditing(index: Int) {
        memoDraft = myLives[index].memo
        isEditingMemo = true
        isMemoEditorFocused = true
    }

    private func finishMemoEditing(index: Int) {
        myLives[index].memo = memoDraft
        saveLives()
        isEditingMemo = false
        isMemoEditorFocused = false
    }

    @ViewBuilder
    func liveDetailSectionView(_ sectionKey: String, liveIndex index: Int, targetChekis: [Cheki]) -> some View {
        switch sectionKey {
        case "photo":
            if myLives[index].isPhotoSectionVisible {
                VStack(alignment: .leading, spacing: 12) {
                    let photoCount = myLives[index].galleryPhotos.count
                    let hasPhotos = photoCount > 0

                    HStack(spacing: 12) {
                        LiveSectionChipHeader(title: "写真 (\(photoCount)枚)", systemImage: "photo.on.rectangle")

                        PhotosPicker(selection: $selectedPhotoItems, matching: .images) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 14, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.08))
                                .cornerRadius(10)
                        }

                        if photoCount > 1 {
                            SortVideosButton(
                                isDisabled: false,
                                action: { sortPhotosByDate(index: index) }
                            )
                        }

                        if photoCount > 1 {
                            Button {
                                withAnimation(.spring()) {
                                    isReorderingPhotos.toggle()
                                }
                            } label: {
                                Image(systemName: isReorderingPhotos ? "checkmark" : "arrow.left.arrow.right")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.secondary.opacity(0.08))
                                    .cornerRadius(10)
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal)

                    if hasPhotos {
                        LivePhotoStripView(
                            photos: $myLives[index].galleryPhotos,
                            isReorderingPhotos: isReorderingPhotos,
                            draggedPhotoID: $draggedPhotoID,
                            onSelect: { tappedIndex in selectedLivePhotoIndex = tappedIndex },
                            onMoveLeft: { photoID in
                                movePhotoLeft(photoID: photoID, liveIndex: index)
                            },
                            onMoveRight: { photoID in
                                movePhotoRight(photoID: photoID, liveIndex: index)
                            },
                            onReorder: { isPhotoSortAscending = true },
                            onSave: { saveLives() }
                        )
                    } else {
                        Text("写真がまだありません")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 30)
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(12)
                            .padding(.horizontal)
                    }
                }
                .padding(.top, 20)
            }

        case "video":
            if myLives[index].isVideoSectionVisible {
                VStack(alignment: .leading, spacing: 12) {
                    let videoCount = myLives[index].videoRecords.count
                    let hasMultipleVideos = videoCount > 1

                    HStack(spacing: 12) {
                        LiveSectionChipHeader(title: "撮可 (\(videoCount))", systemImage: "video")

                        PhotosPicker(selection: $selectedVideoItem, matching: .videos, photoLibrary: .shared()) {
                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 14, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.08))
                                .cornerRadius(10)
                        }
                        .disabled(isDeletingVideos)

                        if hasMultipleVideos {
                            Button {
                                saveLives()
                                playAllVideos(records: myLives[index].videoRecords)
                            } label: {
                                Image(systemName: "play.rectangle.on.rectangle.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.secondary.opacity(0.08))
                                    .cornerRadius(10)
                            }
                            .disabled(isDeletingVideos)
                        }

                        if hasMultipleVideos {
                            SortVideosButton(
                                isDisabled: false,
                                action: { sortVideosByDate(index: index) }
                            )
                        }

                        if hasMultipleVideos {
                            Button {
                                withAnimation(.spring()) {
                                    isReorderingVideos.toggle()
                                }
                            } label: {
                                Image(systemName: isReorderingVideos ? "checkmark" : "arrow.left.arrow.right")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.secondary.opacity(0.08))
                                    .cornerRadius(10)
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal)
                    
                    if myLives[index].videoRecords.isEmpty {
                        Text("動画がまだありません").font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 30).background(Color.secondary.opacity(0.05)).cornerRadius(12)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach($myLives[index].videoRecords) { $record in
                                    VideoItemView(
                                        record: $record,
                                        isDeletingVideos: false,
                                        isReorderingVideos: isReorderingVideos,
                                        onPlay: {
                                            saveLives()
                                            playVideo(identifier: record.videoID)
                                        },
                                        onDelete: {},
                                        onMoveLeft: {
                                            moveVideoLeft(videoID: record.videoID, liveIndex: index)
                                        },
                                        onMoveRight: {
                                            moveVideoRight(videoID: record.videoID, liveIndex: index)
                                        },
                                        onSave: { saveLives() }
                                    )
                                    .onDrag {
                                        draggedVideo = record.videoID
                                        return NSItemProvider(object: record.videoID as NSString)
                                    }
                                    .onDrop(
                                        of: [UTType.text],
                                        delegate: VideoDropDelegate(
                                            item: record.videoID,
                                            items: $myLives[index].videoRecords,
                                            draggedItem: $draggedVideo,
                                            onReorder: { isVideoSortAscending = true },
                                            onSave: { saveLives() }
                                        )
                                    )
                                }
                            }
                            .padding(.leading, 20)
                            .padding(.trailing, 20)
                        }
                        .frame(height: 190)
                    }
                }
                .padding(.top, 20)
            }

        case "cheki":
            if myLives[index].isChekiSectionVisible {
                VStack(alignment: .leading, spacing: 12) {
                    LiveSectionChipHeader(title: "この日のチェキ (\(targetChekis.count)枚)", systemImage: "person.crop.rectangle.fill")
                        .padding(.horizontal)
                    
                    if targetChekis.isEmpty {
                        Text("チェキがありません").font(.caption).padding(.horizontal)
                    } else {
                        LiveChekiStripView(
                            chekis: targetChekis,
                            onSelect: { cheki in selectedChekiData = cheki.imageData }
                        )
                    }
                }
                .padding(.top, 20)
            }

        case "memo":
            if myLives[index].isMemoSectionVisible {
                VStack(alignment: .leading, spacing: 12) {
                    LiveSectionChipHeader(title: "メモ（感想・セトリなど）", systemImage: "note.text")

                    if isEditingMemo {
                        VStack(alignment: .leading, spacing: 10) {
                            TextEditor(text: $memoDraft)
                                .frame(minHeight: 140)
                                .padding(8)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(15)
                                .focused($isMemoEditorFocused)

                            HStack {
                                Spacer()
                                Button("完了") {
                                    finishMemoEditing(index: index)
                                }
                                .font(.subheadline.weight(.semibold))
                            }
                        }
                    } else {
                        Button {
                            beginMemoEditing(index: index)
                        } label: {
                            Text(myLives[index].memo.isEmpty ? "メモを書く" : myLives[index].memo)
                                .font(.body)
                                .lineSpacing(6)
                                .foregroundColor(myLives[index].memo.isEmpty ? .secondary : .primary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(15)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
            }

        default:
            EmptyView()
        }
    }

    func liveGroupDisplayString(at index: Int) -> String {
        let selectedOshis = selectedOshis(for: myLives[index], myOshis: myOshis)
        let groupSet = Set(selectedOshis.compactMap { $0.group.isEmpty ? $0.name : $0.group })
        var sortedGroups = Array(groupSet).sorted()
        if liveIncludesOtherGroup(myLives[index], myOshis: myOshis) {
            sortedGroups.append("その他")
        }
        return sortedGroups.joined(separator: "、")
    }

    func sortVideosByDate(index: Int) {
        let identifiers = myLives[index].videoRecords.map { $0.videoID }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var dateMap: [String: Date] = [:]
        assets.enumerateObjects { (asset, _, _) in dateMap[asset.localIdentifier] = asset.creationDate }
        withAnimation(.spring()) {
            if isVideoSortAscending {
                myLives[index].videoRecords.sort { (dateMap[$0.videoID] ?? Date.distantPast) < (dateMap[$1.videoID] ?? Date.distantPast) }
            } else {
                myLives[index].videoRecords.sort { (dateMap[$0.videoID] ?? Date.distantPast) > (dateMap[$1.videoID] ?? Date.distantPast) }
            }
            isVideoSortAscending.toggle()
            saveLives()
        }
    }

    func sortPhotosByDate(index: Int) {
        withAnimation(.spring()) {
            if isPhotoSortAscending {
                myLives[index].galleryPhotos.sort { $0.date < $1.date }
            } else {
                myLives[index].galleryPhotos.sort { $0.date > $1.date }
            }
            isPhotoSortAscending.toggle()
            saveLives()
        }
    }

    func moveVideoLeft(videoID: String, liveIndex: Int) {
        guard let from = myLives[liveIndex].videoRecords.firstIndex(where: { $0.videoID == videoID }),
              from > 0 else { return }
        withAnimation(.spring()) {
            myLives[liveIndex].videoRecords.swapAt(from, from - 1)
            isVideoSortAscending = true
            saveLives()
        }
    }

    func moveVideoRight(videoID: String, liveIndex: Int) {
        guard let from = myLives[liveIndex].videoRecords.firstIndex(where: { $0.videoID == videoID }),
              from < myLives[liveIndex].videoRecords.count - 1 else { return }
        withAnimation(.spring()) {
            myLives[liveIndex].videoRecords.swapAt(from, from + 1)
            isVideoSortAscending = true
            saveLives()
        }
    }

    func movePhotoLeft(photoID: UUID, liveIndex: Int) {
        guard let from = myLives[liveIndex].galleryPhotos.firstIndex(where: { $0.id == photoID }),
              from > 0 else { return }
        withAnimation(.spring()) {
            myLives[liveIndex].galleryPhotos.swapAt(from, from - 1)
            isPhotoSortAscending = true
            saveLives()
        }
    }

    func movePhotoRight(photoID: UUID, liveIndex: Int) {
        guard let from = myLives[liveIndex].galleryPhotos.firstIndex(where: { $0.id == photoID }),
              from < myLives[liveIndex].galleryPhotos.count - 1 else { return }
        withAnimation(.spring()) {
            myLives[liveIndex].galleryPhotos.swapAt(from, from + 1)
            isPhotoSortAscending = true
            saveLives()
        }
    }

    func setSwipeBackAction() {
        // 画面が表示された時に、スワイプ戻りを強制的に有効にする
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        
        func findNavigationController(viewController: UIViewController) -> UINavigationController? {
            if let nav = viewController as? UINavigationController { return nav }
            for child in viewController.children {
                if let nav = findNavigationController(viewController: child) { return nav }
            }
            return nil
        }

        if let nav = findNavigationController(viewController: rootVC) {
            nav.interactivePopGestureRecognizer?.delegate = nil // Delegateを空にすることで強制有効化
        }
    }

    func playAllVideos(records: [VideoRecord]) {
        let identifiers = records.map { $0.videoID }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assetMap: [String: PHAsset] = [:]
        assets.enumerateObjects { (asset, _, _) in assetMap[asset.localIdentifier] = asset }
        let sortedAssets = identifiers.compactMap { assetMap[$0] }
        let group = DispatchGroup()
        var items: [AVPlayerItem] = []
        for asset in sortedAssets {
            group.enter()
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: nil) { item, _ in
                if let item = item { items.append(item) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let queuePlayer = AVQueuePlayer(items: items)
            let controller = AVPlayerViewController(); controller.player = queuePlayer
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene, let rootVC = scene.windows.first?.rootViewController {
                if let lastItem = items.last {
                    NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: lastItem,
                        queue: .main
                    ) { _ in
                        controller.dismiss(animated: true)
                    }
                }
                rootVC.present(controller, animated: true) { queuePlayer.play() }
            }
        }
    }

    func playVideo(identifier: String) {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = result.firstObject else { return }
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: nil) { item, _ in
            DispatchQueue.main.async {
                if let playerItem = item {
                    let player = AVPlayer(playerItem: playerItem)
                    let controller = AVPlayerViewController(); controller.player = player
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene, let rootVC = scene.windows.first?.rootViewController {
                        NotificationCenter.default.addObserver(
                            forName: .AVPlayerItemDidPlayToEndTime,
                            object: playerItem,
                            queue: .main
                        ) { _ in
                            controller.dismiss(animated: true)
                        }
                        rootVC.present(controller, animated: true) { player.play() }
                    }
                }
            }
        }
    }
}

// 写真がない時の専用パーツ
struct NoPhotoView: View {
    let color: Color
    
    var body: some View {
        ZStack {
            RadialGradient(
                gradient: Gradient(colors: [
                    color.opacity(0.05), // ★ 中心：かなり薄く（ほぼ透明）
                    color.opacity(0.4)   // ★ 外側：推し色をふんわり乗せる
                ]),
                center: .center,
                startRadius: 5,
                endRadius: 120 // 少し広めにすると外側への広がりが綺麗です
            )
            .background(color.opacity(0.1)) // 全体にうっすら色を敷くと、より逆グラデが映えます

            
            Image(systemName: "music.mic")
                .font(.system(size: 50, weight: .thin))
                .foregroundColor(color.opacity(0.5))
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
    }
}

// Data型をIdentifiableにするための構造体
struct IdentifiableData: Identifiable {
    let id = UUID()
    let data: Data
}

struct IdentifiableUUID: Identifiable, Hashable {
    let value: UUID
    var id: UUID { value }
}

struct IdentifiableInt: Identifiable, Hashable {
    let value: Int
    var id: Int { value }
}

// --- サブビューとデリゲート ---

struct VideoItemView: View {
    @Binding var record: VideoRecord
    let isDeletingVideos: Bool
    let isReorderingVideos: Bool
    let onPlay: () -> Void
    let onDelete: () -> Void
    let onMoveLeft: () -> Void
    let onMoveRight: () -> Void
    let onSave: () -> Void
    
    @State private var creationDate: String = ""
    @State private var duration: String = "" // ★ 動画の長さを保持

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            // 1. 曲名・メモ
            TextField("曲名・メモ", text: $record.title)
                .font(.system(size: 10, weight: .bold))
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .frame(width: 90, height: 22)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)

            // 2. サムネイル
            ZStack(alignment: .bottomTrailing) { // ★ 長さは右下に重ねるとビデオっぽい
                VideoThumbnailView(videoID: record.videoID)
                    .contentShape(Rectangle())
                    .onTapGesture { if !isDeletingVideos { onPlay() } }
                
                // ★ 右下に動画の長さを表示
                if !duration.isEmpty {
                    Text(duration)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                        .padding(4)
                }

                // 削除ボタン（右上）はそのまま
                if isDeletingVideos {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.red).background(Circle().fill(.white)).offset(x: 8, y: -8)
                    }
                }
            }
            
            // 3. 撮影日時
            if !creationDate.isEmpty {
                Text(creationDate)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }

            if isReorderingVideos {
                HStack(spacing: 10) {
                    Button(action: onMoveLeft) {
                        Image(systemName: "arrow.left.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                    }

                    Button(action: onMoveRight) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .onAppear { fetchVideoInfo() }
    }

    func fetchVideoInfo() {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [record.videoID], options: nil)
        if let asset = assets.firstObject {
            // 日時の取得
            if let date = asset.creationDate {
                let formatter = DateFormatter()
                formatter.dateFormat = "M/d HH:mm"
                self.creationDate = formatter.string(from: date)
            }
            // ★ 長さの取得と変換
            let minutes = Int(asset.duration) / 60
            let seconds = Int(asset.duration) % 60
            self.duration = String(format: "%d:%02d", minutes, seconds)
        } else {
            self.creationDate = "リンク切れ"
            self.duration = ""
        }
    }
}

struct VideoDropDelegate: DropDelegate {
    let item: String
    @Binding var items: [VideoRecord]
    @Binding var draggedItem: String?
    var onReorder: () -> Void
    var onSave: () -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        onSave()
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem, draggedItem != item else { return }
        if let from = items.firstIndex(where: { $0.videoID == draggedItem }),
           let to = items.firstIndex(where: { $0.videoID == item }) {
            withAnimation(.spring()) {
                items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
            onReorder()
        }
    }
}

struct PhotoDropDelegate: DropDelegate {
    let item: UUID
    @Binding var items: [LivePhotoItem]
    @Binding var draggedItem: UUID?
    var onReorder: () -> Void
    var onSave: () -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        onSave()
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem, draggedItem != item else { return }
        if let from = items.firstIndex(where: { $0.id == draggedItem }),
           let to = items.firstIndex(where: { $0.id == item }) {
            withAnimation(.spring()) {
                items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
            onReorder()
        }
    }
}

private struct SecondaryCircleIconButton: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(.secondary)
            .padding(8)
            .background(Circle().fill(Color.secondary.opacity(0.1)))
    }
}

private struct SortVideosButton: View {
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(10)
        }
        .disabled(isDisabled)
    }
}

private struct LiveChekiStripView: View {
    let chekis: [Cheki]
    let onSelect: (Cheki) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(chekis) { cheki in
                    DownsampledDataImage(
                        cacheKey: "live-cheki-\(cheki.id.uuidString)-\(chekiThumbnailFingerprint(cheki))",
                        data: cheki.thumbnailData,
                        maxPixelSize: 150,
                        contentMode: .fit
                    )
                    .frame(width: 110, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 3)
                    .onTapGesture { onSelect(cheki) }
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, 20)
        }
        .frame(height: 160)
        .clipped()
    }
}

private struct LivePhotoStripView: View {
    @Binding var photos: [LivePhotoItem]
    let isReorderingPhotos: Bool
    @Binding var draggedPhotoID: UUID?
    let onSelect: (Int) -> Void
    let onMoveLeft: (UUID) -> Void
    let onMoveRight: (UUID) -> Void
    let onReorder: () -> Void
    let onSave: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    VStack(spacing: 8) {
                        DownsampledDataImage(
                            cacheKey: "live-photo-strip-\(photo.id.uuidString)",
                            data: photo.imageData,
                            maxPixelSize: 300,
                            contentMode: .fill
                        )
                        .frame(width: 110, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 3)
                        .onTapGesture { onSelect(index) }
                        .onDrag {
                            draggedPhotoID = photo.id
                            return NSItemProvider(object: photo.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: PhotoDropDelegate(
                                item: photo.id,
                                items: $photos,
                                draggedItem: $draggedPhotoID,
                                onReorder: onReorder,
                                onSave: onSave
                            )
                        )

                        if isReorderingPhotos {
                            HStack(spacing: 10) {
                                Button(action: { onMoveLeft(photo.id) }) {
                                    Image(systemName: "arrow.left.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.secondary)
                                }

                                Button(action: { onMoveRight(photo.id) }) {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, 20)
        }
        .frame(height: isReorderingPhotos ? 190 : 160)
        .clipped()
    }
}

private struct EditableLivePhotoThumbnail: View {
    let photo: LivePhotoItem
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            DownsampledDataImage(
                cacheKey: "editable-live-photo-\(photo.id.uuidString)",
                data: photo.imageData,
                maxPixelSize: 240,
                contentMode: .fill
            )
            .frame(width: 90, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.red)
                    .background(Circle().fill(.white))
            }
            .padding(4)
        }
    }
}

private struct LivePhotoFullscreenViewer: View {
    let photos: [LivePhotoItem]
    let startIndex: Int
    let onClose: () -> Void

    @State private var selection: Int = 0
    @State private var verticalDragOffset: CGFloat = 0
    @State private var zoomedPhotoID: UUID? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    GeometryReader { proxy in
                        ZStack {
                            Color.black.ignoresSafeArea()

                            if let ui = UIImage(data: photo.imageData) {
                                Image(uiImage: ui)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(
                                        width: proxy.size.width,
                                        height: proxy.size.height,
                                        alignment: .center
                                    )
                                    .scaleEffect(zoomedPhotoID == photo.id ? 2.0 : 1.0)
                                    .animation(.spring(response: 0.25, dampingFraction: 0.85), value: zoomedPhotoID == photo.id)
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                    .tag(index)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onClose()
                    }
                    .onTapGesture(count: 2) {
                        zoomedPhotoID = (zoomedPhotoID == photo.id) ? nil : photo.id
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .offset(y: verticalDragOffset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        guard abs(value.translation.height) > abs(value.translation.width),
                              value.translation.height > 0 else { return }
                        verticalDragOffset = value.translation.height
                    }
                    .onEnded { value in
                        let isVertical = abs(value.translation.height) > abs(value.translation.width)
                        let shouldClose = isVertical && value.translation.height > 120

                        if shouldClose {
                            onClose()
                        } else {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                verticalDragOffset = 0
                            }
                        }
                    }
            )

            VStack {
                HStack {
                    Spacer()
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.top, 20)
                    .padding(.trailing, 20)
                }
                Spacer()
            }
        }
        .onAppear {
            selection = min(max(startIndex, 0), max(photos.count - 1, 0))
            verticalDragOffset = 0
            zoomedPhotoID = nil
        }
        .onChange(of: selection) { _, _ in
            zoomedPhotoID = nil
        }
    }
}

// 動画IDからサムネイルを自動で作って表示するView
struct VideoThumbnailView: View {
    let videoID: String
    @State private var thumbnail: UIImage? = nil
    @State private var isMissing = false

    var body: some View {
        ZStack {
            if let uiImage = thumbnail {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill() // ここで枠いっぱいに広げる
            } else if isMissing {
                ZStack {
                    Color.secondary.opacity(0.08)
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text("リンク切れ")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Color.black.opacity(0.1)
                ProgressView()
            }
            
            if !isMissing {
                // 再生アイコン
                Image(systemName: "play.fill")
                    .foregroundColor(.white)
                    .font(.body)
                    .padding(8)
                    .background(.black.opacity(0.4))
                    .clipShape(Circle())
            }
        }
        // ★ 縦横比を「3:4」や「9:16」に近い縦長に設定
        .frame(width: 90, height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            generateThumbnail()
        }
    }

    func generateThumbnail() {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [videoID], options: nil)
        guard let asset = assets.firstObject else {
            DispatchQueue.main.async {
                self.thumbnail = nil
                self.isMissing = true
            }
            return
        }
        isMissing = false

        let manager = PHImageManager.default()
        let option = PHImageRequestOptions()
        option.isNetworkAccessAllowed = true // iCloud上の動画も考慮
        
        // ★ 取得するサイズも縦長にリクエスト
        manager.requestImage(for: asset,
                           targetSize: CGSize(width: 180, height: 280),
                           contentMode: .aspectFill,
                           options: option) { image, _ in
            DispatchQueue.main.async {
                self.thumbnail = image
            }
        }
    }
}

private struct LiveSectionChipHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct AddLiveView: View {
    @Binding var myLives: [LiveRecord]
    @Binding var myOshis: [Oshi]
    @EnvironmentObject var loader: OshiLoader
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL
    
    let editingLive: LiveRecord?
    
    // 入力項目
    @State private var selectedGroupNames: [String] = []
    @State private var isOtherGroupSelected = false
    @State private var date = Date()
    @State private var title = ""
    @State private var venue = ""
    @State private var memo = ""
    @State private var imageData: Data? = nil
    @State private var isPhotoSectionVisible = true
    @State private var isVideoSectionVisible = true
    @State private var isChekiSectionVisible = true
    @State private var isMemoSectionVisible = true
    @State private var sectionOrder = LiveRecord.defaultSectionOrder
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var galleryPhotos: [LivePhotoItem] = []
    @State private var selectedGalleryItems: [PhotosPickerItem] = []
    @State private var selectedVideoItem: PhotosPickerItem? = nil
    @State private var videoRecords: [VideoRecord] = []
    @State private var showingDeleteAllPhotosAlert = false
    @State private var showingDeleteAllVideosAlert = false
    @State private var timeTreeSuggestions: [TimeTreeEventSuggestion] = []
    @State private var isLoadingTimeTreeSuggestions = false
    @State private var timeTreeSuggestionErrorMessage: String? = nil
    @State private var selectedTimeTreeEventURL: URL? = nil
    
    // 会場サジェスト用
    @State private var venueSuggestions: [VenueInfo] = []

    private var recentVenueNames: [String] {
        myLives
            .sorted { $0.date > $1.date }
            .map(\.venue)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .reduce(into: [String]()) { result, venueName in
                if !result.contains(venueName) {
                    result.append(venueName)
                }
            }
    }

    private var filteredVenueSuggestions: [VenueInfo] {
        let query = venue.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseSuggestions: [VenueInfo]

        if query.isEmpty {
            baseSuggestions = venueSuggestions
        } else {
            baseSuggestions = venueSuggestions.filter {
                $0.searchableTexts.contains {
                    $0.range(of: query, options: .caseInsensitive) != nil
                }
            }
        }

        let recentMatches = recentVenueNames.compactMap { recentName in
            baseSuggestions.first(where: { $0.name == recentName })
        }

        let remainingMatches = baseSuggestions.filter { info in
            !recentMatches.contains(where: { $0.id == info.id })
        }

        return Array((recentMatches + remainingMatches).prefix(8))
    }

    private func groupReference(for groupName: String) -> LiveGroupReference {
        let matchingOshis = myOshis.filter { $0.group == groupName }
        let groupId = matchingOshis.compactMap(\.groupId).first
        return makeLiveGroupReference(groupId: groupId, groupName: groupName)
    }

    private func configuredTimeTreeURL(for groupName: String) -> String? {
        loader.displayGroupOshis
            .filter { $0.group == groupName }
            .compactMap(\.timeTreeURL)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private var selectedTimeTreeSourceGroupName: String? {
        selectedGroupNames.first { configuredTimeTreeURL(for: $0) != nil }
    }

    private var selectedTimeTreeSourceValue: String? {
        guard let selectedTimeTreeSourceGroupName else { return nil }
        return configuredTimeTreeURL(for: selectedTimeTreeSourceGroupName)
    }

    private var selectedTimeTreeAliasCode: String? {
        guard let selectedTimeTreeSourceValue else { return nil }
        return TimeTreePublicCalendarClient.calendarIdentifier(from: selectedTimeTreeSourceValue)
    }

    private func ensureTimeTreeSourceLoadedIfNeeded() async {
        let targetGroupNames = selectedGroupNames.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !targetGroupNames.isEmpty else { return }

        if loader.agencies.isEmpty {
            await loader.fetchAgencies()
        }

        for groupName in targetGroupNames {
            if configuredTimeTreeURL(for: groupName) != nil {
                return
            }

            let matchingAgencyIDs = myOshis
                .filter { $0.group == groupName }
                .compactMap(\.agencyId)
                .filter { !$0.isEmpty }

            for agencyId in matchingAgencyIDs {
                guard let agency = loader.agencies.first(where: { $0.agencyId == agencyId }) else { continue }
                await loader.fetchAgencyDetail(url: agency.detailURL)

                if configuredTimeTreeURL(for: groupName) != nil {
                    return
                }
            }
        }
    }

    private var shouldShowTimeTreeSuggestionsSection: Bool {
        !timeTreeSuggestions.isEmpty
    }

    private var timeTreeLookupKey: String {
        let dayKey = ISO8601DateFormatter().string(from: Calendar(identifier: .gregorian).startOfDay(for: date))
        let selectedGroupsKey = selectedGroupNames.sorted().joined(separator: ",")
        return [selectedGroupsKey, selectedTimeTreeSourceGroupName ?? "", selectedTimeTreeAliasCode ?? "", dayKey, String(isOtherGroupSelected)].joined(separator: "|")
    }

    private func buildLiveRecord() -> LiveRecord {
        var appearingGroups = selectedGroupNames.map(groupReference(for:))
        if isOtherGroupSelected {
            appearingGroups.append(makeLiveGroupReference(groupId: nil, groupName: "その他", isOther: true))
        }

        return LiveRecord(
            id: editingLive?.id ?? UUID(),
            appearingGroups: appearingGroups,
            date: date,
            title: title,
            venue: venue,
            memo: memo,
            imageData: imageData,
            isPhotoSectionVisible: isPhotoSectionVisible,
            isVideoSectionVisible: isVideoSectionVisible,
            isChekiSectionVisible: isChekiSectionVisible,
            isMemoSectionVisible: isMemoSectionVisible,
            sectionOrder: sectionOrder,
            galleryPhotos: galleryPhotos,
            videoRecords: videoRecords,
            isFavorite: editingLive?.isFavorite ?? false
        )
    }

    private func removeGalleryPhoto(at index: Int) {
        galleryPhotos.remove(at: index)
    }

    private func removeVideoRecord(_ record: VideoRecord) {
        videoRecords.removeAll { $0.id == record.id }
    }

    private func sectionTitle(for key: String) -> String {
        switch key {
        case "photo": return "写真"
        case "video": return "撮可"
        case "cheki": return "チェキ"
        case "memo": return "メモ"
        default: return key
        }
    }

    private func sectionVisibilityBinding(for key: String) -> Binding<Bool>? {
        switch key {
        case "photo":
            return $isPhotoSectionVisible
        case "video":
            return $isVideoSectionVisible
        case "cheki":
            return $isChekiSectionVisible
        case "memo":
            return $isMemoSectionVisible
        default:
            return nil
        }
    }

    private func moveSections(from source: IndexSet, to destination: Int) {
        sectionOrder.move(fromOffsets: source, toOffset: destination)
    }

    private func normalizedVenueSearchKey(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func venueCandidateFromTitle(_ title: String) -> String? {
        for separator in ["＠", "@"] {
            if let range = title.range(of: separator) {
                let candidate = title[range.upperBound...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: .newlines)
                    .first?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let candidate, !candidate.isEmpty {
                    return candidate
                }
            }
        }
        return nil
    }

    private func matchedVenueInfo(for rawVenueName: String) -> VenueInfo? {
        let normalizedCandidate = normalizedVenueSearchKey(rawVenueName)
        guard !normalizedCandidate.isEmpty else { return nil }

        return venueSuggestions.first(where: { info in
            info.searchableTexts.contains { searchableText in
                normalizedVenueSearchKey(searchableText) == normalizedCandidate
            }
        })
    }

    private func cleanedEventTitleForAutoFill(from suggestion: TimeTreeEventSuggestion, resolvedVenueInfo: VenueInfo?) -> String {
        guard let resolvedVenueInfo,
              let rawVenueCandidate = venueCandidateFromTitle(suggestion.title),
              let titleVenueInfo = matchedVenueInfo(for: rawVenueCandidate),
              titleVenueInfo.id == resolvedVenueInfo.id
        else {
            return normalizedAutoFilledEventTitle(suggestion.title)
        }

        var cleanedTitle = suggestion.title
        for separator in ["＠", "@"] {
            if let range = cleanedTitle.range(of: separator) {
                cleanedTitle = String(cleanedTitle[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        let normalizedTitle = normalizedAutoFilledEventTitle(cleanedTitle)
        return normalizedTitle.isEmpty ? normalizedAutoFilledEventTitle(suggestion.title) : normalizedTitle
    }

    private func normalizedAutoFilledEventTitle(_ title: String) -> String {
        var result = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let wrapperPairs: [(Character, Character)] = [
            ("「", "」"),
            ("『", "』"),
            ("【", "】"),
            ("(", ")"),
            ("（", "）"),
            ("[", "]"),
            ("［", "］")
        ]

        var didTrim = true
        while didTrim, let first = result.first, let last = result.last {
            didTrim = false
            for (opening, closing) in wrapperPairs where first == opening && last == closing {
                result = String(result.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                didTrim = true
                break
            }
        }

        return result
    }

    private func resolvedVenueInfoForAutoFill(from suggestion: TimeTreeEventSuggestion) -> VenueInfo? {
        guard let rawVenueName = suggestion.extractedVenueName, !rawVenueName.isEmpty else {
            return nil
        }

        return matchedVenueInfo(for: rawVenueName)
    }

    private func resolvedVenueNameForAutoFill(from suggestion: TimeTreeEventSuggestion) -> String? {
        resolvedVenueInfoForAutoFill(from: suggestion)?.name
    }

    private func applyTimeTreeSuggestion(_ suggestion: TimeTreeEventSuggestion) {
        let venueInfo = resolvedVenueInfoForAutoFill(from: suggestion)
        title = cleanedEventTitleForAutoFill(from: suggestion, resolvedVenueInfo: venueInfo)
        selectedTimeTreeEventURL = suggestion.eventURL
        if let venueInfo {
            venue = venueInfo.name
        }
    }

    private func applyTimeTreeSuggestionAndLoadImage(_ suggestion: TimeTreeEventSuggestion) {
        applyTimeTreeSuggestion(suggestion)

        guard let coverImageURL = suggestion.coverImageURL else { return }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: coverImageURL)
                guard UIImage(data: data) != nil else { return }
                await MainActor.run {
                    imageData = data
                }
            } catch {
                // 画像取得に失敗してもイベント名入力は続行
            }
        }
    }

    private func loadTimeTreeSuggestionsIfNeeded() async {
        await ensureTimeTreeSourceLoadedIfNeeded()

        guard let aliasCode = selectedTimeTreeAliasCode else {
            await MainActor.run {
                timeTreeSuggestions = []
                timeTreeSuggestionErrorMessage = nil
                isLoadingTimeTreeSuggestions = false
                selectedTimeTreeEventURL = nil
            }
            return
        }

        await MainActor.run {
            isLoadingTimeTreeSuggestions = true
            timeTreeSuggestionErrorMessage = nil
            selectedTimeTreeEventURL = nil
        }

        do {
            let suggestions = try await TimeTreePublicCalendarClient.fetchSuggestions(aliasCode: aliasCode, date: date)
            await MainActor.run {
                timeTreeSuggestions = suggestions
                isLoadingTimeTreeSuggestions = false
            }
        } catch {
            await MainActor.run {
                timeTreeSuggestions = []
                timeTreeSuggestionErrorMessage = "候補を取得できませんでした"
                isLoadingTimeTreeSuggestions = false
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("日付") {
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }

                // --- 1. 出演グループ選択（グループ名で重複なし表示） ---
                Section(header: Text("出演グループ（複数選択可）")) {
                    if myOshis.isEmpty {
                        Text("推しが登録されていません").foregroundColor(.secondary)
                    } else {
                        let uniqueGroupNames = Array(Set(myOshis.compactMap { $0.group.isEmpty ? nil : $0.group })).sorted()
                        
                        // --- 既存のグループ名リスト ---
                        ForEach(uniqueGroupNames, id: \.self) { gName in
                            let isSelected = selectedGroupNames.contains(gName)

                            LiveGroupSelectionRow(
                                groupName: gName,
                                isSelected: isSelected,
                                action: {
                                    withAnimation {
                                        if isSelected {
                                            selectedGroupNames.removeAll { $0 == gName }
                                        } else {
                                            selectedGroupNames.append(gName)
                                        }
                                    }
                                }
                            )
                        }
                        
                        // --- ★ 追加：「その他」の行 ---
                        HStack {
                            Text("その他")
                                .foregroundColor(isOtherGroupSelected ? .primary : .secondary)
                            Spacer()
                            Image(systemName: isOtherGroupSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isOtherGroupSelected ? .gray : .secondary.opacity(0.3))
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation {
                                isOtherGroupSelected.toggle()
                            }
                        }
                    }
                }

                Section("イベント名と会場") {
                    if let selectedTimeTreeSourceGroupName,
                       selectedTimeTreeAliasCode != nil,
                       shouldShowTimeTreeSuggestionsSection {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Text("TimeTree候補")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(selectedTimeTreeSourceGroupName)
                                    .font(.caption)
                                    .foregroundColor(.pink)
                            }
                            ForEach(timeTreeSuggestions) { suggestion in
                                Button {
                                    applyTimeTreeSuggestionAndLoadImage(suggestion)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(alignment: .top, spacing: 10) {
                                            Text(suggestion.displayTimeText)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .frame(width: 40, alignment: .leading)
                                            Text(suggestion.title)
                                                .font(.subheadline)
                                                .foregroundColor(.primary)
                                                .multilineTextAlignment(.leading)
                                            Spacer()
                                        }
                                        if let venueName = resolvedVenueNameForAutoFill(from: suggestion) {
                                            Text(venueName)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .padding(.leading, 50)
                                        }
                                        Text("タップで入力")
                                            .font(.caption2)
                                            .foregroundColor(.pink)
                                            .padding(.leading, 50)
                                    }
                                    .padding(.vertical, 2)
                                }
                                .buttonStyle(.plain)
                            }

                            if let selectedTimeTreeEventURL {
                                HStack {
                                    Text("TimeTreeでイベントを開く")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                        .underline()
                                        .fixedSize()
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            openURL(selectedTimeTreeEventURL)
                                        }
                                    Spacer()
                                }
                            }

                        }
                        .padding(.top, 4)
                    }

                    TextField("イベント名", text: $title)

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("会場名", text: $venue)

                        if !filteredVenueSuggestions.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(filteredVenueSuggestions) { info in
                                        Button(action: { venue = info.name }) {
                                            Text(info.name)
                                                .font(.caption)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color.pink.opacity(0.1))
                                                .cornerRadius(15)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // 3. ヘッダー画像
                Section("ヘッダー画像") {
                    if let data = imageData, let ui = UIImage(data: data) {
                        VStack(spacing: 12) {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .cornerRadius(10)
                                .allowsHitTesting(false)
                            
                            Button(role: .destructive) {
                                withAnimation { imageData = nil; selectedItem = nil }
                            } label: {
                                Label("この写真を削除", systemImage: "trash").font(.subheadline)
                            }
                            .buttonStyle(.borderless)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label(imageData == nil ? "写真を選択" : "写真を変更", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.borderless)

                    if editingLive == nil {
                        Text("後から変更出来ます")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("表示順") {
                    ForEach(sectionOrder, id: \.self) { key in
                        HStack(spacing: 12) {
                            Text(sectionTitle(for: key))

                            Spacer()

                            if let isVisible = sectionVisibilityBinding(for: key) {
                                Toggle("表示", isOn: isVisible)
                                    .labelsHidden()
                            }

                            Image(systemName: "line.3.horizontal")
                                .foregroundColor(.secondary)
                        }
                    }
                    .onMove(perform: moveSections)
                }
                .environment(\.editMode, .constant(.active))

                // 4. 写真
                Section("写真 (\(galleryPhotos.count))") {

                    PhotosPicker(selection: $selectedGalleryItems, matching: .images) {
                        Label("写真を追加", systemImage: "photo.badge.plus")
                    }
                    .buttonStyle(.borderless)

                    if editingLive == nil {
                        Text("後から追加出来ます")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if !galleryPhotos.isEmpty {
                        let galleryPhotoIndices = Array(galleryPhotos.indices)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(galleryPhotoIndices, id: \.self) { index in
                                    EditableLivePhotoThumbnail(
                                        photo: galleryPhotos[index],
                                        onDelete: { removeGalleryPhoto(at: index) }
                                    )
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    if !galleryPhotos.isEmpty {
                        Button(role: .destructive) {
                            showingDeleteAllPhotosAlert = true
                        } label: {
                            Label("全削除", systemImage: "trash")
                                .font(.subheadline)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                // 5. 動画
                Section("撮可 (\(videoRecords.count))") {
                        PhotosPicker(selection: $selectedVideoItem, matching: .videos, photoLibrary: .shared()) {
                            Label("動画を追加", systemImage: "video.badge.plus")
                        }
                        .buttonStyle(.borderless)

                        if editingLive == nil {
                            Text("後から追加出来ます")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if !videoRecords.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(videoRecords) { record in
                                        EditableLiveVideoThumbnail(
                                            record: record,
                                            onDelete: {
                                                removeVideoRecord(record)
                                            }
                                        )
                                    }
                                }
                                .padding(.vertical, 4)
                            }

                            Button(role: .destructive) {
                                showingDeleteAllVideosAlert = true
                            } label: {
                                Label("全削除", systemImage: "trash")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.borderless)
                        }
                }

                // 6. メモ
                Section("メモ（感想・セトリなど）") {
                    TextEditor(text: $memo)
                        .frame(height: 150)
                }
            }
            .navigationTitle(editingLive == nil ? "ライブを追加" : "ライブを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let newLive = buildLiveRecord()
                        
                        if let index = myLives.firstIndex(where: { $0.id == newLive.id }) {
                            myLives[index] = newLive
                        } else {
                            myLives.append(newLive)
                        }
                        save()
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
            .onChange(of: selectedItem) { oldValue, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self),
                       let resizedData = ImageResizer.resizedJPEGData(
                        from: data,
                        maxLongEdge: 1400,
                        compressionQuality: 0.82
                       ) {
                        await MainActor.run { self.imageData = resizedData }
                    }
                }
            }
            .onChange(of: selectedGalleryItems) { _, newItems in
                Task {
                    var appendedPhotos: [LivePhotoItem] = []
                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let resizedData = ImageResizer.resizedJPEGData(
                            from: data,
                            maxLongEdge: 1400,
                            compressionQuality: 0.82
                           ) {
                            appendedPhotos.append(LivePhotoItem(imageData: resizedData, date: Date()))
                        }
                    }

                    await MainActor.run {
                        galleryPhotos.insert(contentsOf: appendedPhotos, at: 0)
                        selectedGalleryItems = []
                    }
                }
            }
            .onChange(of: selectedVideoItem) { _, newValue in
                guard let newValue else { return }
                Task {
                    if let id = newValue.itemIdentifier {
                        await MainActor.run {
                            if !videoRecords.contains(where: { $0.videoID == id }) {
                                videoRecords.insert(VideoRecord(videoID: id, title: ""), at: 0)
                            }
                            selectedVideoItem = nil
                        }
                    } else {
                        await MainActor.run {
                            selectedVideoItem = nil
                        }
                    }
                }
            }
            .onAppear {
                fetchVenueList() // 起動時にGitHubから取得
                if let live = editingLive {
                    let references = resolvedLiveGroupReferences(for: live, myOshis: myOshis)
                    selectedGroupNames = references
                        .filter { !$0.isOther }
                        .map(\.groupName)
                    isOtherGroupSelected = references.contains(where: \.isOther)
                    date = live.date
                    title = live.title
                    venue = live.venue
                    memo = live.memo
                    imageData = live.imageData
                    isPhotoSectionVisible = live.isPhotoSectionVisible
                    isVideoSectionVisible = live.isVideoSectionVisible
                    isChekiSectionVisible = live.isChekiSectionVisible
                    isMemoSectionVisible = live.isMemoSectionVisible
                    sectionOrder = live.sectionOrder
                    galleryPhotos = live.galleryPhotos
                    videoRecords = live.videoRecords
                } else {
                    selectedGroupNames = []
                    isOtherGroupSelected = false
                }
            }
            .task(id: timeTreeLookupKey) {
                await loadTimeTreeSuggestionsIfNeeded()
            }
            .alert("写真をすべて削除しますか？", isPresented: $showingDeleteAllPhotosAlert) {
                Button("キャンセル", role: .cancel) { }
                Button("全削除", role: .destructive) {
                    withAnimation {
                        galleryPhotos = []
                        selectedGalleryItems = []
                    }
                }
            } message: {
                Text("追加した写真がすべて削除されます。元画像は削除されません。")
            }
            .alert("動画をすべて削除しますか？", isPresented: $showingDeleteAllVideosAlert) {
                Button("キャンセル", role: .cancel) { }
                Button("全削除", role: .destructive) {
                    videoRecords = []
                }
            } message: {
                Text("追加した動画がすべて削除されます。本体の動画は削除されません。")
            }
        }
    }
    
    // GitHubから会場リスト(JSON配列)を取得
    func fetchVenueList() {
        guard let url = URL(string: AppConfig.venueListURL) else { return }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                // [VenueInfo] 型としてデコードする
                let list = try JSONDecoder().decode([VenueInfo].self, from: data)
                await MainActor.run {
                    self.venueSuggestions = list
                }
            } catch {
                print("Venue fetch failed: \(error)")
            }
        }
    }
    
    func save() {
        LocalStorage.save(myLives, for: .lives)
    }
}

private struct EditableLiveVideoThumbnail: View {
    let record: VideoRecord
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VideoThumbnailView(videoID: record.videoID)

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.red)
                    .background(Circle().fill(.white))
            }
            .padding(4)
        }
    }
}

private struct LiveGroupSelectionRow: View {
    let groupName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Text(groupName)
                .foregroundColor(isSelected ? .primary : .secondary)
            Spacer()
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .gray : .secondary.opacity(0.3))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

struct SettingsView: View {
    @Binding var myOshis: [Oshi]
    @Binding var myLives: [LiveRecord]
    @Binding var myChekis: [Cheki]
    @Binding var profile: UserProfile
    
    // アラート管理用の状態
    @State private var showingFirstAlert = false
    @State private var showingFinalAlert = false
    
    var body: some View {
        List {
            // 1. データと会場リスト
            Section("データと会場リスト") {
                Link(destination: URL(string: AppConfig.venueListURL)!) {
                    Label("GitHubで会場リストを確認", systemImage: "map.fill")
                }
                .foregroundColor(.primary)
            }

            Section("フォント") {
                Picker("画面フォント", selection: $profile.preferredAppFont) {
                    ForEach(AppDisplayFontChoice.allCases) { fontChoice in
                        Text(fontChoice.title).tag(fontChoice)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("プレビュー")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    let previewNames = Array(myOshis.prefix(3).map(\.name))

                    HStack(spacing: 12) {
                        if previewNames.isEmpty {
                            Text("推しライファー！")
                                .font(AppTypography.roundedDisplayFont(for: profile.preferredAppFont, size: 24, weight: .black))
                        } else {
                            ForEach(previewNames, id: \.self) { name in
                                Text(name)
                                    .font(AppTypography.roundedDisplayFont(for: profile.preferredAppFont, size: 24, weight: .black))
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
            }
            
            // 2. アプリの誓い
            Section("アプリの誓い") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("1. 推しの幸せを第一に願う")
                    Text("2. 自分の生活も大切に、無理なく楽しく")
                    Text("3. 現場での出会いと感謝を忘れない")
                }
                .font(.subheadline)
                .padding(.vertical, 5)
            }
            
            // ★ 3. データの全削除（追加）
            Section {
                Button(role: .destructive) {
                    showingFirstAlert = true
                } label: {
                    Label("すべてのデータを削除", systemImage: "trash.fill")
                }
            } header: {
                Text("危険な操作")
            } footer: {
                Text("保存されている推し、参戦記録、チェキをすべて消去し、アプリを初期状態に戻します。この操作は取り消せません。")
            }
            
            // 4. クレジット ＆ バージョン
            Section {
                VStack(spacing: 12) {
                    HStack(spacing: 15) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.pink)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Soraize")
                                .font(.headline)
                            Text("推しを愛する開発者")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    Divider()
                    HStack {
                        Text("バージョン")
                            .font(.caption)
                        Spacer()
                        Text("1.1.0") // 動画機能追加につきVer 1.1へ
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text("ABOUT")
            } footer: {
                Text("© 2026 Soraize. All rights reserved.")
                    .font(.system(size: 10))
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("設定")
                    .font(AppTypography.navigationTitleFont(for: profile.preferredAppFont, size: 18))
                    .tracking(-0.5)
            }
        }
        
        // --- 削除確認アラート：1回目 ---
        .alert("データをすべて削除しますか？", isPresented: $showingFirstAlert) {
            Button("次へ", role: .destructive) {
                // 1.5秒後に2回目を出して、うっかり連打を防ぐ
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showingFinalAlert = true
                }
            }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("すべての推し情報、参戦記録、チェキが消去されます。")
        }
        
        // --- 削除確認アラート：最終確認 ---
        .alert("本当に最後の手続きです", isPresented: $showingFinalAlert) {
            Button("すべて削除する", role: .destructive) {
                executeAllDelete()
            }
            Button("やっぱりやめる", role: .cancel) { }
        } message: {
            Text("この操作を実行すると、二度とデータを復元することはできません。よろしいですか？")
        }
    }
    
    // 全削除の実行関数
    private func executeAllDelete() {
        // 1. 保存ファイルと旧UserDefaultsデータを削除
        LocalStorage.delete(.oshis)
        LocalStorage.delete(.lives)
        LocalStorage.delete(.chekis)
        LocalStorage.delete(.graduatedOshis)
        LocalStorage.delete(.profile)
        LocalStorage.delete(.chekiSaveSettings)
        LocalStorage.delete(.chekiWatermarkText)
        
        // 2. メモリ上のデータを空にする
        withAnimation(.easeInOut) {
            myOshis = []
            myLives = []
            myChekis = []
        }
    }
}

struct ProfileView: View {
    let profile: UserProfile
    let myOshis: [Oshi]

    private var favoriteOshi: Oshi? {
        myOshis.first
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    if let data = profile.iconImageData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 88, height: 88)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 88, height: 88)
                            .foregroundColor(.secondary)
                    }

                    VStack(spacing: 6) {
                        Text(profile.displayName.isEmpty ? "名前はまだ未設定" : profile.displayName)
                            .font(AppTypography.roundedDisplayFont(for: profile.preferredAppFont, size: 20, weight: .bold))

                        Text(profile.message.isEmpty ? "プロフィールメッセージはまだ未設定です" : profile.message)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section("推し情報プレビュー") {
                if let favoriteOshi {
                    HStack(spacing: 12) {
                        OshiImage(oshi: favoriteOshi, size: 50)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(favoriteOshi.name).bold()
                            Text(favoriteOshi.group)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text("推しを登録すると、ここに名刺交換向けの情報を載せられます。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("自分のプロフィール")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NameCardTabView: View {
    @Binding var profile: UserProfile
    let myOshis: [Oshi]

    private var favoriteOshi: Oshi? {
        myOshis.first
    }

    private var nameCardAccentColor: Color {
        guard let favoriteColor = favoriteOshi?.color else { return .pink }
        return favoriteColor
    }

    private var nameCardAccentTextColor: Color {
        ColorUtils.isLightColor(nameCardAccentColor) ? .black : .white
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 16) {
                    if let data = profile.iconImageData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 96, height: 96)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 1))
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                            .foregroundColor(.secondary)
                    }

                    VStack(spacing: 8) {
                        Text(profile.displayName.isEmpty ? "名前はまだ未設定" : profile.displayName)
                            .font(AppTypography.roundedDisplayFont(for: profile.preferredAppFont, size: 28, weight: .black))
                            .multilineTextAlignment(.center)

                        Text(profile.message.isEmpty ? "自分だけの名刺を少しずつ整えていこう" : profile.message)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                    }

                    if let favoriteOshi {
                        HStack(spacing: 12) {
                            OshiImage(oshi: favoriteOshi, size: 54)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("最推し")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(favoriteOshi.name)
                                    .font(.headline)
                                Text(favoriteOshi.group)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    } else {
                        Text("推しを登録すると、名刺にもあなたらしさが増えていきます。")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 28)
                        .fill(Color(.systemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.04), radius: 16, y: 8)

                NavigationLink {
                    EditProfileView(profile: $profile)
                } label: {
                    Label("名刺を編集", systemImage: "square.and.pencil")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(nameCardAccentColor)
                .foregroundStyle(nameCardAccentTextColor)

                VStack(spacing: 8) {
                    Label("名刺交換機能は準備中", systemImage: "qrcode")
                        .foregroundColor(.secondary)
                    Text("今は自分の名刺を整えるための場所です。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .navigationTitle("名刺")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ToolsHomeView: View {
    @Binding var profile: UserProfile
    @Binding var myOshis: [Oshi]
    @Binding var myLives: [LiveRecord]
    @Binding var myChekis: [Cheki]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                NavigationLink {
                    NameCardTabView(profile: $profile, myOshis: myOshis)
                } label: {
                    ToolMenuCard(
                        title: "名刺",
                        subtitle: "プロフィールや最推しをまとめた、自分用の名刺を整える",
                        symbol: "person.text.rectangle",
                        accent: myOshis.first?.color ?? .pink,
                        fontChoice: profile.preferredAppFont
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ToolPlaceholderView(
                        title: "うちわ",
                        subtitle: "現場で使えるうちわデザインはこれから追加予定です。",
                        symbol: nil,
                        fontChoice: profile.preferredAppFont
                    )
                } label: {
                    ToolMenuCard(
                        title: "うちわ",
                        subtitle: "推しカラーや文字を使った、うちわ向けツール",
                        symbol: nil,
                        accent: .orange,
                        fontChoice: profile.preferredAppFont,
                        statusText: "準備中"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    PenlightToolView(fontChoice: profile.preferredAppFont)
                } label: {
                    ToolMenuCard(
                        title: "キンブレシート",
                        subtitle: "テンプレに2つの文字を入れて、キンブレシートを保存する",
                        symbol: "flashlight.on.fill",
                        accent: .blue,
                        fontChoice: profile.preferredAppFont
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    SettingsView(
                        myOshis: $myOshis,
                        myLives: $myLives,
                        myChekis: $myChekis,
                        profile: $profile
                    )
                } label: {
                    ToolMenuCard(
                        title: "設定",
                        subtitle: "フォントやデータ管理など、アプリ全体の設定を整える",
                        symbol: "gearshape",
                        accent: .gray,
                        fontChoice: profile.preferredAppFont
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("ツール")
                    .font(AppTypography.navigationTitleFont(for: profile.preferredAppFont, size: 18))
                    .tracking(-0.5)
            }
        }
    }
}

private struct PenlightSizePreset: Identifiable, Hashable {
    let id: String
    let displayTitle: String
    let widthMM: Double
    let heightMM: Double

    var title: String {
        displayTitle
    }
}

private enum PenlightSheetLayoutMetrics {
    static let previewCanvasHeight: CGFloat = 420
    static let slotCanvasHeight: CGFloat = 150
    static let referenceTextSize: CGFloat = 28
    static let referenceCharacterSpacing: CGFloat = -20
}

private enum PenlightTemplateLayoutKind: String, Codable {
    case single
    case double
}

private struct PenlightTemplateManifestEntry: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let layoutKind: PenlightTemplateLayoutKind
    let baseImageName: String?
    let baseImageURL: String?
    let group: String?
}

private enum PenlightTemplateManifest {
    private static let fallbackEntries: [PenlightTemplateManifestEntry] = [
        .init(id: "customImage", title: "自分の画像", subtitle: "自作テンプレ画像を使う", layoutKind: .double, baseImageName: nil, baseImageURL: nil, group: "custom"),
        .init(id: "sparkleBerry", title: "きらきらベリー", subtitle: "星とハートの軽めライン", layoutKind: .double, baseImageName: nil, baseImageURL: nil, group: "double"),
        .init(id: "spaceStar", title: "スペーススター", subtitle: "星と土星のポップライン", layoutKind: .double, baseImageName: nil, baseImageURL: "images/spaceStar.jpg", group: "double"),
        .init(id: "dottedLovely", title: "ドットラブリー", subtitle: "ドット多めの甘めライン", layoutKind: .double, baseImageName: nil, baseImageURL: nil, group: "double"),
        .init(id: "singleLovely", title: "シングルラブリー", subtitle: "1行用の両脇ライン", layoutKind: .single, baseImageName: nil, baseImageURL: nil, group: "single")
    ]

    private static let pinnedTemplateIDs: [String] = [
        "sparkleBerry",
        "spaceStar",
        "singleLovely"
    ]

    static func loadRemoteEntries() async -> [PenlightTemplateManifestEntry]? {
        guard
            let url = URL(string: AppConfig.penlightSheetManifestURL)
        else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard
                let httpResponse = response as? HTTPURLResponse,
                (200...299).contains(httpResponse.statusCode)
            else {
                return nil
            }

            let decoded = try JSONDecoder().decode([PenlightTemplateManifestEntry].self, from: data)
            return decoded.isEmpty ? nil : decoded
        } catch {
            return nil
        }
    }

    static func starterEntries() -> [PenlightTemplateManifestEntry] {
        return pinnedTemplateIDs.compactMap { id in
            fallbackEntries.first(where: { $0.id == id })
        }
    }

    static func bundledImageURL(for rawString: String?) -> URL? {
        guard
            let rawString,
            !rawString.isEmpty,
            !rawString.hasPrefix("http://"),
            !rawString.hasPrefix("https://")
        else {
            return nil
        }

        let path = rawString as NSString
        let fileName = path.lastPathComponent
        let resourceName = (fileName as NSString).deletingPathExtension
        let fileExtension = (fileName as NSString).pathExtension
        let parentDirectory = path.deletingLastPathComponent
        let subdirectory = ["Data/penlightsheet", parentDirectory]
            .filter { !$0.isEmpty }
            .joined(separator: "/")

        return Bundle.main.url(
            forResource: resourceName,
            withExtension: fileExtension.isEmpty ? nil : fileExtension,
            subdirectory: subdirectory
        ) ?? Bundle.main.url(
            forResource: resourceName,
            withExtension: fileExtension.isEmpty ? nil : fileExtension
        )
    }

    static func mergedEntries(remoteEntries: [PenlightTemplateManifestEntry]) -> [PenlightTemplateManifestEntry] {
        let starters = starterEntries()
        let starterIDs = Set(starters.map(\.id))
        let appended = remoteEntries.filter { entry in
            entry.id != "ribbonHeart" && !starterIDs.contains(entry.id)
        }
        return starters + appended
    }

    static func resolvedRemoteURLString(for rawString: String?) -> String? {
        guard let rawString, !rawString.isEmpty else { return nil }

        if rawString.hasPrefix("http://") || rawString.hasPrefix("https://") {
            return rawString
        }

        guard
            let manifestURL = URL(string: AppConfig.penlightSheetManifestURL)
        else {
            return nil
        }

        return URL(string: rawString, relativeTo: manifestURL.deletingLastPathComponent())?.absoluteURL.absoluteString
    }

    static func entry(for template: PenlightTemplateStyle) -> PenlightTemplateManifestEntry {
        starterEntries().first(where: { $0.id == template.rawValue })
        ?? fallbackEntries.first(where: { $0.id == template.rawValue })
        ?? fallbackEntries[0]
    }
}

private enum PenlightTemplateStyle: String, CaseIterable, Identifiable, Codable {
    case customImage
    case ribbonHeart
    case sparkleBerry
    case spaceStar
    case dottedLovely
    case singleLovely

    var id: String { rawValue }

    var title: String {
        PenlightTemplateManifest.entry(for: self).title
    }

    var subtitle: String {
        PenlightTemplateManifest.entry(for: self).subtitle
    }

    var defaultPrimaryPosition: CGPoint {
        switch layoutKind {
        case .single:
            return CGPoint(x: 0.50, y: 0.54)
        case .double:
            return CGPoint(x: 0.70, y: 0.54)
        }
    }

    var defaultSecondaryPosition: CGPoint {
        switch layoutKind {
        case .single:
            return CGPoint(x: 0.70, y: 0.54)
        case .double:
            return CGPoint(x: 0.30, y: 0.54)
        }
    }

    var layoutKind: PenlightTemplateLayoutKind {
        PenlightTemplateManifest.entry(for: self).layoutKind
    }
}

private struct PenlightRelativePoint: Codable, Equatable {
    var x: Double
    var y: Double

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }

    static func from(_ point: CGPoint) -> PenlightRelativePoint {
        PenlightRelativePoint(x: point.x, y: point.y)
    }
}

private struct PenlightSheetDraft: Identifiable, Codable, Equatable {
    static let defaultTextSize: Double = 28
    static let defaultOutlineEnabled = true
    static let defaultWhiteOutlineSize: Double = 4.0
    static let defaultBlackOutlineSize: Double = 1.0

    var id: UUID
    var slotIndex: Int
    var template: PenlightTemplateStyle
    var widthMM: Double
    var heightMM: Double
    var primaryTextSize: Double
    var secondaryTextSize: Double
    var isOutlineEnabled: Bool
    var whiteOutlineSize: Double
    var blackOutlineSize: Double
    var customTemplateImageData: Data?
    var customTemplateThumbnailData: Data?
    var showsSecondaryText: Bool
    var primaryText: String
    var secondaryText: String
    var primaryPosition: PenlightRelativePoint
    var secondaryPosition: PenlightRelativePoint
    var singlePrimaryPosition: PenlightRelativePoint
    var doublePrimaryPosition: PenlightRelativePoint
    var doubleSecondaryPosition: PenlightRelativePoint
    var updatedAt: Date

    var isConfigured: Bool {
        !primaryText.isEmpty || (showsSecondaryText && !secondaryText.isEmpty)
    }

    var slotTitle: String {
        "シート\(slotIndex + 1)"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case slotIndex
        case template
        case widthMM
        case heightMM
        case textSize
        case primaryTextSize
        case secondaryTextSize
        case isOutlineEnabled
        case whiteOutlineSize
        case blackOutlineSize
        case customTemplateImageData
        case customTemplateThumbnailData
        case showsSecondaryText
        case primaryText
        case secondaryText
        case primaryPosition
        case secondaryPosition
        case singlePrimaryPosition
        case doublePrimaryPosition
        case doubleSecondaryPosition
        case updatedAt
    }

    init(
        id: UUID,
        slotIndex: Int,
        template: PenlightTemplateStyle,
        widthMM: Double,
        heightMM: Double,
        primaryTextSize: Double,
        secondaryTextSize: Double,
        isOutlineEnabled: Bool,
        whiteOutlineSize: Double,
        blackOutlineSize: Double,
        customTemplateImageData: Data?,
        customTemplateThumbnailData: Data?,
        showsSecondaryText: Bool,
        primaryText: String,
        secondaryText: String,
        primaryPosition: PenlightRelativePoint,
        secondaryPosition: PenlightRelativePoint,
        singlePrimaryPosition: PenlightRelativePoint,
        doublePrimaryPosition: PenlightRelativePoint,
        doubleSecondaryPosition: PenlightRelativePoint,
        updatedAt: Date
    ) {
        self.id = id
        self.slotIndex = slotIndex
        self.template = template
        self.widthMM = widthMM
        self.heightMM = heightMM
        self.primaryTextSize = primaryTextSize
        self.secondaryTextSize = secondaryTextSize
        self.isOutlineEnabled = isOutlineEnabled
        self.whiteOutlineSize = whiteOutlineSize
        self.blackOutlineSize = blackOutlineSize
        self.customTemplateImageData = customTemplateImageData
        self.customTemplateThumbnailData = customTemplateThumbnailData
        self.showsSecondaryText = showsSecondaryText
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.primaryPosition = primaryPosition
        self.secondaryPosition = secondaryPosition
        self.singlePrimaryPosition = singlePrimaryPosition
        self.doublePrimaryPosition = doublePrimaryPosition
        self.doubleSecondaryPosition = doubleSecondaryPosition
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        slotIndex = try container.decode(Int.self, forKey: .slotIndex)
        template = try container.decode(PenlightTemplateStyle.self, forKey: .template)
        widthMM = try container.decode(Double.self, forKey: .widthMM)
        heightMM = try container.decode(Double.self, forKey: .heightMM)
        let legacyTextSize = try container.decodeIfPresent(Double.self, forKey: .textSize) ?? Self.defaultTextSize
        primaryTextSize = try container.decodeIfPresent(Double.self, forKey: .primaryTextSize) ?? legacyTextSize
        secondaryTextSize = try container.decodeIfPresent(Double.self, forKey: .secondaryTextSize) ?? legacyTextSize
        isOutlineEnabled = try container.decodeIfPresent(Bool.self, forKey: .isOutlineEnabled) ?? Self.defaultOutlineEnabled
        whiteOutlineSize = try container.decodeIfPresent(Double.self, forKey: .whiteOutlineSize) ?? Self.defaultWhiteOutlineSize
        blackOutlineSize = try container.decodeIfPresent(Double.self, forKey: .blackOutlineSize) ?? Self.defaultBlackOutlineSize
        customTemplateImageData = try container.decodeIfPresent(Data.self, forKey: .customTemplateImageData)
        customTemplateThumbnailData = try container.decodeIfPresent(Data.self, forKey: .customTemplateThumbnailData)
        showsSecondaryText = try container.decodeIfPresent(Bool.self, forKey: .showsSecondaryText) ?? (template.layoutKind == .double)
        primaryText = try container.decode(String.self, forKey: .primaryText)
        secondaryText = try container.decode(String.self, forKey: .secondaryText)
        primaryPosition = try container.decode(PenlightRelativePoint.self, forKey: .primaryPosition)
        secondaryPosition = try container.decode(PenlightRelativePoint.self, forKey: .secondaryPosition)
        singlePrimaryPosition =
            try container.decodeIfPresent(PenlightRelativePoint.self, forKey: .singlePrimaryPosition)
            ?? .from(PenlightTemplateStyle.singleLovely.defaultPrimaryPosition)
        let defaultDoublePrimary = PenlightRelativePoint.from(PenlightTemplateStyle.sparkleBerry.defaultPrimaryPosition)
        let defaultDoubleSecondary = PenlightRelativePoint.from(PenlightTemplateStyle.sparkleBerry.defaultSecondaryPosition)
        doublePrimaryPosition =
            try container.decodeIfPresent(PenlightRelativePoint.self, forKey: .doublePrimaryPosition)
            ?? (template.layoutKind == .double ? primaryPosition : defaultDoublePrimary)
        doubleSecondaryPosition =
            try container.decodeIfPresent(PenlightRelativePoint.self, forKey: .doubleSecondaryPosition)
            ?? (template.layoutKind == .double ? secondaryPosition : defaultDoubleSecondary)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)

        if template.layoutKind == .single {
            if (try? container.decodeIfPresent(PenlightRelativePoint.self, forKey: .singlePrimaryPosition)) == nil {
                singlePrimaryPosition = primaryPosition
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(slotIndex, forKey: .slotIndex)
        try container.encode(template, forKey: .template)
        try container.encode(widthMM, forKey: .widthMM)
        try container.encode(heightMM, forKey: .heightMM)
        try container.encode(primaryTextSize, forKey: .primaryTextSize)
        try container.encode(secondaryTextSize, forKey: .secondaryTextSize)
        try container.encode(isOutlineEnabled, forKey: .isOutlineEnabled)
        try container.encode(whiteOutlineSize, forKey: .whiteOutlineSize)
        try container.encode(blackOutlineSize, forKey: .blackOutlineSize)
        try container.encodeIfPresent(customTemplateImageData, forKey: .customTemplateImageData)
        try container.encodeIfPresent(customTemplateThumbnailData, forKey: .customTemplateThumbnailData)
        try container.encode(showsSecondaryText, forKey: .showsSecondaryText)
        try container.encode(primaryText, forKey: .primaryText)
        try container.encode(secondaryText, forKey: .secondaryText)
        try container.encode(primaryPosition, forKey: .primaryPosition)
        try container.encode(secondaryPosition, forKey: .secondaryPosition)
        try container.encode(singlePrimaryPosition, forKey: .singlePrimaryPosition)
        try container.encode(doublePrimaryPosition, forKey: .doublePrimaryPosition)
        try container.encode(doubleSecondaryPosition, forKey: .doubleSecondaryPosition)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    static func empty(slotIndex: Int) -> PenlightSheetDraft {
        let template: PenlightTemplateStyle = .sparkleBerry
        return PenlightSheetDraft(
            id: UUID(),
            slotIndex: slotIndex,
            template: template,
            widthMM: 88,
            heightMM: 143,
            primaryTextSize: Self.defaultTextSize,
            secondaryTextSize: Self.defaultTextSize,
            isOutlineEnabled: Self.defaultOutlineEnabled,
            whiteOutlineSize: Self.defaultWhiteOutlineSize,
            blackOutlineSize: Self.defaultBlackOutlineSize,
            customTemplateImageData: nil,
            customTemplateThumbnailData: nil,
            showsSecondaryText: true,
            primaryText: "",
            secondaryText: "",
            primaryPosition: .from(template.defaultPrimaryPosition),
            secondaryPosition: .from(template.defaultSecondaryPosition),
            singlePrimaryPosition: .from(PenlightTemplateStyle.singleLovely.defaultPrimaryPosition),
            doublePrimaryPosition: .from(template.defaultPrimaryPosition),
            doubleSecondaryPosition: .from(template.defaultSecondaryPosition),
            updatedAt: Date()
        )
    }
}

private final class PenlightTemplateImageCache {
    static let shared = PenlightTemplateImageCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 24
        cache.totalCostLimit = 36 * 1024 * 1024
    }

    func cachedImage(for urlString: String) -> UIImage? {
        cache.object(forKey: urlString as NSString)
    }

    func loadImage(urlString: String) async -> UIImage? {
        if let cached = cachedImage(for: urlString) {
            return cached
        }

        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard
                let httpResponse = response as? HTTPURLResponse,
                (200...299).contains(httpResponse.statusCode),
                let image = UIImage(data: data)
            else {
                return nil
            }

            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
            cache.setObject(image, forKey: urlString as NSString, cost: cost)
            return image
        } catch {
            return nil
        }
    }
}

private struct PenlightToolView: View {
    let fontChoice: AppDisplayFontChoice

    @State private var drafts: [PenlightSheetDraft] = []
    @State private var templateEntries: [PenlightTemplateManifestEntry] = PenlightTemplateManifest.starterEntries()
    @State private var autosaveTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("3つまで保存して、あとから編集できます。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                ForEach(Array(drafts.enumerated()), id: \.element.id) { index, draft in
                    NavigationLink {
                        PenlightSheetEditorView(
                            fontChoice: fontChoice,
                            templateEntries: templateEntries,
                            draft: $drafts[index]
                        )
                    } label: {
                        PenlightSheetSlotCard(
                            draft: draft,
                            fontChoice: fontChoice,
                            templateEntry: manifestEntry(for: draft.template)
                        )
                    }
                    .buttonStyle(.plain)
                }

                NavigationLink {
                    PenlightSheetHowToView(fontChoice: fontChoice)
                } label: {
                    PenlightSheetHowToCard(fontChoice: fontChoice)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 28)
        }
        .navigationTitle("キンブレシート")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if drafts.isEmpty {
                let loadedDrafts = LocalStorage.load([PenlightSheetDraft].self, for: .penlightSheets) ?? []
                drafts = (0..<3).map { index in
                    if index < loadedDrafts.count {
                        var draft = loadedDrafts[index]
                        draft.slotIndex = index
                        return draft
                    }
                    return PenlightSheetDraft.empty(slotIndex: index)
                }
            }
        }
        .onChange(of: drafts) { _, newValue in
            autosaveTask?.cancel()
            autosaveTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    LocalStorage.save(newValue, for: .penlightSheets)
                }
            }
        }
        .onDisappear {
            autosaveTask?.cancel()
            LocalStorage.save(drafts, for: .penlightSheets)
        }
        .task {
            if let remoteEntries = await PenlightTemplateManifest.loadRemoteEntries() {
                templateEntries = PenlightTemplateManifest.mergedEntries(remoteEntries: remoteEntries)
            } else {
                templateEntries = PenlightTemplateManifest.starterEntries()
            }
        }
    }

    private func manifestEntry(for template: PenlightTemplateStyle) -> PenlightTemplateManifestEntry {
        templateEntries.first(where: { $0.id == template.rawValue })
        ?? PenlightTemplateManifest.entry(for: template)
    }
}

private struct PenlightSheetHowToCard: View {
    let fontChoice: AppDisplayFontChoice

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.12))

                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.orange)
            }
            .frame(width: 72, height: 150)

            VStack(alignment: .leading, spacing: 6) {
                Text("作り方")
                    .font(AppTypography.roundedDisplayFont(for: fontChoice, size: 20, weight: .bold))
                    .foregroundColor(.primary)

                Text("初めて作る時の流れや、印刷時のコツを確認できます")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.secondary.opacity(0.8))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 14, y: 6)
        .padding(.horizontal, 20)
    }
}

private struct PenlightSheetSlotCard: View {
    let draft: PenlightSheetDraft
    let fontChoice: AppDisplayFontChoice
    let templateEntry: PenlightTemplateManifestEntry

    private var slotScale: CGFloat {
        PenlightSheetLayoutMetrics.slotCanvasHeight / max(PenlightSheetLayoutMetrics.previewCanvasHeight, 1)
    }

    private var customBackgroundImage: UIImage? {
        guard draft.template == .customImage,
              let data = draft.customTemplateThumbnailData ?? draft.customTemplateImageData else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        HStack(spacing: 14) {
            PenlightStickerCanvasView(
                template: draft.template,
                templateEntry: templateEntry,
                primaryText: draft.primaryText.isEmpty ? "文字1" : draft.primaryText,
                secondaryText: draft.secondaryText.isEmpty ? "文字2" : draft.secondaryText,
                showsSecondaryText: draft.showsSecondaryText,
                primaryTextSize: CGFloat(draft.primaryTextSize) * slotScale,
                secondaryTextSize: CGFloat(draft.secondaryTextSize) * slotScale,
                isOutlineEnabled: draft.isOutlineEnabled,
                whiteOutlineSize: CGFloat(draft.whiteOutlineSize) * slotScale,
                blackOutlineSize: CGFloat(draft.blackOutlineSize) * slotScale,
                primaryPosition: .constant(draft.primaryPosition.cgPoint),
                secondaryPosition: .constant(draft.secondaryPosition.cgPoint),
                isInteractive: false,
                canvasStyle: .cardPreview,
                providedBackgroundImage: customBackgroundImage
            )
            .frame(width: 72, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 6) {
                Text(draft.slotTitle)
                    .font(AppTypography.roundedDisplayFont(for: fontChoice, size: 20, weight: .bold))
                    .foregroundColor(.primary)

                Text(templateEntry.title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if draft.isConfigured {
                    Text(slotSummaryText)
                        .font(.footnote)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                } else {
                    Text("未作成")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                }

                Text("\(Int(draft.widthMM)) × \(Int(draft.heightMM)) mm")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.secondary.opacity(0.8))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 14, y: 6)
        .padding(.horizontal, 20)
    }

    private var slotSummaryText: String {
        if !draft.showsSecondaryText {
            return draft.primaryText
        }
        return [draft.primaryText, draft.secondaryText].filter { !$0.isEmpty }.joined(separator: " / ")
    }
}

private struct PenlightSheetHowToView: View {
    let fontChoice: AppDisplayFontChoice

    private var titleFont: Font {
        AppTypography.roundedDisplayFont(for: fontChoice, size: 24, weight: .bold)
    }

    private var subtitleFont: Font {
        AppTypography.roundedDisplayFont(for: fontChoice, size: 18, weight: .semibold)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Group {
                    Text("作り方")
                        .font(titleFont)
                        .foregroundColor(.primary)

                    Text("テンプレや自分の画像を使って、文字を入れて、印刷用のシート画像を保存する流れです。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)

                howToSection(
                    title: "基本の流れ",
                    lines: [
                        "1. 発光部サイズを選ぶ",
                        "2. 背景から使いたいテンプレ、または自分の画像を選ぶ",
                        "3. 文字枠1と必要なら文字枠2を入力する",
                        "4. 文字サイズと縁取りを調整する",
                        "5. 文字をドラッグして位置を合わせる",
                        "6. 保存して、印刷して試す"
                    ]
                )

                howToSection(
                    title: "印刷のコツ",
                    lines: [
                        "保存画像は原寸向けなので、印刷時は実際のサイズで印刷してください",
                        "用紙に合わせる、自動拡大縮小はオフがおすすめです",
                        "最初は普通紙で試して、サイズ感を見てから本番印刷すると安心です"
                    ]
                )

                howToSection(
                    title: "調整のポイント",
                    lines: [
                        "文字が太く見えすぎる時は白フチや黒フチを少し下げる",
                        "1行で使いたい時は文字枠2をオフにする",
                        "自分の画像は、左右を合わせたまま上下だけ調整されるように表示されます"
                    ]
                )
            }
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .navigationTitle("作り方")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func howToSection(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(subtitleFont)
                .foregroundColor(.primary)

            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.body)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 12, y: 5)
        .padding(.horizontal, 20)
    }
}

private struct PenlightSheetEditorView: View {
    let fontChoice: AppDisplayFontChoice
    let templateEntries: [PenlightTemplateManifestEntry]
    @Binding var draft: PenlightSheetDraft

    @State private var showSaveAlert = false
    @State private var saveAlertText = ""
    @State private var resolvedBackgroundImage: UIImage?
    @State private var decodedCustomBackgroundImage: UIImage?
    @State private var decodedCustomBackgroundThumbnailImage: UIImage?
    @State private var selectedTemplateImageItem: PhotosPickerItem?

    private let presets: [PenlightSizePreset] = [
        .init(id: "light150", displayTitle: "150", widthMM: 88, heightMM: 143),
        .init(id: "light120", displayTitle: "120", widthMM: 70, heightMM: 113),
        .init(id: "light100", displayTitle: "100", widthMM: 57, heightMM: 93)
    ]

    private let exportDPI: Double = 300

    private var sectionTitleFont: Font {
        AppTypography.roundedDisplayFont(for: fontChoice, size: 24, weight: .bold)
    }

    private var subsectionTitleFont: Font {
        AppTypography.roundedDisplayFont(for: fontChoice, size: 18, weight: .semibold)
    }

    var body: some View {
        editorScrollContent
            .navigationTitle(draft.slotTitle)
            .navigationBarTitleDisplayMode(.inline)
            .alert(saveAlertText, isPresented: $showSaveAlert) {
                Button("OK", role: .cancel) {}
            }
            .onAppear {
                applyNavigationTitleAppearance()
                if draft.primaryPosition == .from(.zero) || draft.secondaryPosition == .from(.zero) {
                    resetTextPositions(for: draft.template)
                }
                refreshCustomBackgroundImages()
            }
            .onDisappear {
                resetNavigationTitleAppearance()
            }
            .task(id: currentTemplateEntry.id + (currentTemplateEntry.baseImageURL ?? currentTemplateEntry.baseImageName ?? "")) {
                resolvedBackgroundImage = await loadBackgroundImage(for: currentTemplateEntry)
            }
            .onChange(of: draft.template) { _, _ in
                draft.updatedAt = Date()
            }
            .onChange(of: draft.widthMM) { _, _ in
                draft.updatedAt = Date()
            }
            .onChange(of: draft.heightMM) { _, _ in
                draft.updatedAt = Date()
            }
            .onChange(of: draft.primaryText) { _, _ in
                draft.updatedAt = Date()
            }
            .onChange(of: draft.secondaryText) { _, _ in
                draft.updatedAt = Date()
            }
            .onChange(of: draft.primaryTextSize) { _, _ in
                draft.updatedAt = Date()
            }
            .onChange(of: draft.secondaryTextSize) { _, _ in
                draft.updatedAt = Date()
            }
            .onChange(of: draft.isOutlineEnabled) { _, _ in
                draft.updatedAt = Date()
            }
            .onChange(of: draft.whiteOutlineSize) { _, _ in
                draft.updatedAt = Date()
            }
            .onChange(of: draft.blackOutlineSize) { _, _ in
                draft.updatedAt = Date()
            }
            .onChange(of: draft.showsSecondaryText) { _, _ in
                draft.updatedAt = Date()
            }
            .onChange(of: draft.customTemplateImageData) { _, _ in
                refreshCustomBackgroundImages()
            }
            .onChange(of: draft.customTemplateThumbnailData) { _, _ in
                refreshCustomBackgroundImages()
            }
            .onChange(of: selectedTemplateImageItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    defer {
                        Task { @MainActor in
                            selectedTemplateImageItem = nil
                        }
                    }

                    guard
                        let data = try? await newItem.loadTransferable(type: Data.self),
                        let resizedData = ImageResizer.resizedJPEGData(
                            from: data,
                            maxLongEdge: 1600,
                            compressionQuality: 0.84
                        ),
                        let thumbnailData = ImageResizer.resizedJPEGData(
                            from: data,
                            maxLongEdge: 320,
                            compressionQuality: 0.78
                        )
                    else {
                        return
                    }

                    await MainActor.run {
                        draft.template = .customImage
                        draft.customTemplateImageData = resizedData
                        draft.customTemplateThumbnailData = thumbnailData
                        decodedCustomBackgroundImage = UIImage(data: resizedData)
                        decodedCustomBackgroundThumbnailImage = UIImage(data: thumbnailData)
                        draft.updatedAt = Date()
                    }
                }
            }
    }

    private var editorScrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("ペンライト発光部サイズ")
                        .font(sectionTitleFont)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(presets) { preset in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        draft.widthMM = preset.widthMM
                                        draft.heightMM = preset.heightMM
                                    }
                                } label: {
                                    Text(preset.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(selectedPresetID == preset.id ? .white : .primary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(
                                            Capsule()
                                                .fill(selectedPresetID == preset.id ? Color.pink : Color(.secondarySystemBackground))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Stepper(value: $draft.widthMM, in: 60...140, step: 1) {
                        HStack {
                            Text("幅")
                            Spacer()
                            Text("\(Int(draft.widthMM)) mm")
                                .foregroundColor(.secondary)
                        }
                    }

                    Stepper(value: $draft.heightMM, in: 100...220, step: 1) {
                        HStack {
                            Text("高さ")
                            Spacer()
                            Text("\(Int(draft.heightMM)) mm")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 12) {
                    Text("文字")
                        .font(sectionTitleFont)

                    TextField("文字枠1", text: $draft.primaryText)
                        .textFieldStyle(.roundedBorder)

                    Toggle("文字枠2を表示", isOn: $draft.showsSecondaryText)
                        .font(.subheadline.weight(.semibold))

                    if draft.showsSecondaryText {
                        TextField("文字枠2", text: $draft.secondaryText)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 8) {
                    Text("プレビュー")
                        .font(sectionTitleFont)
                    Text("文字をドラッグして位置を調整してね")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)

                PenlightStickerCanvasView(
                    template: draft.template,
                    templateEntry: currentTemplateEntry,
                    primaryText: primaryPreviewText,
                    secondaryText: secondaryPreviewText,
                    showsSecondaryText: draft.showsSecondaryText,
                    primaryTextSize: CGFloat(draft.primaryTextSize),
                    secondaryTextSize: CGFloat(draft.secondaryTextSize),
                    isOutlineEnabled: draft.isOutlineEnabled,
                    whiteOutlineSize: CGFloat(draft.whiteOutlineSize),
                    blackOutlineSize: CGFloat(draft.blackOutlineSize),
                    primaryPosition: primaryPosition,
                    secondaryPosition: secondaryPosition,
                    isInteractive: true,
                    canvasStyle: .editorPreview,
                    providedBackgroundImage: effectiveBackgroundImage
                )
                .aspectRatio(CGFloat(draft.widthMM / max(draft.heightMM, 1)), contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(height: PenlightSheetLayoutMetrics.previewCanvasHeight)
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 12) {
                    textSizeRow(
                        title: draft.showsSecondaryText ? "文字1サイズ" : "文字サイズ",
                        value: $draft.primaryTextSize
                    )
                    if draft.showsSecondaryText {
                        textSizeRow(title: "文字2サイズ", value: $draft.secondaryTextSize)
                    }
                }
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 12) {
                    Toggle("縁取り", isOn: $draft.isOutlineEnabled)
                        .font(.subheadline.weight(.semibold))

                    if draft.isOutlineEnabled {
                        outlineSizeRow(
                            title: "白フチ",
                            value: $draft.whiteOutlineSize,
                            range: PenlightSheetDraft.defaultWhiteOutlineSize...6.0
                        )
                        outlineSizeRow(
                            title: "黒フチ",
                            value: $draft.blackOutlineSize,
                            range: PenlightSheetDraft.defaultBlackOutlineSize...6.0
                        )

                        HStack {
                            Spacer()
                            Button("規定に戻す") {
                                resetVisualAdjustments()
                            }
                            .font(.subheadline.weight(.semibold))
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 12) {
                    Text("背景")
                        .font(sectionTitleFont)

                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("自分の画像")
                                .font(subsectionTitleFont)
                                .foregroundColor(.secondary)

                            if draft.customTemplateThumbnailData == nil {
                                PhotosPicker(selection: $selectedTemplateImageItem, matching: .images) {
                                    templateSelectionCard(
                                        title: "画像を選ぶ",
                                        subtitle: "自作テンプレ画像を選べます。",
                                        preview: {
                                            PenlightBackgroundPreview(
                                                image: customBackgroundThumbnailImage,
                                                fallbackText: "画像"
                                            )
                                        },
                                        isSelected: false
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                        draft.template = .customImage
                                    }
                                } label: {
                                    templateSelectionCard(
                                        title: "選択した画像",
                                        subtitle: "選んだ画像をテンプレとして使います。",
                                        preview: {
                                            PenlightBackgroundPreview(
                                                image: customBackgroundThumbnailImage,
                                                fallbackText: "画像"
                                            )
                                        },
                                        isSelected: draft.template == .customImage,
                                        trailingAccessory: {
                                            PhotosPicker(selection: $selectedTemplateImageItem, matching: .images) {
                                                Label("画像を変更", systemImage: "photo.badge.plus")
                                                    .font(.caption.weight(.semibold))
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 6)
                                                    .background(
                                                        Capsule()
                                                            .fill(Color(.secondarySystemBackground))
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        ForEach(templateSections, id: \.title) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(section.title)
                                    .font(subsectionTitleFont)
                                    .foregroundColor(.secondary)

                                ForEach(section.templates) { template in
                                    Button {
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                            applyTemplateChange(to: template)
                                        }
                                    } label: {
                                        PenlightTemplateCard(
                                            template: template,
                                            templateEntry: manifestEntry(for: template),
                                            isSelected: template == draft.template
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                Button(action: savePenlightSheet) {
                    Label("画像を保存", systemImage: "square.and.arrow.down")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
        }
    }

    private var primaryPreviewText: String {
        draft.primaryText.isEmpty ? "文字枠1" : draft.primaryText
    }

    private var secondaryPreviewText: String {
        guard draft.showsSecondaryText else { return "" }
        return draft.secondaryText.isEmpty ? "文字枠2" : draft.secondaryText
    }

    private var primaryPosition: Binding<CGPoint> {
        Binding(
            get: { draft.primaryPosition.cgPoint },
            set: {
                draft.primaryPosition = .from($0)
                if draft.template.layoutKind == .single {
                    draft.singlePrimaryPosition = .from($0)
                } else {
                    draft.doublePrimaryPosition = .from($0)
                }
                draft.updatedAt = Date()
            }
        )
    }

    private var secondaryPosition: Binding<CGPoint> {
        Binding(
            get: { draft.secondaryPosition.cgPoint },
            set: {
                draft.secondaryPosition = .from($0)
                if draft.template.layoutKind == .double {
                    draft.doubleSecondaryPosition = .from($0)
                }
                draft.updatedAt = Date()
            }
        )
    }

    private var selectedPresetID: String {
        presets.first(where: { $0.widthMM == draft.widthMM && $0.heightMM == draft.heightMM })?.id ?? ""
    }

    private var templateSections: [(title: String, templates: [PenlightTemplateStyle])] {
        let orderedTemplates = templateEntries
            .compactMap { PenlightTemplateStyle(rawValue: $0.id) }
            .filter { $0 != .customImage }
        let groupedTemplates = Dictionary(grouping: orderedTemplates, by: \.layoutKind)
        return [
            ("テンプレ2行用", groupedTemplates[.double] ?? []),
            ("テンプレ1行用", groupedTemplates[.single] ?? [])
        ].filter { !$0.templates.isEmpty }
    }

    private var currentTemplateEntry: PenlightTemplateManifestEntry {
        manifestEntry(for: draft.template)
    }

    private var effectiveBackgroundImage: UIImage? {
        guard draft.template == .customImage else {
            return resolvedBackgroundImage
        }
        return decodedCustomBackgroundImage ?? resolvedBackgroundImage
    }

    private var customBackgroundThumbnailImage: UIImage? {
        decodedCustomBackgroundThumbnailImage
    }

    private func refreshCustomBackgroundImages() {
        if let data = draft.customTemplateImageData {
            decodedCustomBackgroundImage = UIImage(data: data)
        } else {
            decodedCustomBackgroundImage = nil
        }

        if let data = draft.customTemplateThumbnailData {
            decodedCustomBackgroundThumbnailImage = UIImage(data: data)
        } else {
            decodedCustomBackgroundThumbnailImage = nil
        }
    }

    private func resetTextPositions(for template: PenlightTemplateStyle) {
        switch template.layoutKind {
        case .single:
            let singlePosition = PenlightRelativePoint.from(template.defaultPrimaryPosition)
            draft.singlePrimaryPosition = singlePosition
            draft.primaryPosition = singlePosition
            draft.secondaryPosition = draft.doubleSecondaryPosition
        case .double:
            let primaryPosition = PenlightRelativePoint.from(template.defaultPrimaryPosition)
            let secondaryPosition = PenlightRelativePoint.from(template.defaultSecondaryPosition)
            draft.doublePrimaryPosition = primaryPosition
            draft.doubleSecondaryPosition = secondaryPosition
            draft.primaryPosition = primaryPosition
            draft.secondaryPosition = secondaryPosition
        }
        draft.updatedAt = Date()
    }

    private func applyTemplateChange(to newTemplate: PenlightTemplateStyle) {
        let previousLayout = draft.template.layoutKind
        let newLayout = newTemplate.layoutKind

        if previousLayout == .single {
            draft.singlePrimaryPosition = draft.primaryPosition
        } else {
            draft.doublePrimaryPosition = draft.primaryPosition
            draft.doubleSecondaryPosition = draft.secondaryPosition
        }

        draft.template = newTemplate

        if previousLayout != newLayout {
            switch newLayout {
            case .single:
                draft.primaryPosition = draft.singlePrimaryPosition
            case .double:
                draft.primaryPosition = draft.doublePrimaryPosition
                draft.secondaryPosition = draft.doubleSecondaryPosition
            }
        }

        draft.updatedAt = Date()
    }

    private func resetVisualAdjustments() {
        draft.isOutlineEnabled = PenlightSheetDraft.defaultOutlineEnabled
        draft.whiteOutlineSize = PenlightSheetDraft.defaultWhiteOutlineSize
        draft.blackOutlineSize = PenlightSheetDraft.defaultBlackOutlineSize
        draft.updatedAt = Date()
    }

    private func applyNavigationTitleAppearance() {
        let font = AppTypography.navigationTitleUIFont(for: fontChoice, size: 18)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.titleTextAttributes = [
            .font: font,
            .foregroundColor: UIColor.label
        ]
        appearance.largeTitleTextAttributes = [
            .font: font,
            .foregroundColor: UIColor.label
        ]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    private func resetNavigationTitleAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    private var exportPixelSize: CGSize {
        let pixelsPerMillimeter = exportDPI / 25.4
        return CGSize(
            width: max(1, (draft.widthMM * pixelsPerMillimeter).rounded()),
            height: max(1, (draft.heightMM * pixelsPerMillimeter).rounded())
        )
    }

    private func savePenlightSheet() {
        let pixelSize = exportPixelSize
        let exportScale = pixelSize.height / max(PenlightSheetLayoutMetrics.previewCanvasHeight, 1)
        let content = PenlightStickerCanvasView(
            template: draft.template,
            templateEntry: currentTemplateEntry,
            primaryText: primaryPreviewText,
            secondaryText: secondaryPreviewText,
            showsSecondaryText: draft.showsSecondaryText,
            primaryTextSize: CGFloat(draft.primaryTextSize) * exportScale,
            secondaryTextSize: CGFloat(draft.secondaryTextSize) * exportScale,
            isOutlineEnabled: draft.isOutlineEnabled,
            whiteOutlineSize: CGFloat(draft.whiteOutlineSize) * exportScale,
            blackOutlineSize: CGFloat(draft.blackOutlineSize) * exportScale,
            primaryPosition: .constant(draft.primaryPosition.cgPoint),
            secondaryPosition: .constant(draft.secondaryPosition.cgPoint),
            isInteractive: false,
            canvasStyle: .exportedImage,
            providedBackgroundImage: effectiveBackgroundImage
        )
        .frame(width: pixelSize.width, height: pixelSize.height)
        .background(Color.white)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 1

        guard
            let image = renderer.uiImage,
            let flattenedImage = flattenedOpaqueImage(from: image)
        else {
            saveAlertText = "画像の保存に失敗しました"
            showSaveAlert = true
            return
        }

        UIImageWriteToSavedPhotosAlbum(flattenedImage, nil, nil, nil)
        saveAlertText = "キンブレシートを保存しました"
        showSaveAlert = true
    }

    private func flattenedOpaqueImage(from image: UIImage) -> UIImage? {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: image.size))
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    @ViewBuilder
    private func outlineSizeRow(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 16) {
            Text(title)
            Spacer()
            Button {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - 0.2)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 22, weight: .bold))
            }
            .buttonStyle(.plain)

            Text(String(format: "%.1f", value.wrappedValue))
                .font(.body.monospacedDigit())
                .frame(minWidth: 34)

            Button {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + 0.2)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .bold))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func textSizeRow(title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button {
                value.wrappedValue = max(18, value.wrappedValue - 1)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 24, weight: .bold))
            }
            .buttonStyle(.plain)

            Text("\(Int(value.wrappedValue))")
                .font(.body.monospacedDigit())
                .frame(minWidth: 28)

            Button {
                value.wrappedValue = min(48, value.wrappedValue + 1)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24, weight: .bold))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func templateSelectionCard<Preview: View, TrailingAccessory: View>(
        title: String,
        subtitle: String,
        @ViewBuilder preview: () -> Preview,
        isSelected: Bool,
        @ViewBuilder trailingAccessory: () -> TrailingAccessory = { EmptyView() }
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            preview()
                .frame(width: 112, height: 224)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                trailingAccessory()
            }

            Spacer(minLength: 12)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(isSelected ? .pink : .secondary.opacity(0.7))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(isSelected ? Color.pink.opacity(0.9) : Color.primary.opacity(0.06), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 14, y: 6)
    }

    private func manifestEntry(for template: PenlightTemplateStyle) -> PenlightTemplateManifestEntry {
        templateEntries.first(where: { $0.id == template.rawValue })
        ?? PenlightTemplateManifest.entry(for: template)
    }

    private func loadBackgroundImage(for entry: PenlightTemplateManifestEntry) async -> UIImage? {
        if let urlString = PenlightTemplateManifest.resolvedRemoteURLString(for: entry.baseImageURL),
           let image = await PenlightTemplateImageCache.shared.loadImage(urlString: urlString) {
            return image
        }
        if let bundledURL = PenlightTemplateManifest.bundledImageURL(for: entry.baseImageURL),
           let image = UIImage(contentsOfFile: bundledURL.path) {
            return image
        }
        return nil
    }
}

private struct PenlightTemplateCard: View {
    let template: PenlightTemplateStyle
    let templateEntry: PenlightTemplateManifestEntry
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            PenlightTemplatePreviewView(template: template, templateEntry: templateEntry)
                .frame(width: 112, height: 224)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(templateEntry.title)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text(templateEntry.subtitle)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 12)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(isSelected ? .pink : .secondary.opacity(0.7))
                }

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(isSelected ? Color.pink.opacity(0.9) : Color.primary.opacity(0.06), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 14, y: 6)
    }
}

private struct PenlightBackgroundPreview: View {
    let image: UIImage?
    let fallbackText: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(fallbackText)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .padding(8)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct PenlightTemplatePreviewView: View {
    let template: PenlightTemplateStyle
    let templateEntry: PenlightTemplateManifestEntry

    var body: some View {
        PenlightTemplatePreviewContent(template: template, templateEntry: templateEntry)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct PenlightTemplatePreviewContent: View {
    let template: PenlightTemplateStyle
    let templateEntry: PenlightTemplateManifestEntry

    @State private var remoteImage: UIImage?

    var body: some View {
        Group {
            if let remoteImage {
                Image(uiImage: remoteImage)
                    .resizable()
                    .scaledToFit()
            } else {
                PenlightStickerCanvasView(
                    template: template,
                    templateEntry: templateEntry,
                    primaryText: "",
                    secondaryText: "",
                    showsSecondaryText: template.layoutKind == .double,
                    primaryTextSize: 28,
                    secondaryTextSize: 28,
                    isOutlineEnabled: true,
                    whiteOutlineSize: PenlightSheetDraft.defaultWhiteOutlineSize,
                    blackOutlineSize: PenlightSheetDraft.defaultBlackOutlineSize,
                    primaryPosition: .constant(template.defaultPrimaryPosition),
                    secondaryPosition: .constant(template.defaultSecondaryPosition),
                    isInteractive: false,
                    canvasStyle: .cardPreview,
                    providedBackgroundImage: nil
                )
            }
        }
        .task(id: templateEntry.id + (templateEntry.baseImageURL ?? templateEntry.baseImageName ?? "")) {
            if let urlString = PenlightTemplateManifest.resolvedRemoteURLString(for: templateEntry.baseImageURL) {
                remoteImage = await PenlightTemplateImageCache.shared.loadImage(urlString: urlString)
            } else if let bundledURL = PenlightTemplateManifest.bundledImageURL(for: templateEntry.baseImageURL),
                      let image = UIImage(contentsOfFile: bundledURL.path) {
                remoteImage = image
            } else {
                remoteImage = nil
            }
        }
    }
}

private enum PenlightStickerCanvasStyle {
    case editorPreview
    case cardPreview
    case exportedImage
}

private struct PenlightStickerCanvasView: View {
    let template: PenlightTemplateStyle
    let templateEntry: PenlightTemplateManifestEntry
    let primaryText: String
    let secondaryText: String
    let showsSecondaryText: Bool
    let primaryTextSize: CGFloat
    let secondaryTextSize: CGFloat
    let isOutlineEnabled: Bool
    let whiteOutlineSize: CGFloat
    let blackOutlineSize: CGFloat
    @Binding var primaryPosition: CGPoint
    @Binding var secondaryPosition: CGPoint
    let isInteractive: Bool
    let canvasStyle: PenlightStickerCanvasStyle
    let providedBackgroundImage: UIImage?
    @State private var primaryDragStartPosition: CGPoint?
    @State private var secondaryDragStartPosition: CGPoint?
    @State private var remoteBackgroundImage: UIImage?

    private var backgroundTemplateImage: UIImage? {
        providedBackgroundImage
        ?? remoteBackgroundImage
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                canvasBackground(in: size)

                if backgroundTemplateImage == nil {
                    templateDecoration(in: size)
                }

                draggableText(
                    primaryText,
                    textSize: primaryTextSize,
                    position: $primaryPosition,
                    dragStartPosition: $primaryDragStartPosition,
                    in: size
                )

                if showsSecondaryText {
                    draggableText(
                        secondaryText,
                        textSize: secondaryTextSize,
                        position: $secondaryPosition,
                        dragStartPosition: $secondaryDragStartPosition,
                        in: size
                    )
                }
            }
            .contentShape(Rectangle())
            .clipped()
        }
        .task(id: templateEntry.id + (templateEntry.baseImageURL ?? templateEntry.baseImageName ?? "")) {
            guard providedBackgroundImage == nil else {
                remoteBackgroundImage = nil
                return
            }

            if let urlString = PenlightTemplateManifest.resolvedRemoteURLString(for: templateEntry.baseImageURL) {
                remoteBackgroundImage = await PenlightTemplateImageCache.shared.loadImage(urlString: urlString)
            } else if let bundledURL = PenlightTemplateManifest.bundledImageURL(for: templateEntry.baseImageURL),
                      let image = UIImage(contentsOfFile: bundledURL.path) {
                remoteBackgroundImage = image
            } else {
                remoteBackgroundImage = nil
            }
        }
    }

    @ViewBuilder
    private func canvasBackground(in size: CGSize) -> some View {
        switch canvasStyle {
        case .editorPreview:
            Rectangle()
                .fill(Color.white)
        case .cardPreview:
            RoundedRectangle(cornerRadius: size.width * 0.08)
                .fill(Color.white)
        case .exportedImage:
            Rectangle()
                .fill(Color.white)
        }

        if let backgroundTemplateImage {
            Image(uiImage: backgroundTemplateImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size.width)
                .frame(width: size.width, height: size.height, alignment: .center)
                .clipped()
        }

        switch canvasStyle {
        case .editorPreview:
            Rectangle()
                .stroke(Color.black.opacity(0.12), lineWidth: max(size.width * 0.01, 1))
        case .cardPreview:
            RoundedRectangle(cornerRadius: size.width * 0.08)
                .stroke(Color.black.opacity(0.12), lineWidth: max(size.width * 0.01, 1))
        case .exportedImage:
            EmptyView()
        }
    }

    @ViewBuilder
    private func templateDecoration(in size: CGSize) -> some View {
        if template.layoutKind == .double {
            sideDecorationColumn(canvasWidth: size.width, canvasHeight: size.height)
                .position(x: size.width * 0.45, y: size.height * 0.5)

            sideDecorationColumn(canvasWidth: size.width, canvasHeight: size.height)
                .position(x: size.width * 0.91, y: size.height * 0.5)
        }

        if template.layoutKind == .single {
            sideDecorationColumn(canvasWidth: size.width, canvasHeight: size.height)
                .position(x: size.width * 0.28, y: size.height * 0.5)

            sideDecorationColumn(canvasWidth: size.width, canvasHeight: size.height)
                .position(x: size.width * 0.72, y: size.height * 0.5)
        }
    }

    private var sideDecorationSymbols: [String] {
        switch template {
        case .customImage:
            return []
        case .ribbonHeart:
            return ["heart.fill", "sparkles", "gift.fill", "heart", "sparkles", "heart.fill", "gift.fill", "sparkles", "heart"]
        case .sparkleBerry:
            return ["sparkles", "heart.fill", "star.fill", "sparkles", "heart", "star.fill", "sparkles", "heart.fill", "sparkles"]
        case .spaceStar:
            return ["star.fill", "sparkles", "circle.fill", "sparkles", "star", "circle.fill", "sparkles", "star.fill", "sparkles"]
        case .dottedLovely, .singleLovely:
            return ["heart", "circle.fill", "heart.fill", "circle", "heart", "circle.fill", "heart.fill", "circle", "heart"]
        }
    }

    @ViewBuilder
    private func decorationSymbol(_ systemName: String, canvasWidth: CGFloat) -> some View {
        Image(systemName: systemName)
            .font(.system(size: max(canvasWidth * 0.055, 8), weight: .bold))
            .foregroundColor(.black)
    }

    @ViewBuilder
    private func sideDecorationColumn(canvasWidth: CGFloat, canvasHeight: CGFloat) -> some View {
        VStack(spacing: canvasHeight * 0.028) {
            ForEach(Array(sideDecorationSymbols.enumerated()), id: \.offset) { _, symbol in
                decorationSymbol(symbol, canvasWidth: canvasWidth)
            }
        }
    }

    private func clampedRelativePosition(_ point: CGPoint, for text: String, textSize: CGFloat, in size: CGSize) -> CGPoint {
        let measured = estimatedTextBounds(for: text, textSize: textSize)
        let halfWidthRatio = min(max((measured.width / max(size.width, 1)) / 2, 0.08), 0.45)
        let halfHeightRatio = min(max((measured.height / max(size.height, 1)) / 2, 0.14), 0.48)

        return CGPoint(
            x: min(max(point.x, halfWidthRatio), 1 - halfWidthRatio),
            y: min(max(point.y, halfHeightRatio), 1 - halfHeightRatio)
        )
    }

    private func estimatedTextBounds(for text: String, textSize: CGFloat) -> CGSize {
        let characterCount = max(text.count, 1)
        let characterSpacing =
            PenlightSheetLayoutMetrics.referenceCharacterSpacing
            * (textSize / max(PenlightSheetLayoutMetrics.referenceTextSize, 1))
        let horizontalPadding = max(2, 4 * (textSize / max(PenlightSheetLayoutMetrics.referenceTextSize, 1)))
        let verticalPadding = max(3, 6 * (textSize / max(PenlightSheetLayoutMetrics.referenceTextSize, 1)))
        let outlinePadding = isOutlineEnabled ? (whiteOutlineSize + blackOutlineSize) * 2.4 : 0

        let width = textSize + horizontalPadding * 2 + outlinePadding * 2
        let height =
            CGFloat(characterCount) * textSize
            + CGFloat(max(characterCount - 1, 0)) * characterSpacing
            + verticalPadding * 2
            + outlinePadding * 2

        return CGSize(
            width: width * 1.05,
            height: max(height, textSize) * 1.24
        )
    }

    @ViewBuilder
    private func draggableText(
        _ text: String,
        textSize: CGFloat,
        position: Binding<CGPoint>,
        dragStartPosition: Binding<CGPoint?>,
        in size: CGSize
    ) -> some View {
        let clampedPosition = clampedRelativePosition(position.wrappedValue, for: text, textSize: textSize, in: size)

        VerticalStickerText(
            text: text,
            textSize: textSize,
            isOutlineEnabled: isOutlineEnabled,
            whiteOutlineSize: whiteOutlineSize,
            blackOutlineSize: blackOutlineSize,
            isPlaceholder: text.hasPrefix("文字枠")
        )
            .position(x: size.width * clampedPosition.x, y: size.height * clampedPosition.y)
            .gesture(
                isInteractive
                ? DragGesture()
                    .onChanged { value in
                        if dragStartPosition.wrappedValue == nil {
                            dragStartPosition.wrappedValue = position.wrappedValue
                        }
                        let base = dragStartPosition.wrappedValue ?? position.wrappedValue
                        let updatedPoint = CGPoint(
                            x: base.x + (value.translation.width / max(size.width, 1)),
                            y: base.y + (value.translation.height / max(size.height, 1))
                        )
                        position.wrappedValue = clampedRelativePosition(updatedPoint, for: text, textSize: textSize, in: size)
                    }
                    .onEnded { _ in
                        dragStartPosition.wrappedValue = nil
                    }
                : nil
            )
    }
}

private struct VerticalStickerText: View {
    let text: String
    let textSize: CGFloat
    let isOutlineEnabled: Bool
    let whiteOutlineSize: CGFloat
    let blackOutlineSize: CGFloat
    let isPlaceholder: Bool

    private var characters: [String] {
        Array(text).map { String($0) }
    }

    private var characterSpacing: CGFloat {
        let baseSpacing = PenlightSheetLayoutMetrics.referenceCharacterSpacing
            * (textSize / max(PenlightSheetLayoutMetrics.referenceTextSize, 1))
        return isOutlineEnabled ? baseSpacing : baseSpacing * 0.7
    }

    private var horizontalPadding: CGFloat {
        max(2, 4 * (textSize / max(PenlightSheetLayoutMetrics.referenceTextSize, 1)))
    }

    private var verticalPadding: CGFloat {
        max(3, 6 * (textSize / max(PenlightSheetLayoutMetrics.referenceTextSize, 1)))
    }

    var body: some View {
        VStack(spacing: characterSpacing) {
            ForEach(Array(characters.enumerated()), id: \.offset) { _, character in
                outlinedCharacter(character)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(isPlaceholder ? 0.22 : 0.001))
        )
    }

    @ViewBuilder
    private func outlinedCharacter(_ character: String) -> some View {
        if let image = renderedCharacterImage(for: character) {
            Image(uiImage: image)
                .interpolation(.high)
        } else {
            Text(character)
                .font(AppTypography.penlightSheetFont(size: textSize))
                .foregroundColor(.black.opacity(isPlaceholder ? 0.35 : 1.0))
        }
    }

    private func renderedCharacterImage(for character: String) -> UIImage? {
        let cacheKey = [
            character,
            String(format: "%.2f", textSize),
            isOutlineEnabled ? "1" : "0",
            String(format: "%.2f", whiteOutlineSize),
            String(format: "%.2f", blackOutlineSize),
            isPlaceholder ? "1" : "0"
        ].joined(separator: "|")

        if let cached = PenlightCharacterImageCache.shared.image(forKey: cacheKey) {
            return cached
        }

        guard let font = resolvedUIFont(size: textSize) else { return nil }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let characterString = character as NSString
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]

        let baseBounds = characterString.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: baseAttributes,
            context: nil
        ).integral

        let totalOutlineSize = isOutlineEnabled ? (blackOutlineSize + whiteOutlineSize) : 0
        let strokePaddingX = ceil(max(totalOutlineSize * 4.6, 2))
        let strokePaddingY = ceil(max(totalOutlineSize * 1.4, 1))
        let contentSize = CGSize(
            width: max(baseBounds.width, textSize),
            height: max(baseBounds.height, textSize)
        )
        let imageSize = CGSize(
            width: contentSize.width + strokePaddingX * 2,
            height: contentSize.height + strokePaddingY * 2
        )
        let drawRect = CGRect(origin: CGPoint(x: strokePaddingX, y: strokePaddingY), size: contentSize)

        let renderer = UIGraphicsImageRenderer(size: imageSize)
        let image = renderer.image { _ in
            if !isPlaceholder && isOutlineEnabled {
                let blackStrokeAttributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .paragraphStyle: paragraphStyle,
                    .foregroundColor: UIColor.black,
                    .strokeColor: UIColor.black,
                    .strokeWidth: strokePercent(for: blackOutlineSize + whiteOutlineSize, fontSize: textSize, multiplier: 1.9)
                ]
                characterString.draw(in: drawRect, withAttributes: blackStrokeAttributes)

                let whiteStrokeAttributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .paragraphStyle: paragraphStyle,
                    .foregroundColor: UIColor.white,
                    .strokeColor: UIColor.white,
                    .strokeWidth: strokePercent(for: whiteOutlineSize, fontSize: textSize, multiplier: 1.0)
                ]
                characterString.draw(in: drawRect, withAttributes: whiteStrokeAttributes)
            }

            let fillAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .paragraphStyle: paragraphStyle,
                .foregroundColor: isPlaceholder ? UIColor.black.withAlphaComponent(0.35) : UIColor.black
            ]
            characterString.draw(in: drawRect, withAttributes: fillAttributes)
        }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        PenlightCharacterImageCache.shared.setImage(image, forKey: cacheKey, cost: cost)
        return image
    }

    private func strokePercent(for width: CGFloat, fontSize: CGFloat, multiplier: CGFloat) -> CGFloat {
        guard fontSize > 0 else { return 0 }
        return max(0, width / fontSize * 100 * multiplier)
    }

    private func resolvedUIFont(size: CGFloat) -> UIFont? {
        if let font = UIFont(name: "GenJyuuGothicX-Heavy", size: size) {
            return font
        }
        if let fallback = UIFont(name: "YuseiMagic-Regular", size: size) {
            return fallback
        }
        return UIFont.systemFont(ofSize: size, weight: .black)
    }
}

private final class PenlightCharacterImageCache {
    static let shared = PenlightCharacterImageCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 512
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func setImage(_ image: UIImage, forKey key: String, cost: Int) {
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
}

private struct ToolMenuCard: View {
    let title: String
    let subtitle: String
    let symbol: String?
    let accent: Color
    let fontChoice: AppDisplayFontChoice
    var statusText: String? = nil

    var body: some View {
        HStack(spacing: 16) {
            if let symbol {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(accent.opacity(0.14))
                        .frame(width: 58, height: 58)
                    Image(systemName: symbol)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(accent)
                }
            } else {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.clear)
                    .frame(width: 58, height: 58)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(AppTypography.roundedDisplayFont(for: fontChoice, size: 20, weight: .bold))
                        .foregroundColor(.primary)
                    if let statusText {
                        Text(statusText)
                            .font(.caption.bold())
                            .foregroundColor(accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(accent.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.secondary.opacity(0.8))
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 14, y: 6)
    }
}

private struct ToolPlaceholderView: View {
    let title: String
    let subtitle: String
    let symbol: String?
    let fontChoice: AppDisplayFontChoice

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 52, weight: .bold))
                    .foregroundColor(.secondary)
            }
            Text(title)
                .font(AppTypography.roundedDisplayFont(for: fontChoice, size: 28, weight: .black))
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct EditProfileView: View {
    @Binding var profile: UserProfile
    @State private var selectedItem: PhotosPickerItem? = nil

    var body: some View {
        Form {
            Section("基本情報") {
                HStack(spacing: 16) {
                    if let data = profile.iconImageData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                            .foregroundColor(.secondary)
                    }

                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label(profile.iconImageData == nil ? "アイコンを選ぶ" : "アイコンを変更", systemImage: "photo")
                    }
                }

                TextField("表示名", text: $profile.displayName)
                TextField("ひとこと", text: $profile.message, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
            }

            Section {
                Text("名刺交換機能に向けた土台です。表示項目はあとから増やせます。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("プロフィール編集")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   UIImage(data: data) != nil {
                    await MainActor.run {
                        profile.iconImageData = data
                        selectedItem = nil
                    }
                } else {
                    await MainActor.run {
                        selectedItem = nil
                    }
                }
            }
        }
    }
}


// MARK: - 補助
struct SNSBtn: View {
    let icon: String; let label: String; let color: Color; let action: () -> Void
    var body: some View {
        Button(action: action) { VStack(spacing: 5) { Image(systemName: icon).font(.title3); Text(label).font(.caption2).bold() }.foregroundColor(color).frame(width: 55, height: 55).background(color.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 12)) }
    }
}

struct ColorUtils {
    static func isLightColor(_ color: Color) -> Bool {
        let uiColor = UIColor(color); var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: nil); return (0.299 * r + 0.587 * g + 0.114 * b) > 0.85
    }

    static func recommendedTextColor(backgroundImageData: Data?, fallbackColor: Color) -> Color {
        guard let backgroundImageData,
              let image = UIImage(data: backgroundImageData),
              let sampledBrightness = sampledBrightnessForTextArea(in: image) else {
            return isLightColor(fallbackColor) ? .black : .white
        }

        return sampledBrightness > 0.64 ? .black : .white
    }

    private static func sampledBrightnessForTextArea(in image: UIImage) -> CGFloat? {
        guard let normalizedImage = normalizedImage(image),
              let cgImage = normalizedImage.cgImage else {
            return nil
        }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 1, height > 1 else { return nil }

        // 推し画面の名前と日数が出る中央付近をざっくり見る
        let normalizedRect = CGRect(x: 0.18, y: 0.42, width: 0.64, height: 0.30)
        let cropRect = CGRect(
            x: width * normalizedRect.minX,
            y: height * normalizedRect.minY,
            width: width * normalizedRect.width,
            height: height * normalizedRect.height
        ).integral

        guard let croppedImage = cgImage.cropping(to: cropRect) else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(croppedImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        let r = CGFloat(pixel[0]) / 255
        let g = CGFloat(pixel[1]) / 255
        let b = CGFloat(pixel[2]) / 255
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    private static func normalizedImage(_ image: UIImage) -> UIImage? {
        if image.imageOrientation == .up {
            return image
        }

        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    static func toHex(_ color: Color) -> String {
        let uiColor = UIColor(color); var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a); return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        
        let r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12bit)
            (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RRGGBB (24bit)
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (128, 128, 128) // エラー時はグレー
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b: UInt64
        switch hex.count {
        case 3:
            (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (128, 128, 128)
        }

        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: 1
        )
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedData: Data?
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                // ヘッダー用なので少し圧縮して保存
                parent.selectedData = image.jpegData(compressionQuality: 0.8)
            }
            parent.dismiss()
        }
    }
}

#Preview { ContentView() }
