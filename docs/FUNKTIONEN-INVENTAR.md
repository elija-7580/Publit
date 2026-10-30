# Funktions-Inventar (automatisch erzeugt)

> Nicht von Hand bearbeiten. Erzeugt von `scripts/feature_inventory.py` (CI: `features-doc.yml`).
> Die ausführliche Beschreibung steht in [FUNKTIONEN.md](FUNKTIONEN.md).

**172 Views, 5 App Intents, 3 Widgets in 69 Dateien.**

## `Sources/App/DesignSamples.swift`
- Views: `DesignSampleView`

## `Sources/App/PresentationSampleView.swift`
- Views: `PresentationSampleView`
- Sichtbare Texte: Departures · Alerts · Steps · Route · Trip · Active trip · Done

## `Sources/App/PublitApp.swift`
- Views: `RootView`, `AdaptiveTabs`
- Sichtbare Texte: Nearby · Plan · Tickets · Saved · Minimize · Done

## `Sources/Intents/PublitIntents.swift`
- Views: `DeparturesSnippet`
- App Intents: `NextDeparturesIntent`, `GoHomeIntent`, `GoToWorkIntent`, `ShowTicketIntent`
- Sichtbare Texte: Offline. Showing data from %@. · No departures from %@ in the next hour. · %@ to %@ · %@ is cancelled · %@ now · %@ in %lld min · At %@: %@.

## `Sources/Shared/DirectionLabel.swift`
- Views: `DirectionLabel`
- Sichtbare Texte: Towards · Circle line · Direction unavailable

## `Sources/Tickets/PassSamples.swift`
- Views: `PassSampleView`

## `Sources/Tickets/Views/AddToWalletButton.swift`
- Views: `AddToWalletButton`
- Sichtbare Texte: The Wallet pass could not be created.

## `Sources/Tickets/Views/LogoPickerView.swift`
- Views: `LogoPickerView`
- Sichtbare Texte: Operator · Search · No logo found. Try another name or choose an image. · Suggestions · Choose image · No logo · Logo · Cancel · Website icon

## `Sources/Tickets/Views/PassArchiveView.swift`
- Views: `PassArchiveView`
- Sichtbare Texte: No archived tickets · Expired tickets move here a day after they end. They stay on this iPhone until you delete them. · Archive · Delete all archived tickets? · Delete archived tickets · Their copies and originals are removed from this iPhone. · More

## `Sources/Tickets/Views/PassCardView.swift`
- Views: `PassCardView`, `ValidityBadge`, `BarcodeView`
- Sichtbare Texte: From · Type · Via · Valid from · Valid until · Passenger · Class · Price · Shows the code full screen. · %@ code · No code found. Show the original instead. · No code · Valid now · From %@ · Expired

## `Sources/Tickets/Views/PassDetailView.swift`
- Views: `PassDetailView`, `FullScreenCodeView`
- Sichtbare Texte: Ticket deleted · Expired on %@ · Show original · Notes · Edit · Delete · More · Ticket image unavailable · Original ticket · Done · Delete this ticket? · Delete ticket · The copy and its original are removed from this iPhone. · %@ code

## `Sources/Tickets/Views/PassEditorView.swift`
- Views: `PassEditorView`
- Sichtbare Texte: Preview: %@ · Read on your iPhone. Check every detail before you save. · Assign fields on the ticket · Ticket · Title · Operator · Type · Route · From · Via · Validity · Valid from · Valid until · Details · Passenger · Class · None · Class %@ · Price · Ticket number · Look · Symbol · Notes · Check ticket · Edit ticket · Cancel · Save · Ticket could not be saved · Logo · Remove logo · Operator logo · Suggested from Wikimedia Commons. Choose another if it is not the right one. · Code · No code · Remove code · Use the %@ code · No code found on this page. Publit shows the original instead. · This code is shown exactly as on the original ticket. · Apple Wallet cannot show %@ codes. Publit can. · Only codes that stay the same work here. Codes that change every few seconds only work in the operator's app. · From ticket · The end date must not be before the start date. · Ticket already saved

