`timescale 1ns / 1ps

import tb_pkg::*;

module tb_sign;
    localparam logic[1:0] MODE = SIGN_MODE;

    logic tb_rst, failed;
    integer ctr, tv_ctr;
    // Since dilithium-low-res loads/dumps the data as separate
    // operations, it is useful to keep track of both also separately.
    // These counters are thus only valid for dilithium-low-res.
    integer start_time, load_msg_time, exec_time, unload_time, stop_time;
    integer load_sk_cycles, load_msg_cycles, exec_cycles, unload_cycles, total_cycles;
    logic unload_time_started;
    // Dump results to csv
    integer csv_fd;
    string file_name;

    logic clk = 1;
    logic rst, start, done;
    logic valid_i,  ready_o;
    logic ready_i, valid_o;
    logic  [W-1:0] data_i;  
    logic [W-1:0] data_o;
    logic [7:0] reject_counter;

    logic [0:SEED_SIZE-1]  rho       [TOTAL_TV_NUM-1:0];
    logic [0:SEED_SIZE-1]  k         [TOTAL_TV_NUM-1:0];
    logic [0:S1_SIZE-1]    s1        [TOTAL_TV_NUM-1:0];
    logic [0:S2_SIZE-1]    s2        [TOTAL_TV_NUM-1:0];
    logic [0:T0_SIZE-1]    t0        [TOTAL_TV_NUM-1:0];
    logic [0:SEED_SIZE-1]  tr        [TOTAL_TV_NUM-1:0];
    logic [0:SEED_SIZE-1]  c         [TOTAL_TV_NUM-1:0];
    logic [0:Z_SIZE-1]     z         [TOTAL_TV_NUM-1:0];
    logic [0:H_SIZE-1]     h         [TOTAL_TV_NUM-1:0];
    logic [0:MSG_SIZE-1]   msg       [TOTAL_TV_NUM-1:0];
    logic [0:MSG_LEN_SIZE] msg_len   [TOTAL_TV_NUM-1:0];
  
    // NOTE: different Dilithiums will have same states, but different transitions
    typedef enum logic [3:0] {
        S_INIT, S_START, LOAD_RHO, LOAD_MLEN, LOAD_TR,
        LOAD_MSG, LOAD_K, LOAD_S1, LOAD_S2, LOAD_T0, UNLOAD_Z,
        UNLOAD_H, UNLOAD_C, S_STOP
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
        $readmemh({TV_SHARED_PATH, "k.txt"}, k);
        $readmemh({TV_SHARED_PATH, "msg.txt"}, msg);
        $readmemh({TV_SHARED_PATH, "msg_len.txt"}, msg_len);
        $readmemh({TV_PATH, "s1.txt"}, s1);
        $readmemh({TV_PATH, "s2.txt"}, s2);
        $readmemh({TV_PATH, "t0.txt"}, t0);
        $readmemh({TV_PATH, "tr.txt"}, tr);
        $readmemh({TV_PATH, "c.txt"}, c);
        $readmemh({TV_PATH, "z.txt"}, z);
        $readmemh({TV_PATH, "h.txt"}, h);

        // Dump to csv
        file_name = $sformatf(
            "sign_perf%0d_lvl%0d_tv%0d_%0d.csv",
            HIGH_PERF, SEC_LEVEL, INITIAL_TV, (INITIAL_TV+NUM_TV_TO_EXEC-1)
        );
        csv_fd = $fopen({RESULTS_DIR, file_name}, "w");
        if (!csv_fd) begin
            $fatal(1, "Failed to open CSV file for writing — does the directory exist?");
        end
        if (HIGH_PERF) begin
            $fwrite(csv_fd, "test_num,total_cycles,rejects_count,success\n");
        end else begin
            $fwrite(csv_fd, "test_num,load_sk_cycles,load_msg_cycles,exec_cycles,unload_cycles,total_cycles,rejects_count,success\n");
        end
    end

    initial begin
        tb_rst = 1;
        #(2*P);
        tb_rst = 0;
    end

    always_ff @(posedge clk) begin
        if (tb_rst) begin
            start               <= 0;
            valid_i             <= 0;
            ready_o             <= 0;
            data_i              <= 0;
            ctr                 <= 0; 
            tv_ctr              <= INITIAL_TV;
            unload_time_started <= 0;
            failed              <= 0;
            rst                 <= 1;
            state               <= S_INIT;
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
                            state  <= HIGH_PERF ? LOAD_MLEN : LOAD_K;
                            data_i <= HIGH_PERF ? msg_len[tv_ctr] : k[tv_ctr][0 +: W];
                        end else begin
                            ctr    <= ctr + 1;
                            data_i <= rho[tv_ctr][(ctr+1)*W +: W];
                        end
                    end
                end
                LOAD_MLEN: begin
                    valid_i <= 1;
                    data_i <= msg_len[tv_ctr];
                
                    if (ready_i) begin
                        state  <= HIGH_PERF ? LOAD_TR : LOAD_MSG;
                        data_i <= HIGH_PERF ? tr[tv_ctr][0 +: W] : msg[tv_ctr][0 +: W];
                        load_msg_time = $time;
                    end
                end
                LOAD_TR: begin
                    valid_i <= 1;
                    data_i <= tr[tv_ctr][ctr*W +: W];
                
                    if (ready_i) begin
                        if (ctr == SEED_WORDS_NUM-1) begin
                            ctr    <= 0;
                            state  <= HIGH_PERF ? LOAD_MSG : LOAD_S1;
                            data_i <= HIGH_PERF ? msg[tv_ctr][0 +: W] : s1[tv_ctr][0 +: W];
                        end else begin
                            ctr    <= ctr + 1;
                            data_i <= tr[tv_ctr][(ctr+1)*W +: W];
                        end
                    end
                end
                LOAD_MSG: begin
                    valid_i <= 1;
                    data_i <= msg[tv_ctr][ctr*W +: W];
                
                    if (ready_i) begin
                        if ((ctr+1)*W >= msg_len[tv_ctr]*8) begin
                            ctr     <= 0;
                            state   <= HIGH_PERF ? LOAD_K : UNLOAD_C;
                            data_i  <= k[tv_ctr][0 +: W];
                            valid_i <= HIGH_PERF ? 1 : 0;
                            ready_o <= HIGH_PERF ? 0 : 1;
                            exec_time = $time;
                        end else begin
                            ctr    <= ctr + 1;
                            data_i <= msg[tv_ctr][(ctr+1)*W +: W];
                        end
                    end
                end
                LOAD_K: begin
                    valid_i <= 1;
                    data_i <= k[tv_ctr][ctr*W +: W];
                
                    if (ready_i) begin
                        if (ctr == SEED_WORDS_NUM-1) begin
                            ctr    <= 0;
                            state  <= HIGH_PERF ? LOAD_S1 : LOAD_TR;
                            data_i <= HIGH_PERF ? s1[tv_ctr][0 +: W] : tr[tv_ctr][0 +: W];
                        end else begin
                            ctr    <= ctr + 1;
                            data_i <= k[tv_ctr][(ctr+1)*W +: W];
                        end
                    end
                end
                LOAD_S1: begin
                    valid_i <= 1;
                    data_i <= s1[tv_ctr][ctr*W +: W];
                
                    if (ready_i) begin
                        if (ctr == S1_WORDS_NUM-1) begin
                            ctr    <= 0;
                            state  <= LOAD_S2;
                            data_i <= s2[tv_ctr][0 +: W];
                        end else begin
                            ctr    <= ctr + 1;
                            data_i <= s1[tv_ctr][(ctr+1)*W +: W];
                        end
                    end
                end
                LOAD_S2: begin
                    valid_i <= 1;
                    data_i <= s2[tv_ctr][ctr*W +: W];
                
                    if (ready_i) begin
                        if (ctr == S2_WORDS_NUM-1) begin
                            ctr    <= 0;
                            state  <= LOAD_T0;
                            data_i <= t0[tv_ctr][0 +: W];
                        end else begin
                            ctr    <= ctr + 1;
                            data_i <= s2[tv_ctr][(ctr+1)*W +: W];
                        end
                    end
                end
                LOAD_T0: begin
                    valid_i <= 1;
                    data_i <= t0[tv_ctr][ctr*W +: W];
                
                    if (ready_i) begin
                        if (ctr == T0_WORDS_NUM-1) begin
                            ctr    <= 0;
                            state  <= HIGH_PERF ? UNLOAD_Z : LOAD_MLEN;
                            valid_i <= HIGH_PERF ? 0 : 1;
                            ready_o <= HIGH_PERF ? 1 : 0;
                            data_i <= msg_len[tv_ctr];
                        end else begin
                            ctr    <= ctr + 1;
                            data_i <= t0[tv_ctr][(ctr+1)*W +: W];
                        end
                    end
                end        
                UNLOAD_Z: begin
                    ready_o <= 1;
                    if (valid_o) begin
                        if (data_o !== z[tv_ctr][ctr*W+:W]) begin
                            $display("[Z, %d] Error: Expected %h, received %h", ctr, z[tv_ctr][ctr*W+:W], data_o);
                            failed <= 1;
                        end

                        ctr <= ctr + 1;
                        if (ctr == Z_WORDS_NUM-1) begin
                            ctr <= 0;
                            state <= UNLOAD_H;
                        end
                    end
                end        
                UNLOAD_H: begin
                    ready_o <= 1;
                    if (valid_o) begin
                        if (!unload_time_started) begin
                            unload_time = $time;
                            unload_time_started <= 1;
                        end

                        if (data_o != h[tv_ctr][ctr*W+:W]) begin
                            $display("[H, %d] Error: Expected %h, received %h", ctr, h[tv_ctr][ctr*W+:W], data_o);
                            failed <= 1;
                        end
                    
                        ctr <= ctr + 1;
                        if (ctr == H_WORDS_NUM-1) begin
                            ctr <= 0;
                            state <= HIGH_PERF ? UNLOAD_C : S_STOP;
                            stop_time = $time;
                        end
                    end
                end
                UNLOAD_C: begin
                    ready_o <= 1;
                    if (valid_o) begin
                        if (data_o !== c[tv_ctr][ctr*W+:W]) begin
                            $display("[c, %d] Error: Expected %h, received %h", ctr, c[tv_ctr][ctr*W+:W], data_o);
                            failed <= 1;
                        end
        
                        ctr <= ctr + 1;
                        if (ctr == SEED_WORDS_NUM-1) begin
                            ctr <= 0;
                            state <= HIGH_PERF ? S_STOP : UNLOAD_Z;
                            stop_time = $time;
                        end
                    end
                end
                S_STOP: begin
                    tv_ctr              <= tv_ctr + 1;
                    unload_time_started <= 0;
                    failed              <= 0;
                    state               <= S_INIT;

                    total_cycles = (stop_time-start_time)/P;
                    if (HIGH_PERF) begin
                        $display("SG%d[%d] completed in %d clock cycles with %d reject(s)", SEC_LEVEL, tv_ctr, total_cycles, reject_counter);
                        $fwrite(csv_fd, "%0d,%0d,%d,%0d\n", tv_ctr, total_cycles, reject_counter, (!failed));
                    end else begin
                        load_sk_cycles = (load_msg_time-start_time)/P;
                        load_msg_cycles = (exec_time-load_msg_time)/P;
                        exec_cycles = (unload_time-exec_time)/P;
                        unload_cycles = (stop_time-unload_time)/P;

                        $display(
                            "SG%d[%d] completed in %d (load sk) + %d (load msg) + %d (exec) + %d (unload) = %d (total) clock cycles with %d reject(s)",
                            SEC_LEVEL, tv_ctr, load_sk_cycles, load_msg_cycles, exec_cycles, unload_cycles, total_cycles, reject_counter
                        );
                        $fwrite(
                            csv_fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n", tv_ctr, load_sk_cycles,
                            load_msg_cycles, exec_cycles, unload_cycles, total_cycles, reject_counter, (!failed)
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