import Foundation

/// Booking links, read and booked from the phone: the server's scheduling
/// routes (server/src/routes/scheduling.ts: `parseBookingLink`,
/// `bookingUrl`, the Cal.com v2 calls) ported as they are, so Book a time
/// talks to Cal.com's keyless API itself and no shared rate limit stands in
/// the way (docs/SERVER-INVENTORY.md, 2026-10-14). GET /scheduling/slots and
/// POST /scheduling/book stay as the fallback when Cal.com can't be reached.
///
/// Cal.com answers a public event's open times and takes a booking with no
/// key. Calendly gives times only to the host's own sign-in, so its link
/// comes back on the day chosen, and it books only on its own page.
///
/// Synchronous: `http` blocks, so BackendClient runs this off the main
/// queue and tests hand in a stand-in.
enum CalBooking {

    struct Link: Equatable {
        /// "calcom" or "calendly".
        let provider: String
        /// The link without query or extra path: https://cal.com/jane/30min
        var base: String
        let username: String
        var slug: String?
        /// physics for physics.cal.com: Cal.com organisations have their own host.
        let org: String?
    }

    /// What came back over HTTP: the status and the body.
    struct Response {
        let status: Int
        let body: Data
    }

    /// The request never left the phone (no connection, no name, no TLS):
    /// safe to ask the server instead, even for a booking.
    struct NotSent: Error {}

    /// Sends a request and blocks for the answer. Throws `NotSent` when it
    /// never went out, anything else when it was lost on the way.
    typealias HTTP = (_ method: String, _ url: String, _ headers: [String: String], _ body: Data?) throws -> Response

    enum Outcome<T> {
        case ok(T)
        /// A final answer, in the server's own words.
        case refused(String)
        /// Cal.com couldn't be asked, and nothing was booked: the server may.
        case unreachable
    }

    struct Slots {
        let provider: String
        let link: String
        let bookingUrl: String
        let title: String?
        let length: Int?
        let days: [(date: String, slots: [(start: String, url: String)])]
    }

    struct Booked {
        let uid: String?
        let start: String?
        let end: String?
        let title: String?
        let meetingUrl: String?
        let invited: [String]
    }

    static let defaultAPI = "https://api.cal.com/v2"

    // MARK: Links

