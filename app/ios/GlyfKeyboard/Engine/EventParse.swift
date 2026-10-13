import Foundation

/// A plan read out of a line, the way people type one: "Lunch with Sam
/// tomorrow 1pm" is a title ("Lunch with Sam"), a day and a time. The New
/// Event title and the strip's Add to calendar chip both use it. English, plus
/// the Hinglish people type in India ("kal 5 baje"). Pure, and EventParse.kt
/// on Android is its twin: the two run the same cases.
enum EventParse {

    struct Plan: Equatable {
        /// What is left once the day and the time are taken out.
        var title: String
        var start: Date
        var end: Date
        var allDay: Bool
        /// Whether the text named a day, a time. A line with neither is only a title.
        var hasDay: Bool
        var hasTime: Bool
    }

    /// `dayFirst` reads 5/10 as 5 October (India, Britain); false reads it as
    /// May 10 (the US). The keyboard passes the phone's region.
    static func parse(_ text: String, now: Date = Date(), calendar cal: Calendar = .current,
                      dayFirst: Bool = true) -> Plan {
        var w = Work(text)
        var allDay = false
        var dayOffset: Int?
        var ymd: (y: Int?, m: Int, d: Int)?
        var weekday: (wd: Int, next: Bool, this: Bool)?
        var minutes: Int?          // start, minutes after midnight
        var endMinutes: Int?
        var bareHour: (h: Int, m: Int)?
        var duration: Int?         // minutes
        var relative: Int?         // minutes from now
        var part: Int?             // a part of the day's own hour ("evening": 18)
        var pm: Bool?              // what a part of the day says about a bare hour

        if w.take(#"\b(all[ -]?day|whole day|full day|poora din)\b"#) != nil { allDay = true }

        if let m = w.take(#"\bin\s+(\d+(?:\.\d+)?|an?|half an?)\s*(minutes?|mins?|hours?|hrs?|h)\b"#) {
            relative = amount(m[1], unit: m[2])
        }
        if let m = w.take(#"\bfor\s+(\d+(?:\.\d+)?|an?|half an?)\s*(minutes?|mins?|hours?|hrs?|h)\b"#) {
            duration = amount(m[1], unit: m[2])
        }

        // Parts of the day: a time of their own, and whether 8 means 8 PM.
        // "Good morning" is a greeting and "last night" is gone: neither is a plan.
        if let m = w.take(#"(?<!good )(?<!gud )(?<!last )\b(?:this\s+|in the\s+)?(morning|afternoon|evening|tonight|night|subah|dopahar|shaam|sham|raat)\b"#) {
            switch m[1] {
            case "morning", "subah": part = 9 * 60; pm = false
            case "afternoon": part = 15 * 60; pm = true
            case "dopahar": part = 14 * 60; pm = true
            case "evening", "shaam", "sham": part = 18 * 60; pm = true
            default: part = 20 * 60; pm = true   // tonight, night, raat
            }
            if m[1] == "tonight" { dayOffset = 0 }
        }

        // Times: a range first ("5-6pm", "from 5 to 7"), then one time.
        let hm = #"(\d{1,2})(?:[:.](\d{2}))?"#
        let range1 = #"\b(?:from\s+)?"# + hm + #"\s*(am|pm)?\s*(?:-|–|to|till|until)\s*"# + hm + #"\s*(am|pm)\b"#
        let range2 = #"\bfrom\s+"# + hm + #"\s*(am|pm)?\s*(?:-|–|to|till|until)\s*"# + hm + #"\s*(am|pm)?\b"#
        if let m = w.take(range1) ?? w.take(range2) {
            let endMer = m[6].isEmpty ? nil : m[6]
            let startMer = m[3].isEmpty ? endMer : m[3]
            if let s = clock(m[1], m[2], startMer, pm: pm), let e = clock(m[4], m[5], endMer, pm: pm) {
                minutes = s
                endMinutes = e
                // "11-1pm": the start is the morning before an afternoon end.
                if m[3].isEmpty, s > e, s >= 12 * 60 { minutes = s - 12 * 60 }
            }
        }
        if minutes == nil,
           let m = w.take(#"\b(?:at\s+|@\s*|around\s+|by\s+)?"# + hm + #"\s*(am|pm|a\.m\.?|p\.m\.?)(?![a-z])"#) {
            minutes = clock(m[1], m[2], m[3].hasPrefix("p") ? "pm" : "am", pm: pm)
        }
        if minutes == nil, let m = w.take(#"\b(?:at\s+|@\s*|around\s+|by\s+)?(\d{1,2}):(\d{2})\b"#) {
            let h = Int(m[1]) ?? 0, mm = Int(m[2]) ?? 0
            if h >= 13 && h <= 23 || h == 0 { minutes = h * 60 + mm } else if h <= 12 { bareHour = (h, mm) }
        }
        if minutes == nil, bareHour == nil, let m = w.take(#"\b"# + hm + #"\s*baje\b"#) {
            bareHour = (Int(m[1]) ?? 0, Int(m[2]) ?? 0)
        }
        if minutes == nil, bareHour == nil,
           let m = w.take(#"\b(?:at|@|around)\s+(\d{1,2})(?:[:.](\d{2}))?\b(?!\s*(?:%|/|st\b|nd\b|rd\b|th\b|people|persons|pax|mins?|minutes|hours?|hrs?))"#) {
            bareHour = (Int(m[1]) ?? 0, Int(m[2]) ?? 0)
        }
        // "brunch sunday 11", "dinner friday 8": an hour straight after the
        // day is its time ("sunday 11th" stays a date).
        if minutes == nil, bareHour == nil,
           let m = w.take(#"(?<=\b(?:mon|monday|tue|tues|tuesday|wed|weds|wednesday|thu|thur|thurs|thursday|fri|friday|sat|saturday|sun|sunday|today|tomorrow|tmrw|tonight)\s)(\d{1,2})(?:[:.](\d{2}))?\b(?!\s*(?:%|/|st\b|nd\b|rd\b|th\b|people|persons|pax|mins?|minutes|hours?|hrs?))"#) {
            bareHour = (Int(m[1]) ?? 0, Int(m[2]) ?? 0)
        }
        if minutes == nil, bareHour == nil, let m = w.take(#"\b(noon|midday|midnight)\b"#) {
            if m[1] == "midnight" { minutes = 0; dayOffset = (dayOffset ?? 0) + 1 } else { minutes = 12 * 60 }
        }
        // Dinner at 8 is 8 in the evening; breakfast at 8 is the morning.
        if pm == nil, bareHour != nil {
            let lower = text.lowercased()
            if lower.range(of: #"\b(dinner|drinks|party|movie|club)\b"#, options: .regularExpression) != nil { pm = true }
            if lower.range(of: #"\b(breakfast)\b"#, options: .regularExpression) != nil { pm = false }
        }
        if let b = bareHour, b.h >= 1, b.h <= 12, b.m < 60 {
            var h = b.h
            let isPM = pm ?? (h <= 7 || h == 12)
            if isPM, h < 12 { h += 12 }
            if !isPM, h == 12 { h = 0 }
            minutes = h * 60 + b.m
        }

        // Days.
        if w.take(#"\b(day after (?:tomorrow|tmrw)|parso|parson)\b"#) != nil { dayOffset = 2 }
        if w.take(#"\b(tomorrow|tomorow|tmrw|tmr|tmrrw|tomo|2moro|2morrow|kal)\b"#) != nil { dayOffset = 1 }
        if w.take(#"\b(today|aaj)\b"#) != nil { dayOffset = 0 }
        let full = #"(monday|tuesday|wednesday|thursday|friday|saturday|sunday)"#
        let short = #"(mon|tue|tues|wed|weds|thu|thur|thurs|fri|sat|sun)"#
        if let m = w.take(#"\b(?:(this|next|coming|on)\s+)?"# + full + #"\b"#) {
            weekday = (index(m[2]), m[1] == "next", m[1] == "this")
        } else if let m = w.take(#"\b(this|next|coming|on|by)\s+"# + short + #"\b"#) {
            weekday = (index(m[2]), m[1] == "next", m[1] == "this")
        } else if let m = w.take(#"\b"# + short + #"(?=\s*(?:\d|at\b|@|morning|evening|night|afternoon))"#) {
            weekday = (index(m[1]), false, false)
        }
        if weekday == nil, dayOffset == nil, w.take(#"\bnext week\b"#) != nil { dayOffset = 7 }
        if weekday == nil, dayOffset == nil, w.take(#"\b(?:this\s+)?weekend\b"#) != nil { weekday = (7, false, true) }

        let months = #"(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)"#
        if let m = w.take(#"\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?"# + months + #"\b"#) {
            ymd = (nil, month(m[2]), Int(m[1]) ?? 0)
        } else if let m = w.take(#"\b"# + months + #"\s+(\d{1,2})(?:st|nd|rd|th)?\b"#) {
            ymd = (nil, month(m[1]), Int(m[2]) ?? 0)
        } else if let m = w.take(#"\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b"#) {
            let a = Int(m[1]) ?? 0, b = Int(m[2]) ?? 0
            let y = m[3].isEmpty ? nil : (Int(m[3]).map { $0 < 100 ? 2000 + $0 : $0 })
            ymd = dayFirst ? (y, b, a) : (y, a, b)
        } else if let m = w.take(#"\b(?:on\s+)?the\s+(\d{1,2})(?:st|nd|rd|th)\b"#) {
            // This month's, or next month's once it has gone.
            var c = cal.dateComponents([.year, .month], from: now)
            c.day = Int(m[1]) ?? 0
            if let d = cal.date(from: c), cal.component(.day, from: d) == c.day {
                let use = d < cal.startOfDay(for: now) ? (cal.date(byAdding: .month, value: 1, to: d) ?? d) : d
                let u = cal.dateComponents([.year, .month, .day], from: use)
                ymd = (u.year, u.month ?? 1, u.day ?? 1)
            }
        }

        // Resolve the day.
        let today = cal.startOfDay(for: now)
        var day: Date?
        if let r = relative, let at = cal.date(byAdding: .minute, value: r, to: now) {
            day = cal.startOfDay(for: at)
            let c = cal.dateComponents([.hour, .minute], from: at)
            minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        } else if let x = ymd, x.m >= 1, x.m <= 12, x.d >= 1, x.d <= 31 {
            var c = DateComponents()
            c.year = x.y ?? cal.component(.year, from: now)
            c.month = x.m
            c.day = x.d
            if var d = cal.date(from: c), cal.component(.day, from: d) == x.d {
                if x.y == nil, d < today, let next = cal.date(byAdding: .year, value: 1, to: d) { d = next }
                day = d
            }
        } else if let x = weekday {
            let todayWd = cal.component(.weekday, from: today)   // 1 = Sunday
            var ahead = (x.wd - todayWd + 7) % 7                  // the weekend is Saturday (7)
            if ahead == 0, !x.this { ahead = 7 }
            var d = cal.date(byAdding: .day, value: ahead, to: today) ?? today
            if x.next, cal.isDate(d, equalTo: today, toGranularity: .weekOfYear) {
                d = cal.date(byAdding: .day, value: 7, to: d) ?? d
            }
            day = d
        } else if let o = dayOffset {
            day = cal.date(byAdding: .day, value: o, to: today)
        }
        let hasDay = day != nil
        // A clock time counts; a part of the day counts once a day is named
        // ("tomorrow evening"), since "evening" alone is how people talk.
        let hasTime = !allDay && (minutes != nil || (part != nil && hasDay))
        if minutes == nil, let p = part { minutes = p }

        let title = w.title()
        // A meal says when it is, when nothing else does.
        if !hasTime, !allDay {
            let lower = title.lowercased()
            let meals: [(String, Int)] = [("breakfast", 9 * 60), ("brunch", 11 * 60), ("lunch", 13 * 60), ("dinner", 20 * 60)]
            if let meal = meals.first(where: { lower.range(of: "\\b\($0.0)\\b", options: .regularExpression) != nil }) {
                minutes = meal.1
            }
        }

        let startDay = day ?? today
        var start: Date
        if allDay {
            start = startDay
        } else if let m = minutes {
            start = cal.date(byAdding: .minute, value: m, to: startDay) ?? startDay
            // A time with no day is the next time it comes round.
            if !hasDay, start <= now, let next = cal.date(byAdding: .day, value: 1, to: start) {
                start = next
            }
        } else if hasDay, !cal.isDate(startDay, inSameDayAs: today) {
            start = cal.date(byAdding: .hour, value: 9, to: startDay) ?? startDay
        } else {
            // Nothing said when: the next whole hour, like Calendar's own New Event.
            let hour = cal.dateInterval(of: .hour, for: now)?.start ?? now
            start = cal.date(byAdding: .hour, value: 1, to: hour) ?? now
        }

        var end: Date
        if allDay {
            end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        } else if let e = endMinutes {
            end = cal.date(byAdding: .minute, value: e, to: cal.startOfDay(for: start)) ?? start
            if end <= start { end = cal.date(byAdding: .day, value: 1, to: end) ?? end }
        } else {
            end = cal.date(byAdding: .minute, value: duration ?? 60, to: start) ?? start
        }
        return Plan(title: title, start: start, end: end, allDay: allDay, hasDay: hasDay, hasTime: hasTime)
    }

    /// Whether a message reads like a plan worth offering to put in the
    /// calendar: a time, and either a day or a word that makes it a plan.
    static func looksLikePlan(_ text: String, now: Date = Date(), calendar cal: Calendar = .current,
                              dayFirst: Bool = true) -> Plan? {
        // What the calendar itself put in the message is already in the
        // calendar: an event ("📅 Lunch · Fri…") or free time ("I'm free…").
        if text.contains("📅") || text.range(of: #"\bI[’']?m (free|busy|booked|done)\b"#,
                                             options: [.regularExpression, .caseInsensitive]) != nil {
            return nil
        }
        // "Call me in 5 minutes" is a countdown, not something for the calendar.
        if text.range(of: #"\bin\s+(?:\d+|an?|a few|few|couple of)\s*(?:minutes?|mins?)\b"#,
                      options: [.regularExpression, .caseInsensitive]) != nil { return nil }
        let p = parse(text, now: now, calendar: cal, dayFirst: dayFirst)
        // "remind me to call mom tomorrow": a reminder with a day and no
        // time is 9 AM that day, for half an hour (2026-10-14).
        if !p.hasTime, p.hasDay, !p.allDay,
           text.range(of: #"^\s*(?:pls\s+|please\s+)?(?:remind\s+me|reminder)\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
           let nine = cal.date(bySettingHour: 9, minute: 0, second: 0, of: p.start) {
            var r = p
            r.start = nine
            r.end = nine.addingTimeInterval(30 * 60)
            r.hasTime = true
            return r
        }
        guard p.hasTime else { return nil }
        let intent = #"\b(let[’']?s|lets|shall we|should we|can we|could we|meet|meeting|call|catch up|see you|see u|dinner|lunch|breakfast|brunch|coffee|drinks|party|appointment|interview|standup|sync|review|demo|class|session|gym|workout|yoga|movie|movies|film|concert|flight|dentist|doctor|haircut|game|match|pick (?:me|you|us|him|her|them) up|pickup|milte|milenge)\b"#
        let planned = text.range(of: intent, options: [.regularExpression, .caseInsensitive]) != nil
        // "what are you doing tonight" asks about a plan; it isn't one
        // (2026-10-08 probe). EventParse.kt's twin.
        if !planned, text.range(of: #"^\s*(?:what|wat|wht|where|who|why|how|whats|what's)\b"#,
                                options: [.regularExpression, .caseInsensitive]) != nil { return nil }
        if p.hasDay { return p }
        return planned ? p : nil
    }

    /// "Sam Lee sam@x.com, ria@y.com": a name and the email addresses on one
    /// line, the way the keyboard's who field takes them. The first address
    /// is the person, the rest their guests.
    static func people(_ line: String) -> (name: String, emails: [String]) {
        let pattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return ("", []) }
        let ns = line as NSString
        var emails: [String] = []
        for m in re.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            let e = ns.substring(with: m.range).lowercased()
            if !emails.contains(e) { emails.append(e) }
        }
        let rest = re.stringByReplacingMatches(in: line, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        let name = rest.replacingOccurrences(of: #"[,;<>()]"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (name, emails)
    }

    /// 5/10 is 5 October in India and Britain, May 10 in the US.
    static var regionDayFirst: Bool {
        let region = Locale.current.region?.identifier ?? "IN"
        return !["US", "PH", "CA", "FM", "MH", "PW"].contains(region)
    }

    /// "Dinner · Fri 8:00 PM", "Call · Today 5:00 PM": the strip chip's words.
    /// What the person already has when a plan falls ("busy: Dentist"), set
    /// by the keyboard where the calendar can be read (CalendarWriter).
    static var busyNote: ((Plan) -> String?)?

    /// The first timed event that overlaps the plan, said short: "busy:
    /// Dentist". All-day events (birthdays, holidays) don't make anyone busy.
    static func busyNote(for p: Plan, events: [CalendarText.Event]) -> String? {
        guard !p.allDay, p.hasTime else { return nil }
        guard let hit = events.first(where: { !$0.allDay && $0.start < p.end && $0.end > p.start }) else { return nil }
        let title = hit.title.count > 18 ? String(hit.title.prefix(17)) + "…" : hit.title
        return "busy: \(title)"
    }

    static func summary(_ p: Plan, now: Date = Date(), calendar cal: Calendar = .current,
                        locale: Locale = .current) -> String {
        let day: String
        if cal.isDate(p.start, inSameDayAs: now) {
            day = "Today"
        } else if let t = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(p.start, inSameDayAs: t) {
            day = "Tomorrow"
        } else {
            let f = DateFormatter()
            f.calendar = cal
            f.timeZone = cal.timeZone
            f.locale = locale
            f.setLocalizedDateFormatFromTemplate("EEE d MMM")
            day = f.string(from: p.start)
        }
        let when = p.allDay ? day : "\(day) \(CalendarText.clock(p.start, calendar: cal, locale: locale))"
        return p.title.isEmpty ? when : "\(p.title) · \(when)"
    }

    // MARK: pieces

    private static func amount(_ n: String, unit: String) -> Int {
        let value: Double
        switch n {
        case "a", "an": value = 1
        case "half a", "half an": value = 0.5
        default: value = Double(n) ?? 0
        }
        return Int((unit.hasPrefix("h") ? value * 60 : value).rounded())
    }

    /// Minutes after midnight for "5", "5:30", with a meridiem when one was
    /// given; a bare hour leans on the part of the day, then on habit.
    private static func clock(_ h: String, _ m: String, _ meridiem: String?, pm: Bool?) -> Int? {
        guard var hour = Int(h), hour <= 23 else { return nil }
        let minute = Int(m) ?? 0
        guard minute < 60 else { return nil }
        if let mer = meridiem {
            guard hour >= 1, hour <= 12 else { return nil }
            if mer == "pm", hour < 12 { hour += 12 }
            if mer == "am", hour == 12 { hour = 0 }
        } else if hour <= 12 {
            let isPM = pm ?? (hour <= 7 || hour == 12)
            if isPM, hour < 12 { hour += 12 }
        }
        return hour * 60 + minute
    }

    /// Calendar's weekday numbers: Sunday 1 to Saturday 7.
    private static func index(_ name: String) -> Int {
        switch String(name.prefix(3)) {
        case "sun": return 1
        case "mon": return 2
        case "tue": return 3
        case "wed": return 4
        case "thu": return 5
        case "fri": return 6
        default: return 7
        }
    }

    private static func month(_ name: String) -> Int {
        let names = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        return (names.firstIndex(of: String(name.prefix(3))) ?? 0) + 1
    }

    /// The line being read. Each piece taken out is blanked where it stood,
    /// so later patterns can't reuse it and what remains is the title.
    private struct Work {
        private(set) var text: NSMutableString

        init(_ s: String) { text = NSMutableString(string: s) }

        /// The first match's groups, lowercased (a missing group is ""), and
        /// the match blanked out; nil when nothing matches.
        /// Compiled once: the strip reads every keystroke.
        private static var compiled: [String: NSRegularExpression] = [:]

        mutating func take(_ pattern: String) -> [String]? {
            let re: NSRegularExpression
            if let cached = Self.compiled[pattern] {
                re = cached
            } else {
                guard let made = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
                Self.compiled[pattern] = made
                re = made
            }
            let s = text as String
            guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: text.length)) else { return nil }
            var groups: [String] = []
            for i in 0..<m.numberOfRanges {
                let r = m.range(at: i)
                groups.append(r.location == NSNotFound ? "" : text.substring(with: r).lowercased())
            }
            text.replaceCharacters(in: m.range, with: String(repeating: " ", count: m.range.length))
            return groups
        }

        func title() -> String {
            var t = (text as String).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            let greeting = #"^\s*(?:hey|hi|so|ok|okay|yo|good morning|good evening|gm)[,!.]*\s+"#
            t = t.replacingOccurrences(of: greeting, with: "", options: [.regularExpression, .caseInsensitive])
            let lead = #"^\s*(?:(?:let[’']?s|lets|let us|shall we|should we|can we|could we|we should|how about|what about|maybe|pls|please|remind me to|reminder to|reminder:?)\s+)+"#
            t = t.replacingOccurrences(of: lead, with: "", options: [.regularExpression, .caseInsensitive])
            let dangling = #"(?:\s+(?:at|on|for|from|by|around|in|this|next|the|and|,|-|–))+\s*$"#
            for _ in 0..<3 {
                t = t.replacingOccurrences(of: dangling, with: "", options: [.regularExpression, .caseInsensitive])
                t = t.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:!?-–"))
            }
            t = t.replacingOccurrences(of: #"^(?:on|at|by)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
            t = t.replacingOccurrences(of: #"\s+([,.!?])"#, with: "$1", options: .regularExpression)
            guard let first = t.first else { return "" }
            return first.uppercased() + t.dropFirst()
        }
    }
}
