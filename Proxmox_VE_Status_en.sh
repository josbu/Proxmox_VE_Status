#!/usr/bin/env bash

## Build 20231112

#"/usr/share/perl5/PVE/API2/Nodes.pm"
#"/usr/share/pve-manager/js/pvemanagerlib.js"
#"/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"

# 检查并安装工具包
if [[ -z $(which sensors) || -z $(which iostat) ]]; then
    apt-get update > /dev/null 2>&1
    if [ -z $(which sensors) ]; then
        echo -e "Package lm-sensors Install ......"
        apt-get install -y lm-sensors > /dev/null 2>&1
    fi

    if [ -z $(which iostat) ]; then
        echo -e "Package sysstat Install ......"
        apt-get install -y sysstat > /dev/null 2>&1
    fi
fi

# 设定工具权限
if [ -n $(which sensors) ]; then
    chmod +s /usr/sbin/smartctl
fi
if [ -n $(which iostat) ]; then
    chmod +s /usr/bin/iostat
fi

# 识别 CPU 平台
cpu_platform="$(lscpu | grep 'Model name' | grep -E 'Intel|AMD')"
case $cpu_platform in
    *Intel*)
          CPU="Intel"
          cpu_keyword="coretemp-isa"
          ;;
    *AMD*)
          CPU="AMD"
          cpu_keyword="k10temp-pci-"
          ;;
    *)
          echo -e "Unsupported CPU Architecture"
          ;;
esac

# CPU 主频及温度等信息 API
cpu_info_api='		
	my $cpufreqs = `lscpu | grep MHz`;
	my $corefreqs = `cat /proc/cpuinfo | grep -i  "cpu MHz"`;
	$res->{cpu_frequency} = $cpufreqs . $corefreqs;

    $res->{cpu_temperatures} = `sensors`;
		'

# CPU 主频信息 Web UI
cpu_freq_display=',
	{
	    itemId: '"'"'cpu-frequency'"'"',
	    colspan: 2,
	    printBar: false,
	    title: gettext('"'"'CPU Frequency'"'"'),
	    textField: '"'"'cpu_frequency'"'"',
	    renderer:function(value){
	        let output = '"'"''"'"';
	        let cpufreqs = value.matchAll(/^CPU MHz.*?(\d+\.\d+)\\n^CPU max MHz.*?(\d+)\.\d+\\n^CPU min MHz.*?(\d+)\.\d+\\n/gm);
              for (const cpufreq of cpufreqs) {
                  output += `Real-time frequency: ${cpufreq[1]} MHz | Min: ${cpufreq[3]} MHz | Max: ${cpufreq[2]} MHz\\n`;
              }

	        let corefreqs = value.match(/^cpu MHz.*?(\d+\.\d+)/gm);
	        if (corefreqs.length > 0) {
	            for (i = 1;i < corefreqs.length;) {
	                for (const corefreq of corefreqs) {
	                    output += `Thread ${i++}: ${corefreq.match(/(?<=:\s+)(\d+\.\d+)/g)} MHz`;
	                    output += '"'"' | '"'"';
	                    if ((i-1) % 4 == 0){
	                        output = output.slice(0, -2);
	                        output += '"'"'\\n'"'"';
	                    }
	                }
	            }
	        } else { 
	            output += '"'"'('"'"';
	            output += `${corefreqs}`;
	            output += '"'"')'"'"';
	        }
	        return output.replace(/\\n/g, '"'"'<br>'"'"');
	    }
	},'

