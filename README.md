# Overview

This project is a **revision** of this [original RTL design](https://github.com/GMUCERG/Dilithium) implementing the CRYSTALS-Dilithium algorithm.

The objective of this revision was to fix small issues and bugs that were found in the design, when trying to use it as a custom core connected to a SoC bus, as part of another project.
For the core's performance metrics, there is a [separate repository with a comparative analysis](https://github.com/franos-cm/dilithium-comparison) between this design and another.
However, the present repository contains the most recent revision of this core, with all the (known) bug fixes.

Overall, the changes made to the design were minimal. The original interface and KATs are kept, although the testbench was changed to the one also used in the comparative analysis.

We recommend reading the article referenced in the original repository to get a better sense of the core's architecture.

> ℹ️ **Note**
> 
> If using the testbench, it is necessary to change all the paths [here](tb/tb_pkg.sv).
> 
> When synthesizing the design, the ```ZETAS_PATH``` parameter will need to be set in the top-level ```dilithium``` module.
> In the case of Vivado, this can be done using the TCL console:
>
> ```tcl
> set_property generic {ZETAS_PATH="/path/to/zetas.txt"} [current_fileset]
> ```

# Changes made

Here we present a very brief summary of the main changes made to the core.

## Streaming interface

The original core is designed with a streaming interface very similar to that of AXI-Stream (a fact which is also referenced in the article), coupled with a side-band for certain control signals, such as `start` and `sec_level`.
However, the original design did not fully adhere to the AXI-Stream handshaking protocol. Specifically, it would assert `TVALID` and continously stream output even when `TREADY` was not asserted; that is, the core would assume the requester is always ready to receive output data (as is the case of the testbench).

There is a way of fixing this which would involve changing the design's FSMs more deeply. That said, the simplest and most straight-forward fix was to introduce a buffer that captures the core's output and retransmits it to the streaming interface, correctly following the protocol.
It should be noted that this solution does increase the amount of resources used by the design, but the additional buffer represents less than 3% of the total memory originally needed.


## Back pressure

Somewhat related to the previous problem, the original design would also assume that the requester has the input data continously available as soon as the core needed it, which led to some problems.

In order to reduce latency, the original core was developed with a high degree of parallelism; it often executes a task while also ingesting the input data necessary for the next one. When changing FSM states, however, the design typically assumed that the ingestion would be done by the time the other task, supposedly more time-consuming, was finished. Obviously, this is not necessarily true in a real-life scenario, in which I/O might be the bottleneck.

Solving this required changing the designs's FSMs (particularly the ones related to the Verify operation), and adding signals that correctly assert if all tasks are finished before transitioning states.

## Reset signals

Some minor bugs were found concerning the incorrect initialization and resetting of certain signals. Some of these bugs would not show up in simulations — only in synthesized designs — and others only showed up when using *specific* simulation tools, such as QuestaSim and Active-HDL's simulator. All of these bugs were duly fixed.


## SHAKE core

The original SHAKE core used for the required hashing operations was written in VHDL.
A comparable design was developed in SystemVerilog, and used in this revision.
Although no bug was found in the original core, this change was made to facilitate using simulation tools that do not support VHDL, such as Verilator.