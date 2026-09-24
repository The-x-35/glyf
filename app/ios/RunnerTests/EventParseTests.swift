import XCTest

/// EventParse against a fixed morning: Wednesday 23 September 2026, 10:00 in
/// India. The Android twin (EventParseTest.kt) runs these same cases.
final class EventParseTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        c.locale = Locale(identifier: "en_US_POSIX")
        c.firstWeekday = 2
        return c
    }()

    private var now: Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 10, minute: 0))!
    }

    private func fmt(_ d: Date) -> String {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }

    /// "title | start – end | flags", flags: D (a day was named), T (a time), A (all day).
    private func read(_ text: String, dayFirst: Bool = true) -> String {
        let p = EventParse.parse(text, now: now, calendar: cal, dayFirst: dayFirst)
        let flags = (p.hasDay ? "D" : "") + (p.hasTime ? "T" : "") + (p.allDay ? "A" : "")
        return "\(p.title) | \(fmt(p.start)) – \(fmt(p.end)) | \(flags)"
    }

    func testDaysAndTimes() {
        XCTAssertEqual(read("Lunch with Sam tomorrow 1pm"), "Lunch with Sam | 2026-09-24 13:00 – 2026-09-24 14:00 | DT")
        XCTAssertEqual(read("call at 5"), "Call | 2026-09-23 17:00 – 2026-09-23 18:00 | T")
        XCTAssertEqual(read("standup at 9"), "Standup | 2026-09-24 09:00 – 2026-09-24 10:00 | T")
        XCTAssertEqual(read("dinner friday 8pm"), "Dinner | 2026-09-25 20:00 – 2026-09-25 21:00 | DT")
        XCTAssertEqual(read("let's meet tomorrow at 5"), "Meet | 2026-09-24 17:00 – 2026-09-24 18:00 | DT")
        XCTAssertEqual(read("let’s meet at 6"), "Meet | 2026-09-23 18:00 – 2026-09-23 19:00 | T")
        XCTAssertEqual(read("25 sep 3pm demo"), "Demo | 2026-09-25 15:00 – 2026-09-25 16:00 | DT")
        XCTAssertEqual(read("sep 30 at 4"), " | 2026-09-30 16:00 – 2026-09-30 17:00 | DT")
        XCTAssertEqual(read("meeting at 3:30"), "Meeting | 2026-09-23 15:30 – 2026-09-23 16:30 | T")
        XCTAssertEqual(read("5.30pm call"), "Call | 2026-09-23 17:30 – 2026-09-23 18:30 | T")
        XCTAssertEqual(read("17:00 sync"), "Sync | 2026-09-23 17:00 – 2026-09-23 18:00 | T")
        XCTAssertEqual(read("noon lunch"), "Lunch | 2026-09-23 12:00 – 2026-09-23 13:00 | T")
        XCTAssertEqual(read("midnight launch"), "Launch | 2026-09-24 00:00 – 2026-09-24 01:00 | DT")
        XCTAssertEqual(read("dinner at 8"), "Dinner | 2026-09-23 20:00 – 2026-09-23 21:00 | T")
        XCTAssertEqual(read("sync on the 30th at 11"), "Sync | 2026-09-30 11:00 – 2026-09-30 12:00 | DT")
        XCTAssertEqual(read("rent due the 5th"), "Rent due | 2026-10-05 09:00 – 2026-10-05 10:00 | D")
    }

    func testRangesDurationsAndRelative() {
        XCTAssertEqual(read("meeting 10:30-11:30am tomorrow"), "Meeting | 2026-09-24 10:30 – 2026-09-24 11:30 | DT")
        XCTAssertEqual(read("review 11-1pm on monday"), "Review | 2026-09-28 11:00 – 2026-09-28 13:00 | DT")
        XCTAssertEqual(read("from 5 to 7 party"), "Party | 2026-09-23 17:00 – 2026-09-23 19:00 | T")
        XCTAssertEqual(read("workshop tomorrow 10am for 2 hours"), "Workshop | 2026-09-24 10:00 – 2026-09-24 12:00 | DT")
        XCTAssertEqual(read("call in 30 mins"), "Call | 2026-09-23 10:30 – 2026-09-23 11:30 | DT")
        XCTAssertEqual(read("offsite all day friday"), "Offsite | 2026-09-25 00:00 – 2026-09-26 00:00 | DA")
    }

    func testPartsOfTheDayAndWeeks() {
        XCTAssertEqual(read("dinner tonight"), "Dinner | 2026-09-23 20:00 – 2026-09-23 21:00 | DT")
        XCTAssertEqual(read("tomorrow evening drinks"), "Drinks | 2026-09-24 18:00 – 2026-09-24 19:00 | DT")
        XCTAssertEqual(read("next friday coffee"), "Coffee | 2026-10-02 09:00 – 2026-10-02 10:00 | D")
        XCTAssertEqual(read("weekend trip"), "Trip | 2026-09-26 09:00 – 2026-09-26 10:00 | D")
        XCTAssertEqual(read("good morning! meeting at 5"), "Meeting | 2026-09-23 17:00 – 2026-09-23 18:00 | T")
        // A time of day with no day named is only how people talk.
        XCTAssertFalse(EventParse.parse("I slept late last night", now: now, calendar: cal).hasTime)
    }

    func testHinglish() {
        XCTAssertEqual(read("kal 5 baje milte hain"), "Milte hain | 2026-09-24 17:00 – 2026-09-24 18:00 | DT")
        XCTAssertEqual(read("parso 11 baje interview"), "Interview | 2026-09-25 11:00 – 2026-09-25 12:00 | DT")
        XCTAssertEqual(read("kal shaam 7 baje dinner"), "Dinner | 2026-09-24 19:00 – 2026-09-24 20:00 | DT")
    }

    func testNumericDatesFollowTheRegion() {
        XCTAssertEqual(read("25/12 christmas lunch"), "Christmas lunch | 2026-12-25 13:00 – 2026-12-25 14:00 | D")
        XCTAssertEqual(read("12/25 christmas lunch", dayFirst: false), "Christmas lunch | 2026-12-25 13:00 – 2026-12-25 14:00 | D")
    }

    func testNothingSaidIsTheNextHour() {
        XCTAssertEqual(read("Dentist"), "Dentist | 2026-09-23 11:00 – 2026-09-23 12:00 | ")
        XCTAssertEqual(read("at 5 people are coming"), "5 people are coming | 2026-09-23 11:00 – 2026-09-23 12:00 | ")
    }

    func testPeopleLine() {
        let a = EventParse.people("Sam Lee sam@x.com, Ria@Y.com")
        XCTAssertEqual(a.name, "Sam Lee")
        XCTAssertEqual(a.emails, ["sam@x.com", "ria@y.com"])
        XCTAssertEqual(EventParse.people("a@b.co a@b.co").emails, ["a@b.co"])
        XCTAssertEqual(EventParse.people("Just a name").emails, [])
        XCTAssertEqual(EventParse.people("<Arpit Singh> (arpit@gmail.com)").name, "Arpit Singh")
    }

    func testBookingPages() {
        XCTAssertEqual(Smart.bookingLink(in: "grab a slot: cal.com/sam/intro", own: nil), "cal.com/sam/intro")
        XCTAssertEqual(Smart.bookingLink(in: "book me here https://calendly.com/ria", own: nil), "https://calendly.com/ria")
        XCTAssertEqual(Smart.bookingLink(in: "physics.cal.com/rick/15min?x=1", own: nil), "physics.cal.com/rick/15min")
        XCTAssertNil(Smart.bookingLink(in: "mail sam@cal.com", own: nil))
        // The person's own page is theirs to send, not to book.
        XCTAssertNil(Smart.bookingLink(in: "cal.com/me/15min", own: "https://cal.com/me"))
        XCTAssertEqual(Smart.Chip.booking(link: "https://calendly.com/ria").value, "A time on calendly.com/ria")
        guard case .booking(let link)? = Smart.chip(for: "grab a slot: cal.com/sam/intro", fields: []) else {
            return XCTFail("no booking chip")
        }
        XCTAssertEqual(link, "cal.com/sam/intro")
    }

    func testWhatCountsAsAPlan() {
        let plan = { (t: String) in EventParse.looksLikePlan(t, now: self.now, calendar: self.cal) != nil }
        XCTAssertTrue(plan("let's grab coffee at 4"))
        XCTAssertTrue(plan("dinner friday 8pm?"))
        XCTAssertTrue(plan("call me tomorrow at 11"))
        XCTAssertTrue(plan("kal 5 baje milte hain"))
        XCTAssertFalse(plan("see you tomorrow"))
        XCTAssertFalse(plan("I woke up at 7"))
        XCTAssertFalse(plan("good morning"))
        XCTAssertFalse(plan("split is 3480/4"))
        XCTAssertFalse(plan("at 5 people are coming"))
        // What the calendar itself typed is already in the calendar.
        XCTAssertFalse(plan("📅 Lunch with Sam · Fri, Sep 25, 1:00–2:00 PM"))
        XCTAssertFalse(plan("I'm free Fri 25 Sep, 9:00 AM–1:00 PM and 3:00–9:00 PM"))
    }
}
