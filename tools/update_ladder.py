from concurrent.futures import ThreadPoolExecutor, as_completed
import json, time, re, urllib.request, sys, os
from pathlib import Path

BASE_ID = 22
WEEK = 1

SCORES_PAGES = 200
RUNS_TIMED_PAGES = 300
RUNS_ALL_PAGES = 300

WORKERS = 8
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_LUA = Path(os.path.join(SCRIPT_DIR, "..", "Modules", "Database", "Data", "LadderData.lua"))

API_SCORES = f"https://sirus.su/api/base/{BASE_ID}/leaderboard/challenge/scores"
API_RUNS = f"https://sirus.su/api/base/{BASE_ID}/leaderboard/challenge/runs"

MAP_ID_TO_NAME = {
    542: "Кузня Крови",
    543: "Бастионы Адского Пламени",
    547: "Узилище",
    557: "Гробницы Маны",
    574: "Крепость Утгард",
    600: "Крепость Драк'Тарон",
    602: "Чертоги Молний",
    619: "Королевство Ан'кахет",
}

def progress_bar(current, total, label):
    if total == 0:
        return
    pct = current / total
    filled = int(40 * pct)
    bar = "█" * filled + " " * (40 - filled)
    sys.stdout.write(f"\r  {label}: [{bar}] {pct:.0%} ({current}/{total})")
    sys.stdout.flush()

def fetch_json(url):
    req = urllib.request.Request(url, headers={
        "User-Agent": "SMP_LadderUpdater/1.0",
        "Accept": "application/json, text/plain, */*",
    })
    with urllib.request.urlopen(req, timeout=40) as r:
        return json.loads(r.read().decode("utf-8", "replace"))

def rows(payload):
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict):
        for k in ("data", "items", "rows", "results"):
            v = payload.get(k)
            if isinstance(v, list):
                return v
        for k in ("result", "payload"):
            v = payload.get(k)
            if isinstance(v, dict):
                for k2 in ("data", "items", "rows", "results"):
                    vv = v.get(k2)
                    if isinstance(vv, list):
                        return vv
    return []

def pick_name(d):
    for k in ("name", "nickname"):
        v = d.get(k)
        if isinstance(v, str) and v:
            return v
    ch = d.get("character")
    if isinstance(ch, dict):
        v = ch.get("name")
        if isinstance(v, str) and v:
            return v
    return None

def pick_guid(d):
    for k in ("guid", "memberGuid", "characterGuid"):
        v = d.get(k)
        if isinstance(v, (int, float)):
            return int(v)
        if isinstance(v, str) and v.isdigit():
            return int(v)
    return None

def pick_score(d):
    for k in ("current_score", "score", "points", "rating", "rio", "mplus_score"):
        v = d.get(k)
        if isinstance(v, (int, float)):
            return float(v)
        if isinstance(v, str):
            try:
                return float(v.replace(",", "."))
            except:
                pass
    return None

def pick_best_key(d):
    for k in ("best_key", "bestKey", "key_level", "keystone_level", "max_key", "highest_key"):
        v = d.get(k)
        if isinstance(v, (int, float)):
            return int(v)
        if isinstance(v, str) and v.isdigit():
            return int(v)
    for v in d.values():
        if isinstance(v, str):
            m = re.search(r"\+(\d+)", v)
            if m:
                return int(m.group(1))
    return None

def pick_counts(d):
    timed = next((d.get(k) for k in ("timed_runs", "timed", "in_time", "timedCount") if isinstance(d.get(k), (int, float))), None)
    total = next((d.get(k) for k in ("total_runs", "total", "runs", "completed", "count") if isinstance(d.get(k), (int, float))), None)
    return (int(timed) if timed is not None else None, int(total) if total is not None else None)

def extract_members(run):
    for k in ("members", "group", "players", "party"):
        v = run.get(k)
        if isinstance(v, list):
            out = []
            for m in v:
                if isinstance(m, dict):
                    gid = pick_guid(m)
                    nm = pick_name(m) or m.get("name")
                    if gid and isinstance(nm, str) and nm:
                        out.append((gid, nm))
            if out:
                return out
    gid = pick_guid(run)
    nm = pick_name(run) or run.get("name")
    if gid and isinstance(nm, str) and nm:
        return [(gid, nm)]
    return []

def extract_level(run):
    for k in ("challengeLevel", "level", "keyLevel", "key_level", "keystone_level", "mythic_level"):
        v = run.get(k)
        if isinstance(v, (int, float)):
            return int(v)
        if isinstance(v, str) and v.isdigit():
            return int(v)
    return None

def map_name(map_id):
    if map_id is None:
        return None
    try:
        map_id = int(map_id)
    except:
        return None
    return MAP_ID_TO_NAME.get(map_id) or f"mapId:{map_id}"

