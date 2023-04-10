	module VDriveZ88

include "director.def"
include "dor.def"
include "stdio.def"
include "serintfc.def"
include "syspar.def"
include "fileio.def"
include "error.def"
include "memory.def"

include "vdap.def"

; General constants

	defc port_timeout = 10
	defc filename_length = 20
	
	defc dir_item_width = 14
	defc dir_cols = 6
	defc dir_rows = 7
	
	defc dir_left = 0
	defc dir_top = 0
	defc dir_right = dir_left + dir_item_width * dir_cols
	defc dir_bottom = dir_top + dir_rows

; Safe workspace variables

	defc unsafe_ws = 128
	defc safe_ws = 0
	
	defc ram_vars = $1FFE - unsafe_ws
	
	defvars ram_vars {
		port_handle     ds.w 1          ; serial port handle
		filename        ds.b 32         ; buffer for filenames
		has_disk        ds.b 1          ; whether the drive has a disk in it or not
		memory_pool     ds.w 1          ; memory allocation pool
		dir_list        ds.w 2          ; pointer to first file in list
		dir_count       ds.w 1          ; number of files in file list
		dir_list_ptr    ds.w 2          ; pointer to current item in file list
		dir_list_new    ds.w 2          ; pointer to new item in the file list
		dir_list_old    ds.w 2          ; pointer to old item in the file list
		cursor_x        ds.b 1          ; cursor x
		cursor_y        ds.b 1          ; cursor y
		dir_offset      ds.w 1          ; offset into directory listing
		dir_working     ds.w 1          ; working file index
		dir_selected    ds.w 1          ; selected file index
		path            ds.w 2          ; pointer to storage for full file path
	}

; Application bank and origin

	defc appl_bank = $3F                ; default to top bank loading
	org $C000

; Application DOR

.appl_dor
	defb 0,0,0                          ; links to parent, brother, son
	defb 0,0,0
	defb 0,0,0
	defb $83                            ; DOR type - application
	defb indorend-indorstart
.indorstart
	defb '@'                            ; key to info section
	defb ininfend-ininfstart
.ininfstart
	defw 0
	defb 'D'                            ; application key
	defb 0                              ; no bad app memory
	defw 0                              ; overhead
	defw unsafe_ws                      ; unsafe workspace
	defw safe_ws                        ; safe workspace
	defw appl_start                     ; entry point
	defb 0                              ; bank bindings
	defb 0
	defb 0
	defb appl_bank
	defb at_popd|at_good                ; good popdown
	defb 0                              ; no caps lock
.ininfend
	defb 'H'                            ; key to help section
	defb inhlpend-inhlpstart
.inhlpstart
	defw appl_dor                       ; no topics
	defb appl_bank
	defw appl_dor                       ; no commands
	defb appl_bank
	defw appl_dor                       ; no help
	defb appl_bank
	defw appl_dor                       ; no tokens
	defb appl_bank
.inhlpend
	defb 'N'                            ; key to name section
	defb innamend-innamstart
.innamstart
	defm "VDrive", 0
.innamend
	defb $FF
.indorend

; The main entry point

.appl_start
	jp appl_main
	scf
	ret

.appl_main
	
	; clear our RAM variables
	ld hl, ram_vars
	ld (hl), 0
	ld de, ram_vars + 1
	ld bc, unsafe_ws - 1
	ldir
	
	; use segment 1 for memory allocations
	ld a, MM_S1
	ld bc, 0
	oz (OS_Mop)
    jr nc, opened_pool
	
	; quit with error message
	oz (OS_Bye)
	
.opened_pool
	ld (memory_pool), ix
	
	; allocate memory for the path
	xor a
	ld bc, 256
	oz (OS_Mal)
	jp z, appl_exit
	
	ld (path + 0), bc
	ld (path + 2), hl
	
	oz (OS_Mpb)
	ld (hl), 0
	
	; initialise the full window for output
	ld hl, window_full
	oz (GN_Sop)
	
	; initialise the drive
	call drive_init
	
	ld hl, connecting
	oz (GN_Sop)

.connecting_loop
	
	call sync
	jr c, connecting_failed
	jr z, connecting_succeeded

.connecting_failed

	ld bc, 10
	oz (OS_Tin)
	jr nc, connecting_loop_key
	
	cp RC_TIME
	jr z, connecting_loop
	jp appl_exit

.connecting_loop_key
	
	cp ESC
	jp z, appl_exit
	
	jr connecting_loop

.connecting_succeeded

	ld hl, ok
	oz (GN_Sop)
	oz (Gn_Nln)
	
	; path is already cleared, so just skip to the root directory
	ld hl, up_to_root
	call change_directory
	
	; clear the screen
	ld hl, window_full
	oz (GN_Sop)
	
	; skip the next block as we've already reset the path
	jr dir_list_start
	
