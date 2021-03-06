# boredcore

### โ  Currently still in early development! โ 
---
Another RISC-V cpu core design.

## Design ๐บ
- 4-stage in-order pipelined processor
- Aimed to be implemented as a soft-cpu for use in FPGAs

## Dependencies โ
- GNU Make
- GCC RISC-V compiler/cross-compiler toolchain
- Icarus Verilog (testing)
- Verilator (testing)
- SymbiYosys (testing)
    - Yosys
    - z3
- Python >= 3.6

## Make configs โ
Below are a table of Make config variables:
| Variable     | Behavior                   | Usage                                   | Default             |
|:-------------|:---------------------------|:----------------------------------------|:--------------------|
|TC_TRIPLE     |RISCV-GCC toolcahin triple  |$ make TC_TRIPLE=riscv64-unknown-elf ... | riscv64-unknown-elf |
|GTEST_BASEDIR |GoogleTest install dir      |$ make GTEST_BASEDIR=/opt/gtest/lib ...  | /usr/local/lib      |
|DOCKER        |Use Docker GCC toolchain    |$ make DOCKER=1 ...                      | 0 (OFF)             |
|TEST_VERBOSE  |Verbose Verilated CPU tests |$ make TEST_VERBOSE=1 ...                | 0 (OFF)             |

## Testing ๐งช
Functional Verification:
- `iverilog`    : Unit testing CPU sub-modules
- `Verilator`   : CPU testing

Formal Verification:
- `SymbiYosys`  : Formal verify critical pieces of sub-module logic (TODO)

To build CPU tests:

    # make

CPU testing program outputs to `obj_dir/Vboredcore`

To build the submodule tests:

    $ make sub

Each submodule test outputs to `obj_dir/sub/sub_<module_name>.out`

### Docker ๐ณ
RISC-V GCC cross-compiler is needed for running tests and building example firmware. There is a Dockerfile
here to take care of this (easy-mode).

To build and start the container (need to run at least once to ensure container is running):

    $ make docker

To build the CPU tests:

    $ make DOCKER=ON

Then to build the submodule tests:

    $ make sub DOCKER=ON
