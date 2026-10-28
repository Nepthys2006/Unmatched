#!/usr/bin/env python3
"""
Comprehensive responsiveness and fullscreen verification across:
1. Mobile Phone (iPhone Safari, Android Chrome)
2. Tablets (iPad Safari, Android Tablet)
3. Desktop (Chromium wide & narrow)
4. Fullscreen & orientation behaviors
"""

import http.server
import os
import shutil
import socketserver
import sys
import tempfile
import threading
import time
from playwright.sync_api import sync_playwright

PORT = 8765
BUILD_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "build", "web_lan"))

class QuietHandler(http.server.SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.0"
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=BUILD_DIR, **kwargs)

    def log_message(self, format, *args):
        pass

class ReusableServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    def handle_error(self, request, client_address):
        pass

def start_server():
    server = ReusableServer(("127.0.0.1", PORT), QuietHandler)
    t = threading.Thread(target=server.serve_forever, daemon=True)
    t.start()
    return server

def setup_page(context, url):
    """Adds pre-seeded credentials before navigation so the app opens MenuScreen directly."""
    context.route("**/rest/v1/**", lambda route: route.abort())
    context.add_init_script("""
        window.localStorage.setItem('flutter.username', '"TESTER"');
        window.localStorage.setItem('flutter.accountToken', '"dummy-token"');
    """)
    page = context.new_page()
    page.goto(url)
    return page

def wait_for_menu(page, timeout_s=120):
    """Waits for the app to finish loading assets and display the MenuScreen."""
    start = time.time()
    try:
        page.wait_for_selector("flt-glass-pane", timeout=15000)
    except Exception:
        pass

    while time.time() - start < timeout_s:
        try:
            page.evaluate("""() => {
                const el = document.querySelector('flt-semantics-placeholder');
                if (el) {
                    el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
                }
            }""")
        except Exception:
            pass
        found = page.evaluate("""() => {
            const nodes = Array.from(document.querySelectorAll('flt-semantics'));
            return nodes.some(n => {
                const s = ((n.getAttribute('aria-label') || '') + ' ' + (n.textContent || '')).toUpperCase();
                return s.includes('PLAY VS AI');
            });
        }""")
        if found:
            return True
        time.sleep(1)
    return False

def find_semantics_text(page, text, timeout_ms=5000):
    start = time.time()
    while (time.time() - start) * 1000 < timeout_ms:
        found = page.evaluate("""(text) => {
            const nodes = Array.from(document.querySelectorAll('flt-semantics'));
            return nodes.some(n => {
                const s = ((n.getAttribute('aria-label') || '') + ' ' + (n.textContent || '')).toUpperCase();
                return s.includes(text.toUpperCase());
            });
        }""", text)
        if found:
            return True
        time.sleep(0.3)
    return False

def click_smallest_match(page, text, timeout_s=5):
    start = time.time()
    while time.time() - start < timeout_s:
        clicked = page.evaluate("""(text) => {
            const nodes = Array.from(document.querySelectorAll('flt-semantics'));
            const matches = nodes.filter(n => {
                const s = ((n.getAttribute('aria-label') || '') + ' ' + (n.textContent || '')).toUpperCase();
                return s.includes(text.toUpperCase());
            });
            if (matches.length === 0) return false;
            // Click smallest matching node (leaf button)
            matches.sort((a, b) => (a.textContent || '').length - (b.textContent || '').length);
            matches[0].click();
            return true;
        }""", text)
        if clicked:
            return True
        time.sleep(0.3)
    return False

