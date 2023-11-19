# Script to run ricobank invariant tests and log failing seeds to examine. Extra workarounds for forge results:
# Sometimes forge endlessly runs beyond target depth, seen with logging to file -> Use a timeout and run many seeds.
# Forge can report overall PASS even when invariants fail -> use -vv and search output for errors
# When fail_on_revert = true in foundry.toml, and handler reverts, test result is PASS -> Fail if calls < depth

from enum import auto, Enum
import argparse
import os
import re
import subprocess
import toml


timeout = 60
start_seed = 700
end_seed = 710


class TestMode(Enum):
    INVARIANTS = auto()  # params can be anything, look for any way to get into bad state
    REVERTS = auto()     # limit fuzz to conditions which should not revert, and look for reverts


def run_forge(mode):
    script_dir = os.path.dirname(os.path.abspath(__file__))
    toml_path = os.path.join(script_dir, '..', '..', 'foundry.toml')
    depth = toml.load(toml_path)["invariant"]["depth"]
    env = {**os.environ}

    subprocess.run(["forge", "build"])
    command = ["forge", "test", "--match-test", "test_name", "-vv", "--fuzz-seed"]

    match mode:
        case TestMode.INVARIANTS:
            command[3] = 'invariant_core'
        case TestMode.REVERTS:
            command[3] = 'invariant_revert_search'
            env.update({"FOUNDRY_PROFILE": "disallow_reverts"})
        case _:
            raise ValueError(f"Unimplemented test mode: {mode}")

    for seed in range(start_seed, end_seed):
        output = ''
        expired = failed = False
        print(f"seed {seed}: ", end="")
        try:
            output = subprocess.run(command + [str(seed)], env=env, timeout=timeout, capture_output=True, text=True).stdout
        except subprocess.TimeoutExpired:
            expired = True
        else:
            # clear colour instructions for terminal output
            output = re.sub(r'\x1b\[[0-9;]*m', '', output)
            match = re.search('calls: (\d+)', output)
            calls = int(match.group(1))
            failed = (calls != depth or any(err_str in output for err_str in ("FAIL", "Error: ")))

        if failed:
            print("failed")
            print(output)
            break

        if expired:
            print("expired")
        elif not failed:
            print("passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run invariant tests in various modes.")
    parser.add_argument("mode", type=str, choices=[mode.name for mode in TestMode])
    args = parser.parse_args()

    try:
        mode = TestMode[args.mode]
        print(f"Running tests in mode {mode}")
        run_forge(mode)
    except KeyError:
        print(f"Specify a test mode from {[mode.name for mode in TestMode]}")