.dir_list_start_from_root

	; clear the stored path
	ld bc, (path + 0)
	ld hl, (path + 2)
	
	oz (OS_Mpb)
	ld (hl), 0

	; initially start from the root directory
	ld hl, up_to_root
	call change_directory

.dir_list_start

	; draw the title bar
	ld hl, window_title_begin
	oz (GN_Sop)
	
	ld a, (has_disk)
	or a
	jr nz, dir_list_title_path
	
	ld hl, no_disk
	jr dir_list_output_title

.dir_list_title_path
	
	ld hl, path_prefix
	oz (GN_Sop)
	
	ld bc, (path + 0)
	ld hl, (path + 2)
	
	oz (OS_Mpb)

.dir_list_output_title

	oz (GN_Sop)
	
	ld hl, window_title_end
	oz (GN_Sop)
	
	; switch to the directory window
	ld hl, window_dir
	oz (GN_Sop)
	
	ld de, 0
	ld (dir_offset), de
	ld (dir_selected), de

.dir_list_render

	ld hl, (dir_count)
	ld a, l
	or h
	jp z, key_loop

.dir_list_has_files

	ld a, dir_left
	ld (cursor_x), a
	ld a, dir_top
	ld (cursor_y), a
	
	ld de, (dir_offset)
	ld (dir_working), de
	call dir_set_index

.dir_list_loop
	
	call dir_list_print_file
	jr z, dir_list_done
	
	call dir_next
	jr nz, dir_list_loop

.dir_list_done

	; we've either run out of files/directories to display,
	; or we've filled the screen
	xor a
	ld (cursor_x), a
	ld (cursor_y), a

.no_dir_list

	; wait for key
.key_loop

	call check_events
	jr z, no_key_loop_events
	
	; there was an event
	jp dir_list_start_from_root

.no_key_loop_events

	ld bc, 100
	oz (OS_Tin)
	jr c, key_error
	
	or a
	jr z, extended_key
	
	cp ESC
	jp z, appl_exit
	
	cp CR
	jp z, dir_enter
	
	jr key_loop

.key_error
	
	; time-outs are OK
	cp RC_TIME
	jr z, key_loop
	
	; treat any other errors as a request to quit
	jp appl_exit

.extended_key
	oz (OS_In)
	jr c, key_error
	
	cp IN_LFT
	jr z, dir_move_left
	
	cp IN_RGT
	jr z, dir_move_right
	
	cp IN_UP
	jr z, dir_move_up
	
	cp IN_DWN
	jr z, dir_move_down
	
	cp IN_SUP
	jp z, dir_up_a_level
	
	cp IN_SDWN
	jp z, dir_enter
	
	jr key_loop

.dir_list_print_file
	
	; set cursor position
	call goto_cursor
	
	ld a, ' '
	oz (OS_Out)
	
	; show file name
	ld bc, (dir_list_ptr + 0)
	ld hl, (dir_list_ptr + 2)
	
	oz (OS_Mpb)
	
	ld bc, 4
	add hl,bc
	
	; first character of name denotes if it's 'f' file or 'd' directory
	ld a, (hl)
	inc hl
	cp 'd'
	jr nz, dir_list_is_file
	
	; enable directory style
	push hl
	ld hl, working_file_is_dir
	oz (GN_Sop)
	pop hl

.dir_list_is_file
	oz (GN_Sop)
	
	; switch back to default file styles
	ld hl, working_file_is_file
	oz (GN_Sop)
	
	; advance file position, but also check if it was the selected file
	ld hl, (dir_selected)
	ld de, (dir_working)
	or a
	sbc hl, de
	inc de
	ld (dir_working), de
	
	jr nz, dir_list_not_selected
	
	; if the file was selected, apply the reverse video style
	call goto_cursor
	
	ld hl, selected_file_reverse_on
	oz (GN_Sop)
	
.dir_list_not_selected
	
	; advance cursor position
	ld a, (cursor_x)
	add a, dir_item_width
	cp dir_right
	jr nz, dir_list_cursor_done
	
	ld a, (cursor_y)
	inc a
	ld (cursor_y), a
	cp dir_bottom
	ret z
	
	ld a, dir_left
.dir_list_cursor_done
	ld (cursor_x), a
	cp $FF ; force nz
	ret

.dir_move_left
	ld a, -1
	jr dir_move

.dir_move_right
	ld a, +1
	jr dir_move

.dir_move_up
	ld a, -dir_cols
	jr dir_move

.dir_move_down
	ld a, +dir_cols
	jr dir_move

