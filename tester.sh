#!/usr/bin/env bash
# push_swap_tester - tests push_swap (mandatory) and checker (bonus).
# Usage: ./tester.sh [all|mandatory|bonus]   (normally via `make a|m|b`)

set -f
MODE="${1:-all}"
TESTER_DIR="$(cd "$(dirname "$0")" && pwd)"
PS_DIR="$(cd "${PS_DIR:-$TESTER_DIR/..}" 2>/dev/null && pwd)" \
	|| { echo "push_swap directory not found (PS_DIR=${PS_DIR})"; exit 2; }
PS="$PS_DIR/push_swap"
CK="$PS_DIR/checker"
TOOL="$TESTER_DIR/tools/ps_tool"
RUNS_100="${RUNS_100:-5}"
RUNS_500="${RUNS_500:-3}"
TIMEOUT="${TIMEOUT:-10}"
LEAKS="${LEAKS:-1}"
# One seed drives every random input (ps_tool and $RANDOM): rerun with SEED=... to replay.
SEED="${SEED:-$(( (RANDOM << 15 | RANDOM) % 1000000000 ))}"
case "$SEED" in '' | *[!0-9]*) echo "SEED must be a non-negative integer (got '$SEED')"; exit 2 ;; esac
SEED=$((10#$SEED % 1000000000))
RANDOM=$SEED
# Op limits apply to the default (--adaptive); the others must sort, limits only warn.
STRATS=(--adaptive --simple --medium --complex)

TMP="$(mktemp -d "${TMPDIR:-/tmp}/ps_tester.XXXXXX")"
# Always leave the push_swap repo without object files (also on Ctrl-C / early exit).
cleanup() {
	[ -f "$PS_DIR/Makefile" ] && make -C "$PS_DIR" clean >/dev/null 2>&1
	rm -rf "$TMP"
}
trap cleanup EXIT
echo 0 >"$TMP/seed_n"
mkdir -p "$TESTER_DIR/logs"
LOG="$TESTER_DIR/logs/$(date +%Y%m%d_%H%M%S)_$MODE.log"
: >"$LOG"

if [ -t 1 ]; then
	R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; C=$'\033[36m'
	B=$'\033[1m'; D=$'\033[2m'; N=$'\033[0m'
else
	R=; G=; Y=; C=; B=; D=; N=
fi

FAILS=0; WARNS=0; CRASHES=0; XTRA=
SUM_NAME=(); SUM_RES=()

# ---------------------------------------------------------------- helpers

log() { printf '%s\n' "$*" >>"$LOG"; }

# tool gen|mix|randops ...   -> ps_tool with SEED + call number, so every call differs
# but the whole run is reproducible (counter is a file: calls often run in $(...) subshells;
# sec_begin moves it to the section's own offset).
tool() {
	local n
	read -r n <"$TMP/seed_n"
	echo $((n + 1)) >"$TMP/seed_n"
	SEED=$((SEED + n)) "$TOOL" "$@"
}

# A program stuck in an output loop can write ~1 GB in 10 s: cap every file written (SIGXFSZ).
OUT_MB=100
ulimit -f $((OUT_MB * 1024)) 2>/dev/null
SIGXFSZ=$(kill -l XFSZ 2>/dev/null)

# run STDIN OUT ERR cmd...   -> RC (the program's own exit code) and RK, how it ended:
# exit | timeout | noexec | "signal N". RK comes from a status file, so a program that
# exits with 124 / 127 / 255 (exit(-1)) is never mistaken for a timeout or a crash.
# The child gets its own process group so a timeout / Ctrl-C also kills what it spawned (make -> cc).
PERL_TO='my $t=shift; my $f=shift;
sub st { open(my $h, ">", $f) or return; print $h $_[0]; close $h }
my $p=fork(); die "fork" unless defined $p;
if(!$p){ setpgrp(0,0); exec {$ARGV[0]} @ARGV; st("noexec"); exit 127 }
setpgrp($p,$p);
$SIG{INT}=$SIG{TERM}=sub{ kill 9,-$p; waitpid($p,0); st("interrupted"); exit 130 };
$SIG{ALRM}=sub{ kill 9,-$p; waitpid($p,0); st("timeout"); exit 124 }; alarm $t;
waitpid($p,0); my $s=$?;
if($s & 127){ st("signal ".($s & 127)); exit(128+($s & 127)) }
exit($s >> 8);'
run() {
	local in="$1" out="$2" err="$3"
	shift 3
	: >"$TMP/st"
	if [ "$in" = - ]; then
		perl -e "$PERL_TO" "$TIMEOUT" "$TMP/st" "$@" >"$out" 2>"$err"
	else
		perl -e "$PERL_TO" "$TIMEOUT" "$TMP/st" "$@" <"$in" >"$out" 2>"$err"
	fi
	RC=$?
	RK=
	read -r RK <"$TMP/st"
	[ -n "$RK" ] || RK=exit
}

# True when the last run timed out or hit the output cap: both cost a full timeout / disk,
# so loops stop retrying that program instead of waiting on every remaining input.
hung() { [ "$RK" = timeout ] || [ "$RK" = "signal $SIGXFSZ" ]; }

# Sets PROB and returns 1 when the last run crashed / timed out.
check_rc() {
	local sig
	PROB=
	case "$RK" in
		timeout) PROB="TIMEOUT: no answer after ${TIMEOUT}s (infinite loop or waiting on input?)" ;;
		noexec) PROB="could not execute the program (missing, not executable, or exec failed)" ;;
		interrupted) PROB="interrupted" ;;
		signal\ *)
			sig=$(kill -l "${RK#signal }" 2>/dev/null)
			if [ "$sig" = XFSZ ]; then PROB="OUTPUT TOO LARGE: stopped after ${OUT_MB} MB of output (endless output loop?)"
			else PROB="CRASH: killed by signal SIG${sig:-${RK#signal }} (segfault / abort?)"; fi
			;;
	esac
	if [ -n "$PROB" ]; then
		CRASHES=$((CRASHES + 1))
		return 1
	fi
	return 0
}

short() {
	if [ -s "$1" ]; then head -c 120 "$1" | tr '\n' '|'; else printf '(nothing)'; fi
}

# Each section draws its random inputs from its own offset of SEED (from its name), so a
# section gets the same inputs whatever ran before it (make a / m / b, LEAKS=0, ...).
sec_begin() {
	local base
	SEC="$1"; NEED="$2"; SP=0; ST=0; SEC_SKIP=; HUNG=
	base=$(printf '%s' "$1" | cksum | cut -d' ' -f1)
	base=$(( base % 100000 * 1000 ))
	echo "$base" >"$TMP/seed_n"
	RANDOM=$((SEED + base))
	printf '\n%s▸ %s%s\n' "$B" "$1" "$N"
	[ -n "$3" ] && printf '  %s%s%s\n' "$D" "$3" "$N"
	log "" "=== $1"
}

