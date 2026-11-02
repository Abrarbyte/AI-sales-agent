import csv, sys
for name in sys.argv[1:]:
    rows = list(csv.DictReader(open(f"{name}_stats.csv")))
    print(f"--- {name}")
    for r in rows:
        if r["Name"] == "Aggregated" or "all leads" in r["Name"] or r["Name"] in ("sign in", "app: my leads", "app: one lead"):
            print(f"{r['Name'][:44]:44s} n={r['Request Count']:>6s} fail={r['Failure Count']:>4s} median={r['Median Response Time']:>6s} p95={r['95%']:>6s} rps={float(r['Requests/s']):7.2f}")
