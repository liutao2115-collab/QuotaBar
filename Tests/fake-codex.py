#!/usr/bin/python3
"""Local protocol fixture. Never connects to a network or reads authentication."""
import json
import pathlib
import sys

state = next(json.loads(arg.split("=", 1)[1]) for arg in sys.argv if arg.startswith("sqlite_home="))
directory = pathlib.Path(state)
mode = directory.name
for line in sys.stdin:
    request = json.loads(line)
    if request.get("method") == "initialize":
        response = {"id": request["id"], "result": {"userAgent": "test"}}
    elif request.get("method") == "account/rateLimits/read":
        if mode == "timeout":
            continue
        if mode == "authentication":
            response = {"id": request["id"], "error": {"code": -32000, "message": "Login required"}}
        else:
            counter = directory / "calls"
            counter.write_text(str(int(counter.read_text()) + 1 if counter.exists() else 1))
            response = {"id": request["id"], "result": {"rateLimitsByLimitId": {
                "codex": {"primary": {"usedPercent": 4, "windowDurationMins": 300, "resetsAt": 4102444800},
                          "secondary": {"usedPercent": 14, "windowDurationMins": 10080, "resetsAt": 4103049600}},
                "codex_other": {"primary": {"usedPercent": 99, "windowDurationMins": 300, "resetsAt": 4102444800}}
            }}}
    else:
        continue
    print(json.dumps(response), flush=True)