.dir_move

	; sign-extend a -> de
	ld e, a
	add a, a
	sbc a, a
	ld d, a
	
	; can't move within the directory listing if there aren't any files
	ld hl, (dir_count)
	ld a, h
	or l
	jp z, dir_move_skip
	
	; can't move within the directory listing if there's just one file too
	dec hl
	ld a, h
	or l
	jp z, dir_move_skip
	
	push de
	
	call goto_selected_file
	ld hl, selected_file_reverse_off
	oz (GN_Sop)
	
	pop de
	
	ld hl, (dir_selected)
	add hl, de
	
	bit 7, h
	jr z, dir_move_not_off_start
	
	ld hl, (dir_count)
	dec hl
	
.dir_move_not_off_start
	ld (dir_selected), hl
	
	ld de, (dir_count)
	or a
	sbc hl, de
	
	jr c, dir_move_not_off_end
	
	ld hl, 0
	ld (dir_selected), hl

.dir_move_not_off_end

	; have we moved off the top or bottom of the screen?
.dir_move_off_edge_loop
	
	ld hl, (dir_selected)
	ld de, (dir_offset)
	or a
	sbc hl, de
	
	bit 7, h
	jr nz, dir_moved_off_top
	
	ld de, dir_cols * dir_rows
	
	or a
	sbc hl, de
	jr c, dir_move_not_off_bottom
	
	; increment the offset
	ld hl, (dir_offset)
	ld de, +dir_cols
	add hl, de
	ld (dir_offset), hl
	
	; scroll the screen
	ld a, SOH
	oz (OS_Out)
	ld a, SD_DWN
	oz (OS_Out)
	
	; redraw the bottom line of files
	ld hl, (dir_offset)
	ld de, dir_cols * [ dir_rows - 1 ]
	add hl, de
	
	ex de, hl
	call dir_set_index
	
	ld a, dir_left
	ld (cursor_x), a
	ld a, dir_bottom - 1
	ld (cursor_y), a
	
.dir_move_off_bottom_reprint_loop
	
	call dir_list_print_file
	jr z, dir_move_off_edge_loop
	
	call dir_next
	jr nz, dir_move_off_bottom_reprint_loop
	
	jr dir_move_off_edge_loop

.dir_moved_off_top
	
	; decrement the offset
	ld hl, (dir_offset)
	ld de, -dir_cols
	add hl, de
	ld (dir_offset), hl
	
	; scroll the screen
	ld a, SOH
	oz (OS_Out)
	ld a, SD_UP
	oz (OS_Out)
	
	; redraw the top line of files
	ld de, (dir_offset)	
	call dir_set_index
	
	ld a, dir_left
	ld (cursor_x), a
	ld a, dir_top
	ld (cursor_y), a
	
	ld b, dir_cols
	
.dir_move_off_top_reprint_loop
	
	push bc
	call dir_list_print_file
	pop bc
	
	jr z, dir_move_off_edge_loop
	
	push bc
	call dir_next
	pop bc
	
	jr z, dir_move_off_edge_loop
	
	djnz dir_move_off_top_reprint_loop
	
	jr dir_move_off_edge_loop
	
.dir_move_not_off_bottom

	call goto_selected_file
	ld hl, selected_file_reverse_on
	oz (GN_Sop)

.dir_move_skip
	
	jp key_loop


.dir_enter
	
	; we can't do anything if we don't have any files
	ld hl, (dir_count)
	ld a, l
	or h
	jp z, key_loop
	
	; copy the selected filename from the directory listing
	ld de, (dir_selected)
	call dir_set_index
	
	ld bc, 4
	add hl, bc
	
	ld de, filename
	ld bc, filename_length + 2
	ldir
	
	; we can only act on directories
	ld a, (filename)
	cp 'd'
	jp nz, key_loop
	
	
	ld bc, (path + 0)
	ld hl, (path + 2)
	oz (OS_Mpb)
	
	ld b, 256 - filename_length
	ld c, 0

.change_dir_find_path_end
	ld a, (hl)
	or a
	jr z, change_dir_found_path_end
	inc hl
	inc c
	djnz change_dir_find_path_end

.change_dir_found_path_end
	
	ld a, c
	or a
	jr z, change_dir_found_path_end_empty
	
	ld (hl), '/'
	inc hl

.change_dir_found_path_end_empty
	
	ex de, hl
	ld hl, filename + 1
	ld bc, filename_length + 1
	ldir
	
	ld hl, filename + 1
	call change_directory
	jp dir_list_start

.dir_up_a_level
	ld hl, up_a_level
	call change_directory
	
	; now we need to pop the last '/' from the path
	ld bc, (path + 0)
	ld hl, (path + 2)
	oz (OS_Mpb)
	
	ld a, (hl)

