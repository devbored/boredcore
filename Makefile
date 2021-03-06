ifdef TC_TRIPLE
TOOLCHAIN_PREFIX       := $(TC_TRIPLE)
else
TOOLCHAIN_PREFIX       := riscv64-unknown-elf
endif
CC                     := $(TOOLCHAIN_PREFIX)-gcc
AS                     := $(TOOLCHAIN_PREFIX)-as
OBJCOPY                := $(TOOLCHAIN_PREFIX)-objcopy
OBJDUMP                := $(TOOLCHAIN_PREFIX)-objdump

IVERILOG_FLAGS         := -Wall
IVERILOG_FLAGS         += -Ihdl
IVERILOG_FLAGS         += -DSIM
IVERILOG_FLAGS         += -DDUMP_VCD

IVERILOG_OUT           := obj_dir/sub

ROOT_DIR               := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
ifdef DOCKER
DOCKER_CMD             := docker exec -u user -w /src boredcore
DOCKER_RUNNING         := $(shell docker ps -a -q -f name=boredcore)
else
DOCKER_CMD             :=
endif

GTEST_BASEDIR          ?= /usr/local/lib

VERILATOR_VER          := $(shell verilator --version | awk '{print $$2}' | sed 's/\.//')

VERILATOR_CFLAGS       := -g
VERILATOR_CFLAGS       += -DBASE_PATH='\"$(ROOT_DIR)/obj_dir\"'
VERILATOR_CFLAGS       += -DVERILATOR_VER=$(VERILATOR_VER)
ifdef TEST_VERBOSE
VERILATOR_CFLAGS       += -DVERBOSE
endif

VERILATOR_FLAGS        := -Wall
VERILATOR_FLAGS        += -Ihdl
VERILATOR_FLAGS        += --trace
VERILATOR_FLAGS        += -CFLAGS "$(VERILATOR_CFLAGS)"
VERILATOR_FLAGS        += -LDFLAGS "$(GTEST_BASEDIR)/libgtest_main.a $(GTEST_BASEDIR)/libgtest.a -lpthread"
VERILATOR_FLAGS        += --x-assign unique
VERILATOR_FLAGS        += --x-initial unique

vpath %.v tests
vpath %.py scripts

HDL_SRCS               := $(shell find hdl -type f -name "*.v")
TEST_PY_MEM            := $(shell find scripts -type f -name "sub_*.mem.py" -exec basename {} \;)
TEST_PY_ASM            := $(shell find scripts -type f -name "sub_*.asm.py" -exec basename {} \;)

VERILATOR_SRCS         := $(shell find tests/cpu -type f -name "*.cc")
VERILATOR_TEST_ASM     := $(shell find tests/cpu/programs -type f -name "*.s" -exec basename {} \;)
VERILATOR_PY_SRCS      := $(shell find scripts -type f -name "cpu_*.asm.py" -exec basename {} \;)
VERILATOR_TEST_SRCS    := $(VERILATOR_PY_SRCS:%.asm.py=obj_dir/%.s)
VERILATOR_TEST_ELF     := $(VERILATOR_TEST_SRCS:%.s=%.elf)
VERILATOR_TEST_MEM     := $(VERILATOR_TEST_ELF:%.elf=%.mem)
VERILATOR_TEST_ASM_MEM := $(VERILATOR_TEST_ASM:%.s=obj_dir/%.mem)

IVERILOG_ALL_SRCS      := $(shell find tests/sub -type f -name "*.v" -exec basename {} \;)
IVERILOG_MEMH_SRCS     := $(TEST_PY_MEM:sub_%.mem.py=%.v)
IVERILOG_MEMH_OBJS     := $(IVERILOG_MEMH_SRCS:%.v=$(IVERILOG_OUT)/%.mem.out)
IVERILOG_ASM_SRCS      := $(TEST_PY_ASM:sub_%.asm.py=%.v)
IVERILOG_ASM_OBJS      := $(IVERILOG_ASM_SRCS:%.v=$(IVERILOG_OUT)/%.asm.out)
IVERILOG_PLAIN_SRCS    := $(filter-out $(IVERILOG_MEMH_SRCS) $(IVERILOG_ASM_SRCS), $(IVERILOG_ALL_SRCS))
IVERILOG_PLAIN_OBJS    := $(IVERILOG_PLAIN_SRCS:%.v=$(IVERILOG_OUT)/%.out)

