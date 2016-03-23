
# PlanAhead Launch Script for Post-Synthesis pin planning, created by Project Navigator

create_project -name SpiLink -dir "C:/Users/TM/Desktop/FPGA/SpiLink/SpiLink/planAhead_run_2" -part xc6slx9tqg144-3
set_property design_mode GateLvl [get_property srcset [current_run -impl]]
set_property edif_top_file "C:/Users/TM/Desktop/FPGA/SpiLink/SpiLink/Master_Test.ngc" [ get_property srcset [ current_run ] ]
add_files -norecurse { {C:/Users/TM/Desktop/FPGA/SpiLink/SpiLink} }
set_param project.pinAheadLayout  yes
set_property target_constrs_file "Master_Test.ucf" [current_fileset -constrset]
add_files [list {Master_Test.ucf}] -fileset [get_property constrset [current_run]]
link_design
