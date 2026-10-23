#!/usr/bin/env python3
# Shows the phone's motion as the game gets it: it greets the launcher's bridge (127.0.0.1:47701)
# like a game, so the launcher hands it the phone's pad packets, and prints their acceleration
# (in g) and angular velocity (rad/s) for a few seconds. A game has to be playing so the phone
# shows its pad; the game gets no pad from the phone while this runs.
#     python3 tool/motion_test.py [seconds]
import socket, struct, sys, time
bridge = ("127.0.0.1", 47701)
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("127.0.0.1", 0))
s.settimeout(0.2)
end = time.time() + float(sys.argv[1] if len(sys.argv) > 1 else 8)
greeted = 0
shown = 0
while time.time() < end:
    if time.time() - greeted > 0.3:
        s.sendto(struct.pack("<IHH8x", 0x48525041, 1, 16), bridge)
        greeted = time.time()
    try:
        data, _ = s.recvfrom(512)
    except socket.timeout:
        continue
    if len(data) != 80 or struct.unpack_from("<I", data, 0)[0] != 0x49525041:
        continue
    if time.time() - shown < 0.25:
        continue
    shown = time.time()
    motion = struct.unpack_from("<I", data, 12)[0] & 1
    ax, ay, az, gx, gy, gz = struct.unpack_from("<6f", data, 56)
    print(f"motion={motion}  accel g: x={ax/9.80665:+.2f} y={ay/9.80665:+.2f} z={az/9.80665:+.2f}   gyro rad/s: x={gx:+.2f} y={gy:+.2f} z={gz:+.2f}")
print("done")
