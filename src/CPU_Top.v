`timescale 1ns / 1ps

/*
=============================================================================
RISC-V 5-STAGE PIPELINED CPU - BEGINNER VERSION
=============================================================================

This CPU has 5 stages (like an assembly line):
1. IF  (Instruction Fetch)    - Get instruction from memory
2. ID  (Instruction Decode)   - Figure out what instruction does
3. EX  (Execute)              - Do the actual calculation
4. MEM (Memory Access)        - Read/Write data memory
5. WB  (Write Back)           - Save result to register

Data flows through these stages using "pipeline registers" that hold
data between stages.
*/

module CPU_Top(
    input wire clk,           // Clock signal - makes CPU do work
    input wire reset,         // Reset signal - restart CPU
    output wire [31:0] debug_pc  // Program Counter - which instruction we're on
);

// =========================================================================
// PART 1: MEMORY AND REGISTERS (The CPU's storage)
// =========================================================================

// --- Instruction Memory (stores the program) ---
// This is like a book of instructions the CPU reads
reg [31:0] instr_mem [0:255];  // 256 instructions max
initial begin
    // Load instructions from a file
    $readmemh("D:/3rd year/vhdl/risc-v/risc-v.srcs/sources_1/new/instructions.hex", instr_mem);
end

// --- Data Memory (stores numbers/data) ---
// This is where the CPU can save and load data
reg [31:0] data_mem [0:255];   // 256 data words

// --- Register File (CPU's quick-access storage) ---
// 32 registers named x0, x1, x2, ... x31
// x0 is always 0 (special rule in RISC-V)
reg [31:0] regs [0:31];
integer i;
initial begin
    for (i = 0; i < 32; i = i + 1) 
        regs[i] = 0;  // Start with all zeros
end

// --- Program Counter (PC) ---
// Points to the current instruction address
reg [31:0] pc;
initial pc = 0;  // Start at instruction 0
assign debug_pc = pc;  // Let testbench see PC

// =========================================================================
// PART 2: CONTROL SIGNALS FOR JUMPING
// =========================================================================
wire pc_jump;          // Should we jump to a new address?
wire [31:0] next_pc_j; // Where should we jump to?

// =========================================================================
// PART 3: PIPELINE REGISTERS (Data storage between stages)
// =========================================================================
// These act like conveyor belts between factory stations

// --- IF/ID Pipeline Register (between stage 1 and 2) ---
reg [31:0] if_id_pc;      // PC of current instruction
reg [31:0] if_id_instr;   // The instruction itself

// --- ID/EX Pipeline Register (between stage 2 and 3) ---
reg [31:0] id_ex_pc;      // PC (needed for JAL)
reg [31:0] id_ex_rd1;     // Value from register rs1
reg [31:0] id_ex_rd2;     // Value from register rs2
reg [31:0] id_ex_imm;     // Immediate value (constant in instruction)
reg [4:0] id_ex_rs1;      // Source register 1 number
reg [4:0] id_ex_rs2;      // Source register 2 number
reg [4:0] id_ex_rd;       // Destination register number
reg reg_write_idex;       // Should we write to register?
reg mem_read_idex;        // Should we read memory?
reg mem_write_idex;       // Should we write memory?
reg alu_src_idex;         // Use immediate or register for ALU?
reg mem_to_reg_idex;      // Write memory data or ALU result to register?
reg jal_idex;             // Is this a JAL (jump) instruction?
reg [3:0] alu_op_idex;    // What operation should ALU do?

// --- EX/MEM Pipeline Register (between stage 3 and 4) ---
reg [31:0] ex_mem_alu_result; // Result from ALU calculation
reg [31:0] ex_mem_rd2;        // Data to write to memory
reg [4:0] ex_mem_rd;          // Destination register number
reg reg_write_exmem;
reg mem_read_exmem;
reg mem_write_exmem;
reg mem_to_reg_exmem;
reg jal_exmem;

// --- MEM/WB Pipeline Register (between stage 4 and 5) ---
reg [31:0] mem_wb_alu_result; // ALU result
reg [31:0] mem_wb_mem_data;   // Data read from memory
reg [4:0] mem_wb_rd;          // Destination register number
reg reg_write_memwb;
reg mem_to_reg_memwb;
reg jal_memwb;

// =========================================================================
// STAGE 1: IF (INSTRUCTION FETCH)
// =========================================================================
// This stage fetches (gets) the next instruction from memory

reg stall;  // Pause the pipeline if there's a hazard

always @(posedge clk) begin
    if (reset) begin
        // When reset, start fresh
        pc <= 0;
        if_id_instr <= 0;
        if_id_pc <= 0;
        stall <= 0;
    end else begin
        if (stall) begin
            // STALL: Hold everything, insert a bubble (NOP)
            if_id_instr <= 0;  // NOP (no operation)
            if_id_pc <= if_id_pc;
        end else if (pc_jump) begin
            // JUMP: Go to a new address
            pc <= next_pc_j;
            if_id_instr <= 0;  // Flush (cancel) next instruction
            if_id_pc <= 0;
        end else begin
            // NORMAL: Fetch next instruction
            if_id_instr <= instr_mem[pc[9:2]];  // Get instruction at PC
            if_id_pc <= pc;                      // Save PC
            pc <= pc + 4;                        // Move to next instruction (4 bytes)
        end
    end
end

// =========================================================================
// STAGE 2: ID (INSTRUCTION DECODE)
// =========================================================================
// This stage figures out what the instruction means

// --- Extract fields from instruction ---
wire [4:0] rs1 = if_id_instr[19:15];  // Source register 1
wire [4:0] rs2 = if_id_instr[24:20];  // Source register 2
wire [4:0] rd  = if_id_instr[11:7];   // Destination register
wire [6:0] opcode = if_id_instr[6:0]; // Instruction type
wire [2:0] funct3 = if_id_instr[14:12]; // Function code
wire [6:0] funct7 = if_id_instr[31:25]; // Function code (for R-type)

// --- Forwarding Logic (to avoid waiting for data) ---
// If a later stage has the data we need, grab it early!
wire id_fwd_rs1_exmem = (reg_write_exmem && ex_mem_rd != 0 && ex_mem_rd == rs1);
wire id_fwd_rs1_memwb = (reg_write_memwb && mem_wb_rd != 0 && mem_wb_rd == rs1);
wire id_fwd_rs2_exmem = (reg_write_exmem && ex_mem_rd != 0 && ex_mem_rd == rs2);
wire id_fwd_rs2_memwb = (reg_write_memwb && mem_wb_rd != 0 && mem_wb_rd == rs2);

wire [31:0] wb_data_id = (mem_to_reg_memwb) ? mem_wb_mem_data : mem_wb_alu_result;

// Read register values (with forwarding)
wire [31:0] rd1 = id_fwd_rs1_exmem ? ex_mem_alu_result : 
                 (id_fwd_rs1_memwb ? wb_data_id : regs[rs1]);
wire [31:0] rd2 = id_fwd_rs2_exmem ? ex_mem_alu_result : 
                 (id_fwd_rs2_memwb ? wb_data_id : regs[rs2]);

// --- Generate Immediate Values (constants from instruction) ---

// I-Type: Used for ADDI, Load instructions
// Format: [imm[11:0]] [rs1] [funct3] [rd] [opcode]
wire [31:0] imm_i = {{20{if_id_instr[31]}}, if_id_instr[31:20]};

// S-Type: Used for Store instructions
// Format: [imm[11:5]] [rs2] [rs1] [funct3] [imm[4:0]] [opcode]
wire [31:0] imm_s = {{20{if_id_instr[31]}}, if_id_instr[31:25], if_id_instr[11:7]};

// J-Type: Used for JAL (jump) instruction
// Format: [imm[20|10:1|11|19:12]] [rd] [opcode]
wire [31:0] imm_j = {{12{if_id_instr[31]}}, 
                     if_id_instr[19:12], 
                     if_id_instr[20], 
                     if_id_instr[30:21], 
                     1'b0};

// --- Jump Control ---
reg pc_jump_ctrl;
assign pc_jump = pc_jump_ctrl;
assign next_pc_j = if_id_pc + imm_j;  // New PC = current PC + offset

// --- Control Signals (tells CPU what to do) ---
reg reg_write_ctrl;   // Write to register?
reg mem_read_ctrl;    // Read from memory?
reg mem_write_ctrl;   // Write to memory?
reg alu_src_ctrl;     // Use immediate or register?
reg mem_to_reg_ctrl;  // Write memory data to register?
reg jal_ctrl;         // Is this JAL?
reg [3:0] alu_op_ctrl; // ALU operation

// --- Decode Instruction (big decision tree) ---
always @(*) begin
    // Default: do nothing
    reg_write_ctrl = 0;
    mem_read_ctrl = 0;
    mem_write_ctrl = 0;
    alu_src_ctrl = 0;
    mem_to_reg_ctrl = 0;
    jal_ctrl = 0;
    pc_jump_ctrl = 0;
    alu_op_ctrl = 4'b0000;

    case(opcode)
        // --- LOAD (LW) ---
        7'b0000011: begin
            reg_write_ctrl = 1;    // Yes, write to register
            mem_read_ctrl = 1;     // Yes, read memory
            alu_src_ctrl = 1;      // Use immediate (for address calculation)
            mem_to_reg_ctrl = 1;   // Write memory data to register
            alu_op_ctrl = 4'b0000; // ADD (calculate address = rs1 + offset)
        end
        
        // --- STORE (SW) ---
        7'b0100011: begin
            mem_write_ctrl = 1;    // Yes, write to memory
            alu_src_ctrl = 1;      // Use immediate (for address calculation)
            alu_op_ctrl = 4'b0000; // ADD (calculate address = rs1 + offset)
        end
        
        // --- JUMP (JAL) ---
        7'b1101111: begin
            reg_write_ctrl = 1;    // Write return address (PC+4) to register
            pc_jump_ctrl = 1;      // Yes, jump!
            jal_ctrl = 1;          // Mark as JAL
            alu_op_ctrl = 4'b0000; // Not used for JAL
        end
        
        // --- ADDI (Add Immediate) ---
        7'b0010011: begin
            if (funct3 == 3'b000) begin
                reg_write_ctrl = 1;    // Write result to register
                alu_src_ctrl = 1;      // Use immediate
                alu_op_ctrl = 4'b0000; // ADD operation
            end
        end
        
        // --- R-Type (Register operations: ADD, SUB, AND, OR, XOR, SLL) ---
        7'b0110011: begin
            reg_write_ctrl = 1;  // Write result to register
            alu_src_ctrl = 0;    // Use register (not immediate)
            
            case(funct3)
                3'b000: alu_op_ctrl = (funct7 == 7'b0000000) ? 4'b0000 : // ADD
                                      (funct7 == 7'b0100000) ? 4'b0001 : 4'b1111; // SUB
                3'b100: alu_op_ctrl = 4'b0101; // XOR
                3'b001: alu_op_ctrl = 4'b0010; // SLL (shift left)
                3'b111: alu_op_ctrl = 4'b0011; // AND
                3'b110: alu_op_ctrl = 4'b0100; // OR
                default: alu_op_ctrl = 4'b1111; // Invalid
            endcase
        end
    endcase
end

// --- Hazard Detection (Load-Use Hazard) ---
// Problem: If current instruction needs data that previous instruction
// is still loading from memory, we must STALL (wait one cycle)
wire load_use_hazard = mem_read_idex && ((id_ex_rd == rs1) || (id_ex_rd == rs2));
always @(*) stall = load_use_hazard;

// --- ID/EX Pipeline Register Update ---
always @(posedge clk) begin
    if (reset || stall || pc_jump) begin
        // Clear pipeline register (insert bubble)
        id_ex_pc <= 0; id_ex_rd1 <= 0; id_ex_rd2 <= 0; id_ex_imm <= 0;
        id_ex_rd <= 0; id_ex_rs1 <= 0; id_ex_rs2 <= 0;
        reg_write_idex <= 0; mem_read_idex <= 0; mem_write_idex <= 0;
        alu_src_idex <= 0; alu_op_idex <= 0; mem_to_reg_idex <= 0;
        jal_idex <= 0;
    end else begin
        // Pass data to next stage
        id_ex_pc <= if_id_pc;
        id_ex_rd1 <= rd1;
        id_ex_rd2 <= rd2;
        
        // Select correct immediate
        id_ex_imm <= (opcode == 7'b0100011) ? imm_s : // Store
                     (opcode == 7'b0000011) ? imm_i : // Load
                     (opcode == 7'b0010011) ? imm_i : // ADDI
                     (opcode == 7'b1101111) ? imm_j : imm_i; // JAL
        
        id_ex_rd <= rd;
        id_ex_rs1 <= rs1;
        id_ex_rs2 <= rs2;
        reg_write_idex <= reg_write_ctrl;
        mem_read_idex <= mem_read_ctrl;
        mem_write_idex <= mem_write_ctrl;
        alu_src_idex <= alu_src_ctrl;
        alu_op_idex <= alu_op_ctrl;
        mem_to_reg_idex <= mem_to_reg_ctrl;
        jal_idex <= jal_ctrl;
    end
end

// =========================================================================
// STAGE 3: EX (EXECUTE)
// =========================================================================
// This stage does the actual calculation

reg [31:0] alu_in1, alu_in2;  // ALU inputs
reg [31:0] alu_result;         // ALU output

wire [31:0] wb_data = (mem_to_reg_memwb) ? mem_wb_mem_data : mem_wb_alu_result;

// --- Forwarding Control (avoid data hazards) ---
// If newer instruction needs data from older instruction that's still
// in pipeline, forward the data instead of waiting
wire [1:0] fwd_a = (reg_write_exmem && ex_mem_rd != 0 && ex_mem_rd == id_ex_rs1) ? 2'b01 :
                  (reg_write_memwb && mem_wb_rd != 0 && mem_wb_rd == id_ex_rs1) ? 2'b10 : 2'b00;
                  
wire [1:0] fwd_b = (reg_write_exmem && ex_mem_rd != 0 && ex_mem_rd == id_ex_rs2) ? 2'b01 :
                  (reg_write_memwb && mem_wb_rd != 0 && mem_wb_rd == id_ex_rs2) ? 2'b10 : 2'b00;

// --- Select ALU Input 1 (with forwarding) ---
always @(*) begin
    case(fwd_a)
        2'b01: alu_in1 = ex_mem_alu_result;  // Forward from EX/MEM stage
        2'b10: alu_in1 = wb_data;            // Forward from MEM/WB stage
        default: alu_in1 = id_ex_rd1;        // Use normal register value
    endcase
end

// --- Select ALU Input 2 (with forwarding + immediate) ---
always @(*) begin
    if (alu_src_idex) begin
        // Use immediate value (for ADDI, Load, Store)
        alu_in2 = id_ex_imm;
    end else begin
        // Use register value (with forwarding)
        case(fwd_b)
            2'b01: alu_in2 = ex_mem_alu_result;  // Forward from EX/MEM
            2'b10: alu_in2 = wb_data;            // Forward from MEM/WB
            default: alu_in2 = id_ex_rd2;        // Normal register value
        endcase
    end
end

// --- ALU (Arithmetic Logic Unit) - The Calculator ---
always @(*) begin
    case(alu_op_idex)
        4'b0000: alu_result = alu_in1 + alu_in2;          // ADD
        4'b0001: alu_result = alu_in1 - alu_in2;          // SUBTRACT
        4'b0010: alu_result = alu_in1 << alu_in2[4:0];    // SHIFT LEFT
        4'b0011: alu_result = alu_in1 & alu_in2;          // AND
        4'b0100: alu_result = alu_in1 | alu_in2;          // OR
        4'b0101: alu_result = alu_in1 ^ alu_in2;          // XOR
        default: alu_result = 0;                          // Invalid
    endcase
end

// --- Forward rs2 for Store instructions ---
reg [31:0] forwarded_rd2;
always @(*) begin
    case(fwd_b)
        2'b01: forwarded_rd2 = ex_mem_alu_result;
        2'b10: forwarded_rd2 = wb_data;
        default: forwarded_rd2 = id_ex_rd2;
    endcase
end

// --- EX/MEM Pipeline Register Update ---
always @(posedge clk) begin
    if (reset) begin
        ex_mem_alu_result <= 0; ex_mem_rd2 <= 0; ex_mem_rd <= 0;
        reg_write_exmem <= 0; mem_read_exmem <= 0; mem_write_exmem <= 0;
        mem_to_reg_exmem <= 0; jal_exmem <= 0;
    end else begin
        // For JAL: save return address (PC+4)
        ex_mem_alu_result <= (jal_idex) ? (id_ex_pc + 4) : alu_result;
        
        ex_mem_rd2 <= forwarded_rd2;
        ex_mem_rd <= id_ex_rd;
        reg_write_exmem <= reg_write_idex;
        mem_read_exmem <= mem_read_idex;
        mem_write_exmem <= mem_write_idex;
        mem_to_reg_exmem <= mem_to_reg_idex;
        jal_exmem <= jal_idex;
    end
end

// =========================================================================
// STAGE 4: MEM (MEMORY ACCESS)
// =========================================================================
// This stage reads from or writes to data memory

always @(posedge clk) begin
    if (reset) begin
        mem_wb_mem_data <= 0; mem_wb_alu_result <= 0; mem_wb_rd <= 0;
        reg_write_memwb <= 0; mem_to_reg_memwb <= 0; jal_memwb <= 0;
    end else begin
        // --- READ from Memory (LOAD instruction) ---
        if (mem_read_exmem) begin
            mem_wb_mem_data <= data_mem[ex_mem_alu_result[9:2]];
        end else begin
            mem_wb_mem_data <= 0;
        end

        // --- WRITE to Memory (STORE instruction) ---
        if (mem_write_exmem) begin
            data_mem[ex_mem_alu_result[9:2]] <= ex_mem_rd2;
        end

        // Pass data to next stage
        mem_wb_alu_result <= ex_mem_alu_result;
        mem_wb_rd <= ex_mem_rd;
        reg_write_memwb <= reg_write_exmem;
        mem_to_reg_memwb <= mem_to_reg_exmem;
        jal_memwb <= jal_exmem;
    end
end

// =========================================================================
// STAGE 5: WB (WRITE BACK)
// =========================================================================
// This stage writes the final result back to the register file

always @(posedge clk) begin
    if (reset) begin
        for (i = 0; i < 32; i = i + 1) regs[i] <= 0;
    end else begin
        if (reg_write_memwb && mem_wb_rd != 0) begin
            // Write to register (except x0, which is always 0)
            if (mem_to_reg_memwb) 
                regs[mem_wb_rd] <= mem_wb_mem_data;  // Write memory data
            else 
                regs[mem_wb_rd] <= mem_wb_alu_result; // Write ALU result
        end
    end
end

endmodule
