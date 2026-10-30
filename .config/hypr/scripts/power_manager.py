#!/usr/bin/env python3
import os
import sys
import re
import json
import subprocess
import glob

USER_HOME = os.path.expanduser("~")
if USER_HOME == "/root" and os.path.exists("/home/dx4white"):
    USER_HOME = "/home/dx4white"
CONFIG_PATH = os.path.join(USER_HOME, ".config/hypr/hypridle.conf")
BAT_SYSFS = "/sys/class/power_supply/BAT1"
TLP_THRESH_CONF = "/etc/tlp.d/01-charge-threshold.conf"

def ensure_env():
    if "XDG_RUNTIME_DIR" not in os.environ or not os.environ["XDG_RUNTIME_DIR"]:
        os.environ["XDG_RUNTIME_DIR"] = f"/run/user/{os.getuid()}"
    if "WAYLAND_DISPLAY" not in os.environ or not os.environ["WAYLAND_DISPLAY"]:
        run_dir = os.environ["XDG_RUNTIME_DIR"]
        sockets = sorted(glob.glob(f"{run_dir}/wayland-*"))
        if sockets:
            os.environ["WAYLAND_DISPLAY"] = os.path.basename(sockets[0])
        else:
            os.environ["WAYLAND_DISPLAY"] = "wayland-1"

def get_charge_threshold():
    try:
        thresh_path = os.path.join(BAT_SYSFS, "charge_control_end_threshold")
        if os.path.exists(thresh_path):
            with open(thresh_path, "r") as f:
                return int(f.read().strip())
    except Exception:
        pass
    return 100

def set_charge_threshold(val):
    try:
        val = int(val)
        if val < 20 or val > 100:
            return False
        thresh_path = os.path.join(BAT_SYSFS, "charge_control_end_threshold")
        if os.path.exists(thresh_path):
            with open(thresh_path, "w") as f:
                f.write(str(val))
        # Persist to /etc/tlp.d/
        try:
            os.makedirs(os.path.dirname(TLP_THRESH_CONF), exist_ok=True)
            with open(TLP_THRESH_CONF, "w") as f:
                f.write(f"# Managed by illogical-impulse Power Management\nSTOP_CHARGE_THRESH_BAT1={val}\n")
        except Exception:
            pass
        return True
    except Exception as e:
        sys.stderr.write(f"Error setting charge threshold: {e}\n")
        return False

def get_battery_details():
    info = {
        "present": False,
        "percentage": 100,
        "state": "unknown",
        "power_w": 0.0,
        "health_pct": 100.0,
        "capacity_full_wh": 0.0,
        "capacity_design_wh": 0.0,
        "technology": "Li-ion",
        "charge_threshold": get_charge_threshold()
    }
    if not os.path.exists(BAT_SYSFS):
        return info

    info["present"] = True
    try:
        def read_val(filename):
            p = os.path.join(BAT_SYSFS, filename)
            if os.path.exists(p):
                with open(p, "r") as f:
                    return f.read().strip()
            return ""

        status = read_val("status")
        if status:
            info["state"] = status.lower()

        cap = read_val("capacity")
        if cap:
            info["percentage"] = int(cap)

        tech = read_val("technology")
        if tech:
            info["technology"] = tech

        # Voltage & Current / Power
        voltage = float(read_val("voltage_now") or 0) / 1e6
        current = float(read_val("current_now") or 0) / 1e6
        power = float(read_val("power_now") or 0) / 1e6
        if power == 0.0 and voltage > 0 and current > 0:
            power = voltage * current
        info["power_w"] = round(power, 2)

        # Health
        full = float(read_val("charge_full") or read_val("energy_full") or 0)
        design = float(read_val("charge_full_design") or read_val("energy_full_design") or 0)
        if full > 0 and design > 0:
            info["health_pct"] = round((full / design) * 100, 1)
            info["capacity_full_wh"] = round((full * voltage) / 1e6, 1) if "charge_full" in BAT_SYSFS else round(full / 1e6, 1)
            info["capacity_design_wh"] = round((design * voltage) / 1e6, 1) if "charge_full" in BAT_SYSFS else round(design / 1e6, 1)
    except Exception as e:
        sys.stderr.write(f"Error reading battery details: {e}\n")

    return info