ok() {
	if [ -n "$XTRA" ]; then
		printf '  %s✔%s %s %s(extra)%s\n' "$G" "$N" "$1" "$D" "$N"
		return
	fi
	SP=$((SP + 1)); ST=$((ST + 1))
	printf '  %s✔%s %s\n' "$G" "$N" "$1"
}

ko() {
	if [ -n "$XTRA" ]; then
		wn "$1 (extra)" "$2"
		return
	fi
	ST=$((ST + 1)); FAILS=$((FAILS + 1))
	printf '  %s✘ %s%s\n' "$R" "$1" "$N"
	[ -n "$2" ] && printf '      %s%s%s\n' "$D" "$2" "$N"
	log "FAIL: $1" "      $2"
}

wn() {
	WARNS=$((WARNS + 1))
	printf '  %s! %s%s\n' "$Y" "$1" "$N"
	[ -n "$2" ] && printf '      %s%s%s\n' "$D" "$2" "$N"
	log "WARN: $1" "      $2"
}

info() { printf '  %sℹ %s%s\n' "$C" "$1" "$N"; }

sec_end() {
	local need="$NEED" res
	[ "$need" = all ] && need=$ST
	if [ -n "$SEC_SKIP" ]; then
		res="${Y}SKIPPED${N} ($SEC_SKIP)"
	elif [ "$ST" -eq 0 ]; then
		res="${Y}SKIPPED${N}"
	elif [ "$SP" -ge "$need" ]; then
		res="${G}PASS${N} ($SP/$ST)"
	else
		res="${R}FAIL${N} ($SP/$ST, need $need)"
	fi
	printf '  %s→%s %b\n' "$B" "$N" "$res"
	SUM_NAME+=("$SEC"); SUM_RES+=("$res")
}

# expect_error LABEL STDIN_FILE cmd...   ("Error\n" on stderr, nothing on stdout)
expect_error() {
	local label="$1" in="$2"
	shift 2
	run "$in" "$TMP/o" "$TMP/e" "$@"
	if ! check_rc; then
		ko "$label" "$PROB"
	elif [ -s "$TMP/o" ]; then
		ko "$label" "expected nothing on stdout (error case), but the program printed: $(short "$TMP/o")"
	elif ! printf 'Error\n' | cmp -s - "$TMP/e"; then
		ko "$label" "expected exactly \"Error\\n\" on stderr, got: $(short "$TMP/e") (exit code $RC)"
	else
		ok "$label"
	fi
}

# expect_nothing LABEL STDIN_FILE cmd...   (no output at all)
expect_nothing() {
	local label="$1" in="$2"
	shift 2
	run "$in" "$TMP/o" "$TMP/e" "$@"
	if ! check_rc; then
		ko "$label" "$PROB"
	elif [ -s "$TMP/o" ] || [ -s "$TMP/e" ]; then
		ko "$label" "expected no output at all, got stdout: $(short "$TMP/o") / stderr: $(short "$TMP/e")"
	else
		ok "$label"
	fi
}

# Reference checker: checker_linux when it runs here, ps_tool otherwise.
REF_NAME="built-in reference checker (tools/ps_tool)"
REF=("$TOOL" check)
pick_ref() {
	local cl="$TESTER_DIR/checker_linux"
	chmod +x "$cl" 2>/dev/null
	if [ "$(printf 'sa\n' | "$cl" 2 1 2>/dev/null)" = OK ]; then
		REF=("$cl"); REF_NAME="checker_linux"
	fi
}

# verify "FLAGS" "NUMBERS"   -> V_RES (OK/KO/...) and V_OPS; returns 0 if OK
verify() {
	local flags="$1" nums="$2"
	V_OPS=0
	case "$HUNG" in *"|$flags|"*)
		V_RES="skipped: push_swap $flags already timed out in this section"
		return 1 ;;
	esac
	run /dev/null "$TMP/o" "$TMP/e" "$PS" $flags $nums
	if ! check_rc; then
		V_RES="$PROB"
		hung && HUNG="$HUNG|$flags|"
		return 1
	fi
	V_OPS=$(wc -l <"$TMP/o" | tr -d ' ')
	if [ -s "$TMP/e" ] && [[ "$flags" != *--bench* ]]; then
		V_RES="unexpected stderr: $(short "$TMP/e")"
		return 1
	fi
	V_RES=$("${REF[@]}" $nums <"$TMP/o" 2>&1)
	case "$V_RES" in
		OK) ;;
		KO) V_RES="checker says KO: the operations printed do not leave stack a sorted (and b empty)" ;;
		Error) V_RES="checker says Error: push_swap printed something that is not a valid operation" ;;
		*) V_RES="checker gave an unexpected answer: \"${V_RES:-nothing}\"" ;;
	esac
	[ "$V_RES" = OK ]
}

save_input() {
	local f="$TESTER_DIR/logs/failed_input_$(date +%H%M%S)_$RANDOM.txt"
	printf '%s\n' "$1" >"$f"
	printf 'input saved to %s' "${f#$TESTER_DIR/}"
}

rating() { # ops pass good excellent
	if [ "$1" -lt "$4" ]; then printf 'excellent'
	elif [ "$1" -lt "$3" ]; then printf 'good'
	elif [ "$1" -lt "$2" ]; then printf 'pass'
	else printf 'FAIL'; fi
}

# make_fail BINARY -> explains why the last `mk` did not produce BINARY (full output saved to logs/)
make_fail() {
	local bin="$1" f errs why
	f="$TESTER_DIR/logs/make_failed_$(date +%H%M%S)_$RANDOM.txt"
	{ echo "== make stdout"; cat "$TMP/mo"; echo "== make stderr"; cat "$TMP/me"; } >"$f"
	errs=$(cat "$TMP/mo" "$TMP/me" | grep -Ei 'error|\*\*\*|undefined|not found|no rule|cannot' | head -4 | cut -c1-160 | tr '\n' '|')
	if [ "$RK" = timeout ]; then why="make timed out after ${TIMEOUT}s"
	elif [ "$RC" -ne 0 ]; then why="make failed (exit code $RC)"
	else why="make succeeded but ./$bin was not created (does NAME match '$bin'?)"; fi
	[ -z "$errs" ] && errs="$(tail -c 200 "$TMP/me" | tr '\n' '|')"
	printf '%s. First errors: %s full output: %s' "$why" "${errs:-(no output)}" "${f#$TESTER_DIR/}"
}