.dir_up_find_path_end
	ld a, (hl)
	or a
	jr z, dir_up_found_path_end_empty
	cp '/'
	jr z, dir_up_found_path_end
	inc hl
	inc c
	jr dir_up_find_path_end

.dir_up_found_path_end_empty
	ld hl, (path + 2)
.dir_up_found_path_end
	ld (hl), 0
	jp dir_list_start

.appl_exit

	; de-initialise the drive
	call drive_deinit
	
	; free directory resources
	call dir_free
	
	; free path variable
	ld bc, (path+0)
	ld hl, (path+2)
	ld a, b
	or c
	or h
	or l
	jr z, path_not_allocated
	
	ld ix, (memory_pool)
	ld a, b
	ld bc, 256
	oz (OS_Mfr)

.path_not_allocated

	; free memory pool
	ld ix, (memory_pool)
	oz (OS_Mcl)

	; purge keyboard buffer
	oz (OS_Pur)
	
	; quit popdown with no error
	xor a
	oz (OS_Bye)

.drive_init
	
	; start by sending panel settings to reconfigure the serial port
	
	ld hl, drive_init_panel
	ld b, [drive_init_panel_end - drive_init_panel] / 5

.drive_init_loop
	
	push bc
	
	; fetch reason code
	ld c, (hl)
	inc hl
	ld b, (hl)
	inc hl
	
	; fetch data length
	ld a, (hl)
	inc hl
	
	; update the panel
	push hl
	oz (OS_Sp)
	pop hl
	
	; skip past the data bytes
	inc hl
	inc hl
	
	pop bc
	djnz drive_init_loop
	
	; open the serial port from its handle
	ld b, 0
	ld hl, port_name
	ld de, filename
	ld a, OP_UP
	oz (GN_Opf)
	
	; store the port handle
	ld (port_handle), ix
	
	; soft-reset the serial port
	ld l, SI_SFT
	oz (OS_Si)
	
	; set the default timeout
	ld l, SI_TMO
	ld bc, port_timeout
	oz (OS_Si)
	
	ret

.drive_init_panel
	defw PA_Txb
	defb 2
	defw 9600
	
	defw PA_Rxb
	defb 2
	defw 9600
	
	defw PA_Xon
	defb 1
	defb 'N'
	defb 0
	
	defw PA_Par
	defb 1
	defb 'N'
	defb 0
.drive_init_panel_end

.drive_deinit
	; close the port handle
	ld ix, (port_handle)
	oz (GN_Cl)
	ret

.port_name
	defm ":COM.0", 0

.sync
	ld b, 8
.sync_attempt_loop
	push bc
	call sync_attempt
	pop bc
	ret c
	ret z
	djnz sync_attempt_loop
	ret

.sync_attempt
	
	ld ix, (port_handle)

	; flush receive buffer
	ld l, SI_FRX
	oz (OS_Si)

.sync_flush_input
	ld bc, 1
	call get_byte_timeout
	jr nc, sync_flush_input
	
	; output a single CR
	ld a, CR
	call send_byte
	
	; bail out on timeout
	ret c
	
	; flush the initial response
	call flush_to_cr

	; send a multiple 'E' echo requests
.sync_wait_upper_echo_multiple
	ld a, 'E'
	call send_command_byte
	jp c, flush_to_cr
	
	; we expect to receive a single 'E' back
	ld a, 'E'
	call check_command_response
	jp c, flush_to_cr
	jr nz, sync_wait_upper_echo_multiple
	
	; now send a single 'e' echo request
	ld a, 'e'
	call send_command_byte
	jp c, flush_to_cr

	; we expect to receive a single 'e' back
.sync_wait_lower_echo
	ld a, 'e'
	call check_command_response
	jp c, flush_to_cr
	jr nz, sync_wait_lower_echo
	
	; now send a single 'E' echo request
	ld a, 'E'
	call send_command_byte
	jp c, flush_to_cr

.sync_wait_upper_echo_single
	ld a, 'E'
	call check_command_response
	jp c, flush_to_cr
	jr nz, sync_wait_upper_echo_single

.sync_finished_echo	
	
	; flush input
	call flush_to_cr
	
	; we should now be synchronised based on response to echos.
	
	; switch to short command set
	ld a, VDAP_SCS
	call send_command_byte
	jr c, sync_abort
	
	call check_prompt
	jr c, sync_abort
	jr nz, sync_abort
	
	; switch to binary (hex) mode
	ld a, VDAP_IPH
	call send_command_byte
	jr c, sync_abort
	
	call check_prompt
	jr c, sync_abort
	jr nz, sync_abort
	
	; suspend the disc after file operations
	ld a, VDAP_SUD
	call send_command_byte
	jr c, sync_abort
	
	call check_prompt
	jr c, sync_abort
	jr nz, sync_abort
	
	; check for the presence of a disc
	ld a, CR
	call send_cr
	jr c, sync_abort
	
	call check_prompt
	ld (has_disk), a

