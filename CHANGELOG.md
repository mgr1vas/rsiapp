# Changelog

Notable changes to Road Safety Insights. All accident, road segment, hazard
and rental data in these releases is mock data for development.

## [0.2.0] - 2026-09-14

Version code 2. Branch: `feature/safety-map-rentals-onboarding`

### Added

- **Hazard alerts outside the app.**
  - When a hazard is announced while the app is in the background, a
    heads-up notification appears (channel "Προειδοποιήσεις κινδύνου",
    `flutter_local_notifications`).
  - Notification permission is requested when navigation starts
    (Android 13+).
  - The ongoing navigation notification shows the next instruction and the
    arrival time, updated at most once a second.
- **Navigation survives switching apps.**
  - The active trip (origin, destination, simulation or live GPS, speed and
    progress) is saved every 5 seconds.
  - On the next launch it resumes if it is less than 3 hours old.
  - Back during navigation no longer closes the app. It floats the app in
    picture-in-picture (see below), or otherwise sends it to the
    background.
- **Picture-in-picture during navigation (Android).**
  - Leaving the app during a trip (home, recents or back) shrinks it into a
    floating 3:4 window. This is automatic on Android 12+; on Android 8–11
    it happens through `onUserLeaveHint`.
  - The floating window shows only the map, the car and one strip with the
    next turn, which turns orange with the distance when a hazard is ahead.
  - The camera always follows the car there, slightly zoomed out.
  - Enabled only while navigating (`supportsPictureInPicture`, method
    channel in `MainActivity`).
- **Demo routes for testing alerts.** Available in the route planner; they
  start in simulation mode:
  - Άρτα: 3.3 km from the old bridge to the General Hospital, with 10 mock
    hazards (`assets/data/arta_hazards.geojson`).
  - Πύλη Βοιωτίας: 2.7 km to the Ζωοδόχου Πηγής monastery.
  - Πύλη → Θήβα: 26 km on regional roads and the ΕΟ3. The two Πύλη routes
    share 14 mock hazards (`assets/data/pyli_hazards.geojson`).

  Hazards sit on the OSRM demo routes, with street names from OSRM and
  OpenStreetMap. Hide the routes with `--dart-define=RSI_DEMO_ROUTES=false`.
- **Pick a destination on the map.** A long press drops a pin, names it
  with the nearest address and routes to that exact point.
- **Tests.** 117 unit and widget tests (`flutter test`).

### Changed

- **Place search** uses the Mapbox Search Box API instead of Geocoding v5.
  - Finds businesses and landmarks, e.g. "Γενικό Νοσοκομείο Άρτας".
  - Results show two lines (name, then postcode and town), a type icon and
    the distance.
  - Routes end at the entrance point (`routable_points`) when Mapbox has
    one.
  - The search uses the `MAPBOX_ACCESS_TOKEN` define instead of a token
    written into the source.
- Turn instructions fall back to the road number (e.g. ΕΟ3) when a road has
  no name.
- **Smoother simulation.**
  - The car moves by elapsed time at a steady speed instead of jumping from
    point to point on a timer.
  - The camera updates every frame without overlapping animations, and the
    heading eases through corners.
  - Speeds changed: 1× is now 50 km/h; the old 1× was about 280 km/h.
- Live GPS positions within 35 m of the route are snapped onto it and eased
  between fixes.
- **Route line.**
  - The line is a map style layer. The part already driven is trimmed with
    `line-trim-offset`; the line is no longer deleted and redrawn every few
    points.
  - While following, a car arrow drawn by Flutter sits at the camera's
    follow point.
- Guidance measures the route once (`RouteProgress`, `RouteGuidance`) rather
  than re-projecting every step and hazard on each update.
- The hazard alert card stays until the driver has passed the hazard (was
  7 seconds).
- The background service uses only the `location` foreground-service type,
  and only starts once location access is granted.

### Removed

- `just_audio` and the hazard sound. The audio file was never bundled, so it
  never played. Alerts now use vibration, and the notification sound when
  the app is in the background.

### Fixed

- Hazard alerts during navigation only ever came from the Naxos data file.
  All hazard files are now loaded.
