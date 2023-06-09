	module VDriveZ88

include "director.def"
include "dor.def"
include "stdio.def"
include "serintfc.def"
include "syspar.def"
include "fileio.def"
include "error.def"
include "memory.def"
include "integer.def"
include "time.def"
include "fpp.def"

include "vdap.def"

; General constants

	defc port_timeout_default = 25 ; 1/4 second
	defc port_timeout_long = 50 ; 1/2 second
	defc filename_length = 20
	
	defc dir_item_width = 14
	defc dir_cols = 6
	defc dir_rows = 7
	
	defc dir_left = 0
	defc dir_top = 0
	defc dir_right = dir_left + dir_item_width * dir_cols
	defc dir_bottom = dir_top + dir_rows

; Unsafe workspace variables

	defc unsafe_ws = 152
	defc safe_ws = 0
	
	defc ram_vars = $1FFE - unsafe_ws
	
	defvars ram_vars {
		screen_handle    ds.w 1          ; screen handle
		port_handle      ds.w 1          ; serial port handle
		port_timeout     ds.w 1          ; serial port timeout
		file_handle      ds.w 1          ; file handle
		filename         ds.b 32         ; buffer for filenames
		has_disk         ds.b 1          ; whether the drive has a disk in it or not
		memory_pool      ds.w 1          ; memory allocation pool
		dir_list         ds.w 2          ; pointer to first file in list
		dir_count        ds.w 1          ; number of files in file list
		dir_list_ptr     ds.w 2          ; pointer to current item in file list
		dir_list_new     ds.w 2          ; pointer to new item in the file list
		dir_list_old     ds.w 2          ; pointer to old item in the file list
		cursor_x         ds.b 1          ; cursor x
		cursor_y         ds.b 1          ; cursor y
		dir_offset       ds.w 1          ; offset into directory listing
		dir_working      ds.w 1          ; working file index
		dir_selected     ds.w 1          ; selected file index
		path             ds.w 2          ; pointer to storage for full file path
		file_size        ds.b 4          ; size of a file
		file_created     ds.w 2          ; file creation date+time
		file_accessed    ds.w 2          ; file accessed date+time
		file_modified    ds.w 2          ; file modification date+time
		oz_date_time     ds.b 6          ; OZ-format date+time
		local_filename   ds.b 32         ; local filename for copy operations
		file_buffer      ds.w 2          ; allocated buffer to handle file transfers
		data_transferred ds.b 4          ; general "data remaining" counter
		data_remaining   ds.b 4          ; general "data remaining" counter
		chunk_size       ds.w 2          ; when transferring data to/from the drive
		old_pa_txb_size  ds.b 1          ; transmit baud rate is 1 or 2 bytes
		old_pa_txb       ds.w 1          ; original transmit baud rate
		old_pa_rxb_size  ds.b 1          ; receive baud rate is 1 or 2 bytes
		old_pa_rxb       ds.w 1          ; original receive baud rate
		old_pa_xon       ds.b 1          ; original xon/off state
		old_pa_par       ds.b 1          ; original parity state
		ram_vars_end     ds.b 1
	}
	
	if ram_vars_end - ram_vars > unsafe_ws
		error "Too many variables"
	endif

; Application bank and origin

	defc appl_bank = $3F                ; default to top bank loading
	org $E000

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
	defw topics_dor
	defb appl_bank
	defw commands_dor
	defb appl_bank
	defw help_dor
	defb appl_bank
	defw tokens_dor
	defb appl_bank
.inhlpend
	defb 'N'                            ; key to name section
	defb innamend-innamstart
.innamstart
	defm "VDrive", 0
.innamend
	defb $FF
.indorend

.topics_dor
	defb 0                              ; start marker
.topic_commands
	defb topic_end - topic_commands     ; length byte
	defm "Commands"                     ; topic name
	defb >(help_commands - help_dor)    ; help offset msb
	defb <(help_commands - help_dor)    ; help offset lsb
	defb TPCF_HELP                      ; topic attributes
	defb topic_end - topic_commands     ; length byte
.topic_end
	defb 0                              ; end marker

.commands_dor
	defb 0                              ; start marker

.cmd_rename
	defb cmd_rename_end - cmd_rename    ; length byte
	defb 'R'                            ; command code
	defm "RE", 0                        ; keyboard sequence
	defm "Rename"                       ; command name
	defb >(help_rename - help_dor)      ; help offset msb
	defb <(help_rename - help_dor)      ; help offset lsb
	defb CMDF_HELP                      ; command attributes
	defb cmd_rename_end - cmd_rename    ; length byte
.cmd_rename_end

.cmd_erase
	defb cmd_erase_end - cmd_erase      ; length byte
	defb 'E'                            ; command code
	defm "ER", 0                        ; keyboard sequence
	defm "Erase"                        ; command name
	defb >(help_erase - help_dor)       ; help offset msb
	defb <(help_erase - help_dor)       ; help offset lsb
	defb CMDF_HELP                      ; command attributes
	defb cmd_erase_end - cmd_erase      ; length byte
.cmd_erase_end

.cmd_create
	defb cmd_create_end - cmd_create    ; length byte
	defb 'C'                            ; command code
	defm "CD", 0                        ; keyboard sequence
	defm "Create Directory"             ; command name
	defb >(help_create - help_dor)      ; help offset msb
	defb <(help_create - help_dor)      ; help offset lsb
	defb CMDF_HELP                      ; command attributes
	defb cmd_create_end - cmd_create    ; length byte
.cmd_create_end

.cmd_up_dir
	defb cmd_up_dir_end - cmd_up_dir    ; length byte
	defb IN_SUP                         ; command code
	defm IN_SUP, 0                      ; keyboard sequence
	defm "Up Directory"                 ; command name
	defb >(help_up_dir - help_dor)      ; help offset msb
	defb <(help_up_dir - help_dor)      ; help offset lsb
	defb CMDF_COLUMN|CMDF_HELP          ; command attributes
	defb cmd_up_dir_end - cmd_up_dir    ; length byte
.cmd_up_dir_end

.cmd_dwn_dir
	defb cmd_dwn_dir_end - cmd_dwn_dir  ; length byte
	defb IN_SDWN                        ; command code
	defm IN_SDWN, 0                     ; keyboard sequence
	defm "Down Directory", 0            ; command name
	defb >(help_dwn_dir - help_dor)     ; help offset msb
	defb <(help_dwn_dir - help_dor)     ; help offset lsb
	defb CMDF_HELP                      ; command attributes
	defb cmd_dwn_dir_end - cmd_dwn_dir  ; length byte
.cmd_dwn_dir_end

.cmd_cur_rgt
	defb cmd_cur_rgt_end - cmd_cur_rgt  ; length byte
	defb IN_RGT                         ; command code
	defm IN_RGT, 0                      ; keyboard sequence
	defm "Cursor Right", 0              ; command name
	defb cmd_cur_rgt_end - cmd_cur_rgt  ; length byte
.cmd_cur_rgt_end

.cmd_cur_lft
	defb cmd_cur_lft_end - cmd_cur_lft  ; length byte
	defb IN_LFT                         ; command code
	defm IN_LFT, 0                      ; keyboard sequence
	defm "Cursor Left", 0               ; command name
	defb cmd_cur_lft_end - cmd_cur_lft  ; length byte
.cmd_cur_lft_end

.cmd_cur_up
	defb cmd_cur_up_end - cmd_cur_up    ; length byte
	defb IN_UP                          ; command code
	defm IN_UP, 0                       ; keyboard sequence
	defm "Cursor Up", 0                 ; command name
	defb cmd_cur_up_end - cmd_cur_up    ; length byte
.cmd_cur_up_end

.cmd_cur_dwn
	defb cmd_cur_dwn_end - cmd_cur_dwn  ; length byte
	defb IN_DWN                         ; command code
	defm IN_DWN, 0                      ; keyboard sequence
	defm "Cursor Down", 0               ; command name
	defb cmd_cur_dwn_end - cmd_cur_dwn  ; length byte
.cmd_cur_dwn_end

.cmd_send
	defb cmd_send_end - cmd_send        ; length byte
	defb 'S'                            ; command code
	defm "ES", 0                        ; keyboard sequence
	defm "Send to Drive"                ; command name
	defb >(help_send - help_dor)        ; help offset msb
	defb <(help_send - help_dor)        ; help offset lsb
	defb CMDF_COLUMN|CMDF_HELP          ; command attributes
	defb cmd_send_end - cmd_send        ; length byte
.cmd_send_end

.cmd_fetch
	defb cmd_fetch_end - cmd_fetch      ; length byte
	defb 'F'                            ; command code
	defm "EF", 0                        ; keyboard sequence
	defm "Fetch from Drive"             ; command name
	defb >(help_fetch - help_dor)       ; help offset msb
	defb <(help_fetch - help_dor)       ; help offset lsb
	defb CMDF_HELP                      ; command attributes
	defb cmd_fetch_end - cmd_fetch      ; length byte
.cmd_fetch_end

	defb 1                              ; end of topic
	defb 0                              ; end of all topics

.help_dor
	defm DEL
	defm "Version 1.0", DEL
	defm DEL
	defm "Send files to and fetch files from a Vinculum", DEL
	defm "USB host device such as the VDrive or VMusic.", DEL
	defm DEL
	defm "Ben Ryves 2023 - https://benryves.com/", 0

.help_commands
	defm "The current directory listing will be shown with directories", DEL
	defm "at the top in small capitals (", SOH, "2+TDIRNAME", SOH, "2-T) and files underneath.", DEL
	defm "You can move around the listing using the ", TOK_CURSOR_KEYS, " keys,", DEL
	defm "enter directories or fetch files with the ", TOK_ENTER, " key,", DEL
	defm "or erase files with the ", TOK_DEL, " key.", DEL
	defm "Other operations can be accessed with the ", TOK_MENU, " key.", 0

.help_rename
	defm DEL
	defm "Rename existing files or directories on the USB drive.", 0

.help_erase
	defm DEL
	defm "Erase existing files or directories from the USB drive.", DEL
	defm DEL
	defm "Directories that contain other items cannot be erased,", DEL
	defm "so make sure to empty them before erasing them.", DEL
	defm DEL
	defm "Files or directories can also be erased with the ", TOK_DEL, " key.", 0