.sync_abort
	ret

; send a command byte
; in:  a = command to send
; out: Fc = 0 on success, Fc = 1 on timeout
.send_command_byte
	call send_byte
	ret c
.send_cr
	ld a, CR
	jp send_byte

; send a command string
; in:  a = command to send
;      hl = pointer to string argument to send (NUL or CR terminated)
; out: Fc = 0 on success, Fc = 1 on timeout
.send_command_string
	push hl
	call send_byte
	pop hl
	ret c
	
	ld a, ' '		
	push hl
	call send_byte
	pop hl
	ret c

.send_command_string_loop
	
	ld a, (hl)
	or a
	jr z, send_cr
	cp CR
	jr z, send_cr
	
	inc hl
	push hl
	call send_byte
	pop hl
	ret c
	jr send_command_string_loop

; gets and checks a byte from the serial port
; in:  a = byte to check
; out: Fc = 1 on timeout
;      Fz = 1 on successful match
.check_byte
	ld d, a
	call get_byte
	ret c
	cp d
	scf
	ccf
	ret
	
; checks for the '>' or 'ND' prompt(s)
; in:  a = command response to check for
; out: Fc = 1 on timeout
;      Fz = 1 on successful response
;      a = 1 if the prompt is '>', 0 if the prompt is 'ND'
.check_prompt
	call get_byte
	ret c
	
	ld e, 1
	cp '>'
	jr z, check_prompt_cr
	
	dec e
	cp 'N'
	jr z, check_prompt_no_disk
	
	; not > or ND
	scf
	ccf
	jr flush_to_cr

.check_prompt_no_disk
	
	ld a, 'D'
	call check_byte
	ret c
	jr nz, flush_to_cr
	
.check_prompt_cr
	ld a, CR
	call check_byte
	ret c
	ld a, e
	ret z
	jr flush_to_cr

; checks for a particular response to a command
; in:  a = command response to check for
; out: Fc = 1 on timeout
;      Fz = 1 on successful response
.check_command_response
	
	; check the first received byte and bail out on timeout
	call check_byte
	ret c
	
	; flush on error
	jr nz, flush_to_cr
	
	; check for CR
	ld a, CR
	call check_byte
	ret c
	ret z
	
	; fall-through to flush on error

; flush the input until timeout or CR received
.flush_to_cr
	push af
.flush_to_cr_loop
	ld bc, 1
	call get_byte_timeout
	jr c, flush_to_cr_timeout
	cp CR
	jr nz, flush_to_cr_loop
.flush_to_cr_timeout
	pop af
	ret

.print_hex_nybble
	and $0F
	cp 10
	jr c, print_hex_nybble_09

.print_hex_nybble_af
	add a, 'A'-10
	oz (OS_Out)
	ret

.print_hex_nybble_09
	add a, '0'
	oz (OS_Out)
	ret
	
.print_hex_byte
	push af	
	srl a
	srl a
	srl a
	srl a
	call print_hex_nybble
	pop af
	push af
	call print_hex_nybble
	pop af
	ret

.print_hex_word
	push af
	ld a, h
	call print_hex_byte
	ld a, l
	call print_hex_byte
	pop af
	ret

.send_byte
	ld bc, port_timeout
.send_byte_timeout
	oz (OS_Pbt)
	ret
	
	; send_byte debug
	push af
	ld a, '>'
	oz (OS_Out)
	pop af
	push af
	call print_hex_byte
	pop af
	
	oz (OS_Pbt)
	ret

.get_byte
	ld bc, port_timeout
.get_byte_timeout
	oz (OS_Gbt)
	ret
	
	; get_byte debug
	ret c
	push af
	ld a, '<'
	oz (OS_Out)
	pop af
	push af
	call print_hex_byte
	pop af
	ret


.dir_free
	
	; reset the file list count
	ld hl, 0
	ld (dir_count), hl

.dir_free_loop

	ld bc, (dir_list + 0)
	ld hl, (dir_list + 2)
	
	ld a, b
	or c
	or h
	or l
	
	jr z, dir_free_done
	
	; bchl points to allocated item
	
	push bc
	oz (OS_Mpb)
	pop bc
	
	; get pointer to next item
	push hl
	
	ld e, (hl)
	inc hl
	ld d, (hl)
	inc hl
	
	ld (dir_list + 0), de
	
	ld e, (hl)
	inc hl
	ld d, (hl)

	ld (dir_list + 2), de
	
	pop hl
	
	; free item
	ld ix, (memory_pool)
	ld a, b
	ld bc, 32
	oz (OS_Mfr)
	
	jr dir_free_loop