mk() { # make TARGET... in PS_DIR (output in $TMP/mo, $TMP/me)
	local TIMEOUT=300
	run /dev/null "$TMP/mo" "$TMP/me" make -C "$PS_DIR" "$@"
}

newer_than_stamp() { [ -n "$(find "$1" -newer "$TMP/stamp" 2>/dev/null)" ]; }

leak_tool() {
	[ "$LEAKS" = 0 ] && return 1
	if command -v valgrind >/dev/null 2>&1; then LEAK_TOOL=valgrind
	elif [ "$(uname -s)" = Darwin ] && command -v leaks >/dev/null 2>&1; then LEAK_TOOL=leaks
	else return 1; fi
}

# leak_case LABEL STDIN cmd...
leak_case() {
	local label="$1" in="$2" TIMEOUT=120
	shift 2
	if [ "$LEAK_TOOL" = valgrind ]; then
		run "$in" "$TMP/o" "$TMP/e" valgrind --leak-check=full \
			--show-leak-kinds=all --errors-for-leak-kinds=definite,indirect,possible \
			--error-exitcode=42 "$@"
		if [ "$RC" -eq 42 ]; then
			ko "$label" "$(grep -E 'lost:|Invalid|uninitialised' "$TMP/e" | head -3 | tr -s ' ' | tr '\n' '|')"
		elif ! check_rc; then
			ko "$label" "$PROB"
		elif grep -Eq 'still reachable: [1-9]' "$TMP/e"; then
			wn "$label: still reachable memory at exit" "$(grep 'still reachable' "$TMP/e" | head -1)"
		else
			ok "$label"
		fi
	else
		# leaks -atExit exits 0 even when the program crashes: run it alone first.
		run "$in" "$TMP/o" "$TMP/e" "$@"
		if ! check_rc; then
			ko "$label" "$PROB"
			return
		fi
		MallocStackLogging=0 run "$in" "$TMP/o" "$TMP/e" leaks -quiet -atExit -- "$@"
		if grep -Eq '[1-9][0-9]* leaks? for' "$TMP/o"; then
			ko "$label" "$(grep -E 'leaks? for' "$TMP/o" | head -1)"
		elif ! check_rc; then
			ko "$label" "$PROB"
		elif ! grep -Eq 'leaks? for' "$TMP/o"; then
			wn "$label: leaks could not analyse the program - check manually" "$(short "$TMP/e")"
		else
			ok "$label"
		fi
	fi
}

# ---------------------------------------------------------------- mandatory

m_build() {
	sec_begin "Makefile & compilation" all
	local mf="$PS_DIR/Makefile" r
	if [ ! -f "$mf" ]; then
		ko "Makefile present" "no Makefile found in $PS_DIR"
		sec_end; return 1
	fi
	ok "Makefile present"
	if grep -Eq '^[[:space:]]*NAME[[:space:]]*[:+?]?=' "$mf"; then ok "NAME variable"; else ko "NAME variable" "no 'NAME =' line found in Makefile"; fi
	for r in all clean fclean re; do
		if grep -Eq "^([^#:=]*[[:space:]])?$r([[:space:]][^:=]*)?:([^=]|$)" "$mf"; then
			ok "rule '$r'"
		else
			ko "rule '$r'" "no '$r:' target found in Makefile"
		fi
	done
	if grep -q -- -Wall "$mf" && grep -q -- -Wextra "$mf" && grep -q -- -Werror "$mf"; then
		ok "flags -Wall -Wextra -Werror"
	else
		ko "flags -Wall -Wextra -Werror" "missing in Makefile:$(for fl in -Wall -Wextra -Werror; do grep -q -- $fl "$mf" || printf ' %s' $fl; done)"
	fi
	mk fclean
	mk
	if [ "$RC" -ne 0 ] || [ ! -x "$PS" ]; then
		ko "make builds ./push_swap" "$(make_fail push_swap)"
		sec_end; return 1
	fi
	ok "make builds ./push_swap"
	touch "$TMP/stamp"; sleep 1
	mk
	XTRA=1
	if newer_than_stamp "$PS"; then ko "no relink on second make" "push_swap was rebuilt"
	else ok "no relink on second make"; fi
	XTRA=
	mk clean
	if [ -n "$(find "$PS_DIR" -path "$TESTER_DIR" -prune -o -name '*.o' -print | head -1)" ]; then
		ko "make clean removes object files" "object file left after 'make clean': $(find "$PS_DIR" -path "$TESTER_DIR" -prune -o -name '*.o' -print | head -1)"
	elif [ ! -x "$PS" ]; then
		ko "make clean keeps ./push_swap" "./push_swap was deleted by 'make clean' (only 'fclean' may remove it)"
	else
		ok "make clean"
	fi
	mk fclean
	if [ -e "$PS" ]; then ko "make fclean removes ./push_swap" "./push_swap still exists after 'make fclean'"; else ok "make fclean"; fi
	mk re
	if [ "$RC" -eq 0 ] && [ -x "$PS" ]; then ok "make re"
	else ko "make re" "exit code $RC, ./push_swap $([ -x "$PS" ] && echo present || echo missing); $(tail -c 200 "$TMP/me" | tr '\n' '|')"; fi
	[ -x "$PS" ] || mk
	sec_end
	[ -x "$PS" ]
}

