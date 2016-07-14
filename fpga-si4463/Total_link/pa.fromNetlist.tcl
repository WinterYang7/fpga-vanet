
# PlanAhead Launch Script for Post-Synthesis pin planning, created by Project Navigator

create_project -name Total_link -dir "E:/work/FPGA/Workspace/0616/Total_link/planAhead_run_1" -part xc6slx45tfgg484-2
set_property design_mode GateLvl [get_property srcset [current_run -impl]]
set_property edif_top_file "E:/work/FPGA/Workspace/0616/Total_link/total_link.ngc" [ get_property srcset [ current_run ] ]
add_files -norecurse { {E:/work/FPGA/Workspace/0616/Total_link} }
set_param project.pinAheadLayout  yes
set_property target_constrs_file "total_link.ucf" [current_fileset -constrset]
add_files [list {total_link.ucf}] -fileset [get_property constrset [current_run]]
link_design
