"""Helicopter landing approach model, fitted to RPT telemetry.

Why a HAL transport climbs when it brakes, and which speed schedule stops it.

This is a model, not the engine. It has three parts, each fitted to the
CLASH SCARGO AIR DIAG snapshots in Arma3_x64_2026-10-10_23-22-36.rpt:

  1. Arrival law. An AI helicopter closing on its last waypoint holds
     speed <= K * distance. Every landing leg in the RPT sits on that line.
  2. Zoom. Braking is a nose-up flare. The kinetic energy shed goes into
     height: climb rate = ETA * decel * speed / g.
  3. Height hold. The pilot pushes back toward flyInHeight, but only at up
     to U_DOWN metres per second.

So the aircraft balloons whenever decel * speed / g exceeds U_DOWN. The arrival
law alone demands K * v * v / g, which passes U_DOWN above about 130 km/h.

The schedules compared are flown from a standstill over the leg lengths HAL
actually flew, by three pilots that differ in the one thing the RPT does not
show: how hard a SMALL height error is corrected.

Run:  python tools/approach_sim.py
"""

from __future__ import annotations

import itertools
import math
from dataclasses import dataclass, replace

G = 9.81
KMH = 3.6

# [seconds, metres to waypoint (2D), m/s, metres above ground]
# Legs A and B: Huron flying to a pickup. Leg C: Huron delivering, mode LAND.
# Legs D and E: Littlebird pickup hops, used for the arrival law only.
LEGS = {
    "A": [[0, 2396, 69.4, 68], [6, 2069, 72.2, 80], [11, 1862, 66.9, 148],
          [19, 1616, 70.0, 142], [24, 1276, 72.2, 109], [30, 892, 69.7, 102],
          [35, 603, 46.9, 281], [40, 407, 28.3, 291], [46, 280, 18.6, 262],
          [51, 194, 12.8, 234], [56, 134, 8.9, 188]],
    "B": [[0, 1913, 65.3, 64], [5, 1576, 66.1, 94], [10, 1230, 68.9, 79],
          [16, 857, 65.8, 135], [21, 584, 44.4, 226], [26, 400, 27.8, 269],
          [31, 274, 18.3, 251], [37, 190, 12.5, 212], [42, 131, 8.6, 166],
          [47, 91, 6.1, 119]],
    "C": [[0, 1756, 47.5, 75], [6, 1478, 55.6, 62], [11, 1167, 58.6, 54],
          [17, 815, 61.9, 82], [22, 563, 41.9, 181], [27, 385, 25.0, 197]],
    "D": [[0, 342, 7.5, 48], [5, 245, 17.5, 64], [13, 171, 11.9, 49],
          [18, 119, 8.3, 58]],
    "E": [[0, 308, 7.2, 48], [5, 217, 15.8, 84], [10, 152, 10.3, 64],
          [15, 106, 7.2, 49]],
}


@dataclass(frozen=True)
class Pilot:
    """The AI pilot. Speed terms are the least-squares fit; see PILOTS."""
    k_arrive: float = 0.07    # 1/s, arrival law
    k_speed: float = 0.60     # 1/s, how hard an overspeed is braked
    a_max: float = 4.5        # m/s^2
    eta: float = 1.1          # share of shed energy that becomes height
    u_down: float = 9.0       # m/s, most the height hold will descend
    u_up: float = 8.0
    k_height: float = 0.10    # 1/s, how hard a height error is corrected


# What the RPT pins down and what it does not.
#
# Pinned: k_arrive (five legs, 0.065 to 0.078), and u_down (descents after
# both Huron balloons run 8 to 10 m/s for as long as the error is large).
#
# Not pinned: k_height, the response to a SMALL height error. Every brake in
# the RPT is a hard one, so the data only says the hold loses badly to a 25
# m/s zoom. Whether it can cancel a 3 m/s one is the whole question for a
# gentle schedule, and the answer is not in this log. The fit prefers a soft
# hold, so "soft" is not a strawman.
PILOTS = {
    "soft": Pilot(eta=1.2, k_height=0.05),
    "middle": Pilot(),
    "firm": Pilot(eta=1.0, k_height=0.25),
}


# ---------------------------------------------------------------- schedules
# A schedule maps metres-to-go to (speed limit in km/h, height in metres).

ITW_RUNGS = [(300, 80, 10), (500, 90, 11), (1000, 110, 16), (1500, 150, 23),
             (2000, 190, 30), (2500, 230, 37), (3000, 270, 44)]
END_KMH, END_M, LOW_M = 80.0, 300.0, 10.0