def run_tests():
    sys.stdout.reconfigure(line_buffering=True)
    print(f"Serving web build from: {BUILD_DIR} on http://127.0.0.1:{PORT}", flush=True)
    server = start_server()
    time.sleep(0.5)

    cache_dir = tempfile.mkdtemp(prefix="pw_chrome_cache_")

    passes = 0
    failures = 0

    def check(name, condition, info=""):
        nonlocal passes, failures
        if condition:
            passes += 1
            print(f"PASS  {name}" + (f" ({info})" if info else ""), flush=True)
        else:
            failures += 1
            print(f"FAIL  {name}" + (f" ({info})" if info else ""), flush=True)

    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(
                headless=True,
                args=[f"--disk-cache-dir={cache_dir}"]
            )
            url = f"http://127.0.0.1:{PORT}"

            # =============================================================
            # 1. iPhone Safari (Mobile Phone)
            # =============================================================
            print("\n--- 1. Testing iPhone Safari (Mobile Phone) ---")
            iphone = p.devices["iPhone 14"]
            iphone_params = dict(iphone)
            iphone_params["viewport"] = {"width": 390, "height": 844}
            ctx_iphone = browser.new_context(**iphone_params)
            page_iphone = setup_page(ctx_iphone, url)

            # Check portrait rotate overlay
            rot_p = page_iphone.evaluate("() => window.getComputedStyle(document.getElementById('rotate')).display")
            check("iPhone: portrait shows 'Turn your phone' overlay while loading", rot_p == "flex", f"display={rot_p}")

            # Rotate to landscape: 844x390
            page_iphone.set_viewport_size({"width": 844, "height": 390})
            page_iphone.wait_for_timeout(300)
            rot_l = page_iphone.evaluate("() => window.getComputedStyle(document.getElementById('rotate')).display")
            check("iPhone: landscape hides rotate overlay", rot_l == "none", f"display={rot_l}")

            # Wait for MenuScreen to load
            menu_loaded = wait_for_menu(page_iphone, timeout_s=80)
            check("iPhone: MenuScreen loaded successfully", menu_loaded)

            vp = page_iphone.evaluate("() => [window.innerWidth, window.innerHeight]")
            check("iPhone: viewport matches landscape dimensions exactly", vp == [844, 390], f"{vp}")

            # Full screen button is present initially on iPhone before hint dismissal
            has_fs = find_semantics_text(page_iphone, "FULL SCREEN", timeout_ms=5000)
            check("iPhone: Full screen button is present before hint is shown", has_fs)

            # Click the button to trigger iOS hint dialog
            click_smallest_match(page_iphone, "FULL SCREEN")
            page_iphone.wait_for_timeout(800)

            # Verify hint dialog appeared with exact title
            hint_shown = find_semantics_text(page_iphone, "FULL SCREEN ON IPHONE", timeout_ms=4000)
            check("iPhone: clicking Full screen shows 'FULL SCREEN ON IPHONE' dialog", hint_shown)

            # Dismiss dialog by clicking 'GOT IT'
            click_smallest_match(page_iphone, "GOT IT")
            page_iphone.wait_for_timeout(800)

            # Verify localStorage saved
            tip_saved = page_iphone.evaluate("() => window.localStorage.getItem('ios-pwa-tip-shown')")
            check("iPhone: 'ios-pwa-tip-shown' saved as '1' in localStorage", tip_saved == "1", f"value={tip_saved}")

            # Verify Full screen button is now gone
            btn_dismissed = not find_semantics_text(page_iphone, "FULL SCREEN", timeout_ms=1000)
            check("iPhone: Full screen button is dismissed/hidden after Got it", btn_dismissed)

            # Rotate to portrait again -> overlay returns
            page_iphone.set_viewport_size({"width": 390, "height": 844})
            page_iphone.wait_for_timeout(300)
            rot_p2 = page_iphone.evaluate("() => window.getComputedStyle(document.getElementById('rotate')).display")
            check("iPhone: rotating back to portrait shows overlay again", rot_p2 == "flex")

            # Rotate to landscape again -> overlay hides
            page_iphone.set_viewport_size({"width": 844, "height": 390})
            page_iphone.wait_for_timeout(300)
            rot_l2 = page_iphone.evaluate("() => window.getComputedStyle(document.getElementById('rotate')).display")
            check("iPhone: rotating back to landscape hides overlay again", rot_l2 == "none")

            ctx_iphone.close()

            # iPhone Standalone (Add to Home Screen launch)
            ctx_pwa = browser.new_context(**iphone_params)
            ctx_pwa.add_init_script("""
                window.navigator.standalone = true;
                window._agy_navigator_standalone = () => true;
            """)
            page_pwa = setup_page(ctx_pwa, url)
            page_pwa.set_viewport_size({"width": 844, "height": 390})
            wait_for_menu(page_pwa, timeout_s=120)
            pwa_fs_btn = find_semantics_text(page_pwa, "FULL SCREEN", timeout_ms=2000)
            check("iPhone Home Screen (standalone): Full screen button is hidden", not pwa_fs_btn)
            ctx_pwa.close()

            # =============================================================
            # 2. iPad Safari (Tablet)
            # =============================================================
            print("\n--- 2. Testing iPad Safari (Tablet) ---")
            ipad = p.devices["iPad Pro 11"]
            ipad_params = dict(ipad)
            ipad_params["viewport"] = {"width": 834, "height": 1194}
            ctx_ipad = browser.new_context(**ipad_params)
            page_ipad = setup_page(ctx_ipad, url)

            # In iPad portrait: rotate overlay MUST NOT BE DISPLAYED (shortest side 834 >= 600)
            ipad_rot_p = page_ipad.evaluate("() => window.getComputedStyle(document.getElementById('rotate')).display")
            check("iPad: portrait DOES NOT show rotate overlay (tablet is exempt)", ipad_rot_p == "none", f"display={ipad_rot_p}")

            # In iPad landscape: width=1194, height=834
            page_ipad.set_viewport_size({"width": 1194, "height": 834})
            page_ipad.wait_for_timeout(300)
            ipad_rot_l = page_ipad.evaluate("() => window.getComputedStyle(document.getElementById('rotate')).display")
            check("iPad: landscape DOES NOT show rotate overlay", ipad_rot_l == "none", f"display={ipad_rot_l}")

            # Wait for menu
            ipad_loaded = wait_for_menu(page_ipad, timeout_s=120)
            check("iPad: MenuScreen loaded", ipad_loaded)

            ipad_vp = page_ipad.evaluate("() => [window.innerWidth, window.innerHeight]")
            check("iPad: layout fills landscape viewport ([1194, 834])", ipad_vp == [1194, 834], f"{ipad_vp}")

            # Verify buttons responsive on iPad
            ipad_play = find_semantics_text(page_ipad, "PLAY VS AI", timeout_ms=5000)
            check("iPad: Play vs AI menu button is rendered and interactive", ipad_play)

            # Full screen button on iPad should be standard fullscreen toggle, NOT iPhone tip
            ipad_fs = find_semantics_text(page_ipad, "FULL SCREEN", timeout_ms=3000)
            check("iPad: Full screen button is present for element fullscreen", ipad_fs)

            # Test iPad rotating back to portrait: rotate overlay remains hidden on tablet
            page_ipad.set_viewport_size({"width": 834, "height": 1194})
            page_ipad.wait_for_timeout(300)
            ipad_rot_p_after = page_ipad.evaluate("() => window.getComputedStyle(document.getElementById('rotate')).display")
            check("iPad: portrait after rotation still has NO rotate overlay", ipad_rot_p_after == "none")

            # Test iPad on-screen keyboard simulation (keyboard popping up shrinks viewport height)
            print("  Testing iPad keyboard opening (height shrink)...")
            # 1. Landscape keyboard open: height drops to ~420px
            page_ipad.set_viewport_size({"width": 1194, "height": 420})
            page_ipad.wait_for_timeout(300)
            ipad_kb_l = page_ipad.evaluate("() => window.getComputedStyle(document.getElementById('rotate')).display")
            check("iPad: on-screen keyboard in landscape DOES NOT trigger rotate overlay", ipad_kb_l == "none", f"display={ipad_kb_l}")

            # 2. Portrait keyboard open: height drops to ~680px
            page_ipad.set_viewport_size({"width": 834, "height": 680})
            page_ipad.wait_for_timeout(300)
            ipad_kb_p = page_ipad.evaluate("() => window.getComputedStyle(document.getElementById('rotate')).display")
            check("iPad: on-screen keyboard in portrait DOES NOT trigger rotate overlay", ipad_kb_p == "none", f"display={ipad_kb_p}")

            # 3. Restore to landscape and check CSS font-size rule on text inputs (>= 16px prevents iOS zoom)
            page_ipad.set_viewport_size({"width": 1194, "height": 834})
            page_ipad.wait_for_timeout(300)
            css_rule_ok = page_ipad.evaluate("""() => {
                const testInput = document.createElement('input');
                testInput.className = 'flt-text-editing';
                document.body.appendChild(testInput);
                const size = parseFloat(window.getComputedStyle(testInput).fontSize);
                document.body.removeChild(testInput);
                return size >= 16;
            }""")
            check("iPad: text inputs enforce >= 16px font-size to prevent Safari auto-zoom crash", css_rule_ok)

            ctx_ipad.close()

            # =============================================================
            # 3. Android Mobile (Pixel 7)
            # =============================================================
            print("\n--- 3. Testing Android Mobile (Phone) ---")
            pixel = p.devices["Pixel 7"]
            pixel_params = dict(pixel)
            pixel_params["viewport"] = {"width": 412, "height": 915}
            ctx_pixel = browser.new_context(**pixel_params)
            page_pixel = setup_page(ctx_pixel, url)

            pixel_rot_p = page_pixel.evaluate("() => window.getComputedStyle(document.getElementById('rotate')).display")
            check("Android Phone: portrait shows rotate overlay", pixel_rot_p == "flex", f"display={pixel_rot_p}")

            # Rotate to landscape: 915x412
            page_pixel.set_viewport_size({"width": 915, "height": 412})
            page_pixel.wait_for_timeout(300)
            pixel_rot_l = page_pixel.evaluate("() => window.getComputedStyle(document.getElementById('rotate')).display")
            check("Android Phone: landscape hides rotate overlay", pixel_rot_l == "none", f"display={pixel_rot_l}")

            ctx_pixel.close()

            # =============================================================
            # 4. Android Tablet (1280x800)
            # =============================================================
            print("\n--- 4. Testing Android Tablet ---")
            tab_context = browser.new_context(
                viewport={"width": 800, "height": 1280},
                has_touch=True,
                user_agent="Mozilla/5.0 (Linux; Android 13; SM-X800) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            )
            page_tab = setup_page(tab_context, url)

            tab_rot_p = page_tab.evaluate("() => window.getComputedStyle(document.getElementById('rotate')).display")
            check("Android Tablet: portrait DOES NOT show rotate overlay (tablet is exempt)", tab_rot_p == "none", f"display={tab_rot_p}")

            page_tab.set_viewport_size({"width": 1280, "height": 800})
            page_tab.wait_for_timeout(300)
            tab_rot_l = page_tab.evaluate("() => window.getComputedStyle(document.getElementById('rotate')).display")
            check("Android Tablet: landscape DOES NOT show rotate overlay", tab_rot_l == "none", f"display={tab_rot_l}")

            tab_context.close()

            # =============================================================
            # 5. Desktop (Chromium)
            # =============================================================
            print("\n--- 5. Testing Desktop Chromium ---")
            ctx_desk = browser.new_context(
                viewport={"width": 1280, "height": 720},
                has_touch=False,
            )
            page_desk = setup_page(ctx_desk, url)

            desk_rot = page_desk.evaluate("() => window.getComputedStyle(document.getElementById('rotate')).display")
            check("Desktop: landscape has no rotate overlay", desk_rot == "none")

            # Narrow vertical window (e.g. 500x900) - must NOT show overlay because desktop pointer is not coarse
            page_desk.set_viewport_size({"width": 500, "height": 900})
            page_desk.wait_for_timeout(300)
            desk_narrow = page_desk.evaluate("() => window.getComputedStyle(document.getElementById('rotate')).display")
            check("Desktop: narrow vertical window DOES NOT show rotate overlay", desk_narrow == "none", f"display={desk_narrow}")

            ctx_desk.close()
            browser.close()
    finally:
        try:
            server.shutdown()
        except Exception:
            pass
        try:
            server.server_close()
        except Exception:
            pass
        shutil.rmtree(cache_dir, ignore_errors=True)

    print(f"\n==========================================", flush=True)
    print(f"RESULTS: {passes} passed, {failures} failed", flush=True)
    print(f"==========================================", flush=True)
    return failures == 0

if __name__ == "__main__":
    success = run_tests()
    sys.exit(0 if success else 1)
