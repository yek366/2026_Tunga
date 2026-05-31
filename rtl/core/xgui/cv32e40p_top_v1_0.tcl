# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "COREV_CLUSTER" -parent ${Page_0}
  ipgui::add_param $IPINST -name "COREV_PULP" -parent ${Page_0}
  ipgui::add_param $IPINST -name "FPU" -parent ${Page_0}
  ipgui::add_param $IPINST -name "FPU_ADDMUL_LAT" -parent ${Page_0}
  ipgui::add_param $IPINST -name "FPU_OTHERS_LAT" -parent ${Page_0}
  ipgui::add_param $IPINST -name "NUM_MHPMCOUNTERS" -parent ${Page_0}
  ipgui::add_param $IPINST -name "ZFINX" -parent ${Page_0}


}

proc update_PARAM_VALUE.COREV_CLUSTER { PARAM_VALUE.COREV_CLUSTER } {
	# Procedure called to update COREV_CLUSTER when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.COREV_CLUSTER { PARAM_VALUE.COREV_CLUSTER } {
	# Procedure called to validate COREV_CLUSTER
	return true
}

proc update_PARAM_VALUE.COREV_PULP { PARAM_VALUE.COREV_PULP } {
	# Procedure called to update COREV_PULP when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.COREV_PULP { PARAM_VALUE.COREV_PULP } {
	# Procedure called to validate COREV_PULP
	return true
}

proc update_PARAM_VALUE.FPU { PARAM_VALUE.FPU } {
	# Procedure called to update FPU when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.FPU { PARAM_VALUE.FPU } {
	# Procedure called to validate FPU
	return true
}

proc update_PARAM_VALUE.FPU_ADDMUL_LAT { PARAM_VALUE.FPU_ADDMUL_LAT } {
	# Procedure called to update FPU_ADDMUL_LAT when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.FPU_ADDMUL_LAT { PARAM_VALUE.FPU_ADDMUL_LAT } {
	# Procedure called to validate FPU_ADDMUL_LAT
	return true
}

proc update_PARAM_VALUE.FPU_OTHERS_LAT { PARAM_VALUE.FPU_OTHERS_LAT } {
	# Procedure called to update FPU_OTHERS_LAT when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.FPU_OTHERS_LAT { PARAM_VALUE.FPU_OTHERS_LAT } {
	# Procedure called to validate FPU_OTHERS_LAT
	return true
}

proc update_PARAM_VALUE.NUM_MHPMCOUNTERS { PARAM_VALUE.NUM_MHPMCOUNTERS } {
	# Procedure called to update NUM_MHPMCOUNTERS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.NUM_MHPMCOUNTERS { PARAM_VALUE.NUM_MHPMCOUNTERS } {
	# Procedure called to validate NUM_MHPMCOUNTERS
	return true
}

proc update_PARAM_VALUE.ZFINX { PARAM_VALUE.ZFINX } {
	# Procedure called to update ZFINX when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.ZFINX { PARAM_VALUE.ZFINX } {
	# Procedure called to validate ZFINX
	return true
}


proc update_MODELPARAM_VALUE.COREV_PULP { MODELPARAM_VALUE.COREV_PULP PARAM_VALUE.COREV_PULP } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.COREV_PULP}] ${MODELPARAM_VALUE.COREV_PULP}
}

proc update_MODELPARAM_VALUE.COREV_CLUSTER { MODELPARAM_VALUE.COREV_CLUSTER PARAM_VALUE.COREV_CLUSTER } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.COREV_CLUSTER}] ${MODELPARAM_VALUE.COREV_CLUSTER}
}

proc update_MODELPARAM_VALUE.FPU { MODELPARAM_VALUE.FPU PARAM_VALUE.FPU } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.FPU}] ${MODELPARAM_VALUE.FPU}
}

proc update_MODELPARAM_VALUE.FPU_ADDMUL_LAT { MODELPARAM_VALUE.FPU_ADDMUL_LAT PARAM_VALUE.FPU_ADDMUL_LAT } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.FPU_ADDMUL_LAT}] ${MODELPARAM_VALUE.FPU_ADDMUL_LAT}
}

proc update_MODELPARAM_VALUE.FPU_OTHERS_LAT { MODELPARAM_VALUE.FPU_OTHERS_LAT PARAM_VALUE.FPU_OTHERS_LAT } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.FPU_OTHERS_LAT}] ${MODELPARAM_VALUE.FPU_OTHERS_LAT}
}

proc update_MODELPARAM_VALUE.ZFINX { MODELPARAM_VALUE.ZFINX PARAM_VALUE.ZFINX } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.ZFINX}] ${MODELPARAM_VALUE.ZFINX}
}

proc update_MODELPARAM_VALUE.NUM_MHPMCOUNTERS { MODELPARAM_VALUE.NUM_MHPMCOUNTERS PARAM_VALUE.NUM_MHPMCOUNTERS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.NUM_MHPMCOUNTERS}] ${MODELPARAM_VALUE.NUM_MHPMCOUNTERS}
}

