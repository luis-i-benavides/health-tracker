//
//  TodayCardsView.swift
//  health-tracker
//
//  Variant B — dashboard with a progress ring, a highlighted "next dose" card,
//  and grids of dose / measurement cards.
//

import SwiftUI

struct TodayCardsView: View {
    @Environment(HealthStore.self) private var store

    @State private var doseToLog: DoseSlot?
    @State private var isLoggingSymptom = false

    var body: some View {
        let doses = store.todaysDoses()
        let logged = doses.filter { $0.log != nil }.count
        let nextDose = doses.first { $0.log == nil }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    progressHeader(logged: logged, total: doses.count)

                    if let nextDose {
                        nextDoseCard(nextDose)
                    }

                    sectionTitle("All doses today")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        ForEach(doses) { slot in
                            Button {
                                doseToLog = slot
                            } label: {
                                doseCard(slot)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    sectionTitle("Measurements")
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(store.measurementReminders.filter(\.isEnabled)) { reminder in
                                measurementCard(reminder)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)

                    HStack {
                        sectionTitle("Symptoms")
                        Spacer()
                        Button("Log", systemImage: "plus") { isLoggingSymptom = true }
                            .buttonStyle(.glass)
                    }
                    ForEach(store.todaysSymptoms()) { log in
                        HStack(spacing: 12) {
                            Image(systemName: log.type.symbol)
                                .font(.title3)
                                .foregroundStyle(log.severity.color)
                                .frame(width: 40, height: 40)
                                .background(log.severity.color.opacity(0.15), in: .circle)
                            VStack(alignment: .leading) {
                                Text(log.displayName).font(.headline)
                                Text(log.date, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            SeverityBadge(severity: log.severity)
                        }
                        .cardStyle()
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .sheet(item: $doseToLog) { slot in
                LogMedicationCardView(medication: slot.medication, scheduledTime: slot.time)
            }
            .sheet(isPresented: $isLoggingSymptom) {
                LogSymptomCardView()
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
    }

    private func progressHeader(logged: Int, total: Int) -> some View {
        let fraction = total == 0 ? 0 : Double(logged) / Double(total)
        return HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(.tint.opacity(0.2), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.headline)
            }
            .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 4) {
                Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(logged) of \(total) doses")
                    .font(.title2.bold())
                Text(logged == total ? "All done for today 🎉" : "Keep it up")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .cardStyle()
    }

    private func nextDoseCard(_ slot: DoseSlot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(slot.isOverdue() ? "Overdue" : "Up next", systemImage: "bell.fill")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(slot.isOverdue() ? .red : .accentColor)
            HStack(alignment: .firstTextBaseline) {
                Text(slot.medication.name)
                    .font(.title.bold())
                Spacer()
                Text(slot.time.displayText)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Text(slot.medication.displayDosage)
                .foregroundStyle(.secondary)
            Button {
                doseToLog = slot
            } label: {
                Text("Log Dose")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
        }
        .cardStyle()
    }

    private func doseCard(_ slot: DoseSlot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "pills.fill")
                    .foregroundStyle(.tint)
                Spacer()
                Text(slot.time.displayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(slot.medication.name)
                .font(.headline)
            Text(slot.medication.displayDosage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            DoseStatusLabel(slot: slot)
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: .rect(cornerRadius: 16))
    }

    private func measurementCard(_ reminder: MeasurementReminder) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: reminder.kind.symbol)
                .font(.title2)
                .foregroundStyle(reminder.kind.color)
            Text(reminder.kind.label)
                .font(.headline)
            Text(reminder.times.map(\.displayText).formatted(.list(type: .and)))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 150, alignment: .leading)
        .padding()
        .background(.background, in: .rect(cornerRadius: 16))
    }
}

#Preview("Today – Cards") {
    TodayCardsView()
        .environment(HealthStore.preview)
}