## `Sources/Tickets/Views/PassImportView.swift`
- Views: `PassImportView`, `PagePicker`, `PDFPageChoice`
- Sichtbare Texte: Reading ticket… · This file could not be read. · Try another file · Cancel · The photo could not be loaded. · Photo or screenshot · PDF or image file · Scan a paper ticket · Add ticket · Which page is the ticket? · Choose page · Page %lld

## `Sources/Tickets/Views/PassWalletView.swift`
- Views: `PassWalletView`, `PassCards`, `PassArchiveButton`
- Sichtbare Texte: Tickets · Add ticket · No current tickets · Archive · No tickets yet · Move back to tickets · Move to archive

## `Sources/Tickets/Views/TicketFieldMapper.swift`
- Views: `TicketFieldMapper`, `TicketFieldAssignSheet`
- Sichtbare Texte: Tap a text on the ticket and choose what it is. · Reading ticket… · No text found on this page. · This file could not be read. · Assign fields on the ticket · Done · Text · Ticket · Cancel · No date found in this text.

## `Sources/Tickets/Views/TripPassesView.swift`
- Views: `TripPassesView`, `TripPassSection`
- Sichtbare Texte: No ticket for this trip · Add ticket · Tickets · Show ticket · Done · Default ticket · All tickets · Add ticket for this trip

## `Sources/Tickets/Views/ZoomableDocumentView.swift`
- Views: `ZoomableDocumentView`
- Sichtbare Texte: Original ticket

## `Sources/Views/BoardingViews.swift`
- Views: `BoardingLine`, `BoardingSteps`
- Sichtbare Texte: Walk to %@ · Board at %@ · Pl. %@ · → %@ · Get off at %@

## `Sources/Views/Components/CoverageBanner.swift`
- Views: `CoverageBanner`, `CoverageMapNote`, `CoverageMark`
- Sichtbare Texte: Not reliable here · Publit uses open timetable data (Transitous). Where it is missing, connections can be incomplete or wrong. · Coverage map · Close

## `Sources/Views/Components/DepartureRow.swift`
- Views: `DepartureRow`
- Sichtbare Texte: Platform %@ · Rail replacement bus · Circle line · Towards %@ · Direction unavailable · at %@ · cancelled · live, %lld minutes late · live, on time · timetable time, no live data · platform %@

## `Sources/Views/Components/Design.swift`
- Views: `SignatureDot`, `InkProgress`, `Notice`, `NoticeBackground`, `InlineNotice`, `PlaceKeyRow`, `WhereToField`

## `Sources/Views/Components/DurationFigure.swift`
- Views: `DurationFigure`

## `Sources/Views/Components/LineBadge.swift`
- Views: `LineBadge`, `DepartureTimeView`, `AttributionFooter`
- Sichtbare Texte: Cancelled · now · min · +%lld min · Live · Timetable

## `Sources/Views/Components/LiveTripBar.swift`
- Views: `LiveTripBar`
- Sichtbare Texte: Start trip · Hide · Open trip · Live trip · min

## `Sources/Views/Components/LogoLoader.swift`
- Views: `LogoLoader`
- Sichtbare Texte: Loading…

## `Sources/Views/Components/ModeFilterBar.swift`
- Views: `ModeFilterBar`
- Sichtbare Texte: All · Filter by mode

## `Sources/Views/Components/OfflineNote.swift`
- Views: `OfflineNote`

## `Sources/Views/ConnectionGuideView.swift`
- Views: `ConnectionGuideView`, `ConnectionSymbols`, `ConnectionLegendRow`
- Sichtbare Texte: All rows use the same clock. Later departures start farther right. · The coloured blocks are rides. Thin grey sections are walking; dotted gaps are waiting between legs. · This is a comparison, not live progress. Check the departure times, line names and change warnings. · How to read connections · Ride · Walk · Wait · Time axis · Done

## `Sources/Views/FareSection.swift`
- Views: `FareSection`, `RegionTicketRow`
- Sichtbare Texte: Fare estimate · Fare information · Fares and tickets: %@

