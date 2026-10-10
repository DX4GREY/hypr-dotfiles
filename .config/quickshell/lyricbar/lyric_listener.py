#!/usr/bin/env python3
"""
lyric_listener.py
Helper script for Quickshell LyricBar widget.
Monitors MPRIS players (Spotify, MPD, VLC, etc.), synchronizes timestamps from .lrc lyrics,
and streams the active line to stdout in real-time.
"""

import sys
import os
import re
import json
import time
import bisect
import urllib.request
import urllib.parse
from pathlib import Path

# Local lyric search paths
LYRIC_CACHE_DIR = Path.home() / ".cache" / "lyrics"
LOCAL_LYRIC_DIRS = [
    Path.home() / ".lyrics",
    Path.home() / ".cache" / "lyrics",
    Path.home() / ".config" / "quickshell" / "lyrics",
    Path.home() / "Music" / "lyrics",
]

# Ensure cache directory exists
LYRIC_CACHE_DIR.mkdir(parents=True, exist_ok=True)


def clean_title(title: str) -> str:
    """Removes common track suffixes like '(Remastered...)', '[feat. ...]' for better search."""
    if not title:
        return ""
    cleaned = re.sub(r"\(.*?(?:feat|remaster|version|edition|live|explicit|mono|stereo).*?\)", "", title, flags=re.IGNORECASE)
    cleaned = re.sub(r"\[.*?(?:feat|remaster|version|edition|live|explicit|mono|stereo).*?\]", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\s+-\s+(?:remaster|live|mono|stereo).*$", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    return cleaned or title


def sanitize_filename(name: str) -> str:
    """Sanitizes artist/title for filesystem storage."""
    return re.sub(r'[\\/*?:"<>|]', "", name).strip()


def parse_lrc(lrc_text: str):
    """
    Parses an LRC string into a sorted list of (timestamp_seconds, text).
    Handles multiple timestamps per line and trims metadata tags.
    """
    entries = []
    for line in lrc_text.splitlines():
        line = line.strip()
        if not line:
            continue
        # Match one or more [mm:ss.xx] or [mm:ss]
        matches = list(re.finditer(r"\[(\d{1,2}):(\d{2}(?:\.\d+)?)\]", line))
        if not matches:
            continue
        text = line[matches[-1].end():].strip()
        for m in matches:
            try:
                minutes = int(m.group(1))
                seconds = float(m.group(2))
                t = minutes * 60.0 + seconds
                entries.append((t, text))
            except ValueError:
                continue
    entries.sort(key=lambda x: x[0])
    return entries


def find_local_lrc(artist: str, title: str, file_url: str = "") -> str:
    """Finds a matching local .lrc file if present."""
    # 1. Check beside file if it's a local audio file
    if file_url and file_url.startswith("file://"):
        local_audio_path = urllib.parse.unquote(file_url[7:])
        base_path, _ = os.path.splitext(local_audio_path)
        lrc_path = base_path + ".lrc"
        if os.path.isfile(lrc_path):
            try:
                with open(lrc_path, "r", encoding="utf-8", errors="replace") as f:
                    return f.read()
            except Exception:
                pass

    # 2. Check local directories
    safe_artist = sanitize_filename(artist)
    safe_title = sanitize_filename(title)
    candidate_names = [
        f"{safe_artist} - {safe_title}.lrc",
        f"{safe_title}.lrc",
        f"{safe_artist}/{safe_title}.lrc",
    ]

    for d in LOCAL_LYRIC_DIRS:
        for name in candidate_names:
            p = d / name
            if p.is_file():
                try:
                    with open(p, "r", encoding="utf-8", errors="replace") as f:
                        return f.read()
                except Exception:
                    pass

    return ""


def fetch_online_lrc(artist: str, title: str, album: str = "", duration: float = 0.0) -> str:
    """
    Fetches synced LRC from LRCLIB.net (free, fast, open-source synced lyrics API).
    Caches successful fetches locally.
    """
    clean_t = clean_title(title)
    safe_artist = sanitize_filename(artist)
    safe_title = sanitize_filename(title)
    cache_path = LYRIC_CACHE_DIR / f"{safe_artist} - {safe_title}.lrc"

    if cache_path.is_file():
        try:
            with open(cache_path, "r", encoding="utf-8", errors="replace") as f:
                return f.read()
        except Exception:
            pass

    # Try exact get endpoint
    params = {
        "artist_name": artist,
        "track_name": clean_t or title,
    }
    if album:
        params["album_name"] = album
    if duration > 0:
        params["duration"] = int(duration)

    headers = {"User-Agent": "LyricBar-Quickshell/1.0 (https://github.com/)"}

    try:
        url = "https://lrclib.net/api/get?" + urllib.parse.urlencode(params)
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=3.5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            synced = data.get("syncedLyrics")
            if synced:
                with open(cache_path, "w", encoding="utf-8") as f:
                    f.write(synced)
                return synced
    except Exception:
        pass

    # Fallback to search endpoint
    try:
        search_query = f"{artist} {clean_t}".strip()
        url = "https://lrclib.net/api/search?" + urllib.parse.urlencode({"q": search_query})
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=3.5) as resp:
            results = json.loads(resp.read().decode("utf-8"))
            if isinstance(results, list) and len(results) > 0:
                for item in results:
                    synced = item.get("syncedLyrics")
                    if synced:
                        with open(cache_path, "w", encoding="utf-8") as f:
                            f.write(synced)
                        return synced
    except Exception:
        pass

    return ""


