#!/usr/bin/env python3
# Feels the phone's rumble and light bar without a game: it plays a pretend game on the
# launcher's bridge (127.0.0.1:47701) and sends a pattern the launcher passes to the connected
# phone: the large motor, the small one, a ramp, pulses, then a red light bar. Keep the app in
# front on the phone.
#     python3 tool/rumble_test.py
import socket, struct, time
bridge = ("127.0.0.1", 47701)
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("127.0.0.1", 0))
s.sendto(struct.pack("<IHH8x", 0x48525041, 1, 16), bridge)
seq = 0
def out(large, small, light=None, ms=1500):
    global seq
    end = time.time() + ms / 1000
    while time.time() < end:
        seq += 1
        r, g, b = light or (0, 0, 0)
        pkt = struct.pack("<IHHIIQBBBBBBBB", 0x4F525041, 1, 32, seq, 0, 0, large, small, 1 if light else 0, r, g, b, 0, 0)
        s.sendto(pkt, bridge)
        if seq % 50 == 0: s.sendto(struct.pack("<IHH8x", 0x48525041, 1, 16), bridge)
        time.sleep(0.008)
print("large motor"); out(255, 0)
out(0, 0, ms=500)
print("small motor"); out(0, 200)
out(0, 0, ms=500)
print("ramp")
for level in range(16, 256, 16): out(level, 0, ms=100)
out(0, 0, ms=500)
print("pulses")
for _ in range(6): out(255, 120, ms=120); out(0, 0, ms=180)
print("red light bar"); out(0, 0, light=(255, 30, 30), ms=2000)
out(0, 0, ms=300)
print("done")
