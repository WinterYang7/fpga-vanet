
# PlanAhead Launch Script for Post-Synthesis floorplanning, created by Project Navigator

create_project -name Total_link -dir "C:/Users/TM/Desktop/FPGA/Total/Total_link/planAhead_run_3" -part xc6slx9tqg144-3
set_property design_mode GateLvl [get_property srcset [current_run -impl]]
set_property edif_top_file "C:/Users/TM/Desktop/FPGA/Total/Total_link/total_link.ngc" [ get_property srcset [ current_run ] ]
add_files -norecurse { {C:/Users/TM/Desktop/FPGA/Total/Total_link} }
set_property target_constrs_file "total_link.ucf" [current_fileset -constrset]
add_files [list {total_link.ucf}] -fileset [get_property constrset [current_run]]
link_design
