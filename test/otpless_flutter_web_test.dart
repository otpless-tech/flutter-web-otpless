// Runs on Chrome only: this package imports `dart:html` and `dart:js`, so the
// Dart VM cannot even compile it. Always:
//
//     flutter test --platform chrome        (or: make test)
//
// A bare `flutter test` fails to load with "Undefined name 'context'" — that is
// the VM rejecting web-only libraries, not a bug in these tests.
@TestOn('browser')
library otpless_flutter_web_test;

import 'dart:async';
import 'dart:convert';
import 'dart:js' as js;

import 'package:flutter_test/flutter_test.dart';
import 'package:otpless_flutter_web/otpless_flutter_web.dart';

/// The names this package calls on `window`. They are installed by the OTPLESS
/// browser bundle (`https://otpless.com/v2/flutter.js`, built from the
/// `vegapunk` repo's `src/auth-files/flutter.ts`). They are a contract this
/// package cannot verify at compile time — see `api/js-interop-surface.txt`.
const initiateAuth = 'initiateAuth';
const verifyAuth = 'verifyAuth';
const startHeadless = 'startHeadless';
const openLoginPage = 'openLoginPage';
const getResponse = 'getResponse';

/// Installs a stub for a global JS function and records the argument it is
/// called with. Without this arrangement `js.context.callMethod(name, ...)`
/// throws, because in a bare test page the OTPLESS bundle does not exist.
List<String> stubGlobal(String name) {
  final calls = <String>[];
  js.context[name] = (String? arg) {
    calls.add(arg ?? '<null>');
    return null;
  };
  return calls;
}

/// Invokes the `window.getResponse` slot the package installed. It holds a Dart
/// closure (the package assigns it from Dart), so it is called as a Dart
/// function rather than through `JsFunction.apply`.
void callGetResponse(String message) {
  (js.context[getResponse] as Function)(message);
}

void clearGlobals() {
  for (final name in [
    initiateAuth,
    verifyAuth,
    startHeadless,
    openLoginPage,
    getResponse,
  ]) {
    js.context.deleteProperty(name);
  }
}

