`include "types.vh"

module FetchDecode (
    input   [31:0]  i_instr,
    output  [31:0]  o_imm,
    output  [3:0]   o_aluOp,
    output          o_exec_a, o_exec_b, o_mem_w, o_reg_w, o_mem2reg, o_bra, o_jmp
);
    ImmGen IMMGEN_unit(
        .i_instr    (i_instr),
        .o_imm      (o_imm)
    );
    Controller CTRL_unit(
        .i_opcode   (`OPCODE(i_instr)),
        .o_aluOp    (o_aluOp),
        .o_exec_a   (o_exec_a),
        .o_exec_b   (o_exec_b),
        .o_mem_w    (o_mem_w),
        .o_reg_w    (o_reg_w),
        .o_mem2reg  (o_mem2reg),
        .o_bra      (o_bra),
        .o_jmp      (o_jmp)
    );
endmodule
