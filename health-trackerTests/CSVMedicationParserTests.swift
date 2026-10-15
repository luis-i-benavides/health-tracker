//
//  CSVMedicationParserTests.swift
//  health-trackerTests
//

import Foundation
import Testing
@testable import health_tracker

@MainActor
struct CSVPrescriptionFormatTests {
    private let calendar = Calendar(identifier: .gregorian)
    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 15))! }

    private func t(_ hour: Int, _ minute: Int = 0) -> TimeOfDay { TimeOfDay(hour: hour, minute: minute) }

    private func parse(_ csv: String) -> CSVParseResult {
        CSVMedicationParser.parse(csv, today: today, calendar: calendar)
    }

    /// Parses one data row under the given header and returns the medication or the error message.
    private func row(_ header: String, _ row: String) -> (Medication?, String?) {
        let result = parse("\(header)\n\(row)")
        return (result.medications.first, result.errors.first?.message)
    }

    @Test func parsesAFullRow() throws {
        let result = parse("""
        name,generic,strength,form,quantity,route,frequency,times,food,duration_days,start,purpose
        Amoxil,amoxicillin,500 mg,capsule,1,by mouth,TID,,with food;avoid alcohol,10,2026-10-16,infection
        """)
        #expect(result.format == .prescription)
        #expect(result.errors.isEmpty)
        let med = try #require(result.medications.first)
        #expect(med.name == "Amoxil")
        #expect(med.genericName == "amoxicillin")
        #expect(med.strength == Strength(value: 500, unit: "mg"))
        #expect(med.form == .capsule)
        #expect(med.quantity == 1)
        #expect(med.route == .byMouth)
        #expect(med.schedule == .daily(times: [t(8), t(14), t(20)]))
        #expect(med.foodRules == [.withFood, .avoidAlcohol])
        #expect(med.purpose == "infection")
        let course = try #require(med.course)
        #expect(course.days == 10)
        #expect(course.startDate == calendar.date(from: DateComponents(year: 2026, month: 10, day: 16)))
        // The medication starts with its course, so earlier days don't show it as missed.
        #expect(med.addedOn == course.startDate)
    }

    @Test func appliesDefaultsAndAcceptsAnyColumnOrder() throws {
        let result = parse("""
        frequency,strength,name
        once daily,10 mg,Lisinopril
        """)
        let med = try #require(result.medications.first)
        #expect(med.name == "Lisinopril")
        #expect(med.form == .tablet)
        #expect(med.quantity == 1)
        #expect(med.route == .byMouth)
        #expect(med.foodRules.isEmpty)
        #expect(med.course == nil)
        #expect(med.genericName == nil)
        #expect(med.addedOn == today)
    }

    @Test func allowsTrailingEmptyColumnsToBeOmitted() {
        let result = parse("""
        name,strength,frequency,food,purpose
        Lisinopril,10 mg,once daily
        """)
        #expect(result.errors.isEmpty)
        #expect(result.medications.count == 1)
    }

    @Test func handlesQuotedNamesWithCommas() throws {
        let result = parse("""
        name,strength,frequency
        "Vitamin D3, chewable",1000 IU,daily
        """)
        #expect(try #require(result.medications.first).name == "Vitamin D3, chewable")
    }

    @Test func dropsGenericNameThatMatchesName() throws {
        let (med, _) = row("name,generic,strength,frequency", "Metformin,metformin,500 mg,BID")
        #expect(try #require(med).genericName == nil)
    }

    // MARK: Frequency

    @Test(arguments: [
        ("once daily", [8]), ("QD", [8]), ("daily", [8]),
        ("twice daily", [8, 20]), ("BID", [8, 20]), ("b.i.d.", [8, 20]), ("twice a day", [8, 20]),
        ("TID", [8, 14, 20]), ("3 times a day", [8, 14, 20]), ("three times daily", [8, 14, 20]),
        ("QID", [8, 12, 16, 20]), ("4x daily", [8, 12, 16, 20]),
        ("every morning", [8]), ("QPM", [20]),
    ])
    func dailyFrequencies(frequency: String, hours: [Int]) throws {
        let (med, error) = row("name,strength,frequency", "Test,10 mg,\(frequency)")
        #expect(error == nil)
        #expect(try #require(med).schedule == .daily(times: hours.map { t($0) }))
    }

    @Test func everyNHours() throws {
        let (q8, _) = row("name,strength,frequency", "Test,10 mg,q8h")
        #expect(try #require(q8).schedule == .everyHours(interval: 8, firstDose: t(6)))
        #expect(try #require(q8).times == [t(6), t(14), t(22)])

        let (q12, _) = row("name,strength,frequency", "Test,10 mg,every 12 hours")
        #expect(try #require(q12).times == [t(8), t(20)])

        let (custom, _) = row("name,strength,frequency,times", "Test,10 mg,every 6 hours,00:00")
        #expect(try #require(custom).times == [t(0), t(6), t(12), t(18)])
    }

    @Test func everyNHoursMustDivide24() {
        let (_, error) = row("name,strength,frequency", "Test,10 mg,every 5 hours")
        #expect(error?.contains("divide evenly") == true)
    }

    @Test func bedtime() throws {
        let (med, _) = row("name,strength,frequency", "Test,10 mg,QHS")
        #expect(try #require(med).schedule == .atBedtime(t(22)))

        let (custom, _) = row("name,strength,frequency,times", "Test,10 mg,at bedtime,21:30")
        #expect(try #require(custom).schedule == .atBedtime(t(21, 30)))
    }

    @Test func weekdays() throws {
        let (med, _) = row("name,strength,frequency", "Alendronate,70 mg,Sun")
        #expect(try #require(med).schedule == .weekly(days: [.sunday], times: [t(8)]))

        let (multi, _) = row("name,strength,frequency,times", "Test,10 mg,Mon;Wed;Fri,09:00")
        #expect(try #require(multi).schedule == .weekly(days: [.monday, .wednesday, .friday], times: [t(9)]))

        let (phrased, _) = row("name,strength,frequency", "Test,10 mg,weekly on Tues/Thurs")
        #expect(try #require(phrased).schedule == .weekly(days: [.tuesday, .thursday], times: [t(8)]))
    }

    @Test func weeklyWithoutDaysIsAnError() {
        let (_, error) = row("name,strength,frequency", "Test,10 mg,weekly")
        #expect(error?.contains("needs the days") == true)
    }

    @Test func timesOverrideDefaults() throws {
        let (med, _) = row("name,strength,frequency,times", "Test,10 mg,twice daily,07:00;19:30")
        #expect(try #require(med).schedule == .daily(times: [t(7), t(19, 30)]))
    }

    @Test func timeCountMustMatchFrequency() {
        let (_, error) = row("name,strength,frequency,times", "Test,10 mg,twice daily,08:00;14:00;20:00")
        #expect(error == "“twice daily” needs 2 times, but 3 were given.")
    }

    @Test func moreThanFourDailyNeedsTimes() throws {
        let (_, error) = row("name,strength,frequency", "Test,10 mg,6 times daily")
        #expect(error?.hasPrefix("Give 6 times") == true)

        let (med, _) = row("name,strength,frequency,times", "Test,10 mg,6 times daily,06:00;09:00;12:00;15:00;18:00;21:00")
        #expect(try #require(med).times.count == 6)
    }

    @Test func invalidTimesAreReported() {
        let (_, error) = row("name,strength,frequency,times", "Test,10 mg,once daily,25:00")
        #expect(error == "Invalid time “25:00”. Use 24-hour HH:mm.")
    }

    @Test func unknownFrequency() {
        let (_, error) = row("name,strength,frequency", "Test,10 mg,whenever")
        #expect(error?.hasPrefix("Unknown frequency “whenever”") == true)
    }

    @Test func missingFrequency() {
        let (_, error) = row("name,strength,frequency", "Test,10 mg,")
        #expect(error?.hasPrefix("Frequency is required") == true)
    }

    // MARK: As needed

    @Test func asNeededWithLimits() throws {
        let (med, error) = row("name,strength,form,quantity,route,frequency,max_per_24h,min_hours_apart",
                               "Albuterol HFA,90 mcg,puff,2,inhaled,as needed,4,4")
        #expect(error == nil)
        #expect(try #require(med).schedule == .asNeeded(minHoursApart: 4, maxDosesPer24h: 4))
    }

    @Test func asNeededDefaultsToFourHoursApart() throws {
        let (med, _) = row("name,strength,frequency,max_per_24h", "Ibuprofen,200 mg,PRN,3")
        #expect(try #require(med).schedule == .asNeeded(minHoursApart: 4, maxDosesPer24h: 3))
    }

    @Test func asNeededRequiresMaximum() {
        let (_, error) = row("name,strength,frequency", "Ibuprofen,200 mg,as needed")
        #expect(error?.contains("need max_per_24h") == true)
    }

    @Test func asNeededRejectsScheduledTimes() {
        let (_, error) = row("name,strength,frequency,times,max_per_24h", "Ibuprofen,200 mg,as needed,08:00,3")
        #expect(error?.contains("don't have scheduled times") == true)
    }

    @Test func limitsOnlyApplyToAsNeeded() {
        let (_, maxError) = row("name,strength,frequency,max_per_24h", "Test,10 mg,once daily,3")
        #expect(maxError == "max_per_24h only applies to as-needed medications.")
        let (_, minError) = row("name,strength,frequency,min_hours_apart", "Test,10 mg,once daily,4")
        #expect(minError == "min_hours_apart only applies to as-needed medications.")
    }

    // MARK: Field validation

    @Test func strengthNeedsAUnit() {
        let (_, error) = row("name,strength,frequency", "Test,500,once daily")
        #expect(error == "Strength “500” needs a unit, e.g. 500 mg.")
    }

    @Test func strengthMustBeRecognized() {
        let (_, error) = row("name,strength,frequency", "Test,lots,once daily")
        #expect(error?.hasPrefix("Strength “lots” isn't recognized") == true)
    }

    @Test func nameIsRequired() {
        let (_, error) = row("name,strength,frequency", ",10 mg,once daily")
        #expect(error == "Medication name is empty.")
    }

    @Test(arguments: [("1/2", 0.5), ("½", 0.5), ("1 1/2", 1.5), ("1½", 1.5), (".5", 0.5), ("2", 2.0)])
    func quantities(text: String, expected: Double) throws {
        let (med, error) = row("name,strength,quantity,frequency", "Test,10 mg,\(text),once daily")
        #expect(error == nil)
        #expect(try #require(med).quantity == expected)
    }

    @Test(arguments: ["0", "-1", "two", "1/0"])
    func invalidQuantities(text: String) {
        let (_, error) = row("name,strength,quantity,frequency", "Test,10 mg,\(text),once daily")
        #expect(error?.hasPrefix("Quantity “\(text)” must be a positive number") == true)
    }

    @Test func unknownFormAndRoute() {
        let (_, formError) = row("name,strength,form,frequency", "Test,10 mg,blob,once daily")
        #expect(formError?.hasPrefix("Unknown form “blob”") == true)
        let (_, routeError) = row("name,strength,route,frequency", "Test,10 mg,telepathic,once daily")
        #expect(routeError?.hasPrefix("Unknown route “telepathic”") == true)
    }

    @Test func foodRules() {
        let (_, unknown) = row("name,strength,frequency,food", "Test,10 mg,once daily,with cake")
        #expect(unknown?.hasPrefix("Unknown food rule “with cake”") == true)
        let (_, conflict) = row("name,strength,frequency,food", "Test,10 mg,once daily,with food;empty stomach")
        #expect(conflict == "Food rules “with food” and “empty stomach” contradict each other.")
    }

    @Test func durationAndStartValidation() {
        let (_, duration) = row("name,strength,frequency,duration_days", "Test,10 mg,once daily,ten")
        #expect(duration?.hasPrefix("duration_days “ten”") == true)
        let (_, impossible) = row("name,strength,frequency,start", "Test,10 mg,once daily,2026-02-31")
        #expect(impossible == "Start date “2026-02-31” must be YYYY-MM-DD.")
        let (_, format) = row("name,strength,frequency,start", "Test,10 mg,once daily,10/16/2026")
        #expect(format == "Start date “10/16/2026” must be YYYY-MM-DD.")
    }

    // MARK: Header problems

    @Test func unknownColumnsAreReportedButRowsStillImport() throws {
        let result = parse("""
        name,strength,frequency,colour
        Lisinopril,10 mg,once daily,blue
        """)
        #expect(result.medications.count == 1)
        let error = try #require(result.errors.first)
        #expect(error.line == 1)
        #expect(error.message.hasPrefix("Unknown column “colour”"))
    }

    @Test func missingRequiredColumnStopsTheImport() {
        let result = parse("""
        name,form,frequency
        Lisinopril,tablet,once daily
        """)
        #expect(result.medications.isEmpty)
        #expect(result.errors.map(\.message) == ["Missing required column “strength”."])
    }

    @Test func tooManyColumns() {
        let (_, error) = row("name,strength,frequency", "Test,10 mg,once daily,extra")
        #expect(error == "Row has 4 columns but the header has 3.")
    }

    @Test func badRowsDoNotStopGoodRows() {
        let result = parse("""
        name,strength,frequency
        Good,10 mg,once daily

        Bad,10,once daily
        Also good,20 mg,BID
        """)
        #expect(result.medications.map(\.name) == ["Good", "Also good"])
        #expect(result.errors.map(\.line) == [4])
    }
}