.dir_free_done
	
	ld hl, 0
	ld (dir_list + 0), hl
	ld (dir_list + 2), hl
	
	ret

.dir
	
	; free any previously-used memory
	call dir_free

	; sync
	call sync
	ret c
	ret nz
	
	; only perform a directory listing if we have a disk
	ld a, (has_disk)
	or a
	ret z
	
	; request a directory listing
	ld a, VDAP_DIR
	call send_command_byte
	
	; check for CR
	ld a, CR
	call check_byte
	ret c
	jp nz, flush_to_cr
	
.dir_loop

	; memory allocation changes the handle
	ld ix, (port_handle)

	; fetch a byte of the filename
	call get_byte
	ret c
	
	; is it the end of the directory listing?
	cp '>'
	jp z, dir_end
	
	; store the filename
	ld hl, filename
	
	; default assumption is that it's a file rather than a directory
	ld (hl), 'f'
	inc hl
	
	ld b, filename_length ; maximum length (just in case)

.dir_filename_loop
	
	ld (hl), a
	inc hl
	
	; fetch the next byte
	push bc
	call get_byte
	pop bc
	ret c
	
	; is it the end of the filename?
	cp CR
	jr z, dir_got_filename
	djnz dir_filename_loop
	
	; filename is too long if we get here
	call flush_to_cr

.dir_got_filename
	
	; append NUL terminator
	ld (hl), 0
	
	; is it a file or a directory?
	ld hl, filename + 1
	
	; look for the space
.filename_is_dir_loop
	ld a, (hl)
	inc hl
	or a
	jr z, filename_not_dir
	
	cp ' '
	jr z, filename_possibly_dir
	jr filename_is_dir_loop

.filename_possibly_dir

	ld a, (hl)
	inc hl
	cp 'D'
	jr nz, filename_not_dir
	
	ld a, (hl)
	inc hl
	cp 'I'
	jr nz, filename_not_dir
	
	ld a, (hl)
	inc hl
	cp 'R'
	jr nz, filename_not_dir
	
	ld a, (hl)
	or a
	jr nz, filename_not_dir
	
	; at this point, the filename is definitely a directory
	
	; trim the last four characters (" DIR")
	ld de, -4
	add hl, de
	ld (hl), 0
	
	; mark the filename as a directory
	ld hl, filename
	ld (hl), 'd'
	inc hl
	
	; is the filename all '.'?

.check_dot_dir_loop
	ld a, (hl)
	inc hl
	
	; if we've reached the end of the filename
	; then it's all '.'!
	or a
	jp z, dir_loop
	
	cp '.'
	jr z, check_dot_dir_loop
	
.filename_not_dir
	
	; allocate memory to store the filename
	
	xor a
	ld ix, (memory_pool)
	ld bc, 32
	oz (OS_Mal)
	
	jp c, appl_exit ; out of memory
	
	; store the pointers away for safe keeping
	ld (dir_list_new + 0), bc
	ld (dir_list_new + 2), hl

	; update bank binding
	push bc
	oz (OS_Mpb)
	pop bc
	
	; bchl now points to allocated memory
	
	; zero pointers
	ld d, h
	ld e, l
	inc de
	
	ld (hl), 0
	ld bc, 3
	ldir
	
	; copy over the filename
	ld hl, filename
	ld bc, filename_length + 2
	ldir
	
	; where in the linked list are we going to store the filename?
	
	ld de, (dir_count)
	ld a, e
	or d
	jr nz, dir_not_first_filename

.dir_first_filename
	
	; the first filename is easy, just put that at the head of the list
	
	ld bc, (dir_list_new + 0)
	ld hl, (dir_list_new + 2)
	
	ld (dir_list + 0), bc
	ld (dir_list + 2), hl
	
	jp dir_allocated_filename

.dir_not_first_filename
	
	; subsequent file names are a bit more awkward to store
	
	; we'll work through the linked list of known file names
	; if our received filename is < the stored filename,
	; we'll insert our received filename before it.
	
	; start from the head of the list
	call dir_reset_index
	
	; compare
	ld de, 4
	add hl, de
	ld de, filename
	call str_cmp
	
	; it's not before the current head, use the regular sort loop
	jr nc, dir_sort_loop
	
	; we need to insert our new filename before the current head

.dir_before_head
	; update our new record to say the current head comes next
	ld bc, (dir_list_new + 0)
	ld hl, (dir_list_new + 2)
	
	oz (OS_Mpb)
	
	ld bc, (dir_list + 0)
	
	ld (hl), c
	inc hl
	ld (hl), b
	inc hl
	
	ld bc, (dir_list + 2)
	ld (hl), c
	inc hl
	ld (hl), b
	
	; now update the current head record to point at our new record
	
	ld bc, (dir_list_new + 0)
	ld hl, (dir_list_new + 2)
	
	ld (dir_list + 0), bc
	ld (dir_list + 2), hl
	
	jr dir_allocated_filename
	
