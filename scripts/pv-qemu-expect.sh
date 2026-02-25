#!/usr/bin/expect -f
# pv-qemu-expect.sh — Long-running expect backend for pv-qemu-tool
#
# Spawns QEMU with EFI firmware, logs console output, and accepts
# commands via named pipes (FIFO protocol). Stays alive across
# guest reboots.
#
# Usage: expect scripts/pv-qemu-expect.sh <session_dir>
#
# FIFO protocol (one command per line on cmd.fifo → result on result.fifo):
#   WAIT_SHELL <timeout>     → OK or TIMEOUT
#   EXEC <timeout> <cmd>     → EXIT:<code>\n<output>\nEND
#   WAIT <timeout> <pattern> → OK or TIMEOUT
#   QUIT                     → (sends Ctrl-A X, exits)
#
# Copyright (c) 2025-2026 Pantacor Ltd.
# SPDX-License-Identifier: MIT

if {$argc < 1} {
    puts stderr "Usage: pv-qemu-expect.sh <session_dir>"
    exit 1
}

set session_dir [lindex $argv 0]
set cmd_fifo "$session_dir/cmd.fifo"
set result_fifo "$session_dir/result.fifo"

# --- Paths (same as run-qemu-efi.sh / test-update-efi.exp) ---
set top_dir [file dirname [file dirname [file normalize $argv0]]]
set builddir "$top_dir/build"
set tmpdir "$builddir/tmp-scarthgap"
set deploy "$tmpdir/deploy/images/x64-efi"
set native_base "$tmpdir/sysroots-components/x86_64"
set uninative "$tmpdir/sysroots-uninative/x86_64-linux"

set qemu "$native_base/qemu-system-native/usr/bin/qemu-system-x86_64"
set loader "$uninative/lib/ld-linux-x86-64.so.2"
set qemu_data "$native_base/qemu-system-native/usr/share/qemu"
set ovmf_code "$deploy/ovmf.code.qcow2"

# Read image path from session config (written by pv-qemu-tool.sh start)
set image_file "$session_dir/image"
if {[file exists $image_file]} {
    set fp [open $image_file r]
    set wic [string trim [read $fp]]
    close $fp
} else {
    set wic "$deploy/pantavisor-remix-x64-efi.rootfs.wic"
}

# OVMF vars copy lives in session dir (persists across reboots within session)
set vars_copy "$session_dir/vars.qcow2"

# Verify prerequisites
foreach f [list $qemu $loader $wic $ovmf_code $vars_copy] {
    if {![file exists $f]} {
        puts stderr "ERROR: missing $f"
        exit 1
    }
}

# Build library path
set lib_path "$uninative/lib:$uninative/usr/lib"
foreach d [glob -nocomplain "$native_base/*/usr/lib"] {
    append lib_path ":$d"
}

log_user 1

# --- Spawn QEMU ---
spawn env LD_LIBRARY_PATH=$lib_path $loader --library-path $lib_path $qemu \
    -L $qemu_data \
    -machine q35 \
    -cpu IvyBridge \
    -m 2048 \
    -smp 2 \
    -nographic \
    -drive if=pflash,format=qcow2,readonly=on,file=$ovmf_code \
    -drive if=pflash,format=qcow2,file=$vars_copy \
    -drive format=raw,file=$wic \
    -netdev user,id=net0 -device e1000,netdev=net0 \
    -serial mon:stdio

# Log all output to console.log
log_file -a "$session_dir/console.log"

# Write QEMU PID
set fp [open "$session_dir/qemu.pid" w]
puts $fp [exp_pid]
close $fp

# --- Helper: write result to FIFO ---
proc write_result {session_dir msg} {
    set fout [open "$session_dir/result.fifo" w]
    puts $fout $msg
    close $fout
}

# --- Helper: enter debug shell (from test-update-efi.exp) ---
proc handle_wait_shell {timeout_val session_dir} {
    set timeout $timeout_val
    expect {
        -re {Press.*ENTER.*debug} {
            sleep 0.2
            send "\r"
        }
        timeout {
            write_result $session_dir "TIMEOUT"
            return
        }
    }

    # Wait for boot to settle (NIC link-up or e1000 init)
    set timeout 60
    expect {
        "NIC Link is Up" { }
        "e1000: eth0" { }
        timeout { }
    }

    sleep 3
    send "\r"
    sleep 0.5
    write_result $session_dir "OK"
}

# --- Helper: execute command with exit code capture ---
proc handle_exec {cmd timeout_val session_dir} {
    set uid [clock clicks]
    set marker "XQTOOL_${uid}"
    send "$cmd; echo ${marker}_\$?\r"

    set output ""
    set exit_code -1
    set timeout $timeout_val

    expect {
        -re "${marker}_(\[0-9\]+)" {
            set exit_code $expect_out(1,string)
            # Buffer contains everything up to the match
            set output $expect_out(buffer)
        }
        timeout {
            set exit_code -1
            set output "TIMEOUT"
        }
    }

    # Clean up the output: remove the echoed command line and trailing whitespace
    # The buffer typically contains: <echoed command>\r\n<actual output>\r\n
    # Strip everything up to and including the first newline (the echoed command)
    set lines [split $output "\n"]
    if {[llength $lines] > 1} {
        set output [join [lrange $lines 1 end] "\n"]
    }
    # Strip trailing whitespace/newlines
    set output [string trimright $output]

    set fout [open "$session_dir/result.fifo" w]
    puts $fout "EXIT:$exit_code"
    puts $fout $output
    puts $fout "END"
    close $fout
}

# --- Helper: wait for console pattern ---
proc handle_wait {pattern timeout_val session_dir} {
    set timeout $timeout_val
    expect {
        -re $pattern {
            write_result $session_dir "OK"
        }
        timeout {
            write_result $session_dir "TIMEOUT"
        }
    }
}

# --- Main command loop ---
# Reads commands from cmd.fifo, dispatches, writes results to result.fifo.
# FIFOs are opened/closed per command to allow the shell wrapper to
# synchronize via blocking reads/writes.

while {1} {
    # Open FIFO for reading (blocks until a writer connects)
    set fin [open $cmd_fifo r]
    gets $fin line
    close $fin

    if {$line eq ""} {
        continue
    }

    if {[string match "WAIT_SHELL *" $line]} {
        set timeout_val [lindex [split $line] 1]
        handle_wait_shell $timeout_val $session_dir

    } elseif {[string match "EXEC *" $line]} {
        # Format: EXEC <timeout> <cmd...>
        set parts [split $line]
        set timeout_val [lindex $parts 1]
        set cmd [join [lrange $parts 2 end]]
        handle_exec $cmd $timeout_val $session_dir

    } elseif {[string match "WAIT *" $line]} {
        # Format: WAIT <timeout> <pattern...>
        set parts [split $line]
        set timeout_val [lindex $parts 1]
        set pattern [join [lrange $parts 2 end]]
        handle_wait $pattern $timeout_val $session_dir

    } elseif {$line eq "QUIT"} {
        # Send Ctrl-A X to exit QEMU monitor
        send "\x01x"
        expect eof
        break

    } else {
        write_result $session_dir "ERROR: unknown command: $line"
    }
}

exit 0