def height_for(limit_kmh: float, cruise_m: float) -> float:
    """ITW's seven rungs are one line: 10 m at 80 km/h, 0.18 m per km/h."""
    return min(cruise_m, LOW_M + 0.18 * max(limit_kmh - END_KMH, 0.0))


def none(_d, cruise_m):
    return math.inf, cruise_m


def itw_stairs(d, cruise_m):
    """ITW_Attack.sqf:3812-3820, as written."""
    for limit_d, kmh, height in ITW_RUNGS:
        if d < limit_d:
            return float(kmh), float(min(height, cruise_m))
    return math.inf, cruise_m


def inside_1200(d, cruise_m):
    """ITW's last four rungs, starting at the run-in decision point."""
    if d >= 1200:
        return math.inf, cruise_m
    return itw_stairs(max(d, 0), cruise_m) if d < 1000 else (150.0, min(23.0, cruise_m))


def constant_power(power):
    """Shed kinetic energy at a fixed rate: v^3 = v_end^3 + 3 P (d - d_end).

    decel * speed is then P everywhere, so the zoom rate P / g is the same at
    every point of the approach, instead of largest where the aircraft is
    fastest.
    """
    def schedule(d, cruise_m):
        v_end = END_KMH / KMH
        v = (v_end ** 3 + 3.0 * power * max(d - END_M, 0.0)) ** (1.0 / 3.0)
        kmh = v * KMH
        return kmh, height_for(kmh, cruise_m)
    schedule.__name__ = f"power_{power:g}"
    return schedule


# --------------------------------------------------------------- simulation

def fly(schedule, pilot: Pilot, cruise_kmh: float, cruise_m: float = 50.0,
        start_m: float = 4000.0, tick_s: float = 0.5, dt: float = 0.05,
        start_v: float | None = None, start_h: float | None = None,
        sample_at: list[float] | None = None):
    """Fly one approach. Returns a summary and, if asked, samples at times."""
    d = start_m
    v = cruise_kmh / KMH if start_v is None else start_v
    h = cruise_m if start_h is None else start_h
    cruise_v = max(cruise_kmh / KMH, v)
    t, next_tick = 0.0, 0.0
    limit, h_cmd = math.inf, cruise_m
    peak, over, above60, slow, begun = h, 0.0, 0.0, 0.0, None
    samples, wanted = [], list(sample_at or [])
    while d > 60.0 and t < 900.0:
        if t >= next_tick:
            limit_kmh, h_cmd = schedule(d, cruise_m)
            limit = limit_kmh / KMH
            next_tick += tick_s
            if begun is None and limit < cruise_v:
                begun = d
        target = min(cruise_v, pilot.k_arrive * d, limit)
        if v > target:
            decel = min(pilot.k_speed * (v - target), pilot.a_max)
        else:
            # Departures in the RPT: 0 to 108 km/h in 5 s, 250 km/h by 40 s.
            decel = -min(0.08 * (cruise_v - v) + 0.2, 6.0, 2.0 * (target - v))
        zoom = pilot.eta * max(decel, 0.0) * v / G
        hold = max(-pilot.u_down, min(pilot.u_up, pilot.k_height * (h_cmd - h)))
        h = max(h + (zoom + hold) * dt, 0.0)
        v = max(v - decel * dt, 0.0)
        d -= v * dt
        t += dt
        peak = max(peak, h)
        over = max(over, h - h_cmd)
        above60 += dt if h > 60.0 else 0.0
        slow += dt if v * KMH < 120.0 else 0.0
        while wanted and t >= wanted[0]:
            samples.append((wanted.pop(0), d, v, h))
    return {"peak": peak, "over": over, "above60": above60, "slow": slow,
            "time": t, "begins": begun or 0.0}, samples


# ---------------------------------------------------------------------- fit

