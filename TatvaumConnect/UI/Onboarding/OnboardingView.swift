import SwiftUI

struct OnboardingView: View {
    let profileStore: ProfileStore
    let pincodes: PincodeGeoService
    let cities: CitySearch

    private enum PlaceMode: String, CaseIterable { case city = "Search city", pin = "India PIN code" }
    enum SheetKind: Identifiable { case date, time; var id: Self { self } }
    private struct Birthplace { let label: String; let lat: Double; let lon: Double; let tz: String }

    @State private var name = ""
    @State private var preferredName = ""
    @State private var gender = "Male"
    @State private var date: Date?
    @State private var time: Date?
    @State private var mode = PlaceMode.city
    @State private var pincode = ""
    @State private var cityQuery = ""
    @State private var city: City?
    @State private var sheet: SheetKind?
    @FocusState private var focused: Bool

    init(profileStore: ProfileStore, pincodes: PincodeGeoService, cities: CitySearch) {
        self.profileStore = profileStore; self.pincodes = pincodes; self.cities = cities
    }

    private var pinPlace: PincodePlace? { pincodes.isReady && pincode.count == 6 ? pincodes.resolve(pincode) : nil }
    private var birthplace: Birthplace? {
        switch mode {
        case .city: city.map { Birthplace(label: $0.label, lat: $0.latitude, lon: $0.longitude, tz: $0.timezone) }
        // The PIN dataset covers India, so a resolved PIN always means IST.
        case .pin: pinPlace.map { Birthplace(label: $0.name, lat: $0.latitude, lon: $0.longitude, tz: "Asia/Kolkata") }
        }
    }
    private var canContinue: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && date != nil && time != nil && birthplace != nil }

    var body: some View {
        CosmicBackground {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        Text("✦").font(.system(size: 48)).foregroundStyle(Cosmic.gold)
                            .phaseAnimator([-5.0, 5.0]) { $0.offset(y: $1) } animation: { _ in .easeInOut(duration: 2.4) }
                        CosmicTitle(lead: "Welcome to", accent: "Tatvaum", size: 26)
                        Subtitle("Tell us when and where you were born, and we'll reveal the sky that was waiting for you.")
                            .multilineTextAlignment(.center).padding(.horizontal, 8)
                    }
                    GlassPanel { form }
                    privacyNote
                    PrimaryButton(text: "Reveal my sky ✦", enabled: canContinue, action: submit)
                }
                .padding(.horizontal, 24).padding(.vertical, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sheet(item: $sheet) { s in
            PickerSheet(kind: s, date: $date, time: $time).presentationDetents([s == .date ? .large : .height(320)])
        }
    }

    @ViewBuilder private var form: some View {
        field("Full name", text: $name, prompt: "", caps: .words)
        field("What should we call you?", text: $preferredName, prompt: "Optional", caps: .words)
        Picker("Gender", selection: $gender) { ForEach(["Male", "Female", "Other"], id: \.self, content: Text.init) }.pickerStyle(.segmented)
        pickerRow("Date of birth", date?.formatted(date: .long, time: .omitted), "calendar", .date)
        pickerRow("Time of birth", time?.formatted(date: .omitted, time: .shortened), "clock", .time)

        FieldLabel("Place of birth").padding(.top, 4)
        Picker("Place", selection: $mode) { ForEach(PlaceMode.allCases, id: \.self) { Text($0.rawValue) } }.pickerStyle(.segmented)
        if mode == .city { cityField } else { pinField }
    }

    private var suggestions: [City] {
        !cities.isReady || city?.label == cityQuery ? [] : cities.search(cityQuery)
    }

    @ViewBuilder private var cityField: some View {
        let list = suggestions
        field("City or town (e.g. Hyderabad)", text: Binding(get: { cityQuery }, set: { cityQuery = $0; if city?.label != $0 { city = nil } }),
              prompt: "e.g. Hyderabad", caps: .words, submit: .search,
              trailing: !cities.isReady ? AnyView(ProgressView()) : city != nil ? AnyView(check) : nil,
              help: city.map { String(format: "%.4f, %.4f · %@", $0.latitude, $0.longitude, $0.timezone.replacingOccurrences(of: "_", with: " ")) }
                ?? (cities.isReady && cityQuery.trimmingCharacters(in: .whitespaces).count >= 2 && list.isEmpty
                    ? "No match. Try the nearest larger town, or add the country (\"Paris, France\")."
                    : "Used to calculate your birth chart and local birth time"))
        if !list.isEmpty {
            VStack(spacing: 0) {
                ForEach(list, id: \.self) { c in
                    Button { city = c; cityQuery = c.label; focused = false } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.circle.fill").foregroundStyle(Cosmic.gold)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Cosmic.starText)
                                Text(([c.region, c.country].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                                    .joined(separator: ", ")) + " · " + c.timezone.replacingOccurrences(of: "_", with: " "))
                                    .font(.system(size: 12)).foregroundStyle(Cosmic.muted)
                            }
                            Spacer(minLength: 0)
                        }.padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            .background(Color(argb: 0xF0121430), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Cosmic.panelBorder))
        }
    }

    private var check: some View { Image(systemName: "checkmark.circle.fill").foregroundStyle(Cosmic.success) }

    @ViewBuilder private var pinField: some View {
        let place = pinPlace
        field("Place of birth (PIN code)", text: Binding(get: { pincode }, set: { pincode = String($0.filter(\.isASCII).filter(\.isNumber).prefix(6)) }),
              prompt: "6-digit PIN code", keyboard: .numberPad,
              error: pincodes.isReady && pincode.count == 6 && place == nil,
              trailing: !pincodes.isReady ? AnyView(ProgressView()) : place != nil ? AnyView(check) : nil,
              help: place.map { "\($0.name) · India Standard Time" }
                ?? (pincodes.isReady && pincode.count == 6 ? "PIN code not found" : "Used to calculate your birth chart"))
    }

    private func field(_ label: String, text: Binding<String>, prompt: String, caps: TextInputAutocapitalization = .never,
                       keyboard: UIKeyboardType = .default, submit: SubmitLabel = .next, error: Bool = false,
                       trailing: AnyView? = nil, help: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            FieldLabel(label)
            HStack {
                TextField("", text: text, prompt: Text(prompt).foregroundColor(Cosmic.faint))
                    .textInputAutocapitalization(caps).keyboardType(keyboard).submitLabel(submit).autocorrectionDisabled()
                    .focused($focused).foregroundStyle(Cosmic.starText).tint(Cosmic.gold)
                trailing
            }
            .padding(.horizontal, 14).frame(height: 50)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(error ? Cosmic.error : Cosmic.panelBorder))
            if let help { Note(help).foregroundStyle(error ? Cosmic.error : Cosmic.faint) }
        }
    }

    private func pickerRow(_ label: String, _ value: String?, _ icon: String, _ s: SheetKind) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            FieldLabel(label)
            Button { focused = false; sheet = s } label: {
                HStack {
                    Text(value ?? "Tap to choose").foregroundStyle(value == nil ? Cosmic.faint : Cosmic.starText)
                    Spacer(); Image(systemName: icon).foregroundStyle(Cosmic.muted)
                }
                .padding(.horizontal, 14).frame(height: 50).contentShape(Rectangle())
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Cosmic.panelBorder))
            }.buttonStyle(.plain)
        }
    }

    /// Plain statement of where the person's data goes (stored on-device, shared only with Gemini).
    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill").font(.system(size: 15)).foregroundStyle(Cosmic.gold)
            VStack(alignment: .leading, spacing: 3) {
                Text("Private by design").font(.system(size: 13, weight: .semibold)).foregroundStyle(Cosmic.starText)
                Text("Your details are stored only on this device. There is no Tatvaum account or server.")
                    .font(.system(size: 12)).foregroundStyle(Cosmic.muted).lineSpacing(3)
            }
            Spacer(minLength: 0)
        }
        .padding(14).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Cosmic.panelBorder))
    }

    private func submit() {
        guard let p = birthplace, let date, let time else { return }
        // Picked in the device zone; hand the store the same wall-clock components in the birth zone.
        let dev = Calendar.current
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: p.tz) ?? .current
        let d = dev.dateComponents([.year, .month, .day], from: date), t = dev.dateComponents([.hour, .minute], from: time)
        let birth = DateComponents(year: d.year, month: d.month, day: d.day, hour: t.hour, minute: t.minute)
        guard let moment = cal.date(from: birth) else { return }
        profileStore.completeOnboarding(name: name.trimmingCharacters(in: .whitespaces),
                                        preferredName: preferredName.trimmingCharacters(in: .whitespaces), gender: gender,
                                        dateOfBirth: moment, timeOfBirth: moment, timezone: p.tz, placeOfBirth: p.label,
                                        latitude: p.lat, longitude: p.lon)
    }
}

private struct PickerSheet: View {
    let kind: OnboardingView.SheetKind
    @Binding var date: Date?
    @Binding var time: Date?
    @Environment(\.dismiss) private var dismiss
    @State private var value = Date()

    var body: some View {
        VStack(spacing: 12) {
            Text(kind == .date ? "Date of birth" : "Time of birth").font(.headline)
            if kind == .date {
                DatePicker("", selection: $value, in: ...Date(), displayedComponents: .date).datePickerStyle(.graphical)
            } else {
                DatePicker("", selection: $value, displayedComponents: .hourAndMinute).datePickerStyle(.wheel).labelsHidden()
            }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("OK") { if kind == .date { date = value } else { time = value }; dismiss() }.fontWeight(.semibold)
            }
        }
        .padding().tint(Cosmic.gold).preferredColorScheme(.dark)
        .onAppear {
            let cal = Calendar.current
            value = (kind == .date ? date : time)
                ?? (kind == .date ? cal.date(byAdding: .year, value: -25, to: Date())! : cal.date(bySettingHour: 6, minute: 0, second: 0, of: Date())!)
        }
    }
}
