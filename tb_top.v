// ============================================================================
// 12. TESTBENCH MÔ PHỎNG
// ============================================================================
`timescale 1ns / 1ps

module tb_top;
    reg         clk;
    reg         reset;
    wire [31:0] WriteData;
    wire [31:0] DataAdr;
    wire        MemWrite;

    // Khởi tạo Top Module
    top uut (
        .clk(clk),
        .reset(reset),
        .WriteData(WriteData),
        .DataAdr(DataAdr),
        .MemWrite(MemWrite)
    );

    // Tạo Xung Clock chu kỳ 10ns (100 MHz)
    always #5 clk = ~clk;

    initial begin
        $display("=========================================================");
        $display("   BAT DAU MO PHONG BOH VI XU LY ARM 32-BIT SINGLE CYCLE  ");
        $display("=========================================================");
        
        clk = 0;
        reset = 1;
        #12;
        reset = 0;

        // Chạy qua 15 chu kỳ clock để hoàn tất tập lệnh mẫu
        repeat (15) @(posedge clk);

        $display("=========================================================");
        $display("                   MO PHONG HOAN THANH                   ");
        $display("=========================================================");
        $finish;
    end

    // Theo dõi kết quả ngõ ra sau mỗi sườn xuống của Clock
    always @(negedge clk) begin
        if (!reset) begin
            $display("Time: %4t ns | PC: 0x%h | MemWrite: %b | DataAdr: 0x%h | WriteData: 0x%h",
                     $time, uut.PC, MemWrite, DataAdr, WriteData);
        end
    end
endmodule