# CPU 温度信息 Web UI
if [ $CPU = "Intel" ]; then
    cpu_temp_display='
	{
	    itemId: '"'"'cpu-temperatures'"'"',
	    colspan: 2,
	    printBar: false,
	    title: gettext('"'"'CPU Temp'"'"'),
	    textField: '"'"'cpu_temperatures'"'"',
	    renderer: function(value) {
	        value = value.replace(/Â/g, '"'"''"'"');
	        let data = [];
	        let cpus = value.matchAll(/^coretemp-isa-(\d{4})$\\n.*?\\n((?:Package|Core)[\s\S]*?^\\n)+/gm);
	        for (const cpu of cpus) {
	            let cpuNumber = parseInt(cpu[1], 10);
	            data[cpuNumber] = {
	                   packages: [],
	                   cores: []
	            };

	            let packages = cpu[2].matchAll(/^Package id \d+:\s*\+([^°]+).*$/gm);
	            for (const package of packages) {
	                data[cpuNumber]['"'"'packages'"'"'].push(package[1]);
	            }

	            let cores = cpu[2].matchAll(/^Core \d+:\s*\+([^°]+).*$/gm);
	            for (const core of cores) {
	                data[cpuNumber]['"'"'cores'"'"'].push(core[1]);
	            }
	        }

	        let output = '"'"''"'"';
	        for (const [i, cpu] of data.entries()) {
	            if (cpu.packages.length > 0) {
	                for (const packageTemp of cpu.packages) {
	                    output += `CPU ${i+1}: ${packageTemp}°C `;
	                }
	            }

	            if (cpu.cores.length > 0 && cpu.cores.length <= 4) {
	                output += '"'"'('"'"';
	                for (j = 1;j < cpu.cores.length;) {
	                    for (const coreTemp of cpu.cores) {
	                        output += `Core ${j++}: ${coreTemp}°C, `;
	                    }
	                }
	                output = output.slice(0, -2);
	                output += '"'"')'"'"';
	            }

	            let acpitzs = value.matchAll(/^acpitz-acpi-(\d*)$\\n.*?\\n((?:temp)[\s\S]*?^\\n)+/gm);
	            for (const acpitz of acpitzs) {
	                let acpitzNumber = parseInt(acpitz[1], 10);
	                data[acpitzNumber] = {
	                       acpisensors: []
	                };

	                let acpisensors = acpitz[2].matchAll(/^temp\d+:\s*\+([^°]+).*$/gm);
	                for (const acpisensor of acpisensors) {
	                    data[acpitzNumber]['"'"'acpisensors'"'"'].push(acpisensor[1]);
	                }

	                for (const [k, acpitz] of data.entries()) {
	                    if (acpitz.acpisensors.length > 0) {
	                        output += '"'"' | MB: '"'"';
	                        for (const acpiTemp of acpitz.acpisensors) {
	                            output += `${acpiTemp}°C, `;
	                        }
	                        output = output.slice(0, -2);
	                    }
	                }
	            }

	            let FunStates = value.matchAll(/^[a-zA-z]{2,3}\d{4}-isa-(\w{4})$\\n((?![ \S]+: *\d+ +RPM)[ \S]*?\\n)*((?:[ \S]+: *\d+ RPM)[\s\S]*?^\\n)+/gm);
	            for (const FunState of FunStates) {
	                let FanNumber = 0;
	                data[FanNumber] = {
	                    rotationals: [],
	                    cpufans: [],
	                    pumpfans: [],
	                    systemfans: []
	                };

	                let rotationals = FunState[3].match(/^([ \S]+: *[0-9]\d* +RPM)[ \S]*?$/gm);
	                for (const rotational of rotationals) {
	                    if (rotational.toLowerCase().indexOf("pump") !== -1 || rotational.toLowerCase().indexOf("opt") !== -1){
	                        let pumpfans = rotational.matchAll(/^[ \S]+: *([1-9]\d*) +RPM[ \S]*?$/gm);
	                        for (const pumpfan of pumpfans) {
	                            data[FanNumber]['"'"'pumpfans'"'"'].push(pumpfan[1]);
	                        }
	                    } else if (rotational.toLowerCase().indexOf("cpu") !== -1){
	                        let cpufans = rotational.matchAll(/^[ \S]+: *([1-9]\d*) +RPM[ \S]*?$/gm);
	                        for (const cpufan of cpufans) {
	                            data[FanNumber]['"'"'cpufans'"'"'].push(cpufan[1]);
	                        }
	                    } else {
	                        let systemfans = rotational.matchAll(/^[ \S]+: *([1-9]\d*) +RPM[ \S]*?$/gm);
	                        for (const systemfan of systemfans) {
	                            data[FanNumber]['"'"'systemfans'"'"'].push(systemfan[1]);
	                        }
	                    }
	                }

	                for (const [j, FunState] of data.entries()) {
	                    if (FunState.cpufans.length > 0 || FunState.pumpfans.length > 0 || FunState.systemfans.length > 0) {
	                        output += '"'"' | Fan: '"'"';
	                        if (FunState.cpufans.length > 0) {
	                            output += '"'"'CPU-'"'"';
	                            for (const cpufan_value of FunState.cpufans) {
	                                output += `${cpufan_value} RPM, `;
	                            }
	                        }

	                        if (FunState.pumpfans.length > 0) {
	                            output += '"'"'Liquid cooling-'"'"';
	                            for (const pumpfan_value of FunState.pumpfans) {
	                                output += `${pumpfan_value} RPM, `;
	                            }
	                        }

	                        if (FunState.systemfans.length > 0) {
	                            if (FunState.cpufans.length > 0 || FunState.pumpfans.length > 0) {
	                                output += '"'"'Sys-'"'"';
	                            }
	                            for (const systemfan_value of FunState.systemfans) {
	                                output += `${systemfan_value} RPM, `;
	                            }
	                        }
	                        output = output.slice(0, -2);
	                    } else if (FunState.cpufans.length == 0 && FunState.pumpfans.length == 0 && FunState.systemfans.length == 0) {
	                        output += '"'"' | Fan: Stop'"'"';
	                    }
	                }
	            }

	            if (cpu.cores.length > 4) {
	                output += '"'"'\\n'"'"';
	                for (j = 1;j < cpu.cores.length;) {
	                    for (const coreTemp of cpu.cores) {
	                        output += `Core ${j++}: ${coreTemp}°C`;
	                        output += '"'"' | '"'"';
	                        if ((j-1) % 4 == 0){
	                            output = output.slice(0, -2);
	                            output += '"'"'\\n'"'"';
	                        }
	                    }
	                }
	                output = output.slice(0, -2);
	            }
	        }

	        return output.replace(/\\n/g, '"'"'<br>'"'"');
	    }
	}'
