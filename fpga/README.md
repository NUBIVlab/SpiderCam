# Floating Point Image Processing SV RTL

Contains parameterized floating point\
- adder\
- multiplier\
- divider

Parameterized as in you can select a custom number of bits for exponent
and fractional parts i.e to support FP16 or FP32 (or anything above and
in between like FP24). It's almost to the IEEE-754 with the exceptions
of disabling subnormal number support and the rounding isn't perfect
(ties always round up and instead of having a round and guard bit, there
is just a round bit). This was done to make it more area efficient when
deploying on FPGA platforms.

There is also the modules\
- window fetcher\
- convolution floating point

The window fetcher grabs a window of values from a data stream (such as
a pixel stream). The convolution module takes a window of values and a
kernel and performs the convolution (MAC operation). Since kernels are
often sparse matrices and/or with powers of 2, there is also the
`optimal_convolution_floating_point_generator.py` in the tools folder
which generates the necessary wrappers to optimize away 0 values for
multiplies and consequently the sparse adder trees. View the python file
itself to see how to call it.

By combining these building blocks modules, we can build networks of
convolution filters with the data streaming model. This is showcased in
the DfDD project.

------------------------------------------------------------------------

# Folder Structure

### rtl

Contains RTL code.

### → third_party

Contains third party RTL code.

### → verify_files

Verifying that my floating point modules are correct is tricky business.
Thus on top of using formal equivalence verification (by comparing my
results to the CPU's results), I also wrote these informal
`verify_files` that detail steps I took, which I then proof read some
number of times.

### tb

Contains all relevant testbench code done using Formal Equivalence
Verification (FEV). This is a fancy way of saying I compared the DUT
results to theoretical golden models as a verification methodology. It
is structured and decoupled in a way that makes most sense to me and is
generally applicable.

### → components

Organized the standard components that using the OOP part of
SystemVerilog is built and quite handy for; drivers, generators, golden
models, interfaces, monitors, scoreboards and utilities, package
manager.

Very briefly, it follows the Bus Functional Model (BFM) where you pass
the main interface as a virtual interface to the named components and
connect these components via blocking queues as seen in each of the
`*_tb` subfolders that correspond to the DUT.

### → \*\_tb/simulate

Contains the script to run the simulation on ModelSim (specifically
through Diamond).

### synth

This contains all the synthesis folders. The synthesis folders contain
the final `top` files and various scripts to perform synthesis.

In this case, the folders are targeted towards the ECP5 FPGA using
Yosys's Trellis Project + Nextpnr\
https://github.com/YosysHQ/prjtrellis

### Tools

Mainly python scripts that do useful things (like my optimal convolution
generator) and miscellaneous tasks.

------------------------------------------------------------------------

# Bitstreams and Running the GUI

The FPGA bitstream used to program the board must correspond to how the
GUI is configured. The GUI expects a specific data format depending on
which processing pipeline is programmed onto the FPGA.

## Bitstream Variants

### dual_scale → dxdy → radial → pre → top.bit

This bitstream configures the pipeline with:

-   Dual-scale network enabled\
-   `dx` and `dy` filters enabled\
-   Radial `a/b` terms enabled\
-   Preprocessing performed in hardware\
-   Slow frame rate mode

Outputs **two windows**:

-   `cam_0`
-   Depth output

------------------------------------------------------------------------

### dual_scale → pass → simple → nopre → top.bit

This bitstream configures the pipeline with:

-   Dual-scale network enabled\
-   `dx` and `dy` filters disabled\
-   Single (non-radial) `a/b` term\
-   No preprocessing\
-   Slow frame rate mode

Outputs **two windows**:

-   `cam_0`
-   Depth output

------------------------------------------------------------------------

### camera_previewer → top.bit

This bitstream encodes logic that simply passes through `cam_0` and
`cam_1` without any processing.

It runs at slow frame rate and outputs **two windows**.

This configuration is useful when capturing raw sensor data for
processing or performing homography calibration between the two cameras.

------------------------------------------------------------------------

### pre_fast variants

The `pre_fast` versions enable the high frame rate pipeline (\~30 FPS).

In this configuration the system outputs **a single window** containing
only the depth output.

------------------------------------------------------------------------

# Running the GUI

Depending on the programmed bitstream, the GUI must be launched with the
correct number of channels and frame-rate mode.

### Two output windows (slow frame rate mode)

``` bash
python .\serialcam_stream_ft232h.py --width 500 --height 480 --maxchannels 2 --fast 0
```

Displays:

-   `cam_0`
-   depth output

------------------------------------------------------------------------

### One output window (fast frame rate mode)

``` bash
python .\serialcam_stream_ft232h.py --width 500 --height 480 --maxchannels 1 --fast 1
```

Displays:

-   depth output only (high frame rate mode)
