# push_swap_tester

Tester for the 42 **push_swap** project (the version with `--simple / --medium / --complex / --adaptive / --bench`). It tests the mandatory part (`push_swap`) and the bonus (`checker`).

> **Disclaimer:** this tester is an unofficial tool, meant only as a reference to help you check your work. Passing every test doesn't guarantee your project is correct or complete, and a failed or warned test isn't necessarily wrong, since some behaviour depends on how you choose to handle it. Always read the subject yourself and use your own judgment.

## Installation

Clone the tester inside your push_swap repository:

```sh
cd push_swap
git clone https://github.com/sisheng1998/push_swap_tester.git
cd push_swap_tester
```

## Usage

| Command  | Runs                         |
| -------- | ---------------------------- |
| `make a` | mandatory + bonus            |
| `make m` | mandatory only (`push_swap`) |
| `make b` | bonus only (`checker`)       |

## Options

Append to any target:

| Variable   | Default | Meaning                               |
| ---------- | ------- | ------------------------------------- |
| `PS_DIR`   | `..`    | push_swap directory                   |
| `RUNS_100` | `5`     | number of random 100-number runs      |
| `RUNS_500` | `3`     | number of random 500-number runs      |
| `TIMEOUT`  | `10`    | seconds before a run counts as a hang |
| `LEAKS`    | `1`     | `0` skips the memory-leak sections    |
| `SEED`     | random  | replays the random inputs of a run    |

Example: `make m RUNS_100=20 RUNS_500=10`

Each run prints its seed in the header and the summary; `make m SEED=<seed>` reruns it with exactly the same random inputs.

## What is tested

**Mandatory**

- Makefile: `NAME`, `all`, `clean`, `fclean`, `re`, `-Wall -Wextra -Werror`, build, clean/fclean/re behaviour, and relinking (warning only)
- Norminette (skipped with a warning if it isn't installed; the tester folder is excluded)
- README.md: present at the repository root (its content is up to you to review)
- Error management: non-numeric input, duplicates, > INT_MAX / < INT_MIN / wrap-around overflow, no parameters. Output must be exactly `Error\n` on stderr, with nothing on stdout
- Strategy selection: every flag on `5 4 3 2 1`, and no flag gives the same output as `--adaptive`
- Identity: sorted inputs print nothing
- 3 numbers: all 6 permutations through every strategy (≤5 ops, ≤3 good; over the limit only warns)
- 5 numbers: all 120 permutations through every strategy, with a few example counts shown (≤15 ops, ≤12 good; over the limit only warns)
- `--bench`: stdout still sorts; stderr shows disorder %, strategy, class, total, and the count per op (if the strategy isn't called "simple", you only get a warning, since the subject doesn't fix the name); disorder is 0.00% / 100.00% / correct for a random list; nothing is printed on stderr without `--bench`
- 100 numbers (<2000 / 1500 / 700) and 500 numbers (<12000 / 8000 / 5500): each random input goes through every strategy, with min/avg/max per strategy
- 50 numbers through every flag, comparing their operation counts
- Robustness: every flag against sizes 1→500, reversed input, low/medium disorder, and INT limits
- Memory leaks: `valgrind` on Linux, `leaks` on macOS

**Bonus (checker)**

- `make bonus`, and relinking (warning only)
- Errors: bad args, duplicates, overflow, no args (must return without reading stdin), unknown instructions, leading/trailing spaces
- KO tests: fixed cases, b not empty, random unsorting instructions
- OK tests: fixed cases, no-ops on an empty b, random lists with valid solutions (up to 500 numbers / ~60k instructions)
- Fuzzing against a reference checker, and memory leaks

Every strategy must sort correctly. For 3 and 5 numbers, going over the operation limit is only a warning, for every strategy: a correct sort passes. For 100 and 500 numbers, the limits apply to the default (`--adaptive`) only; when `--simple`, `--medium` or `--complex` go over a limit, you get a warning instead of a failure (an O(n²) strategy can't stay under 12000 on 500 numbers).

Tests marked `(extra)` cover behaviour the subject leaves open (`""`, `0 -0`, `1 +1`, unknown flags, …). They appear as warnings and don't count toward the result.

Any crash or timeout is counted and reported separately in the summary. When a run fails, its input is saved to `logs/failed_input_*.txt`, and every run writes a full log to `logs/`.

## Notes

- Results are checked with `checker_linux` when it runs on the machine (Linux x86_64). Otherwise the built-in reference checker `tools/ps_tool` is used, so the tester also works on macOS.
- The tester runs `make fclean` / `make re` / `make bonus` inside the push_swap folder.
- Still to check by hand: the README content, the group requirements and explanations of the code.
- **Delete `push_swap_tester/` when you're done.** It isn't part of your submission. Its `tools/*.c` files pass norminette, so a run at the repository root won't fail because of it.
