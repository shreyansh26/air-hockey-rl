"""Godot RL Agents transport + the standard SB3 VecEnv boundary.

Only launcher, packet safety, terminal metadata and VecEnv interfaces are adapted.
The learner is stock Stable Baselines3 PPO; the simulation is the shared Arena.
"""
from __future__ import annotations

import atexit
import json
import os
from pathlib import Path
import socket
import subprocess
import time

import numpy as np
from godot_rl.core.godot_env import GodotEnv
from stable_baselines3.common.vec_env import VecEnv, VecExtractDictObs

ROOT = Path(__file__).resolve().parents[1]


class Transport(GodotEnv):
    def __init__(self, arenas=16, seed=1, delay=10, log_dir=None):
        self.arenas, self.seed_value, self.delay = arenas, seed, delay
        self.log_dir = Path(log_dir or ROOT / "training/runs/bridge")
        self.log_dir.mkdir(parents=True, exist_ok=True)
        self.log_file = (self.log_dir / f"godot-{seed}-{time.time_ns()}.log").open("w")
        self.listener = None
        self.connection = None
        self.proc = None
        self.closed = False
        try:
            super().__init__(env_path=None, port=0, convert_action_space=True)
        except BaseException:
            self.close()
            raise

    def _start_server(self):
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen(1)
        self.listener.settimeout(30)
        self.port = self.listener.getsockname()[1]
        default_engine = ROOT / "tools/godot"
        engine = os.environ.get("GODOT", str(default_engine))
        command = [engine, "--headless", "--path", str(ROOT), "--fixed-fps", "120",
                   "res://training/training.tscn", "--", f"--port={self.port}",
                   f"--arenas={self.arenas}", f"--seed={self.seed_value}", f"--delay={self.delay}"]
        self.proc = subprocess.Popen(command, stdout=self.log_file, stderr=subprocess.STDOUT)
        connection, _ = self.listener.accept()
        connection.settimeout(120)
        connection.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self.listener.close()
        self.listener = None
        return connection

    def _get_data(self):
        def receive(length):
            chunks = bytearray()
            while len(chunks) < length:
                chunk = self.connection.recv(length - len(chunks))
                if not chunk:
                    raise ConnectionError("Godot disconnected; inspect its run log")
                chunks.extend(chunk)
            return chunks
        length = int.from_bytes(receive(4), "little")
        if not 0 < length <= 1048576:
            raise ValueError("Godot packet exceeds 1 MiB")
        return receive(length).decode("utf-8")

    def step_recv(self):
        reply = self._get_json_dict()
        if reply.get("type") != "step":
            raise ValueError("Expected a Godot step packet")
        return reply["obs"], reply["reward"], reply["terminated"], reply["truncated"], reply["info"]

    def reset(self, seed=None):
        self._send_as_json({"type": "reset", "seed": seed})
        reply = self._get_json_dict()
        return reply["obs"], reply["info"]

    def command(self, kind, **kwargs):
        self._send_as_json({"type": kind, **kwargs})
        return self._get_json_dict()

    def close(self):
        if self.closed:
            return
        self.closed = True
        if self.connection:
            try:
                self._send_as_json({"type": "close"})
            except (OSError, ValueError):
                pass
            self.connection.close()
        if self.listener:
            self.listener.close()
        if self.proc:
            try:
                self.proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.proc.terminate()
                try:
                    self.proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    self.proc.kill()
                    self.proc.wait()
        self.log_file.close()
        atexit.unregister(self._close)


class HockeyVecEnv(VecEnv):
    def __init__(self, arenas=16, seed=1, delay=10, log_dir=None, processes=1):
        self.clients = []
        try:
            for i in range(processes):
                self.clients.append(Transport(arenas, seed + i * 1000003, delay, log_dir))
        except BaseException:
            self.close()
            raise
        self.client = self.clients[0]
        super().__init__(arenas * processes, self.client.observation_space, self.client.action_space)
        self.render_mode = None
        self.bridge_seconds = 0.0
        self.transitions = 0

    def _observations(self, obs):
        array = np.asarray([item["obs"] for item in obs], dtype=np.float32)
        if array.shape != (self.num_envs, 52) or not np.isfinite(array).all():
            self.close()
            raise ValueError("Godot returned invalid observations")
        return {"obs": array}

    def reset(self):
        obs, self.reset_infos = [], []
        for i, client in enumerate(self.clients):
            observations, infos = client.reset(seed=self._seeds[i * client.num_envs])
            obs.extend(observations)
            self.reset_infos.extend(infos)
        self._reset_seeds()
        self._reset_options()
        return self._observations(obs)

    def step_async(self, actions):
        actions = np.asarray(actions, dtype=np.float32)
        if actions.shape != (self.num_envs, 2) or not np.isfinite(actions).all():
            raise ValueError("Actions must be a finite (N, 2) batch")
        self._sent = time.perf_counter()
        try:
            for i, client in enumerate(self.clients):
                client.step_send(np.clip(actions[i * client.num_envs:(i + 1) * client.num_envs], -1, 1))
        except BaseException:
            self.close()
            raise

    def step_wait(self):
        try:
            batches = [client.step_recv() for client in self.clients]
            obs, rewards, terminated, truncated, infos = [sum((list(batch[i]) for batch in batches), []) for i in range(5)]
        except BaseException:
            self.close()
            raise
        self.bridge_seconds += time.perf_counter() - self._sent
        self.transitions += self.num_envs
        rewards = np.asarray(rewards, dtype=np.float32)
        dones = np.asarray(terminated, dtype=bool) | np.asarray(truncated, dtype=bool)
        if rewards.shape != (self.num_envs,) or dones.shape != (self.num_envs,) or len(infos) != self.num_envs or not np.isfinite(rewards).all():
            self.close()
            raise ValueError("Invalid reward/done/info batch")
        for i, info in enumerate(infos):
            if dones[i]:
                final = np.asarray(info["terminal_observation"], dtype=np.float32)
                if final.shape != (52,) or not np.isfinite(final).all():
                    self.close()
                    raise ValueError("Invalid terminal observation")
                info["terminal_observation"] = {"obs": final}
                info["TimeLimit.truncated"] = bool(truncated[i] and not terminated[i])
                self.reset_infos[i] = info["reset_info"]
        return self._observations(obs), rewards, dones, infos

    def close(self):
        for client in self.clients:
            client.close()

    def get_attr(self, attr_name, indices=None):
        if attr_name == "render_mode":
            return [None for _ in self._get_indices(indices)]
        if not hasattr(self, attr_name):
            raise AttributeError(attr_name)
        return [getattr(self, attr_name) for _ in self._get_indices(indices)]

    def set_attr(self, attr_name, value, indices=None):
        if attr_name not in {"render_mode"}:
            raise AttributeError("Use configure for engine settings")
        setattr(self, attr_name, value)

    def env_method(self, method_name, *args, indices=None, **kwargs):
        if method_name not in {"configure", "inspect"}:
            raise AttributeError(method_name)
        results = [client.command(method_name, **kwargs) for client in self.clients]
        return [results[i // self.client.num_envs] for i in self._get_indices(indices)]

    def env_is_wrapped(self, wrapper_class, indices=None):
        return [False for _ in self._get_indices(indices)]


def make_env(**kwargs):
    # SB3's own wrapper also extracts terminal observations correctly.
    return VecExtractDictObs(HockeyVecEnv(**kwargs), "obs")
