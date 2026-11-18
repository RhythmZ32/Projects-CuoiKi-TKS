// ============================================================================
// 1. MODULE ALU (Số học, Logic, Shift & Cờ trạng thái ARM)
// ============================================================================
module alu (
    input  wire [31:0] A,
    input  wire [31:0] B,
    input  wire [2:0]  ALUControl,
    output reg  [31:0] Result,
    output wire [3:0]  ALUFlags // {N, Z, C, V}
);
    wire [32:0] sum;
    wire        sub_op = (ALUControl == 3'b001);
    
    assign sum = sub_op ? ({1'b0, A} + {1'b0, ~B} + 33'b1) : ({1'b0, A} + {1'b0, B});

    always @(*) begin
        case (ALUControl)
            3'b000: Result = A & B;             // AND
            3'b001: Result = sum[31:0];         // SUB / CMP
            3'b010: Result = sum[31:0];         // ADD
            3'b011: Result = A | B;             // ORR
            3'b100: Result = B;                 // MOV (Pass B)
            3'b101: Result = A ^ B;             // EOR (XOR)
            3'b110: Result = A << B[4:0];       // LSL (Logical Shift Left)
            3'b111: Result = A >> B[4:0];       // LSR (Logical Shift Right)
            default: Result = 32'b0;
        endcase
    end

    wire N = Result[31];
    wire Z = (Result == 32'b0);
    wire C = (ALUControl == 3'b010 || ALUControl == 3'b001) ? sum[32] : 1'b0;
    wire V = (ALUControl == 3'b010 || ALUControl == 3'b001) ? 
             (~(A[31] ^ B[31] ^ sub_op) & (A[31] ^ Result[31])) : 1'b0;

    assign ALUFlags = {N, Z, C, V};
endmodule

// ============================================================================
// 2. MODULE REGISTER FILE (16 x 32-bit Register File)
// ============================================================================
module regfile (
    input  wire        clk,
	 input  wire        reset,
    input  wire        we3,
    input  wire [3:0]  ra1,
    input  wire [3:0]  ra2,
    input  wire [3:0]  wa3,
    input  wire [31:0] wd3,
    input  wire [31:0] r15,
    output wire [31:0] rd1,
    output wire [31:0] rd2
);
    reg [31:0] rf [14:0];
    integer i;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 15; i = i + 1)
                rf[i] <= 32'b0;
        end else if (we3 && wa3 != 4'b1111) begin
            rf[wa3] <= wd3;
        end
    end

    assign rd1 = (ra1 == 4'b1111) ? r15 : rf[ra1];
    assign rd2 = (ra2 == 4'b1111) ? r15 : rf[ra2];
endmodule

// ============================================================================
// 3. MODULE EXTEND (Sign / Zero Extender cho Immediate)
// ============================================================================
module extend (
    input  wire [23:0] InstrImm,
    input  wire [1:0]  ImmSrc,
    output reg  [31:0] ExtImm
);
    always @(*) begin
        case (ImmSrc)
            2'b00: ExtImm = {24'b0, InstrImm[7:0]};                      // 8-bit Data Processing Imm
            2'b01: ExtImm = {20'b0, InstrImm[11:0]};                     // 12-bit Memory Offset
            2'b10: ExtImm = {{6{InstrImm[23]}}, InstrImm[23:0], 2'b00}; // 24-bit Branch Offset (sign-extended)
            default: ExtImm = 32'b0;
        endcase
    end
endmodule

// ============================================================================
// 4. MODULE CONDITION CHECK (Kiểm tra điều kiện rẽ nhánh ARM)
// ============================================================================
module condcheck (
    input  wire [3:0] Cond,
    input  wire [3:0] ALUFlags, // {N, Z, C, V}
    output reg        CondEx
);
    wire N = ALUFlags[3];
    wire Z = ALUFlags[2];
    wire C = ALUFlags[1];
    wire V = ALUFlags[0];

    always @(*) begin
        case (Cond)
            4'b0000: CondEx = Z;                  // EQ (Equal)
            4'b0001: CondEx = ~Z;                 // NE (Not Equal)
            4'b0010: CondEx = C;                  // CS / HS (Carry Set)
            4'b0011: CondEx = ~C;                 // CC / LO (Carry Clear)
            4'b0100: CondEx = N;                  // MI (Minus)
            4'b0101: CondEx = ~N;                 // PL (Plus)
            4'b0110: CondEx = V;                  // VS (Overflow)
            4'b0111: CondEx = ~V;                 // VC (No Overflow)
            4'b1000: CondEx = C & ~Z;             // HI (Unsigned Higher)
            4'b1001: CondEx = ~C | Z;             // LS (Unsigned Lower or Same)
            4'b1010: CondEx = ~(N ^ V);           // GE (Greater or Equal)
            4'b1011: CondEx = N ^ V;              // LT (Less Than)
            4'b1100: CondEx = ~Z & ~(N ^ V);      // GT (Greater Than)
            4'b1101: CondEx = Z | (N ^ V);       // LE (Less Than or Equal)
            4'b1110: CondEx = 1'b1;               // AL (Always)
            default: CondEx = 1'b0;
        endcase
    end
endmodule

// ============================================================================
// 5. MODULE DECODER (Giải mã bộ điều khiển)
// ============================================================================
module decoder (
    input  wire [1:0] Op,
    input  wire [5:0] Funct,
    input  wire [3:0] Rd,
    output reg        PCSrc,
    output reg        RegWrite,
    output reg        MemWrite,
    output reg        MemtoReg,
    output reg        ALUSrc,
    output reg  [1:0] RegSrc,
    output reg  [1:0] ImmSrc,
    output reg  [2:0] ALUControl,
    output reg        NoWrite,
    output reg        FlagWrite
);
    wire I = Funct[5];
    wire [3:0] ALUOp = Funct[4:1];
    wire S = Funct[0];

    always @(*) begin
        RegWrite  = 1'b0;
        MemWrite  = 1'b0;
        MemtoReg  = 1'b0;
        ALUSrc    = 1'b0;
        RegSrc    = 2'b00;
        ImmSrc    = 2'b00;
        PCSrc     = 1'b0;
        NoWrite   = 1'b0;
        FlagWrite = 1'b0;

        case (Op)
            2'b00: begin // Data Processing / Move / Shift
                ALUSrc = I;
                ImmSrc = 2'b00;
                RegSrc = 2'b00;

                if (ALUOp == 4'b1010) begin // CMP
                    NoWrite   = 1'b1;
                    RegWrite  = 1'b0;
                    FlagWrite = S;
                end else begin
                    NoWrite   = 1'b0;
                    RegWrite  = 1'b1;
                    FlagWrite = S;
                end

                if (Rd == 4'b1111 && RegWrite) PCSrc = 1'b1;
            end

            2'b01: begin // Memory (LDR / STR)
                ALUSrc = 1'b1;
                ImmSrc = 2'b01;
                if (Funct[0]) begin // LDR
                    RegWrite = 1'b1;
                    MemtoReg = 1'b1;
                    RegSrc   = 2'b00;
                    if (Rd == 4'b1111) PCSrc = 1'b1;
                end else begin // STR
                    RegWrite = 1'b0;
                    MemWrite = 1'b1;
                    RegSrc   = 2'b10;
                end
            end

            2'b10: begin // Branch (B / BEQ / BNE ...)
                RegWrite = 1'b0;
                MemWrite = 1'b0;
                PCSrc    = 1'b1;
                RegSrc   = 2'b01;
                ImmSrc   = 2'b10;
            end

            default: begin
                RegWrite = 1'b0;
                MemWrite = 1'b0;
            end
        endcase
    end

    always @(*) begin
        case (Op)
            2'b00: begin
                case (ALUOp)
                    4'b0000: ALUControl = 3'b000; // AND
                    4'b0010: ALUControl = 3'b001; // SUB
                    4'b0100: ALUControl = 3'b010; // ADD
                    4'b1010: ALUControl = 3'b001; // CMP (Dùng SUB)
                    4'b1100: ALUControl = 3'b011; // ORR
                    4'b1101: ALUControl = 3'b100; // MOV
                    4'b1110: ALUControl = 3'b110; // LSL
                    4'b1111: ALUControl = 3'b111; // LSR
                    default: ALUControl = 3'b010;
                endcase
            end
            2'b01: ALUControl = 3'b010; // LDR/STR
            2'b10: ALUControl = 3'b010; // Branch
            default: ALUControl = 3'b010;
        endcase
    end
endmodule

// ============================================================================
// 6. MODULE CONTROLLER (Khối điều khiển trung tâm)
// ============================================================================
module controller (
    input  wire        clk,
    input  wire        reset,
    input  wire [31:0] Instr,
    input  wire [3:0]  ALUFlags,
    output wire        PCSrc,
    output wire        RegWrite,
    output wire        MemWrite,
    output wire        MemtoReg,
    output wire        ALUSrc,
    output wire [1:0]  RegSrc,
    output wire [1:0]  ImmSrc,
    output wire [2:0]  ALUControl
);
    wire [1:0] Op    = Instr[27:26];
    wire [5:0] Funct = Instr[25:20];
    wire [3:0] Rd    = Instr[15:12];
    wire [3:0] Cond  = Instr[31:28];

    wire PCSrcD, RegWriteD, MemWriteD, NoWriteD, FlagWriteD;
    wire CondEx;
    reg  [3:0] Flags;

    decoder dec (
        .Op(Op),
        .Funct(Funct),
        .Rd(Rd),
        .PCSrc(PCSrcD),
        .RegWrite(RegWriteD),
        .MemWrite(MemWriteD),
        .MemtoReg(MemtoReg),
        .ALUSrc(ALUSrc),
        .RegSrc(RegSrc),
        .ImmSrc(ImmSrc),
        .ALUControl(ALUControl),
        .NoWrite(NoWriteD),
        .FlagWrite(FlagWriteD)
    );

    condcheck cc (
        .Cond(Cond),
        .ALUFlags(Flags),
        .CondEx(CondEx)
    );

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            Flags <= 4'b0000;
        end else if (FlagWriteD && CondEx) begin
            Flags <= ALUFlags;
        end
    end

    assign PCSrc    = PCSrcD & CondEx;
    assign RegWrite = RegWriteD & CondEx & ~NoWriteD;
    assign MemWrite = MemWriteD & CondEx;
endmodule

// ============================================================================
// 7. MODULE DATAPATH (Đường dữ liệu ARM)
// ============================================================================
module datapath (
    input  wire        clk,
    input  wire        reset,
    input  wire [1:0]  RegSrc,
    input  wire        RegWrite,
    input  wire [1:0]  ImmSrc,
    input  wire        ALUSrc,
    input  wire [2:0]  ALUControl,
    input  wire        MemtoReg,
    input  wire        PCSrc,
    input  wire [31:0] Instr,
    input  wire [31:0] ReadData,
    output reg  [31:0] PC,
    output wire [31:0] ALUResult,
    output wire [31:0] WriteData,
    output wire [3:0]  ALUFlags
);
    wire [31:0] PCNext, PCPlus4, PCPlus8;
    wire [31:0] ExtImm;
    wire [31:0] SrcA, SrcB, Result;
    wire [3:0]  RA1, RA2;

    assign PCPlus4 = PC + 32'd4;
    assign PCPlus8 = PCPlus4 + 32'd4;
    assign PCNext  = PCSrc ? Result : PCPlus4;

    always @(posedge clk or posedge reset) begin
        if (reset)
            PC <= 32'b0;
        else
            PC <= PCNext;
    end

    assign RA1 = RegSrc[0] ? 4'b1111 : Instr[19:16];
    assign RA2 = RegSrc[1] ? Instr[15:12] : Instr[3:0];

    regfile rf (
        .clk(clk),
        .we3(RegWrite),
        .ra1(RA1),
        .ra2(RA2),
        .wa3(Instr[15:12]),
        .wd3(Result),
        .r15(PCPlus8),
        .rd1(SrcA),
        .rd2(WriteData)
    );

    extend ext (
        .InstrImm(Instr[23:0]),
        .ImmSrc(ImmSrc),
        .ExtImm(ExtImm)
    );

    assign SrcB = ALUSrc ? ExtImm : WriteData;

    alu alu_inst (
        .A(SrcA),
        .B(SrcB),
        .ALUControl(ALUControl),
        .Result(ALUResult),
        .ALUFlags(ALUFlags)
    );

    assign Result = MemtoReg ? ReadData : ALUResult;
endmodule

// ============================================================================
// 8. MODULE ARM CORE (Bộ vi xử lý ARM Single-Cycle)
// ============================================================================
module arm (
    input  wire        clk,
    input  wire        reset,
    output wire [31:0] PC,
    input  wire [31:0] Instr,
    output wire        MemWrite,
    output wire [31:0] ALUResult,
    output wire [31:0] WriteData,
    input  wire [31:0] ReadData
);
    wire        PCSrc, RegWrite, MemtoReg, ALUSrc;
    wire [1:0]  RegSrc, ImmSrc;
    wire [2:0]  ALUControl;
    wire [3:0]  ALUFlags;

    controller c (
        .clk(clk),
        .reset(reset),
        .Instr(Instr),
        .ALUFlags(ALUFlags),
        .PCSrc(PCSrc),
        .RegWrite(RegWrite),
        .MemWrite(MemWrite),
        .MemtoReg(MemtoReg),
        .ALUSrc(ALUSrc),
        .RegSrc(RegSrc),
        .ImmSrc(ImmSrc),
        .ALUControl(ALUControl)
    );

    datapath dp (
        .clk(clk),
        .reset(reset),
        .RegSrc(RegSrc),
        .RegWrite(RegWrite),
        .ImmSrc(ImmSrc),
        .ALUSrc(ALUSrc),
        .ALUControl(ALUControl),
        .MemtoReg(MemtoReg),
        .PCSrc(PCSrc),
        .Instr(Instr),
        .ReadData(ReadData),
        .PC(PC),
        .ALUResult(ALUResult),
        .WriteData(WriteData),
        .ALUFlags(ALUFlags)
    );
endmodule

// ============================================================================
// MODULE INSTRUCTION MEMORY (Bộ nhớ lệnh IMEM)
// ============================================================================
module imem (
    input  wire [31:0] a,
    output wire [31:0] rd
);
    reg [31:0] RAM [63:0];
    integer i;

    initial begin
        // Khởi tạo toàn bộ bộ nhớ bằng lệnh NOP (MOV R0, R0) để tránh rác X
        for (i = 0; i < 64; i = i + 1)
            RAM[i] = 32'hE1A00000; 

        // Tập lệnh kiểm thử ARM 32-bit:
        RAM[0]  = 32'hE3A00005; // PC = 0  : MOV R0, #5
        RAM[1]  = 32'hE3A0100C; // PC = 4  : MOV R1, #12
        RAM[2]  = 32'hE0802001; // PC = 8  : ADD R2, R0, R1 (R2 = 17)
        RAM[3]  = 32'hE0413000; // PC = 12 : SUB R3, R1, R0 (R3 = 7)
        RAM[4]  = 32'hE5802004; // PC = 16 : STR R2, [R0, #4] (Ghi 17 vào ô 9)
        RAM[5]  = 32'hE5904004; // PC = 20 : LDR R4, [R0, #4] (Đọc 17 vào R4)
        RAM[6]  = 32'hE1540002; // PC = 24 : CMP R4, R2
        RAM[7]  = 32'h0A000000; // PC = 28 : BEQ (Nhảy qua lệnh kế tiếp)
        RAM[8]  = 32'hE3A050AA; // PC = 32 : MOV R5, #170 (Bị nhảy qua)
        RAM[9]  = 32'hE3A050FF; // PC = 36 : MOV R5, #255
    end

    assign rd = RAM[a[31:2]];
endmodule

// ============================================================================
// MODULE DATA MEMORY (Bộ nhớ dữ liệu DMEM)
// ============================================================================
module dmem (
    input  wire        clk,
    input  wire        we,
    input  wire [31:0] a,
    input  wire [31:0] wd,
    output wire [31:0] rd
);
    reg [31:0] RAM [63:0];
    integer i;

    initial begin
        for (i = 0; i < 64; i = i + 1)
            RAM[i] = 32'b0;
    end

    assign rd = RAM[a[31:2]];

    always @(posedge clk) begin
        if (we)
            RAM[a[31:2]] <= wd;
    end
endmodule

// ============================================================================
// 11. MODULE TOP (Kết nối Vi xử lý với Bộ nhớ)
// ============================================================================
module top (
    input  wire        clk,
    input  wire        reset,
    output wire [31:0] WriteData,
    output wire [31:0] DataAdr,
    output wire        MemWrite
);
    wire [31:0] PC, Instr, ReadData;

    arm arm_inst (
        .clk(clk),
        .reset(reset),
        .PC(PC),
        .Instr(Instr),
        .MemWrite(MemWrite),
        .ALUResult(DataAdr),
        .WriteData(WriteData),
        .ReadData(ReadData)
    );

    imem imem_inst (
        .a(PC),
        .rd(Instr)
    );

    dmem dmem_inst (
        .clk(clk),
        .we(MemWrite),
        .a(DataAdr),
        .wd(WriteData),
        .rd(ReadData)
    );
endmodule
