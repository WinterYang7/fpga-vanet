
# PlanAhead Launch Script for Pre-Synthesis Floorplanning, created by Project Navigator

create_project -name SpiLink -dir "C:/Users/TM/Desktop/FPGA/SpiLink/SpiLink/planAhead_run_1" -part xc6slx9tqg144-3
set_param project.pinAheadLayout yes
set srcset [get_property srcset [current_run -impl]]
set_property target_constrs_file "Master_Test.ucf" [current_fileset -constrset]
set hdlfile [add_files [list {spi_master.v}]]
set_property file_type Verilog $hdlfile
set_property library work $hdlfile
set hdlfile [add_files [list {master_test.v}]]
set_property file_type Verilog $hdlfile
set_property library work $hdlfile
set_property top Master_Test $srcset
add_files [list {Master_Test.ucf}] -fileset [get_property constrset [current_run]]
open_rtl_design -part xc6slx9tqg144-3