m_norm() {
	sec_begin "Norminette" all
	if ! command -v norminette >/dev/null 2>&1; then
		SEC_SKIP="norminette not installed"
		wn "norminette not installed - run it manually"
		sec_end; return
	fi
	local files=() f TIMEOUT=300
	while IFS= read -r f; do files+=("$f"); done < <(find "$PS_DIR" \
		\( -path "$TESTER_DIR" -o -path "$PS_DIR/.git" \) -prune -o \
		-type f \( -name '*.c' -o -name '*.h' \) -print)
	# norminette with no arguments would check the current directory (the tester itself)
	if [ ${#files[@]} -eq 0 ]; then
		SEC_SKIP="no .c / .h files found"
		wn "norminette: no .c / .h files found in $PS_DIR"
		sec_end; return
	fi
	run /dev/null "$TMP/o" "$TMP/e" norminette "${files[@]}"
	if ! check_rc; then
		ko "norminette" "$PROB"
	elif grep -Eq ': Error!|^Error: ' "$TMP/o" "$TMP/e"; then
		ko "norminette" "$(grep -c ': Error!' "$TMP/o") file(s) with errors: $(grep ': Error!' "$TMP/o" | head -3 | tr '\n' ' ')"
	elif [ "$RC" -ne 0 ]; then
		ko "norminette" "norminette exited with code $RC: $(short "$TMP/e")"
	else
		ok "norminette (${#files[@]} files)"
	fi
	sec_end
}

m_readme() {
	sec_begin "README.md" all
	if [ -f "$PS_DIR/README.md" ]; then ok "README.md at repository root"
	else ko "README.md at repository root" "no README.md in $PS_DIR (name is case-sensitive)"; fi
	info "content (first line, sections, algorithms, contributions) must be judged by you"
	sec_end
}

m_errors() {
	sec_begin "Error management" all
	expect_error "non numeric: push_swap 1 a 3" /dev/null "$PS" 1 a 3
	expect_error "non numeric: push_swap abc" /dev/null "$PS" abc
	expect_error "non numeric: push_swap 1 2 3x" /dev/null "$PS" 1 2 3x
	expect_error "non numeric: push_swap 1 - 2" /dev/null "$PS" 1 - 2
	expect_error "non numeric: push_swap 1 + 2" /dev/null "$PS" 1 + 2
	expect_error "non numeric: push_swap 1 --2 3" /dev/null "$PS" 1 --2 3
	expect_error "non numeric: push_swap --adaptive 0 one 2 3" /dev/null "$PS" --adaptive 0 one 2 3
	expect_error "duplicate: push_swap 1 2 1" /dev/null "$PS" 1 2 1
	expect_error "duplicate: push_swap --simple 3 2 3" /dev/null "$PS" --simple 3 2 3
	expect_error "duplicate: push_swap 5 -3 8 -3" /dev/null "$PS" 5 -3 8 -3
	expect_error "> MAXINT: push_swap 2147483648" /dev/null "$PS" 2147483648
	expect_error "> MAXINT: push_swap 1 2 2147483648" /dev/null "$PS" 1 2 2147483648
	expect_error "< MININT: push_swap 1 -2147483649" /dev/null "$PS" 1 -2147483649
	expect_error "overflow wrap: push_swap 1 4294967296" /dev/null "$PS" 1 4294967296
	expect_error "huge: push_swap 99999999999999999999 1" /dev/null "$PS" 99999999999999999999 1
	expect_nothing "no parameters: push_swap" /dev/null "$PS"
	XTRA=1
	expect_error "empty argument: push_swap \"\"" /dev/null "$PS" ""
	expect_error "empty argument: push_swap 1 \"\" 2" /dev/null "$PS" 1 "" 2
	expect_error "duplicate 0 / -0: push_swap 0 -0" /dev/null "$PS" 0 -0
	expect_error "duplicate 1 / +1: push_swap 1 +1" /dev/null "$PS" 1 +1
	expect_error "unknown flag: push_swap --foo 2 1" /dev/null "$PS" --foo 2 1
	XTRA=
	info "extras are subject-ambiguous: shown as warnings, not counted"
	sec_end
}

m_flags_basic() {
	sec_begin "Strategy selection - basic" all
	local f nums same=1 prob=
	for f in --simple --medium --complex --adaptive; do
		if verify "$f" "5 4 3 2 1"; then ok "push_swap $f 5 4 3 2 1 → OK ($V_OPS ops)"
		else ko "push_swap $f 5 4 3 2 1" "$V_RES"; fi
	done
	for nums in "5 4 3 2 1" "$(tool gen 20 -100 100)" "$(tool gen 100)" "$(tool mix 100 10)"; do
		# a crash / timeout leaves both outputs empty, which would compare as "same"
		run /dev/null "$TMP/def" "$TMP/e" "$PS" $nums
		check_rc || { prob="without flag: $PROB - $(save_input "$nums")"; break; }
		run /dev/null "$TMP/ada" "$TMP/e" "$PS" --adaptive $nums
		check_rc || { prob="with --adaptive: $PROB - $(save_input "$nums")"; break; }
		cmp -s "$TMP/def" "$TMP/ada" || { same=0; log "default != --adaptive for: $nums"; }
	done
	if [ -n "$prob" ]; then ko "no flag produces the same output as --adaptive" "$prob"
	elif [ $same = 1 ]; then ok "no flag produces the same output as --adaptive (4 inputs)"
	else ko "no flag produces the same output as --adaptive" "default and --adaptive printed different operations; $(grep -m1 'default != --adaptive' "$LOG" | cut -c1-100)"; fi
	sec_end
}

m_identity() {
	sec_begin "Identity test - already sorted" all
	local nums f
	for nums in "42" "2 3" "0 1 2 3" "0 1 2 3 4 5 6 7 8 9"; do
		expect_nothing "push_swap $nums" /dev/null "$PS" $nums
	done
	XTRA=1
	for f in --simple --medium --complex --adaptive; do
		expect_nothing "push_swap $f -5 0 7 42" /dev/null "$PS" $f -5 0 7 42
	done
	expect_nothing "push_swap -2147483648 0 2147483647" /dev/null "$PS" -2147483648 0 2147483647
	XTRA=
	sec_end
}

# strat_result STRATEGY DESC BAD MAX LIMIT GOOD
# Small inputs (3 / 5 numbers): must sort; going over LIMIT only warns, for every strategy.
strat_result() {
	local f="$1" desc="$2" bad="$3" max="$4" limit="$5" good="$6" q=acceptable
	[ "$max" -le "$good" ] && q=good
	if [ -n "$bad" ]; then
		ko "$f: $desc" "not sorted:$bad"
	elif [ "$max" -le "$limit" ]; then
		ok "$f: $desc, max $max ops ($q)"
	else
		ok "$f: $desc"
		wn "$f: max $max ops is above $limit (small inputs only need to sort; limit is a warning)"
	fi
}

m_small() {
	sec_begin "Small inputs (3 numbers)" all "all 6 permutations × every strategy; ≤3 good, ≤5 acceptable"
	local f nums max bad line
	for f in "${STRATS[@]}"; do
		max=0; bad=; line=
		for nums in "2 1 0" "0 2 1" "1 0 2" "1 2 0" "2 0 1" "0 1 2"; do
			if verify "$f" "$nums"; then
				line="$line $V_OPS"
				[ "$V_OPS" -gt $max ] && max=$V_OPS
			else
				line="$line ✘"; bad="$bad [$nums] $V_RES"
			fi
		done
		strat_result "$f" "ops per permutation:$line" "$bad" $max 5 3
	done
	sec_end
}

m_medium5() {
	sec_begin "Medium inputs (5 numbers)" all "all 120 permutations × every strategy; ≤12 good, ≤15 acceptable"
	local perms=() p a b c d e f max bad over12 ex
	for a in 1 2 3 4 5; do for b in 1 2 3 4 5; do [ $b = $a ] && continue
	for c in 1 2 3 4 5; do case " $a $b " in *" $c "*) continue ;; esac
	for d in 1 2 3 4 5; do case " $a $b $c " in *" $d "*) continue ;; esac
	for e in 1 2 3 4 5; do case " $a $b $c $d " in *" $e "*) continue ;; esac
		perms+=("$a $b $c $d $e")
	done; done; done; done; done
	for f in "${STRATS[@]}"; do
		max=0; bad=; over12=0; ex=
		for p in "${perms[@]}"; do
			if ! verify "$f" "$p"; then
				bad="$bad [$p: ${V_RES:0:60}]"; log "5-perm $f $p -> $V_RES"
				continue
			fi
			[ "$V_OPS" -gt $max ] && max=$V_OPS
			[ "$V_OPS" -gt 12 ] && over12=$((over12 + 1))
			case "$p" in "1 5 2 4 3" | "5 1 4 2 3" | "3 5 1 4 2") ex="$ex ${p// /}→$V_OPS" ;; esac
		done
		[ ${#bad} -gt 100 ] && bad="${bad:0:97}..."
		strat_result "$f" "${#perms[@]} permutations, examples:$ex" "$bad" $max 15 12
		[ $over12 -gt 0 ] && [ -z "$bad" ] && info "$f: $over12 permutation(s) need more than 12 ops"
	done
	sec_end
}

m_bench() {
	sec_begin "Benchmark mode & disorder" all
	local missing op exp lo hi nums f re
	if verify "--bench --simple" "5 4 3 2 1"; then ok "--bench --simple 5 4 3 2 1: stdout sorts ($V_OPS ops)"
	else ko "--bench --simple 5 4 3 2 1: stdout sorts" "$V_RES"; fi
	cp "$TMP/e" "$TMP/bench"
	if [ ! -s "$TMP/bench" ]; then
		ko "benchmark printed on stderr" "--bench printed nothing on stderr (stats go to stderr, operations to stdout)"
	else
		ok "benchmark printed on stderr"
		grep -q '%' "$TMP/bench" && ok "disorder shown as %" || ko "disorder shown as %" "no '%' found in the benchmark; got: $(short "$TMP/bench")"
		grep -Eiq 'simple' "$TMP/bench" && ok "strategy name" \
			|| wn "strategy name: 'simple' not found (fine if the algorithm name is shown instead)"
		grep -Eiq 'O\(' "$TMP/bench" && ok "complexity class" || ko "complexity class (O(...))" "no 'O(' found in the benchmark; got: $(short "$TMP/bench")"
		grep -Eq "(^|[^0-9])$V_OPS([^0-9]|$)" "$TMP/bench" && ok "total operations ($V_OPS)" \
			|| ko "total operations ($V_OPS) shown" "stdout has $V_OPS operations but that number is not in the benchmark; got: $(short "$TMP/bench")"
		missing=
		for op in sa sb ss pa pb ra rb rr rra rrb rrr; do
			grep -Eiq "(^|[^a-z])$op([^a-z]|$)" "$TMP/bench" || missing="$missing $op"
		done
		[ -z "$missing" ] && ok "count for each operation type" || ko "count for each operation type" "missing:$missing"
	fi
	run /dev/null "$TMP/o" "$TMP/e" "$PS" --bench 1 2 3 4 5
	if grep -Eq '(^|[^0-9.])0[.,]00' "$TMP/e"; then ok "disorder of 1 2 3 4 5 = 0.00%"
	else ko "disorder of 1 2 3 4 5 = 0.00%" "expected 0.00% (sorted input), stderr was: $(short "$TMP/e")"; fi
	run /dev/null "$TMP/o" "$TMP/e" "$PS" --bench 5 4 3 2 1
	if grep -Eq '100[.,]00' "$TMP/e"; then ok "disorder of 5 4 3 2 1 = 100.00%"
	else ko "disorder of 5 4 3 2 1 = 100.00%" "expected 100.00% (reversed input), stderr was: $(short "$TMP/e")"; fi
	nums=$(tool gen 40 -500 500)
	exp=$("$TOOL" disorder $nums)
	lo=$(awk -v x="$exp" 'BEGIN{printf "%.2f", x-0.01}')
	hi=$(awk -v x="$exp" 'BEGIN{printf "%.2f", x+0.01}')
	run /dev/null "$TMP/o" "$TMP/e" "$PS" --bench $nums
	if grep -Eq "(^|[^0-9])(${exp//./[.,]}|${lo//./[.,]}|${hi//./[.,]})" "$TMP/e"; then
		ok "disorder of random 40 numbers = $exp%"
	else
		ko "disorder of random 40 numbers = $exp%" "expected $exp% (input: $nums), stderr was: $(short "$TMP/e")"
	fi
	run /dev/null "$TMP/o" "$TMP/e" "$PS" 5 4 3 2 1
	[ -s "$TMP/e" ] && ko "no benchmark output without --bench" "nothing should be on stderr without --bench, got: $(short "$TMP/e")" \
		|| ok "no benchmark output without --bench"
	XTRA=1
	for f in "--medium:sqrt|√|n\^?1[.,]5|n\*?√" "--complex:log" "--adaptive:adaptive"; do
		re="${f#*:}"; f="${f%%:*}"
		if verify "--bench $f" "$(tool gen 30)" && grep -Eiq "$re" "$TMP/e"; then
			ok "--bench $f reports its strategy/class"
		else
			ko "--bench $f reports its strategy/class" "${V_RES:-expected /$re/ in the benchmark, got: $(short "$TMP/e")}"
		fi
	done
	verify "--simple --bench" "3 1 2" && [ -s "$TMP/e" ] && ok "flag order --simple --bench works" \
		|| ko "flag order --simple --bench works" "${V_RES:-no benchmark on stderr or output not sorted}"
	XTRA=
	sec_end
}

# perf SIZE RUNS RANGE_MAX PASS GOOD EXCELLENT  (every strategy on the same input)
perf() {
	local size=$1 runs=$2 hi=$3 pass=$4 good=$5 exc=$6 i k f nums line fail
	local mins=() maxs=() sums=() ns=()
	for k in "${!STRATS[@]}"; do mins[k]=999999; maxs[k]=0; sums[k]=0; ns[k]=0; done
	for i in $(seq 1 "$runs"); do
		if [ "$i" -eq "$runs" ] && [ "$runs" -gt 1 ]; then nums=$(tool gen "$size")
		else nums=$(tool gen "$size" 1 "$hi"); fi
		line=; fail=
		for k in "${!STRATS[@]}"; do
			f=${STRATS[k]}
			if ! verify "$f" "$nums"; then
				line="$line ${f#--}=✘"; fail="$fail ${f#--}: $V_RES;"
				continue
			fi
			ns[k]=$((ns[k] + 1)); sums[k]=$((sums[k] + V_OPS))
			[ "$V_OPS" -gt "${maxs[k]}" ] && maxs[k]=$V_OPS
			[ "$V_OPS" -lt "${mins[k]}" ] && mins[k]=$V_OPS
			line="$line ${f#--}=$V_OPS"
			[ "$k" -eq 0 ] && [ "$V_OPS" -ge "$pass" ] && fail="$fail adaptive uses $V_OPS ops (≥ $pass);"
		done
		fail="${fail# }"
		if [ -n "$fail" ]; then ko "run $i:$line" "${fail%;} - $(save_input "$nums")"
		else ok "run $i:$line"; fi
	done
	for k in "${!STRATS[@]}"; do
		[ "${ns[k]}" -gt 0 ] || continue
		f=${STRATS[k]}
		info "$(printf '%-10s' "${f#--}") min ${mins[k]} / avg $((sums[k] / ns[k])) / max ${maxs[k]} → $(rating "${maxs[k]}" "$pass" "$good" "$exc")"
		[ "$k" -gt 0 ] && [ "${maxs[k]}" -ge "$pass" ] \
			&& wn "$f: max ${maxs[k]} ops is above $pass (limits apply to the default strategy only)"
	done
	info "limits: <$pass pass, <$good good, <$exc excellent (applied to adaptive / default)"
}

m_100() {
	sec_begin "Large inputs (100 numbers)" all "$RUNS_100 runs; last run uses the full int range"
	perf 100 "$RUNS_100" 500 2000 1500 700
	sec_end
}

m_500() {
	sec_begin "Very large inputs (500 numbers)" all "$RUNS_500 runs; last run uses the full int range"
	perf 500 "$RUNS_500" 1000 12000 8000 5500
	sec_end
}

m_flags50() {
	sec_begin "Strategy flags testing (50 numbers)" all
	local r nums f line s c mark
	for r in 1 2 3; do
		nums=$(tool gen 50 1 200)
		line=; s=; c=; mark="$G✔$N"
		for f in --simple --medium --complex --adaptive none; do
			if [ $f = none ]; then verify "" "$nums"; else verify "$f" "$nums"; fi
			if [ "$V_RES" != OK ]; then
				ko "input $r: ${f#--}" "$V_RES - $(save_input "$nums")"
				line="$line ${f#--}=✘"; mark="$R✘$N"
				continue
			fi
			SP=$((SP + 1)); ST=$((ST + 1))
			line="$line ${f#--}=$V_OPS"
			[ $f = --simple ] && s=$V_OPS
			[ $f = --complex ] && c=$V_OPS
		done
		printf '  %s input %s:%s\n' "$mark" "$r" "$line"
		if [ -n "$s" ] && [ -n "$c" ] && [ "$c" -ge "$s" ]; then
			wn "input $r: --complex ($c) is not better than --simple ($s)"
		fi
	done
	sec_end
}

m_robust() {
	sec_begin "Robustness - every strategy, every size & disorder" all "subject: any selector must work regardless of input size or disorder"
	local f fl sz nums bad cnt label first
	for f in --simple --medium --complex --adaptive; do
		bad=; cnt=0; first=
		for sz in 1 2 3 4 5 6 7 8 10 25 50 100 500 rev100 rev500 low100 mid100 low500 mid500 limits; do
			case $sz in
				rev*) nums=$(seq "${sz#rev}" | sort -rn | tr '\n' ' ') ;;
				low*) nums=$(tool mix "${sz#low}" 5) ;;
				mid*) nums=$(tool mix "${sz#mid}" 35) ;;
				limits) nums="2147483647 -2147483648 0 -1 1 2147483646 -2147483647" ;;
				*) nums=$(tool gen "$sz") ;;
			esac
			cnt=$((cnt + 1))
			if ! verify "$f" "$nums"; then
				bad="$bad $sz"
				[ -z "$first" ] && first="size '$sz': $V_RES - $(save_input "$nums")"
				log "robust $f $sz: $V_RES" "  input: $nums"
			fi
		done
		if [ -z "$bad" ]; then ok "$f: $cnt cases OK (sizes 1→500, reversed, low/mid disorder, INT limits)"
		else ko "$f" "failed on:$bad. First failure -> $first"; fi
	done
	info "disorder of sample inputs: low=$("$TOOL" disorder $(tool mix 100 5))% mid=$("$TOOL" disorder $(tool mix 100 35))%"
	sec_end
}

