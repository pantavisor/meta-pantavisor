setenv pv_baseargs "root=/dev/ram rootfstype=ramfs rdinit=/usr/bin/pantavisor pv_storage.device=LABEL=root pv_storage.fstype=ext4"
setenv pv_mmcdev ${mmcdev}
setenv pv_mmcboot 0
setenv pv_ctrl 1
setenv devtype mmc
setenv envloadaddr ${loadaddr}
part size ${devtype} ${pv_mmcdev} ${pv_ctrl} pv_config_size
if test "${pv_config_size}" = "800"; then
	echo Found PV OEM Config at ${devtype} ${pv_mmcdev}:2
	part start ${devtype} ${pv_mmcdev} ${pv_ctrl} pv_config_start
	${devtype} read ${envloadaddr} ${pv_config_start} ${pv_config_size}
	env import ${envloadaddr} 0x1000
	setexpr pv_mmcdata ${pv_ctrl} + 1
else
	setexpr pv_mmcdata ${pv_mmcboot} + 1
fi
load ${devtype} ${pv_mmcdev}:${pv_mmcdata} ${envloadaddr} /boot/uboot.txt; setenv uboot_txt_size ${filesize}

echo Loading pantavisor uboot.txt
setenv pv_try; env import ${envloadaddr} ${uboot_txt_size}

load ${devtype} ${pv_mmcdev}:${pv_mmcboot} ${envloadaddr} pv.env; setenv pv_env_size ${filesize}
echo Loading pv.env
setenv pv_trying; env import ${envloadaddr} ${pv_env_size}

echo
if env exists pv_try; then
	if env exists pv_trying && test ${pv_trying} = ${pv_try}; then
		echo Pantavisor boots checkpoint revision ${pv_rev} after failed try-boot of revision: ${pv_try}
		setenv pv_trying
		env export ${envloadaddr} pv_trying; setenv pv_env_size ${filesize};
		save ${devtype} ${pv_mmcdev}:${pv_mmcboot} ${envloadaddr} pv.env ${pv_env_size}
		setenv boot_rev ${pv_rev}
	else
		echo Pantavisor boots try-boot revision: ${pv_try}
		setenv pv_trying ${pv_try}
		env export ${envloadaddr} pv_trying; setenv pv_env_size ${filesize};
		save ${devtype} ${pv_mmcdev}:${pv_mmcboot} ${envloadaddr} pv.env ${pv_env_size}
		setenv boot_rev ${pv_trying}
	fi
else
	echo Pantavisor boots revision: ${pv_rev}
	setenv boot_rev ${pv_rev}
fi

echo Pantavisor loading FDT at ${fdt_addr_r}
echo "load ${devtype} ${pv_mmcdev}:${pv_mmcdata} ${fdt_addr_r} /trails/${boot_rev}/.pv/pv-fdt.dtb"
if load ${devtype} ${pv_mmcdev}:${pv_mmcdata} ${fdt_addr_r} /trails/${boot_rev}/.pv/pv-fdt.dtb; then
	echo "Successfully loaded pv-fdt.dtb"
else
	load ${devtype} ${pv_mmcdev}:${pv_mmcdata} ${fdt_addr_r} /trails/${boot_rev}/bsp/${fdtfile}
fi
fdt addr ${fdt_addr_r}
fdt get value fdtbootargs /chosen bootargs

echo Pantavisor bootargs: "${pv_baseargs} pv_try=${pv_try} pv_rev=${boot_rev} panic=2 ${fdtbootargs} ${configargs} ${localargs}"
setenv bootargs "${pv_baseargs} pv_try=${pv_try} pv_rev=${boot_rev} panic=2 ${fdtbootargs} ${configargs} ${localargs}"
echo Pantavisor kernel load: load ${devtype} ${pv_mmcdev}:${pv_mmcdata} ${kernel_addr_r} /trails/${boot_rev}/.pv/pv-kernel.img
load ${devtype} ${pv_mmcdev}:${pv_mmcdata} ${kernel_addr_r} /trails/${boot_rev}/.pv/pv-kernel.img
echo Pantavisor initrd load: load ${devtype} ${pv_mmcdev}:${pv_mmcdata} ${initrd_addr} /trails/${boot_rev}/.pv/pv-initrd.img
load ${devtype} ${pv_mmcdev}:${pv_mmcdata} ${initrd_addr} /trails/${boot_rev}/.pv/pv-initrd.img
setenv rd_size ${filesize}
setexpr rd_offset ${initrd_addr} + ${rd_size}
setenv i 0
while load ${devtype} ${pv_mmcdev}:${pv_mmcdata} ${rd_offset} /trails/${boot_rev}/.pv/pv-initrd.img.${i}; do
	echo Pantavisor initrd addon loaded: load ${devtype} ${mmcdev}:${mmcdata} ${rd_offset} /trails/${boot_rev}/.pv/pv-initrd.img.${i}
	setexpr i ${i} + 1
	setexpr rd_size ${rd_size} + ${filesize}
	setexpr rd_offset ${rd_offset} + ${filesize}
done
echo "Pantavisor go... : booti ${kernel_addr_r} ${initrd_addr}:${rd_size} ${fdt_addr_r}"
booti ${kernel_addr_r} ${initrd_addr}:${rd_size} ${fdt_addr_r}
echo "Failed to boot step, rebooting"; sleep 5; reset