elif [ $CPU = "AMD" ]; then
    cpu_temp_display=',
	{
	    itemId: '"'"'cpu-temperatures'"'"',
	    colspan: 2,
	    printBar: false,
	    title: gettext('"'"'CPU Temp'"'"'),
	    textField: '"'"'cpu_temperatures'"'"',
	    renderer: function(value) {
	        value = value.replace(/Â/g, '"'"''"'"');
	        let data = [];
	        let cpus = value.matchAll(/^k10temp-pci-(\w{4})$\\n.*?\\n((?:Tctl)[\s\S]*?^\\n)+/gm);
	        for (const cpu of cpus) {
	            let cpuNumber = 0;
	            data[cpuNumber] = {
	                   packages: []
	            };

	            let packages = cpu[2].matchAll(/^Tctl:\s*\+([^°]+).*$/gm);
	            for (const package of packages) {
	                data[cpuNumber]['"'"'packages'"'"'].push(package[1]);
	            }
	        }

	        let output = '"'"''"'"';
	        for (const [i, cpu] of data.entries()) {
	            if (cpu.packages.length > 0) {
	                for (const packageTemp of cpu.packages) {
	                    output += `CPU ${i+1}: ${packageTemp}°C `;
	                }
	            }

	            let gpus = value.matchAll(/^amdgpu-pci-(\d*)$\\n((?!edge:)[ \S]*?\\n)*((?:edge)[\s\S]*?^\\n)+/gm);
	            for (const gpu of gpus) {
	                let gpuNumber = 0;
	                data[gpuNumber] = {
	                       edges: []
	                };

	                let edges = gpu[3].matchAll(/^edge:\s*\+([^°]+).*$/gm);
	                for (const edge of edges) {
	                    data[gpuNumber]['"'"'edges'"'"'].push(edge[1]);
	                }

	                for (const [k, gpu] of data.entries()) {
	                    if (gpu.edges.length > 0) {
	                        output += '"'"' | Integrated Graphics: '"'"';
	                        for (const edgeTemp of gpu.edges) {
	                            output += `${edgeTemp}°C, `;
	                        }
	                        output = output.slice(0, -2);
	                    }
	                }
	            }

	            let FunStates = value.matchAll(/^[a-zA-z]{2,3}\d{4}-isa-(\w{4})$\\n((?![ \S]+: *\d+ +RPM)[ \S]*?\\n)*((?:[ \S]+: *\d+ RPM)[\s\S]*?^\\n)+/gm);
	            for (const FunState of FunStates) {
	                let FanNumber = 0;
	                data[FanNumber] = {
	                    rotationals: [],
	                    cpufans: [],
	                    pumpfans: [],
	                    systemfans: []
	                };

	                let rotationals = FunState[3].match(/^([ \S]+: *[0-9]\d* +RPM)[ \S]*?$/gm);
	                for (const rotational of rotationals) {
	                    if (rotational.toLowerCase().indexOf("pump") !== -1 || rotational.toLowerCase().indexOf("opt") !== -1){
	                        let pumpfans = rotational.matchAll(/^[ \S]+: *([1-9]\d*) +RPM[ \S]*?$/gm);
	                        for (const pumpfan of pumpfans) {
	                            data[FanNumber]['"'"'pumpfans'"'"'].push(pumpfan[1]);
	                        }
	                    } else if (rotational.toLowerCase().indexOf("cpu") !== -1){
	                        let cpufans = rotational.matchAll(/^[ \S]+: *([1-9]\d*) +RPM[ \S]*?$/gm);
	                        for (const cpufan of cpufans) {
	                            data[FanNumber]['"'"'cpufans'"'"'].push(cpufan[1]);
	                        }
	                    } else {
	                        let systemfans = rotational.matchAll(/^[ \S]+: *([1-9]\d*) +RPM[ \S]*?$/gm);
	                        for (const systemfan of systemfans) {
	                            data[FanNumber]['"'"'systemfans'"'"'].push(systemfan[1]);
	                        }
	                    }
	                }

	                for (const [j, FunState] of data.entries()) {
	                    if (FunState.cpufans.length > 0 || FunState.pumpfans.length > 0 || FunState.systemfans.length > 0) {
	                        output += '"'"' | Fan: '"'"';
	                        if (FunState.cpufans.length > 0) {
	                            output += '"'"'CPU-'"'"';
	                            for (const cpufan_value of FunState.cpufans) {
	                                output += `${cpufan_value} RPM, `;
	                            }
	                        }

	                        if (FunState.pumpfans.length > 0) {
	                            output += '"'"'Liquid cooling-'"'"';
	                            for (const pumpfan_value of FunState.pumpfans) {
	                                output += `${pumpfan_value} RPM, `;
	                            }
	                        }

	                        if (FunState.systemfans.length > 0) {
	                            if (FunState.cpufans.length > 0 || FunState.pumpfans.length > 0) {
	                                output += '"'"'Sys-'"'"';
	                            }
	                            for (const systemfan_value of FunState.systemfans) {
	                                output += `${systemfan_value} RPM, `;
	                            }
	                        }
	                        output = output.slice(0, -2);
	                    } else if (FunState.cpufans.length == 0 && FunState.pumpfans.length == 0 && FunState.systemfans.length == 0) {
	                        output += '"'"' | Fan: Stop'"'"';
	                    }
	                }
	            }
	        }

	        return output.replace(/\\n/g, '"'"'<br>'"'"');
	    }
	}'
fi

