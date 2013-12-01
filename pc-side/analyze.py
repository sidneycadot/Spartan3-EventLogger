#! /usr/bin/env python

import numpy as np
from matplotlib import pyplot as plt
import scipy.signal

def analyze_pps(tw, sq, tf, pps, allowed_deviation_from_start_of_second):

    assert tw.shape == tf.shape == pps.shape

    # Only keep the entries where the PPS signal changes

    curr = pps[1:]
    prev = pps[:-1]

    change = (curr != prev)
    change = np.insert(change, 0, False)

    print "Keeping", sum(change), "of", len(change), "values."

    tw = tw[change]
    tf = tf[change]
    pps = pps[change]

    # Verify that the PPS signal is now alternating

    assert np.all(np.diff(pps))

    # If the first event is a "down" event, we discard it -- we are only interested in complete "100 ms" records.

    if pps[0] == False:
        tw = tw[1:]
        tf = tf[1:]
        pps = pps[1:]

    # If the last event is an "up" event, we discard it -- we are only interested in complete "100 ms" records.

    if pps[-1] == True:
        tw  = tw[:-1]
        tf  = tf[:-1]
        pps = pps[:-1]

    # Check that the PPS record is alternating, begins with an "Up" event, and is even-length
    # If this is true, the PPS signal holds no more information and we can discard it.

    assert np.all(np.diff(pps))
    assert pps[0]
    assert len(pps) % 2 == 0

    assert tw.shape == tf.shape == pps.shape

    del pps

    # Reshape the tw and tf arrays, to have start/end columns

    tw = tw.reshape((-1, 2))
    tf = tf.reshape((-1, 2))

    # Only accept pulses that are within 5ms of the expected 100ms length

    duration_approx = (tf[:, 1] - tf[:, 0]) / 50000000.0

    good_duration = np.abs(duration_approx - 0.100) <= 0.005

    tw = tw[good_duration, :]
    tf = tf[good_duration, :]

    # Project the wallclock time to the nearest second.

    tw_int = np.round(tw[:, 0]).astype(np.int64)

    times_ok = (np.abs(tw[:, 0] - tw_int) <= allowed_deviation_from_start_of_second) & (np.abs(tw[:, 1] - tw_int) <= allowed_deviation_from_start_of_second)

    tw_int = tw_int[times_ok]
    tf     = tf[times_ok, :]

    return (tw_int, tf)