.help_create
	defm DEL
	defm "Create a new directory on the USB drive.", 0

.help_up_dir
	defm DEL
	defm "Move up to the parent directory of the current directory.", 0

.help_dwn_dir
	defm DEL
	defm "Move down into the highlighted child directory.", DEL
	defm DEL
	defm "You can also enter child directories by highlighting them", DEL
	defm "and pressing the ", TOK_ENTER, " key.", 0

.help_send
	defm DEL
	defm "Send a file from the Z88's file system to the", DEL
	defm "current directory on the USB drive.", 0

.help_fetch
	defm DEL
	defm "Fetch the highlighted file from the USB drive and save it", DEL
	defm "on the Z88's file system.", DEL
	defm DEL
	defm "You can also fetch files by highlighting them and pressing", DEL
	defm "the ", TOK_ENTER, " key.", 0

.tokens_dor
	defb (token_80 - tokens_list) / 2
	defb (token_80 - tokens_list) / 2
.tokens_list
	defw token_80 - tokens_dor
	defw token_81 - tokens_dor
	defw token_82 - tokens_dor
	defw token_83 - tokens_dor
	defw tokens_end - tokens_dor
.token_80
	defm SOH, SD_ENT
.token_81
	defm SOH, SD_DEL
.token_82
	defm SOH, SD_ORGT, SOH, SD_OLFT, SOH, SD_OUP, SOH, SD_ODWN
.token_83
	defm SOH, SD_MNU
.tokens_end

defc TOK_ENTER       = $80
defc TOK_DEL         = $81
defc TOK_CURSOR_KEYS = $82
defc TOK_MENU        = $83

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
	
	; back up original panel settings
	ld a, 2
	ld bc, PA_Txb
	ld de, old_pa_txb
	oz (OS_Nq)
	jr c, bye_error
	ld (old_pa_txb_size), a
	
	ld a, 2
	ld bc, PA_Rxb
	ld de, old_pa_rxb
	oz (OS_Nq)
	jr c, bye_error
	ld (old_pa_rxb_size), a
	
	ld a, 1
	ld bc, PA_Xon
	ld de, old_pa_xon
	oz (OS_Nq)
	jr c, bye_error
	
	ld a, 1
	ld bc, PA_Par
	ld de, old_pa_par
	oz (OS_Nq)
	jr c, bye_error
	
	; use segment 1 for memory allocations
	ld a, MM_S1
	ld bc, 0
	oz (OS_Mop)
	jr nc, opened_pool
	
	; quit with error message
.bye_error
	oz (GN_Err)
	oz (OS_Bye)
	
.opened_pool
	ld (memory_pool), ix
	
	; allocate memory for the path
	xor a
	ld bc, 256
	oz (OS_Mal)
	jp c, appl_exit
	
	ld (path + 0), bc
	ld (path + 2), hl
	
	oz (OS_Mpb)
	ld (hl), 0
	
	; allocate memory for the file transfer buffer
	xor a
	ld bc, 256
	oz (OS_Mal)
	jp c, appl_exit
	
	ld (file_buffer + 0), bc
	ld (file_buffer + 2), hl
	
	; open the screen from its name
	ld bc, filename_length
	ld hl, screen_name
	ld de, filename
	ld a, OP_UP
	oz (GN_Opf)
	
	jp c, appl_exit
	
	; store the port handle
	ld (screen_handle), ix
	
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
	
	call busy_start
	
	; path is already cleared, so just skip to the root directory
	ld hl, up_to_root
	call change_directory
	
	; clear the screen
	ld hl, window_full
	oz (GN_Sop)
	
	call busy_end
	
	; skip the next block as we've already reset the path
	jr dir_list_start
	
.dir_list_start_from_current
	
	call busy_start
	call dir
	call busy_end
	
	jr dir_list_start

.dir_list_start_from_root

	; clear the stored path
	ld bc, (path + 0)
	ld hl, (path + 2)
	
	oz (OS_Mpb)
	ld (hl), 0
	
	call busy_start

	; initially start from the root directory
	ld hl, up_to_root
	call change_directory

	call busy_end

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
	
	; ensure it's ungreyed
	call ungrey_window
	
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
	
.dir_list_selection_on_screen_check
	; ensure that the selected index is on-screen
	ld hl, (dir_selected)
	ld de, (dir_offset)
	or a
	sbc hl, de
	
	bit 7, h
	jr nz, dir_list_selection_off_top
	
	ld de, dir_cols * dir_rows
	
	or a
	sbc hl, de
	jr c, dir_list_selection_on_screen

.dir_list_selection_off_bottom

	; increment the offset
	ld hl, (dir_offset)
	ld de, +dir_cols
	add hl, de
	ld (dir_offset), hl
	
	jr dir_list_selection_on_screen_check

.dir_list_selection_off_top
	
	; decrement the offset
	ld hl, (dir_offset)
	ld de, -dir_cols
	add hl, de
	ld (dir_offset), hl
	
	jr dir_list_selection_on_screen_check
	
.dir_list_selection_on_screen
	
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
	
	cp DEL
	jp z, delete_file
	
	; if it's a filename character, can we jump to the next file starting with its initial?
	call char_to_upper
	call validate_filename_char
	jr c, key_loop
	
	; jump to next item starting with the initial just pressed
	ld c, a
	
	ld hl, (dir_count)
	ld a, h
	or l
	jr z, key_loop
	
	; start from the current file
	push bc
	ld de, (dir_selected)
	ld (dir_working), de
	call dir_set_index
	pop bc
	
.next_lettered_file_loop
	; advance to the next file
	push bc
	ld de, (dir_working)
	inc de
	push de
	call dir_next
	pop de
	jr nz, next_lettered_file_nowrap
	call dir_reset_index
	ld de, 0
.next_lettered_file_nowrap
	ld (dir_working), de
	pop bc
	
	; does the file start with our desired character?
	ld de, 4 + 1
	add hl, de
	ld a, (hl)
	cp c
	jr z, next_lettered_file_found
	
	; have we looped around?
	ld hl, (dir_working)
	ld de, (dir_selected)
	or a
	sbc hl, de
	jr nz, next_lettered_file_loop

.next_lettered_file_found
	; how far have we moved?
	ld hl, (dir_working)
	ld de, (dir_selected)
	or a
	sbc hl, de
	jr z, key_loop
	ex de, hl
	
	jp dir_move_16

.key_error
	
	; time-outs are OK
	cp RC_TIME
	jp z, key_loop
	
	cp RC_SUSP
	jp z, key_loop
	
	cp RC_DRAW
	jp z, dir_list_start
	
	; treat any other errors as a request to quit
	jp appl_exit

.extended_key
	oz (OS_In)
	jr c, key_error
	
	cp 'R'
	jp z, rename_file
	
	cp 'E'
	jp z, delete_file
	
	cp 'C'
	jp z, create_dir
	
	cp IN_SUP
	jp z, dir_up_a_level
	
	cp IN_SDWN
	jp z, dir_down_a_level
	
	cp IN_RGT
	jr z, dir_move_right

	cp IN_LFT
	jr z, dir_move_left

	cp IN_UP
	jr z, dir_move_up
	
	cp IN_DWN
	jr z, dir_move_down
	
	cp 'S'
	jp z, send_file
	
	cp 'F'
	jp z, dir_fetch
	
	jp key_loop

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

.dir_move_16
	
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
	ld (dir_working), de
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
	ld (dir_working), de
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
	
	jp z, dir_move_off_edge_loop
	
	djnz dir_move_off_top_reprint_loop
	
	jp dir_move_off_edge_loop
	
.dir_move_not_off_bottom

	call goto_selected_file
	ld hl, selected_file_reverse_on
	oz (GN_Sop)

.dir_move_skip
	
	jp key_loop


.dir_down_a_level
	
	call dir_enter_begin
	jp z, key_loop
	cp 'd'
	jp nz, key_loop
	jr dir_enter_dir

.dir_fetch
	
	call dir_enter_begin
	jp z, key_loop
	cp 'f'
	jp nz, key_loop
	jr dir_enter_file

.dir_enter
	
	call dir_enter_begin
	jp z, key_loop
	
	
	cp 'd'
	jr z, dir_enter_dir
	
	cp 'f'
	jr z, dir_enter_file
	
	jp key_loop

.dir_enter_begin
	; we can't do anything if we don't have any files
	ld hl, (dir_count)
	ld a, l
	or h
	ret z
	
	; copy the selected filename from the directory listing
	ld de, (dir_selected)
	call dir_set_index
	
	ld bc, 4
	add hl, bc
	
	ld de, filename
	ld bc, filename_length + 2
	ldir
	
	; are we acting on a file or a directory?
	ld a, (filename)
	
	or a
	ret

.dir_enter_dir
	
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
	
	call busy_start
	call grey_window
	
	ld hl, filename + 1
	call change_directory
	
	call busy_end
	
	jp dir_list_start

.dir_enter_file
	ld hl, filename + 1
	call get_file_info
	
	jp c, key_loop
	jp nz, key_loop
	
	; prepare the local filename
	ld hl, filename + 1
	ld de, local_filename
	ld bc, 32
	ldir

.dir_copy_file_redraw_dialog

	ld hl, window_dialog_begin
	oz (GN_Sop)
	ld hl, filename + 1
	oz (GN_Sop)
	ld hl, window_dialog_end
	oz (GN_Sop)

.dir_copy_file_show_info

	call dialog_show_size_and_dates
	
	; get the length of the local filename
	ld hl, local_filename
	call str_len
	
.dir_enter_file_prompt_loop
	
	; prompt for file name to save as
	ld hl, save_as_file
	oz (GN_Sop)

	call enable_cursor
	
	ld a, 1
	ld b, 21	
	ld hl, local_filename
	ld de, local_filename
	oz (GN_Sip)
	
	call disable_cursor
	
	jr nc, dir_enter_file_prompt_ok

.dir_enter_file_prompt_error
	
	cp RC_QUIT
	jp z, appl_exit
	
	cp RC_SUSP
	jp z, dir_enter_file_prompt_loop
	
	cp RC_DRAW
	jp z, dir_enter_file
	
	ld hl, window_dialog_close
	oz (GN_Sop)
	
	cp RC_ESC
	jp z, dir_list_start
	
	jp appl_exit