.dir_sort_loop
	
	; move to the next record
	ld bc, (dir_list_ptr + 0)
	ld hl, (dir_list_ptr + 2)
	
	ld (dir_list_old + 0), bc
	ld (dir_list_old + 2), hl
	
	call dir_next

	; if we've run out of records, append to the tail of the list
	jr z, dir_after_tail
	
	; compare
	ld de, 4
	add hl, de
	ld de, filename
	call str_cmp
	
	; our new file doesn't go before the current one,
	; so try the next item in the list
	jr nc, dir_sort_loop

.dir_before_current
	
	; we need to insert our new record between old and current
	
	; set old to point to our new record
	ld bc, (dir_list_old + 0)
	ld hl, (dir_list_old + 2)
	
	oz (OS_Mpb)
	
	ld bc, (dir_list_new + 0)
	ld de, (dir_list_new + 2)
	
	ld (hl), c
	inc hl
	ld (hl), b
	inc hl
	ld (hl), e
	inc hl
	ld (hl), d
	
	ex de, hl
	
	; set new record to point to current
	oz (OS_Mpb)
	
	ld bc, (dir_list_ptr + 0)
	ld (hl), c
	inc hl
	ld (hl), b
	inc hl
	
	ld bc, (dir_list_ptr + 2)
	ld (hl), c
	inc hl
	ld (hl), b
	
	jr dir_allocated_filename

.dir_after_tail

	; if we get this far, we've reached the end of the list
	; append our record to the end
	
	ld bc, (dir_list_ptr + 0)
	ld hl, (dir_list_ptr + 2)
	
	oz (OS_Mpb)
	
	ld bc, (dir_list_new + 0)
	ld (hl), c
	inc hl
	ld (hl), b
	inc hl
	
	ld bc, (dir_list_new + 2)
	ld (hl), c
	inc hl
	ld (hl), b

.dir_allocated_filename
	
	; increment the count of received files
	ld hl, (dir_count)
	inc hl
	ld (dir_count), hl

	; fetch next filename
	jp dir_loop

.dir_end
	
	call dir_reset_index
	
	call flush_to_cr
	
	xor a
	ret


	
.dir_reset_index
	ld de, 0
	; fall-through to dir_set_index
	
.dir_set_index
	
	; start from the front of the list
	ld bc, (dir_list + 0)
	ld hl, (dir_list + 2)

.dir_set_index_loop
	
	; update bank binding
	push bc
	oz (OS_Mpb)
	pop bc
	
	; is this the file name at the index we wanted?
	ld a, d
	or e
	jr nz, dir_set_index_next
	
	ld (dir_list_ptr + 0), bc
	ld (dir_list_ptr + 2), hl
	ret

.dir_set_index_next

	; no, so advance to next file name
	dec de
	push de
	
	; find next item's pointer
	ld c, (hl)
	inc hl
	ld b, (hl)
	inc hl
	ld e, (hl)
	inc hl
	ld d, (hl)
	
	ex de, hl
	pop de
	
	jr dir_set_index_loop

.dir_next
	
	ld bc, (dir_list_ptr + 0)
	ld hl, (dir_list_ptr + 2)
	
	oz (OS_Mpb)

	; find next item's pointer
	ld c, (hl)
	inc hl
	ld b, (hl)
	inc hl
	
	ld e, (hl)
	inc hl
	ld d, (hl)
	inc hl
	
	ex de, hl
	
	; have we reached the end of the list?
	ld a, b
	or c
	or h
	or l
	
	ret z
	
	ld (dir_list_ptr + 0), bc
	ld (dir_list_ptr + 2), hl
	
	push bc
	oz (OS_Mpb)
	pop bc
	
	ret

.change_directory
	
	push hl
	call dir_free
	call sync
	pop hl
	
	ret c
	ret nz

	; only change directory if we have a disk
	ld a, (has_disk)
	or a
	ret z
	
	ld a, VDAP_CD
	call send_command_string
	ret c
	
	jp dir


; checks for incoming events from the drive
; out: Fz = 1 if there are no events
;      Fz = 0 if there is an event with A being the event code
.check_events

	; check if there's any incoming data
	ld ix, (port_handle)
	ld l, SI_ENQ
	oz (OS_Si)
	
	ld a, d
	or a
	ret z
	
	; what is the incoming event?
	ld hl, filename
	ld b, filename_length
	