def lua_dump(db):
    def esc(s):
        return s.replace("\\", "\\\\").replace('"', '\\"')

    out = [
        f"-- Updated: {time.strftime('%Y-%m-%d %H:%M:%S')}",
        f"-- Players: {len(db)}",
        "",
        "local SMPData = SMPLoader:ImportModule(\"SMPData\")",
        "",
        "SMPData:RegisterLadderData({",
    ]

    for name in sorted(db):
        info = db[name]
        p = []

        if info.get("rank") is not None:
            p.append(f'rank={int(info["rank"])}')
        if info.get("score") is not None:
            p.append(f'score={info["score"]}')
        if info.get("bestLevel") is not None:
            p.append(f'bestLevel={int(info["bestLevel"])}')
        if info.get("timed") is not None:
            p.append(f'timed={int(info["timed"])}')
        if info.get("total") is not None:
            p.append(f'total={int(info["total"])}')
        if info.get("bestTimedLevel") is not None:
            p.append(f'bestTimedLevel={int(info["bestTimedLevel"])}')
        if info.get("bestTimedDungeon"):
            p.append(f'bestTimedDungeon="{esc(info["bestTimedDungeon"])}"')
        if info.get("bestOverallLevel") is not None:
            p.append(f'bestOverallLevel={int(info["bestOverallLevel"])}')
        if info.get("bestOverallDungeon"):
            p.append(f'bestOverallDungeon="{esc(info["bestOverallDungeon"])}"')

        out.append(f'  ["{esc(name)}"] = {{ {", ".join(p)} }},')

    out.append("})")
    out.append("")
    return "\n".join(out)

def main():
    t0 = time.time()
    updated_at = int(time.time())
    db = {}
    guid2name = {}

    def fetch_scores(p):
        return p, rows(fetch_json(f"{API_SCORES}?page={p}&week={WEEK}"))

    def fetch_runs_timed(p):
        return rows(fetch_json(f"{API_RUNS}?page={p}&timed=true"))

    def fetch_runs_all(p):
        return rows(fetch_json(f"{API_RUNS}?page={p}"))

    # Step 1: Scores
    print(f"[1/4] Scores")
    completed = 0
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        futs = [ex.submit(fetch_scores, p) for p in range(1, SCORES_PAGES + 1)]
        for fut in as_completed(futs):
            completed += 1
            progress_bar(completed, SCORES_PAGES, "Pages")
            try:
                page, rws = fut.result()
            except Exception:
                continue
            if not rws:
                continue

            page_size = len(rws)
            for i, row in enumerate(rws):
                if not isinstance(row, dict):
                    continue
                name = pick_name(row)
                if not name:
                    continue

                info = db.get(name, {})
                info["rank"] = (page - 1) * page_size + (i + 1)

                gid = pick_guid(row)
                if gid:
                    guid2name[gid] = name

                sc = pick_score(row)
                if sc is not None:
                    info["score"] = sc

                bk = pick_best_key(row)
                if bk is not None:
                    info["bestLevel"] = bk

                t, a = pick_counts(row)
                if t is not None:
                    info["timed"] = t
                if a is not None:
                    info["total"] = a

                db[name] = info

    print(f"\n  Players: {len(db)}")

    # Step 2: Timed runs
    print(f"\n[2/4] Timed runs")
    completed = 0
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        futs = [ex.submit(fetch_runs_timed, p) for p in range(1, RUNS_TIMED_PAGES + 1)]
        for fut in as_completed(futs):
            completed += 1
            progress_bar(completed, RUNS_TIMED_PAGES, "Pages")
            try:
                rws = fut.result()
            except Exception:
                continue
            if not rws:
                continue

            for run in rws:
                if not isinstance(run, dict):
                    continue
                lvl = extract_level(run)
                if lvl is None:
                    continue

                dung = map_name(run.get("mapId"))
                members = extract_members(run)
                if not members:
                    continue

                for gid, nm in members:
                    name = guid2name.get(gid) or nm
                    guid2name[gid] = name
                    info = db.get(name, {})

                    cur = info.get("bestTimedLevel")
                    if cur is None or lvl > int(cur):
                        info["bestTimedLevel"] = lvl
                        if dung:
                            info["bestTimedDungeon"] = dung

                    db[name] = info

    print()

    # Step 3: All runs
    print(f"\n[3/4] All runs")
    completed = 0
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        futs = [ex.submit(fetch_runs_all, p) for p in range(1, RUNS_ALL_PAGES + 1)]
        for fut in as_completed(futs):
            completed += 1
            progress_bar(completed, RUNS_ALL_PAGES, "Pages")
            try:
                rws = fut.result()
            except Exception:
                continue
            if not rws:
                continue

            for run in rws:
                if not isinstance(run, dict):
                    continue
                lvl = extract_level(run)
                if lvl is None:
                    continue

                dung = map_name(run.get("mapId"))
                members = extract_members(run)
                if not members:
                    continue

                for gid, nm in members:
                    name = guid2name.get(gid) or nm
                    guid2name[gid] = name
                    info = db.get(name, {})

                    cur = info.get("bestOverallLevel")
                    if cur is None or lvl > int(cur):
                        info["bestOverallLevel"] = lvl
                        if dung:
                            info["bestOverallDungeon"] = dung

                    db[name] = info

    print()

    # Step 4: Write
    print(f"\n[4/4] Writing")
    OUT_LUA.parent.mkdir(parents=True, exist_ok=True)
    OUT_LUA.write_text(lua_dump(db), encoding="utf-8")
    elapsed = time.time() - t0
    print(f"  Done: {len(db)} players, {elapsed:.1f}s")
    print(f"  Output: {OUT_LUA}")

if __name__ == "__main__":
    main()
