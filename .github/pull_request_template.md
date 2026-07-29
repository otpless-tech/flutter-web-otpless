<!-- Read CLAUDE.md before filling this in. It is the binding constitution, and
     it lists the known defects you should not be surprised by. -->

## What and why

<!-- One paragraph. What changes for a merchant? -->

## Constitution checklist

- [ ] **I. Public API** — no public member or **parameter name** renamed or
      removed, OR the break is intentional, `make surface-update` was run, and
      the semver impact is stated below. `api/*.txt` was not hand-edited.
- [ ] **I. JS-interop surface** — `api/js-interop-surface.txt` unchanged, OR the
      matching change has already shipped in the CDN bundle built from
      `vegapunk` (`src/auth-files/flutter.ts`). A rename on one side only breaks
      merchants silently — no compile error, no analyzer warning.
- [ ] **II. Host page** — no new `window` global written; `kIsWeb` guard intact;
      no exception can escape into the merchant's widget tree.
- [ ] **III. Privacy** — no phone/email/OTP/token logged; no new network call.
- [ ] **V. Dependencies** — runtime deps still `flutter` only; no dev dependency
      added that would raise the published `sdk:` lower bound.
- [ ] **VI. Verification** — `make gate` run locally and its output pasted below.

## Known defects

- [ ] This PR does not touch defect #1 (silent swallow), #2 (single
      `getResponse` slot), or #3 (`verifyAuth` ONETAP-only filter).
- [ ] This PR **fixes** one of them — then its characterisation test and the
      CLAUDE.md "Known defects" section are updated in the same commit, and the
      merchant-visible behaviour change is called out below.

## Contract impact

**Parity:** <!-- `ported in <repo>#NN` / `N/A — <reason>` / `port ticket <link>` -->

If this changes the response contract or the channel vocabulary, the hub's
`docs/PARITY.md` §E is updated in the same cycle.

## Semver impact

<!-- patch / minor / major, and why. Note: nothing has been published since
     1.2.6 (2024-05-21), so also say whether this is meant to ship. -->

## `make gate` output

```
<!-- paste the tail here. "Should pass" is not a verification. -->
```

## Browser verification

<!-- Required for any change to executeFunction or to a JS-global name: no test
     in this repo loads the real browser bundle. Say what you exercised with
     `cd example && flutter run -d chrome` against a real app id, or write
     "not applicable — no runtime behaviour changed". -->