.check_events_get_event
	push bc
	ld bc, 1
	call get_byte_timeout
	pop bc
	jr c, check_events_error
	
	cp CR
	jr z, check_events_got_event
	
	ld (hl), a
	inc hl
	djnz check_events_get_event
	
	; if we fall off the end, the event is too long
	jr check_events_error

.check_events_got_event
	ld (hl), 0
	
	; check each event string in turn
	ld hl, event_strings
	ld de, filename

.check_events_check_next_event

	; have we run out of event strings?
	ld a, (hl)
	or a
	jr z, check_events_unidentified_event
	
	; check the string
	call str_cmp
	jr z, check_events_identified_event

	; not a match, so skip over the NUL terminator
.check_events_find_next_event
	ld a, (hl)
	inc hl
	or a
	jr nz, check_events_find_next_event
	
	; skip over the event ID, then try next string
	inc hl
	jr check_events_check_next_event


.check_events_identified_event
	; skip over the NUL terminator
	ld a, (hl)
	inc hl
	or a
	jr nz, check_events_identified_event
	
	; fetch event ID
	ld a, (hl)
	or a
	ret

.check_events_unidentified_event
	ld a, EVENT_UNKNOWN
	or a
	ret

.check_events_error
	; pretend nothing happened
	call flush_to_cr
	xor a
	ret

	defc EVENT_NO_UPGRADE      = '#'
	defc EVENT_NO_DISK         = '0'
	defc EVENT_DEVICE_REMOVED  = '-'
	defc EVENT_DEVICE_DETECTED = '+'
	defc EVENT_UNKNOWN         = '?'

.event_strings
	defm "NU", 0,  EVENT_NO_UPGRADE
	defm "ND", 0,  EVENT_NO_DISK
	defm "DR2", 0, EVENT_DEVICE_REMOVED
	defm "DD2", 0, EVENT_DEVICE_DETECTED
	defb 0

.window_full
	defm SOH, "7#1", 32 + 1, 32 + 0, 32 + dir_item_width * dir_cols, 32 + 8, 128 + 1
	defm SOH, "2C1"
	defm SOH, "3+SC"
	defb 0

.window_dir
	defm SOH, "7#1", 32 + 1, 32 + 1, 32 + dir_item_width * dir_cols, 32 + 7, 128
	defm SOH, "2C1"
	defm SOH, "3-SC"
	defb 0

.window_title_begin
	defm SOH, "7#1", 32 + 1, 32 + 0, 32 + dir_item_width * dir_cols, 32 + 1, 128 + 1 + 2
	defm SOH, "4+TUR"
	defm SOH, "2JC"
	defm FF
	defm SOH, "3@", 32 + 0, 32 + 0
	defb 0

.window_title_end
	defm SOH, "4-TUR"
	defm SOH, "2JC"
	defb 0

.goto_selected_file

	ld hl, (dir_selected)
	ld de, (dir_offset)
	or a
	sbc hl, de
	ld b, l
	
	ld a, dir_left
	ld (cursor_x), a
	
	ld a, dir_top
	ld (cursor_y), a
	
	ld a, b
	or a
	jr z, goto_cursor

.goto_selected_file_loop

	ld a, (cursor_x)
	add a, dir_item_width
	cp dir_right
	jr nz, goto_selected_file_next_x
	
	ld a, (cursor_y)
	inc a
	ld (cursor_y), a
	
	ld a, dir_left

.goto_selected_file_next_x
	ld (cursor_x), a
	
	djnz goto_selected_file_loop
	; fall-through to goto_cursor

.goto_cursor
	
	ld a, SOH
	oz (OS_Out)
	ld a, '3'
	oz (OS_Out)
	ld a, '@'
	oz (OS_Out)
	
	ld a, (cursor_x)
	add a, 32
	oz (OS_Out)
	
	ld a, (cursor_y)
	add a, 32
	oz (OS_Out)
	
	ret

.connecting
	defm "Connecting to drive...", 0

.ok
	defm "OK", 0

.no_disk
	defm "No disk", 0

.selected_file_reverse_on
	defm SOH, "2+R"
	defm SOH, "2A", 32 + dir_item_width
	defm SOH, "2-R"
	defb 0

.selected_file_reverse_off
	defm SOH, "2-R"
	defm SOH, "2A", 32 + dir_item_width
	defb 0

.working_file_is_file
	defm SOH, "2-T"
	defb 0

.working_file_is_dir
	defm SOH, "2+T"
	defb 0

.up_a_level
	defm "..", 0

.up_to_root
	defm "/", 0

.path_prefix
	defm "D:/", 0

.str_cmp
	push hl
	push de
	call str_cmp_loop
	pop de
	pop hl
	ret
	
.str_cmp_loop
	ld a, (de)
	cp (hl)
	ret nz
	or a
	ret z
	
	inc hl
	inc de
	jr str_cmp_loop