# NVME 硬盘信息 API 及 Web UI
nvme_height="0"
if [ $(ls /dev/nvme? 2> /dev/null | wc -l) -gt 0 ]; then
    i="1"
    nvme_info_api=''
    nvme_info_display=''
    for nvme_device in $(ls -1 /dev/nvme?); do
        nvme_code=${nvme_device##*/}
	    if [[ $(smartctl -a $nvme_device|grep -E "Cycle") && $(iostat -d -x -k 1 1 | grep -E "^$nvme_code") ]] && [[ $(smartctl -a $nvme_device|grep -E "Model") || $(smartctl -a $nvme_device|grep -E "Capacity") ]]; then
	        nvme_degree="2"
	    else
	        nvme_degree="1"
	    fi
        nvme_tmp_height="$[nvme_degree*17+7]"
		nvme_height="$[nvme_height + nvme_tmp_height]"
        nvme_info_api_tmp='
	my $'$nvme_code'_temperatures = `smartctl -a '$nvme_device'|grep -E "Model Number|Total NVM Capacity|Temperature:|Percentage|Data Unit|Power Cycles|Power On Hours|Unsafe Shutdowns|Integrity Errors"`;
	my $'$nvme_code'_io = `iostat -d -x -k 1 1 | grep -E "^'$nvme_code'"`;
	$res->{'$nvme_code'_status} = $'$nvme_code'_temperatures . $'$nvme_code'_io;
		'
    nvme_info_api="$nvme_info_api$nvme_info_api_tmp"

    nvme_info_display_tmp=',
	{
	    itemId: '"'"''$nvme_code'-status'"'"',
	    colspan: 2,
	    printBar: false,
	    title: gettext('"'"'NVMe SSD '$i''"'"'),
	    textField: '"'"''$nvme_code'_status'"'"',
	    renderer:function(value){
	        if (value.length > 0) {
	            value = value.replace(/Â/g, '"'"''"'"');
	            let data = [];
	            let nvmes = value.matchAll(/(^(?:Model|Total|Temperature:|Percentage|Data|Power|Unsafe|Integrity Errors|nvme)[\s\S]*)+/gm);
	            for (const nvme of nvmes) {
	                let nvmeNumber = 0;
	                data[nvmeNumber] = {
	                       Models: [],
						   Integrity_Errors: [],
	                       Capacitys: [],
	                       Temperatures: [],
	                       Useds: [],
	                       Reads: [],
	                       Writtens: [],
	                       Cycles: [],
	                       Hours: [],
	                       Shutdowns: [],
	                       States: [],
	                       r_awaits: [],
	                       w_awaits: [],
	                       utils: []
	                };

	                let Models = nvme[1].matchAll(/^Model Number: *([ \S]*)$/gm);
	                for (const Model of Models) {
	                    data[nvmeNumber]['"'"'Models'"'"'].push(Model[1]);
	                }

	                let Integrity_Errors = nvme[1].matchAll(/^Media and Data Integrity Errors: *([ \S]*)$/gm);
	                for (const Integrity_Error of Integrity_Errors) {
	                    data[nvmeNumber]['"'"'Integrity_Errors'"'"'].push(Integrity_Error[1]);
	                }

	                let Capacitys = nvme[1].matchAll(/^Total NVM Capacity:[^\[]*\[([ \S]*)\]$/gm);
	                for (const Capacity of Capacitys) {
	                    data[nvmeNumber]['"'"'Capacitys'"'"'].push(Capacity[1]);
	                }

	                let Temperatures = nvme[1].matchAll(/^Temperature: *([\d]*)[ \S]*$/gm);
	                for (const Temperature of Temperatures) {
	                    data[nvmeNumber]['"'"'Temperatures'"'"'].push(Temperature[1]);
	                }

	                let Useds = nvme[1].matchAll(/^Percentage Used: *([ \S]*)%$/gm);
	                for (const Used of Useds) {
	                    data[nvmeNumber]['"'"'Useds'"'"'].push(Used[1]);
	                }

	                let Reads = nvme[1].matchAll(/^Data Units Read:[^\[]*\[([ \S]*)\]$/gm);
	                for (const Read of Reads) {
	                    data[nvmeNumber]['"'"'Reads'"'"'].push(Read[1]);
	                }

	                let Writtens = nvme[1].matchAll(/^Data Units Written:[^\[]*\[([ \S]*)\]$/gm);
	                for (const Written of Writtens) {
	                    data[nvmeNumber]['"'"'Writtens'"'"'].push(Written[1]);
	                }

	                let Cycles = nvme[1].matchAll(/^Power Cycles: *([ \S]*)$/gm);
	                for (const Cycle of Cycles) {
	                    data[nvmeNumber]['"'"'Cycles'"'"'].push(Cycle[1]);
	                }

	                let Hours = nvme[1].matchAll(/^Power On Hours: *([ \S]*)$/gm);
	                for (const Hour of Hours) {
	                    data[nvmeNumber]['"'"'Hours'"'"'].push(Hour[1]);
	                }

	                let Shutdowns = nvme[1].matchAll(/^Unsafe Shutdowns: *([ \S]*)$/gm);
	                for (const Shutdown of Shutdowns) {
	                    data[nvmeNumber]['"'"'Shutdowns'"'"'].push(Shutdown[1]);
	                }

	                let States = nvme[1].matchAll(/^nvme\S+(( *\d+\.\d{2}){22})/gm);
	                for (const State of States) {
	                    data[nvmeNumber]['"'"'States'"'"'].push(State[1]);
	                    const IO_array = [...State[1].matchAll(/\d+\.\d{2}/g)];
	                    if (IO_array.length > 0) {
	                        data[nvmeNumber]['"'"'r_awaits'"'"'].push(IO_array[4]);
	                        data[nvmeNumber]['"'"'w_awaits'"'"'].push(IO_array[10]);
	                        data[nvmeNumber]['"'"'utils'"'"'].push(IO_array[21]);
	                    }
	                }

	                let output = '"'"''"'"';
	                for (const [i, nvme] of data.entries()) {
	                    if (nvme.Models.length > 0) {
	                        for (const nvmeModel of nvme.Models) {
	                            output += `${nvmeModel}`;
	                        }
	                    }

	                    if (nvme.Integrity_Errors.length > 0) {
	                        for (const nvmeIntegrity_Error of nvme.Integrity_Errors) {
	                            if (nvmeIntegrity_Error != 0) {
	                                output += ` (0E: ${nvmeIntegrity_Error}-Error！)`;
	                            }
								break
	                        }
	                    }

	                    if (nvme.Capacitys.length > 0) {
	                        output += '"'"' | '"'"';
	                        for (const nvmeCapacity of nvme.Capacitys) {
	                            output += `Capacity: ${nvmeCapacity.replace(/ |,/gm, '"'"''"'"')}`;
	                        }
	                    }

	                    if (nvme.Useds.length > 0) {
	                        output += '"'"' | '"'"';
	                        for (const nvmeUsed of nvme.Useds) {
				    output += `TBW used: ${nvmeUsed}% `;
	                            output += `Remain TBW: ${100 - nvmeUsed}% `;
	                            if (nvme.Reads.length > 0) {
	                                output += '"'"'('"'"';
	                                for (const nvmeRead of nvme.Reads) {
	                                    output += `Read ${nvmeRead.replace(/ |,/gm, '"'"''"'"')}`;
	                                    output += '"'"')'"'"';
	                                }
	                            }

	                            if (nvme.Writtens.length > 0) {
	                                output = output.slice(0, -1);
	                                output += '"'"', '"'"';
	                                for (const nvmeWritten of nvme.Writtens) {
	                                    output += `Writen ${nvmeWritten.replace(/ |,/gm, '"'"''"'"')}`;
	                                }
	                                output += '"'"')'"'"';
	                            }
	                        }
	                    }

	                    if (nvme.States.length <= 0) {
	                        if (nvme.Cycles.length > 0) {
	                            output += '"'"' | '"'"';
	                            for (const nvmeCycle of nvme.Cycles) {
	                                output += `Power-on Count: ${nvmeCycle.replace(/ |,/gm, '"'"''"'"')}`;
	                            }

	                            if (nvme.Shutdowns.length > 0) {
	                                output += '"'"', '"'"';
	                                for (const nvmeShutdown of nvme.Shutdowns) {
	                                    output += `Unsafe power-offs: ${nvmeShutdown.replace(/ |,/gm, '"'"''"'"')}`;
	                                }
	                            }

	                            if (nvme.Hours.length > 0) {
	                                output += '"'"', '"'"';
	                                for (const nvmeHour of nvme.Hours) {
	                                    output += `Uptime: ${nvmeHour.replace(/ |,/gm, '"'"''"'"')} Hours`;
	                                }
	                            }
	                        }
	                    }

	                    if (nvme.Temperatures.length > 0) {
	                        output += '"'"' | '"'"';
	                        for (const nvmeTemperature of nvme.Temperatures) {
	                            output += `Temp: ${nvmeTemperature}°C`;
	                        }
	                    }

	                    if (nvme.States.length > 0) {
	                        if (nvme.Cycles.length > 0) {
	                            output += '"'"'\\n'"'"';
	                            for (const nvmeCycle of nvme.Cycles) {
	                                output += `Power-on Count: ${nvmeCycle.replace(/ |,/gm, '"'"''"'"')}`;
	                            }

	                            if (nvme.Shutdowns.length > 0) {
	                                output += '"'"', '"'"';
	                                for (const nvmeShutdown of nvme.Shutdowns) {
	                                    output += `Unsafe power-offs: ${nvmeShutdown.replace(/ |,/gm, '"'"''"'"')}`;
	                                }
	                            }

	                            if (nvme.Hours.length > 0) {
	                                output += '"'"', '"'"';
	                                for (const nvmeHour of nvme.Hours) {
	                                    output += `Uptime:${nvmeHour.replace(/ |,/gm, '"'"''"'"')} Hours`;
	                                }
	                            }
	                        }

	                        output += '"'"' | '"'"';
	                        if (nvme.r_awaits.length > 0) {
	                            for (const nvme_r_await of nvme.r_awaits) {
	                                output += `I/O: Read latency: ${nvme_r_await}ms`;
	                            }
	                        }

	                        if (nvme.w_awaits.length > 0) {
	                            output += '"'"', '"'"';
	                            for (const nvme_w_await of nvme.w_awaits) {
	                                output += `Write latency: ${nvme_w_await}ms`;
	                            }
	                        }

	                        if (nvme.utils.length > 0) {
	                            output += '"'"', '"'"';
	                            for (const nvme_util of nvme.utils) {
	                                output += `Load: ${nvme_util}%`;
	                            }
	                        }
	                    }
	                    //output = output.slice(0, -3);
	                }
	                return output.replace(/\\n/g, '"'"'<br>'"'"');
	            }
	        } else { 
	            return `Note: Hard drive not installed or hard drive controller is passed through.`;
	        }
	    }
	}'
        nvme_info_display="$nvme_info_display$nvme_info_display_tmp"
        i=$((i + 1))
    done
fi

# 其他存储设备信息 API 及 Web UI
hdd_height="0"
if [ $(ls /dev/sd? 2> /dev/null | wc -l) -gt 0 ]; then
    i="1"
    hdd_info_api=''
    hdd_info_display=''
    for hdd_device in $(ls -1 /dev/sd?); do
        hdd_code=${hdd_device##*/}
	    if [[ $(smartctl -a $hdd_device|grep -E "Cycle") && $(iostat -d -x -k 1 1 | grep -E "^$hdd_code") ]] && [[ $(smartctl -a $hdd_device|grep -E "Model") || $(smartctl -a $hdd_device|grep -E "Capacity") ]]; then
	        hdd_degree="2"
	    else
	        hdd_degree="1"
	    fi
		hdd_tmp_height="$[hdd_degree*17+7]"
		hdd_height="$[hdd_height + hdd_tmp_height]"
        hdd_info_api_tmp='
	my $'$hdd_code'_temperatures = `smartctl -a '$hdd_device'|grep -E "Model|Capacity|Power_On_Hours|Power_Cycle_Count|Power-Off_Retract_Count|Unexpected_Power_Loss|Unexpect_Power_Loss_Ct|POR_Recovery|Temperature"`;
	my $'$hdd_code'_io = `iostat -d -x -k 1 1 | grep -E "^'$hdd_code'"`;
	$res->{'$hdd_code'_status} = $'$hdd_code'_temperatures . $'$hdd_code'_io;
		'
    hdd_info_api="$hdd_info_api$hdd_info_api_tmp"

    hdd_info_display_tmp=',
	{
	    itemId: '"'"''$hdd_code'-status'"'"',
	    colspan: 2,
	    printBar: false,
	    title: gettext('"'"'Other storage devices '$i''"'"'),
	    textField: '"'"''$hdd_code'_status'"'"',
	    renderer:function(value){
	        if (value.length > 0) {
	            value = value.replace(/Â/g, '"'"''"'"');
	            let data = [];
	            let devices = value.matchAll(/^((?:Device|Model|User|[ ]{0,2}\d|sd)[\s\S]*)+/gm);
	            for (const device of devices) {
	                let deviceNumber = 0;
	                data[deviceNumber] = {
	                       Models: [],
	                       Capacitys: [],
	                       Temperatures: [],
	                       Cycles: [],
	                       Hours: [],
	                       Shutdowns: [],
	                       States: [],
	                       r_awaits: [],
	                       w_awaits: [],
	                       utils: []
	                };

	                if(device[1].indexOf("Family") !== -1){
	                    let Models = device[1].matchAll(/^Model Family: *([ \S]*?)\\n^Device Model: *([ \S]*?)$/gm);
	                    for (const Model of Models) {
	                        data[deviceNumber]['"'"'Models'"'"'].push(`${Model[1]} - ${Model[2]}`);
	                    }
	                } else {
	                    let Models = device[1].matchAll(/Model: *([ \S]*?)$/gm);
	                    for (const Model of Models) {
	                        data[deviceNumber]['"'"'Models'"'"'].push(Model[1]);
	                    }
	                }

	                let Capacitys = device[1].matchAll(/^User Capacity:[^\[]*\[([ \S]*)\]$/gm);
	                for (const Capacity of Capacitys) {
	                    data[deviceNumber]['"'"'Capacitys'"'"'].push(Capacity[1]);
	                }

	                let Temperatures = device[1].matchAll(/Temperature[ \S]*(?:\-|In_the_past) *?(\d+)[ \S]*$/gm);
	                for (const Temperature of Temperatures) {
	                    data[deviceNumber]['"'"'Temperatures'"'"'].push(Temperature[1]);
	                }

	                let Cycles = device[1].matchAll(/Cycle[ \S]*(?:\-|In_the_past) *?(\d+)[ \S]*$/gm);
	                for (const Cycle of Cycles) {
	                    data[deviceNumber]['"'"'Cycles'"'"'].push(Cycle[1]);
	                }

	                let Hours = device[1].matchAll(/Hours[ \S]*(?:\-|In_the_past) *?(\d+)[ \S]*$/gm);
	                for (const Hour of Hours) {
	                    data[deviceNumber]['"'"'Hours'"'"'].push(Hour[1]);
	                }

	                let Shutdowns = device[1].matchAll(/(?:Retract|Loss|POR_Recovery)[ \S]*(?:\-|In_the_past) *?(\d+)[ \S]*$/gm);
	                for (const Shutdown of Shutdowns) {
	                    data[deviceNumber]['"'"'Shutdowns'"'"'].push(Shutdown[1]);
	                }

	                let States = device[1].matchAll(/^sd\S+(( *\d+\.\d{2}){22})/gm);
	                for (const State of States) {
	                    data[deviceNumber]['"'"'States'"'"'].push(State[1]);
	                    const IO_array = [...State[1].matchAll(/\d+\.\d{2}/g)];
	                    if (IO_array.length > 0) {
	                        data[deviceNumber]['"'"'r_awaits'"'"'].push(IO_array[4]);
	                        data[deviceNumber]['"'"'w_awaits'"'"'].push(IO_array[10]);
	                        data[deviceNumber]['"'"'utils'"'"'].push(IO_array[21]);
	                    }
	                }

	                let output = '"'"''"'"';
	                for (const [i, device] of data.entries()) {
	                    if (device.Models.length > 0) {
	                        for (const deviceModel of device.Models) {
	                            output += `${deviceModel}`;
	                        }
	                    }

	                    if (device.Capacitys.length > 0) {
	                        if (device.Models.length > 0) {
	                            output += '"'"' | '"'"';
                          }
	                        for (const deviceCapacity of device.Capacitys) {
	                            output += `Capacity: ${deviceCapacity.replace(/ |,/gm, '"'"''"'"')}`;
	                        }
	                    }

	                    if (device.States.length <= 0) {
	                        if (device.Cycles.length > 0) {
	                            output += '"'"' | '"'"';
	                            for (const deviceCycle of device.Cycles) {
	                                output += `Power-on Count: ${deviceCycle.replace(/ |,/gm, '"'"''"'"')}`;
	                            }

	                            if (device.Shutdowns.length > 0) {
	                                output += '"'"', '"'"';
	                                for (const deviceShutdown of device.Shutdowns) {
	                                    output += `Unsafe power-offs:${deviceShutdown.replace(/ |,/gm, '"'"''"'"')}`;
	                                }
	                            }

	                            if (device.Hours.length > 0) {
	                                output += '"'"', '"'"';
	                                for (const deviceHour of device.Hours) {
	                                    output += `Uptime:${deviceHour.replace(/ |,/gm, '"'"''"'"')} Hours`;
	                                }
	                            }
	                        }
	                    } else if (device.Cycles.length <= 0) {
	                        if (device.States.length > 0) {
	                            if (device.Models.length > 0 || device.Capacitys.length > 0) {
	                                output += '"'"' | '"'"';
	                            }

	                            if (device.r_awaits.length > 0) {
	                                for (const device_r_await of device.r_awaits) {
	                                    output += `I/O: Read latency: ${device_r_await}ms`;
	                                }
	                            }

	                            if (device.w_awaits.length > 0) {
	                                output += '"'"', '"'"';
	                                for (const device_w_await of device.w_awaits) {
	                                    output += `Write latency: ${device_w_await}ms`;
	                                }
	                            }

	                            if (device.utils.length > 0) {
	                                output += '"'"', '"'"';
	                                for (const device_util of device.utils) {
	                                    output += `Load:${device_util}%`;
	                                }
	                            }
	                        }
	                    }

	                    if (device.Temperatures.length > 0) {
	                        output += '"'"' | '"'"';
	                        for (const deviceTemperature of device.Temperatures) {
	                            output += `Temp: ${deviceTemperature}°C`;
                                break
	                        }
	                    }

	                    if (device.States.length > 0) {
	                        if (device.Cycles.length > 0) {
	                            output += '"'"'\\n'"'"';
	                            for (const deviceCycle of device.Cycles) {
	                                output += `Power-on Count: ${deviceCycle.replace(/ |,/gm, '"'"''"'"')}`;
	                            }

	                            if (device.Shutdowns.length > 0) {
	                                output += '"'"', '"'"';
	                                for (const deviceShutdown of device.Shutdowns) {
	                                    output += `Unsafe power-offs:${deviceShutdown.replace(/ |,/gm, '"'"''"'"')}`;
	                                }
	                            }

	                            if (device.Hours.length > 0) {
	                                output += '"'"', '"'"';
	                                for (const deviceHour of device.Hours) {
	                                    output += `Uptime:${deviceHour.replace(/ |,/gm, '"'"''"'"')} Hours`;
	                                }
	                            }

	                            if (device.Models.length > 0 || device.Capacitys.length > 0) {
	                                output += '"'"' | '"'"';
	                            }

	                            if (device.r_awaits.length > 0) {
	                                for (const device_r_await of device.r_awaits) {
	                                    output += `I/O: Read latency:  ${device_r_await}ms`;
	                                }
	                            }

	                            if (device.w_awaits.length > 0) {
	                                output += '"'"', '"'"';
	                                for (const device_w_await of device.w_awaits) {
	                                    output += `Write latency: ${device_w_await}ms`;
	                                }
	                            }

	                            if (device.utils.length > 0) {
	                                output += '"'"', '"'"';
	                                for (const device_util of device.utils) {
	                                    output += `Load:${device_util}%`;
	                                }
	                            }
	                        }
	                    }
	                    //output = output.slice(0, -3);
	                }
	                return output.replace(/\\n/g, '"'"'<br>'"'"');
	            }
	        } else { 
	            return `Note: Hard drive not installed or directly passed through to hard drive controller.`;
	        }
	    }
	}'
        hdd_info_display="$hdd_info_display$hdd_info_display_tmp"
        i=$((i + 1))
    done
fi

# API
INFO_API="$cpu_info_api$nvme_info_api$hdd_info_api"
# Web UI
INFO_DISPLAY="$cpu_freq_display$cpu_temp_display$nvme_info_display$hdd_info_display"

# 缓存代码
# echo -e "\n" > /tmp/0.txt
# echo -e "	    value: '',\n	}," > /tmp/1.txt
echo -e "$INFO_API" > /tmp/2.txt
echo -e "	    value: '',\n	}$INFO_DISPLAY" > /tmp/3.txt

# CPU 主频及温度 UI 高度
cpu_degree="$(sensors | grep $cpu_keyword | wc -l)"
core_degree="$(sensors | grep Core | wc -l)"
process_degree="$(cat /proc/cpuinfo | grep -i "cpu MHz" | wc -l)"
if [ $core_degree -gt 4 ]; then
    cpu_temp_degree="$[cpu_degree + (core_degree+4-1)/4]"
else
    cpu_temp_degree="$cpu_degree"
fi
cpu_temp_height="$[cpu_temp_degree*17+7]"
cpu_freq_degree="$[cpu_degree + (process_degree+4-1)/4]"
cpu_freq_height="$[cpu_freq_degree*17+7]"

# Web UI 总高度
#height1="$[400 + (cpu_temp_height + cpu_freq_height + nvme_height + hdd_height)]"
#height1="400"
height2="$[300 + cpu_temp_height + cpu_freq_height + nvme_height + hdd_height + 25]"
if [ $height2 -le 325 ]; then
    height2="300"
fi

# 重装 pve-manager
# echo -e "Restoring pve-manager ......"
# apt-get update > /dev/null 2>&1
# apt-get reinstall pve-manager > /dev/null 2>&1
# sed -i '/PVE::pvecfg::version_text();/,/my $dinfo = df/!b;//!d;s/my $dinfo = df/\n\t&/' /usr/share/perl5/PVE/API2/Nodes.pm
# sed -i '/pveversion/,/^\s\+],/!b;//!d;s/^\s\+],/\t    value: '"'"''"'"',\n\t},\n&/' /usr/share/pve-manager/js/pvemanagerlib.js
# sed -i '/widget.pveNodeStatus/,/},/ { s/height: [0-9]\+/height: 300/; /textAlign/d}' /usr/share/pve-manager/js/pvemanagerlib.js

# 将 API 及 Web UI 文件修改至原文件
sed -i '/PVE::pvecfg::version_text();/,/my $dinfo = df/!b;//!d;/my $dinfo = df/e cat /tmp/2.txt' /usr/share/perl5/PVE/API2/Nodes.pm
sed -i '/pveversion/,/^\s\+],/!b;//!d;/^\s\+],/e cat /tmp/3.txt' /usr/share/pve-manager/js/pvemanagerlib.js

#sed -i '/let win = Ext.create('"'"'Ext.window.Window'"'"', {/,/height/ s/height: [0-9]\+/height: '$height1'/' /usr/share/pve-manager/js/pvemanagerlib.js

# 修改信息框 Web UI 高度
sed -i '/widget.pveNodeStatus/,/},/ s/height: [0-9]\+/height: '$height2'/; /width: '"'"'100%'"'"'/{n;s/ 	    },/		textAlign: '"'"'right'"'"',\n&/}' /usr/share/pve-manager/js/pvemanagerlib.js

# 完善汉化信息
# sed -i '/'"'"'netin'"'"', '"'"'netout'"'"'/{n;s/		    store: rrdstore/		    fieldTitles: [gettext('"'"'下行'"'"'), gettext('"'"'上行'"'"')],	\n&/g}' /usr/share/pve-manager/js/pvemanagerlib.js
# sed -i '/'"'"'diskread'"'"', '"'"'diskwrite'"'"'/{n;s/		    store: rrdstore/		    fieldTitles: [gettext('"'"'读'"'"'), gettext('"'"'写'"'"')],	\n&/g}' /usr/share/pve-manager/js/pvemanagerlib.js

# 去除订阅提示
sed -Ezi.bak "s/(Ext.Msg.show\(\{\s+title: gettext\('No valid sub)/void\(\{ \/\/\1/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js

APT_SOURCES_LIST="/etc/apt/sources.list.d"

# 移除PVE企业订阅源
PVE_ENTERPRISE_SOURCE="${APT_SOURCES_LIST}/pve-enterprise.list"
if [ -f $PVE_ENTERPRISE_SOURCE ]; then
    mv $PVE_ENTERPRISE_SOURCE "${PVE_ENTERPRISE_SOURCE}.bak"
fi

PVE_NO_SUBSCRIPTION_SOURCE="${APT_SOURCES_LIST}/pve-no-subscription.list"
if [ ! -f $PVE_NO_SUBSCRIPTION_SOURCE ]; then
    # 增加PVE内核官方源
    # echo "deb http://download.proxmox.com/debian/pve bullseye pve-no-subscription" > $PVE_NO_SUBSCRIPTION_SOURCE
    # 记得更新下索引
    apt update
fi

echo -e "Adding PVE hardware summary information completed, restarting pveproxy service ......"
systemctl restart pveproxy

echo -e "pveproxy service restart completed, please manually refresh the PVE web page using Shift + F5."