void main() {
  setUp(clearGlobals);
  tearDown(clearGlobals);

  group('request marshalling', () {
    test('initiateOAuth sends channel OAUTH with the given channelType', () {
      final calls = stubGlobal(initiateAuth);

      Otpless().initiateOAuth((_) {}, 'GMAIL');

      expect(calls, hasLength(1));
      expect(jsonDecode(calls.single), {
        'channelType': 'GMAIL',
        'channel': 'OAUTH',
      });
    });

    test('initiatePhoneAuth adds channel PHONE and keeps the request keys', () {
      final calls = stubGlobal(initiateAuth);

      Otpless().initiatePhoneAuth(
        (_) {},
        {'phone': '9876543210', 'countryCode': '91'},
      );

      expect(calls, hasLength(1));
      expect(jsonDecode(calls.single), {
        'phone': '9876543210',
        'countryCode': '91',
        'channel': 'PHONE',
      });
    });

    test('initiateEmailAuth adds channel EMAIL and keeps the request keys', () {
      final calls = stubGlobal(initiateAuth);

      Otpless().initiateEmailAuth((_) {}, {'email': 'a@b.com'});

      expect(calls, hasLength(1));
      expect(jsonDecode(calls.single), {
        'email': 'a@b.com',
        'channel': 'EMAIL',
      });
    });

    test('verifyAuth forwards the request verbatim and adds no channel', () {
      final calls = stubGlobal(verifyAuth);

      Otpless().verifyAuth((_) {}, {'phone': '9876543210', 'otp': '123456'});

      expect(calls, hasLength(1));
      // Note the asymmetry with initiate*: verifyAuth does NOT inject a
      // `channel` key. The caller must supply everything the backend needs.
      expect(jsonDecode(calls.single), {
        'phone': '9876543210',
        'otp': '123456',
      });
    });

    test('headlessResponse calls startHeadless with no arguments', () {
      final calls = <int>[];
      js.context[startHeadless] = () {
        calls.add(1);
        return null;
      };

      Otpless().headlessResponse((_) {});

      expect(calls, hasLength(1));
    });

    test('openLoginPage calls the openLoginPage global', () {
      final calls = <int>[];
      js.context[openLoginPage] = () {
        calls.add(1);
        return null;
      };

      Otpless().openLoginPage((_) {});

      expect(calls, hasLength(1));
    });
  });

  group('callback wiring', () {
    test('registers window.getResponse after dispatching the call', () {
      stubGlobal(initiateAuth);

      Otpless().initiatePhoneAuth((_) {}, {'phone': '9876543210'});

      expect(js.context[getResponse], isNotNull);
    });

    test('a non-verify call forwards every message to the caller', () {
      stubGlobal(initiateAuth);
      final received = <dynamic>[];

      Otpless().initiatePhoneAuth(received.add, {'phone': '9876543210'});

      // Simulate the browser bundle answering.
      final payload = jsonEncode({
        'responseType': 'INITIATE',
        'statusCode': 200,
      });
      callGetResponse(payload);

      expect(received, [payload]);
    });

    test('verifyAuth forwards ONLY responseType ONETAP to the caller', () {
      stubGlobal(verifyAuth);
      final received = <dynamic>[];

      Otpless().verifyAuth(received.add, {'otp': '123456'});

      // Everything that is not ONETAP is dropped on the floor by design —
      // see otpless_web.dart executeFunction(). A FAILED response to a wrong
      // OTP therefore never reaches the merchant's callback through verifyAuth.
      callGetResponse(
          jsonEncode({'responseType': 'FAILED', 'statusCode': 400}));
      expect(received, isEmpty);

      final onetap = jsonEncode({
        'responseType': 'ONETAP',
        'statusCode': 200,
      });
      callGetResponse(onetap);
      expect(received, [onetap]);
    });
  });

  group('known defects — characterisation tests, not endorsements', () {
    // These pin behaviour that is wrong but shipped. If one of them fails you
    // have probably FIXED the bug: update the test and the "Known defects"
    // section of CLAUDE.md together. Do not "make it pass" by reverting.

    test(
      'a call made before the OTPLESS bundle loads is silently swallowed '
      'and the callback is never registered',
      () async {
        // No stub installed: this is a page where flutter.js has not loaded
        // (or loaded without variant="HEADLESS"), which is the single most
        // common merchant misconfiguration.
        //
        // `executeFunction` is declared `async` but returns `void`, so the
        // NoSuchMethodError from `js.context.callMethod` is routed to the
        // enclosing Zone instead of to the caller. A merchant app installs no
        // zone handler, so it goes nowhere: nothing happens, no exception
        // reaches their code, and the callback is never wired up.
        //
        // runZonedGuarded here plays the part of "somebody who is listening",
        // which is exactly what production is not.
        Object? escaped;
        runZonedGuarded(
          () => Otpless().initiatePhoneAuth((_) {}, {'phone': '9876543210'}),
          (e, _) => escaped = e,
        );
        // The error is delivered asynchronously — that is the whole problem.
        await Future<void>.delayed(Duration.zero);

        expect(
          escaped,
          isA<NoSuchMethodError>(),
          reason: 'the failure exists — it is just delivered to the zone, '
              'not to the caller',
        );
        expect(
          js.context[getResponse],
          isNull,
          reason: 'callback registration happens after the failing call, so it '
              'never runs — the merchant callback is dead',
        );
      },
    );

    test('getResponse is a single global slot, so the newest call wins', () {
      // Two in-flight requests cannot coexist: the second overwrites the
      // first callback, and any late response for the first is delivered to
      // the second caller.
      stubGlobal(initiateAuth);
      final first = <dynamic>[];
      final second = <dynamic>[];

      Otpless().initiatePhoneAuth(first.add, {'phone': '1111111111'});
      Otpless().initiateEmailAuth(second.add, {'email': 'a@b.com'});

      callGetResponse('for-the-first-call');

      expect(first, isEmpty);
      expect(second, ['for-the-first-call']);
    });
  });
}
