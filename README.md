# otpless_flutter_web

OTPLESS authentication for **Flutter web** applications: phone/email OTP, magic
link, and OAuth sign-in, driven by the OTPLESS browser SDK.

pub.dev: [`otpless_flutter_web`](https://pub.dev/packages/otpless_flutter_web)

> ### Release status — read before you depend on this
>
> The latest published version is **1.2.6, published 2024-05-21**. There has been
> **no release in over two years**, and `main` is the same tree that produced it.
> If you are choosing an OTPLESS integration today, take that into account.
>
> This note is here because it is a fact merchants deserve to see in the place
> they look first, not because anything is known to be broken.

> ### This is the web package, not the mobile one
>
> For Flutter **mobile** (Android/iOS) use
> [`otpless_headless_flutter`](https://pub.dev/packages/otpless_headless_flutter)
> instead. It is a different package with a different API and a different
> response contract.

---

## How it works

This package is a thin `dart:js` bridge — about 110 lines. It contains no
authentication logic. All of that lives in a browser script **you load
yourself**, which installs a handful of functions on `window`; this package calls
them and installs one callback (`window.getResponse`) to receive replies.

That has one practical consequence worth knowing up front: if the script tag is
missing or misconfigured, calls to this package currently **fail silently** — no
exception, no callback. See [Troubleshooting](#troubleshooting).

## Install

```bash
flutter pub add otpless_flutter_web
```

## Set up: add the OTPLESS script to `web/index.html`

This step is **required**. Without it nothing works.

```html
<script
  data-appid="{YOUR_APP_ID}"
  src="https://otpless.com/v2/flutter.js"
  id="otpless-sdk"
  type="text/javascript"
  variant="HEADLESS"
></script>
```

All four attributes matter: `data-appid` identifies your OTPLESS app, `id` is how
the bundle finds its own tag, and `variant="HEADLESS"` selects the headless flow.
Omit `variant` and you get the hosted login-page flow instead.

## Usage

```dart
import 'package:otpless_flutter_web/otpless_flutter_web.dart';

final _otpless = Otpless();
```

### 1. Subscribe to results

Do this once, in `initState`. `headlessResponse` is the channel through which
**all** responses arrive — including failures that `verifyAuth` itself will not
report to you (see [Troubleshooting](#troubleshooting)).

```dart
@override
void initState() {
  super.initState();
  _otpless.headlessResponse(onOtplessResult);
}

void onOtplessResult(dynamic result) {
  // `result` is a JSON *String*, not a Map. Decode it yourself:
  //   final data = jsonDecode(result as String);
  //   data['responseType'], data['statusCode'], data['response'], data['success']
  setState(() => _lastResponse = result);
}
```

### 2. Phone or email OTP

```dart
// Send the OTP
_otpless.initiatePhoneAuth(onOtplessResult, {
  'phone': '9876543210',
  'countryCode': '91',       // no leading '+'
});

_otpless.initiateEmailAuth(onOtplessResult, {
  'email': 'user@example.com',
});

// Verify it — pass the same identity plus the code
_otpless.verifyAuth(onOtplessResult, {
  'phone': '9876543210',
  'countryCode': '91',
  'otp': '123456',
});
```

`initiatePhoneAuth` and `initiateEmailAuth` add `"channel": "PHONE"` / `"EMAIL"`
to the payload for you. `verifyAuth` adds **nothing** — pass every field the
request needs.

### 3. OAuth

```dart
_otpless.initiateOAuth(onOtplessResult, 'GMAIL');       // or 'TRUE_CALLER', etc.
```

The channel type string is sent as `{"channelType": "<value>", "channel": "OAUTH"}`.

### 4. Hosted login page (non-headless)

```dart
_otpless.openLoginPage(onOtplessResult);
```

Drop the `variant="HEADLESS"` attribute from the script tag when using this.

## API

| Member | Signature |
|---|---|
| `Otpless()` | Constructor. **Side effect:** if the page URL carries a `code` query parameter, it calls `headlessResponse` internally. |
| `headlessResponse` | `void headlessResponse(OtplessResultCallback cb)` — subscribe to results (calls `window.startHeadless`). |
| `initiatePhoneAuth` | `void initiatePhoneAuth(OtplessResultCallback cb, Map<String, dynamic> request)` |
| `initiateEmailAuth` | `void initiateEmailAuth(OtplessResultCallback cb, Map<String, dynamic> request)` |
| `initiateOAuth` | `void initiateOAuth(OtplessResultCallback cb, String channelType)` |
| `verifyAuth` | `void verifyAuth(OtplessResultCallback cb, dynamic data)` |
| `openLoginPage` | `void openLoginPage(OtplessResultCallback cb)` |
| `getCodeForParams` | `String? getCodeForParams()` — reads the `code` query parameter from the page URL. |
| `OtplessResultCallback` | `void Function(dynamic)` — receives a JSON **String**. |

Every method returns `void` and is fire-and-forget; results arrive on the
callback. On non-web platforms every method is a no-op.

## Response shape

Responses arrive as a JSON string of roughly:

```json
{
  "responseType": "ONETAP",
  "response": { "token": "..." },
  "statusCode": 200,
  "success": true
}
```

> **If you are porting from the OTPLESS Android or iOS SDK:** the web contract is
> **not** the native one. `success` is web-only — no native SDK sends it — and
> `response` may be absent. `SESSION_END` and `LOADING_STATE` are web-only event
> types, while seven native response types (`INITIATE`, `VERIFY`, `SDK_READY`,
> `DELIVERY_STATUS`, `AUTH_TERMINATED`, `MFA_FACTOR_COMPLETED`,
> `AUTO_FLOW_ACTION`) do not appear on web. Web channels are the three coarse
> buckets `PHONE` / `EMAIL` / `OAUTH`. Do not assume payloads match.

## Troubleshooting

**Nothing happens when I call `initiatePhoneAuth` — no error, no callback.**
Almost always a missing or misconfigured script tag in `web/index.html`. This is
the package's worst behaviour: the underlying `NoSuchMethodError` is routed to a
Zone rather than to you, so it is invisible. Check, in order:

1. the `<script>` tag is present and `id="otpless-sdk"`;
2. `data-appid` is your real app id;
3. `variant="HEADLESS"` is present if you are using the headless methods;
4. the browser devtools Network tab shows `flutter.js` loading with 200;
5. `window.initiateAuth` is defined in the devtools console.

**A wrong OTP produces no callback.** `verifyAuth` only forwards responses whose
`responseType` is `ONETAP`. Failures reach you through the `headlessResponse`
subscription instead — so always subscribe with `headlessResponse` in
`initState`, not only per call.

**Two requests in flight and the wrong callback fires.** There is one global
callback slot, so the newest call wins. Serialise your requests.

## Example

`example/` is a runnable demo:

```bash
cd example
flutter run -d chrome
```

## Development

Requires Flutter (stable) and **Chrome** — this package imports `dart:html` and
`dart:js`, so the Dart VM cannot compile it, and a bare `flutter test` fails to
*load*. Always use `--platform chrome`, or just use the Makefile.

```bash
make install
make gate        # THE verification gate — run this before every PR
```

`make gate` runs:

| Step | Command | Protects |
|---|---|---|
| format | `dart format --set-exit-if-changed .` | formatting |
| analyze | `scripts/check-analyzer-baseline.sh` | `flutter analyze` (errors/warnings fatal) + no new analyzer infos |
| test | `flutter test --platform chrome` | 11 unit tests |
| surface | `dart run tool/api_dump.dart` | the public Dart surface **and** the `window` function names, both committed as goldens under `api/` |

Other targets: `make format-fix`, `make surface-update`, `make analyze-update`,
`make example-build`, `make help`.

**What a green gate does not tell you.** Every test stubs the browser bundle.
Nothing here loads `https://otpless.com/v2/flutter.js` or reaches the OTPLESS
backend, and there are no widget or integration tests. Green means the JS-interop
marshalling did not regress — it is not a coverage claim and not evidence that
authentication works.

Contributors: read [`CLAUDE.md`](./CLAUDE.md) first. It is the binding
constitution for this repo, and it lists the known defects you should not be
surprised by.

## Links

- [OTPLESS Flutter platform docs](https://otpless.com/platforms/flutter)
- [pub.dev package](https://pub.dev/packages/otpless_flutter_web)
- [`CHANGELOG.md`](./CHANGELOG.md)

## License

MIT — see [LICENSE](./LICENSE).
