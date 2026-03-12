import Foundation

// MARK: - Date Formatting

enum DateFormatting {
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parseISO(_ string: String) -> Date? {
        isoFormatterWithFractional.date(from: string) ?? isoFormatter.date(from: string)
    }

    static func localString(from isoString: String) -> String {
        guard let date = parseISO(isoString) else {
            return isoString
        }
        return localString(from: date)
    }

    static func localString(from date: Date) -> String {
        let tz = TimeZone.current.abbreviation(for: date) ?? TimeZone.current.identifier
        return "\(date.formatted(date: .abbreviated, time: .shortened)) \(tz)"
    }
}

// MARK: - Schedule

enum Schedule: Codable, Hashable {
    case cron(CronSchedule)
    case oneshot(OneshotSchedule)
    case interval(IntervalSchedule)

    var raw: String {
        switch self {
        case .cron(let s): s.raw
        case .oneshot(let s): s.raw
        case .interval(let s): s.raw
        }
    }

    var description: String {
        switch self {
        case .cron(let s): s.description
        case .oneshot(let s): "once at \(DateFormatting.localString(from: s.at))"
        case .interval(let s): s.description
        }
    }

    var isCron: Bool {
        if case .cron = self { return true }
        return false
    }

    var isRecurring: Bool {
        switch self {
        case .cron, .interval: true
        case .oneshot: false
        }
    }

    private enum CodingKeys: String, CodingKey {
        case tag = "_tag"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(String.self, forKey: .tag)
        switch tag {
        case "Cron":
            self = .cron(try CronSchedule(from: decoder))
        case "Oneshot":
            self = .oneshot(try OneshotSchedule(from: decoder))
        case "Interval":
            self = .interval(try IntervalSchedule(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .tag, in: container, debugDescription: "Unknown schedule tag: \(tag)")
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .cron(let s): try s.encode(to: encoder)
        case .oneshot(let s): try s.encode(to: encoder)
        case .interval(let s): try s.encode(to: encoder)
        }
    }
}

struct CronSchedule: Codable, Hashable {
    let tag: String
    let minute: NumOrStar
    let hour: NumOrStar
    let dayOfMonth: NumOrStar
    let month: NumOrStar
    let dayOfWeek: DayOfWeek
    let raw: String

    private enum CodingKeys: String, CodingKey {
        case tag = "_tag"
        case minute, hour, dayOfMonth, month, dayOfWeek, raw
    }

    var description: String {
        let timeStr: String
        if case .number(let h) = hour {
            let m = minute.numberValue ?? 0
            timeStr = String(format: "%02d:%02d", h, m)
        } else {
            timeStr = "every hour"
        }

        switch dayOfWeek {
        case .range("1-5"): return "weekdays at \(timeStr)"
        case .star: return "daily at \(timeStr)"
        case .number(let d):
            let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let name = d >= 0 && d < 7 ? names[d] : "day \(d)"
            return "every \(name) at \(timeStr)"
        default: return "cron: \(raw)"
        }
    }
}

struct OneshotSchedule: Codable, Hashable {
    let tag: String
    let at: String
    let raw: String

    private enum CodingKeys: String, CodingKey {
        case tag = "_tag"
        case at, raw
    }

    var atDate: Date? {
        DateFormatting.parseISO(at)
    }
}

struct IntervalSchedule: Codable, Hashable {
    let tag: String
    let seconds: Int
    let raw: String

    private enum CodingKeys: String, CodingKey {
        case tag = "_tag"
        case seconds, raw
    }

    var description: String {
        if seconds < 60 {
            return "every \(seconds)s"
        } else if seconds < 3600 {
            let mins = seconds / 60
            return "every \(mins) min\(mins == 1 ? "" : "s")"
        } else {
            let hours = seconds / 3600
            return "every \(hours) hour\(hours == 1 ? "" : "s")"
        }
    }
}

// MARK: - NumOrStar

enum NumOrStar: Codable, Hashable {
    case number(Int)
    case star

    var numberValue: Int? {
        if case .number(let n) = self { return n }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let n = try? container.decode(Int.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self), s == "*" {
            self = .star
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected number or \"*\"")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let n): try container.encode(n)
        case .star: try container.encode("*")
        }
    }
}

// MARK: - DayOfWeek

enum DayOfWeek: Codable, Hashable {
    case number(Int)
    case star
    case range(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let n = try? container.decode(Int.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = s == "*" ? .star : .range(s)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected number, \"*\", or range string")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let n): try container.encode(n)
        case .star: try container.encode("*")
        case .range(let s): try container.encode(s)
        }
    }
}

// MARK: - StopCondition

enum StopCondition: Codable, Hashable {
    case maxRuns(count: Int)
    case afterDate(date: String)

    private enum CodingKeys: String, CodingKey {
        case tag = "_tag"
        case count, date
    }

    var description: String {
        switch self {
        case .maxRuns(let count):
            return "after \(count) runs"
        case .afterDate(let date):
            return "after \(DateFormatting.localString(from: date))"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(String.self, forKey: .tag)
        switch tag {
        case "MaxRuns":
            let count = try container.decode(Int.self, forKey: .count)
            self = .maxRuns(count: count)
        case "AfterDate":
            let date = try container.decode(String.self, forKey: .date)
            self = .afterDate(date: date)
        default:
            throw DecodingError.dataCorruptedError(forKey: .tag, in: container, debugDescription: "Unknown stop condition tag: \(tag)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .maxRuns(let count):
            try container.encode("MaxRuns", forKey: .tag)
            try container.encode(count, forKey: .count)
        case .afterDate(let date):
            try container.encode("AfterDate", forKey: .tag)
            try container.encode(date, forKey: .date)
        }
    }
}

// MARK: - ConditionalStop

struct ConditionalStop: Codable, Hashable {
    let condition: String
}

// MARK: - TaskContext

struct TaskContext: Codable, Hashable {
    var gitBranch: String?
    var gitRemoteUrl: String?
    var gitRepo: String?
    var gitCommit: String?
    var gitDefaultBranch: String?
    var prNumber: Int?
    var prUrl: String?
    var issueNumber: Int?
}

// MARK: - AgentdTask

struct AgentdTask: Codable, Identifiable, Hashable {
    let id: String
    let prompt: String
    let provider: String
    let schedule: Schedule
    let cwd: String
    let createdAt: String
    let status: String
    var lastRun: String?
    var runCount: Int
    var context: TaskContext?
    var stopConditions: [StopCondition]?
    var conditionalStop: ConditionalStop?

    var createdAtDate: Date? {
        DateFormatting.parseISO(createdAt)
    }

    var lastRunDate: Date? {
        guard let lastRun else { return nil }
        return DateFormatting.parseISO(lastRun)
    }

    var statusColor: String {
        switch status {
        case "active": "green"
        case "completed": "blue"
        case "failed": "red"
        default: "gray"
        }
    }

    var nextRunDescription: String? {
        guard status == "active" else { return nil }
        switch schedule {
        case .cron(let cron):
            return cron.description
        case .oneshot(let oneshot):
            guard let date = oneshot.atDate else { return nil }
            if date > Date() {
                return "scheduled for \(DateFormatting.localString(from: date))"
            }
            return "past schedule"
        case .interval(let interval):
            return interval.description
        }
    }
}
