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

CONFIG_LUA_PATH = os.path.join(USER_HOME, ".config/hypr/custom/mouse.lua")
GENERAL_LUA_PATH = os.path.join(USER_HOME, ".config/hypr/custom/general.lua")
CONFIG_JSON_PATH = os.path.join(USER_HOME, ".config/illogical-impulse/config.json")

def get_env():
    env = os.environ.copy()
    if "XDG_RUNTIME_DIR" not in env or not env["XDG_RUNTIME_DIR"]:
        uid = os.getuid()
        if uid == 0 and os.path.exists("/run/user/1000"):
            env["XDG_RUNTIME_DIR"] = "/run/user/1000"
        else:
            env["XDG_RUNTIME_DIR"] = f"/run/user/{uid}"

    if "WAYLAND_DISPLAY" not in env or not env["WAYLAND_DISPLAY"]:
        run_dir = env["XDG_RUNTIME_DIR"]
        sockets = sorted(glob.glob(f"{run_dir}/wayland-*"))
        if sockets:
            env["WAYLAND_DISPLAY"] = os.path.basename(sockets[0])
        else:
            env["WAYLAND_DISPLAY"] = "wayland-1"

    if "HYPRLAND_INSTANCE_SIGNATURE" not in env or not env["HYPRLAND_INSTANCE_SIGNATURE"]:
        run_dir = env["XDG_RUNTIME_DIR"]
        hypr_dir = os.path.join(run_dir, "hypr")
        if os.path.exists(hypr_dir):
            sigs = [f for f in os.listdir(hypr_dir) if not f.startswith(".")]
            if sigs:
                env["HYPRLAND_INSTANCE_SIGNATURE"] = sigs[0]
    return env

def hyprctl_eval(lua_code):
    env = get_env()
    cmd = ["hyprctl", "eval", lua_code]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=3)
        return res.returncode == 0, res.stdout.strip()
    except Exception as e:
        return False, str(e)

def ensure_custom_general_include():
    if not os.path.exists(GENERAL_LUA_PATH):
        return
    try:
        with open(GENERAL_LUA_PATH, "r") as f:
            content = f.read()
        if "custom.mouse" not in content and "mouse.lua" not in content:
            include_code = '\n\n-- Include Mouse & Pointer Customizations\nif is_file_exists(HOME .. "/.config/hypr/custom/mouse.lua") then\n    require("custom.mouse")\nend\n'
            with open(GENERAL_LUA_PATH, "a") as f:
                f.write(include_code)
    except Exception as e:
        sys.stderr.write(f"Error ensuring custom.mouse include: {e}\n")

def get_connected_devices():
    env = get_env()
    devices = []
    try:
        res = subprocess.run(["hyprctl", "devices", "-j"], capture_output=True, text=True, env=env, timeout=3)
        if res.returncode == 0:
            data = json.loads(res.stdout)
            mice = data.get("mice", [])
            for m in mice:
                raw_name = m.get("name", "")
                if not raw_name or "ydotool" in raw_name.lower():
                    continue

                # Filter out pure keyboard/consumer extra nodes
                if "consumer-control" in raw_name.lower() or "keyboard-1" in raw_name.lower():
                    continue

                dev_type = "mouse"
                is_external = True
                if "touchpad" in raw_name.lower():
                    dev_type = "touchpad"
                    is_external = False
                elif "keyboard" in raw_name.lower():
                    is_external = False

                clean_name = raw_name
                if "touchpad" in raw_name.lower():
                    clean_name = "ASUS Precision Touchpad (" + raw_name.split("-")[0].upper() + ")"
                elif "g3" in raw_name.lower() or "2.4g" in raw_name.lower():
                    clean_name = "G3 Wireless Optical Gaming Mouse"
                elif "gaming-keyboard" in raw_name.lower():
                    clean_name = "BYCX Keyboard Pointer Trackpoint"
                elif "elan" in raw_name.lower():
                    clean_name = "ELAN Precision Pointer"

                devices.append({
                    "name": raw_name,
                    "displayName": clean_name,
                    "type": dev_type,
                    "isExternal": is_external,
                    "address": m.get("address", ""),
                    "defaultSpeed": m.get("defaultSpeed", 0.0),
                    "scrollFactor": m.get("scrollFactor", 1.0)
                })
    except Exception as e:
        sys.stderr.write(f"Error getting connected devices: {e}\n")

    seen = set()
    unique_devices = []
    for d in devices:
        if d["name"] not in seen:
            seen.add(d["name"])
            unique_devices.append(d)

    return unique_devices