.dir_enter_file_prompt_ok
	cp ESC
	ld a, RC_ESC
	jr z, dir_enter_file_prompt_error
	
	; ... copy the file ...
	ld bc, (file_buffer + 0)
	ld hl, (file_buffer + 2)
	
	oz (OS_Mpb)
	ex de, hl
	
	; try to open the file for input
	ld bc, 255
	ld hl, 0
	ld (file_handle), hl
	ld hl, local_filename
	ld a, OP_IN
	oz (GN_Opf)
	
	jr c, copy_file_not_found

	; if we can open the file, it already exists... so close it
	oz (GN_Cl)
	jp c, copy_file_error
	
	; prompt for overwrite
	
	; overwrite prompt
	ld hl, overwrite
	oz (GN_Sop)
	
	ld bc, (file_buffer + 0)
	ld hl, (file_buffer + 2)
	oz (OS_Mpb)
	
	oz (GN_Sop)
	
	call get_cursor
	
	ld a, 11
	ld (cursor_x), a
	call goto_cursor
	
	ld a, 'N'
	call confirm
	jp c, appl_exit
	
	cp ESC
	jp z, copy_file_exit
	
	cp 'Y'
	jr z, copy_file_can_overwrite
	
	jp dir_copy_file_show_info

.copy_file_not_found

	; is the problem a bad filename?
	cp RC_IVF
	jr nz, copy_file_can_overwrite
	
	oz (GN_Err)
	jp dir_copy_file_show_info

.copy_file_can_overwrite
	
	; fetch the current date and time
	call get_current_date_time
	ld hl, file_accessed
	call date_time_oz_to_vdap

	; open the file for output
	ld bc, (file_buffer + 0)
	ld hl, (file_buffer + 2)
	oz (OS_Mpb)
	ex de, hl
	
	ld bc, 255
	ld hl, 0
	ld (file_handle), hl
	ld hl, local_filename
	ld a, OP_OUT
	oz (GN_Opf)
	jp c, copy_file_error
	
	ld (file_handle), ix
	
	; try to set the extent of the file
	ld a, FA_EXT
	ld hl, file_size
	oz (OS_Fwm)
	jp c, copy_file_error
	
	; we're about to be very busy...
	call busy_start
	
	; ...but we're still in window #2
	ld hl, window_dialog_select
	oz (GN_Sop)
	
	; check the drive is still available
	call sync
	jp c, copy_file_drive_error
	jp nz, copy_file_drive_error
	
	; open the file for reading
	ld a, VDAP_OPR
	ld hl, filename + 1
	ld de, (file_accessed + 2) ; we only need the date
	call send_command_string_word
	jp c, copy_file_drive_error
	
	call check_prompt
	jp c, copy_file_drive_error
	jp nz, copy_file_drive_error
	
	; we can start copying now!
	
	ld hl, (file_size + 0)
	ld de, (file_size + 2)
	ld (data_remaining + 0), hl
	ld (data_remaining + 2), de
	
	ld hl, 0
	ld (data_transferred + 0), hl
	ld (data_transferred + 2), hl

	; we'll want to be able to cancel transfers with the escape key
	ld a, SC_ENA
	oz (OS_Esc)
	
	; long timeouts
	ld bc, port_timeout_long
	ld (port_timeout), bc

.copy_file_loop
	
	; show progress
	ld a, 17
	ld (cursor_x), a
	ld a, 1
	ld (cursor_y), a
	call goto_cursor
	
	call show_transfer_progress

	; get the size of the chunk to transfer
	call get_transfer_chunk_size
	jp z, copy_file_done

	; request data from the file
	ld ix, (port_handle)
	ld de, 0
	ld hl, (chunk_size)
	push hl
	ld a, VDAP_RDF
	call send_command_dword
	
	; get the buffer ready
	ld bc, (file_buffer + 0)
	ld hl, (file_buffer + 2)
	oz (OS_Mpb)
	
	pop bc
	ld ix, (port_handle)
	ex de, hl
	ld hl, 0
	
	oz (OS_Mv)
	jr c, copy_file_block_move_error
	
	call check_prompt
	jr c, copy_file_block_drive_error
	jr nz, copy_file_block_drive_error
	
	ld bc, (file_buffer + 0)
	ld hl, (file_buffer + 2)
	oz (OS_Mpb)
	
	ld ix, (file_handle)
	ld bc, (chunk_size)
	ld de, 0
	
	oz (OS_Mv)
	jr nc, copy_file_block_written
	
	push af
	; acknowledge escape
	ld a, SC_ACK
	oz (OS_Esc)
	call drive_close_file
	pop af
	jr copy_file_block_move_error
	
.copy_file_block_written
	
	; increment the data transferred counter
	call update_transfer_counters
	
	jp copy_file_loop

.copy_file_done

	call drive_close_file
	jr copy_file_exit

.copy_file_block_drive_error
	push af
	call drive_close_file
	pop af
	jr copy_file_drive_error

.copy_file_block_move_error
	push af
	; acknowledge escape
	ld a, SC_ACK
	oz (OS_Esc)
	call drive_close_file
	pop af
	jr copy_file_error

.drive_close_file
	; close the file on the drive
	ld ix, (port_handle)
	call flush_to_timeout
	ld a, VDAP_CLF
	ld hl, filename + 1
	call send_command_string
	call check_prompt
	jp flush_to_cr

.copy_file_drive_error
	ld a, RC_TIME
	jr c, copy_file_error
.copy_file_fail_error
	ld a, RC_FAIL
.copy_file_error

	; is there a partial file to delete?
	push af
	
	ld hl, (file_handle)
	ld a, h
	or l
	jr z, copy_file_error_no_partial
	
	; close the file
	call close_file_handle

	; delete the partial file
	ld hl, local_filename
	ld b, 0
	oz (GN_Del)
.copy_file_error_no_partial

	pop af
	
	; display the system error message
	oz (GN_Err)

.copy_file_exit

	; disable escape detection
	ld a, SC_DIS
	oz (OS_Esc)
	
	; default timeouts
	ld bc, port_timeout_default
	ld (port_timeout), bc
	
	; flush any remaining data
	ld ix, (port_handle)
	call flush_to_timeout

	; no longer busy
	call busy_end

	; do we need to close the file handle?
	ld hl, (file_handle)
	ld a, h
	or l
	jr z, copy_file_handle_closed
	
	call close_file_handle
	; if we had a file handle, then we must have copied a file.
	
	; update the file modified time
	
	ld hl, file_modified
	call date_time_vdap_to_oz
	
	ld bc, (file_buffer + 0)
	ld hl, (file_buffer + 2)
	oz (OS_Mpb)
	ex de, hl
	
	; open the DOR
	
	ld bc, 255
	ld hl, 0
	ld hl, local_filename
	
	ld a, OP_DOR
	oz (GN_Opf)
	jp c, copy_file_handle_closed
	
	; write the DOR record
	
	ld a, DR_WR
	ld b, DT_UPD
	ld c, 6
	ld de, oz_date_time
	oz (OS_Dor)
	
	; free the DOR
	
	ld a, DR_FRE
	oz (OS_DOR)
	
.copy_file_handle_closed
	
	; close the dialog
	ld hl, window_dialog_close
	oz (GN_Sop)
	
	jp dir_list_start

.dir_up_a_level

	call busy_start
	call grey_window

	ld hl, up_a_level
	call change_directory
	
	call busy_end
	
	; now we need to pop the last '/' from the path
	ld bc, (path + 0)
	ld hl, (path + 2)
	oz (OS_Mpb)
	
	; is the current path empty?
	ld a, (hl)
	or a
	jp z, dir_list_start
	
	; store the length of the string
	ld b, 0

.dir_up_find_path_end
	ld a, (hl)
	or a
	jr z, dir_up_found_path_end
	inc hl
	inc b
	jr dir_up_find_path_end

.dir_up_found_path_end
	dec hl
.dir_up_erase_path_end_loop
	ld a, (hl)
	ld (hl), 0
	cp '/'
	jp z, dir_list_start
	dec hl
	djnz dir_up_erase_path_end_loop
	jp dir_list_start

.send_file

	ld hl, window_dialog_begin
	oz (GN_Sop)
	ld hl, send_file_title
	oz (GN_Sop)
	ld hl, window_dialog_end
	oz (GN_Sop)
	
	; clear the default local filename
	ld c, 0
	ld hl, local_filename
	ld (hl), 0

.send_file_source_prompt_loop
	
	ld hl, send_file_prompt
	oz (GN_Sop)
	
	call enable_cursor
	
	ld a, 1
	ld b, 21	
	ld hl, local_filename
	ld de, local_filename
	oz (GN_Sip)
	
	call disable_cursor
	
	jr nc, send_file_source_prompt_ok

.send_file_source_prompt_error
	
	cp RC_QUIT
	jp z, appl_exit
	
	cp RC_SUSP
	jp z, send_file_source_prompt_loop
	
	cp RC_DRAW
	jp z, send_file
	
	ld hl, window_dialog_close
	oz (GN_Sop)
	
	cp RC_ESC
	jp z, dir_list_start
	
	jp appl_exit

.send_file_source_prompt_ok
	cp ESC
	ld a, RC_ESC
	jr z, send_file_source_prompt_error
	
	; try to open the file
	ld bc, (file_buffer + 0)
	ld hl, (file_buffer + 2)
	
	oz (OS_Mpb)
	
	ex de, hl
	ld bc, 255
	ld hl, local_filename
	ld a, OP_DOR
	
	oz (GN_Opf)
	
	jr nc, send_file_got_source_open_dor

	; error opening the file dor
	oz (GN_Err)
	
	ld hl, local_filename
	call str_len
	jp send_file_source_prompt_loop

.send_file_got_source_open_dor
	
	ld (file_handle), ix
	
	; get the modification date and time
	ld a, DR_RD
	ld b, DT_UPD
	ld c, 6
	ld de, oz_date_time
	oz (OS_Dor)
	
	ld hl, file_modified
	call date_time_oz_to_vdap
	
	; get the creation date and time
	ld a, DR_RD
	ld b, DT_CRE
	ld c, 6
	ld de, oz_date_time
	oz (OS_Dor)
	
	ld hl, file_created
	call date_time_oz_to_vdap
	
	; free the DOR handle
	ld a, DR_FRE
	oz (OS_Dor)
	
	; re-open the file for normal input
	ld bc, (file_buffer + 0)
	ld hl, (file_buffer + 2)
	
	oz (OS_Mpb)
	
	ex de, hl
	ld bc, 255
	ld hl, local_filename
	ld a, OP_IN
	
	oz (GN_Opf)
	
	jr nc, send_file_got_source_open_in

	; error opening the file for input
	oz (GN_Err)
	
	ld hl, local_filename
	call str_len
	jp send_file_source_prompt_loop

