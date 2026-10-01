"""Actual native APK input + read-only QA telemetry on a named disposable AVD."""
import argparse
from hashlib import sha256
import json
from pathlib import Path
import shlex
import subprocess
import time
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


class Device:
    def __init__(self, serial, port):
        self.prefix = ["adb", "-P", str(port), "-s", serial]
        self.package = "com.shreyansh26.glide"
        size = self.adb("shell", "wm", "size").strip().splitlines()[-1].split(":")[-1].strip()
        self.width, self.height = map(int, size.split("x"))

    def adb(self, *args, check=True):
        return subprocess.run([*self.prefix, *args], check=check, capture_output=True, text=True).stdout

    def state(self):
        return json.loads(self.adb("shell", "run-as", self.package, "cat", "files/qa-state.json"))

    def wait(self, predicate, timeout=30):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                state = self.state()
                if predicate(state):
                    return state
            except (ValueError, subprocess.CalledProcessError):
                pass
            time.sleep(0.2)
        raise AssertionError("Timed out waiting for native state: " + str(self.state()))

    def tap_point(self, x, y, state=None):
        state = state or self.state()
        x = round(x / state["viewport"][0] * self.width)
        y = round(y / state["viewport"][1] * self.height)
        self.adb("shell", "input", "tap", str(x), str(y))

    def tap(self, text):
        state = self.wait(lambda s: any(w.get("text") == text for w in s["widgets"]))
        widget = next(w for w in state["widgets"] if w.get("text") == text)
        x, y, width, height = widget["rect"]
        self.tap_point(x + width / 2, y + height / 2, state)
        time.sleep(0.25)

    def select(self, label, index):
        self.tap(label)
        state = self.wait(lambda s: any(w["type"] == "PopupMenu" for w in s["widgets"]))
        popup = next(w for w in state["widgets"] if w["type"] == "PopupMenu")
        x, y, width, height = popup["rect"]
        # PopupMenu's fixed theme separation gives equal-height selectable rows.
        self.tap_point(x + width / 2, y + (index + 0.5) * height / len(popup["items"]), state)
        time.sleep(0.3)

    def command(self, **command):
        script = "printf '%s' " + shlex.quote(json.dumps(command)) + " > files/qa-command.tmp && mv files/qa-command.tmp files/qa-command.json"
        self.adb("shell", "run-as " + self.package + " sh -c " + shlex.quote(script))

    def launch(self):
        try:
            previous = self.state().get("boot_id")
        except (ValueError, subprocess.CalledProcessError):
            previous = None
        self.adb("shell", "am", "force-stop", self.package)
        self.foreground()
        state = self.wait(lambda s: s["state"] == "menu" and s.get("boot_id") != previous)
        self.adb("shell", "uiautomator", "dump", "/sdcard/glide-ui.xml")
        tree = ET.fromstring(self.adb("shell", "cat", "/sdcard/glide-ui.xml"))
        for node in tree.iter("node"):
            if node.get("text") == "Got it" and node.get("package") == "com.android.systemui":
                left, top, right, bottom = map(int, re.findall(r"\d+", node.get("bounds")))
                self.adb("shell", "input", "tap", str((left + right) // 2), str((top + bottom) // 2))
        return state

    def foreground(self):
        self.adb("shell", "am", "start", "-W", "-n", self.package + "/com.godot.game.GodotApp")
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            focus = self.adb("shell", "dumpsys", "window")
            if any("mCurrentFocus=" in line and self.package in line for line in focus.splitlines()):
                time.sleep(0.5)  # Let Android's activity transition finish before injecting a tap.
                return
            time.sleep(0.2)
        raise AssertionError("App never acquired Android input focus")

    def screenshot(self, name):
        path = ROOT / f"validation/screenshots/{name}.png"
        path.parent.mkdir(exist_ok=True)
        result = subprocess.run([*self.prefix, "exec-out", "screencap", "-p"], check=True, capture_output=True)
        path.write_bytes(result.stdout)


def main(args):
    if not args.serial.startswith("emulator-"):
        raise ValueError("This harness clears app data and disables networking; use a disposable Android emulator.")
    device = Device(args.serial, args.port)
    manifest = json.loads(args.manifest.read_text())
    device.launch()
    report = {"serial": args.serial, "resolution": [device.width, device.height],
              "manifest": str(args.manifest), "physics_hash": manifest["physics_hash"], "levels": {}}
    if args.apk:
        report["apk_sha256"] = sha256(args.apk.read_bytes()).hexdigest()
    levels = ["Easy", "Medium", "Hard", "Insane"]
    for index, level in enumerate(levels):
        state = device.state()
        device.select(levels[state["level"]], index)
        device.wait(lambda s: s["level"] == index)
        device.tap("Play")
        state = device.wait(lambda s: s["state"] == "rally")
        assert state["model_hash"] == manifest["levels"][level.lower()]["weights_sha256"] and not state["model_error"]
        # A passive human can leave the puck on its own half indefinitely.
        # Present a legal incoming shot; the bot must use its real delayed actor.
        device.command(type="shot")
        contact = device.wait(lambda s: s["contacts"][1] > 0, timeout=60)
        state = device.wait(lambda s: s["state"] == "rally")
        before = state["paddle"]
        stretch_x, stretch_y = state["stretch"]
        x = state["origin"][0] + before[0] * stretch_x
        y = state["origin"][1] + before[1] * stretch_y
        sx = device.width / state["viewport"][0]
        sy = device.height / state["viewport"][1]
        device.adb("shell", "input", "swipe", str(round(x * sx)), str(round(y * sy)), str(round((x + 130 * stretch_x) * sx)), str(round((y - 70 * stretch_y) * sy)), "800")
        moved = device.wait(lambda s: abs(s["paddle"][0] - before[0]) > 30 and s["touch_id"] == -1)
        device.tap("Pause")
        paused = device.wait(lambda s: s["state"] == "paused")
        time.sleep(0.6)
        assert device.state()["scores"] == paused["scores"]
        device.tap("Resume")
        device.wait(lambda s: s["state"] == "rally")
        device.adb("shell", "input", "keyevent", "3") # Android Home / focus loss.
        device.foreground()
        device.wait(lambda s: s["state"] == "paused")
        device.tap("Resume")
        state = device.wait(lambda s: s["state"] == "rally")
        # Goal fixtures move the actual puck. They never write scores or invoke _goal.
        goal_pockets = []
        for scoring_side in [0, 1]:
            previous_scores = state["scores"]
            device.command(type="goal", side=scoring_side, angled=True)
            goal = device.wait(lambda s: s["state"] == "goal" and s["scores"][scoring_side] == previous_scores[scoring_side] + 1)
            hidden = device.wait(lambda s: s["last_goal"].get("scores") == goal["scores"] and s["last_goal"].get("alpha") == 0)["last_goal"]
            assert hidden["hidden_puck"] == hidden["puck"] == goal["puck"] and hidden["visual_offset"][1] == (-28 if scoring_side == 0 else 28), {"goal": goal, "hidden": hidden}
            assert hidden["hidden_puck"][1] < -18 if scoring_side == 0 else hidden["hidden_puck"][1] > 1018
            goal_pockets.append({"side": scoring_side, "frozen_body": hidden["hidden_puck"], "visual_offset": hidden["visual_offset"], "alpha": hidden["alpha"]})
            if index == 0:
                device.screenshot(f"{args.serial}-goal-pocket-{scoring_side}")
            served = device.wait(lambda s: s["state"] in ["countdown", "rally"])
            assert served["puck_alpha"] == 1 and served["puck_visual_offset"] == [0, 0]
            if served["state"] == "countdown":
                assert served["puck"] == [300, 500] and not served["paddle_frozen"] and not served["bot_frozen"]
            state = device.wait(lambda s: s["state"] == "rally")
        while max(state["scores"]) < 7:
            previous_scores = state["scores"]
            device.command(type="goal", side=0, angled=previous_scores[0] % 2 == 0)
            state = device.wait(lambda s: s["scores"] != previous_scores)
            state = device.wait(lambda s: s["state"] in ["results", "rally"])
            if state["state"] == "results":
                break
        assert state["state"] == "results" and max(state["scores"]) == 7
        device.screenshot(f"{args.serial}-{level.lower()}-results")
        device.tap("Rematch")
        device.wait(lambda s: s["state"] == "rally" and s["scores"] == [0, 0])
        device.adb("shell", "input", "keyevent", "4") # Back pauses.
        device.wait(lambda s: s["state"] == "paused")
        device.tap("Menu")
        report["levels"][level.lower()] = {"model_hash": state["model_hash"], "actual_bot_contacts": contact["contacts"][1], "input_pause_goals_rematch_focus_back": "passed", "angled_goal_pockets": goal_pockets}
    device.tap("Customize")
    device.select("Atlantic", 1)
    device.select("Ice", 2)
    device.select("Apricot", 3)
    device.select("Glacier", 0)
    changed = device.state()["settings"]
    device.tap("Done")
    device.launch()
    assert all(device.state()["settings"][key] == changed[key] for key in ["table", "puck", "human", "bot"])
    report["cosmetics_persist"] = "passed"
    device.adb("shell", "cmd", "connectivity", "airplane-mode", "enable")
    device.adb("shell", "svc", "wifi", "disable")
    device.adb("shell", "svc", "data", "disable")
    device.adb("shell", "pm", "clear", device.package) # Disposable test AVD app data only.
    device.launch()
    device.tap("Play")
    device.wait(lambda s: s["state"] == "rally" and s["model_hash"] != "prototype")
    device.tap("Pause")
    device.tap("Menu")
    report["offline_first_launch"] = "passed"
    device.tap("Customize")
    device.tap("Reset appearance")
    device.tap("Done")
    device.command(type="physics")
    state = device.wait(lambda s: "failures" in s["physics"], timeout=180)
    assert not state["physics"]["failures"]
    report["physics"] = state["physics"]
    device.command(type="parity")
    state = device.wait(lambda s: "insane" in s["parity"] or "error" in s["parity"], timeout=240)
    assert "error" not in state["parity"]
    report["parity"] = state["parity"]
    device.screenshot(f"{args.serial}-final")
    report["android_api"] = device.adb("shell", "getprop", "ro.build.version.sdk").strip()
    report["android_release"] = device.adb("shell", "getprop", "ro.build.version.release").strip()
    report["abi"] = device.adb("shell", "getprop", "ro.product.cpu.abi").strip()
    report["renderer"] = device.adb("shell", "getprop", "ro.hardware.egl").strip()
    report["final_snapshot"] = state
    destination = ROOT / f"validation/android-{args.serial}.json"
    destination.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2), flush=True)
    if args.soak:
        device.command(type="soak")
        device.wait(lambda s: s["soak_seconds"] > 1)
        print("20-minute native soak running", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--serial", required=True)
    parser.add_argument("--port", type=int, default=5038)
    parser.add_argument("--soak", action="store_true")
    parser.add_argument("--manifest", type=Path, default=ROOT / "models/manifest.json")
    parser.add_argument("--apk", type=Path)
    main(parser.parse_args())
