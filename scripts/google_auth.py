#!/usr/bin/env python3
"""
Google OAuth 2.0 helper for Quickshell Google Calendar integration.
Usage: python3 google_auth.py <client_id> <client_secret>
Prints JSON to stdout: {"access_token":"...","refresh_token":"...","expiry":<unix_ts>}
Exits 0 on success, 1 on failure (error to stderr).
"""

import os
import sys
import json
import time
import socket
import webbrowser
import urllib.parse
import urllib.request
from http.server import HTTPServer, BaseHTTPRequestHandler


def find_free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        return s.getsockname()[1]


def main():
    if len(sys.argv) != 3:
        print("Usage: google_auth.py <client_id> <client_secret>", file=sys.stderr)
        sys.exit(1)

    client_id = sys.argv[1]
    client_secret = sys.argv[2]

    port = find_free_port()
    redirect_uri = f"http://127.0.0.1:{port}"

    auth_code = [None]

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            parsed = urllib.parse.urlparse(self.path)
            params = urllib.parse.parse_qs(parsed.query)
            if "code" in params:
                auth_code[0] = params["code"][0]
                self.send_response(200)
                self.send_header("Content-Type", "text/html")
                self.end_headers()
                self.wfile.write(
                    b"<html><body>"
                    b"<h2>Authorization successful! You can close this tab.</h2>"
                    b"<script>window.open('','_self','');window.close();</script>"
                    b"</body></html>"
                )
            else:
                error = params.get("error", ["unknown"])[0]
                self.send_response(400)
                self.send_header("Content-Type", "text/html")
                self.end_headers()
                self.wfile.write(
                    f"<html><body><h2>Authorization failed: {error}</h2></body></html>".encode()
                )

        def log_message(self, format, *args):
            pass  # suppress request logs

    auth_url = (
        "https://accounts.google.com/o/oauth2/v2/auth?"
        + urllib.parse.urlencode(
            {
                "client_id": client_id,
                "redirect_uri": redirect_uri,
                "response_type": "code",
                "scope": "https://www.googleapis.com/auth/calendar",
                "access_type": "offline",
                "prompt": "consent",
            }
        )
    )

    # webbrowser.open() may print informational messages (e.g. "Opening in
    # existing browser session.") to stdout, which would corrupt the JSON
    # result we write there later. Redirect stdout → stderr for the duration
    # of the call so those messages appear as logs instead.
    old_stdout_fd = os.dup(1)
    os.dup2(2, 1)
    try:
        webbrowser.open(auth_url)
    finally:
        os.dup2(old_stdout_fd, 1)
        os.close(old_stdout_fd)

    server = HTTPServer(("127.0.0.1", port), Handler)
    # A bad client id leaves Google on its own error page and the redirect never comes;
    # without a timeout this process, and the shell's "Connecting…" state, wait forever.
    server.timeout = 300
    server.handle_request()  # handle exactly one request, or give up on timeout

    if not auth_code[0]:
        print("No authorization code received (timed out or denied)", file=sys.stderr)
        sys.exit(1)

    # Exchange authorization code for tokens
    token_body = urllib.parse.urlencode(
        {
            "code": auth_code[0],
            "client_id": client_id,
            "client_secret": client_secret,
            "redirect_uri": redirect_uri,
            "grant_type": "authorization_code",
        }
    ).encode()

    req = urllib.request.Request(
        "https://oauth2.googleapis.com/token",
        data=token_body,
        method="POST",
    )

    try:
        with urllib.request.urlopen(req) as resp:
            token_resp = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        print(f"Token exchange failed ({e.code}): {body}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Token exchange failed: {e}", file=sys.stderr)
        sys.exit(1)

    expiry = int(time.time()) + token_resp.get("expires_in", 3600)

    result = {
        "access_token": token_resp.get("access_token", ""),
        "refresh_token": token_resp.get("refresh_token", ""),
        "expiry": expiry,
    }

    print(json.dumps(result))
    sys.exit(0)


if __name__ == "__main__":
    main()
