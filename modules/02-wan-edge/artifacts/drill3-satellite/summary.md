# Drill 3 summary: satellite conditions vs TCP

tc netem adds 300ms delay and 0.5% loss on each of ispa's two site facing
interfaces: 600ms RTT round trip, roughly 1% loss per round trip, the profile
of a geostationary satellite hop. iperf3 measures a single TCP flow s1h to
s2h. Raw JSON in this directory; ping artifacts prove the impairment.

| Condition | Throughput | Retransmits | RTT |
|-----------|-----------:|------------:|-----|
| baseline, no impairment | **5486 Mbps** | 0 | 0.095 ms |
| 600ms RTT + loss, default TCP (cubic) | **11 Mbps** | 7 | 600.7 ms |
| 600ms RTT + loss, BBR + 64MB buffers | **115 Mbps** | 5614 | 600.7 ms |

## Reading the numbers

- **The collapse is 500x**, from 5486 to 11 Mbps, and it is not bandwidth: the
  path is identical hardware. Throughput of one flow is bounded by
  window/RTT, and cubic additionally halves its window on every loss event on
  a link where loss is noise, not congestion. It spends the whole test
  crawling back from drops it should have ignored.
- **Tuning recovers 10x** (11 to 115 Mbps) from two changes measured together:
  raising the namespaced TCP buffer ceilings (net.ipv4.tcp_rmem and tcp_wmem
  to 64MB) so autotuning can open a window that covers the bandwidth delay
  product, and switching congestion control to BBR, which models bandwidth and
  RTT instead of reacting to loss.
- **The retransmit column is the tell.** Cubic's 7 retransmits at 11 Mbps
  mean it barely sent anything to lose. BBR's 5614 retransmits at 115 Mbps
  are 0.5% of a much larger volume: it keeps pushing through random loss and
  pays the retransmission cost, which is the correct trade on this link.
- This physics is why WAN accelerators (the Riverbed class devices named in
  DoD postings) exist: terminate TCP locally on each side of the satellite
  hop, spoof acknowledgments, and apply compression and deduplication.

## Lab honesty notes

The first run of this drill produced a baseline of 12 Mbps at 600ms RTT: a
previous failed run had left netem applied, poisoning the measurement. The
drill now removes impairments before measuring and on every exit
(WHAT-BROKE.md entry 4). Also, net.core.rmem_max is not writable inside a
network namespace; the namespaced net.ipv4.tcp_rmem and tcp_wmem ceilings are
what matter for TCP autotuning in containers.