## `Sources/Views/FavoritesView.swift`
- Views: `FavoritesView`, `PastTripsView`
- Sichtbare Texte: Home and Work · Remove · Change · Set %@ · Lines · At %@ · Nothing else saved yet · Save stops from their departure board, lines from a trip, or add places with +. · Stops · Places · Home · Work · Saved · Add · Past trips · Upcoming trips · Save a route to see it here, add it to your calendar and get a reminder when to leave. · Plan again

## `Sources/Views/GoNowView.swift`
- Views: `GoNowView`
- Sichtbare Texte: Current location · Walk all the way · Later connections · From your location · Route · Leave now · Leave in %lld min

## `Sources/Views/ItineraryDetailView.swift`
- Views: `CompareMapView`, `ItineraryDetailView`, `RouteSummary`, `RouteMap`, `RouteMark`, `LegRow`, `GetOffButton`, `StatusBanner`, `TimelineLegRow`, `TimelineEndRow`, `TimelineRail`, `LeaveHero`
- Sichtbare Texte: Destination · Trip overview · Driving times are without traffic and parking. · Steps · Done · Route · Live · Cancelled · Rail replacement bus · Timetable · This trip is cancelled. · Pick up at %@ · Return at %@ · Rent in the provider's app · +%lld min · Platform %@ · Reminder set · Remind me to get off · We'll notify you at %@. · This stop is less than two minutes away. · Allow notifications for Publit in Settings. · On time · Board at %@ · Get off at %@ · Service changes on this route · Leave in %lld min · Leave now · Arrive

## `Sources/Views/LaunchSplash.swift`
- Views: `LaunchSplash`

## `Sources/Views/LinesView.swift`
- Views: `LinesView`, `LineRefRow`, `LineDetailView`, `LineMap`, `LineStopRow`, `LineTimetableView`
- Sichtbare Texte: Saved lines · At %@ · Allow location access to see the lines around you, or search for a station. · No lines found nearby. · No lines for these modes. · No line nearby matches. Try a station below. · Stations · Lines · Line, destination or station · Direction · Towards %@ · Vehicle positions are estimated from live departure times. · %lld stops · Tap a stop for its timetable. · Saved line · Save line · %@ to %@, next stop %@ · +%lld min · Day · No departures on this day. · %lld departures · Scheduled times. Live delays are on the departure board.

## `Sources/Views/LiveSourcesView.swift`
- Views: `LiveSourcesView`
- Sichtbare Texte: Europe and beyond · Routes, timetables and live times where operators publish them · Vienna · Live departures, disruptions, lifts out of service · Austria · Trains, and buses and trams where reported: delays, cancellations, construction work · Switzerland · Delays, cancellations and track changes of trains, trams, buses and boats · North Rhine-Westphalia · Live times of buses, trams and trains where Transitous has none · Berlin and Brandenburg · Hesse · Lower Saxony and Bremen · Schleswig-Holstein · Rhineland-Palatinate · Venice · Live times of waterbuses and buses · Stockholm · Live departures and disruptions · London · Line status and disruptions (Powered by TfL Open Data) · The extra operators only get the stop, line and time of a ride, never your location or account. · Live data sources

## `Sources/Views/LiveTripView.swift`
- Views: `LiveTripView`, `StageStrip`, `GuideStopRow`, `GuideMap`, `HeadingRow`, `PlatformChangeLabel`, `AlternativeRow`, `StagePager`, `StageRow`
- Sichtbare Texte: You seem to be off the route. · Missed it? · Connection cancelled · Done · Back to now · Trip overview · Route details · Walk to %@ · Platform %@ · Walk faster to make it. · In %@ · Directions · Get off at %@ · +%lld min · On time · Rail replacement bus · This trip is cancelled. · Next stop · in %@ · Position from your location. · Position estimated from live stop times. · Position estimated from the timetable. · Stops · You have arrived · Arrive at %@ · Destination in %@ · End trip · Show ticket · Map style · 3D terrain and buildings · More · Turn off spoken directions · Turn on spoken directions · Backup: %@ at %@ · Your change at %@ may not work (%lld %%). · Departs in %lld min · Departs now · Departed %@ · Board at %@ · Now at %@ · Next: %@ · Take %@ towards %@ · Take %@ · Get off here · Pl. %@ · Stop turning the map · Turn the map with you · No compass: the arrow has north at the top. · Platform changed (was %@) · Your trip: arrive %@ · Looking for the next connection… · No other connection found right now. · Fewer connections · Other connections · New route from here · Walk · Arrive %@ · Switch · Switch to this connection · now