m_leaks() {
	sec_begin "Memory leaks (push_swap)" all
	if ! leak_tool; then
		SEC_SKIP="no valgrind/leaks or LEAKS=0"
		wn "no leak checker available - check manually (valgrind on Linux, leaks on macOS)"
		sec_end; return
	fi
	info "using $LEAK_TOOL"
	leak_case "no arguments" /dev/null "$PS"
	leak_case "error: non numeric" /dev/null "$PS" 1 a 3
	leak_case "error: duplicate" /dev/null "$PS" 1 2 1
	leak_case "error: overflow" /dev/null "$PS" 1 2147483648
	leak_case "sorted input" /dev/null "$PS" 1 2 3
	leak_case "5 numbers" /dev/null "$PS" 5 1 4 2 3
	leak_case "--simple 50 numbers" /dev/null "$PS" --simple $(tool gen 50)
	leak_case "--medium 100 numbers" /dev/null "$PS" --medium $(tool gen 100)
	leak_case "--complex 100 numbers" /dev/null "$PS" --complex $(tool gen 100)
	leak_case "--bench --adaptive 500 numbers" /dev/null "$PS" --bench --adaptive $(tool gen 500)
	sec_end
}

run_mandatory() {
	printf '\n%s══════════════ MANDATORY ══════════════%s\n' "$B" "$N"
	if ! m_build; then
		printf '\n%sCompilation failed - stopping mandatory tests.%s\n' "$R" "$N"
		return 1
	fi
	m_norm
	m_readme
	m_errors
	m_flags_basic
	m_identity
	m_small
	m_medium5
	m_bench
	m_100
	m_flags50
	m_500
	m_robust
	m_leaks
	info "still to do by hand: group/README content review and code explanation"
}