.send_file_got_source_open_in

	ld (file_handle), ix

	; get the size of the file
	ld a, FA_EXT
	ld de, 0
	oz (OS_Frm)
	
	ld (file_size + 0), bc
	ld (file_size + 2), de
	
	jr nc, send_file_got_source
	
	ld hl, local_filename
	call str_len
	jp send_file_source_prompt_loop


.send_file_got_source
	
	; copy local_filename to filename, convert to UPPERCASE, get its length, then prompt for save name
	ld hl, local_filename
	ld de, filename
	ld a, 'f'
	ld (de), a
	inc de
	ld bc, filename_length + 1
	ldir
	
	ld hl, filename + 1
	call str_to_upper
	call str_len
	
	ld hl, window_dialog_begin
	oz (GN_Sop)
	
	; show the full local filename in the title
	ld bc, (file_buffer + 0)
	ld hl, (file_buffer + 2)
	
	oz (OS_Mpb)
	
	oz (GN_Sop)
	
	ld hl, window_dialog_end
	oz (GN_Sop)

	; show sizes and dates
	call dialog_show_size_and_dates
	
	ld hl, filename + 1
	call str_len

.send_file_dest_prompt_loop
	
	ld hl, send_as_file
	oz (GN_Sop)

	call enable_cursor
	
	ld a, 1
	ld b, 21	
	ld hl, filename + 1
	ld de, filename + 1
	oz (GN_Sip)
	
	call disable_cursor
	
	jr nc, send_file_dest_prompt_ok

.send_file_dest_prompt_error
	
	cp RC_QUIT
	jp z, appl_exit
	
	cp RC_SUSP
	jp z, send_file_dest_prompt_loop
	
	cp RC_DRAW
	jp z, send_file_got_source
	
	ld hl, window_dialog_close
	oz (GN_Sop)
	
	cp RC_ESC
	jp nz, appl_exit

.send_file_exit
	
	call close_file_handle
	
	ld hl, window_dialog_close
	oz (GN_Sop)
	
	ld ix, (port_handle)
	jp dir_list_start

.send_file_dest_prompt_ok
	
	cp ESC
	ld a, RC_ESC
	jr z, send_file_dest_prompt_error
	
	; validate the filename
	ld hl, filename + 1
	call validate_filename
	
	jr nc, send_file_dest_filename_ok
	oz (GN_Err)
	
	jp send_file_dest_prompt_loop

.send_file_dest_filename_ok
	
	; does the file already exit?
	ld hl, filename + 1
	call check_file_exists
	
	jr nc, send_file_check_overwrite
	
	; error getting file details
	jr send_file_exit

.send_file_check_overwrite
	
	jr nz, send_file_can_overwrite
	
	; prompt for overwrite
	
	; overwrite prompt
	ld hl, overwrite
	oz (GN_Sop)
	
	ld hl, filename + 1
	oz (GN_Sop)
	
	call get_cursor
	
	ld a, 11
	ld (cursor_x), a
	call goto_cursor
	
	ld a, 'N'
	call confirm
	jp c, appl_exit
	
	cp ESC
	jp z, send_file_exit
	
	cp 'Y'
	jr z, send_file_can_overwrite
	
	jp send_file_got_source

.send_file_can_overwrite

	; open the file on the drive for writing
	ld a, VDAP_OPW
	ld hl, filename + 1
	
	ld bc, (file_modified + 2) ; date
	ld de, (file_modified + 0) ; time
	
	call send_command_string_dword
	
	call check_prompt_or_error
	jp nz, send_file_error
	
	; seek back to the start of the file
	
	ld a, VDAP_SEK
	ld hl, 0
	ld de, 0
	call send_command_dword
	
	call check_prompt_or_error
	jp nz, send_file_error
	
	; recover the size of the local file
	ld ix, (file_handle)
	ld a, FA_EXT
	ld de, 0
	oz (OS_Frm)
	
	ld (file_size + 0), bc
	ld (file_size + 2), de
	
	ld (data_remaining + 0), bc
	ld (data_remaining + 2), de
	
	ld hl, 0
	ld (data_transferred + 0), hl
	ld (data_transferred + 2), hl

	; we'll want to be able to cancel transfers with the escape key
	ld a, SC_ENA
	oz (OS_Esc)
	
	; long timeouts
	ld bc, port_timeout_long
	ld (port_timeout), bc
	
	; we're about to be very busy...
	call busy_start
	
	; ...but we're still in window #2
	ld hl, window_dialog_select
	oz (GN_Sop)

.send_file_loop
	
	; show progress
	ld a, 17
	ld (cursor_x), a
	ld a, 1
	ld (cursor_y), a
	call goto_cursor
	
	call show_transfer_progress
	
	ld ix, (file_handle)

	call get_transfer_chunk_size
	jp z, send_file_done
	
	; read data from the local file
	ld bc, (file_buffer + 0)
	ld hl, (file_buffer + 2)
	oz (OS_Mpb)
	
	ex de, hl
	ld hl, 0
	ld bc, (chunk_size)
	
	oz (OS_Mv)
	jp c, send_file_error
	
	; send it to the connected drive
	ld ix, (port_handle)
	
	ld de, 0
	ld hl, (chunk_size)
	push hl
	ld a, VDAP_WRF
	call send_command_dword
	
	; get the buffer ready
	ld bc, (file_buffer + 0)
	ld hl, (file_buffer + 2)
	oz (OS_Mpb)
	
	pop bc
	ld ix, (port_handle)
	ld de, 0
	
	oz (OS_Mv)
	jp c, send_file_error
	
	ld a, SC_BIT
	oz (OS_Esc)
	ld a, RC_ESC
	jr c, send_file_error
	
	call check_prompt_or_error
	jr nz, send_file_error
	
	call update_transfer_counters
	
	jp send_file_loop

.send_file_done
	
	call busy_end
	
	; disable escape detection
	ld a, SC_DIS
	oz (OS_Esc)
	
	; default timeouts
	ld bc, port_timeout_default
	ld (port_timeout), bc
	
	ld ix, (port_handle)
	ld hl, filename + 1
	ld a, VDAP_CLF
	call send_command_string
	
	call check_prompt_or_error
	jr nz, send_file_error
	
	; did we successfully add the new file?
	ld hl, filename + 1
	call check_file_exists
	
	ld a, RC_TIME
	jr c, send_file_open_error
	jr z, send_file_succeeded
	
	; file not found
	ld a, RC_ONF
	oz (GN_Err)
	
	ld hl, window_dialog_close
	oz (GN_Sop)
	jp dir_list_start_from_current

.send_file_succeeded

	call close_file_handle
	
	call dir_add_filename
	ld de, (dir_working)
	ld (dir_selected), de
	
	; redraw
	ld hl, window_dialog_close
	oz (GN_Sop)
	jp dir_list_start

.send_file_error
	push af

	; acknowledge escape
	ld a, SC_ACK
	oz (OS_Esc)
	
	; disable escape detection
	ld a, SC_DIS
	oz (OS_Esc)

	; close the open file	
	ld ix, (port_handle)
	call flush_to_timeout
	call sync
	ld hl, filename + 1
	ld a, VDAP_CLF
	call send_command_string
	call check_prompt
	call flush_to_cr
	pop af

.send_file_open_error
	push af
	call busy_end
	pop af
	
	oz (GN_Err)
	jp send_file_exit

.rename_file

	; we can't do anything if we don't have any files
	ld hl, (dir_count)
	ld a, l
	or h
	jp z, key_loop
	
	; copy the selected (old) filename from the directory listing
	ld de, (dir_selected)
	call dir_set_index
	
	ld bc, 4
	add hl, bc
	
	ld de, filename
	ld bc, filename_length + 2
	ldir
	
	; initalise the new file name
	ld hl, filename + 1
	ld de, local_filename
	ld bc, filename_length + 1
	ldir
	
	; display the dialog
	ld hl, window_dialog_begin
	oz (GN_Sop)
	
	ld hl, rename_title
	oz (GN_Sop)
	
	ld hl, window_dialog_end
	oz (GN_Sop)
	
	; show the old file name
	ld hl, rename_prompt_old
	oz (GN_Sop)
	
	ld hl, filename + 1
	oz (GN_Sop)

.rename_file_prompt_loop_end
	
	ld hl, local_filename
	call str_len

.rename_file_prompt_loop

	; prompt for the new file name
	ld hl, rename_prompt_new
	oz (GN_Sop)
	
	call enable_cursor

	ld a, 1
	ld b, 21	
	ld de, local_filename
	oz (GN_Sip)
	
	call disable_cursor
	
	jr nc, rename_file_prompt_ok

.rename_file_prompt_error
	
	cp RC_QUIT
	jp z, appl_exit
	
	cp RC_SUSP
	jp z, rename_file_prompt_loop
	
	cp RC_DRAW
	jp z, rename_file
	
	cp RC_ESC
	jp z, rename_file_exit
	
	jp appl_exit

.rename_file_prompt_ok
	cp ESC
	ld a, RC_ESC
	jr z, rename_file_prompt_error
	
	; ensure the new name is uppercase
	ld hl, local_filename
	call str_to_upper
	
	; has the file name changed?
	ld hl, filename + 1
	ld de, local_filename
	
	call str_cmp
	jp z, rename_file_exit
	
	; is the new name valid?
	ld hl, local_filename
	call validate_filename
	
	jr nc, rename_file_new_name_ok
	
	oz (GN_Err)
	
	jr rename_file_prompt_loop_end

.rename_file_new_name_ok

	; does the new name already exist?
	call check_file_exists
	
	; error getting file details
	ld a, RC_TIME
	jr c, rename_file_error
	
	jr nz, rename_file_not_duplicate
	
	; file already exists!
	; VDAP firmware allows you to create two files
	; with the same name this way, so try to prevent that
	ld a, RC_EXIS
	oz (GN_Err)
	
	jr rename_file_prompt_loop_end