## `Sources/Views/Map/GoogleMapView.swift`
- Sichtbare Texte: Apple Maps

## `Sources/Views/Map/TransitMapView.swift`
- Sichtbare Texte: Dropped pin · Available now: %lld · Available now · Show rental details

## `Sources/Views/NearbyView.swift`
- Views: `NearbyView`, `StopGroupHeader`, `StopDeparturesView`, `LineAtStopRow`
- Sichtbare Texte: Location is off · Allow location access in Settings to see departures near you. Trip planning works without it. · Departures unavailable · No departures for these modes · Show all modes · No departures nearby · No departures within 5 km. The station map shows stops further away. · Station map · Couldn't refresh. Times may be out of date. · Route here · All departures · Nearby · Active trip · Where to now? Route from your location · Next trip: %@ · %lld min · Alerts · Towards %@ · Route from here · Share departures · View · Departures · Lines · No upcoming departures. · Saved line · Save line · Save · Direction unavailable · now

## `Sources/Views/OnboardingView.swift`
- Views: `OnboardingView`
- Sichtbare Texte: Skip · Public transport, without the noise. · Departures near you, routes across Europe and a guide until you get off. No ads, no account, no tracking. · Departures where you are · On the way · Not now · Allow location · Get started · Continue · Home and Work · One tap to get home or to work, from anywhere. You can change them any time in Saved. · Not set

## `Sources/Views/PlaceSearchView.swift`
- Views: `PlaceSearchView`, `PlaceLabel`, `CategoryIcon`
- Sichtbare Texte: Current location · Saved · No matches. · Save · Cancel · from %@ · Remove · Clear history · Recently searched · Place from the link

## `Sources/Views/PlanView.swift`
- Views: `PlanView`, `EndpointConnector`, `ItineraryRow`, `TimelineBar`
- Sichtbare Texte: Search routes · Swap · Depart · Arrive · When · Arrive by · Depart at · Now · Recommended: %@ · Plan · Where to? · not set · Earlier connections · Later connections · Updated %@ · Live data · Cancelled · Service changes on this route · Change at %@: %lld %% chance

## `Sources/Views/PublitLogo.swift`
- Views: `PublitLogo`, `PublitAppIcon`

## `Sources/Views/RecentSearchesSection.swift`
- Views: `RecentSearchesSection`
- Sichtbare Texte: from %@ · Remove · Clear history · Recently searched · Cancel

## `Sources/Views/RouteOptionsView.swift`
- Views: `RouteOptionsView`, `RouteOptionsButton`, `StreetComparisonSection`, `FirstMilePicker`
- Sichtbare Texte: Transport modes · Routes only use the modes that are switched on. · To the first stop · Changes · Walk to and from stops · %lld min · Step-free (wheelchair) · Shared bikes and e-scooters · Compare with walking, cycling and driving · Driving times are without traffic and parking. · Route options · Reset · Done · All modes · Other ways · About as fast · %@ faster · %@ slower · Park & Ride searches take longer.

## `Sources/Views/SavedTripView.swift`
- Views: `SavedTripView`, `SavedTripRow`
- Sichtbare Texte: Trip not found · It was removed from this device. · Live status unavailable. Showing saved times.

## `Sources/Views/ServiceAlertsView.swift`
- Views: `ServiceAlertRow`, `ServiceAlertsView`

