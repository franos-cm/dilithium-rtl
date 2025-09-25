`timescale 1ns / 1ps

import tb_pkg::*;

module tb_keygen;
    localparam logic[1:0] MODE = KEYGEN_MODE;

    logic tb_rst, failed;
    integer ctr, tv_ctr;
    // Since dilithium-low-res loads/dumps the data as separate
    // operations, it is useful to keep track of both also separately.
    // These counters are thus only valid for dilithium-low-res.
    integer start_time, exec_time, unload_time, stop_time;
    integer load_cycles, exec_cycles, unload_cycles, total_cycles;
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

    logic [0:SEED_SIZE-1] seed  [TOTAL_TV_NUM-1:0];
    logic [0:SEED_SIZE-1] k     [TOTAL_TV_NUM-1:0];
    logic [0:SEED_SIZE-1] rho   [TOTAL_TV_NUM-1:0];
    logic [0:SEED_SIZE-1] tr    [TOTAL_TV_NUM-1:0];
    logic [0:S1_SIZE-1]   s1    [TOTAL_TV_NUM-1:0];
    logic [0:S2_SIZE-1]   s2    [TOTAL_TV_NUM-1:0];
    logic [0:T0_SIZE-1]   t0    [TOTAL_TV_NUM-1:0];
    logic [0:T1_SIZE-1]   t1    [TOTAL_TV_NUM-1:0];
  
    // NOTE: different Dilithiums will have same states, but different transitions
    logic low_res_sk_done;
    typedef enum logic [3:0] {
        S_INIT, S_START, LOAD_SEED, UNLOAD_RHO, UNLOAD_K, UNLOAD_S1,
        UNLOAD_S2, UNLOAD_T1, UNLOAD_T0, UNLOAD_TR, S_STOP
    } state_t;
    state_t state;

    localparam logic [2:0] sec_lvl_sig = (SEC_LEVEL == 2) ? 3'b010 :
                                         (SEC_LEVEL == 3) ? 3'b011 :
                                         (SEC_LEVEL == 5) ? 3'b101 : 3'b000;


    dilithium dut (
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
        $readmemh({TV_SHARED_PATH, "seed.txt"}, seed);
        $readmemh({TV_SHARED_PATH, "k.txt"}, k);
        $readmemh({TV_SHARED_PATH, "rho.txt"}, rho);
        $readmemh({TV_PATH, "s1.txt"}, s1);
        $readmemh({TV_PATH, "s2.txt"}, s2);
        $readmemh({TV_PATH, "t0.txt"}, t0);
        $readmemh({TV_PATH, "t1.txt"}, t1);
        $readmemh({TV_PATH, "tr.txt"}, tr);

        // Dump to csv
        file_name = $sformatf(
            "keygen_perf%0d_lvl%0d_tv%0d_%0d.csv",
            HIGH_PERF, SEC_LEVEL, INITIAL_TV, (INITIAL_TV+NUM_TV_TO_EXEC-1)
        );
        csv_fd = $fopen({RESULTS_DIR, file_name}, "w");
        if (!csv_fd) begin
            $fatal(1, "Failed to open CSV file for writing — does the directory exist?");
        end
        if (HIGH_PERF) begin
            $fwrite(csv_fd, "test_num,total_cycles,success\n");
        end else begin
            $fwrite(csv_fd, "test_num,load_cycles,exec_cycles,unload_cycles,total_cycles,success\n");
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
            low_res_sk_done     <= 0;
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
                    state <= LOAD_SEED;
                end
                LOAD_SEED: begin
                    if (start) begin
                        start_time = $time;
                    end
                    valid_i <= 1;
                    data_i  <= seed[tv_ctr][0 +: W];
                
                    if (ready_i) begin
                        ctr <= ctr + 1;
                        data_i <= seed[tv_ctr][(ctr+1)*W +: W];

                        if (ctr == SEED_WORDS_NUM-1) begin
                            ctr <= 0;
                            ready_o <= 1;
                            valid_i <= 0;
                            data_i  <= 0;
                            exec_time = $time;
                            state <= UNLOAD_RHO;
                        end
                    end
                end
                UNLOAD_RHO: begin
                    ready_o <= 1;
                    if (valid_o) begin
                        if (!unload_time_started) begin
                            unload_time = $time;
                            unload_time_started <= 1;
                        end
                        
                        if (data_o !== rho[tv_ctr][ctr*W+:W]) begin
                            $display("[Rho, %d] Error: Expected %h, received %h", ctr, rho[tv_ctr][ctr*W+:W], data_o);
                            failed <= 1;
                        end
                    
                        ctr <= ctr + 1;
                        if (ctr == SEED_WORDS_NUM-1) begin
                            ctr <= 0;
                            state <= low_res_sk_done ? UNLOAD_T1 : UNLOAD_K;
                            low_res_sk_done <= !(HIGH_PERF);
                        end
                    end
                end        
                UNLOAD_K: begin
                    ready_o <= 1;
                    if (valid_o) begin
                        if (data_o !== k[tv_ctr][ctr*W+:W]) begin
                            $display("[K, %d] Error: Expected %h, received %h", ctr, k[tv_ctr][ctr*W+:W], data_o);
                            failed <= 1;
                        end
                    
                        ctr <= ctr + 1;
                        if (ctr == SEED_WORDS_NUM-1) begin
                            ctr <= 0;
                            state <= HIGH_PERF ? UNLOAD_S1 : UNLOAD_TR;
                        end
                    end
                end
                UNLOAD_S1: begin
                    ready_o <= 1;
                    if (valid_o) begin
                        if (data_o !== s1[tv_ctr][ctr*W+:W]) begin
                            $display("[S1, %d] Error: Expected %h, received %h", ctr, s1[tv_ctr][ctr*W+:W], data_o);
                            failed <= 1;
                        end
        
                        ctr <= ctr + 1;
                        if (ctr == S1_WORDS_NUM-1) begin
                            ctr <= 0;
                            state <= UNLOAD_S2;
                        end
                    end
                end
                UNLOAD_S2: begin
                    ready_o <= 1;
                    if (valid_o) begin
                        if (data_o !== s2[tv_ctr][ctr*W+:W]) begin
                            $display("[S2, %d] Error: Expected %h, received %h", ctr, s2[tv_ctr][ctr*W+:W], data_o);
                            failed <= 1;
                        end
                    
                        ctr <= ctr + 1;
                        if (ctr == S2_WORDS_NUM-1) begin
                            ctr <= 0;
                            state <= HIGH_PERF ? UNLOAD_T1 : UNLOAD_T0;
                        end
                    end
                end
                UNLOAD_T1: begin
                    ready_o <= 1;
                    if (valid_o) begin
                        if (data_o !== t1[tv_ctr][ctr*W+:W]) begin
                            $display("[T1, %d] Error: Expected %h, received %h", ctr, t1[tv_ctr][ctr*W+:W], data_o);
                            failed <= 1;
                        end

                        ctr <= ctr + 1;
                        if (ctr == T1_WORDS_NUM-1) begin
                            ctr <= 0;
                            state <= HIGH_PERF ? UNLOAD_T0 : S_STOP;
                            stop_time = $time;
                        end
                    end
                end
                UNLOAD_T0: begin
                    ready_o <= 1;
                    if (valid_o) begin
                        if (data_o !== t0[tv_ctr][ctr*W+:W]) begin
                            $display("[T0, %d] Error: Expected %h, received %h", ctr, t0[tv_ctr][ctr*W+:W], data_o);
                            failed <= 1;
                        end

                        ctr <= ctr + 1;
                        if (ctr == T0_WORDS_NUM-1) begin
                            ctr <= 0;
                            state <= HIGH_PERF ? UNLOAD_TR : UNLOAD_RHO;
                        end
                    end
                end
                UNLOAD_TR: begin
                    ready_o <= 1;
                    if (valid_o) begin
                        if (data_o !== tr[tv_ctr][ctr*W+:W]) begin
                            $display("[TR, %d] Error: Expected %h, received %h", ctr, tr[tv_ctr][ctr*W+:W], data_o);
                            failed <= 1;
                        end
                    
                        ctr <= ctr + 1;
                        if (ctr == SEED_WORDS_NUM-1) begin
                            ctr <= 0;
                            state <= HIGH_PERF ? S_STOP : UNLOAD_S1;
                            stop_time = $time;
                        end
                    end
                end
                S_STOP: begin
                    tv_ctr              <= tv_ctr + 1;
                    low_res_sk_done     <= 0;
                    unload_time_started <= 0;
                    failed              <= 0;
                    state               <= S_INIT;

                    total_cycles = (stop_time-start_time)/P;
                    if (HIGH_PERF) begin
                        $display("KG%d[%d] completed in %d clock cycles", SEC_LEVEL, tv_ctr, total_cycles);
                        $fwrite(csv_fd, "%0d,%0d,%0d\n", tv_ctr, total_cycles, (!failed));
                    end else begin
                        load_cycles = (exec_time-start_time)/P;
                        exec_cycles = (unload_time-exec_time)/P;
                        unload_cycles = (stop_time-unload_time)/P;

                        $display(
                            "KG%d[%d] completed in %d (load) + %d (exec) + %d (unload) = %d (total) clock cycles",
                            SEC_LEVEL, tv_ctr, load_cycles, exec_cycles, unload_cycles, total_cycles
                        );
                        $fwrite(
                            csv_fd, "%0d,%0d,%0d,%0d,%0d,%0d\n", tv_ctr, load_cycles,
                            exec_cycles, unload_cycles, total_cycles, (!failed)
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