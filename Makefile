# push_swap_tester
#   make a   -> mandatory + bonus
#   make m   -> mandatory only
#   make b   -> bonus only
# Options: PS_DIR=..  RUNS_100=5  RUNS_500=3  TIMEOUT=10  LEAKS=0 (skip leak checks)
#          SEED=N (replay the random inputs of an earlier run)

PS_DIR		?= ..
RUNS_100	?= 5
RUNS_500	?= 3
TIMEOUT		?= 10
LEAKS		?= 1

TOOL		= tools/ps_tool
ENV			= PS_DIR="$(PS_DIR)" RUNS_100=$(RUNS_100) RUNS_500=$(RUNS_500) \
			  TIMEOUT=$(TIMEOUT) LEAKS=$(LEAKS) \
			  $(if $(SEED),SEED=$(SEED))

help:
	@echo "usage: make a | m | b    (all, mandatory, bonus)"
	@echo "options: PS_DIR=$(PS_DIR) RUNS_100=$(RUNS_100) RUNS_500=$(RUNS_500) TIMEOUT=$(TIMEOUT) LEAKS=$(LEAKS)"

a: $(TOOL)
	@$(ENV) bash ./tester.sh all || true

m: $(TOOL)
	@$(ENV) bash ./tester.sh mandatory || true

b: $(TOOL)
	@$(ENV) bash ./tester.sh bonus || true

$(TOOL): tools/ps_tool.c
	@cc -O2 -o $@ $<

clean:
	@rm -rf $(TOOL) logs

re: clean $(TOOL)

.PHONY: help a m b clean re