$(IVERILOG_OUT)/sub_%.mem: sub_%.mem.py
	python3 $< -out $(IVERILOG_OUT)

$(IVERILOG_OUT)/sub_%.s: sub_%.asm.py
	python3 $< -out $(IVERILOG_OUT)

obj_dir/cpu_%.s: scripts/cpu_%.asm.py
	python3 $< -out obj_dir

.SECONDARY:
$(IVERILOG_OUT)/sub_%.elf: $(IVERILOG_OUT)/sub_%.s
	$(DOCKER_CMD) $(AS) -o $@ $<

.SECONDARY:
$(IVERILOG_OUT)/sub_%.mem: $(IVERILOG_OUT)/sub_%.elf
	$(DOCKER_CMD) $(OBJCOPY) -O verilog --verilog-data-width=4 $< $@

$(IVERILOG_OUT)/%.out: tests/sub/%.v hdl/%.v
	iverilog $(IVERILOG_FLAGS) -o $@ $<

$(IVERILOG_OUT)/%.mem.out: tests/sub/%.v hdl/%.v $(IVERILOG_OUT)/sub_%.mem
	iverilog $(IVERILOG_FLAGS) -o $@ $<

$(IVERILOG_OUT)/%.asm.out: tests/sub/%.v hdl/%.v $(IVERILOG_OUT)/sub_%.mem
	iverilog $(IVERILOG_FLAGS) -o $@ $<

obj_dir/%.cpp: $(VERILATOR_SRCS) $(HDL_SRCS)
	verilator $(VERILATOR_FLAGS) --exe tests/cpu/boredcore.cc $(VERILATOR_SRCS) --top-module boredcore -cc $(HDL_SRCS)

obj_dir/cpu_%.elf: obj_dir/cpu_%.s
	$(DOCKER_CMD) $(AS) -o $@ $<

obj_dir/cpu_%.mem: obj_dir/cpu_%.elf
	$(DOCKER_CMD) $(OBJCOPY) -O verilog --verilog-data-width=4 $< $@

obj_dir/%.elf: tests/cpu/programs/%.s
	$(DOCKER_CMD) $(AS) -o $@ $<

obj_dir/%.mem: obj_dir/%.elf
	$(DOCKER_CMD) $(OBJCOPY) -O verilog --verilog-data-width=4 $< $@
# =====================================================================================================================

# Main build is simulating CPU with Verilator
.PHONY: all
all: build-dir $(VERILATOR_TEST_MEM) $(VERILATOR_TEST_ASM_MEM) obj_dir/Vboredcore.cpp
	@$(MAKE) -C obj_dir -f Vboredcore.mk Vboredcore
	@printf "\nAll done building cpu tests.\n"

# Create the docker container (if needed) and start
.PHONY: docker
docker:
ifeq ($(DOCKER_RUNNING),)
	@docker build -t riscv-gnu-toolchain .
	@docker create -it -v $(ROOT_DIR):/src --name boredcore riscv-gnu-toolchain
endif
	@docker start boredcore

# Sub-module testing
.PHONY: sub
sub: build-dir $(IVERILOG_PLAIN_OBJS) $(IVERILOG_ASM_OBJS) $(IVERILOG_MEMH_OBJS)
	@printf "\nAll done building submodule tests.\n"

.PHONY: build-dir
build-dir:
	@mkdir -p obj_dir/
	@mkdir -p $(IVERILOG_OUT)/

.PHONY: clean
clean:
	rm -rf obj_dir 2> /dev/null || true

.PHONY: soc-sub
soc-sub:
	$(MAKE) sub -C ./soc