class MprisPlayerDbus:
    """Connects to MPRIS via DBus session bus."""
    def __init__(self):
        import dbus
        self.bus = dbus.SessionBus()

    def get_active_player(self, preferred_player=""):
        services = [s for s in self.bus.list_names() if s.startswith("org.mpris.MediaPlayer2.")]
        if not services:
            return None, None

        if preferred_player:
            for s in services:
                if preferred_player.lower() in s.lower():
                    return s, self._get_player_props(s)

        # Prioritize currently playing player
        playing_player = None
        for s in services:
            # Skip playerctld or mirror buses to avoid duplicate loops
            if "playerctld" in s:
                continue
            props = self._get_player_props(s)
            if props:
                status = props.get("status", "")
                if status == "Playing":
                    return s, props
                if not playing_player and status == "Paused":
                    playing_player = (s, props)

        if playing_player:
            return playing_player

        # Fallback to first available
        first = services[0]
        return first, self._get_player_props(first)

    def _get_player_props(self, service_name):
        import dbus
        try:
            obj = self.bus.get_object(service_name, "/org/mpris/MediaPlayer2")
            prop_iface = dbus.Interface(obj, "org.freedesktop.DBus.Properties")
            status = str(prop_iface.Get("org.mpris.MediaPlayer2.Player", "PlaybackStatus"))
            meta = prop_iface.Get("org.mpris.MediaPlayer2.Player", "Metadata")
            pos_us = int(prop_iface.Get("org.mpris.MediaPlayer2.Player", "Position"))

            title = str(meta.get("xesam:title", ""))
            artists = meta.get("xesam:artist", [""])
            artist = str(artists[0]) if artists else ""
            album = str(meta.get("xesam:album", ""))
            length_us = int(meta.get("mpris:length", 0))
            url = str(meta.get("xesam:url", ""))
            track_id = str(meta.get("mpris:trackid", ""))

            return {
                "service": service_name,
                "status": status,
                "title": title,
                "artist": artist,
                "album": album,
                "position": pos_us / 1_000_000.0,
                "duration": length_us / 1_000_000.0 if length_us else 0.0,
                "url": url,
                "track_id": track_id,
            }
        except Exception:
            return None


class MprisPlayerCtl:
    """Fallback connector using playerctl CLI."""
    def get_active_player(self, preferred_player=""):
        import subprocess
        cmd = ["playerctl"]
        if preferred_player:
            cmd.extend(["-p", preferred_player])
        cmd.extend([
            "metadata",
            "--format",
            "{{status}}|{{title}}|{{artist}}|{{album}}|{{position}}|{{mpris:length}}|{{mpris:trackid}}|{{xesam:url}}"
        ])
        try:
            out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL, timeout=1.0).decode("utf-8").strip()
            if not out:
                return None, None
            parts = out.split("|")
            if len(parts) < 6:
                return None, None
            status, title, artist, album, pos_str, length_str = parts[:6]
            track_id = parts[6] if len(parts) > 6 else ""
            url = parts[7] if len(parts) > 7 else ""

            pos_val = float(pos_str) / 1_000_000.0 if pos_str else 0.0
            len_val = float(length_str) / 1_000_000.0 if length_str else 0.0

            return "playerctl", {
                "service": "playerctl",
                "status": status,
                "title": title,
                "artist": artist,
                "album": album,
                "position": pos_val,
                "duration": len_val,
                "url": url,
                "track_id": track_id,
            }
        except Exception:
            return None, None