    /// A Cal.com or Calendly booking link, however it was typed
    /// ("cal.com/jane", "https://calendly.com/jane/30min?month=…"); nil for
    /// anything else.
    static func parse(_ raw: String) -> Link? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if s.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) == nil { s = "https://\(s)" }
        guard let comps = URLComponents(string: s), var host = comps.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var parts: [String] = []
        for piece in comps.percentEncodedPath.split(separator: "/") {
            guard let p = String(piece).removingPercentEncoding else { return nil }
            parts.append(p)
        }
        guard let username = parts.first,
              parts.allSatisfy({ p in !p.isEmpty && p.unicodeScalars.allSatisfy(isNameScalar) }) else { return nil }
        let slug = parts.count > 1 ? parts[1] : nil
        let path = [username, slug].compactMap { $0 }.joined(separator: "/")
        if host == "calendly.com" {
            return Link(provider: "calendly", base: "https://calendly.com/\(path)", username: username, slug: slug, org: nil)
        }
        if host == "cal.com" || host == "app.cal.com" || host.hasSuffix(".cal.com") {
            let org = host.hasSuffix(".cal.com") && host != "app.cal.com" ? String(host.dropLast(".cal.com".count)) : nil
            let shown = host == "app.cal.com" ? "cal.com" : host
            return Link(provider: "calcom", base: "https://\(shown)/\(path)", username: username, slug: slug, org: org)
        }
        return nil
    }

    /// JavaScript's `\w`, a dot or a dash.
    private static func isNameScalar(_ c: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(c) || ("A"..."Z").contains(c) || ("0"..."9").contains(c) || c == "_" || c == "." || c == "-"
    }

    /// The booking page on a day ("…?month=2026-09&date=2026-09-25"), and on
    /// one time when there is one: Cal.com goes straight to the form with `slot`.
    static func bookingUrl(_ link: Link, date: String? = nil, slotUtc: String? = nil) -> String {
        var query: [(String, String)] = []
        if let date {
            query.append(("month", String(date.prefix(7))))
            query.append(("date", date))
        }
        if let slotUtc, link.provider == "calcom" { query.append(("slot", slotUtc)) }
        return query.isEmpty ? link.base : link.base + "?" + form(query)
    }

    /// application/x-www-form-urlencoded, as URLSearchParams writes it.
    static func form(_ pairs: [(String, String)]) -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789*-._")
        allowed.insert(" ")
        func enc(_ s: String) -> String {
            (s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s).replacingOccurrences(of: " ", with: "+")
        }
        return pairs.map { "\(enc($0.0))=\(enc($0.1))" }.joined(separator: "&")
    }

    // MARK: Times

    private static let utcDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func addDays(_ date: String, _ n: Int) -> String {
        guard let d = utcDay.date(from: date) else { return date }
        return utcDay.string(from: d.addingTimeInterval(TimeInterval(n) * 86_400))
    }

    /// An instant as JavaScript's `toISOString()` writes it: UTC, milliseconds.
    static func isoUTC(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    /// Cal.com's times ("2026-09-28T19:00:00.000+05:30"), with or without
    /// the fraction.
    static func parseTime(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    // MARK: Cal.com

    private static func json(_ data: Data) -> Any? { try? JSONSerialization.jsonObject(with: data) }

    /// A GET on Cal.com's API: the body, or the status it failed with
    /// (0 when nothing came back).
    private static func calGet(_ api: String, _ path: String, version: String, http: HTTP) -> (body: Any?, status: Int) {
        guard let r = try? http("GET", api + path, ["cal-api-version": version, "accept": "application/json"], nil)
        else { return (nil, 0) }
        guard (200..<300).contains(r.status), let body = json(r.body) else { return (nil, r.status) }
        return (body, 200)
    }

    private struct EventType { let slug: String; let title: String?; let length: Int?; let bookingUrl: String? }

    /// The event to book on a link with no event in it ("cal.com/jane"): the
    /// shortest one that is shown. `.unreachable` when Cal.com didn't answer.
    private static func firstEventType(_ link: Link, api: String, http: HTTP) -> Outcome<EventType?> {
        var q = [("username", link.username)]
        if let org = link.org { q.append(("organizationSlug", org)) }
        let (body, status) = calGet(api, "/event-types?\(form(q))", version: "2026-06-12", http: http)
        guard status == 200 else { return .unreachable }
        let data = ((body as? [String: Any])?["data"] as? [[String: Any]]) ?? []
        let shown = data.enumerated().compactMap { pair -> (Int, Int, EventType)? in
            let (i, t) = pair
            guard let slug = t["slug"] as? String, !slug.isEmpty, !truthy(t["hidden"]) else { return nil }
            let length = (t["lengthInMinutes"] as? NSNumber)?.intValue
            return (length ?? 999, i, EventType(slug: slug, title: t["title"] as? String, length: length,
                                                bookingUrl: t["bookingUrl"] as? String))
        }.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
        return .ok(shown.first?.2)
    }

    private static func truthy(_ v: Any?) -> Bool {
        switch v {
        case nil, is NSNull: return false
        case let n as NSNumber: return n.boolValue
        case let s as String: return !s.isEmpty
        default: return true
        }
    }

    /// Open times on a link from `date` for `days` days, in `tz`, each with
    /// a link that opens straight on that slot (GET /scheduling/slots).
    static func slots(link raw: String, date: String, days: Int = 3, tz: String,
                      api: String = defaultAPI, http: HTTP) -> Outcome<Slots> {
        guard let link = parse(raw) else { return .refused("That isn't a Cal.com or Calendly link") }
        let days = min(max(days, 1), 7)
        let tz = TimeZone(identifier: tz) != nil ? tz : "UTC"
        if link.provider == "calendly" {
            // Times need the host's Calendly sign-in; the day itself does not.
            return .ok(Slots(provider: "calendly", link: link.base, bookingUrl: bookingUrl(link, date: date),
                             title: nil, length: nil, days: []))
        }
        var full = link
        var title: String?
        var length: Int?
        if link.slug == nil {
            guard case .ok(let found) = firstEventType(link, api: api, http: http) else { return .unreachable }
            guard let type = found else { return .refused("No bookable event on that Cal.com link") }
            full.slug = type.slug
            title = type.title
            length = type.length
            // Cal.com's own page for it: a bare username can be someone in
            // an organisation, whose page lives on the organisation's host.
            let own = type.bookingUrl.flatMap(parse)
            full.base = own?.provider == "calcom" && own?.slug != nil ? own!.base
                : "\(link.base.hasSuffix("/") ? String(link.base.dropLast()) : link.base)/\(type.slug)"
        }
        // A day earlier than asked, so a zone ahead of UTC keeps its morning.
        var q = [("eventTypeSlug", full.slug ?? ""), ("username", link.username),
                 ("start", addDays(date, -1)), ("end", addDays(date, days)), ("timeZone", tz)]
        if let org = link.org { q.append(("organizationSlug", org)) }
        let (body, status) = calGet(api, "/slots?\(form(q))", version: "2024-09-04", http: http)
        if status == 404 { return .refused("Cal.com doesn't know that link") }
        guard status == 200 else { return .unreachable }
        let last = addDays(date, days)
        let data = (body as? [String: Any])?["data"] as? [String: Any] ?? [:]
        var out: [(date: String, slots: [(start: String, url: String)])] = []
        for d in data.keys.filter({ $0 >= date && $0 < last }).sorted() {
            let list = (data[d] as? [[String: Any]] ?? []).prefix(24)
            var slots: [(start: String, url: String)] = []
            for s in list {
                guard let start = s["start"] as? String, let at = parseTime(start) else { return .unreachable }
                slots.append((start, bookingUrl(full, date: d, slotUtc: isoUTC(at))))
            }
            out.append((d, slots))
        }
        return .ok(Slots(provider: "calcom", link: full.base, bookingUrl: bookingUrl(full, date: date),
                         title: title, length: length, days: out))
    }

    // MARK: Booking

    /// zod's email check, which the server runs on every address.
    private static let email = try! NSRegularExpression(
        pattern: "^(?!\\.)(?!.*\\.\\.)([A-Za-z0-9_'+\\-\\.]*)[A-Za-z0-9_+-]@([A-Za-z0-9][A-Za-z0-9\\-]*\\.)+[A-Za-z]{2,}$")

    static func isEmail(_ s: String) -> Bool {
        email.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    /// What Cal.com said, when it said something a person can act on.
    static func calMessage(_ body: Any?) -> String {
        guard let b = body as? [String: Any] else { return "" }
        let m: Any?
        if let e = b["error"], e is [String: Any] || e is NSNull || e is [Any] {
            m = (e as? [String: Any])?["message"]
        } else {
            m = b["error"] ?? b["message"]
        }
        if let s = m as? String { return s }
        if let list = m as? [Any] { return list.map { "\($0)" }.joined(separator: ", ") }
        return ""
    }

    /// Books a time on a Cal.com page with the attendee's name and email
    /// and any guests', the way Cal.com's own page does, and Cal.com emails
    /// everyone the invite (POST /scheduling/book).
    static func book(link raw: String, start: Date, name rawName: String, email rawEmail: String,
                     guests rawGuests: [String], tz: String, notes: String? = nil,
                     api: String = defaultAPI, http: HTTP) -> Outcome<Booked> {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let guests = rawGuests.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let badEmail = !isEmail(email) || email.utf16.count > 200 || guests.count > 10
            || guests.contains { !isEmail($0) || $0.utf16.count > 200 }
        if badEmail { return .refused("Check the email addresses") }
        if name.isEmpty || name.utf16.count > 120 || raw.utf16.count < 3 || raw.utf16.count > 300
            || tz.utf16.count > 64 || (notes?.utf16.count ?? 0) > 500 { return .refused("Bad request") }
        guard let link = parse(raw) else { return .refused("That isn't a Cal.com or Calendly link") }
        if link.provider != "calcom" {
            return .refused("Calendly books only on its own page. Send the link instead")
        }
        let tz = TimeZone(identifier: tz) != nil ? tz : "UTC"
        var slug = link.slug
        if slug == nil {
            guard case .ok(let found) = firstEventType(link, api: api, http: http) else { return .unreachable }
            guard let type = found else { return .refused("No bookable event on that Cal.com link") }
            slug = type.slug
        }
        let startISO = isoUTC(start)
        var body: [String: Any] = [
            "start": startISO,
            "eventTypeSlug": slug ?? "",
            "username": link.username,
            "attendee": ["name": name, "email": email, "timeZone": tz],
        ]
        if let org = link.org { body["organizationSlug"] = org }
        if !guests.isEmpty {
            var seen = Set<String>()
            body["guests"] = guests.map { $0.lowercased() }.filter { seen.insert($0).inserted }
                .filter { $0 != email.lowercased() }
        }
        if let notes, !notes.isEmpty { body["bookingFieldsResponses"] = ["notes": notes] }
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return .refused("Bad request") }
        let r: Response
        do {
            r = try http("POST", api + "/bookings", ["cal-api-version": "2026-02-25", "content-type": "application/json",
                                                     "accept": "application/json"], payload)
        } catch is NotSent {
            return .unreachable
        } catch {
            return .refused("Cal.com didn't answer. Try again")
        }
        let out = json(r.body) as? [String: Any]
        guard (200..<300).contains(r.status) else {
            // Turned away for asking too often: nothing was booked, so the
            // server may ask from where it is.
            if r.status == 429 { return .unreachable }
            let said = calMessage(out)
            if said.range(of: "available|booked|already|slot", options: [.regularExpression, .caseInsensitive]) != nil {
                return .refused("That time was just taken. Pick another")
            }
            if said.range(of: "authenticat|owner|admin", options: [.regularExpression, .caseInsensitive]) != nil {
                return .refused("This page only takes bookings on Cal.com itself. Send the link instead")
            }
            return .refused(said.isEmpty ? "Cal.com couldn't book it. Try again" : "Cal.com said: \(said)")
        }
        let d = out?["data"] as? [String: Any] ?? [:]
        func str(_ v: Any?) -> String? { v as? String }
        return .ok(Booked(uid: str(d["uid"]), start: str(d["start"]) ?? startISO, end: str(d["end"]),
                          title: str(d["title"]), meetingUrl: str(d["meetingUrl"]) ?? str(d["location"]),
                          invited: [email] + guests))
    }
}