def read_log(filename):

    # tw   : wallclock time (float)
    # sq   : sequence number of event (decimal integer)
    # tf   : FPGA time (decimal integer)
    # bits : bit-vector (hexadecimal integer)

    (tw, sq, tf, bits) = np.loadtxt(filename, dtype = np.float64, comments = "#", unpack = True)

    # Convert integer-valued columns to integers

    tf   = tf.astype(np.int64)
    sq   = sq.astype(np.int64)
    bits = bits.astype(np.int64)

    # Verify that the sequence numbers are indeed sequential.
    # If this checks out, forget about them, because they don't hold useful information.

    #assert np.all(np.diff(sq) == 1)
    #del sq

    # Extract pps0 (PPS-GPS), pps1 (PPS-HOST), and pps2 (PPS-CPLD).

    pps0 = (bits & 1 != 0) # The PPS from the GPS
    pps1 = (bits & 2 != 0) # The PPS generated by the host ("serial" program)
    pps2 = (bits & 4 != 0) # The PPS generated by the CPLD (not synced to start-of-second; based on 8 MHz chrystal)

    del bits

    # Analyze the PPS signals

    (tw0, tf0) = analyze_pps(tw, sq, tf, pps0, 0.150)
    (tw1, tf1) = analyze_pps(tw, sq, tf, pps1, 0.150)
    (tw2, tf2) = analyze_pps(tw, sq, tf, pps2, 1.000)

    t_min = min(np.min(tw0), np.min(tw1), np.min(tw2))
    t_max = max(np.max(tw0), np.max(tw1), np.max(tw2))

    n = t_max - t_min + 1

    t = np.arange(t_min, t_max + 1, dtype = np.int64)

    # tdata[:, 0] --> the FPGA clock of the GPS-PPS rising edge
    # tdata[:, 1] --> the FPGA clock of the GPS-PPS falling edge
    # tdata[:, 2] --> the FPGA clock of the HOST-PPS rising edge
    # tdata[:, 3] --> the FPGA clock of the HOST-PPS falling edge

    tdata = np.zeros((n, 6)) ; tdata[:] = np.nan

    tdata[tw0 - t_min, 0:2] = tf0
    tdata[tw1 - t_min, 2:4] = tf1
    tdata[tw2 - t_min, 4:6] = tf2

    t_base = 86400.0 * np.floor(t[0] / 86400.0)
    th = (t - t_base) / 3600.0 + 1

    # Generate the deviation subplot

    tt = tdata[:, 2] - tdata[:, 0] # computer time - GPS time

    tt2 = tt.copy()

    for (window_size, cutoff_factor) in [(61, 10), (31, 5), (11, 2), (5, 1.5), (3, 1.1)]:

        print "filter start:", np.sum(np.isfinite(tt2))

        tt2_minimum = scipy.signal.order_filter(tt2, np.ones(window_size), 0)
        tt2_median  = scipy.signal.medfilt(tt2, window_size)

        tt2_cutoff = tt2_median + cutoff_factor * (tt2_median - tt2_minimum)

        spikes = tt2 > tt2_cutoff

        tt2[spikes] = np.nan

        print "filter end:", np.sum(np.isfinite(tt2))

    # Generate plot

    (fig, axes_array) = plt.subplots(4, 1, sharex=True)

    # Plot #1

    ax = axes_array[0]
    ax.plot(th, tt / 50.0, th, tt2 / 50.0, '+')
    ax.set_title("Deviation of host clock vs. GPS clock")
    #plt.xlabel("time [h]")
    ax.set_ylabel("deviation (host - gps) [us]")

    ax.set_ylim(-120, +120)
    ax.grid(True)

    # Plot #2: FPGA frequency derived from GPS-PPS

    ax = axes_array[1]

    freq_gps = np.diff(tdata[:, 0]) - 50000000.0
    freq_gps = np.append(freq_gps, np.nan)

    ax.plot(th, freq_gps, "+")
    ax.set_title("FPGA frequency assuming GPS-PPS is perfect")
    ax.set_ylabel("freq - 50 MHz [Hz]")

    ax.set_ylim(-260, -60)
    ax.grid(True)

    # Plot #3: FPGA frequency derived from HOST-PPS

    ax = axes_array[2]

    freq_host = np.diff(tdata[:, 2]) - 50000000.0
    freq_host = np.append(freq_host, np.nan)

    freq_host2 = scipy.signal.medfilt(freq_host, 61)

    ax.plot(th, freq_gps, th, freq_host2, "-")
    ax.set_title("FPGA frequency assuming HOST-PPS is perfect")
    ax.set_ylabel("freq - 50 MHz [Hz]")

    ax.set_ylim(-260, -60)
    ax.grid(True)

    # Plot #4: FPGA frequency derived from CPLD-PPS

    ax = axes_array[3]

    freq = np.diff(tdata[:, 4]) - 50000000.0
    freq = np.append(freq, np.nan)

    freq2 = scipy.signal.medfilt(freq, 61)

    ax.plot(th, freq2, "-")
    ax.set_title("FPGA frequency assuming CPLD-PPS is perfect")
    ax.set_xlabel("time [h]")
    ax.set_ylabel("freq - 50 MHz [Hz]")

    ax.set_ylim(-350, +150)
    ax.grid(True)

    # Show the plots

    plt.show()

def main():
    read_log("LOG3")

if __name__ == "__main__":
    main()
