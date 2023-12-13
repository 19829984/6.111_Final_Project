create_project -force -part xc7s50csga324-1 ip_tb ip_tb


read_verilog -sv [ glob ./hdl/*.sv ]
read_verilog [ glob ./hdl/*.v ]
read_verilog -sv [ glob ./sim/*.sv ]

read_ip ./ip/mult1Q3232Q6464/mult1Q3232Q6464.xci
generate_target all [get_ips]
synth_ip [get_ips]

set_property top rasterizer_tb [get_fileset sim_1]
synth_design -top rasterizer_tb
launch_simulation
restart
open_vcd
log_vcd *
run all
flush_vcd
close_vcd