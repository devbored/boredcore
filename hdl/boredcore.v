`include "types.vh"

module boredcore (
    input           i_clk, i_rst, i_ifValid, i_memValid,
    input   [31:0]  i_instr, i_dataIn,
    output          o_dataWe,
    output  [31:0]  o_pcOut, o_dataAddr, o_dataOut
);
    localparam  [4:0] REG_0 = 5'b00000; // Register x0

    // Pipeline regs (p_*)
    localparam  EXEC = 0;
    localparam  MEM  = 1;
    localparam  WB   = 2;
    reg [31:0]  p_rs1       [EXEC:WB];
    reg [31:0]  p_rs2       [EXEC:WB];
    reg [31:0]  p_aluOut    [EXEC:WB];
    reg [31:0]  p_readData  [EXEC:WB];
    reg [31:0]  p_PC        [EXEC:WB];
    reg [31:0]  p_IMM       [EXEC:WB];
    reg  [6:0]  p_funct7    [EXEC:WB];
    reg  [4:0]  p_rs1Addr   [EXEC:WB];
    reg  [4:0]  p_rs2Addr   [EXEC:WB];
    reg  [4:0]  p_rdAddr    [EXEC:WB];
    reg  [3:0]  p_aluOp     [EXEC:WB];
    reg  [2:0]  p_funct3    [EXEC:WB];
    reg         p_mem_w     [EXEC:WB];
    reg         p_reg_w     [EXEC:WB];
    reg         p_mem2reg   [EXEC:WB];
    reg         p_exec_a    [EXEC:WB];
    reg         p_exec_b    [EXEC:WB];
    reg         p_bra       [EXEC:WB];
    reg         p_jmp       [EXEC:WB];
    // Internal wires/regs
    reg     [31:0]  PC, PCReg, instrReg;
    wire    [31:0]  IMM, aluOut, jumpAddr, loadData, rs1Out, rs2Out;
    wire     [3:0]  aluOp;
    wire     [1:0]  fwdRs1, fwdRs2;
    wire            exec_a, exec_b, mem_w, reg_w, mem2reg, bra, jmp, FETCH_stall, EXEC_stall, EXEC_flush, MEM_flush;
    wire    [31:0]  WB_result       = p_mem2reg[WB] ? loadData : p_aluOut[WB];
    wire            braMispredict   = p_bra[EXEC] && aluOut[0];                 // Assume branch not-taken
    wire            writeRd         = `RD(instrReg) != REG_0 ? reg_w : 1'b0;    // Skip regfile write for x0
    wire            pcJump          = braMispredict || p_jmp[EXEC];
    wire            rs1R0           = `RS1(instrReg) == REG_0;
    wire            rs2R0           = `RS2(instrReg) == REG_0;

    // Core submodules
    FetchDecode FETCH_DECODE_unit(
        .i_instr              (instrReg),
        .o_imm                (IMM),
        .o_aluOp              (aluOp),
        .o_exec_a             (exec_a),
        .o_exec_b             (exec_b),
        .o_mem_w              (mem_w),
        .o_reg_w              (reg_w),
        .o_mem2reg            (mem2reg),
        .o_bra                (bra),
        .o_jmp                (jmp)
    );
    Execute EXECUTE_unit(
        .i_funct7             (p_funct7[EXEC]),
        .i_funct3             (p_funct3[EXEC]),
        .i_aluOp              (p_aluOp[EXEC]),
        .i_fwdRs1             (fwdRs1),
        .i_fwdRs2             (fwdRs2),
        .i_aluSrcA            (p_exec_a[EXEC]),
        .i_aluSrcB            (p_exec_b[EXEC]),
        .i_EXEC_rs1           (p_rs1[EXEC]),
        .i_EXEC_rs2           (p_rs2[EXEC]),
        .i_MEM_rd             (p_aluOut[MEM]),
        .i_WB_rd              (WB_result),
        .i_PC                 (p_PC[EXEC]),
        .i_IMM                (p_IMM[EXEC]),
        .o_aluOut             (aluOut),
        .o_addrGenOut         (jumpAddr)
    );
    Memory MEMORY_unit(
        .i_funct3             (p_funct3[MEM]),
        .i_dataIn             (p_rs2[MEM]),
        .o_dataOut            (o_dataOut)
    );
    Writeback WRITEBACK_unit(
        .i_funct3             (p_funct3[WB]),
        .i_dataIn             (p_readData[WB]),
        .o_dataOut            (loadData)
    );
    Hazard HZD_FWD_unit(
        // Forwarding
        .i_MEM_rd_reg_write   (p_reg_w[MEM]),
        .i_WB_rd_reg_write    (p_reg_w[WB]),
        .i_EXEC_rs1           (p_rs1Addr[EXEC]),
        .i_EXEC_rs2           (p_rs2Addr[EXEC]),
        .i_MEM_rd             (p_rdAddr[MEM]),
        .i_WB_rd              (p_rdAddr[WB]),
        .o_FWD_rs1            (fwdRs1),
        .o_FWD_rs2            (fwdRs2),
        // Stall and Flush
        .i_BRA                (braMispredict),
        .i_JMP                (p_jmp[EXEC]),
        .i_FETCH_valid        (i_ifValid),
        .i_MEM_valid          (i_memValid),
        .i_EXEC_mem2reg       (p_mem2reg[EXEC]),
        .i_FETCH_rs1          (`RS1(instrReg)),
        .i_FETCH_rs2          (`RS2(instrReg)),
        .i_EXEC_rd            (p_rdAddr[EXEC]),
        .o_FETCH_stall        (FETCH_stall),
        .o_EXEC_stall         (EXEC_stall),
        .o_EXEC_flush         (EXEC_flush),
        .o_MEM_flush          (MEM_flush)
    );
    Regfile #(.DATA_WIDTH(32), .ADDR_WIDTH(5)) REGFILE_unit (
        .i_clk      (i_clk),
        .i_wrEn     (p_reg_w[WB]),
        .i_rs1Addr  (`RS1(i_instr)),
        .i_rs2Addr  (`RS2(i_instr)),
        .i_rdAddr   (p_rdAddr[WB]),
        .i_rdData   (WB_result),
        .o_rs1Data  (rs1Out),
        .o_rs2Data  (rs2Out)
    );

    // Pipeline assignments
    always @(posedge i_clk) begin
        // --- Execute ---
        p_rs1      [EXEC]  <= i_rst || EXEC_flush || rs1R0 ? 32'd0 : EXEC_stall ? p_rs1     [EXEC] : rs1Out;
        p_rs2      [EXEC]  <= i_rst || EXEC_flush || rs2R0 ? 32'd0 : EXEC_stall ? p_rs2     [EXEC] : rs2Out;
        p_IMM      [EXEC]  <= i_rst || EXEC_flush ?          32'd0 : EXEC_stall ? p_IMM     [EXEC] : IMM;
        p_PC       [EXEC]  <= i_rst || EXEC_flush ?          32'd0 : EXEC_stall ? p_PC      [EXEC] : PCReg;
        p_funct7   [EXEC]  <= i_rst || EXEC_flush ?           7'd0 : EXEC_stall ? p_funct7  [EXEC] : `FUNCT7(instrReg);
        p_rdAddr   [EXEC]  <= i_rst || EXEC_flush ?           5'd0 : EXEC_stall ? p_rdAddr  [EXEC] : `RD(instrReg);
        p_rs1Addr  [EXEC]  <= i_rst || EXEC_flush ?           5'd0 : EXEC_stall ? p_rs1Addr [EXEC] : `RS1(instrReg);
        p_aluOp    [EXEC]  <= i_rst || EXEC_flush ?           4'd0 : EXEC_stall ? p_aluOp   [EXEC] : aluOp;
        p_rs2Addr  [EXEC]  <= i_rst || EXEC_flush ?           5'd0 : EXEC_stall ? p_rs2Addr [EXEC] : `RS2(instrReg);
        p_funct3   [EXEC]  <= i_rst || EXEC_flush ?           3'd0 : EXEC_stall ? p_funct3  [EXEC] : `FUNCT3(instrReg);
        p_mem_w    [EXEC]  <= i_rst || EXEC_flush ?           1'd0 : EXEC_stall ? p_mem_w   [EXEC] : mem_w;
        p_reg_w    [EXEC]  <= i_rst || EXEC_flush ?           1'd0 : EXEC_stall ? p_reg_w   [EXEC] : writeRd;
        p_mem2reg  [EXEC]  <= i_rst || EXEC_flush ?           1'd0 : EXEC_stall ? p_mem2reg [EXEC] : mem2reg;
        p_exec_a   [EXEC]  <= i_rst || EXEC_flush ?           1'd0 : EXEC_stall ? p_exec_a  [EXEC] : exec_a;
        p_exec_b   [EXEC]  <= i_rst || EXEC_flush ?           1'd0 : EXEC_stall ? p_exec_b  [EXEC] : exec_b;
        p_bra      [EXEC]  <= i_rst || EXEC_flush ?           1'd0 : EXEC_stall ? p_bra     [EXEC] : bra;
        p_jmp      [EXEC]  <= i_rst || EXEC_flush ?           1'd0 : EXEC_stall ? p_jmp     [EXEC] : jmp;
        // --- Memory ---
        p_mem_w    [MEM]   <= i_rst || MEM_flush ?  1'd0 : p_mem_w   [EXEC];
        p_reg_w    [MEM]   <= i_rst || MEM_flush ?  1'd0 : p_reg_w   [EXEC];
        p_mem2reg  [MEM]   <= i_rst || MEM_flush ?  1'd0 : p_mem2reg [EXEC];
        p_funct3   [MEM]   <= i_rst || MEM_flush ?  3'd0 : p_funct3  [EXEC];
        p_rs2      [MEM]   <= i_rst || MEM_flush ? 32'd0 : p_rs2     [EXEC];
        p_rdAddr   [MEM]   <= i_rst || MEM_flush ?  5'd0 : p_rdAddr  [EXEC];
        p_aluOut   [MEM]   <= i_rst || MEM_flush ? 32'd0 : aluOut;
        // --- Writeback ---
        p_reg_w    [WB]    <= i_rst ? 1'd0   : p_reg_w   [MEM];
        p_mem2reg  [WB]    <= i_rst ? 1'd0   : p_mem2reg [MEM];
        p_funct3   [WB]    <= i_rst ? 3'd0   : p_funct3  [MEM];
        p_aluOut   [WB]    <= i_rst ? 32'd0  : p_aluOut  [MEM];
        p_rdAddr   [WB]    <= i_rst ? 5'd0   : p_rdAddr  [MEM];
        p_readData [WB]    <= i_rst ? 32'd0  : i_dataIn;
    end

    always @(posedge i_clk) begin
        PC          <=  i_rst               ?   32'd0       :
                        FETCH_stall         ?   PC          :
                        pcJump              ?   jumpAddr    :
                                                PC + 32'd4;
        // Buffer PC reg to balance the 1cc BRAM-based regfile read
        PCReg       <=  i_rst || EXEC_flush ?   32'd0       :
                        FETCH_stall         ?   PCReg       :
                                                PC;
        // Buffer instruction fetch to balance the 1cc BRAM-based regfile read
        instrReg    <=  i_rst || EXEC_flush ?   32'd0       :
                        FETCH_stall         ?   instrReg    :
                                                i_instr;
    end
    assign o_pcOut    = PC;
    assign o_dataAddr = p_aluOut[MEM];
    assign o_dataWe   = p_mem_w[MEM];

endmodule