- Switching to another app during navigation could drop the driver back to
  the route planner. The trip is now resumed (see Added).
- The route line flickered and started behind or ahead of the car while
  driving.
- In split screen, landscape or a floating window, the car was drawn in the
  wrong place while following it. The space kept clear above and below the
  car was a fixed 150 and 240 dp. It is now a share of the map's height
  (`FollowViewport`), with the full-size phone layout unchanged.
- Hazard markers, the destination pin and the car marker are redrawn when
  Android rebuilds the map while the app is in the background.

## [0.1.0] - 2026-09-12

Version code 1.

### Added

- **Map filters.** A filter button with an active-filter badge in the search
  bar opens a sheet:
  - show or hide accidents and road risk
  - filter accidents by severity and time period (last 12 months, last
    3 years, all time)
  - filter roads by risk level
  - Reset returns everything to the defaults

  Changes apply immediately and clusters recount. Road colours always use all
  recorded accidents.
- **Road risk classification.**
  - 24 road segments in central Athens and Ioannina are drawn green, yellow,
    orange or red for Low, Moderate, High and Very high risk.
  - The heuristic 0–100 score uses bands of 0–24, 25–49, 50–74 and 75–100.
  - Inputs: accidents within 75 m per km of road, severity, injuries,
    deaths, recency, and road features (speed limit, junction, lighting,
    pedestrian activity).
  - Tap a road for its level, "Risk Score: NN/100", accident counts, the
    period covered and its road features.
- **Accident points.**
  - 78 accidents (46 in Athens, 32 in Ioannina) are shown as points
    coloured by severity.
  - Nearby points group into clusters; tap a cluster to zoom in.
  - Tap a point for its date, location, severity, injured, deaths, accident
    type, likely cause and source, where available.
- **Car rentals.**
  - A draggable sheet on the map shows partner offers (discount badge,
    original price crossed out), then all cars.
  - A details page shows specs, rental terms and pick-up location, with a
    contact sheet.
  - Data covers 2 partner companies and 8 cars, with freely licensed photos
    (credits in `assets/images/rentals/CREDITS.md`).
- **First-launch onboarding.**
  - Three short intro pages, then a choice to share location.
  - Location permission is only requested when the user opts in.
  - The choice is saved on the device. If the user skips, the location
    button asks later.
- **Side drawer** with About, Terms & Conditions and Privacy Policy pages.
- **Terms & Conditions and Privacy Policy.** Full documents in
  `assets/legal/`, shown in the app.
  - Terms: 18 sections, covering safety while driving, accident data and risk
    estimates, third-party maps and routes, rentals and partner offers, and
    liability.
  - Privacy Policy: 13 sections, covering GDPR legal bases, service providers
    (Mapbox, routing, Google location services), your rights and the Hellenic
    Data Protection Authority.
  - Bracketed placeholders (company details, contact email, dates, routing
    provider) must be completed, and both texts reviewed by a lawyer, before
    release.
- **Map compass.** The needle follows the map's rotation, and tapping it
  resets the map to north. During navigation it switches between north-up
  and heading-up.
- **App identity.** Package `com.roadsafetyinsights.app`, name "Road Safety
  Insights", and a shield-and-road adaptive launcher icon.
- **Developer tool.** `tool/snap_road_segments.py` snaps the mock road
  segments onto real roads using OSRM map matching.
- **Tests.** 80 unit and widget tests (`flutter test`).

### Changed

- The map starts at Athens, then centres on the user after the first GPS fix.
- Map rotation gestures are enabled, and the location dot is smaller.
- Location updates only start after the user agrees to share location.
- The Mapbox logo and map buttons sit above the rentals sheet.
- Mock accidents and road segments follow real streets. Segments are map
  matched or traced from OpenStreetMap.

### Fixed

- Build error caused by an undeclared route index field.
- The location button no longer snaps the camera back to Athens. The map
  viewport was being recreated on every rebuild.
- Crash on launch after navigation had been started. The background service
  used a notification channel the app never created ("Bad notification for
  startForeground").
- Location updates could stay off after the first launch when they started
  before permission was granted.
- Road risk lines were hard to tap. Taps within about 20 dp of a line now
  select it. Accident points drawn on top still take priority.
