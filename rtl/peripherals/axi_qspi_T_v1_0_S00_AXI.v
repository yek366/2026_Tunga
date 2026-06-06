
`timescale 1 ns / 1 ps

	module axi_qspi_T_v1_0_S00_AXI #
	(
		// Users to add parameters here

		// User parameters ends
		// Do not modify the parameters beyond this line

		// Width of S_AXI data bus
		parameter integer C_S_AXI_DATA_WIDTH	= 32,
		// Width of S_AXI address bus
		parameter integer C_S_AXI_ADDR_WIDTH	= 4
	)
	(
// Users to add ports here
    output wire SCLK_pad,
    output wire CS_pad,
    
    // Üst katmandaki IOBUF'lara gidecek olan ayrıştırılmış sinyaller
    output wire [3:0] dq_o,
    input  wire [3:0] dq_i,
    output wire [3:0] dq_oe,
    // User ports ends
		// Do not modify the ports beyond this line

		// Global Clock Signal
		input wire  S_AXI_ACLK,
		// Global Reset Signal. This Signal is Active LOW
		input wire  S_AXI_ARESETN,
		// Write address (issued by master, acceped by Slave)
		input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
		// Write channel Protection type. This signal indicates the
    		// privilege and security level of the transaction, and whether
    		// the transaction is a data access or an instruction access.
		input wire [2 : 0] S_AXI_AWPROT,
		// Write address valid. This signal indicates that the master signaling
    		// valid write address and control information.
		input wire  S_AXI_AWVALID,
		// Write address ready. This signal indicates that the slave is ready
    		// to accept an address and associated control signals.
		output wire  S_AXI_AWREADY,
		// Write data (issued by master, acceped by Slave) 
		input wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
		// Write strobes. This signal indicates which byte lanes hold
    		// valid data. There is one write strobe bit for each eight
    		// bits of the write data bus.    
		input wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
		// Write valid. This signal indicates that valid write
    		// data and strobes are available.
		input wire  S_AXI_WVALID,
		// Write ready. This signal indicates that the slave
    		// can accept the write data.
		output wire  S_AXI_WREADY,
		// Write response. This signal indicates the status
    		// of the write transaction.
		output wire [1 : 0] S_AXI_BRESP,
		// Write response valid. This signal indicates that the channel
    		// is signaling a valid write response.
		output wire  S_AXI_BVALID,
		// Response ready. This signal indicates that the master
    		// can accept a write response.
		input wire  S_AXI_BREADY,
		// Read address (issued by master, acceped by Slave)
		input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
		// Protection type. This signal indicates the privilege
    		// and security level of the transaction, and whether the
    		// transaction is a data access or an instruction access.
		input wire [2 : 0] S_AXI_ARPROT,
		// Read address valid. This signal indicates that the channel
    		// is signaling valid read address and control information.
		input wire  S_AXI_ARVALID,
		// Read address ready. This signal indicates that the slave is
    		// ready to accept an address and associated control signals.
		output wire  S_AXI_ARREADY,
		// Read data (issued by slave)
		output wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
		// Read response. This signal indicates the status of the
    		// read transfer.
		output wire [1 : 0] S_AXI_RRESP,
		// Read valid. This signal indicates that the channel is
    		// signaling the required read data.
		output wire  S_AXI_RVALID,
		// Read ready. This signal indicates that the master can
    		// accept the read data and response information.
		input wire  S_AXI_RREADY
	);

	// AXI4LITE signals
	reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_awaddr;
	reg  	axi_awready;
	reg  	axi_wready;
	reg [1 : 0] 	axi_bresp;
	reg  	axi_bvalid;
	reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_araddr;
	reg  	axi_arready;
	reg [C_S_AXI_DATA_WIDTH-1 : 0] 	axi_rdata;
	reg [1 : 0] 	axi_rresp;
	reg  	axi_rvalid;

	// Example-specific design signals
	// local parameter for addressing 32 bit / 64 bit C_S_AXI_DATA_WIDTH
	// ADDR_LSB is used for addressing 32/64 bit registers/memories
	// ADDR_LSB = 2 for 32 bits (n downto 2)
	// ADDR_LSB = 3 for 64 bits (n downto 3)
	localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;
	localparam integer OPT_MEM_ADDR_BITS = 1;
	//----------------------------------------------
	//-- Signals for user logic register space example
	 wire [31:0] rx_fifo_dout;
	 wire [31:0] hw_status_reg;
	 wire spi_busy;
	//------------------------------------------------
	//-- Number of Slave Registers 4
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg0;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg1;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg2;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg3;
	wire	 slv_reg_rden;
	wire	 slv_reg_wren;
	reg [C_S_AXI_DATA_WIDTH-1:0]	 reg_data_out;
	integer	 byte_index;
	reg	 aw_en;

	// I/O Connections assignments

	assign S_AXI_AWREADY	= axi_awready;
	assign S_AXI_WREADY	= axi_wready;
	assign S_AXI_BRESP	= axi_bresp;
	assign S_AXI_BVALID	= axi_bvalid;
	assign S_AXI_ARREADY	= axi_arready;
	assign S_AXI_RDATA	= axi_rdata;
	assign S_AXI_RRESP	= axi_rresp;
	assign S_AXI_RVALID	= axi_rvalid;
	// Implement axi_awready generation
	// axi_awready is asserted for one S_AXI_ACLK clock cycle when both
	// S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_awready is
	// de-asserted when reset is low.

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_awready <= 1'b0;
	      aw_en <= 1'b1;
	    end 
	  else
	    begin    
	      if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en)
	        begin
	          // slave is ready to accept write address when 
	          // there is a valid write address and write data
	          // on the write address and data bus. This design 
	          // expects no outstanding transactions. 
	          axi_awready <= 1'b1;
	          aw_en <= 1'b0;
	        end
	        else if (S_AXI_BREADY && axi_bvalid)
	            begin
	              aw_en <= 1'b1;
	              axi_awready <= 1'b0;
	            end
	      else           
	        begin
	          axi_awready <= 1'b0;
	        end
	    end 
	end       

	// Implement axi_awaddr latching
	// This process is used to latch the address when both 
	// S_AXI_AWVALID and S_AXI_WVALID are valid. 

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_awaddr <= 0;
	    end 
	  else
	    begin    
	      if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en)
	        begin
	          // Write Address latching 
	          axi_awaddr <= S_AXI_AWADDR;
	        end
	    end 
	end       

	// Implement axi_wready generation
	// axi_wready is asserted for one S_AXI_ACLK clock cycle when both
	// S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_wready is 
	// de-asserted when reset is low. 

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_wready <= 1'b0;
	    end 
	  else
	    begin    
	      if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID && aw_en )
	        begin
	          // slave is ready to accept write data when 
	          // there is a valid write address and write data
	          // on the write address and data bus. This design 
	          // expects no outstanding transactions. 
	          axi_wready <= 1'b1;
	        end
	      else
	        begin
	          axi_wready <= 1'b0;
	        end
	    end 
	end       

	// Implement memory mapped register select and write logic generation
	// The write data is accepted and written to memory mapped registers when
	// axi_awready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted. Write strobes are used to
	// select byte enables of slave registers while writing.
	// These registers are cleared when reset (active low) is applied.
	// Slave register write enable is asserted when valid address and data are available
	// and the slave is ready to accept the write address and write data.
	assign slv_reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;
// Adres 0x08 olduğunda (yani slv_reg2 seçildiğinde) FIFO'yu tetikle
    // NOT: 4-byte hizalamada 0x00=reg0, 0x04=reg1, 0x08=reg2'dir.
    wire is_addr_fifo = (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 2);
    
    // FIFO yazma sinyalini slv_reg_wren'e ve doğru adrese bağla
//    assign tx_fifo_wr_en = slv_reg_wren && is_addr_fifo;
    wire axi_write_to_fifo = S_AXI_WREADY && S_AXI_WVALID && (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS : ADDR_LSB] == 3'h2);

    assign tx_fifo_wr_en = axi_write_to_fifo;
    assign tx_fifo_din   = S_AXI_WDATA;
    
    // Veriyi direkt AXI veri yolundan (WDATA) al, aracı yazmaçta vakit kaybetme
    assign tx_fifo_din = S_AXI_WDATA;
    
	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      slv_reg0 <= 0;
	      slv_reg1 <= 0;
	      slv_reg2 <= 0;
	      slv_reg3 <= 0;
	    end 
	  else begin
	    if (slv_reg_wren)
	      begin
	        case ( axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] )
	          2'h0:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                // Respective byte enables are asserted as per write strobes 
	                // Slave register 0
	                slv_reg0[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end  
	          2'h1:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                // Respective byte enables are asserted as per write strobes 
	                // Slave register 1
	                slv_reg1[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end  
	          2'h2:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                // Respective byte enables are asserted as per write strobes 
	                // Slave register 2
	                slv_reg2[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end  
	          2'h3:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                // Respective byte enables are asserted as per write strobes 
	                // Slave register 3
	                slv_reg3[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end  
	          default : begin
	                      slv_reg0 <= slv_reg0;
	                      slv_reg1 <= slv_reg1;
	                      slv_reg2 <= slv_reg2;
	                      slv_reg3 <= slv_reg3;
	                    end
	        endcase
	      end
	  end
	end    

	// Implement write response logic generation
	// The write response and response valid signals are asserted by the slave 
	// when axi_wready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted.  
	// This marks the acceptance of address and indicates the status of 
	// write transaction.

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_bvalid  <= 0;
	      axi_bresp   <= 2'b0;
	    end 
	  else
	    begin    
	      if (axi_awready && S_AXI_AWVALID && ~axi_bvalid && axi_wready && S_AXI_WVALID)
	        begin
	          // indicates a valid write response is available
	          axi_bvalid <= 1'b1;
	          axi_bresp  <= 2'b0; // 'OKAY' response 
	        end                   // work error responses in future
	      else
	        begin
	          if (S_AXI_BREADY && axi_bvalid) 
	            //check if bready is asserted while bvalid is high) 
	            //(there is a possibility that bready is always asserted high)   
	            begin
	              axi_bvalid <= 1'b0; 
	            end  
	        end
	    end
	end   

	// Implement axi_arready generation
	// axi_arready is asserted for one S_AXI_ACLK clock cycle when
	// S_AXI_ARVALID is asserted. axi_awready is 
	// de-asserted when reset (active low) is asserted. 
	// The read address is also latched when S_AXI_ARVALID is 
	// asserted. axi_araddr is reset to zero on reset assertion.

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_arready <= 1'b0;
	      axi_araddr  <= 32'b0;
	    end 
	  else
	    begin    
	      if (~axi_arready && S_AXI_ARVALID)
	        begin
	          // indicates that the slave has acceped the valid read address
	          axi_arready <= 1'b1;
	          // Read address latching
	          axi_araddr  <= S_AXI_ARADDR;
	        end
	      else
	        begin
	          axi_arready <= 1'b0;
	        end
	    end 
	end       

	// Implement axi_arvalid generation
	// axi_rvalid is asserted for one S_AXI_ACLK clock cycle when both 
	// S_AXI_ARVALID and axi_arready are asserted. The slave registers 
	// data are available on the axi_rdata bus at this instance. The 
	// assertion of axi_rvalid marks the validity of read data on the 
	// bus and axi_rresp indicates the status of read transaction.axi_rvalid 
	// is deasserted on reset (active low). axi_rresp and axi_rdata are 
	// cleared to zero on reset (active low).  
	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_rvalid <= 0;
	      axi_rresp  <= 0;
	    end 
	  else
	    begin    
	      if (axi_arready && S_AXI_ARVALID && ~axi_rvalid)
	        begin
	          // Valid read data is available at the read data bus
	          axi_rvalid <= 1'b1;
	          axi_rresp  <= 2'b0; // 'OKAY' response
	        end   
	      else if (axi_rvalid && S_AXI_RREADY)
	        begin
	          // Read data is accepted by the master
	          axi_rvalid <= 1'b0;
	        end                
	    end
	end    

	// Implement memory mapped register select and read logic generation
	// Slave register read enable is asserted when valid address is available
	// and the slave is ready to accept the read address.
	assign slv_reg_rden = axi_arready & S_AXI_ARVALID & ~axi_rvalid;
	always @(*)
	begin
	      // Address decoding for reading registers
	      case ( axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] )
	        2'h0   : reg_data_out <= slv_reg0;
	        2'h1   : reg_data_out <= slv_reg1;
	       2'h2   : reg_data_out <= rx_fifo_dout;  // 0x08 QSPI_DR (RX FIFO'dan okuma)
            2'h3   : reg_data_out <= hw_status_reg; // 0x0C QSPI_STA (Donanım durumu okuması)
            default : reg_data_out <= 0;
	      endcase
	end

	// Output register or memory read data
	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_rdata  <= 0;
	    end 
	  else
	    begin    
	      // When there is a valid read address (S_AXI_ARVALID) with 
	      // acceptance of read address by the slave (axi_arready), 
	      // output the read dada 
	      if (slv_reg_rden)
	        begin
	          axi_rdata <= reg_data_out;     // register read data
	        end   
	    end
	end    

	// Add user logic here
	
	
// --- 1. YAZMAÇ EŞLEŞTİRMELERİ (Register Mapping) ---
    // Şartname EK-2'ye göre AXI Lite yazmaçlarının adres atamaları:
    wire [31:0] QSPI_CCR = slv_reg0; // 0x00 - Konfigürasyon ve Komut
    wire [31:0] QSPI_ADR = slv_reg1; // 0x04 - Adres (3-bayt veya 4-bayt)
    // 0x08 (QSPI_DR) doğrudan FIFO'lara bağlanacak, aşağıda tanımlandı.
    // 0x0C (QSPI_STA) durum yazmacı donanımsal olarak sürülecek.

    // --- 2. 64x32-BIT FIFO SİNYALLERİ ---
    wire tx_fifo_full, tx_fifo_empty;
    wire rx_fifo_full, rx_fifo_empty;
   
     // State machine'den gelecek meşgul sinyali

    // TX FIFO Yazma: İşlemci 0x08 adresine (slv_reg2) YAZMA yaptığında tetiklenir.

// 1. Önce slv_reg2'ye veri yazıldığını yakalayan bir sinyal oluşturalım
    reg slv_reg2_old_wren;
    always @(posedge S_AXI_ACLK) slv_reg2_old_wren <= slv_reg_wren;

    // 2. Eğer yazma emri varsa ve adres 0x08 ise FIFO yazma ucunu tetikle
    assign tx_fifo_wr_en = slv_reg_wren && (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS : ADDR_LSB] == 3'h2);
    assign tx_fifo_din   = S_AXI_WDATA; // FIFO girişini direkt AXI verisine bağla
    
    // RX FIFO Okuma: İşlemci 0x08 adresinden (slv_reg2) OKUMA yaptığında tetiklenir.
    wire rx_fifo_rd_en = (slv_reg_rden && (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 2'h2));

    // --- 3. QSPI_STA (0x0C) DURUM YAZMACININ GÜNCELLENMESİ ---
    // Şartnamedeki QSPI_STA [cite: 662] bitlerini AXI okuması için hazırlıyoruz.
    // Not: AXI okuma bloğunda slv_reg3'ün donanımdan gelen bu değerlerle ezilmesi gerekir.
  
//    assign hw_status_reg[0]  = ~spi_busy;       // Transaction tamamlandı
//    assign hw_status_reg[1]  = spi_busy;        // Meşgul [cite: 664]
//    assign hw_status_reg[4]  = rx_fifo_full;    // RX FIFO Tam Dolu [cite: 666]
//    assign hw_status_reg[5]  = rx_fifo_empty;   // RX FIFO Tam Boş [cite: 667]
//    assign hw_status_reg[6]  = tx_fifo_full;    // TX FIFO Tam Dolu [cite: 668]
//    assign hw_status_reg[7]  = tx_fifo_empty;   // TX FIFO Tam Boş [cite: 669]
//    assign hw_status_reg[11:8] = 4'b0000;       // Hata durumları (İleride eklenecek) [cite: 670]

assign hw_status_reg = {
    20'b0,            // 31:12 arasını sıfırla (Z'den kurtul)
    4'b0000,          // 11:8 Hata durumları
    tx_fifo_empty,    // 7
    tx_fifo_full,     // 6
    rx_fifo_empty,    // 5
    rx_fifo_full,     // 4
    2'b00,            // 3:2 rezerve
    spi_busy,         // 1
    ~spi_busy         // 0
};
    
    // ==========================================================
    // --- 1. YAZMAÇ (REGISTER) VE FIFO KONTROL SİNYALLERİ ---
    // ==========================================================
    
    // Şartname EK-2 Yazmaç Eşleştirmeleri
  // 0x04
    

   
    
    // FIFO Tetikleyicileri (CPU 0x08 adresine yazınca TX dolar, okuyunca RX boşalır)
  

    // Durum Yazmacı (0x0C) Sinyalleri
  
    
  //  assign hw_status_reg[0]    = ~spi_busy;       
  //  assign hw_status_reg[1]    = spi_busy;        
  //  assign hw_status_reg[4]    = rx_fifo_full;    
   // assign hw_status_reg[5]    = rx_fifo_empty;   
   // assign hw_status_reg[6]    = tx_fifo_full;    
  //  assign hw_status_reg[7]    = tx_fifo_empty;   
  //  assign hw_status_reg[11:8] = 4'b0000;       

    // ==========================================================
    // --- 2. 64x32-BIT FIFO ÖRNEKLEMELERİ ---
    // ==========================================================
    
    wire [31:0] tx_fifo_dout;
    reg tx_fifo_rd_en;
    
    fifo_64x32 tx_fifo (
    .clk(S_AXI_ACLK),
    .srst(~S_AXI_ARESETN),
    
    //.din(slv_reg2),           // 0x08 adresinden gelen veri
    .din(S_AXI_WDATA), // Aracı register'ı baypas et, veriyi hattan direkt al
    .wr_en(tx_fifo_wr_en),
    .rd_en(tx_fifo_rd_en),    // FSM tarafından sürülmeli
    .dout(tx_fifo_dout),      // Bu kablo Wrapper FSM'e gitmeli
    .full(tx_fifo_full),
    .empty(tx_fifo_empty)     // Bu kablo FSM'i tetiklemeli
);

    reg [31:0] rx_fifo_din;
    reg rx_fifo_wr_en;

    fifo_64x32 rx_fifo (
        .clk(S_AXI_ACLK),
        .srst(~S_AXI_ARESETN),
        .din(rx_fifo_din),
        .wr_en(rx_fifo_wr_en),
        .rd_en(rx_fifo_rd_en),
        .dout(rx_fifo_dout),
        .full(rx_fifo_full),
        .empty(rx_fifo_empty)
    );

 // ==========================================================
    // --- 3. 32-BIT'İ 8-BIT'E DÖNÜŞTÜREN KÖPRÜ (WRAPPER FSM) ---
    // ==========================================================
    
    localparam W_IDLE = 0, W_WAIT_FIFO = 1, W_POP = 2, W_PULSE = 3, W_WAIT = 4, W_PUSH = 5;
    reg [2:0] w_state;
    reg [1:0] byte_count;
    reg [31:0] tx_shift_reg;
    reg [31:0] rx_shift_reg;
    
    reg motor_start;
    wire motor_done;
    wire motor_busy;
    wire [7:0] motor_rx_byte;
    
    assign spi_busy = (w_state != W_IDLE) | motor_busy;
    assign debug_fifo_data = tx_fifo_dout;

    // FSM Ana Döngüsü
    always @(posedge S_AXI_ACLK) begin
        if (~S_AXI_ARESETN) begin
            w_state <= W_IDLE;
            tx_fifo_rd_en <= 0;
            rx_fifo_wr_en <= 0;
            motor_start <= 0;
            byte_count <= 0;
            tx_shift_reg <= 32'h0;
            rx_shift_reg <= 32'h0;
        end else begin
            tx_fifo_rd_en <= 0;
            rx_fifo_wr_en <= 0;
            motor_start <= 0;

            case (w_state)
                W_IDLE: begin
                    byte_count <= 0;
                    if (!tx_fifo_empty) begin 
                        tx_fifo_rd_en <= 1; 
                        w_state <= W_WAIT_FIFO; 
                    end
                end
                
                W_WAIT_FIFO: begin
                    w_state <= W_POP; // FIFO Okuma Gecikmesi Fix
                end
                
                W_POP: begin
                    tx_shift_reg <= tx_fifo_dout;
                    w_state <= W_PULSE;
                end
                
                W_PULSE: begin
                    if (!motor_busy) begin // motor_busy kullanıyoruz
                        motor_start <= 1;
                        w_state <= W_WAIT;
                    end
                end
                
                W_WAIT: begin
                    if (motor_done) begin // Master'dan gelen done_tick (motor_done)
                        rx_shift_reg <= {rx_shift_reg[23:0], motor_rx_byte};
                        tx_shift_reg <= {tx_shift_reg[23:0], 8'h00}; 
                        
                        if (byte_count == 2'd3) begin
                            w_state <= W_PUSH;
                        end else begin
                            byte_count <= byte_count + 1;
                            w_state <= W_PULSE;
                        end
                    end
                end
                
//                W_PUSH: begin
//                    if (~rx_fifo_full) begin
//                        rx_fifo_din <= rx_shift_reg;
//                        rx_fifo_wr_en <= 1;
//                        w_state <= W_IDLE;
//                    end
//                end
                W_PUSH: begin
    rx_fifo_din <= rx_shift_reg;
    rx_fifo_wr_en <= 1; // Yazma emrini ver
    w_state <= W_IDLE;  // Beklemeden IDLE'a dön ki yeni veriyi çekebilsin
end
                default: w_state <= W_IDLE;
            endcase
        end
    end

    // ==========================================================
    // --- 4. YENİ SPI MOTORUNUN ÖRNEKLENMESİ ---
    // ==========================================================
    
    wire motor_tx_en = (w_state != W_IDLE) ? 1'b1 : slv_reg0[3];
    wire [1:0] motor_mode = slv_reg0[2:1];
    assign CS_pad = ~slv_reg0[0]; 
    assign irq = motor_done;

    reg [7:0] master_data_in;

    // Data Mux: Master'a gidecek baytı seçer
    // NOT: Master LATCH_DATA durumunda olduğu için bu veri 1 cycle önceden hazır olmalı.
    always @(posedge S_AXI_ACLK) begin
        if (~S_AXI_ARESETN) begin
            master_data_in <= 8'h00;
        end else begin
            // tx_shift_reg her zaman en üst baytı (31:24) buraya sunar
            master_data_in <= tx_shift_reg[31:24];
        end
    end

    // SPI Motoru (Master) Örneklendirmesi
    Master spi_motor_inst (
        .clk        (S_AXI_ACLK),
        .rst_n      (S_AXI_ARESETN),
        .start      (motor_start),       
        .mode       (motor_mode),       
        .tx_en      (motor_tx_en),       
        .tx_byte    (master_data_in),   
        .rx_byte    (motor_rx_byte),     
        .busy       (motor_busy),        
        .done_tick  (motor_done),        
        .sclk       (SCLK_pad),
        .dq_o       (dq_o),
        .dq_i       (dq_i),
        .dq_oe      (dq_oe)
    );

endmodule

