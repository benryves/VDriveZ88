	module romheader

	org $3FC0

.front_dor
	defb 0,0,0           ; link to parent
	defb 0,0,0           ; no help DOR
	defw $E000           ; first application DOR
	defb $3F             ; in top bank of eprom
	defb $13             ; ROM front DOR
	defb 8               ; length
	defb 'N'
	defb 5
	defm "APPL", 0
	defb $FF

	defs 37

.eprom_header
	defw 0               ; card ID, to be filled in by loadmap
	defb @00000011       ; UK country code
	defb $80             ; external application
	defb $01             ; size of EPROM (16K)
	defb 0
	defm "OZ"
