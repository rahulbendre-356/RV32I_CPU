`timescale 1ns / 1ps

// Simple testbench for RISC-V CPU - Beginner Level
module tb_CPU_simple;

// ============================================
// Step 1: Declare signals to connect to CPU
// ============================================
reg clk;              // Clock signal (we control this)
reg reset;            // Reset signal (we control this)
wire [31:0] debug_pc; // Program Counter (CPU outputs this)

// ============================================
// Step 2: Create the CPU instance
// ============================================
CPU_Top cpu (
    .clk(clk),
    .reset(reset),
    .debug_pc(debug_pc)
);

// ============================================
// Step 3: Generate Clock Signal
// ============================================
// Start with clock = 0
initial clk = 0;

// Toggle clock every 5ns (creates 10ns period = 100MHz)
always #5 clk = ~clk;

// ============================================
// Step 4: Apply Reset Signal
// ============================================
initial begin
    // Hold reset HIGH for 20ns
    reset = 1;
    #20;
    
    // Release reset (set to LOW)
    reset = 0;
    
    // Print a message
    $display("\n>>> CPU Reset Complete! Starting execution...\n");
end

// ============================================
// Step 5: Monitor CPU Execution
// ============================================
initial begin
    // Wait for reset to finish
    #25;
    
    // Print header
    $display("Time\t\tPC\t\tx1\tx2\tx3\tx4");
    $display("================================================");
    
    // Run for 20 clock cycles and print register values
    repeat(20) begin
        @(posedge clk);  // Wait for clock edge
        #2;              // Small delay for values to settle
        
        // Print current state
        $display("%0t\t\t%h\t%0d\t%0d\t%0d\t%0d", 
                 $time,           // Current simulation time
                 debug_pc,        // Program Counter value
                 cpu.regs[1],     // Register x1 value
                 cpu.regs[2],     // Register x2 value
                 cpu.regs[3],     // Register x3 value
                 cpu.regs[4]);    // Register x4 value
    end
    
    // ============================================
    // Step 6: Display Final Results
    // ============================================
    $display("\n=== Final Register Values ===");
    $display("x1 = %0d", cpu.regs[1]);
    $display("x2 = %0d", cpu.regs[2]);
    $display("x3 = %0d", cpu.regs[3]);
    $display("x4 = %0d", cpu.regs[4]);
    $display("x5 = %0d", cpu.regs[5]);
    $display("x6 = %0d", cpu.regs[6]);
    $display("x7 = %0d", cpu.regs[7]);
    $display("x8 = %0d", cpu.regs[8]);
    $display("x9 = %0d", cpu.regs[9]);
    
    $display("\n>>> Simulation Complete!\n");
    
    // End simulation
    $finish;
end

// ============================================
// Step 7: Safety - Stop if simulation runs too long
// ============================================
initial begin
    #5000;  // Wait 5000ns
    $display("\n>>> ERROR: Simulation timeout!");
    $finish;
end

endmodule
