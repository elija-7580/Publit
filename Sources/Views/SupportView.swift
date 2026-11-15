import SwiftUI
import StoreKit

/// Support Publit: monthly support first, one-time tips below. Nothing is unlocked by it.
struct SupportView: View {
    @State private var store = SupportStore.shared
    @State private var manage = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "heart.fill").font(.largeTitle).foregroundStyle(Color.signature)
                        .accessibilityHidden(true)
                    Text("Support Publit").font(.title2.weight(.bold))
                    Text("Publit has no ads and no tracking. Your support pays for servers and keeps development going.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }

            if store.thanked || store.activeMonthly != nil {
                Section {
                    Label {
                        if let active = store.activeMonthly {
                            Text(L10n.f("Thank you! You support Publit with %@ a month.", active.displayPrice))
                        } else {
                            Text("Thank you for supporting Publit!")
                        }
                    } icon: { Image(systemName: "heart.circle.fill").foregroundStyle(Color.signature) }
                    .font(.subheadline.weight(.semibold))
                    if store.activeMonthly != nil {
                        Button("Manage subscription") { manage = true }
                    }
                }
            }

            if !store.loaded {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            } else if store.monthly.isEmpty && store.oneTime.isEmpty {
                Section {
                    Text("Support is not available right now.").foregroundStyle(.secondary)
                    Button("Try again") { Task { await store.load() } }
                }
            } else {
                if !store.monthly.isEmpty {
                    Section {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                            ForEach(store.monthly, id: \.id) { product in
                                amountButton(product, monthly: true)
                            }
                        }
                        .padding(.vertical, 6)
                    } header: {
                        Text("Monthly")
                    } footer: {
                        Text("Monthly support renews every month until you cancel it. Cancel it any time in your App Store account.")
                    }
                }
                if !store.oneTime.isEmpty {
                    Section {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
                            ForEach(store.oneTime, id: \.id) { product in
                                amountButton(product, monthly: false)
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("One-time")
                    }
                }
            }

            Section {
                Button("Restore purchases") { Task { await store.restore() } }
                Link("Terms of use", destination: AppInfo.termsURL)
                Link("Privacy policy", destination: AppInfo.privacyURL)
            } footer: {
                Text("Support unlocks nothing: every feature stays free for everyone.")
            }
        }
        .readableWidth()
        .inkList()
        .navigationTitle("Support Publit")
        .navigationBarTitleDisplayMode(.inline)
        .screenTrail("Support")
        .manageSubscriptionsSheet(isPresented: $manage)
        .task { if !store.loaded { await store.load() } }
    }

    private func amountButton(_ product: Product, monthly: Bool) -> some View {
        let cents = Support.parse(product.id)?.cents
        let suggested = monthly && cents == Support.suggestedMonthlyCents && store.activeMonthly == nil
        let active = store.activeMonthly?.id == product.id
        let busy = store.purchasing == product.id
        return Button {
            Task { await store.buy(product) }
        } label: {
            VStack(spacing: 2) {
                if busy { ProgressView() } else {
                    Text(verbatim: product.displayPrice).font((monthly ? Font.headline : .subheadline.weight(.semibold)).monospacedDigit())
                }
                if monthly {
                    Text(active ? L10n.t("Active") : L10n.t("per month")).font(.caption2)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: monthly ? 56 : 44)
            .foregroundStyle(suggested || active ? Color.onInk : Color.ink)
            .background(suggested || active ? Color.ink : Color.inkFill,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(store.purchasing != nil || active)
        .accessibilityLabel(monthly ? L10n.f("%@ per month", product.displayPrice) : product.displayPrice)
        .accessibilityIdentifier(product.id)
    }
}