.rename_file_not_duplicate
	
	ld hl, filename + 1
	ld de, local_filename
	ld a, VDAP_REN
	call send_command_string_string
	
	ld a, RC_TIME
	jr c, rename_file_error_after_rename
	
	call check_prompt_or_error
	jr c, rename_file_error_after_rename
	
	; does the new file exist?
	ld hl, local_filename
	call check_file_exists
	
	ld a, RC_TIME
	jr c, rename_file_error_after_rename
	
	ld a, RC_ONF
	jr nz, rename_file_error_after_rename
	
	; we're OK!
	
	; remove the old directory entry
	ld de, (dir_selected)
	call dir_remove_index
	
	; add the new one
	ld hl, local_filename
	ld de, filename + 1
	ld bc, filename_length + 1
	ldir
	
	call dir_add_filename
	ld de, (dir_working)
	ld (dir_selected), de
	
	; redraw
	ld hl, window_dialog_close
	oz (GN_Sop)
	jp dir_list_start

.rename_file_error
	
	oz (GN_Err)
	call flush_to_timeout

.rename_file_exit
	ld hl, window_dialog_close
	oz (GN_Sop)
	jp dir_list_start

.rename_file_error_after_rename

	oz (GN_Err)
	call flush_to_timeout

.rename_file_exit_after_rename
	
	ld hl, window_dialog_close
	oz (GN_Sop)
	jp dir_list_start_from_current

.delete_file

	; we can't do anything if we don't have any files
	ld hl, (dir_count)
	ld a, l
	or h
	jp z, key_loop

	ld de, (dir_selected)
	call dir_set_index
	
	ld de, 4
	add hl, de
	
	ld de, filename
	ld bc, filename_length + 2
	ldir
	
	ld hl, filename + 1
	call get_file_info
	
	jr nc, delete_show_dialog
	
	ld a, RC_TIME
	oz (GN_Err)
	jp dir_list_start


.delete_show_dialog

	ld hl, window_dialog_begin
	oz (GN_Sop)
	ld hl, delete_title
	oz (GN_Sop)
	ld hl, window_dialog_end
	oz (GN_Sop)
	
	; show size (if a file) and dates
	ld a, (filename)
	cp 'f'
	push af
	call z, dialog_show_size_and_dates
	pop af
	call nz, dialog_show_dates
	
	; prompt for deletion
	ld hl, delete_prompt
	oz (GN_Sop)
	
	ld a, 'N'
	call confirm
	
	jp c, appl_exit
	
	cp 'Y'
	jp nz, delete_file_exit
	
	; delete the file/directory
	ld a, (filename)
	add a, VDAP_DLF - 'f' ; DLF = $07, DLD = $05 - perfect!
	
	ld hl, filename + 1
	
	call send_command_string_string
	jr c, delete_comm_error
	
	; check for success or failure
	call check_prompt_or_error
	jr c, delete_comm_error
	
	jr z, delete_successful
	
	oz (GN_Err)
	jr delete_file_exit

.delete_successful

	call flush_to_timeout
	ld de, (dir_selected)
	call dir_remove_index
	
	ld hl, (dir_selected)
	ld de, (dir_count)
	or a
	sbc hl, de
	
	jr c, delete_file_exit
	
	dec de
	ld (dir_selected), de
	

.delete_file_exit
	ld hl, window_dialog_close
	oz (GN_Sop)
	jp dir_list_start

.delete_comm_error
	call flush_to_timeout
	
	ld a, RC_TIME
	oz (GN_Err)
	
	ld hl, window_dialog_close
	oz (GN_Sop)
	
	; we're not sure what happened here so restart from scratch
	jp dir_list_start_from_current

.create_dir
	
	; we can't do anything if we don't have a disk in the drive
	ld a, (has_disk)
	or a
	jp z, key_loop
	
	; start with a blank filename
	ld a, 'd'
	ld (filename + 0), a
	xor a
	ld (filename + 1), a

.create_dir_show_dialog

	; display the dialog
	ld hl, window_dialog_begin
	oz (GN_Sop)
	
	ld hl, create_dir_title
	oz (GN_Sop)
	
	ld hl, window_dialog_end
	oz (GN_Sop)
	
.create_dir_prompt_loop_end
	
	ld hl, filename + 1
	call str_len

.create_dir_prompt_loop

	; prompt for the new directory name
	ld hl, create_dir_prompt
	oz (GN_Sop)
	
	call enable_cursor

	ld a, 1
	ld b, 21	
	ld de, filename + 1
	oz (GN_Sip)
	
	call disable_cursor
	
	jr nc, create_dir_prompt_ok

.create_dir_prompt_error
	
	cp RC_QUIT
	jp z, appl_exit
	
	cp RC_SUSP
	jp z, create_dir_prompt_loop
	
	cp RC_DRAW
	jp z, create_dir_show_dialog
	
	cp RC_ESC
	jp z, create_dir_exit
	
	jp appl_exit

.create_dir_prompt_ok
	cp ESC
	ld a, RC_ESC
	jr z, create_dir_prompt_error
	
	; ensure the new name is uppercase
	ld hl, filename + 1
	call str_to_upper
	
	; is the new name valid?
	call validate_filename
	
	jr nc, create_dir_new_name_ok
	
	oz (GN_Err)
	
	jr create_dir_prompt_loop_end

.create_dir_new_name_ok

	; does the new name already exist?
	call check_file_exists
	
	; error getting file details
	ld a, RC_TIME
	jr c, create_dir_error
	
	jr nz, create_dir_not_duplicate
	
	; directory already exists.
	ld a, RC_EXIS
	oz (GN_Err)
	
	jr create_dir_prompt_loop_end
	
.create_dir_not_duplicate

	; get the current date and time
	call get_current_date_time

	; store in the "file created" vcariable in VDAP format
	ld hl, file_created
	call date_time_oz_to_vdap

	; send the command to create the directory
	ld a, VDAP_MKD
	ld hl, filename + 1
	ld bc, (file_created + 2) ; date
	ld de, (file_created + 0) ; time
	call send_command_string_dword
	
	ld a, RC_TIME
	jr c, create_dir_error_after_create
	
	call check_prompt_or_error
	jr c, create_dir_error_after_create
	
	; does the new directory exist?
	ld hl, filename + 1
	call check_file_exists
	
	ld a, RC_TIME
	jr c, create_dir_error_after_create
	
	ld a, RC_ONF
	jr nz, create_dir_error_after_create
	
	; we're OK!
	
	; add the new directory entry
	call dir_add_filename
	ld de, (dir_working)
	ld (dir_selected), de
	
	; redraw
	ld hl, window_dialog_close
	oz (GN_Sop)
	jp dir_list_start

.create_dir_error
	
	oz (GN_Err)
	call flush_to_timeout

.create_dir_exit
	ld hl, window_dialog_close
	oz (GN_Sop)
	jp dir_list_start

.create_dir_error_after_create

	oz (GN_Err)
	call flush_to_timeout

.create_dir_exit_after_create
	
	ld hl, window_dialog_close
	oz (GN_Sop)
	jp dir_list_start_from_current

.appl_exit

	; make sure we're not still busy
	call busy_end

	; de-initialise the drive
	call drive_deinit
	
	; free directory resources
	call dir_free
	
	; free file transfer buffer
	ld bc, (file_buffer + 0)
	ld hl, (file_buffer + 2)
	ld a, b
	or c
	or h
	or l
	jr z, file_buffer_not_allocated
	
	ld ix, (memory_pool)
	ld a, b
	ld bc, 256
	oz (OS_Mfr)

.file_buffer_not_allocated
	
	; free path variable
	ld bc, (path + 0)
	ld hl, (path + 2)
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

	; close any open file handles
	call close_file_handle

	; close the open screen handle
	call close_screen_handle

	; close the open port handle
	call close_port_handle
	
	; free memory pool
	ld ix, (memory_pool)
	oz (OS_Mcl)

	; purge keyboard buffer
	oz (OS_Pur)
	
	; restore original panel settings
	ld a, (old_pa_txb_size)
	ld bc, PA_Txb
	ld hl, old_pa_txb
	oz (OS_Sp)
	
	ld a, (old_pa_rxb_size)
	ld bc, PA_Rxb
	ld hl, old_pa_rxb
	oz (OS_Sp)
	
	ld a, 1
	ld bc, PA_Xon
	ld hl, old_pa_xon
	oz (OS_Sp)
	
	ld a, 1
	ld bc, PA_Par
	ld hl, old_pa_par
	oz (OS_Sp)
	
	; soft-reset the serial port
	ld l, SI_SFT
	oz (OS_Si)
	
	; quit popdown with no error
	xor a
	oz (OS_Bye)

.close_port_handle
	push hl
	ld hl, port_handle
	jr close_handle
	
.close_screen_handle
	push hl
	ld hl, screen_handle
	jr close_handle
	
.close_file_handle
	push hl
	ld hl, file_handle
	; fall-through

.close_handle
	push ix
	push de
	push hl
	
	ld e, (hl)
	inc hl
	ld d, (hl)
	
	ld a, d
	or e
	jr z, handle_not_opened
	
	push de
	pop ix
	
	oz (GN_Cl)
	
	pop hl
	push hl
	
	ld (hl), 0
	inc hl
	ld (hl), 0
	dec hl

.handle_not_opened
	pop hl
	pop de
	pop ix
	
	pop hl
	ret

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
	
	; open the serial port from its name
	ld bc, filename_length
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
	ld bc, port_timeout_default
	ld (port_timeout), bc
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
	jp close_port_handle

.screen_name
	defm ":SCR.0", 0

.port_name
	defm ":COM.0", 0

.sync	
	ld ix, (port_handle)
	ld b, 4
.sync_attempt_loop
	push bc
	call sync_attempt
	pop bc
	ret c
	ret z
	djnz sync_attempt_loop
	ret

.sync_attempt

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
	call send_command_string_start
	ret c
	jr send_cr

.send_command_string_start
	call send_byte
	ret c

.send_command_string_space
	
	ld a, ' '		
	call send_byte
	ret c

.send_command_string_loop
	
	ld a, (hl)
	or a
	ret z
	cp CR
	ret z
	
	inc hl
	call send_byte
	ret c
	jr send_command_string_loop

