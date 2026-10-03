VCS ?= vcs
PYTHON ?= python3
CASE ?= 0
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

.PHONY: all compile run smoke regress verdi clean
all: run

# Changing ID_WIDTH / FSDB / COV needs 'make clean' before rebuilding.
simv: $(wildcard ../tb/*.sv ../tb/*.svh ../rtl/*.v ../sva/*.sv) filelist.f Makefile
	$(VCS) $(VCS_OPTS)

compile: simv
run: simv
	./simv $(SIM_OPTS) +CASE=$(CASE) $(RUN_ARGS) -l sim.log
	$(PYTHON) ../scripts/check_log.py sim.log

smoke:
	$(MAKE) run CASE=2

regress: simv
	$(PYTHON) ../scripts/regress.py --simv ./simv --output regress

verdi: simv
	$(VERDI) -dbdir simv.daidir -ssf $(WAVE) &

clean:
	rm -rf simv simv.daidir csrc ucli.key compile.log sim.log \
	       x2p.vcd x2p.fsdb x2p.vdb regress novas.conf novas.rc verdiLog
