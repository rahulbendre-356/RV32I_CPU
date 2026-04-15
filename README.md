# RISC-V Pipelined CPU (RV32I)

This project implements a 5-stage pipelined RISC-V CPU using Verilog HDL. The processor follows the standard pipeline stages: Instruction Fetch (IF), Instruction Decode (ID), Execute (EX), Memory (MEM), and Write Back (WB).

It supports a subset of RV32I instructions including arithmetic, logical, memory, and control operations such as ADD, SUB, ADDI, AND, OR, XOR, SLL, LW, SW, and JAL. Instructions are loaded using a `.hex` file for simulation and testing.

The design uses internal data memory for load/store operations and pipeline registers to enable parallel execution of instructions.

## Features

* 5-stage pipelined architecture
* RV32I instruction subset support
* Instruction memory using `.hex` file
* Internal data memory
* Verilog-based design and simulation

## Tools

* Verilog HDL
* Xilinx Vivado

## Purpose

To understand pipelined processor design, instruction execution, and memory interaction as a foundation for advanced FPGA-based system design.