# ---------------------------------------------------------------- bonus

ck_case() { # EXPECT(OK|KO) LABEL INPUT ARGS...
	local exp="$1" label="$2" input="$3"
	shift 3
	printf '%s' "$input" >"$TMP/in"
	run "$TMP/in" "$TMP/o" "$TMP/e" "$CK" "$@"
	if ! check_rc; then
		ko "$label" "$PROB"
	elif ! printf '%s\n' "$exp" | cmp -s - "$TMP/o"; then
		ko "$label" "expected \"$exp\" on stdout, got stdout: $(short "$TMP/o") / stderr: $(short "$TMP/e")"
	else
		ok "$label → $exp"
	fi
}

ck_error() { # LABEL INPUT ARGS...
	local label="$1"
	printf '%s' "$2" >"$TMP/in"
	shift 2
	expect_error "$label" "$TMP/in" "$CK" "$@"
}

b_build() {
	sec_begin "Bonus compilation" all
	[ -x "$PS" ] || mk
	mk bonus
	if [ "$RC" -ne 0 ] || [ ! -x "$CK" ]; then
		ko "make bonus builds ./checker" "$(make_fail checker)"
		sec_end; return 1
	fi
	ok "make bonus builds ./checker"
	touch "$TMP/stamp"; sleep 1
	mk bonus
	XTRA=1
	if newer_than_stamp "$CK"; then ko "no relink on second make bonus" "checker was rebuilt"
	else ok "no relink on second make bonus"; fi
	XTRA=
	[ -x "$PS" ] || mk
	sec_end
}