def check_ratbag_hardware():
    try:
        res = subprocess.run(["ratbagctl", "list"], capture_output=True, text=True, timeout=2)
        if res.returncode == 0 and res.stdout.strip() and "No devices" not in res.stdout:
            lines = res.stdout.strip().splitlines()
            supported = []
            for line in lines:
                parts = line.split(":")
                dev_id = parts[0].strip()
                name = parts[1].strip() if len(parts) > 1 else dev_id
                supported.append({"id": dev_id, "name": name})
            return True, supported
    except Exception:
        pass
    return False, []

def get_installed_cursor_themes():
    themes = ["Bibata-Modern-Classic", "breeze_cursors", "Breeze_Light", "Adwaita"]
    detected = []
    search_dirs = [
        "/usr/share/icons",
        os.path.expanduser("~/.local/share/icons"),
        os.path.expanduser("~/.icons")
    ]
    for d in search_dirs:
        if os.path.exists(d):
            try:
                for entry in os.listdir(d):
                    cursor_dir = os.path.join(d, entry, "cursors")
                    if os.path.isdir(cursor_dir) and entry not in detected:
                        detected.append(entry)
            except Exception:
                pass
    for t in themes:
        if t not in detected and os.path.exists(f"/usr/share/icons/{t}/cursors"):
            detected.append(t)
    return detected or themes

def get_all_settings():
    config_data = {}
    if os.path.exists(CONFIG_JSON_PATH):
        try:
            with open(CONFIG_JSON_PATH, "r") as f:
                config_data = json.load(f)
        except Exception:
            pass

    mouse_cfg = config_data.get("mouse", {})

    sensitivity = mouse_cfg.get("sensitivity", 0.0)
    accel_profile = mouse_cfg.get("accelProfile", "flat")
    natural_scroll = mouse_cfg.get("naturalScroll", False)
    left_handed = mouse_cfg.get("leftHanded", False)
    middle_emulation = mouse_cfg.get("middleEmulation", False)
    scroll_factor = mouse_cfg.get("scrollFactor", 1.0)

    # Touchpad
    touchpad_enabled = mouse_cfg.get("touchpadEnabled", True)
    auto_disable_touchpad = mouse_cfg.get("autoDisableTouchpad", False)
    touchpad_sensitivity = mouse_cfg.get("touchpadSensitivity", 0.0)
    touchpad_natural_scroll = mouse_cfg.get("touchpadNaturalScroll", True)
    tap_to_click = mouse_cfg.get("tapToClick", True)
    tap_and_drag = mouse_cfg.get("tapAndDrag", True)
    drag_lock = mouse_cfg.get("dragLock", False)
    disable_while_typing = mouse_cfg.get("disableWhileTyping", True)
    clickfinger_behavior = mouse_cfg.get("clickfingerBehavior", True)
    touchpad_scroll_factor = mouse_cfg.get("touchpadScrollFactor", 0.7)
    touchpad_middle_emulation = mouse_cfg.get("touchpadMiddleEmulation", False)
    tap_button_map = mouse_cfg.get("tapButtonMap", "lrm")

    # Cursor & Pointer
    cursor_size = mouse_cfg.get("cursorSize", 24)
    cursor_theme = mouse_cfg.get("cursorTheme", "Bibata-Modern-Classic")
    inactive_timeout = mouse_cfg.get("inactiveTimeout", 0)
    follow_mouse = mouse_cfg.get("followMouse", 1)
    mouse_move_enables_dpms = mouse_cfg.get("mouseMoveEnablesDpms", True)
    no_warps = mouse_cfg.get("noWarps", False)
    hide_on_key_press = mouse_cfg.get("hideOnKeyPress", False)
    zoom_factor = mouse_cfg.get("zoomFactor", 1.0)
    mouse_refocus = mouse_cfg.get("mouseRefocus", True)

    # Gestures
    workspace_swipe_invert = mouse_cfg.get("workspaceSwipeInvert", true := True)
    workspace_swipe_distance = mouse_cfg.get("workspaceSwipeDistance", 700)

    per_device = mouse_cfg.get("perDevice", {})

    connected = get_connected_devices()
    has_ratbag, ratbag_devs = check_ratbag_hardware()

    # Check if external mouse is present
    has_external_mouse = any(d.get("isExternal", False) and d.get("type") == "mouse" for d in connected)
    is_touchpad_actually_disabled = (not touchpad_enabled) or (auto_disable_touchpad and has_external_mouse)

    return {
        "sensitivity": sensitivity,
        "sensitivityPercent": int(round(sensitivity * 100)),
        "accelProfile": accel_profile,
        "naturalScroll": natural_scroll,
        "leftHanded": left_handed,
        "middleEmulation": middle_emulation,
        "scrollFactor": scroll_factor,
        "scrollFactorPercent": int(round(scroll_factor * 100)),

        "touchpadEnabled": touchpad_enabled,
        "autoDisableTouchpad": auto_disable_touchpad,
        "touchpadAutoDisabled": auto_disable_touchpad and has_external_mouse,
        "hasExternalMouse": has_external_mouse,
        "touchpadSensitivity": touchpad_sensitivity,
        "touchpadSensitivityPercent": int(round(touchpad_sensitivity * 100)),
        "touchpadNaturalScroll": touchpad_natural_scroll,
        "tapToClick": tap_to_click,
        "tapAndDrag": tap_and_drag,
        "dragLock": drag_lock,
        "disableWhileTyping": disable_while_typing,
        "clickfingerBehavior": clickfinger_behavior,
        "touchpadScrollFactor": touchpad_scroll_factor,
        "touchpadScrollFactorPercent": int(round(touchpad_scroll_factor * 100)),
        "touchpadMiddleEmulation": touchpad_middle_emulation,
        "tapButtonMap": tap_button_map,

        "cursorSize": cursor_size,
        "cursorTheme": cursor_theme,
        "inactiveTimeout": inactive_timeout,
        "followMouse": follow_mouse,
        "mouseMoveEnablesDpms": mouse_move_enables_dpms,
        "noWarps": no_warps,
        "hideOnKeyPress": hide_on_key_press,
        "zoomFactor": zoom_factor,
        "mouseRefocus": mouse_refocus,

        "workspaceSwipeInvert": workspace_swipe_invert,
        "workspaceSwipeDistance": workspace_swipe_distance,

        "connectedDevices": connected,
        "perDevice": per_device,
        "availableCursorThemes": get_installed_cursor_themes(),
        "hardwareTuningAvailable": has_ratbag,
        "hardwareDevices": ratbag_devs
    }