## `Sources/Views/SettingsView.swift`
- Views: `SettingsView`, `SettingsButton`
- Sichtbare Texte: Public transport, without the noise. · Start screen · Nearby · Plan · Travel preferences · Show connection timelines · How to read connections · Map provider · Map style · Points of interest · Lines · Vehicles · Bikes and scooters · Open directions in · Map · Google Maps uses the Google API key under Search, with “Maps SDK for iOS” enabled. Without a key, Apple Maps is shown. · Place search · Google API key · Search · Tickets · My tickets · Ticket apps per operator · Tickets on Apple Watch · Apple Watch · Disruptions on saved lines · Notifications · Live data from more operators · Live data sources · Export my data · Data · Times marked live come from the operator's real-time feed; all others are timetable times. · Freezes · Failed requests · Crashes and unexpected exits · No problems recorded · Share diagnostics · Report a problem · Delete diagnostics · Diagnostics · Version · About · Publit is open source (MIT). No account, no ads, no tracking. Saved places, trips and tickets stay on this device. · Publit is open source (MIT). No account, no ads, no tracking. Saved places and trips stay on this device. · Settings · Done

## `Sources/Views/SharedRouteView.swift`
- Views: `SharedRouteView`
- Sichtbare Texte: This route could not be loaded. · It may be too old or no longer in the timetable. You can search for it again. · Search this route

## `Sources/Views/SmartRoutingViews.swift`
- Views: `SmartBadgesRow`, `SmartChangesSection`, `ChangeChanceRow`, `SmartRoutingSettingsSection`
- Sichtbare Texte: No change: nothing to miss · Smart routing · Feels like %@: waiting, walking and changes count more than riding. · Safe change · Change should work · Risky change · %@ to spare · Very tight change · Change at %@ · Arrive %@ · still makes the next change · If missed: %@ at %@ · No backup found if you miss it. · Changes · Faster · Fewer changes · A change counts like %lld extra minutes. · Extra time for changes · None · +%lld min · Use my walking speed · Your walking speed · From Apple Health · From the step counter · Not enough walking measured yet. · Avoid steep walks · Learn from my choices · Reset learned preferences

## `Sources/Views/StationMapView.swift`
- Views: `StationMapView`, `MapLayersSheet`, `MapPlaceView`, `MapSelectionView`, `RentalDetailView`, `VehicleTripView`
- Sichtbare Texte: Stations could not be loaded. · Live layer unavailable. Stations still work. · My location · Updating live layer… · Stations · Search places, sights and stops · Done · Close · Search this area · Zoom in to see stations · Zoom in to see lines and vehicles · Map layers · Find nearby · All %@ in this area · No places found · Map · 3D terrain and buildings · Places of interest · Traffic · Lines · Vehicles · Bikes and scooters · Data gaps · On the map · Satellite maps load more data. In 3D, tilt the map with two fingers. · Distance · On foot · %lld min · Route here · Route from here · Provider · Available now · Open in the provider's app · Renting needs the provider's app and an account there. · Towards %@ · Live position · Position from the timetable · %lld min late · Next stops · Line %@: route and timetable

## `Sources/Views/TicketAttachmentView.swift`
- Views: `TicketAttachmentView`
- Sichtbare Texte: Ticket image unavailable

## `Sources/Views/TicketCard.swift`
- Views: `TicketSummaryCard`
- Sichtbare Texte: Pass · Single trip · Valid until %@ · Expired · Stored copy · Open ticket app

## `Sources/Views/TicketsView.swift`
- Views: `TicketsView`, `AddTicketView`, `TicketDisplayView`, `LinkedTicketAppsView`, `ShowTicketButton`
- Sichtbare Texte: No tickets yet · Passes · Single trips · My tickets · Add ticket · Type · Choose screenshot · Replace screenshot · Screenshot · This is not a valid link. · Open app · A web address (many ticket apps open from their website link) or the app's own link, e.g. appname://. · Expires · Valid until · Done · Cancel · Save · Couldn't save ticket. Please try again. · No ticket · Add tickets in Settings → My tickets. · Tickets · Stored copy · Ticket %@ · Show original · Open ticket app · This ticket has no screenshot or link. · A stored screenshot may not be accepted. Use the operator's live ticket when required. · Add · Link · Suggestions · Ticket apps · Show ticket

## `Sources/Views/TransferCard.swift`
- Views: `TransferCard`, `TrainDivisionNotice`
- Sichtbare Texte: Arrive · Departure · Connection cancelled · Change at %@ no longer works · %@ walk · %@ to spare · Very tight change · Towards %@ · Platform %@ · Platform changed (was %@)