b_errors() {
	sec_begin "Checker - error management" all
	ck_error "non numeric: checker 1 a 3" "" 1 a 3
	ck_error "non numeric: checker 3 2 one 0" "" 3 2 one 0
	ck_error "duplicate: checker 1 2 1" "" 1 2 1
	ck_error "> MAXINT: checker 1 2147483648" "" 1 2147483648
	ck_error "< MININT: checker -2147483649 1" "" -2147483649 1
	{ printf ''; sleep 2; } | {
		TIMEOUT=1 run - "$TMP/o" "$TMP/e" "$CK"
		echo "$RC $RK" >"$TMP/rc"
	}
	read -r RC RK <"$TMP/rc"
	if [ "$RK" = timeout ]; then
		ko "no arguments: returns immediately" "checker kept waiting on stdin; with no arguments it must exit at once without reading"
	elif ! check_rc; then
		ko "no arguments" "$PROB"
	elif [ -s "$TMP/o" ] || [ -s "$TMP/e" ]; then
		ko "no arguments: displays nothing" "expected no output, got stdout: $(short "$TMP/o") / stderr: $(short "$TMP/e")"
	else
		ok "no arguments: displays nothing, returns immediately"
	fi
	ck_error "unknown action 'foo'" $'foo\n' 3 2 1
	ck_error "unknown action after valid ones" $'sa\nrra\nsx\n' 3 2 1
	ck_error "unknown action 'pc'" $'pc\n' 3 2 1
	ck_error "space before action ' sa'" $' sa\n' 2 1
	ck_error "space after action 'sa '" $'sa \n' 2 1
	ck_error "spaces around '  rra  '" $'  rra  \n' 3 1 2
	ck_error "tab after action 'pb\\t'" $'pb\t\n' 2 1
	ck_error "two actions on one line 'sa pb'" $'sa pb\n' 2 1
	XTRA=1
	ck_error "empty argument: checker \"\" 1" "" "" 1
	ck_error "empty argument: checker 1 \"\" 2" "" 1 "" 2
	ck_error "uppercase action 'SA'" $'SA\n' 2 1
	ck_error "empty line" $'sa\n\nsa\n' 2 1
	XTRA=
	sec_end
}

b_false() {
	sec_begin "Checker - false tests (KO)" all
	ck_case KO "checker 0 9 1 8 2 7 3 6 4 5 + [sa pb rrr]" $'sa\npb\nrrr\n' 0 9 1 8 2 7 3 6 4 5
	ck_case KO "checker 3 2 1 0 + [sa rra pb]" $'sa\nrra\npb\n' 3 2 1 0
	ck_case KO "checker 2 1 + no instructions" "" 2 1
	ck_case KO "sorted 1 2 3 + [pb] (b not empty)" $'pb\n' 1 2 3
	ck_case KO "sorted 1 2 3 + [sa]" $'sa\n' 1 2 3
	local i n nums ops bad=0 tot=0
	for i in $(seq 1 25); do
		n=$((RANDOM % 15 + 2))
		nums=$(tool gen $n -1000 1000)
		tool randops $((RANDOM % 25 + 1)) >"$TMP/in"
		[ "$("$TOOL" check $nums <"$TMP/in")" = KO ] || continue
		tot=$((tot + 1))
		run "$TMP/in" "$TMP/o" "$TMP/e" "$CK" $nums
		if ! check_rc || [ "$(cat "$TMP/o")" != KO ]; then
			bad=$((bad + 1)); log "expected KO: checker $nums < $(tr '\n' ' ' <"$TMP/in")"
			hung && { log "expected KO: checker timed out - remaining random cases skipped"; break; }
		fi
	done
	[ $bad -eq 0 ] && ok "$tot random lists + random unsorting instructions → KO" \
		|| ko "random unsorting instructions" "$bad/$tot cases: checker should print KO but did not (last: $(grep 'expected KO' "$LOG" | tail -1 | cut -c1-110))"
	sec_end
}

