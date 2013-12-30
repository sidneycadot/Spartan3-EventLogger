#! /usr/bin/env python

import serial, re, binascii, time

fpga = serial.Serial("/dev/ttyUSB1", 115200, serial.EIGHTBITS, serial.PARITY_NONE, serial.STOPBITS_ONE)

pattern = re.compile("^([0-9a-f]{16}) ([0-9a-f]{16}) ([0-9a-f]{16}) ([0-9a-f]{8})\r\n$")

for line in fpga:

    t = time.time()

    match = pattern.match(line)

    if match is None:
        print "# rejected malformed line:", [ord(c) for c in line]
        continue

    sequenceNr = match.group(1)
    timestamp  = match.group(2)
    data       = match.group(3)
    checksum   = match.group(4)

    together = sequenceNr + timestamp + data
    s = []
    while together:
        s.append(chr(int(together[:2], 16)))
        together = together[2:]
    s = "".join(s)

    checksum_calculated = binascii.crc32(s) & 0xffffffff

    hex_checksum_calculated = "%08x" % checksum_calculated

    if checksum != hex_checksum_calculated:
        print "# rejected line because of checksum mismatch: <%s>" % line[:-2]
        continue

    sequenceNr = int(sequenceNr, 16)
    timestamp = int(timestamp, 16)
    data = int(data, 16)

    print "%20.9f %20d %20d %20d" % (t, sequenceNr, timestamp, data)