@MainActor
struct CSVLegacyFormatTests {
    private func t(_ hour: Int, _ minute: Int = 0) -> TimeOfDay { TimeOfDay(hour: hour, minute: minute) }

    @Test func parsesWithHeader() throws {
        let result = CSVMedicationParser.parse("""
        name,dosage,unit,times
        Metformin,500,mg,08:00;20:00
        """)
        #expect(result.format == .legacy)
        #expect(result.errors.isEmpty)
        let med = try #require(result.medications.first)
        #expect(med.strength == Strength(value: 500, unit: "mg"))
        #expect(med.form == .tablet)
        #expect(med.route == .byMouth)
        #expect(med.schedule == .daily(times: [t(8), t(20)]))
    }

    @Test func parsesWithoutHeader() {
        let result = CSVMedicationParser.parse("Aspirin,81,mg,\"08:00; 20:00;08:00\"\r\n\r\n\"Fish \"\"Omega\"\" oil\",1,cap,7:30")
        #expect(result.format == .legacy)
        #expect(result.medications.map(\.name) == ["Aspirin", "Fish \"Omega\" oil"])
        #expect(result.medications.first?.times == [t(8), t(20)])   // duplicates removed
    }

    @Test func formUnitBecomesQuantity() throws {
        let result = CSVMedicationParser.parse("Notification Test,1,tablet,18:00")
        let med = try #require(result.medications.first)
        #expect(med.strength == nil)
        #expect(med.form == .tablet)
        #expect(med.quantity == 1)
    }

    @Test func reportsLegacyErrors() {
        let result = CSVMedicationParser.parse("""
        name,dosage,unit,times
        Atorvastatin,twenty,mg,21:30
        Aspirin,81,mg,25:00
        Ibuprofen,200,mg
        """)
        #expect(result.medications.isEmpty)
        #expect(result.errors.map(\.line) == [2, 3, 4])
        #expect(result.errors.map(\.message) == [
            "Dosage “twenty” is not a positive number.",
            "Invalid time “25:00”. Use 24-hour HH:mm.",
            "Expected 4 columns (name, dosage, unit, times) but found 3.",
        ])
    }

    @Test func emptyInput() {
        let result = CSVMedicationParser.parse("\n\n")
        #expect(result.medications.isEmpty)
        #expect(result.errors.isEmpty)
    }

    /// The sample file used in the simulator should keep importing cleanly.
    @Test func testDataFileImports() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "TestData/medications-test.csv")
        let text = try String(contentsOf: url, encoding: .utf8)
        let result = CSVMedicationParser.parse(text)
        #expect(result.errors.isEmpty)
        #expect(result.medications.count == 9)
    }
}
