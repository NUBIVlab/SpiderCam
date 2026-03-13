# Floating Point Image Processing SV RTL
Contains parameterized floating point  
- adder
- multiplier
- divider

Parameterized as in you can select a custom number of bits for exponent and fractional parts i.e to support FP16 or FP32 (or anything above and in between like FP24). It's almost to the IEEE-754 with the exceptions of disabling subnormal number support and the rounding isn't perfect (ties always round up and instead of having a round and guard bit, there is just a round bit). This was done to make it more area efficient when deploying on FPGA platforms.

There is also the modules
- window fetcher
- convolution floating point
  
The window fetcher grabs a window of values from a data stream (such as a pixel stream). The convolution module takes a window of values and a kernel and performs the convolution (MAC operation). Since kernels are often sparse matrices and/or with powers of 2, there is also the 'optimal_convolution_floating_point_generator.py" in the tools folder which generates the necessary wrappers to optimize away 0 values for multiplies and consequently the sparse adder trees. View the python file itself to see how to call it.
  
By combining these building blocks modules, we can build networks of convolution filters with the data streaming model. This is showcased in the DfDD project.

## Depth from Differential Defocus (DfDD) Project
I am currently part of the BiV lab headed by Professor Emma Alexander at Northwestern University (see https://www.alexander.vision/). DfDD in general is a technique where if you capture two images of the same scene but with slightly different focus levels, you can use those defocus cues to extract depth information (to produce a sparse depth map). As can be seen in the diagram, we have to two image sensors recieving the same image from the beam splitter, but at slightly different focus levels, whcih are then fed to the development board via the ribbon cables. In order to align the images, we use an affine transformation matrix with bilinear interpolation. Then through a series of convolutions and finally a division, it produces a depth map which is then communicated via an FT232H chip to the host computer to be displayed. This is all pipelined and accomplished via stream processing which allows us to buffer way fewer lines, meaning we don't need dedicated SDRAM which would consume a lot of power and can instead rely on the FPGA's embedded memory. I developed the RTL code to perform all these tasks on the FPGA (ECP5). We submitted a paper to CVPR which i am co-first authored with Tianao Li and John Mamish. For details about the CVPR submission and live demo video, please contact me.

## Folder Structure
### rtl
Contains RTL code.
### |--> third_party
Contains third part RTL code.
### |--> verify_files
Verifying that my floating point modules are correct is tricky bussiness. Thus on top of using formal equivalence verification (by comparing my results to the CPUs results), I also wrote these informal 'verify_files' that detail steps I took, which I then proof read some number of times.
### tb
Contains all relevant testbench code done using Formal Equivalence Verification (FEV). This is a fancy way of saying I compared the DUT results to theoretical golden models as a verification methodology. It is structured and decoupled in a way that makes most sense to me and is generally applicable.
### |--> components
Organized the standard components that using OOP part of System Verilog is built and quite handy for; drivers, generators, golden models, interfaces, monitors, scoreboards and utilities, package manager. Very briefly essentially it follows the Bus Functional Model (BFM) where you pass the main interface as a virtual interface to the named components and connect these components via blocking queues as seen in each of the *_tb subfolders that correspond to the DUTl. 
### |--> *_tb/simulate
Contains the script to run the simulation on modelsim (specifically through Diamond).
### synth
This contains all the synthesis folders. The synthesis folders contain the final 'top' files and various scripts to perform synthesis. In this case, the folders are targetted towards to ECP5 fpga using Yosys's Trellis Project + Nextpnr (see https://github.com/YosysHQ/prjtrellis). 
### Tools
Mainly python scripts that do useful things (like my optimal convolution generator) and miscellaneous tasks.






