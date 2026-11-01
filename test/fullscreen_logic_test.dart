// Full screen help, the logic only (no widgets): which device it is, who sees the help, and what the
// Full Screen button does, with made-up devices.
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/ui/platform/fullscreen_controller.dart';
import 'package:unmatched_game/ui/platform/fullscreen_help_storage.dart';
import 'package:unmatched_game/ui/platform/platform_info.dart';
import 'package:unmatched_game/ui/platform/platform_info_service.dart';
import 'package:unmatched_game/ui/platform/platform_info_service_stub.dart';

const uaIphoneSafari =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';
const uaIphoneChrome =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/126.0.6478.153 Mobile/15E148 Safari/604.1';
const uaIphoneFirefox =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/127.0 Mobile/15E148 Safari/605.1.15';
const uaIphoneEdge =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) EdgiOS/126.2592.88 Version/17.0 Mobile/15E148 Safari/604.1';
const uaIphoneOpera =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) OPiOS/16.0.15.124050 Mobile/15E148 Safari/9537.53';
// iPadOS 13+ default ("Request Desktop Website"): a Mac to everything but touch.
const uaIpadDesktopMode =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15';
const uaIpadDesktopChrome =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/126.0.6478.153 Mobile/15E148 Safari/604.1';
// "Request Mobile Website".
const uaIpadMobileMode =
    'Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';
const uaIpadChrome =
    'Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/126.0.6478.153 Mobile/15E148 Safari/604.1';
const uaIpadFirefox =
    'Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/127.0 Mobile/15E148 Safari/605.1.15';
const uaMacSafari =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15';
const uaAndroidChrome =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';
const uaWindowsChrome = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
const uaLinuxFirefox = 'Mozilla/5.0 (X11; Linux x86_64; rv:127.0) Gecko/20100101 Firefox/127.0';

PlatformInfo iphoneSafari({bool standalone = false}) => PlatformInfo(userAgent: uaIphoneSafari, platform: 'iPhone', maxTouchPoints: 5, isStandalone: standalone);
PlatformInfo ipadDesktop({bool standalone = false, bool fullscreen = true, String ua = uaIpadDesktopMode}) =>
    PlatformInfo(userAgent: ua, platform: 'MacIntel', maxTouchPoints: 5, isStandalone: standalone, fullscreenSupported: fullscreen);
PlatformInfo ipadMobile({bool standalone = false, bool fullscreen = true, String ua = uaIpadMobileMode}) =>
    PlatformInfo(userAgent: ua, platform: 'iPad', maxTouchPoints: 5, isStandalone: standalone, fullscreenSupported: fullscreen);
PlatformInfo mac() => const PlatformInfo(userAgent: uaMacSafari, platform: 'MacIntel', maxTouchPoints: 0, fullscreenSupported: true);
PlatformInfo android() => const PlatformInfo(userAgent: uaAndroidChrome, platform: 'Linux armv81', maxTouchPoints: 5, fullscreenSupported: true);
PlatformInfo windows() => const PlatformInfo(userAgent: uaWindowsChrome, platform: 'Win32', fullscreenSupported: true);

