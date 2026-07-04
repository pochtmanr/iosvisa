# M2 — Discovery: passport-strength map + destinations

**First read `ios/prompts/00-shared-context.md` and `ios/README.md`.** Build on
M1 in `ios/`. Verify with `xcodebuild build` + `test`.

## Goal

The headline feature: an interactive **passport-strength world map** plus a
**destinations** browser, both personalized to the user's passports. A user
picks one or more passports and sees where they can go (color-coded by visa
status), taps a destination to see all visa routes by purpose, and can jump from
there into starting an application (wired in M3).

## Scope

### 1. Visa data layer
- `Core/Models/VisaProduct.swift` + `ResolvedVisaProduct` (and
  `VisaProductEligibility`, `DestinationVisaOptions`) mirroring
  `web/src/lib/visa-products.ts` and `web/src/lib/supabase/types.ts`. Include
  `entry_type`, `application_mode`, eligibility, fees (`gov_fee_cents`,
  `service_fee_cents`, `currency`), `max_stay_days`, `processing_time_days`,
  `summary`, `attributes` (JSON).
- `Core/Repositories/VisaRepository.swift`:
  - `requirements(passport:)` → reads `visa_requirements` for a passport across
    all destinations (for map shading). Page past PostgREST's 1000-row clamp.
  - `destinationOptions(passport:destination:)` → **port of
    `loadDestinationVisaOptions`**: expand zones via `visa_zone_members`, select
    active `visa_products` for destination or zone, fold sparse overrides from
    `visa_product_eligibility`. Return resolved products.
  - `countries()` → cached `countries` catalog (public read).

### 2. The map
- `Features/VisaChecker/VisaCheckerView.swift` — top bar to select passports
  (default from the user's vault, primary preselected); the map fills the body.
- `Features/VisaChecker/WorldMapView.swift` — a vector world map shaded per
  `VisaStatus.hue` for the selected passport(s) (when multiple passports, use
  the **best** status available). Implement with an SVG/GeoJSON-backed shape
  layer. Options, in order of preference:
  1. Bundle a lightweight world GeoJSON/SVG (countries keyed by ISO2) in
     `Resources/`, parse to `Path`s, fill by status. (Reuse the web map's data
     source if present under `web/` — check `web/src/components/checker/` and
     `web/public/` for a topojson/geojson/world svg before adding a new one.)
  2. If that's too heavy for a first pass, ship a **grouped list / grid by
     region** with status chips as a functional equivalent, and leave a clear
     `// TODO: vector map` — but prefer the real map.
- Legend using `StatusDot` + `VisaStatus.label`. Tapping a country →
  `DestinationDetailView`.
- Persist selection (passports/destination) so it survives tab switches; support
  the deep link shape `visapilot://...?passports=US,CA&to=DE`.

### 3. Destinations browser
- `Features/Destinations/DestinationsView.swift` — gallery/grid of countries
  (cinematic imagery optional; flag + name + best-status chip is fine), grouped
  or searchable. Personalized status from the selected/primary passport.
- `Features/Destinations/DestinationDetailView.swift` — for a destination:
  baseline regime chip, then the **resolved visa routes** grouped by purpose
  (tourism/study/work/etc.), each showing entry type, eligibility
  (`VisaEligibility.label`), fees, processing time, and an "online vs consular"
  indicator (green = we submit online, blue = manual). A primary CTA "Start
  application" (navigates to the M3 new-application wizard, prefilled with this
  passport+destination+product). Always render `AdvisoryDisclaimer`.

## Web parity references
- `web/src/app/visa-checker/page.tsx`, `web/src/app/(app)/app/visa-checker/page.tsx`,
  `web/src/components/checker/CheckerFlow.tsx`.
- `web/src/app/(app)/app/destinations/**`, `web/src/lib/destinations/types.ts`,
  `web/src/lib/visa-products.ts`.
- Map data: search `web/public` and `web/src/components/checker` for an existing
  world topojson/geojson/svg to reuse before adding one.

## Tests
- Unit-test the zone-expansion + eligibility-fold logic and the "best status
  across multiple passports" reducer (pure, headless-safe) with fixture data.

## Definition of done
- Build + tests green. Map shades correctly for a real passport against the live
  data and matches the web `/visa-checker` for the same inputs (spot-check a few
  passport/destination pairs).
- Destination detail lists the same routes the web shows; "Start application"
  navigates to a (stub-until-M3) new-application entry with the right context.
- Update `ios/README.md` M2 checkbox.
