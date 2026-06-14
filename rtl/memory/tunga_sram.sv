`timescale 1ns / 1ps

module tunga_sram #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 12 // 4KB Bellek (2^12)
)(
    input  logic                    clk_i,
    input  logic                    rst_ni,

    // OBI (Open Bus Interface) Slave Arayüzü
    input  logic                    req_i,
    output logic                    gnt_o,
    input  logic [31:0]             addr_i,
    input  logic                    we_i,
    input  logic [3:0]              be_i,
    input  logic [DATA_WIDTH-1:0]   wdata_i,
    output logic                    rvalid_o,
    output logic [DATA_WIDTH-1:0]   rdata_o
);

    // Bellek Dizisi (Memory Array)
    logic [DATA_WIDTH-1:0] mem_array [0:(1<<ADDR_WIDTH)-1];
    
    // OBI Grant ve Valid Sinyalleri (Her isteğe 1 cycle sonra cevap ver)
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rvalid_o <= 1'b0;
        end else begin
            rvalid_o <= req_i; // Okuma veya yazma isteği varsa bir sonraki saat vuruşunda geçerli (valid) yap
        end
    end

    // Her isteği anında kabul et (Grant)
    assign gnt_o = req_i;

    // 32-bit word hizalaması için adresi kaydır
    wire [ADDR_WIDTH-1:0] word_addr = addr_i[ADDR_WIDTH+1:2]; 

    always_ff @(posedge clk_i) begin
        if (req_i) begin
            if (we_i) begin
                // Yazma İşlemi (Byte Enable Desteği)
                if (be_i[0]) mem_array[word_addr][7:0]   <= wdata_i[7:0];
                if (be_i[1]) mem_array[word_addr][15:8]  <= wdata_i[15:8];
                if (be_i[2]) mem_array[word_addr][23:16] <= wdata_i[23:16];
                if (be_i[3]) mem_array[word_addr][31:24] <= wdata_i[31:24];
            end else begin
                // Okuma İşlemi
                rdata_o <= mem_array[word_addr];
            end
        end
    end

    // İşlemci boot olduğunda boşluğa düşmesin diye her yeri NOP (0x00000013) ile doldur
    initial begin
        for (int i = 0; i < (1<<ADDR_WIDTH); i++) begin
            mem_array[i] = 32'h00000013; 
        end
    end

endmodule