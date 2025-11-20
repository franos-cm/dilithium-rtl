`timescale 1ns / 1ps

import tb_pkg::*;

module tb_verify;
    localparam logic[1:0] MODE = VERIFY_MODE;
    localparam int IDLE1_CYCLES_NUM = 10000;
    localparam int IDLE2_CYCLES_NUM = 10000;

    logic tb_rst, failed;
    integer ctr, tv_ctr, idle_ctr;
    // Since dilithium-low-res loads/dumps the data as separate
    // operations, it is useful to keep track of both also separately.
    // These counters are thus only valid for dilithium-low-res.
    integer start_time, load_sig_time, load_msg_time, exec_time, stop_time;
    integer load_pk_cycles, load_sig_cycles, load_msg_cycles, exec_cycles, total_cycles;
    // Dump results to csv
    integer csv_fd;
    string file_name;

    logic clk = 1;
    logic rst, start, done;
    logic valid_i,  ready_o;
    logic ready_i, valid_o;
    logic  [W-1:0] data_i;  
    logic [W-1:0] data_o;

    logic [0:SEED_SIZE-1]  rho      [TOTAL_TV_NUM-1:0];
    logic [0:SEED_SIZE-1]  c        [TOTAL_TV_NUM-1:0];
    logic [0:MSG_SIZE-1]   msg      [TOTAL_TV_NUM-1:0];
    logic [0:MSG_LEN_SIZE] msg_len  [TOTAL_TV_NUM-1:0];
    logic [0:Z_SIZE-1]     z        [TOTAL_TV_NUM-1:0];
    logic [0:H_SIZE-1]     h        [TOTAL_TV_NUM-1:0];
    logic [0:T1_SIZE-1]    t1       [TOTAL_TV_NUM-1:0];
  
    // NOTE: different Dilithiums will have same states, but different transitions
    typedef enum logic [3:0] {
        S_INIT, S_START, LOAD_RHO, LOAD_C, LOAD_Z, LOAD_T1,
        LOAD_MLEN, LOAD_MSG, LOAD_H, UNLOAD_RESULT, S_STOP,
        // NOTE: the idle states are unnecessary, but simulate backpressure,
        //       which is relevant for testing the designs under different cenarios
        S_IDLE_1, S_IDLE_2
    } state_t;
    state_t state;


    localparam logic [2:0] sec_lvl_sig = (SEC_LEVEL == 2) ? 3'b010 :
                                         (SEC_LEVEL == 3) ? 3'b011 :
                                         (SEC_LEVEL == 5) ? 3'b101 : 3'b000;


    dilithium #(
        .ZETAS_PATH (ZETAS_PATH)
    ) dut (
        .clk (clk),
        .rst (rst),
        .start (start),
        .mode (MODE),
        .sec_lvl (sec_lvl_sig),
        .valid_i (valid_i),
        .ready_i (ready_i),
        .data_i (data_i),
        .valid_o (valid_o),
        .ready_o (ready_o),
        .data_o (data_o)
    );


    initial begin
        // Read test vectors
        $readmemh({TV_SHARED_PATH, "rho.txt"}, rho);
        $readmemh({TV_SHARED_PATH, "msg.txt"}, msg);
        $readmemh({TV_SHARED_PATH, "msg_len.txt"}, msg_len);
        $readmemh({TV_PATH, "t1.txt"}, t1);
        $readmemh({TV_PATH, "c.txt"}, c);
        $readmemh({TV_PATH, "z.txt"}, z);
        $readmemh({TV_PATH, "h.txt"}, h);

        // Dump to csv
        file_name = $sformatf(
            "verify_perf%0d_lvl%0d_tv%0d_%0d.csv",
            HIGH_PERF, SEC_LEVEL, INITIAL_TV, (INITIAL_TV+NUM_TV_TO_EXEC-1)
        );
        csv_fd = $fopen({RESULTS_DIR, file_name}, "w");
        if (!csv_fd) begin
            $fatal(1, "Failed to open CSV file for writing — does the directory exist?");
        end
        if (HIGH_PERF) begin
            $fwrite(csv_fd, "test_num,total_cycles,success\n");
        end else begin
            $fwrite(csv_fd, "test_num,load_pk_cycles,load_sig_cycles,load_msg_cycles,exec_cycles,total_cycles,success\n");
        end
    end

    initial begin
        tb_rst = 1;
        #(2*P);
        tb_rst = 0;
    end

    always_ff @(posedge clk) begin
        if (tb_rst) begin
            start           <= 0;
            valid_i         <= 0;
            ready_o         <= 0;
            data_i          <= 0;
            ctr             <= 0; 
            tv_ctr          <= INITIAL_TV;
            failed          <= 0;
            rst             <= 1;
            state           <= S_INIT;
            idle_ctr       <= 0;
        end

        else begin
            rst     <= 0;
            start   <= 0;
            valid_i <= 0;
            ready_o <= 0;
            data_i  <= 0;
        
            unique case (state)
                S_INIT: begin
                    rst <= 1;
                    ctr <= ctr + 1;
                    // Arbitrary number of reset cycles
                    if (ctr == 3) begin
                        ctr <= 0;
                        state <= S_START;
                    end
                end
                S_START: begin
                    start <= 1;
                    state <= LOAD_RHO;
                end
                LOAD_RHO: begin
                    if (start) begin
                        start_time = $time;
                    end
                    valid_i <= 1;
                    data_i <= rho[tv_ctr][ctr*W +: W];
                
                    if (ready_i) begin
                        if (ctr == SEED_WORDS_NUM-1) begin
                            ctr    <= 0;
                            state  <= HIGH_PERF ? LOAD_C : LOAD_T1;
                            data_i <= HIGH_PERF ? c[tv_ctr][0 +: W] : t1[tv_ctr][0 +: W];
                        end else begin
                            ctr    <= ctr + 1;
                            data_i <= rho[tv_ctr][(ctr+1)*W +: W];
                        end
                    end
                end
                LOAD_C: begin
                    valid_i <= 1;
                    data_i <= c[tv_ctr][ctr*W +: W];
                
                    if (ready_i) begin
                        if (ctr == SEED_WORDS_NUM-1) begin
                            ctr    <= 0;
                            state  <= LOAD_Z;
                            data_i <= z[tv_ctr][0 +: W];
                        end else begin
                            ctr    <= ctr + 1;
                            data_i <= c[tv_ctr][(ctr+1)*W +: W];
                        end
                    end
                end
                LOAD_Z: begin
                    valid_i <= 1;
                    data_i <= z[tv_ctr][ctr*W +: W];
                
                    if (ready_i) begin
                        if (ctr == Z_WORDS_NUM-1) begin
                            ctr    <= 0;
                            state  <= HIGH_PERF ? LOAD_T1 : LOAD_H;
                            data_i <= HIGH_PERF ? t1[tv_ctr][0 +: W] : h[tv_ctr][0 +: W];
                        end else begin
                            ctr    <= ctr + 1;
                            data_i <= z[tv_ctr][(ctr+1)*W +: W];
                        end
                    end
                end
                LOAD_T1: begin
                    valid_i <= 1;
                    data_i <= t1[tv_ctr][ctr*W +: W];
                
                    if (ready_i) begin
                        if (ctr == T1_WORDS_NUM-1) begin
                            ctr    <= 0;
                            state  <= HIGH_PERF ? LOAD_MLEN : LOAD_C;
                            data_i <= HIGH_PERF ? msg_len[tv_ctr] : c[tv_ctr][0 +: W];
                            load_sig_time = $time;
                        end else begin
                            ctr    <= ctr + 1;
                            data_i <= t1[tv_ctr][(ctr+1)*W +: W];
                        end
                    end
                end
                LOAD_MLEN: begin
                    valid_i <= 1;
                    // NOTE: interestingly, this op zero-extends data_i on the left,
                    //       while slicing with [ctr*W +: W] would X/U-extend on the right.
                    //       This is somewhat relevant when porting the designs for the real world.
                    data_i <= msg_len[tv_ctr];
                
                    if (ready_i) begin
                        data_i  <= msg[tv_ctr][0 +: W];
                        state   <= IDLE1_CYCLES_NUM ? S_IDLE_1 : LOAD_MSG;
                        valid_i <= IDLE1_CYCLES_NUM ? 0 : 1;
                        load_msg_time = $time;
                    end
                end
                S_IDLE_1: begin
                    valid_i <= 0;
                    ready_o <= 0;
                    idle_ctr <= idle_ctr + 1;
                    if (idle_ctr == IDLE1_CYCLES_NUM) begin
                        state <= LOAD_MSG;
                        idle_ctr <= 0;
                    end
                end
                LOAD_MSG: begin
                    valid_i <= 1;
                    data_i <= msg[tv_ctr][ctr*W +: W];
                
                    if (ready_i) begin
                        if ((ctr+1)*W >= msg_len[tv_ctr]*8) begin
                            ctr     <= 0;
                            state   <= HIGH_PERF ? (IDLE1_CYCLES_NUM ? S_IDLE_2 : LOAD_H) : UNLOAD_RESULT;
                            data_i  <= h[tv_ctr][0 +: W];
                            valid_i <= IDLE1_CYCLES_NUM ? 0 : (HIGH_PERF ? 1 : 0);
                            ready_o <= HIGH_PERF ? 0 : 1;
                            exec_time = $time;
                        end else begin
                            ctr    <= ctr + 1;
                            data_i <= msg[tv_ctr][(ctr+1)*W +: W];
                        end
                    end
                end
                S_IDLE_2: begin
                    valid_i <= 0;
                    ready_o <= 0;
                    idle_ctr <= idle_ctr + 1;
                    if (idle_ctr == IDLE1_CYCLES_NUM) begin
                        state <= LOAD_H;
                        idle_ctr <= 0;
                    end
                end
                LOAD_H: begin
                    valid_i <= 1;
                    data_i <= h[tv_ctr][ctr*W +: W];
                
                    if (ready_i) begin
                        if (ctr == H_WORDS_NUM-1) begin
                            ctr    <= 0;
                            state  <= HIGH_PERF ? UNLOAD_RESULT : LOAD_MLEN;
                            valid_i <= HIGH_PERF ? 0 : 1;
                            ready_o <= HIGH_PERF ? 1 : 0;
                            data_i <= msg_len[tv_ctr];
                        end else begin
                            ctr    <= ctr + 1;
                            data_i <= h[tv_ctr][(ctr+1)*W +: W];
                        end
                    end
                end
                UNLOAD_RESULT: begin
                    ready_o <= 1;
                    if (valid_o) begin
                        // NOTE: the two designs represent rejection differently
                        if (data_o == HIGH_PERF) begin
                            $display("Rejected");
                            failed <= 1;
                        end
                        ready_o <= 0;
                        state   <= S_STOP;
                        stop_time = $time;
                    end
                end
                S_STOP: begin
                    tv_ctr  <= tv_ctr + 1;
                    failed  <= 0;
                    state   <= S_INIT;

                    total_cycles = (stop_time-start_time)/P;
                    if (HIGH_PERF) begin
                        $display("VY%d[%d] completed in %d clock cycles", SEC_LEVEL, tv_ctr, total_cycles);
                        $fwrite(csv_fd, "%0d,%0d,%0d\n", tv_ctr, total_cycles, (!failed));
                    end else begin
                        load_pk_cycles = (load_sig_time-start_time)/P;
                        load_sig_cycles = (load_msg_time-load_sig_time)/P;
                        load_msg_cycles = (exec_time-load_msg_time)/P;
                        exec_cycles = (stop_time-exec_time)/P;

                        $display(
                            "VY%d[%d] completed in %d (load pk) + %d (load sig) + %d (load msg) + %d (exec) = %d (total) clock cycles",
                            SEC_LEVEL, tv_ctr, load_pk_cycles, load_sig_cycles, load_msg_cycles, exec_cycles, total_cycles
                        );
                        $fwrite(
                            csv_fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d\n", tv_ctr, load_pk_cycles,
                            load_sig_cycles, load_msg_cycles, exec_cycles, total_cycles, (!failed)
                        );
                    end

                    if ((tv_ctr - INITIAL_TV) == NUM_TV_TO_EXEC-1) begin
                        $display ("Testbench done!");
                        $fclose(csv_fd);
                        $finish;
                    end       
                end
                default: begin
                    $fatal(1, "Invalid state reached: %0d", state);
                end
            endcase
        end
    end

    always #(P/2) clk = ~clk;

endmodule