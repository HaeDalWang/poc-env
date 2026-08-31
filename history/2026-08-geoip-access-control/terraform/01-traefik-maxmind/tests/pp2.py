#!/usr/bin/env python3
"""Replay requests through a Traefik entrypoint with a forged PROXY v2 header.

The customer's NLB does not preserve the client IP at the TCP layer; it prepends
a PROXY protocol v2 header and Traefik rebuilds RemoteAddr from it. Anything the
entrypoint trusts can therefore claim any source address, which lets a single
in-cluster Pod produce per-country evidence without sourcing traffic abroad.

Run it against the pptest entrypoint only. Never against a public one.

    python3 pp2.py <host:port> <http_host> <path> <ip[,ip...]>

Example:
    python3 pp2.py svc:9000 sms.example.com '/SMS.asmx?WSDL' 168.126.63.1,8.8.8.8
"""

import re
import socket
import struct
import sys

PROXY_V2_SIGNATURE = b"\x0d\x0a\x0d\x0a\x00\x0d\x0a\x51\x55\x49\x54\x0a"
VERSION_AND_COMMAND = 0x21  # v2, PROXY
FAMILY_AND_PROTOCOL = 0x11  # AF_INET, STREAM
SOURCE_PORT = 12345
CONNECT_TIMEOUT_SECONDS = 10
READ_LIMIT_BYTES = 65536

HEADER_PATTERN = re.compile(
    r"^(X-Geoip2-Country|X-Geoip2-Ipaddress|X-Geoip2-Region):\s*(.+)$",
    re.IGNORECASE | re.MULTILINE,
)


def build_proxy_v2_header(source_ip, destination_ip, destination_port):
    """Return a PROXY v2 header claiming the connection came from source_ip."""
    address_block = (
        socket.inet_aton(source_ip)
        + socket.inet_aton(destination_ip)
        + struct.pack("!HH", SOURCE_PORT, destination_port)
    )
    return (
        PROXY_V2_SIGNATURE
        + struct.pack("!BBH", VERSION_AND_COMMAND, FAMILY_AND_PROTOCOL, len(address_block))
        + address_block
    )


def send_request(target_host, target_port, source_ip, http_host, path, extra_headers=None):
    """Send one forged-source request and return (status_line, headers, body)."""
    connection = socket.create_connection((target_host, target_port), timeout=CONNECT_TIMEOUT_SECONDS)
    try:
        destination_ip = connection.getsockname()[0]
        connection.sendall(build_proxy_v2_header(source_ip, destination_ip, target_port))

        request_lines = [
            f"GET {path} HTTP/1.1",
            f"Host: {http_host}",
            "User-Agent: geoip-poc-pp2",
            "Connection: close",
        ]
        request_lines.extend(extra_headers or [])
        connection.sendall(("\r\n".join(request_lines) + "\r\n\r\n").encode())

        received = b""
        while len(received) < READ_LIMIT_BYTES:
            chunk = connection.recv(4096)
            if not chunk:
                break
            received += chunk
    finally:
        connection.close()

    text = received.decode(errors="replace")
    head, _, body = text.partition("\r\n\r\n")
    status_line = head.split("\r\n")[0] if head else "<no response>"
    return status_line, head, body


def status_code(status_line):
    parts = status_line.split()
    return parts[1] if len(parts) > 1 else "???"


def extract_geoip_headers(body):
    """whoami echoes request headers in its body, which is where the verdict shows."""
    found = {name.lower(): value.strip() for name, value in HEADER_PATTERN.findall(body)}
    return (
        found.get("x-geoip2-country", "-"),
        found.get("x-geoip2-ipaddress", "-"),
    )


def main():
    if len(sys.argv) != 5:
        print(__doc__, file=sys.stderr)
        return 2

    endpoint, http_host, path, ip_list = sys.argv[1:5]
    if ":" not in endpoint:
        print(f"endpoint must be host:port, got {endpoint!r}", file=sys.stderr)
        return 2

    target_host, _, port_text = endpoint.rpartition(":")
    try:
        target_port = int(port_text)
    except ValueError:
        print(f"port must be numeric, got {port_text!r}", file=sys.stderr)
        return 2

    source_ips = [ip.strip() for ip in ip_list.split(",") if ip.strip()]
    if not source_ips:
        print("at least one source IP is required", file=sys.stderr)
        return 2

    print(f"target   {endpoint}")
    print(f"host     {http_host}")
    print(f"path     {path}")
    print()
    print(f"{'claimed source':<18} {'code':<6} {'country':<9} {'plugin saw':<18}")
    print("-" * 55)

    failures = 0
    for source_ip in source_ips:
        try:
            status_line, _, body = send_request(target_host, target_port, source_ip, http_host, path)
        except (OSError, socket.timeout) as error:
            print(f"{source_ip:<18} {'ERR':<6} {str(error)[:30]}")
            failures += 1
            continue

        country, seen_ip = extract_geoip_headers(body)
        print(f"{source_ip:<18} {status_code(status_line):<6} {country:<9} {seen_ip:<18}")

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
