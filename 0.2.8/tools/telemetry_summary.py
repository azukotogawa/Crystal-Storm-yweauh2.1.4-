#!/usr/bin/env python3
import json
import sys
import tempfile
from pathlib import Path


TOP_DAMAGE = 8


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print("usage: telemetry_summary.py <session.json|dir> [more...]")
        print("       telemetry_summary.py --self-test")
        return 0 if len(argv) > 1 else 2
    if argv[1] == "--self-test":
        return self_test()
    paths = collect_paths(argv[1:])
    if not paths:
        print("TELEMETRY SUMMARY FAIL: no session json", file=sys.stderr)
        return 1
    sessions = []
    for path in paths:
        sessions.append(load_session(path))
    print(render(summarize(sessions)), end="")
    return 0


def collect_paths(args):
    found = []
    for raw in args:
        path = Path(raw)
        if path.is_dir():
            found.extend(sorted(path.glob("*.json")))
        elif path.is_file():
            found.append(path)
        else:
            raise SystemExit(f"TELEMETRY SUMMARY FAIL: missing {path}")
    return found


def load_session(path):
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"TELEMETRY SUMMARY FAIL: {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"TELEMETRY SUMMARY FAIL: {path}: not an object")
    return data


def summarize(sessions):
    deaths = 0
    dealt = {}
    taken = {}
    kills = {}
    ttk_total = {}
    gained = 0
    elapsed = 0
    for session in sessions:
        deaths += player_deaths(session)
        add_amounts(dealt, dealt_sources(session))
        add_amounts(taken, taken_sources(session))
        add_ttk(kills, ttk_total, session)
        xp_gained, xp_elapsed = xp_parts(session)
        gained += xp_gained
        elapsed += xp_elapsed
    return {
        "sessions": len(sessions),
        "deaths": deaths,
        "dealt": dealt,
        "taken": taken,
        "kills": kills,
        "ttk_total": ttk_total,
        "gained": gained,
        "elapsed": elapsed,
    }


def player_deaths(session):
    if "player_deaths" in session:
        return int(session["player_deaths"])
    count = 0
    for event in session.get("events") or []:
        if event.get("kind") == "death" and event.get("actor") == "player":
            count += 1
    return count


def dealt_sources(session):
    block = session.get("damage_dealt_by_source")
    if isinstance(block, dict) and block:
        return {str(key): float(value) for key, value in block.items()}
    return amounts_from_events(session, "damage_dealt")


def taken_sources(session):
    return amounts_from_events(session, "damage_taken")


def amounts_from_events(session, kind):
    totals = {}
    for event in session.get("events") or []:
        if event.get("kind") != kind:
            continue
        source = str(event.get("source") or "unknown")
        totals[source] = totals.get(source, 0.0) + float(event.get("amount") or 0.0)
    return totals


def add_amounts(totals, extra):
    for source, amount in extra.items():
        totals[source] = totals.get(source, 0.0) + float(amount)


def add_ttk(kills, ttk_total, session):
    block = session.get("time_to_kill")
    if isinstance(block, dict) and block:
        for kind, row in block.items():
            if not isinstance(row, dict):
                continue
            count = int(row.get("kills") or 0)
            if count <= 0:
                continue
            spent = int(row.get("total_msec") or 0)
            kills[str(kind)] = kills.get(str(kind), 0) + count
            ttk_total[str(kind)] = ttk_total.get(str(kind), 0) + spent
        return
    for event in session.get("events") or []:
        if event.get("kind") != "time_to_kill":
            continue
        kind = str(event.get("actor") or event.get("source") or "unknown")
        kills[kind] = kills.get(kind, 0) + 1
        ttk_total[kind] = ttk_total.get(kind, 0) + int(round(float(event.get("amount") or 0.0) * 1000.0))


def xp_parts(session):
    xp = session.get("xp") if isinstance(session.get("xp"), dict) else {}
    gained = int(xp.get("gained") or 0)
    elapsed = int(xp.get("elapsed_msec") or session.get("elapsed_msec") or 0)
    if gained == 0 and not xp:
        for event in session.get("events") or []:
            if event.get("kind") == "xp":
                gained += int(float(event.get("amount") or 0))
    return max(gained, 0), max(elapsed, 0)


def xp_per_minute(gained, elapsed):
    if gained <= 0 or elapsed <= 0:
        return 0.0
    return float(gained) * 60000.0 / float(elapsed)


