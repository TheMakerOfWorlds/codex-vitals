# Personal macOS builds

This branch combines upstream Codex Vitals 1.6.3 with a borderless personal interface, explicit account switching, and informational banked-reset details.

## Build and verify

```sh
swift test
.build/debug/CodexVitals --render-sanitized-screenshot
.build/debug/CodexVitals --render-sanitized-screenshot --dark
PERSONAL_BUILD=1 ./build-app.sh
codesign --verify --deep --strict dist/CodexVitals.app
```

`PERSONAL_BUILD=1` marks the app as personal and keeps official update checks available while requiring manual update installation. Official updates replace local customizations. Merge upstream changes and rebuild when preserving the personal design. Omit the flag for normal upstream automatic-install behavior.

The app uses the existing bundle identifier and account storage. The screenshot renderer uses sample accounts without fetching usage or switching accounts.

## Sources and updates

- Upstream: https://github.com/Joowonoil/Codex-Vitals
- Contributor fork: https://github.com/TheMakerOfWorlds/codex-vitals
- Target fork: https://github.com/KeystoneScience/codex-vitals
- Sparkle feed: https://ramterstudio.com/codex-vitals/appcast.xml

The feed points to signed upstream GitHub Releases. The original public verification key and verification-before-extraction remain enabled. At verification, KeystoneScience had no published releases, so its project link is separate from the official update source.

## Interface and behavior

- Plain Codex Vitals title without the header app icon, studio attribution, promotional section, or GitHub-star interruption.
- Borderless rows, controls, badges, lists, and Settings cards.
- Email first, one plan badge, and meaningful aliases/workspace names below.
- Persistent Switch button with a larger target. Authenticated exhausted accounts remain switchable.
- Entire Waiting for reset group at 80% opacity, including its header and rows.
- Stacked quota bars with reset icons beside their reset times.
- Informational banked-reset counts and expiry dates; exact local time and zone on hover and in accessibility text. No redemption control.
- Explicit Renews versus Plan ends, with distinct icons; neutral Cycle ends for older metadata without provenance.
- Discount expiry is not treated as renewal. Dates are not copied between accounts based on matching workspace display names.
- Calendar-day countdowns distinguish Today, Tomorrow, and Date passed.
- Upstream Claude throttling, Retry-After handling, and cached usage behavior.

## Validation

- 101 Swift tests passed, including duplicate-plan display, date provenance, calendar-day countdown, and exhausted-account switching cases.
- Light and dark SwiftUI renderings reviewed.
- Release build and strict code-signing verification passed.
- The installed executable matched the release build, and live usage refreshed successfully.
- Native Foundation networking returned HTTP 200 for the RSS update feed.
- Native UI inspection timed out; visual verification used the app renderer, with installation and live refresh verified separately.

Screenshots contain sample accounts. Private local paths, installation logs, and account data are excluded from this document.