; send a command string and a word argument
; in:  a = command to send
;      hl = pointer to string argument to send (NUL or CR terminated)
;      de = word value to send
; out: Fc = 0 on success, Fc = 1 on timeout
.send_command_string_word
	call send_command_string_start
	ret c
	
	ld a, ' '		
	call send_byte
	ret c
	
	ld a, d
	call send_byte
	ret c
	
	ld a, e
	call send_byte
	ret c
	
	jr send_cr

; send a command string and a dword argument
; in:  a = command to send
;      hl = pointer to string argument to send (NUL or CR terminated)
;      bcde = dword value to send
; out: Fc = 0 on success, Fc = 1 on timeout
.send_command_string_dword
	push bc
	call send_command_string_start
	pop hl
	ret c
	
	ld a, ' '		
	call send_byte
	ret c

	ld a, h
	call send_byte
	ret c
	
	ld a, l
	call send_byte
	ret c
	
	ld a, d
	call send_byte
	ret c
	
	ld a, e
	call send_byte
	ret c
	
	jr send_cr

; send a command string and a dword argument
; in:  a = command to send
;      hl = pointer to first string argument to send (NUL or CR terminated)
;      de = pointer to second string argument to send (NUL or CR terminated)
; out: Fc = 0 on success, Fc = 1 on timeout
.send_command_string_string
	
	call send_command_string_start	
	ret c
	
	ex de, hl
	call send_command_string_space
	ret c
	
	jr send_cr

; send a command dword
; in:  a = command to send
;      dehl = dword argument to send
; out: Fc = 0 on success, Fc = 1 on timeout
.send_command_dword
	call send_byte
	ret c
	
	ld a, ' '		
	call send_byte
	ret c
	
	ld a, d
	call send_byte
	ret c
	
	ld a, e
	call send_byte
	ret c
	
	ld a, h
	call send_byte
	ret c
	
	ld a, l
	call send_byte
	ret c
	
	ld a, CR
	jp send_byte

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
	jp flush_to_cr

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

; checks for a prompt or an error message
; in:  a = command response to check for
; out: Fc = 1 on timeout
;      Fz = 0 on success, 1 on error
;      a = RC_? error code
.check_prompt_or_error
	
	call get_byte
	ld e, a
	jr c, check_prompt_error_timeout
	
	; flush any leading CR
	cp CR
	jr z, check_prompt_or_error
	
	cp '>'
	jr z, check_prompt_or_error_prompt
	
	call get_byte
	ld d, a
	jr c, check_prompt_error_timeout
	
	ld a, CR
	call check_byte
	jr c, check_prompt_error_timeout
	
	push hl
	
	ld hl, check_prompt_error_codes
	ld b, [ check_prompt_error_codes_end - check_prompt_error_codes ] / 3

.check_prompt_check_error_code
	
	ld a, (hl)
	inc hl
	cp e
	jr nz, check_prompt_check_error_code_not_b1
	
	ld a, (hl)
	inc hl
	cp d
	jr nz, check_prompt_check_error_code_not_b2
	
	jr check_prompt_found_error

.check_prompt_check_error_code_not_b1
	inc hl
.check_prompt_check_error_code_not_b2
	inc hl
	
	djnz check_prompt_check_error_code
	pop hl
	
	jr check_prompt_unknown_error

.check_prompt_found_error
	ld a, (hl)
	pop hl
	or a
	scf
	jr flush_to_cr

.check_prompt_unknown_error
	; unknown error
	scf
	ccf
	ld a, RC_FAIL
	jr flush_to_cr

.check_prompt_or_error_prompt
	ld a, CR
	call check_byte
	jr c, check_prompt_error_timeout
	ld a, RC_SNTX
	ret

.check_prompt_error_timeout
	ld a, RC_TIME
	or a
	scf
	ret

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

; flush the input until timeout
.flush_to_timeout
	push af
.flush_to_timeout_loop
	call get_byte
	jr c, flush_to_timeout_timeout
	jr flush_to_timeout_loop
.flush_to_timeout_timeout
	pop af
	ret

.check_prompt_error_codes
	defm "BC", RC_SNTX ; BC = Bad Command
	defm "CF", RC_FAIL ; CF = Command Failed
	defm "DF", RC_ROOM ; DF = Disk Full
	defm "FI", RC_FAIL ; FI = Invalid
	defm "FN", RC_IVF  ; FN = Filename Invalid
	defm "FO", RC_USE  ; FO = File Open
	defm "RO", RC_WP   ; RO = Read Only
	defm "ND", RC_USE  ; ND = No Disk
	defm "NE", RC_USE  ; NE = Not Empty
	defm "NU", RC_ONF  ; NU = No Upgrade
.check_prompt_error_codes_end

.send_byte
	ld bc, (port_timeout)
.send_byte_timeout
	oz (OS_Pbt)
	ret

.get_byte
	ld bc, (port_timeout)
.get_byte_timeout
	oz (OS_Gbt)
	ret

; frees memory allocated for directory listing operations
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

; gets the current directory listing
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
	
	call dir_add_filename

	; fetch next filename
	jp dir_loop

.dir_end
	
	call dir_reset_index
	
	call flush_to_cr
	
	xor a
	ret


; adds (filename) to the directory listing
.dir_add_filename
	
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
	ld de, 0
	ld (dir_working), de
	
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
	ld de, (dir_working)
	inc de
	ld (dir_working), de
	
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
	
	ret

; remove the directory entry at a specific index
.dir_remove_index
	
	; what comes after the current node?
	push de
	call dir_set_index
	pop de
	
	ld c, (hl)
	inc hl
	ld b, (hl)
	inc hl
	
	ld (dir_list_new + 0), bc
	
	ld c, (hl)
	inc hl
	ld b, (hl)
	inc hl
	
	ld (dir_list_new + 2), bc
	
	ld bc, -4
	add hl, bc
	
	; hl -> current entry's memory
	
	; free the memory
	ld ix, (memory_pool)
	ld a, (dir_list_ptr + 1)
	ld bc, 32
	oz (OS_Mfr)
	
	ld a, d
	or e
	jr z, dir_remove_head

	; we're not removing the head, so work back to the previous entry
	dec de
	call dir_set_index
	
	; store the new pointer as the next pointer of the previous entry
	ld bc, (dir_list_new + 0)
	
	ld (hl), c
	inc hl
	ld (hl), b
	inc hl
	
	ld bc, (dir_list_new + 2)
	ld (hl), c
	inc hl
	ld (hl), b
	inc hl
	
	ld bc, (dir_list_new + 0)
	ld hl, (dir_list_new + 2)
	
	jr dir_removed_entry

.dir_remove_head

	; point the head directly at the node that followed the old head
	ld bc, (dir_list_new + 0)
	ld hl, (dir_list_new + 2)
	
	ld (dir_list + 0), bc
	ld (dir_list + 2), hl

.dir_removed_entry
	
	; update the current pointer
	ld (dir_list_ptr + 0), bc
	ld (dir_list_ptr + 2), hl
	
	; update the directory item count
	ld de, (dir_count)
	dec de
	ld (dir_count), de

	ret

; resets the directory listing index to the first item
.dir_reset_index
	ld de, 0
	; fall-through to dir_set_index
	
; sets the directory listing index to a specific value
; in:  de = desired index
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

; advances the directory listing pointer to the next item
; out: Fz = 1 if we're at the end of the list
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

; changes the current directory and fetches a new directory listing
; in:  hl = pointer to directory name
.change_directory
	
	push hl
	call dir_free
	call sync
	pop hl
	
	ret c
	ret nz
	
	ld de, 0
	ld (dir_offset), de
	ld (dir_selected), de

	; only change directory if we have a disk
	ld a, (has_disk)
	or a
	ret z
	
	ld a, VDAP_CD
	call send_command_string
	ret c
	
	jp dir


; checks if a file exists
; in:  hl = pointer to filename
.check_file_exists

	push hl
	call sync
	pop hl
	
	ret c
	ret nz
	
	; get the file size
	
	ld a, VDAP_DIR
	push hl
	call send_command_string
	pop hl
	
	; now we should get the original filename followed by a space
	call get_byte
	jp c, check_file_exists_comm_error
	cp CR
	jr nz, check_file_exists_space_skip_cr
	
.check_file_exists_space
	call get_byte
	jp c, check_file_exists_comm_error
.check_file_exists_space_skip_cr
	cp ' '
	jr z, check_file_exists_got_name
	cp (hl)
	inc hl
	jp nz, check_file_exists_fn_error
	jr check_file_exists_space

.check_file_exists_got_name
	
	; next four bytes are the file size
	ld b, 4

.check_file_exists_size_loop
	push bc
	call get_byte
	pop bc
	ret c
	djnz check_file_exists_size_loop
	
	ld a, CR
	call check_byte
	ret c
	jp nz, flush_to_cr
	
	call check_prompt
	ret c
	jp flush_to_cr

.check_file_exists_fn_error
	; error is filename related (e.g. bad name)
	xor a
	inc a
	; fall-through
	
.check_file_exists_comm_error
	; error is communications-related (e.g. drive timed out)
	push af
	call flush_to_timeout
	pop af
	ret

; gets information about a file
; in:  hl = pointer to filename
.get_file_info

	ld de, file_size

	push hl
	push de
	
	; clear the file size and modification fields
	ld hl, file_size
	ld de, file_size + 1
	ld bc, 11
	ld (hl), 0
	ldir
	
	call sync
		
	pop de
	pop hl
	
	ret c
	ret nz
	
	; get the file size
	
	ld a, VDAP_DIR
	push hl
	call send_command_string
	pop hl
	
	; now we should get the original filename followed by a space
	push hl
	call get_byte
	jp c, get_file_info_name_comm_error
	cp CR
	jr nz, get_file_info_size_space_skip_cr
	
.get_file_info_size_space
	call get_byte
	jp c, get_file_info_name_comm_error
.get_file_info_size_space_skip_cr
	cp ' '
	jr z, get_file_info_size_space_got_name
	cp (hl)
	inc hl
	jp nz, get_file_info_name_fn_error
	jr get_file_info_size_space

.get_file_info_size_space_got_name
	pop hl

	; next four bytes are the file size
	ld b, 4

