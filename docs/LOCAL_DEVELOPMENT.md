# Personal macOS builds

This branch combines upstream Codex Vitals 1.6.3 with a borderless personal interface, explicit account switching, informational banked-reset details, and a macOS Keep awake control.

## Build and verify

```sh
swift test
.build/debug/CodexVitals --render-sanitized-screenshot
.build/debug/CodexVitals --render-sanitized-screenshot --dark
PERSONAL_BUILD=1 ./build-app.sh
codesign --verify --deep --strict dist/CodexVitals.app
```

`PERSONAL_BUILD=1` only adds a Personal label. It does not disable this repository's updater. `UNIVERSAL=1` builds both Apple Silicon and Intel. `VERSION=1.6.4.0` overrides the bundle version for a local bootstrap build.

The existing bundle identifier, account storage, and active authentication are preserved.

## Canonical repository and release maintenance

Use **https://github.com/TheMakerOfWorlds/codex-vitals** for changes, releases, project links, and update downloads. The original project is only a source reference; neither its release feed nor the KeystoneScience fork is an update source.

- macOS feed: `https://raw.githubusercontent.com/TheMakerOfWorlds/codex-vitals/main/updates/appcast.xml`
- Windows feed: `https://raw.githubusercontent.com/TheMakerOfWorlds/codex-vitals/main/updates/windows-appcast.xml`
- macOS signing key: Sparkle Keychain account `codex-vitals.themakerofworlds`; CI uses the repository's `SPARKLE_PRIVATE_KEY` Actions secret.

The Publish macOS update workflow tests code, builds a universal app, signs the archive, independently verifies its signature and repository URL, publishes a GitHub release, and only then updates the feed. Runtime/build changes on `main` publish automatically. Versions append the workflow run number to the base version in `Support/Info.plist`. Documentation and generated-feed commits do not trigger releases.

For a manual archive:

```bash
VERSION=1.6.4.0 UNIVERSAL=1 ./build-app.sh
ditto -c -k --sequesterRsrc --keepParent dist/CodexVitals.app dist/CodexVitals-1.6.4.0.zip
scripts/prepare-sparkle-update.sh 1.6.4.0
```

Publish the immutable archive and appcast as release assets before copying the generated feed into `updates/appcast.xml`. The private key is never written to the repository. Personal builds are ad-hoc signed and are not Apple-notarized.

Automatic checks and installation are enabled once when migrating from the old feed. Later user choices are preserved. The runtime delegate pins the feed to this repository even if older preferences contain another URL. Sparkle downloads verified updates automatically and installs them when the app quits; Check for Updates can install immediately.

## Interface and behavior

- Plain Codex Vitals title without the header app icon, studio attribution, promotional section, or GitHub-star interruption.
- Borderless rows, controls, badges, lists, and Settings cards.
- Email first, one plan badge, and meaningful aliases/workspace names below.
- Persistent Switch button with a larger target. Authenticated exhausted accounts remain switchable.
- Entire Waiting for reset group at 80% opacity, including its header and rows.
- Stacked quota bars with reset icons beside their reset times.
- Informational banked-reset counts and expiry dates without the year. Expirations within seven days also display the local time with AM/PM. Fast individual tooltips and accessibility text retain the full date, minute, and time zone. No redemption control.
- Keep awake supports timed sessions and Never, with explicit approval, startup, active, and shutdown states. Active status is confirmed against the system sleep setting. Never removes the timer; sleep is still restored when the app exits or a discharging battery reaches 15%.
- A bundled privileged helper requests macOS administrator approval, restores sleep on timeout or connection loss, and reports activation errors directly in the app.
- Explicit Renews versus Plan ends, with distinct icons; neutral Cycle ends for older metadata without provenance.
- Discount expiry is not treated as renewal. Dates are not copied between accounts based on matching workspace display names.
- Calendar-day countdowns distinguish Today, Tomorrow, and Date passed.
- Upstream Claude throttling, Retry-After handling, and cached usage behavior.

## Validation

- 125 Swift tests and 40 Windows unit tests passed, including expiry formatting at the seven-day boundary, AM/PM and time-zone formatting, keep-awake lifecycle and restoration, and authenticated exhausted-account switching.
- Light and dark SwiftUI renderings reviewed.
- Release build and strict code-signing verification passed.
- A one-minute administrator-approved keep-awake session confirmed that the system sleep setting became active and returned to normal at expiry. Physical lid-closed behavior was not independently tested.
- Native Foundation networking returned HTTP 200 for the RSS update feed.
- Native UI inspection timed out; visual verification used the app renderer, with installation and live refresh verified separately.

Screenshots contain sample accounts. Private local paths, installation logs, and account data are excluded from this document.

## Project credits

App credits, bundled CREDITS.txt, package metadata, and project pages identify Keystone Science, Nathan Stone, and Jackson Stone. The header remains plain Codex Vitals. The existing signed update feed, credential-storage identifiers, package identities, and inherited open-source license notices remain stable.

Light and dark credit renders are available in `docs/credits.png` and `docs/credits-dark.png`. Existing account storage and active sign-ins are retained across app updates.
