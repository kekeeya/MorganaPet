//
//  CalendarCityPicker.swift
//  Mona
//

import SwiftUI

/// Picks where the weather comes from.
///
/// A row showing the current choice; clicking it opens a popover whose *first*
/// element is a real search field, cursor already in it. A plain pop-up menu
/// would have hidden the fact that anything is searchable at all, and the list
/// it would have to hold is thirty-four thousand long.
///
/// Nothing here is a network call: the table ships in the bundle, so results
/// land on the keystroke.
struct CalendarCityPicker: View {
    @Binding var raw: String
    @State private var open = false
    @State private var query = ""
    @FocusState private var searching: Bool

    private var current: CalendarChoice { CalendarChoice.decode(raw) }

    var body: some View {
        LabeledContent("城市") {
            Button {
                open = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    // Just the name. The province and country are in the results
                    // list to tell two Portlands apart; once one is chosen it is
                    // simply "波特兰".
                    Text(current.name)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $open, arrowEdge: .bottom) {
                popover
            }
        }
    }

    private var popover: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索城市", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searching)
                    .onSubmit { if let first = results.first { choose(first) } }
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if query.isEmpty {
                        row(title: CalendarCity.current.name, detail: "跟随系统",
                            selected: isHere) { choose(.here) }
                        ForEach(CalendarCity.all) { city in
                            row(title: city.name, detail: "",
                                selected: current.name == city.name) {
                                choose(.fixed(name: city.name,
                                              latitude: city.latitude,
                                              longitude: city.longitude))
                            }
                        }
                    } else if results.isEmpty {
                        Text("没有找到「\(query)」")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(results) { place in
                            row(title: place.name, detail: place.detail,
                                selected: false) { choose(place) }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 260)
        }
        .frame(width: 300)
        .onAppear { searching = true }
    }

    private var results: [CalendarPlace] { CalendarPlaceTable.search(query) }

    private var isHere: Bool {
        if case .here = current { return true }
        return false
    }

    private func row(title: String, detail: String, selected: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if selected {
                    Image(systemName: "checkmark").font(.caption)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func choose(_ place: CalendarPlace) {
        choose(.fixed(name: place.name, latitude: place.latitude,
                      longitude: place.longitude))
    }

    private func choose(_ choice: CalendarChoice) {
        switch choice {
        case .here:
            raw = CalendarCity.currentID
        case .fixed(let name, let lat, let lon):
            raw = CalendarChoice.encode(name, lat, lon)
        }
        query = ""
        open = false
    }
}