def apply_and_save(settings):
    ensure_custom_general_include()

    connected = get_connected_devices()
    has_external_mouse = any(d.get("isExternal", False) and d.get("type") == "mouse" for d in connected)
    auto_disable_tp = settings.get("autoDisableTouchpad", False)
    tp_master_enabled = settings.get("touchpadEnabled", True)
    final_tp_enabled = tp_master_enabled and not (auto_disable_tp and has_external_mouse)

    tap_button_map = settings.get("tapButtonMap", "lrm")

    lua_lines = [
        "-- Auto-generated by illogical-impulse Mouse & Pointer Settings",
        "hl.config({",
        "    input = {",
        f"        sensitivity = {float(settings.get('sensitivity', 0.0))},",
        f'        accel_profile = "{settings.get("accelProfile", "flat")}",',
        f"        natural_scroll = {'true' if settings.get('naturalScroll', False) else 'false'},",
        f"        left_handed = {'true' if settings.get('leftHanded', False) else 'false'},",
        f"        scroll_factor = {float(settings.get('scrollFactor', 1.0))},",
        f"        follow_mouse = {int(settings.get('followMouse', 1))},",
        f"        mouse_refocus = {'true' if settings.get('mouseRefocus', True) else 'false'},",
        "        touchpad = {",
        f"            natural_scroll = {'true' if settings.get('touchpadNaturalScroll', True) else 'false'},",
        f"            disable_while_typing = {'true' if settings.get('disableWhileTyping', True) else 'false'},",
        f"            clickfinger_behavior = {'true' if settings.get('clickfingerBehavior', True) else 'false'},",
        f"            tap_to_click = {'true' if settings.get('tapToClick', True) else 'false'},",
        f"            drag_lock = {'true' if settings.get('dragLock', False) else 'false'},",
        f"            scroll_factor = {float(settings.get('touchpadScrollFactor', 0.7))},",
        f"            middle_button_emulation = {'true' if settings.get('touchpadMiddleEmulation', False) else 'false'},",
        f'            tap_button_map = "{tap_button_map}"',
        "        }",
        "    },",
        "    gestures = {",
        f"        workspace_swipe_distance = {int(settings.get('workspaceSwipeDistance', 700))},",
        f"        workspace_swipe_invert = {'true' if settings.get('workspaceSwipeInvert', True) else 'false'},",
        "        workspace_swipe_cancel_ratio = 0.2",
        "    },",
        "    cursor = {",
        f"        inactive_timeout = {min(20, max(0, int(settings.get('inactiveTimeout', 0))))},",
        f"        no_warps = {'true' if settings.get('noWarps', False) else 'false'},",
        f"        hide_on_key_press = {'true' if settings.get('hideOnKeyPress', False) else 'false'},",
        f"        zoom_factor = {float(settings.get('zoomFactor', 1.0))}",
        "    },",
        "    misc = {",
        f"        mouse_move_enables_dpms = {'true' if settings.get('mouseMoveEnablesDpms', True) else 'false'}",
        "    }",
        "})",
        ""
    ]

    # Global Touchpad Enable/Disable device rule
    for d in connected:
        if d["type"] == "touchpad":
            tp_sens = float(settings.get("touchpadSensitivity", 0.0))
            lua_lines.extend([
                "hl.device({",
                f'    name = "{d["name"]}",',
                f"    enabled = {'true' if final_tp_enabled else 'false'},",
                f"    sensitivity = {tp_sens}",
                "})",
                ""
            ])

    # Per-device custom configs
    per_device = settings.get("perDevice", {})
    for dev_name, dev_conf in per_device.items():
        if not dev_name:
            continue
        lua_lines.append("hl.device({")
        lua_lines.append(f'    name = "{dev_name}",')
        if "enabled" in dev_conf:
            lua_lines.append(f"    enabled = {'true' if dev_conf['enabled'] else 'false'},")
        if "sensitivity" in dev_conf:
            lua_lines.append(f"    sensitivity = {float(dev_conf['sensitivity'])},")
        if "accelProfile" in dev_conf:
            lua_lines.append(f'    accel_profile = "{dev_conf["accelProfile"]}",')
        if "naturalScroll" in dev_conf:
            lua_lines.append(f"    natural_scroll = {'true' if dev_conf['naturalScroll'] else 'false'},")
        if "scrollFactor" in dev_conf:
            lua_lines.append(f"    scroll_factor = {float(dev_conf['scrollFactor'])},")
        lua_lines.append("})")
        lua_lines.append("")

    lua_code = "\n".join(lua_lines)

    # 1. Write to custom/mouse.lua
    os.makedirs(os.path.dirname(CONFIG_LUA_PATH), exist_ok=True)
    with open(CONFIG_LUA_PATH, "w") as f:
        f.write(lua_code)

    # 2. Apply dynamically via hyprctl eval
    hyprctl_eval(f'dofile("{CONFIG_LUA_PATH}")')

    # 3. Update cursor theme & size
    cursor_theme = settings.get("cursorTheme", "Bibata-Modern-Classic")
    cursor_size = int(settings.get("cursorSize", 24))
    env = get_env()
    subprocess.run(["hyprctl", "setcursor", cursor_theme, str(cursor_size)], env=env, check=False)
    subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", cursor_theme], env=env, check=False)
    subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "cursor-size", str(cursor_size)], env=env, check=False)

    # 4. Save to config.json
    try:
        config_data = {}
        if os.path.exists(CONFIG_JSON_PATH):
            with open(CONFIG_JSON_PATH, "r") as f:
                config_data = json.load(f)
        config_data["mouse"] = settings
        with open(CONFIG_JSON_PATH, "w") as f:
            json.dump(config_data, f, indent=4)
    except Exception as e:
        sys.stderr.write(f"Error saving config.json: {e}\n")

    return True

