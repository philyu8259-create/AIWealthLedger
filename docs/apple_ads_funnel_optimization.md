# Apple Ads Funnel Optimization Plan

## Current Hypothesis

The campaign is attracting broad expense-tracker traffic, but the product now needs to prove a sharper promise before increasing spend: "log spending in seconds, then get a useful monthly money review."

## Funnel Events Added

- `first_open`: first local app launch.
- `app_open`: every launch after dependency setup.
- `onboarding_viewed`: welcome screen shown.
- `onboarding_completed`: guest, demo, Google, or Apple entry completed.
- `record_sheet_opened`: user opens the add-entry sheet.
- `first_record_cta_tapped`: user taps the empty-state first-record CTA.
- `first_record_created`: first saved entry, with source and total count.
- `paywall_opened`: user taps the premium banner.
- `paywall_viewed`: premium purchase sheet is visible.
- `subscription_plan_selected`: monthly or yearly selected.
- `subscription_cta_tapped`: purchase CTA tapped.
- `subscription_checkout_started`: Apple checkout request started.
- `subscription_purchased`: purchase stream confirmed a subscription.
- `apple_ads_attribution_token_received`: iOS AdServices returned a token.
- `funnel_csv_exported`: funnel diagnostics CSV was shared.

The events are stored locally through `FunnelAnalyticsService`, printed in debug logs, summarized in Settings > Ad funnel check, and exportable as CSV. The service is intentionally central so Firebase, PostHog, Amplitude, or a Cloud Function endpoint can be attached in one place later.

## Where To Check The Funnel

Open Settings > Ad funnel check.

- The top section shows Apple Ads attribution status, locale country, Apple Ads country, campaign ID, ad group ID, and keyword ID.
- The middle section shows counts and previous-step conversion for open app, onboarding, first record, paywall, purchase tap, checkout start, and purchase.
- The recent events section shows the latest tracked events with country, campaign, and keyword fields when available.
- Use Export funnel CSV to inspect the raw event rows.

On iOS, the app requests an AdServices token through `AAAttribution.attributionToken()`. Apple requires that token to be exchanged through Apple Ads Attribution API or an MMP/server to retrieve detailed attribution payload fields such as `campaignId`, `adGroupId`, `countryOrRegion`, and `keywordId`. The app now calls the Cloud Function endpoint `/ads/attribution` when the backend base URL is configured, then stores the returned payload through `saveAttributionPayload(...)`.

## Product Copy Changes

- Welcome screen moved away from generic "AI wealth tracker" and now leads with a concrete outcome: track spending in 10 seconds.
- Welcome screen highlights three inspection-ready use cases: voice logging, receipt scan, and monthly review.
- Premium copy now sells the reason to subscribe: AI monthly money reviews, budget warnings, unlimited records, and asset view.

## Apple Ads Keyword Direction

Pause or lower bids for broad terms that are expensive without subscription intent:

- `expense tracker`
- `budget tracker`
- `spending tracker`
- `portfolio tracker`
- `bookkeeping`

Test tighter intent terms in small ad groups:

- `voice expense tracker`
- `receipt tracker`
- `daily expense log`
- `spending habit tracker`
- `monthly budget review`
- `cash flow tracker`
- `freelance expense tracker`

## Seven-Day Validation

Run the next Apple Ads test with a low daily budget and judge it by funnel quality, not installs alone:

- Install to first open.
- First open to first record.
- First record to paywall view.
- Paywall view to checkout start.
- Checkout start to purchase.
- Country and keyword cohorts that reach checkout start.

If first record rate is weak, fix onboarding and first-entry UX before more ads. If first record is healthy but paywall is weak, continue sharpening premium value and pricing.

## Decision Rules

- If open app to first record is below 25%, keep budget low and focus on first-record UX.
- If first record to paywall view is below 15%, surface monthly review value earlier in the home screen.
- If paywall view to checkout start is below 5%, test yearly discount copy and a clearer trial/renewal explanation.
- If checkout start to purchase is near zero, verify StoreKit product availability, pricing, territory eligibility, and sandbox/production product status.
- If one country or keyword reaches first record and checkout start more often, split it into its own Apple Ads ad group and move broad-match spend down.
