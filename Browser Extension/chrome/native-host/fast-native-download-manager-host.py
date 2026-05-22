#!/usr/bin/python3
import json
import os
import struct
import subprocess
import sys
import time
import urllib.parse

LOG_PATH = "/tmp/fast-native-download-manager-native-host.log"
INBOX_PATH = "/tmp/fast-native-download-manager-incoming.jsonl"


def log(message):
    with open(LOG_PATH, "a", encoding="utf-8") as handle:
        handle.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {message}\n")


def read_message():
    raw_length = sys.stdin.buffer.read(4)
    if len(raw_length) == 0:
        return None
    if len(raw_length) != 4:
        raise ValueError("Invalid native message length header.")

    message_length = struct.unpack("<I", raw_length)[0]
    if message_length <= 0 or message_length > 1024 * 1024:
        raise ValueError("Invalid native message length.")

    payload = sys.stdin.buffer.read(message_length)
    if len(payload) != message_length:
        raise ValueError("Invalid native message payload.")

    return json.loads(payload.decode("utf-8"))


def write_message(message):
    encoded = json.dumps(message, separators=(",", ":")).encode("utf-8")
    sys.stdout.buffer.write(struct.pack("<I", len(encoded)))
    sys.stdout.buffer.write(encoded)
    sys.stdout.buffer.flush()


def is_http_url(value):
    parsed = urllib.parse.urlparse(value or "")
    return parsed.scheme in ("http", "https") and bool(parsed.netloc)


def main():
    log("host started")
    message = read_message()
    if message is None:
        log("no message")
        return

    log("message " + json.dumps(message, separators=(",", ":")))
    target_url = message.get("url", "")
    if not is_http_url(target_url):
        log("rejected invalid url")
        write_message({"ok": False, "error": "Expected an HTTP or HTTPS URL."})
        return

    os.makedirs(os.path.dirname(INBOX_PATH), exist_ok=True)
    with open(INBOX_PATH, "a", encoding="utf-8") as inbox:
        inbox.write(json.dumps({"url": target_url, "source": "chrome"}, separators=(",", ":")) + "\n")
    log("queued inbox " + INBOX_PATH)

    log("opening app")
    subprocess.Popen(
        ["/usr/bin/open", "-g", "-b", "dev.codex.FastNativeDownloadManager"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    write_message({"ok": True})
    log("ok")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        log("error " + str(exc))
        write_message({"ok": False, "error": str(exc)})
