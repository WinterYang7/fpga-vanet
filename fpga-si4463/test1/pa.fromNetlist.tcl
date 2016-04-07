
# PlanAhead Launch Script for Post-Synthesis pin planning, created by Project Navigator

create_project -name test1 -dir "C:/Users/TM/Desktop/FPGA/Total/test1/planAhead_run_1" -part xc6slx9tqg144-3
set_property design_mode GateLvl [get_property srcset [current_run -impl]]
set_property edif_top_file "C:/Users/TM/Desktop/FPGA/Total/test1/test1.ngc" [ get_property srcset [ current_run ] ]
add_files -norecurse { {C:/Users/TM/Desktop/FPGA/Total/test1} }
set_param project.pinAheadLayout  yes
set_property target_constrs_file "test1.ucf" [current_fileset -constrset]
add_files [list {test1.ucf}] -fileset [get_property constrset [current_run]]
link_design