def fit() -> tuple[Pilot, float, float]:
    """Least squares on the three Huron legs: speed first, then height."""
    def speed_error(p):
        total, n = 0.0, 0
        for name in "ABC":
            leg = LEGS[name]
            first = next(i for i, s in enumerate(leg) if s[1] < 1400)
            t0, d0, v0, h0 = leg[first]
            times = [s[0] - t0 for s in leg[first + 1:]]
            _, got = fly(none, p, v0 * KMH, start_m=d0, start_v=v0, start_h=h0,
                         sample_at=times)
            for (_, _, v, _), s in zip(got, leg[first + 1:]):
                total += (v - s[2]) ** 2
                n += 1
        return math.sqrt(total / n)

    def height_error(p):
        total, n = 0.0, 0
        for name in "ABC":
            leg = LEGS[name]
            first = next(i for i, s in enumerate(leg) if s[1] < 1400)
            t0, d0, v0, h0 = leg[first]
            times = [s[0] - t0 for s in leg[first + 1:]]
            _, got = fly(none, p, v0 * KMH, start_m=d0, start_v=v0, start_h=h0,
                         sample_at=times)
            for (_, _, _, h), s in zip(got, leg[first + 1:]):
                total += (h - s[3]) ** 2
                n += 1
        return math.sqrt(total / n)

    best = min(
        (replace(Pilot(), k_arrive=k, k_speed=ks, a_max=am)
         for k, ks, am in itertools.product(
             [0.058, 0.060, 0.062, 0.064, 0.066, 0.068, 0.070],
             [0.3, 0.4, 0.5, 0.6, 0.8, 1.0, 1.5],
             [4.5, 5.0, 5.5, 6.5])),
        key=speed_error)
    v_rms = speed_error(best)
    best = min(
        (replace(best, eta=e, u_down=u, k_height=kh)
         for e, u, kh in itertools.product(
             [0.8, 0.9, 1.0, 1.1, 1.2], [6, 8, 10, 12, 14], [0.1, 0.25, 0.5])),
        key=height_error)
    return best, v_rms, height_error(best)


# --------------------------------------------------------------- comparison

AIRFRAMES = {"Huron": 250.0, "Littlebird": 215.0}
# Leg lengths HAL actually flew in that RPT: 1.9 to 4.4 km, from a standstill.
LEGS_M = (2000.0, 3000.0, 4400.0)
CANDIDATES = [none, itw_stairs, inside_1200] + [
    constant_power(p) for p in (15, 20, 25, 35, 50)]
# ITW_CLASH_HALStayLowPower. The largest that keeps the soft pilot's peak
# within about 20 m of the old 50 m cruise on every leg flown.
CHOSEN_POWER = 20


def exposure(schedule, pilot, cruise_kmh, leg_m):
    result, _ = fly(schedule, pilot, cruise_kmh, start_m=leg_m, start_v=0.0)
    return result


def main():
    pilot, v_rms, h_rms = fit()
    print("Least-squares pilot:", pilot)
    print(f"  speed residual {v_rms * KMH:.0f} km/h rms, height residual {h_rms:.0f} m rms")
    print()
    print("Model against the RPT, leg A (Huron to a pickup, no schedule):")
    leg = LEGS["A"]
    first = next(i for i, s in enumerate(leg) if s[1] < 1400)
    t0, d0, v0, h0 = leg[first]
    for name, p in PILOTS.items():
        _, got = fly(none, p, v0 * KMH, start_m=d0, start_v=v0, start_h=h0,
                     sample_at=[s[0] - t0 for s in leg[first + 1:]])
        if name == "soft":
            print("    t   RPT  d  km/h    m")
            for s_ in leg[first + 1:]:
                print(f"  {s_[0] - t0:3.0f}     {s_[1]:5.0f}  {s_[2] * KMH:4.0f}  {s_[3]:3.0f}")
        print(f"  {name:6} model m: " + " ".join(f"{h:4.0f}" for _, _, _, h in got)
              + "   km/h: " + " ".join(f"{v * KMH:4.0f}" for _, _, v, _ in got))
    print()
    for air, kmh in AIRFRAMES.items():
        for leg_m in LEGS_M:
            print(f"{air}, {leg_m:.0f} m leg from a standstill, cruise height 50 m")
            print(f"{'':13}" + "".join(f"{n:>22}" for n in PILOTS) + f"{'time':>8}")
            print(f"{'schedule':13}" + f"{'peak   >60 m':>22}" * len(PILOTS))
            for schedule in CANDIDATES:
                cells, time_s = "", 0.0
                for p in PILOTS.values():
                    r = exposure(schedule, p, kmh, leg_m)
                    cells += f"{r['peak']:13.0f}m {r['above60']:5.0f}s "
                    time_s = r["time"]
                print(f"{schedule.__name__:13}{cells}{time_s:7.0f}s")
            print()
    print("peak:  highest point of the leg, metres above ground")
    print(">60 m: seconds spent above 60 m")
    print()
    print("What each step of power buys and costs, soft pilot, Huron, 4400 m leg:")
    base = exposure(none, PILOTS["soft"], 250.0, 4400.0)
    for power in (10, 15, 20, 25, 30, 35, 50):
        r = exposure(constant_power(power), PILOTS["soft"], 250.0, 4400.0)
        mark = "  <- chosen" if power == CHOSEN_POWER else ""
        print(f"  P={power:2}: peak {r['peak']:4.0f} m, leg {r['time']:4.0f} s "
              f"(+{r['time'] - base['time']:.0f} s){mark}")


if __name__ == "__main__":
    main()