## `Sources/Views/TripActions.swift`
- Views: `TripActionsSection`, `TicketSection`, `TicketCardButton`
- Sichtbare Texte: End trip · Start trip · The calendar entry links back to this trip with its live status. · Saved · Save trip · Add to Calendar · Share arrival · Share trip · Reminder on · Leave reminder · Trip ended · Allow notifications for Publit in Settings. · This trip starts now. · We'll remind you at %@. · Follow it on the lock screen. · Live updates on the lock screen start 8 hours before. · Turn on Live Activities for Publit in Settings to follow it on the lock screen. · Add ticket for this trip · Tickets · The operator publishes no ticket link. Link your ticket app in Settings → Ticket apps.

## `Sources/Views/TripView.swift`
- Views: `TripView`, `TripMap`, `StopTimeRow`, `LineDeparturesView`
- Sichtbare Texte: Stops · From %@ to here · Route here · Route from here · Saved line · Save line · Not departed yet · Arrived at %@ · At %@ · Between %@ and %@ · No live data for this trip. Position estimated from the timetable. · Position estimated from live stop times. · Estimated vehicle position

## `Sources/Views/WalkThereRow.swift`
- Views: `WalkThereRow`
- Sichtbare Texte: Walk there: %@ · %lld min walk · %@

## `Sources/Views/Wide/WideLayout.swift`
- Views: `WideMapCanvas`, `WideRoutesMap`

## `Watch/WatchHomeView.swift`
- Views: `WatchHomeView`, `WatchLiveTile`
- Sichtbare Texte: Where to? · Nearby · Saved · Tickets · Live

## `Watch/WatchNearbyView.swift`
- Views: `WatchNearbyView`, `WatchDepartureRow`
- Sichtbare Texte: Nearby · Refresh · Updated %@ · Try again · now · min · Live

## `Watch/WatchPlanView.swift`
- Views: `WatchPlanView`, `WatchRouteRow`, `WatchPlaceChooser`, `WatchPlaceRow`
- Sichtbare Texte: Current location · Where to? · Plan · Refresh · Try again · Later connections · Search · No place found for “%@”. · Saved · From

## `Watch/WatchRoute.swift`
- Views: `WatchRouteView`, `WatchMessage`, `WatchCoverageNote`, `WatchCoverageMark`
- Sichtbare Texte: Not reliable here

## `Watch/WatchSavedView.swift`
- Views: `WatchSavedView`, `WatchSavedTripRow`, `WatchStopView`
- Sichtbare Texte: Upcoming trips · Home and Work · Stops · Places · Past trips · Saved · Live · Try again · Route here · Updated %@ · Save

## `Watch/WatchTicketsView.swift`
- Views: `WatchTicketsView`, `WatchTicketRow`, `WatchTicketView`, `WatchCodeView`, `WatchTicketDetails`
- Sichtbare Texte: Updated %@ · Tickets · Valid until %@ · Valid now · Valid from %@ · Expired · Ticket code · The code is on its way from your iPhone.

## `Watch/WatchTripMapView.swift`
- Views: `WatchTripMapView`
- Sichtbare Texte: Not reliable here · Trip overview · Walk %@ · Map

## `Watch/WatchTripView.swift`
- Views: `WatchTripView`, `WatchTripOverview`, `WatchLegPage`
- Sichtbare Texte: Map · Tickets · Trip overview · End trip · Start trip · Remove · Save trip · Cancelled · Live · Walk %@ · +%lld min · Pl. %@ · Platform changed

## `Widgets/DeparturesWidget.swift`
- Views: `DeparturesWidgetView`
- App Intents: `DeparturesProvider`
- Widgets: `DeparturesWidget`
- Sichtbare Texte: Choose a stop · No departures soon

## `Widgets/PublitWidgets.swift`
- Views: `LineChip`, `PlatformChip`, `Countdown`, `FamilyAdaptiveView`, `SmallActivityView`, `ActivityContent`, `LockScreenView`
- Widgets: `WatchTripLiveActivity`, `TripLiveActivity`
- Sichtbare Texte: Show ticket
