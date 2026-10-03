VCS ?= vcs
PYTHON ?= python3
CASE ?= 0
SEED ?= 1
RANDOM_ITERS ?= 64
ID_WIDTH ?= 4
FSDB ?= 0
COV ?= 0
VERDI ?= verdi
WAVE ?= x2p.fsdb
VCS_OPTS = -full64 -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps \
           -debug_access+all -kdb -top x2p_tb -f filelist.f \
           +define+X2P_ID_WIDTH=$(ID_WIDTH) -l compile.log -o simv
SIM_OPTS ?= +UVM_VERBOSITY=UVM_MEDIUM +X2P_TOPOLOGY
RUN_ARGS ?= +X2P_DUMP_VCD

ifeq ($(FSDB),1)
ifndef VERDI_HOME
$(error FSDB=1 requires VERDI_HOME)
endif
VCS_OPTS += +define+X2P_FSDB \
            -P $(VERDI_HOME)/share/PLI/VCS/LINUX64/novas.tab \
               $(VERDI_HOME)/share/PLI/VCS/LINUX64/pli.a
endif
ifeq ($(COV),1)
VCS_OPTS += -cm line+cond+tgl+branch+assert -cm_dir x2p.vdb
SIM_OPTS += -cm line+cond+tgl+branch+assert -cm_dir x2p.vdb
endif

.PHONY: all compile run smoke added regress regress_new verdi clean
all: run

# Changing ID_WIDTH / FSDB / COV needs 'make clean' before rebuilding.
simv: $(wildcard ../tb/*.sv ../tb/*.svh ../rtl/*.v ../sva/*.sv) filelist.f Makefile
	$(VCS) $(VCS_OPTS)

compile: simv
run: simv
	./simv $(SIM_OPTS) +CASE=$(CASE) +ntb_random_seed=$(SEED) \
	       +RANDOM_ITERS=$(RANDOM_ITERS) $(RUN_ARGS) -l sim.log
	$(PYTHON) ../scripts/check_log.py sim.log

smoke:
	$(MAKE) run CASE=2

added:
	$(MAKE) run CASE=0 RUN_ARGS="$(RUN_ARGS) +X2P_NEW_ONLY"

regress: simv
	$(PYTHON) ../scripts/regress.py --simv ./simv --output regress \
	          --seed $(SEED) --random-iters $(RANDOM_ITERS)

regress_new: simv
	$(PYTHON) ../scripts/regress.py --simv ./simv --output regress_new \
	          --cases 21,22,23,24,25,26,27,28 --seed $(SEED) --random-iters $(RANDOM_ITERS)

verdi: simv
	$(VERDI) -dbdir simv.daidir -ssf $(WAVE) &

clean:
	rm -rf simv simv.daidir csrc ucli.key compile.log sim.log \
	       x2p.vcd x2p.fsdb x2p.vdb regress regress_new novas.conf novas.rc verdiLog
