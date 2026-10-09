# Widget customization

The source now includes a “Dream up your own background” section in the Pro widget studio. Users describe a scene in up to 500 characters, generate it for 200 tokens, and switch between saved backgrounds for free. Generated artwork is stored in shared storage at a maximum of 640 pixels per side for widget archives.

Background generation uses the existing authenticated image-job pipeline, including saved request keys, polling, recovery after relaunch, and refunds for failed provider jobs. Recovery saves a background without creating a pet or photo-adventure entry. Prices are assigned by the server.

Each missing animation costs 1,500 tokens, so creating idle, playful and sleeping costs up to 4,500. Completed animations and recovered cached jobs remain free to replay.

The medium widget’s right side offers:

- Pet info: the pet’s name and current mood message.
- Clock: the local time and date, using native live time on iOS 18+ and minute timeline entries on iOS 17.
- Daily quote: one quote per local day from ZenQuotes, with its author and linked source attribution. The app and widget share an atomic disk cache and a lock to avoid duplicate requests. Failed requests retain the last fetched quote and retry no more often than every 30 minutes. With no saved quote, the panel explains that ZenQuotes is unavailable.
- Calendar: the current month, respecting the local first weekday and highlighting today.

The selected option persists across launches and is shared with the widget. Older snapshots default to Pet Info. The small widget retains its pet layout.

## Verification

On October 9, 2026, the app and widget extension compiled successfully. All 63 iOS tests and 41 backend tests passed. New checks cover old snapshot compatibility, preference persistence, bounded artwork storage, saved-background deduplication, timezone-aware quote expiry, once-daily fetching across launches and app/widget clients, certificate failures, response validation, recovery context, authoritative prices, insufficient funds, duplicate charges, private jobs, opaque background output, and refunds. Image/animation provider requests were mocked; no paid background generation was performed. The ZenQuotes integration was additionally verified with a live fetch through the Swift service and cache reload.

The four medium layouts and studio were visually inspected at phone/widget dimensions, including a six-row calendar month. See [medium options](screenshots/widget-customization/medium-options.png) and [widget studio](screenshots/widget-customization/studio.png). The [ZenQuotes daily panel](screenshots/widget-customization/zenquotes-daily.png) shows a real fetched quote with its author and source link.

Daily quotes use `GET https://zenquotes.io/api/today`, following its [API documentation](https://docs.zenquotes.io/zenquotes-documentation/). ZenQuotes publishes a shared daily quote at midnight server time (documented as 00:00 CST). The app fetches and caches the available quote once per local day; WidgetKit controls actual widget refresh timing. The studio refreshes on selection, app activation, and midnight while visible. This integration does not spend tokens.

Free access permits five requests per 30 seconds per IP and requires a link back to ZenQuotes. The widget and app include that link. Longer daily quotes keep their full text; tapping the quote widget opens the studio, where users can read the complete quote.

Quotable was replaced after its endpoint presented an expired HTTPS certificate. ZenQuotes returned HTTP 200 on October 9, 2026, and the live Swift service fetch/cache check passed.

These changes are included in TestFlight 1.0 (12), processed and available in Internal Testing. The matching backend is deployed. See [release verification](TESTFLIGHT_RELEASE.md).