def main():
    plain_output = "--plain" in sys.argv
    preferred_player = ""
    for i, arg in enumerate(sys.argv):
        if arg == "--player" and i + 1 < len(sys.argv):
            preferred_player = sys.argv[i + 1]

    # Initialize connector
    connector = None
    try:
        import dbus
        connector = MprisPlayerDbus()
    except Exception:
        connector = MprisPlayerCtl()

    last_track_id = ""
    last_title = ""
    last_artist = ""
    lrc_entries = []
    lrc_timestamps = []
    has_synced_lyrics = False

    last_output_text = None
    last_output_status = None

    # Playback estimation variables
    last_pos = 0.0
    last_pos_time = time.monotonic()
    last_poll_time = 0.0

    while True:
        try:
            _, props = connector.get_active_player(preferred_player)

            # If DBus fails momentarily, try fallback
            if not props and isinstance(connector, MprisPlayerDbus):
                fallback = MprisPlayerCtl()
                _, props = fallback.get_active_player(preferred_player)

            if not props:
                # No player active
                if last_output_status != "Stopped":
                    data = {
                        "text": "",
                        "next": "",
                        "artist": "",
                        "title": "",
                        "status": "Stopped",
                        "hasLyrics": False,
                        "position": 0.0,
                        "duration": 0.0,
                        "progress": 0.0,
                    }
                    if plain_output:
                        print("", flush=True)
                    else:
                        print(json.dumps(data), flush=True)
                    last_output_text = ""
                    last_output_status = "Stopped"
                time.sleep(1.0)
                continue

            status = props.get("status", "Stopped")
            title = props.get("title", "")
            artist = props.get("artist", "")
            album = props.get("album", "")
            duration = props.get("duration", 0.0)
            track_id = props.get("track_id", "") or f"{artist}-{title}"
            reported_pos = props.get("position", 0.0)

            # Track changed
            if track_id != last_track_id or title != last_title or artist != last_artist:
                last_track_id = track_id
                last_title = title
                last_artist = artist
                last_pos = reported_pos
                last_pos_time = time.monotonic()

                # Fetch or load LRC
                raw_lrc = find_local_lrc(artist, title, props.get("url", ""))
                if not raw_lrc:
                    raw_lrc = fetch_online_lrc(artist, title, album, duration)

                if raw_lrc:
                    lrc_entries = parse_lrc(raw_lrc)
                    lrc_timestamps = [e[0] for e in lrc_entries]
                    has_synced_lyrics = len(lrc_entries) > 0
                else:
                    lrc_entries = []
                    lrc_timestamps = []
                    has_synced_lyrics = False

                last_output_text = None  # Force immediate update

            now = time.monotonic()

            # Resync position periodically (every 0.5s) to avoid drift
            if now - last_poll_time > 0.5:
                last_pos = reported_pos
                last_pos_time = now
                last_poll_time = now

            # Estimate current position
            if status == "Playing":
                est_pos = last_pos + (now - last_pos_time)
            else:
                est_pos = last_pos

            current_text = ""
            next_text = ""
            time_to_next = 0.25

            if has_synced_lyrics and lrc_timestamps:
                idx = bisect.bisect_right(lrc_timestamps, est_pos) - 1
                if idx >= 0:
                    current_text = lrc_entries[idx][1]
                    if idx + 1 < len(lrc_entries):
                        next_text = lrc_entries[idx + 1][1]
                        time_to_next = max(0.05, lrc_entries[idx + 1][0] - est_pos)
                else:
                    # Before first lyric
                    current_text = ""
                    if lrc_entries:
                        next_text = lrc_entries[0][1]
                        time_to_next = max(0.05, lrc_entries[0][0] - est_pos)
            else:
                current_text = ""
                next_text = ""
                time_to_next = 0.5

            progress = (est_pos / duration) if duration > 0 else 0.0

            # Emit output if lyric, status, or title changed
            if current_text != last_output_text or status != last_output_status:
                last_output_text = current_text
                last_output_status = status

                data = {
                    "text": current_text,
                    "next": next_text,
                    "artist": artist,
                    "title": title,
                    "album": album,
                    "status": status,
                    "hasLyrics": has_synced_lyrics,
                    "position": round(est_pos, 2),
                    "duration": round(duration, 2),
                    "progress": round(progress, 3),
                }

                if plain_output:
                    print(current_text, flush=True)
                else:
                    print(json.dumps(data), flush=True)

            # Efficient sleep: calculate sleep interval until next lyric change
            sleep_time = min(0.35, max(0.05, time_to_next))
            time.sleep(sleep_time)

        except KeyboardInterrupt:
            break
        except Exception:
            time.sleep(1.0)


if __name__ == "__main__":
    main()