void main() {
  group('who the device is (PlatformInfo)', () {
    test('iPhone Safari', () {
      final i = iphoneSafari();
      expect(i.deviceKind, DeviceKind.iphone);
      expect(i.browser, BrowserKind.safari);
      expect(i.isIos, isTrue);
    });
    test('iPhone Chrome, Firefox, Edge and Opera are other browsers (all WebKit underneath)', () {
      for (final ua in [uaIphoneChrome, uaIphoneFirefox, uaIphoneEdge, uaIphoneOpera]) {
        final i = PlatformInfo(userAgent: ua, platform: 'iPhone', maxTouchPoints: 5);
        expect(i.deviceKind, DeviceKind.iphone, reason: ua);
        expect(i.browser, BrowserKind.other, reason: ua);
      }
    });
    test('iPad Safari in the default desktop mode (a Mac user agent with touch) is an iPad', () {
      final i = ipadDesktop();
      expect(i.userAgent, contains('Macintosh'));
      expect(i.deviceKind, DeviceKind.ipad);
      expect(i.browser, BrowserKind.safari);
    });
    test('iPad Safari with "Request Mobile Website" (iPad in the user agent) is an iPad', () {
      final i = ipadMobile();
      expect(i.deviceKind, DeviceKind.ipad);
      expect(i.browser, BrowserKind.safari);
    });
    test('iPad Chrome and Firefox, in either mode, are an iPad with another browser', () {
      for (final i in [ipadMobile(ua: uaIpadChrome), ipadMobile(ua: uaIpadFirefox), ipadDesktop(ua: uaIpadDesktopChrome)]) {
        expect(i.deviceKind, DeviceKind.ipad, reason: i.userAgent);
        expect(i.browser, BrowserKind.other, reason: i.userAgent);
      }
    });
    test('a real Mac (Macintosh, no touch points) is NOT iOS', () {
      final i = mac();
      expect(i.deviceKind, DeviceKind.mac);
      expect(i.isIos, isFalse);
      expect(i.browser, BrowserKind.other, reason: 'the question is only asked on iOS');
    });
    test('one touch point is not an iPad (a touch screen Mac does not exist; a stylus on a PC is not one either)', () {
      expect(const PlatformInfo(userAgent: uaMacSafari, platform: 'MacIntel', maxTouchPoints: 1).deviceKind, DeviceKind.mac);
      expect(const PlatformInfo(userAgent: uaMacSafari, platform: 'MacIntel', maxTouchPoints: 2).deviceKind, DeviceKind.ipad);
    });
    test('Android, Windows and Linux', () {
      expect(android().deviceKind, DeviceKind.android, reason: 'an Android user agent also says Linux and Safari');
      expect(windows().deviceKind, DeviceKind.windows);
      expect(const PlatformInfo(userAgent: uaLinuxFirefox, platform: 'Linux x86_64').deviceKind, DeviceKind.linux);
      expect(const PlatformInfo().deviceKind, DeviceKind.other);
    });
    test('the platform string alone finds an iPad when the user agent is hidden (privacy modes)', () {
      expect(const PlatformInfo(userAgent: '', platform: 'MacIntel', maxTouchPoints: 5).deviceKind, DeviceKind.ipad);
      expect(const PlatformInfo(userAgent: '', platform: 'MacIntel', maxTouchPoints: 0).deviceKind, DeviceKind.mac);
    });
    test('browser names for the debug panel', () {
      expect(const PlatformInfo(userAgent: uaIphoneChrome).browserName, 'Chrome (iOS)');
      expect(const PlatformInfo(userAgent: uaAndroidChrome).browserName, 'Chrome');
      expect(const PlatformInfo(userAgent: uaIphoneSafari).browserName, 'Safari');
    });
  });

  group('shouldShowFullscreenHelp', () {
    bool show(PlatformInfo i, {bool dismissed = false, bool inMatch = false}) => shouldShowFullscreenHelp(i, dismissed: dismissed, inMatch: inMatch);

    test('iPhone Safari: yes', () => expect(show(iphoneSafari()), isTrue));
    test('iPhone Chrome and Firefox: yes', () {
      for (final ua in [uaIphoneChrome, uaIphoneFirefox]) {
        expect(show(PlatformInfo(userAgent: ua, platform: 'iPhone', maxTouchPoints: 5)), isTrue);
      }
    });
    test('iPad, desktop mode, mobile mode and Chrome: yes', () {
      for (final i in [ipadDesktop(), ipadMobile(), ipadMobile(ua: uaIpadChrome), ipadDesktop(ua: uaIpadDesktopChrome)]) {
        expect(show(i), isTrue, reason: i.userAgent);
      }
    });
    test('a real Mac, Android and desktops: no', () {
      expect(show(mac()), isFalse);
      expect(show(android()), isFalse);
      expect(show(windows()), isFalse);
      expect(show(const PlatformInfo(userAgent: uaLinuxFirefox)), isFalse);
    });
    test('already on the Home Screen (standalone): no', () {
      expect(show(iphoneSafari(standalone: true)), isFalse);
      expect(show(ipadDesktop(standalone: true)), isFalse);
      expect(show(ipadMobile(standalone: true)), isFalse);
    });
    test('dismissed before: no', () {
      expect(show(iphoneSafari(), dismissed: true), isFalse);
      expect(show(ipadDesktop(), dismissed: true), isFalse);
    });
    test('during a match: never', () {
      expect(show(iphoneSafari(), inMatch: true), isFalse);
      expect(show(ipadDesktop(), inMatch: true), isFalse);
      expect(show(iphoneSafari(), inMatch: true, dismissed: true), isFalse);
    });
    test('all four conditions have to hold (exhaustive)', () {
      for (final standalone in [false, true]) {
        for (final dismissed in [false, true]) {
          for (final inMatch in [false, true]) {
            for (final ios in [false, true]) {
              final info = ios ? iphoneSafari(standalone: standalone) : windows().copyWith(isStandalone: standalone);
              expect(show(info, dismissed: dismissed, inMatch: inMatch), ios && !standalone && !dismissed && !inMatch);
            }
          }
        }
      }
    });
  });

  group('what the Full Screen button does (fullscreenActionFor)', () {
    test('iPhone: straight to the help, never the API, even with the API "supported"', () {
      expect(fullscreenActionFor(iphoneSafari().copyWith(fullscreenSupported: true)), FullscreenAction.help);
    });
    test('iPad: the API first, then the help', () {
      expect(fullscreenActionFor(ipadDesktop()), FullscreenAction.apiThenHelp);
      expect(fullscreenActionFor(ipadMobile()), FullscreenAction.apiThenHelp);
    });
    test('iPad without the API: the help directly', () {
      expect(fullscreenActionFor(ipadDesktop(fullscreen: false)), FullscreenAction.help);
    });
    test('Android, Mac, Windows, Linux: the API', () {
      for (final i in [android(), mac(), windows()]) {
        expect(fullscreenActionFor(i), FullscreenAction.api, reason: '${i.deviceKind}');
      }
    });
    test('a browser with no Fullscreen API and no iOS: no button', () {
      expect(fullscreenActionFor(windows().copyWith(fullscreenSupported: false)), FullscreenAction.hidden);
    });
    test('standalone: no button on any device', () {
      for (final i in [iphoneSafari(standalone: true), ipadDesktop(standalone: true), ipadMobile(standalone: true), android().copyWith(isStandalone: true)]) {
        expect(fullscreenActionFor(i), FullscreenAction.hidden, reason: '${i.deviceKind}');
      }
    });
    test('the step 1 wording', () {
      expect(shareStepFor(DeviceKind.iphone, BrowserKind.safari), ShareStep.iphoneSafari);
      expect(shareStepFor(DeviceKind.ipad, BrowserKind.safari), ShareStep.ipadSafari);
      expect(shareStepFor(DeviceKind.iphone, BrowserKind.other), ShareStep.otherBrowser);
      expect(shareStepFor(DeviceKind.ipad, BrowserKind.other), ShareStep.otherBrowser);
    });
  });

  group('FullscreenController', () {
    FullscreenController make(FakePlatformInfoService s, [FullscreenHelpStorage? storage]) =>
        FullscreenController(platform: s, storage: storage ?? MemoryFullscreenHelpStorage());

    test('iPad where the Fullscreen API works: enters full screen, no dialog, then the button exits it', () async {
      final s = FakePlatformInfoService(ipadDesktop());
      final c = make(s);
      expect(await c.press(), FullscreenPress.entered);
      expect(s.requests, 1);
      expect(c.isFullscreen, isTrue);
      expect(await c.press(), FullscreenPress.exited);
      expect(s.exits, 1);
      expect(c.isFullscreen, isFalse);
      c.dispose();
    });

    test('iPad where the API refuses: falls back to the dialog', () async {
      final s = FakePlatformInfoService(ipadDesktop(), behavior: FakeFullscreen.refuses);
      final c = make(s);
      expect(await c.press(), FullscreenPress.showHelp);
      expect(s.requests, 1, reason: 'it did try first');
      c.dispose();
    });

    test('iPad where the API throws: falls back to the dialog, no crash', () async {
      final s = FakePlatformInfoService(ipadMobile(), behavior: FakeFullscreen.throws);
      final c = make(s);
      expect(await c.press(), FullscreenPress.showHelp);
      c.dispose();
    });

    test('iPad where the API is missing: the dialog, without trying', () async {
      final s = FakePlatformInfoService(ipadDesktop(fullscreen: false), behavior: FakeFullscreen.missing);
      final c = make(s);
      expect(await c.press(), FullscreenPress.showHelp);
      expect(s.requests, 0);
      c.dispose();
    });

    test('iPhone never attempts the Fullscreen API: straight to the dialog', () async {
      final s = FakePlatformInfoService(iphoneSafari().copyWith(fullscreenSupported: true));
      final c = make(s);
      expect(await c.press(), FullscreenPress.showHelp);
      expect(s.requests, 0);
      c.dispose();
    });

    test('the API call is made synchronously inside press (Safari needs the user gesture)', () {
      final s = FakePlatformInfoService(ipadDesktop());
      final c = make(s);
      c.press(); // not awaited: nothing has had a chance to run
      expect(s.requests, 1, reason: 'the request must already have been made when press() returns');
      c.dispose();
    });

    test('Android and desktop: the API; a refusal just does nothing (no dialog there)', () async {
      for (final info in [android(), windows(), mac()]) {
        final ok = FakePlatformInfoService(info);
        final c = make(ok);
        expect(await c.press(), FullscreenPress.entered, reason: '${info.deviceKind}');
        c.dispose();
        final no = FakePlatformInfoService(info, behavior: FakeFullscreen.refuses);
        final d = make(no);
        expect(await d.press(), FullscreenPress.nothing);
        d.dispose();
      }
    });

    test('standalone iPhone or iPad: no button, pressing does nothing', () async {
      for (final info in [iphoneSafari(standalone: true), ipadDesktop(standalone: true)]) {
        final s = FakePlatformInfoService(info);
        final c = make(s);
        expect(c.buttonVisible, isFalse);
        expect(c.shouldAutoShowHelp, isFalse);
        expect(await c.press(), FullscreenPress.nothing);
        expect(s.requests, 0);
        c.dispose();
      }
    });

    test('the button label stays in sync with the system entering and leaving full screen', () async {
      final s = FakePlatformInfoService(android());
      final c = make(s);
      var notified = 0;
      c.addListener(() => notified++);
      expect(c.isFullscreen, isFalse);
      s.setFullscreen(true); // the system (Esc, a swipe, the other tab) changed it
      await pumpEventQueue();
      expect(c.isFullscreen, isTrue);
      s.setFullscreen(false);
      await pumpEventQueue();
      expect(c.isFullscreen, isFalse);
      expect(notified, greaterThanOrEqualTo(2));
      c.dispose();
    });

    test('dismissed: no automatic dialog, but the button still opens it', () async {
      final storage = MemoryFullscreenHelpStorage(dismissed: true);
      final c = make(FakePlatformInfoService(iphoneSafari()), storage);
      await c.load();
      expect(c.dismissed, isTrue);
      expect(c.shouldAutoShowHelp, isFalse);
      expect(await c.press(), FullscreenPress.showHelp, reason: 'Settings can always reopen it');
      c.dispose();
    });

    test('markDismissed saves the flag and a new controller reads it back', () async {
      final storage = MemoryFullscreenHelpStorage();
      final a = make(FakePlatformInfoService(iphoneSafari()), storage);
      await a.load();
      expect(a.shouldAutoShowHelp, isTrue);
      await a.markDismissed();
      expect(storage.dismissed, isTrue);
      expect(a.shouldAutoShowHelp, isFalse);
      final b = make(FakePlatformInfoService(iphoneSafari()), storage); // "restart"
      await b.load();
      expect(b.shouldAutoShowHelp, isFalse);
      await b.clearDismissed();
      expect(b.shouldAutoShowHelp, isTrue);
      a.dispose();
      b.dispose();
    });

    test('storage that throws never crashes: it reads as not dismissed and writes are ignored', () async {
      final storage = MemoryFullscreenHelpStorage(failing: true);
      final c = make(FakePlatformInfoService(iphoneSafari()), storage);
      await c.load();
      expect(c.dismissed, isFalse);
      expect(c.shouldAutoShowHelp, isTrue);
      await c.markDismissed();
      expect(c.dismissed, isTrue, reason: 'still remembered for this session');
      await c.clearDismissed();
      c.dispose();
    });

    test('in a match: the help never shows, whatever else is true', () async {
      final c = make(FakePlatformInfoService(iphoneSafari()));
      await c.load();
      expect(c.shouldAutoShowHelp, isTrue);
      c.inMatch = true;
      expect(c.shouldAutoShowHelp, isFalse);
      c.inMatch = false;
      expect(c.shouldAutoShowHelp, isTrue);
      c.dispose();
    });

    test('iPad offers "install the app" as the better way; the others do not', () {
      expect(make(FakePlatformInfoService(ipadDesktop())).installOptionVisible, isTrue);
      expect(make(FakePlatformInfoService(ipadDesktop(standalone: true))).installOptionVisible, isFalse);
      expect(make(FakePlatformInfoService(iphoneSafari())).installOptionVisible, isFalse);
      expect(make(FakePlatformInfoService(windows())).installOptionVisible, isFalse);
    });

    test('swapping the device (the debug panel) uses its own storage and leaves the real one alone', () async {
      final real = MemoryFullscreenHelpStorage(dismissed: true);
      final c = make(FakePlatformInfoService(windows()), real);
      await c.load();
      final sim = MemoryFullscreenHelpStorage();
      await c.useService(FakePlatformInfoService(iphoneSafari()), storage: sim);
      expect(c.simulated, isTrue);
      expect(c.info.deviceKind, DeviceKind.iphone);
      expect(c.dismissed, isFalse, reason: 'the simulated storage says so');
      await c.markDismissed();
      expect(sim.dismissed, isTrue);
      expect(real.dismissed, isTrue);
      expect(real.writes, 0, reason: 'the real flag was never written');
      c.dispose();
    });
  });

  group('non-web builds', () {
    test('the stub answers without touching the browser: already full screen, no button, no help', () {
      final s = StubPlatformInfoService();
      expect(s.read().isStandalone, isTrue);
      expect(s.isFullscreen, isTrue);
      final c = FullscreenController(platform: s, storage: MemoryFullscreenHelpStorage());
      expect(c.buttonVisible, isFalse);
      expect(c.shouldAutoShowHelp, isFalse);
      c.dispose();
    });
  });
}
