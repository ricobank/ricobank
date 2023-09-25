# Sometimes forge endlessly runs beyond target depth, seen with logging to file
# For now work around with timeout and repeats, so large runs looking for fail seeds always terminate

import subprocess

timeout    = 60
start_seed = 1
end_seed   = 1000
command = ["forge", "test", "--match-test", "invariant", "--fuzz-seed"]

subprocess.run(["forge", "build"])
for seed in range(start_seed, end_seed):
    output = ''
    expired = failed = False
    print(f"seed {seed}: ", end="")
    try:
        output = subprocess.run(command + [str(seed)], timeout=timeout, capture_output=True)
    except subprocess.TimeoutExpired:
        expired = True
    else:
        failed = "[PASS]" not in output.stdout.decode()

    if failed:
        print()
        print(f"------------------------ seed {seed} failed ------------------------")
        print()

    if expired: print("expired")
    elif not failed: print("pass")
