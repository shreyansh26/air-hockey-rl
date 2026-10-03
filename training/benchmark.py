import argparse
import json
import os
import platform
import time
import numpy as np
from env import ROOT, make_env

parser = argparse.ArgumentParser()
parser.add_argument("--output", default="validation/throughput.json")
args = parser.parse_args()
results = []
for processes in [1, 2, 4, 8]:
    env = make_env(arenas=16, processes=processes, seed=99101)
    try:
        env.reset()
        actions = np.zeros((env.num_envs, 2), np.float32)
        started = time.perf_counter()
        for _ in range(128):
            env.step(actions)
        seconds = time.perf_counter() - started
        results.append({"processes": processes, "arenas_per_process": 16, "transitions_per_second": 128 * env.num_envs / seconds})
    finally:
        env.close()
report = {"host": platform.platform(), "cpus": os.cpu_count(), "engine_worker_threads": 4, "results": results}
(ROOT / args.output).parent.mkdir(parents=True, exist_ok=True)
(ROOT / args.output).write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