.get_file_info_size_loop
	push bc
	call get_byte
	pop bc
	ret c
	ld (de), a
	inc de
	djnz get_file_info_size_loop
	
	ld a, CR
	call check_byte
	ret c
	jp nz, flush_to_cr
	
	call check_prompt
	ret c
	jp nz, flush_to_cr
	
	; flush any extra CR
	call flush_to_cr
	
	; get the file dates
	
	ld a, VDAP_DIRT
	push hl
	call send_command_string
	pop hl
	
	; now we should get the original filename followed by a space
	push hl
	
	call get_byte
	jr c, get_file_info_name_comm_error
	cp CR
	jr nz, get_file_info_date_space_skip_cr
	
.get_file_info_date_space
	call get_byte
	jr c, get_file_info_name_comm_error
.get_file_info_date_space_skip_cr
	cp ' '
	jr z, get_file_info_date_space_got_name
	cp (hl)
	inc hl
	jr nz, get_file_info_name_fn_error
	jr get_file_info_date_space

.get_file_info_date_space_got_name
	pop hl

	
	; next four bytes are the file creation date
	ld de, file_created
	ld b, 4

.get_file_info_created_loop
	push bc
	call get_byte
	pop bc
	ret c
	ld (de), a
	inc de
	djnz get_file_info_created_loop
	
	; next two bytes are the file access date
	call get_byte
	ret c
	ld (de), a
	inc de
	
	call get_byte
	ret c
	ld (de), a
	inc de
	
	xor a
	ld (de), a
	inc de
	ld (de), a
	inc de
	
	; next four bytes are the file modification date
	ld b, 4

.get_file_info_modified_loop
	push bc
	call get_byte
	pop bc
	ret c
	ld (de), a
	inc de
	djnz get_file_info_modified_loop
	
	ld a, CR
	call check_byte
	ret c
	jp nz, flush_to_cr
	
	call check_prompt
	ret c
	jp nz, flush_to_cr
	
	call flush_to_cr
	xor a
	ret

.get_file_info_name_fn_error
	; error is filename related (e.g. bad name)
	xor a
	inc a
	; fall-through
	
.get_file_info_name_comm_error
	; error is communications-related (e.g. drive timed out)
	push af
	call flush_to_timeout
	pop af
	pop hl
	ret

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

	defc EVENT_NONE            = NUL
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
	defm ">", 0,   EVENT_NONE
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
	defm SOH, "2JN"
	defb 0

.window_dialog_begin
	defm SOH, "7#1", 32 + 0, 32 + 0, 32 + dir_item_width * dir_cols + 2, 32 + 8, 128
	defm SOH, "2G+"
	defm SOH, "7#2", 32 + 24, 32 + 0, 32 + 38, 32 + 1, 128 + 1 + 2
	defm SOH, "2C2"
	defm SOH, "4+TUR"
	defm SOH, "2JC"
	defm FF
	defm SOH, "3@", 32 + 0, 32 + 0
	defb 0

.window_dialog_end
	defm SOH, "4-TUR"
	defm SOH, "2JN"
	defm SOH, "7#2", 32 + 24, 32 + 1, 32 + 38, 32 + 7, 128 + 1
	defm SOH, "2C2"
	defm SOH, "3-SC"
	defb 0

.window_dialog_select
	defm SOH, "2H2"
	defb 0

.window_dialog_close
	defm SOH, "7#1", 32 + 0, 32 + 0, 32 + dir_item_width * dir_cols + 2, 32 + 8, 128
	defm SOH, "2H1"
	defm SOH, "2G-"
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

.get_cursor

	xor a
	ld bc, NQ_WCUR
	oz (OS_Nq)
	
	ret c
	ld (cursor_x), bc
	ret

.busy_start
	push af
	push hl
	ld hl, busy_message_on
	oz (GN_Sop)
	pop hl
	pop af
	ret

.busy_end
	push af
	push hl
	ld hl, busy_message_off
	oz (GN_Sop)
	pop hl
	pop af
	ret

.busy_message_on
	defm SOH, "2H7"
	defm SOH, "3@", 32+0, 32+7
	defm SOH, "2-G"
	defm "Busy..."
	defm SOH, "2H1"
	defb 0

.busy_message_off
	defm SOH, "2H7"
	defm SOH, "3@", 32+0, 32+7
	defm SOH, "2+G"
	defm "       "
	defm SOH, "2H1"
	defb 0

.grey_window
	push af
	push hl
	ld hl, grey_window_on
	oz (GN_Sop)
	pop hl
	pop af
	ret

.ungrey_window
	push af
	push hl
	ld hl, grey_window_off
	oz (GN_Sop)
	pop hl
	pop af
	ret

.grey_window_on
	defm SOH, "2G+"
	defb 0

.grey_window_off
	defm SOH, "2G-"
	defb 0

.enable_cursor
	push af
	push hl
	ld hl, cursor_on
	oz (GN_Sop)
	pop hl
	pop af
	ret

.disable_cursor
	push af
	push hl
	ld hl, cursor_off
	oz (GN_Sop)
	pop hl
	pop af
	ret

.cursor_on
	defm SOH, "2+C", 0

.cursor_off
	defm SOH, "2-C", 0

.connecting
	defm "Connecting to drive...", 0

.ok
	defm "OK", 0
.yes
	defm "Yes", 0
.no
	defm "No", 0

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

.prop_size
	defm SOH, "3@", 32 + 1, 32 + 1
	defm "Size (bytes)  : ", 0
.prop_modified
	defm SOH, "3@", 32 + 1, 32 + 2
	defm "Date modified : ", 0
.prop_created
	defm SOH, "3@", 32 + 1, 32 + 3
	defm "Date created  : ", 0

.save_as_file
	defm SOH, "3@", 32 + 1, 32 + 5
	defm "Save as file  : "
	defm SOH, "2C", 254
	defb 0

.overwrite
	defm SOH, "3@", 32 + 1, 32 + 5
	defm "Overwrite     : "
	defm SOH, "2C", 254
	defb 0

.send_file_title
	defm "Send file", 0

.send_file_prompt
	defm SOH, "3@", 32 + 1, 32 + 1
	defm "Filename      : "
	defm SOH, "2C", 254
	defb 0

.send_as_file
	defm SOH, "3@", 32 + 1, 32 + 5
	defm "Send as file  : "
	defm SOH, "2C", 254
	defb 0

.rename_title
	defm "Rename", 0

.rename_prompt_old
	defm SOH, "3@", 32 + 1, 32 + 1
	defm "Name          : "
	defb 0

.rename_prompt_new
	defm SOH, "3@", 32 + 1, 32 + 3
	defm "New name      : "
	defm SOH, "2C", 254
	defb 0

.delete_title
	defm "Erase", 0

.delete_prompt
	defm SOH, "3@", 32 + 1, 32 + 5
	defm "Erase         : "
	defm SOH, "2C", 254
	defb 0

.create_dir_title
	defm "Create Directory", 0

.create_dir_prompt
	defm SOH, "3@", 32 + 1, 32 + 1
	defm "Directory name: "
	defb 0

.dialog_show_size_and_dates
	
	push ix
	; show file size
	ld hl, prop_size
	oz (GN_Sop)
	
	ld hl, file_size
	ld de, 0
	ld ix, (screen_handle)
	xor a
	
	oz (GN_Pdn)
	pop ix
	
.dialog_show_dates
	
	; show file date modified
	ld hl, prop_modified
	oz (GN_Sop)
	
	ld hl, file_modified
	call print_vdap_date_time
	
	; show file date created
	ld hl, prop_created
	oz (GN_Sop)
	
	ld hl, file_created
	call print_vdap_date_time
	
	ret

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

.str_len
	push hl
	push af
	ld bc, -1
	call str_len_loop
	pop af
	pop hl
	ret

.str_len_loop
	ld a, (hl)
	inc hl
	inc bc
	or a
	jr nz, str_len_loop
	ret

.str_to_upper
	push hl
	push af
	call str_to_upper_loop
	pop af
	pop hl
	ret

.str_to_upper_loop
	ld a, (hl)
	or a
	ret z
	
	call char_to_upper
	ld (hl), a
	inc hl
	jr str_to_upper_loop

.char_to_upper
	cp 'a'
	ret c
	cp 'z' + 1
	ret nc
	add a, 'A' - 'a'
	ret


; 5.3.1 Valid Characters
; Filenames generated using the VNC1L monitor must be uppercase letters and numbers or one
; of the following characters:
; $ % ' - _ @ ~ ` ! ( ) { } ^ # &
.validate_filename
	call str_to_upper
	push hl
	push bc
	call validate_filename_loop
	pop bc
	pop hl
	ld a, RC_IVF
	ret c
	xor a
	ret

.validate_filename_loop
	
	ld bc, [8 + 1] * 256

.validate_filename_first_part_loop
	
	ld a, (hl)
	or a
	jr z, validate_filename_check_empty
	
	cp '.'
	jr z, validate_filename_got_dot
	
	call validate_filename_char
	ret c
	
	ld (hl), a
	inc hl
	
	inc c
	djnz validate_filename_first_part_loop
	
	; too long
	scf
	ret
	

.validate_filename_got_dot
	
	ld a, c
	or a
	jr nz, validate_filename_first_part_not_empty
	
	scf
	ret

.validate_filename_first_part_not_empty

	inc hl
	ld bc, [3 + 1] * 256

.validate_filename_extension_loop
	ld a, (hl)
	or a
	ret z
	jr z, validate_filename_check_empty
	
	call validate_filename_char
	ret c
	
	ld (hl), a
	inc hl
	
	inc c
	djnz validate_filename_extension_loop
	
	; too long
	scf
	ret

.validate_filename_check_empty
	ld a, c
	or a
	ret nz
	scf
	ret

.validate_filename_char
	; all characters from NUL..SP are illegal
	cp '!'
	ret c
	
	; characters from DEL and above are illegal
	cp DEL
	ccf
	ret c
	
	; is the character a number?
	cp '0'
	jr c, validate_filename_not_numeric
	cp '9' + 1
	jr nc, validate_filename_not_numeric
	
	or a
	ret

.validate_filename_not_numeric

	; is the character a letter?
	cp 'A'
	jr c, validate_filename_not_letter
	cp 'Z' + 1
	jr nc, validate_filename_not_letter
	
	or a
	ret

.validate_filename_not_letter
	
	; is it one of the permitted symbols?
	push hl
	push bc
	
	ld hl, validate_filename_symbols
	ld b, validate_filename_symbol_count