def render(summary):
    lines = [
        f"sessions: {summary['sessions']}",
        f"deaths: {summary['deaths']}",
        "top_damage:",
    ]
    lines.extend(ranked_lines(summary["dealt"]))
    lines.append("damage_taken_sources:")
    lines.extend(ranked_lines(summary["taken"]))
    kill_count = sum(summary["kills"].values())
    if kill_count <= 0:
        lines.append("avg_time_to_kill_msec: n/a")
    else:
        spent = sum(summary["ttk_total"].values())
        lines.append(f"avg_time_to_kill_msec: {num(spent / kill_count)}")
    lines.append("time_to_kill:")
    if not summary["kills"]:
        lines.append("  (none)")
    else:
        kinds = sorted(summary["kills"], key=lambda kind: (-summary["kills"][kind], kind))
        for kind in kinds:
            count = summary["kills"][kind]
            mean = summary["ttk_total"][kind] / count
            lines.append(f"  {kind} {num(mean)} msec kills={count}")
    rate = xp_per_minute(summary["gained"], summary["elapsed"])
    lines.append(f"xp_per_minute: {num(rate)}")
    lines.append(f"xp_gained: {summary['gained']}")
    lines.append(f"elapsed_msec: {summary['elapsed']}")
    return "\n".join(lines) + "\n"


def ranked_lines(totals):
    ranked = sorted(totals.items(), key=lambda item: (-item[1], item[0]))
    ranked = [item for item in ranked if item[1] > 0][:TOP_DAMAGE]
    if not ranked:
        return ["  (none)"]
    return [f"  {source} {num(amount)}" for source, amount in ranked]


def num(value):
    number = float(value)
    rounded = round(number, 4)
    if rounded == int(rounded):
        return str(int(rounded))
    text = f"{rounded:.4f}".rstrip("0").rstrip(".")
    return text


def self_test():
    first = {
        "session_id": "demo-a",
        "elapsed_msec": 464,
        "player_deaths": 1,
        "damage_dealt_by_source": {"spear": 2.0, "sword": 10.0},
        "damage_taken": 14.5,
        "time_to_kill": {
            "crystal_mite": {"kills": 1, "total_msec": 120, "mean_msec": 120.0, "min_msec": 120, "max_msec": 120},
            "rabbit": {"kills": 1, "total_msec": 0, "mean_msec": 0.0, "min_msec": 0, "max_msec": 0},
        },
        "xp": {"gained": 30, "elapsed_msec": 464, "per_minute": 3879.31034482759, "level": 2, "level_ups": []},
        "events": [
            {"kind": "damage_taken", "source": "crystal_mite", "actor": "player", "amount": 10.5},
            {"kind": "damage_taken", "source": "unknown", "actor": "player", "amount": 4.0},
            {"kind": "death", "source": "", "actor": "player", "amount": 0.0},
        ],
    }
    second = {
        "session_id": "demo-b",
        "elapsed_msec": 60000,
        "player_deaths": 2,
        "damage_dealt_by_source": {"sword": 5, "bow": 20},
        "time_to_kill": {
            "crystal_mite": {"kills": 3, "total_msec": 900, "mean_msec": 300.0, "min_msec": 200, "max_msec": 400},
        },
        "xp": {"gained": 90, "elapsed_msec": 60000, "per_minute": 90.0, "level": 3, "level_ups": []},
        "events": [
            {"kind": "damage_taken", "source": "crystal_mite", "actor": "player", "amount": 8},
        ],
    }
    with tempfile.TemporaryDirectory(prefix="cs-telemetry-") as folder:
        root = Path(folder)
        (root / "a.json").write_text(json.dumps(first), encoding="utf-8")
        (root / "b.json").write_text(json.dumps(second), encoding="utf-8")
        one = render(summarize([load_session(root / "a.json")]))
        both = render(summarize([load_session(path) for path in sorted(root.glob("*.json"))]))
    expect_line(one, "sessions: 1")
    expect_line(one, "deaths: 1")
    expect_line(one, "  sword 10")
    expect_line(one, "  spear 2")
    expect_line(one, "  crystal_mite 10.5")
    expect_line(one, "  unknown 4")
    expect_line(one, "avg_time_to_kill_msec: 60")
    expect_line(one, "  crystal_mite 120 msec kills=1")
    expect_line(one, "  rabbit 0 msec kills=1")
    expect_line(one, f"xp_per_minute: {num(xp_per_minute(30, 464))}")
    expect_line(one, "xp_gained: 30")
    expect_line(both, "sessions: 2")
    expect_line(both, "deaths: 3")
    expect_line(both, "  bow 20")
    expect_line(both, "  sword 15")
    expect_line(both, "avg_time_to_kill_msec: 204")
    expect_line(both, "  crystal_mite 255 msec kills=4")
    expect_line(both, f"xp_per_minute: {num(xp_per_minute(120, 60464))}")
    expect_line(both, "xp_gained: 120")
    expect_line(both, "elapsed_msec: 60464")
    print("TELEMETRY SUMMARY OK")
    return 0


def expect_line(text, line):
    if line not in text.splitlines():
        raise SystemExit(f"TELEMETRY SUMMARY FAIL: missing {line}\n{text}")


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except BrokenPipeError:
        sys.exit(0)