def get_current_settings():
    lock_to = 300
    sleep_to = 600
    suspend_to = 900
    lock_en = False
    sleep_en = False
    suspend_en = False
    dim_en = False
    dim_sec = 30

    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r") as f:
                content = f.read()

            listeners = []
            idx = 0
            while True:
                pos = content.find("listener {", idx)
                if pos == -1:
                    break
                start = pos + len("listener {")
                depth = 1
                i = start
                while i < len(content) and depth > 0:
                    if content[i] == '{':
                        depth += 1
                    elif content[i] == '}':
                        depth -= 1
                    i += 1
                listeners.append(content[start:i-1])
                idx = i

            for l in listeners:
                to_m = re.search(r'timeout\s*=\s*(\d+)', l)
                cmd_m = re.search(r'on-timeout\s*=\s*([^\n]+)', l)
                if to_m and cmd_m:
                    timeout = int(to_m.group(1))
                    cmd = cmd_m.group(1).strip()
                    if 'brightnessctl' in cmd:
                        dim_en = True
                    elif 'lock-session' in cmd:
                        lock_to = timeout
                        lock_en = True
                    elif 'dpms' in cmd:
                        sleep_to = timeout
                        sleep_en = True
                    elif 'suspend' in cmd:
                        suspend_to = timeout
                        suspend_en = True
        except Exception as e:
            sys.stderr.write(f"Error reading config: {e}\n")

    profile = "balanced"
    try:
        res = subprocess.run(["tlpctl", "get"], capture_output=True, text=True, timeout=2)
        if res.returncode == 0 and res.stdout.strip():
            profile = res.stdout.strip()
    except Exception:
        pass

    return {
        "lock_timeout": max(1, round(lock_to / 60)),
        "sleep_timeout": max(1, round(sleep_to / 60)),
        "suspend_timeout": max(1, round(suspend_to / 60)),
        "lock_enabled": lock_en,
        "sleep_enabled": sleep_en,
        "suspend_enabled": suspend_en,
        "dim_enabled": dim_en,
        "dim_seconds": dim_sec,
        "profile": profile,
        "charge_threshold": get_charge_threshold(),
        "battery": get_battery_details()
    }

