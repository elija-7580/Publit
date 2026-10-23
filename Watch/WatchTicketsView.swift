import SwiftUI
import UIKit
import WatchKit

/// All tickets the iPhone sent, grouped like in the Tickets tab: valid now, upcoming, without dates, expired.
struct WatchTicketsView: View {
    @Environment(WatchLibrary.self) private var library

    var body: some View {
        TimelineView(.everyMinute) { context in
            let snap = library.snapshot
            let now = context.date
            List {
                if !snap.ticketsOn {
                    WatchMessage(symbol: "applewatch.slash", text: "Tickets on the watch are turned off in the Publit settings on your iPhone.")
                        .listRowBackground(Color.clear)
                } else if snap.tickets.isEmpty {
                    if library.lastSync == nil {
                        WatchMessage(symbol: "iphone.gen3.radiowaves.left.and.right", text: "Open Publit on your iPhone once to bring your tickets here.")
                            .listRowBackground(Color.clear)
                    } else {
                        WatchMessage(symbol: "ticket", text: "No tickets on the watch")
                            .listRowBackground(Color.clear)
                    }
                }
                ForEach(PassGroup.grouped(snap.tickets.map(\.pass), at: now), id: \.group) { section in
                    Section(section.group.title) {
                        ForEach(section.passes) { pass in
                            NavigationLink(value: WatchRoute.ticket(pass.id)) {
                                WatchTicketRow(pass: pass, now: now)
                            }
                        }
                    }
                }
                if let synced = library.lastSync {
                    Text(L10n.f("Updated %@", Fmt.time(synced)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle(Text("Tickets"))
    }
}

/// A ticket in a list: its symbol in the ticket's colour, the title and how long it is valid.
struct WatchTicketRow: View {
    let pass: TicketPass
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: pass.symbol.systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(hex: pass.style.foreground) ?? .white)
                .frame(width: 28, height: 28)
                .background(Color(hex: pass.style.background) ?? .gray, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: pass.displayTitle).font(.headline).lineLimit(2)
                if let validity = WatchTicketText.validity(pass, now: now) {
                    Text(verbatim: validity.text).font(.caption2).foregroundStyle(validity.color).lineLimit(2)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

enum WatchTicketText {
    /// "Valid until 23:59", "Valid from …", "Expired"; nothing when the ticket has no dates.
    static func validity(_ pass: TicketPass, now: Date) -> (text: String, color: Color)? {
        switch pass.validity(at: now) {
        case .valid(let until):
            return (until.map { L10n.f("Valid until %@", PassFormat.date($0, end: true)) } ?? L10n.t("Valid now"), Color.live)
        case .upcoming(let from):
            return (L10n.f("Valid from %@", PassFormat.date(from, end: false)), Color.secondary)
        case .expired:
            return (L10n.t("Expired"), Color.danger)
        case .unknown:
            return nil
        }
    }
}

/// One ticket: its code as large as the screen allows, white like on a paper ticket, then what it says.
struct WatchTicketView: View {
    let ticketId: String
    @Environment(WatchLibrary.self) private var library

    var body: some View {
        if let ticket = library.snapshot.ticket(ticketId) {
            ScrollView {
                VStack(spacing: 8) {
                    WatchCodeView(ticket: ticket)
                    TimelineView(.everyMinute) { context in
                        WatchTicketDetails(pass: ticket.pass, now: context.date)
                    }
                }
            }
            .navigationTitle(Text("Tickets"))
        } else {
            WatchMessage(symbol: "ticket", text: "Ticket not found")
        }
    }
}

/// The picture of the code the iPhone drew, shown pixel for pixel.
struct WatchCodeView: View {
    let ticket: WatchTicket
    @Environment(WatchLibrary.self) private var library

    var body: some View {
        // Draws again when a picture arrives.
        let _ = library.codeVersion
        if ticket.pass.barcode == nil {
            WatchMessage(symbol: "qrcode", text: "This ticket has no code.")
        } else if let url = library.codeURL(for: ticket), let image = UIImage(contentsOfFile: url.path) {
            let device = WKInterfaceDevice.current()
            // One image pixel is one screen pixel: modules stay sharp and the scanner reads them.
            let natural = image.size.width * image.scale / device.screenScale
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
                .frame(width: min(natural, device.screenBounds.width - 4))
                .accessibilityLabel(Text("Ticket code"))
                .accessibilityIdentifier("ticketCode")
        } else if library.snapshot.ticketsOn {
            VStack(spacing: 6) {
                ProgressView()
                Text("The code is on its way from your iPhone.").font(.footnote).multilineTextAlignment(.center)
            }
            .padding()
        } else {
            WatchMessage(symbol: "iphone", text: "Open this ticket on your iPhone.")
        }
    }
}

/// Title, validity, route, passenger and reference of a ticket.
struct WatchTicketDetails: View {
    let pass: TicketPass
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: pass.displayTitle).font(.headline)
            if let name = pass.operatorName, name != pass.displayTitle {
                Text(verbatim: name).font(.caption2).foregroundStyle(.secondary)
            }
            if let validity = WatchTicketText.validity(pass, now: now) {
                Text(verbatim: validity.text).font(.footnote.weight(.semibold)).foregroundStyle(validity.color)
            }
            if pass.hasRoute, let origin = pass.origin, let destination = pass.destination {
                Text(verbatim: "\(origin) → \(destination)").font(.footnote)
            }
            if let via = pass.via { Text(verbatim: via).font(.caption2).foregroundStyle(.secondary) }
            if let passenger = pass.passenger { Text(verbatim: passenger).font(.footnote) }
            if let travelClass = pass.travelClassText { Text(verbatim: travelClass).font(.caption2).foregroundStyle(.secondary) }
            if let reference = pass.reference {
                Text(verbatim: reference).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
            }
            if let alt = pass.barcode?.altText, alt != pass.reference {
                Text(verbatim: alt).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}
