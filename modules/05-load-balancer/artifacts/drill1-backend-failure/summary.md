# Drill summary: backend failure and health check failover

The client polled the VIP 60 times at 0.25s while web1 was stopped (request 15)
and later restarted (request 40). Response bodies name the serving backend.
Numbers from responses.txt and analysis.txt.

| Window | web1 | web2 | failed |
|--------|-----:|-----:|-------:|
| whole run (60 requests) | 17 | 42 | 1 |
| during outage (requests 18 to 38) | 0 | 21 | 0 |

## What happened, request by request

- Requests 1 to 14: round robin, roughly alternating web1 and web2.
- Request 15: web1 stopped. The very next request that hashed to web1 failed
  once (the single FAILED in the run): the connection HAProxy had already
  chosen was in flight when the backend died.
- Within about 2 seconds (health check `inter 1s fall 2`: two failed checks),
  HAProxy marked web1 down and stopped sending it traffic. From request 18
  onward, every request went to web2. Zero failures during the outage window.
- Request 40: web1 restarted. Health check `rise 2` brought it back after two
  good checks, and round robin resumed across both.

## The lesson

A load balancer does not prevent the single in flight request from failing
when a backend dies without warning; it prevents the next thousand. The health
check interval and fall count set how fast "next" begins: here about 2 seconds.
Tightening `inter` and `fall` shrinks the failure window at the cost of more
health check traffic and more sensitivity to transient blips, the same
fast-detection tradeoff seen with routing timers in the other modules.