def main():
    if len(sys.argv) < 2 or sys.argv[1] == "get":
        print(json.dumps(get_all_settings()))
        return

    cmd = sys.argv[1]
    if cmd == "list-devices":
        print(json.dumps(get_connected_devices()))
    elif cmd == "set":
        if len(sys.argv) > 2:
            data = json.loads(sys.argv[2])
        else:
            data = json.load(sys.stdin)
        apply_and_save(data)
        print(json.dumps({"status": "ok"}))
    elif cmd == "update-field":
        key = sys.argv[2]
        val = sys.argv[3]
        current = get_all_settings()
        if val.lower() == "true":
            val = True
        elif val.lower() == "false":
            val = False
        else:
            try:
                if "." in val:
                    val = float(val)
                else:
                    val = int(val)
            except ValueError:
                pass
        current[key] = val
        apply_and_save(current)
        print(json.dumps({"status": "ok", "updated": key, "value": val}))
    elif cmd == "set-device-tuning":
        dev_name = sys.argv[2]
        key = sys.argv[3]
        val = sys.argv[4]
        if val.lower() == "true":
            val = True
        elif val.lower() == "false":
            val = False
        else:
            try:
                if "." in val:
                    val = float(val)
                else:
                    val = int(val)
            except ValueError:
                pass
        current = get_all_settings()
        if "perDevice" not in current:
            current["perDevice"] = {}
        if dev_name not in current["perDevice"]:
            current["perDevice"][dev_name] = {}
        current["perDevice"][dev_name][key] = val
        apply_and_save(current)
        print(json.dumps({"status": "ok", "device": dev_name, "updated": key, "value": val}))

if __name__ == "__main__":
    main()
