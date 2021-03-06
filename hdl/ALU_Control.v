`include "types.vh"

module ALU_Control (
    input       [3:0] i_aluOp,
    input       [6:0] i_funct7,
    input       [2:0] i_funct3,
    output reg  [4:0] o_aluControl
);
    localparam SRAI = 5;
    always @* begin
        case (i_aluOp)
            // ~~~ U/J-Type formats ~~~
            `ALU_OP_J           : o_aluControl = `OP_ADD4A;
            `ALU_OP_U_LUI       : o_aluControl = `OP_PASSB;
            `ALU_OP_U_AUIPC     : o_aluControl = `OP_ADD;
            // ~~~ I/S/B-Type formats ~~~
            `ALU_OP_S           : o_aluControl = `OP_ADD;
            `ALU_OP_I_SYS       : o_aluControl = `OP_ADD;
            `ALU_OP_I_LOAD      : o_aluControl = `OP_ADD;
            `ALU_OP_I_JUMP      : o_aluControl = `OP_ADD4A;
            `ALU_OP_I_FENCE     : o_aluControl = `OP_ADD;
            `ALU_OP_B           : case (i_funct3)
                3'b000          : o_aluControl = `OP_EQ;
                3'b001          : o_aluControl = `OP_NEQ;
                3'b100          : o_aluControl = `OP_SLT;
                3'b101          : o_aluControl = `OP_SGTE;
                3'b110          : o_aluControl = `OP_SLTU;
                3'b111          : o_aluControl = `OP_SGTEU;
                default         : o_aluControl = 5'b00000;
            endcase
            `ALU_OP_I_ARITH     : case (i_funct3)
                3'b000          : o_aluControl = `OP_ADD;
                3'b010          : o_aluControl = `OP_SLT;
                3'b011          : o_aluControl = `OP_SLTU;
                3'b100          : o_aluControl = `OP_XOR;
                3'b110          : o_aluControl = `OP_OR;
                3'b111          : o_aluControl = `OP_AND;
                3'b001          : o_aluControl = `OP_SLL;
                3'b101          : o_aluControl =  i_funct7[SRAI] ? `OP_SRA : `OP_SRL;
                default         : o_aluControl = 5'b00000;
            endcase
            // ~~~ R-Type format ~~~
            default             : case ({i_funct7, i_funct3})
                10'b0000000_000 : o_aluControl = `OP_ADD;
                10'b0100000_000 : o_aluControl = `OP_SUB;
                10'b0000000_001 : o_aluControl = `OP_SLL;
                10'b0000000_010 : o_aluControl = `OP_SLT;
                10'b0000000_011 : o_aluControl = `OP_SLTU;
                10'b0000000_100 : o_aluControl = `OP_XOR;
                10'b0000000_101 : o_aluControl = `OP_SRL;
                10'b0100000_101 : o_aluControl = `OP_SRA;
                10'b0000000_110 : o_aluControl = `OP_OR;
                10'b0000000_111 : o_aluControl = `OP_AND;
                default         : o_aluControl = 5'b00000;
            endcase
        endcase
    end
endmodule
