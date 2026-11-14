#!/usr/bin/env python3
"""A tiny OpenSubsonic stand-in for the harness (the Simulator reaches the Mac at localhost).

    python3 Harness/mockserver.py            # serves http://localhost:4533/rest/…

Answers ping, getAlbum and getCoverArt with made-up data (no real music, no real covers), enough for the
redesign's rebuilt pages. Requests must carry u/t/s like NaviMus's, or they're refused like a real server.
"""
import json
import struct
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

ALBUMS = {
    "al-1": {
        "id": "al-1", "name": "Harness Album 1", "artist": "Harness Artist", "artistId": "ar-1",
        "coverArt": "al-1", "year": 2026, "genre": "Hip-Hop/Rap", "releaseTypes": ["Album"],
        "song": [
            {"id": "so-%d" % n, "title": title, "artist": artist, "track": n, "duration": 180 + n,
             "explicitStatus": "explicit" if n % 2 else ""}
            for n, (title, artist) in enumerate([
                ("Purpose General", "Harness Artist"),
                ("Face The Flame", "Harness Artist, Guest Singer, Another Guest"),
                ("Lose Control", "Harness Artist, Second Guest"),
                ("Fourth Song", "Harness Artist"),
                ("Fifth Song", "Harness Artist"),
                ("Sixth Song", "Harness Artist, Guest Singer"),
                ("Seventh Song", "Harness Artist"),
                ("Eighth Song", "Harness Artist"),
            ], start=1)
        ],
    },
}


def png(width, height):
    """A diagonal gradient PNG, written by hand (no imaging library needed)."""
    rows = []
    for y in range(height):
        row = bytearray([0])
        for x in range(width):
            t = (x + y) / (width + height)
            row += bytes([int(40 + 150 * (1 - t)), int(90 + 60 * t), int(80 + 40 * t)])
        rows.append(bytes(row))
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(b"".join(rows))) + chunk(b"IEND", b"")


class Handler(BaseHTTPRequestHandler):
    def reply(self, body, kind="application/json"):
        self.send_response(200)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def subsonic(self, payload, ok=True):
        body = {"subsonic-response": dict({"status": "ok" if ok else "failed", "version": "1.16.1",
                                           "type": "harness", "openSubsonic": True}, **payload)}
        self.reply(json.dumps(body).encode())

    def do_GET(self):
        url = urlparse(self.path)
        query = {k: v[0] for k, v in parse_qs(url.query).items()}
        endpoint = url.path.rsplit("/", 1)[-1].replace(".view", "")
        if not (query.get("u") and query.get("t") and query.get("s")):
            return self.subsonic({"error": {"code": 10, "message": "Required parameter is missing"}}, ok=False)
        if endpoint == "ping":
            return self.subsonic({})
        if endpoint == "getAlbum":
            album = ALBUMS.get(query.get("id", ""))
            if not album:
                return self.subsonic({"error": {"code": 70, "message": "Album not found"}}, ok=False)
            return self.subsonic({"album": album})
        if endpoint == "getCoverArt":
            size = max(32, min(int(query.get("size", "300")), 600))
            return self.reply(png(size, size), "image/png")
        self.subsonic({"error": {"code": 0, "message": "Not in the harness: " + endpoint}}, ok=False)

    def log_message(self, fmt, *args):
        print("mockserver:", self.command, self.path.split("?")[0])


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 4533), Handler).serve_forever()