.validate_filename_symbol_loop
	cp (hl)
	jr z, validate_filename_valid_symbol
	djnz validate_filename_symbol_loop
	
	pop bc
	pop hl
	
	scf
	ret

.validate_filename_valid_symbol
	pop bc
	pop hl
	ret

.validate_filename_symbols
	defm "$%'-_@~`!(){}^#&"

.validate_filename_symbol_count equ 16

; convert a date and time from the VDAP format to the OZ format
; in:  hl = pointer to VDAP date-time to convert
; out: oz_date_time
.date_time_vdap_to_oz
	
	push ix
	
	push hl
	pop ix

	; start with the time
	
	; this is a 16-bit value, split like this:
	; HHHHHMMM MMMSSSSS
	; (seconds are halved)
	
	; set HL to seconds
	ld a, (ix + 0)
	and $1F
	add a, a
	ld l, a
	ld h, 0
	push hl
	
	; fetch minutes
	
	ld a, (ix + 1)
	and $07
	ld d, a
	ld e, (ix + 0)
	
	ld b, 5
.minute_shift
	srl d
	rr e
	djnz minute_shift
	
	; de = minutes, multiply by 60 to get seconds
	ld hl, 60
	
	oz (GN_M16)
	
	pop de
	add hl, de
	push hl
	
	; fetch hours
	ld e, (ix + 1)
	
	srl e
	srl e
	srl e
	
	ld hl, 3600
	
	ld bc, 0
	ld d, b
	
	; BHL = 3600
	; CDE = <hours>
	
	oz (GN_M24)
	
	; BHL = seconds in hours
	
	pop de
	add hl, de
	
	jr nc, added_seconds_in_hours
	inc b
.added_seconds_in_hours

	; we now have seconds in day in BHL
	
	; multiply by 100 to get centiseconds
	ld c, 0
	ld de, 100
	oz (GN_M24)
	
	ld (oz_date_time + 0), hl
	ld a, b
	ld (oz_date_time + 2), a
	
	; now convert the date
	
	; this is a 16-bit value, split like this:
	; YYYYYYYM MMMDDDDD
	; (years are offset from 1980)
	
	ld a, (ix + 2)
	and $1F
	ld c, a
	
	ld a, (ix + 3)
	and $01
	ld b, a
	
	ld a, (ix + 2)
	
	add a, a
	rl b
	add a, a
	rl b
	add a, a
	rl b
	
	ld e, (ix + 3)
	srl e
	ld d, 0
	
	ld hl, 1980
	add hl, de
	
	ex de, hl
	
	oz (GN_Dei)

	ld (oz_date_time + 3), bc
	ld (oz_date_time + 5), a

	pop ix
	ret

; convert a date and time from the OZ format to the VDAP format
; in:  oz_date_time
;      hl = pointer to VDAP date-time to convert to
.date_time_oz_to_vdap
	push ix
	
	push hl
	pop ix
	
	; start with the time
	
	; first three bytes of oz_date_time is time of day in centiseconds
	
	ld hl, (oz_date_time + 0)
	ld a, (oz_date_time + 2)
	ld b, a
	
	; 60 * 60 * 100 = 360000cs in an hour
	; 360000 = $057E40
	ld de, $7E40
	ld c, $05
	oz (GN_D24)
	
	; BHL = seconds
	ld a, l
	ld (ix + 2), a
	
	; remainder -> dividend
	ex de, hl
	ld b, c
	
	; 60 * 100 = 6000cs in a minute
	ld de, 6000
	ld c, 0
	oz (GN_D24)
	
	; BHL = minutes
	ld a, l
	ld (ix + 1), a
	
	; remainder -> dividend
	ex de, hl
	
	; 200cs in a double-second
	ld de, 200
	oz (GN_D16)
	
	; HL = double-seconds
	ld a, l
	ld (ix + 0), a
	
	; vdap time is a 16-bit value, packed like this:
	; HHHHHMMM MMMSSSSS
	; (seconds are halved)
	
	ld a, (ix + 2)
	add a, a
	add a, a
	add a, a
	ld b, a
	ld c, 0
	
	ld a, (ix + 1)
	
	srl a
	rr c
	srl a
	rr c
	srl a
	rr c
	
	or b
	ld (ix + 1), a
	
	ld a, (ix + 0)
	or c
	ld (ix + 0), a
	
	; now convert the date
	
	; fortunately there's an API call for that!
	ld bc, (oz_date_time + 3)
	ld a, (oz_date_time + 5)
	oz (GN_Die)
	
	; oz date (Y-M-D) is now in DE-B-C
	
	; vdap date is a 16-bit value, packed like this:
	; YYYYYYYM MMMDDDDD
	; (years are offset from 1980)
	
	ld a, c
	and $1F
	ld c, a
	xor a
	
	srl b
	rr a
	srl b
	rr a
	srl b
	rr a
	
	or c
	ld (ix + 2), a
	
	ld hl, -1980
	add hl, de
	
	ld a, l
	add a, a
	or b
	ld (ix + 3), a
	
	pop ix
	ret

.get_current_date_time
	
	ld de, oz_date_time + 3
	oz (GN_Gmd)
	
	ld a, (oz_date_time + 3)
	ld c, a
	
	ld de, oz_date_time + 0
	oz (GN_Gmt)
	
	jr nz, get_current_date_time ; date has changed between calls, so fetch again
	ret

.print_vdap_date_time
	push ix
	push hl
	push de
	push bc
	
	call date_time_vdap_to_oz
	
	ld ix, (screen_handle)
	ld hl, oz_date_time
	oz (GN_Sdo)
	
	pop bc
	pop de
	pop hl
	pop ix
	ret

.confirm
	
	push af
	call enable_cursor
	pop af

.confirm_loop
	ld hl, yes
	ld b, 3
	cp 'Y'
	jr z, confirm_got_symbol
	ld hl, no
	ld b, 2
.confirm_got_symbol
	
	ld c, a
	push bc
	oz (GN_Sop)
	pop bc
	
	ld a, b
	cp 3
	jr z, confirm_bs_loop
	ld a, ' '
	oz (OS_Out)
	inc b

.confirm_bs_loop
	ld a, BS
	oz (OS_Out)
	djnz confirm_bs_loop

.confirm_key_loop
	
	oz (OS_In)
	jr c, confirm_error
	
	cp 'y'
	jr z, confirm_set_y
	cp 'Y'
	jr z, confirm_set_y
	
	cp 'n'
	jr z, confirm_set_n
	cp 'n'
	jr z, confirm_set_n
	
	cp 'J' - '@' ; <>J
	jr z, confirm_toggle
	
	cp CR
	jr z, confirm_return
	
	cp ESC
	jr z, confirm_end
	
	jr confirm_key_loop

.confirm_toggle
	ld a, c
	cp 'Y'
	jr z, confirm_set_n

.confirm_set_y
	ld a, 'Y'
	jr confirm_loop
.confirm_set_n
	ld a, 'N'
	jr confirm_loop

.confirm_error

	cp RC_QUIT
	jp z, appl_exit

	cp RC_SUSP
	jr z, confirm_key_loop
	
	cp RC_DRAW
	ld c, a
	jr z, confirm_loop
	
	ld a, ESC
	jr confirm_end

.confirm_return
	or a
	ld a, c
	; fall-through to confirm_end

.confirm_end
	push af
	call disable_cursor
	pop af
	ret
	
; prints progress from data_transferred and file_size to screen
.show_transfer_progress
	ld ix, (screen_handle)
	
	ld de, 0
	ld hl, data_transferred
	xor a
	oz (GN_Pdn)
	
	ld a, '/'
	oz (OS_Out)
	
	ld de, 0
	ld hl, file_size
	xor a
	oz (GN_Pdn)
	
	ld a, ' '
	oz (OS_Out)
	ld a, '('
	oz (OS_Out)
	
	; calculate %ge
	
	ld hl, (file_size + 0)
	ld de, (file_size + 2)
	
	ld a, h
	or l
	or d
	or e
	
	ld hl, 100
	
	jr z, progress_file_is_empty
	
	ld hl, (data_transferred + 2)
	ld de, (file_size + 2)
	exx
	ld hl, (data_transferred + 0)
	ld de, (file_size + 0)
	exx
	ld bc, 0
	
	fpp (FP_DIV)
	
	ld de, 0
	exx
	ld de, 100
	exx
	ld b, 0
	
	fpp (FP_MUL)
	fpp (FP_FIX)
	
	exx
	push hl
	exx
	pop hl

.progress_file_is_empty

	ld (oz_date_time + 0), hl
	ld hl, 0
	ld (oz_date_time + 2), hl
	
	ld de, 0
	ld hl, oz_date_time
	ld ix, (screen_handle)
	xor a
	oz (GN_Pdn)
	
	ld a, '%'
	oz (OS_Out)
	ld a, ')'
	oz (OS_Out)
	ret

.get_transfer_chunk_size
	
	; how much data do we need to pull in?
	ld hl, (data_remaining + 0)
	ld de, (data_remaining + 2)
	
	; is it 0?
	ld a, h
	or l
	or d
	or e
	ret z
	
	; is it >=256 bytes?
	ld a, d
	or e
	jr nz, transfer_file_gte_256
	
	ld de, 256
	or a
	sbc hl, de
	jr nc, transfer_file_gte_256

.copy_file_lt_256
	
	; we're under 256 bytes
	ld bc, (data_remaining + 0)
	ld (chunk_size), bc
	
	ld bc, 0
	ld (data_remaining + 0), bc
	jr transfer_file_got_chunk_size

.transfer_file_gte_256
	
	; we have >= 256 bytes to go, so cap at 256
	ld bc, 256
	ld (chunk_size), bc
	
	or a
	
	ld hl, (data_remaining + 0)
	sbc hl, bc
	ld (data_remaining + 0), hl
	
	ld bc, 0
	ld hl, (data_remaining + 2)
	sbc hl, bc
	ld (data_remaining + 2), hl

.transfer_file_got_chunk_size
	xor a
	dec a
	ret

; update the data transferred counters with the latest chunk size
.update_transfer_counters
	ld hl, (data_transferred + 0)
	ld de, (chunk_size)
	add hl, de
	ld (data_transferred + 0), hl
	ld de, 0
	ld hl, (data_transferred + 2)
	adc hl, de
	ld (data_transferred + 2), hl
	ret