def update_hypridle(lock_min=5, sleep_min=10, suspend_min=15, lock_en=True, sleep_en=True, suspend_en=True, dim_en=True, dim_sec=30):
    ensure_env()
    lock_sec = max(30, int(float(lock_min) * 60))
    sleep_sec = max(60, int(float(sleep_min) * 60))
    suspend_sec = max(60, int(float(suspend_min) * 60))

    existing_input = ""
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r") as f:
                old_text = f.read()
                m_input = re.search(r'(input\s*\{.*?\})', old_text, re.DOTALL)
                if m_input:
                    existing_input = "\n" + m_input.group(1).strip() + "\n"
        except Exception:
            pass

    new_content = [
        "$lock_cmd = hyprctl dispatch 'hl.dsp.global(\"quickshell:lock\")' & pidof qs quickshell hyprlock || hyprlock",
        "$suspend_cmd = systemctl suspend || loginctl suspend",
        "",
        "general {",
        "    lock_cmd = $lock_cmd",
        "    before_sleep_cmd = loginctl lock-session",
        "    after_sleep_cmd = hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })' && hyprctl dispatch 'hl.dsp.global(\"quickshell:lockFocus\")'",
        "    inhibit_sleep = 3",
        "}",
        ""
    ]

    # Dimming listener before sleep
    if dim_en and sleep_en and sleep_sec > dim_sec:
        dim_trigger_sec = sleep_sec - dim_sec
        new_content.extend([
            "listener {",
            f"    timeout = {dim_trigger_sec} # Dim screen before sleep",
            "    on-timeout = brightnessctl -s set 10%",
            "    on-resume = brightnessctl -r",
            "}",
            ""
        ])

    if lock_en:
        new_content.extend([
            "listener {",
            f"    timeout = {lock_sec} # {lock_min}mins",
            "    on-timeout = loginctl lock-session",
            "}",
            ""
        ])

    if sleep_en:
        new_content.extend([
            "listener {",
            f"    timeout = {sleep_sec} # {sleep_min}mins",
            "    on-timeout = hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'",
            "    on-resume = hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })' && brightnessctl -r",
            "}",
            ""
        ])

    if suspend_en:
        new_content.extend([
            "listener {",
            f"    timeout = {suspend_sec} # {suspend_min}mins",
            "    on-timeout = $suspend_cmd",
            "}",
            ""
        ])

    if existing_input:
        new_content.append(existing_input)

    with open(CONFIG_PATH, "w") as f:
        f.write("\n".join(new_content))

    # Restart hypridle
    subprocess.run(["pkill", "-x", "hypridle"], check=False)
    subprocess.Popen(["hypridle"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True, env=os.environ)
    return True

def set_profile(profile):
    if profile not in ["power-saver", "balanced", "performance"]:
        return False
    subprocess.run(["tlpctl", "set", profile], check=False)
    try:
        import dbus
        bus = dbus.SystemBus()
        obj = bus.get_object('net.hadess.PowerProfiles', '/net/hadess/PowerProfiles')
        props = dbus.Interface(obj, 'org.freedesktop.DBus.Properties')
        props.Set('net.hadess.PowerProfiles', 'ActiveProfile', dbus.String(profile))
    except Exception:
        pass
    return True

def main():
    if len(sys.argv) < 2:
        print(json.dumps(get_current_settings()))
        return

    cmd = sys.argv[1]
    if cmd == "get":
        print(json.dumps(get_current_settings()))
    elif cmd == "get-battery":
        print(json.dumps(get_battery_details()))
    elif cmd == "set-idle":
        import argparse
        parser = argparse.ArgumentParser()
        parser.add_argument("--lock", type=int, default=5)
        parser.add_argument("--sleep", type=int, default=10)
        parser.add_argument("--suspend", type=int, default=15)
        parser.add_argument("--enable-lock", type=lambda x: (str(x).lower() in ['true', '1']), default=True)
        parser.add_argument("--enable-sleep", type=lambda x: (str(x).lower() in ['true', '1']), default=True)
        parser.add_argument("--enable-suspend", type=lambda x: (str(x).lower() in ['true', '1']), default=True)
        parser.add_argument("--enable-dim", type=lambda x: (str(x).lower() in ['true', '1']), default=True)
        parser.add_argument("--dim-seconds", type=int, default=30)
        args, _ = parser.parse_known_args(sys.argv[2:])
        update_hypridle(args.lock, args.sleep, args.suspend, args.enable_lock, args.enable_sleep, args.enable_suspend, args.enable_dim, args.dim_seconds)
        print(json.dumps({"status": "ok"}))
    elif cmd == "set-profile":
        if len(sys.argv) > 2:
            p = sys.argv[2]
            set_profile(p)
            print(json.dumps({"status": "ok", "profile": p}))
    elif cmd == "set-charge-threshold" or cmd == "set-charge-limit":
        if len(sys.argv) > 2:
            lim = int(sys.argv[2])
            ok = set_charge_threshold(lim)
            print(json.dumps({"status": "ok" if ok else "error", "charge_threshold": lim}))
    elif cmd == "suspend":
        subprocess.run(["bash", "-c", "systemctl suspend || loginctl suspend"])
    elif cmd == "sleep":
        ensure_env()
        subprocess.run(["hyprctl", "dispatch", "hl.dsp.dpms({ action = 'disable' })"])
    elif cmd == "lock":
        subprocess.run(["loginctl", "lock-session"])
    elif cmd == "hibernate":
        subprocess.run(["bash", "-c", "systemctl hibernate || loginctl hibernate"])

if __name__ == "__main__":
    main()