b_right() {
	sec_begin "Checker - right tests (OK)" all
	ck_case OK "checker 0 1 2 + no instructions" "" 0 1 2
	ck_case OK "checker 0 9 1 8 2 + [pb ra pb ra sa ra pa pa]" $'pb\nra\npb\nra\nsa\nra\npa\npa\n' 0 9 1 8 2
	ck_case OK "checker 3 2 1 0 + [rra pb sa rra pa]" $'rra\npb\nsa\nrra\npa\n' 3 2 1 0
	ck_case OK "1 2 3 + [pa sb rb rrb] (no-ops on empty b)" $'pa\nsb\nrb\nrrb\n' 1 2 3
	ck_case OK "single number + no instructions" "" 42
	ck_case OK "INT limits 2147483647 -2147483648 + [sa]" $'sa\n' 2147483647 -2147483648
	local n nums bad=0 tot=0
	for n in 2 3 4 5 7 10 20 50 100 100 250; do
		nums=$(tool gen $n)
		"$TOOL" solve $nums >"$TMP/in"
		tot=$((tot + 1))
		run "$TMP/in" "$TMP/o" "$TMP/e" "$CK" $nums
		if ! check_rc || [ "$(cat "$TMP/o")" != OK ]; then
			bad=$((bad + 1)); log "expected OK: checker $nums (ops from ps_tool solve)"
			hung && { log "expected OK: checker timed out - remaining random cases skipped"; break; }
		fi
	done
	[ $bad -eq 0 ] && ok "$tot random lists (2→250) + valid sorting instructions → OK" \
		|| ko "random lists + valid sorting instructions" "$bad/$tot cases: checker should print OK but did not (last: $(grep 'expected OK' "$LOG" | tail -1 | cut -c1-110))"
	nums=$(tool gen 500)
	"$TOOL" solve $nums >"$TMP/in"
	run "$TMP/in" "$TMP/o" "$TMP/e" "$CK" $nums
	if check_rc && [ "$(cat "$TMP/o")" = OK ]; then ok "500 numbers, $(wc -l <"$TMP/in" | tr -d ' ') instructions → OK"
	else ko "500 numbers, large instruction list" "${PROB:-expected OK, got stdout: $(short "$TMP/o") stderr: $(short "$TMP/e")}"; fi
	XTRA=1
	nums=$(tool gen 100)
	run /dev/null "$TMP/in" "$TMP/e" "$PS" $nums
	if ! check_rc; then
		ko "./push_swap \$ARG | ./checker \$ARG (100 numbers)" "push_swap: $PROB"
	else
		run "$TMP/in" "$TMP/o" "$TMP/e" "$CK" $nums
		if ! check_rc; then
			ko "./push_swap \$ARG | ./checker \$ARG (100 numbers)" "checker: $PROB"
		elif [ "$(cat "$TMP/o")" = OK ]; then
			ok "./push_swap \$ARG | ./checker \$ARG (100 numbers)"
		else
			ko "./push_swap \$ARG | ./checker \$ARG (100 numbers)" "checker should print OK on push_swap's output, got: $(short "$TMP/o")"
		fi
	fi
	XTRA=
	sec_end
}

b_fuzz() {
	sec_begin "Checker - fuzz against reference" all "random lists + random/valid instruction mixes, all 11 ops"
	local i n nums exp got bad=0
	for i in $(seq 1 60); do
		# $RANDOM inside $(...) is reseeded by bash 3.2 subshells: draw it out here
		n=$((RANDOM % 6 + 1))
		nums=$(tool gen $n -20 20)
		if [ $((i % 3)) -eq 0 ]; then "$TOOL" solve $nums >"$TMP/in"
		else tool randops $((RANDOM % 12)) >"$TMP/in"; fi
		exp=$("$TOOL" check $nums <"$TMP/in")
		run "$TMP/in" "$TMP/o" "$TMP/e" "$CK" $nums
		if ! check_rc; then
			bad=$((bad + 1)); log "fuzz crash: $nums ($PROB)"
			hung && { log "fuzz: checker timed out - remaining cases skipped"; break; }
			continue
		fi
		got=$(cat "$TMP/o")
		if [ "$got" != "$exp" ]; then
			bad=$((bad + 1))
			log "fuzz: checker $nums < [$(tr '\n' ' ' <"$TMP/in")] expected $exp got $got"
		fi
	done
	[ $bad -eq 0 ] && ok "60 random cases match the reference" || ko "fuzz" "$bad/60 answers differ from the reference (last: $(grep 'fuzz' "$LOG" | tail -1 | cut -c1-110))"
	sec_end
}

b_leaks() {
	sec_begin "Memory leaks (checker)" all
	if ! leak_tool; then
		SEC_SKIP="no valgrind/leaks or LEAKS=0"
		wn "no leak checker available - check manually"
		sec_end; return
	fi
	local nums
	leak_case "no arguments" /dev/null "$CK"
	leak_case "error: non numeric" /dev/null "$CK" 1 a
	leak_case "error: duplicate" /dev/null "$CK" 1 2 1
	printf 'sa\nfoo\n' >"$TMP/lin"
	leak_case "error: bad instruction" "$TMP/lin" "$CK" 3 2 1
	printf 'sa\npb\nrrr\n' >"$TMP/lin"
	leak_case "KO case" "$TMP/lin" "$CK" 0 9 1 8 2 7 3 6 4 5
	nums=$(tool gen 100)
	"$TOOL" solve $nums >"$TMP/lin"
	leak_case "OK case (100 numbers)" "$TMP/lin" "$CK" $nums
	sec_end
}

run_bonus() {
	printf '\n%s══════════════ BONUS ══════════════%s\n' "$B" "$N"
	b_build || return 1
	b_errors
	b_false
	b_right
	b_fuzz
	b_leaks
}

# ---------------------------------------------------------------- main

if [ ! -x "$TOOL" ]; then
	(set +f; cc -O2 -o "$TOOL" "$TESTER_DIR"/tools/*.c) || { echo "cannot build ps_tool"; exit 2; }
fi
pick_ref

printf '%spush_swap tester%s  -  %s\n' "$B" "$N" "$PS_DIR"
printf '%sDisclaimer: unofficial tester, for reference only. Passing does not guarantee a correct project.%s\n' "$Y" "$N"
printf '%sverifying with %s | timeout %ss | seed %s | log: %s%s\n' "$D" "$REF_NAME" "$TIMEOUT" "$SEED" "${LOG#$TESTER_DIR/}" "$D$N"
log "SEED=$SEED (replay with: make $MODE SEED=$SEED)"

case "$MODE" in
	mandatory) run_mandatory ;;
	bonus) run_bonus ;;
	all)
		run_mandatory
		run_bonus
		;;
	*) echo "usage: $0 [all|mandatory|bonus]"; exit 2 ;;
esac

printf '\n%s══════════════ SUMMARY ══════════════%s\n' "$B" "$N"
for i in "${!SUM_NAME[@]}"; do
	printf '  %-52s %b\n' "${SUM_NAME[$i]}" "${SUM_RES[$i]}"
done
echo
[ "$CRASHES" -gt 0 ] && printf '  %s%s crash(es)/timeout(s) detected%s\n' "$R$B" "$CRASHES" "$N"
if [ "$FAILS" -eq 0 ]; then
	printf '  %sAll counted tests passed%s' "$G$B" "$N"
else
	printf '  %s%s failed test(s)%s' "$R$B" "$FAILS" "$N"
fi
printf ', %s warning(s). Details: %s\n' "$WARNS" "${LOG#$TESTER_DIR/}"
printf '  %sReplay the same random inputs with SEED=%s%s\n' "$D" "$SEED" "$N"
printf '  %sRunning make clean in the push_swap repo to remove object files.%s\n' "$D" "$N"
[ "$FAILS" -eq 0 ] && [ "$CRASHES" -eq 0 ]
