################# CSC258 Assembly Final Project ###################
# This file contains our implementation of Dr Mario.
#
# Student 1: Yuxi Zhang, 1008791639
# Student 2: Jeha Park, 1009840415
#
# We assert that the code submitted here is entirely our own 
# creation, and will indicate otherwise when it is not.
#
######################## Bitmap Display Configuration ########################
# - Unit width in pixels:       2
# - Unit height in pixels:      2
# - Display width in pixels:    128
# - Display height in pixels:   128
# - Base Address for Display:   0x10008000 ($gp)
##############################################################################

    .data

    game_columns: .word 24               # Number of columns in the playable region
    game_rows: .word 40                  # Number of rows in the playable region
    music_data:
        .include "fever_music.asm"
    mario_bitmap:
        .include "dr_mario_virus.asm"
    pause_bitmap:
        .include "pause.asm"
    unpause_bitmap:
        .include "unpause.asm"

##############################################################################
# Immutable Data
##############################################################################
# The address of the bitmap display. Don't forget to connect it!
ADDR_DSPL: .word 0x10008000
# The address of the keyboard. Don't forget to connect it!
ADDR_KBRD: .word 0xffff0000
    display_address: .word 0x10010000  # Base address of the display (adjust as needed)
    display_width:   .word 256         # Width of the display in pixels (adjust as needed)
    white_color:     .word 0x00FFFFFF  # White color in ARGB format

##############################################################################
# Mutable Data
##############################################################################

# stored starting at address 0x10010000

# store the HEX codes for each colour as data values
red: .word 0xff3366
green: .word 0x33cc66
blue: .word 0x3399ff
black: .word 0x000000
gray: .word 0xa0a0a0

# the (x,y) coordinates of playing area on the bitmap
GAME_DSPL_X: .word 0x00000006
GAME_DSPL_Y: .word 0x00000012

# number of bytes corresponding to a full row and step of playing area
game_row: .word 0x00000064
game_step: .word 0x00000100

# allocate a block to format the bitmap properly in memory
spacer: .space 8

# allocate 24 x 40 = 960 words (960 x 4 = 3840 bytes) representing each pixel of the playing area
GAME_MEMORY_ADDR: .word 0x10009220       # address of the state of the game stored in memory
GAME_MEMORY: .space 3840                 # starts at address 0x10010040

# gravity variables 
last_gravity_time: .word 0       # Last time gravity was applied
gravity_interval:  .word 1000    # Current interval (1000ms = 1s)
base_gravity:      .word 1000    # Baseline gravity
min_gravity:       .word 100     # Minimum interval (fastest fall)
gravity_step:      .word 500     # How much to change by
gravity_paused: .word 0        # 0 = gravity active, 1 = gravity paused
gravity_speed:  .word 2       # Speed multiplier (1 = normal, 2 = fast, etc.)

clear_count: .word 0       # Counter for cleared rows/columns


level_counter:     .word 0       # Track when to increase
level_threshold:   .word 10      # Increase every 10 moves


# darker colors for viruses
dark_red: .word 0xcc0033
dark_green: .word 0x009933
dark_blue: .word 0x0066cc

# virus positioning and count
virus_count: .word 0          # number of viruses to place
virus_positions: .space 60     # space for up to 15 virus positions (each virus needs 4 bytes)

       .align 2  # Align to word boundary (4 bytes)
    difficulty: .word 0             # 1=Easy, 2=Medium, 3=Hard
    difficulty_prompt: .asciiz "Select difficulty:\n1. Easy\n2. Medium\n3. Hard\nEnter choice (1-3): "
    invalid_input_msg: .asciiz "Invalid input. Please enter 1, 2, or 3.\n"
    
    # Virus counts for each difficulty
    .align 2  # Align to word boundary (4 bytes)
    easy_viruses: .word 3
    medium_viruses: .word 6
    hard_viruses: .word 9
    
    # Gravity intervals for each difficulty (ms)
    .align 2  # Align to word boundary (4 bytes)
    easy_gravity: .word 1000
    medium_gravity: .word 700
    hard_gravity: .word 400

# Game Over Screen Constants
GAME_OVER_TEXT_X: .word 16
GAME_OVER_TEXT_Y: .word 28
RETRY_TEXT_X:     .word 18
RETRY_TEXT_Y:     .word 32
SELECTOR_X:       .word 16
SELECTOR_Y:       .word 32
RED_COLOR:        .word 0x00FF0000
WHITE_COLOR:      .word 0x00FFFFFF
BLACK_COLOR:      .word 0x00000000

# Game State Flags
game_over_flag:   .word 0
retry_selected:   .word 1  # 1 for retry, 0 for quit

is_paused: .word 0        # 0 = not paused, 1 = paused
pause_msg: .asciiz "Paused"

    .align 2  # Align to word boundary (4 bytes)
    next_capsule_x: .word 36      # x position for next capsule preview
    next_capsule_y: .word 20      # y position for next capsule preview
    next_capsule_color1: .word 0  # color of first half
    next_capsule_color2: .word 0  # color of second half
    next_capsule_orientation: .word 2  # horizontal by default
#######################################################

##############################################################################
# Notes
##############################################################################

# - finalize what each byte holds (orientation, type, ...)

##############################################################################

# Save Register Designations:
# $s0: x-coordinate of first half
# $s1: y-coordinate of second half
# $s2: capsule orientation, 1 is vertical, 2 is horizontal 
# $s3: colour of first half
# $s4: colour of second half
# $s5: 
# $s6: 
# $s7: 

##############################################################################
# Code
##############################################################################
	.text


##############################################################################
# Macros
##############################################################################

.macro get_pixel (%x, %y)
    # transforms coordinate pair (x,y) into corresponding bitmap display address and places in v0
    
    addi $sp, $sp, -8       # allocate stack space for two temporary registers
    sw $t0, 4($sp)          # preserve $t0 value
    sw $t1, 0($sp)          # preserve $t1 value
    
    move $a0, %x        # store x position
    move $a1, %y        # store y position
    
    li $t0, 256         # row offset calculation value
    li $t1, 4           # column offset calculation value

    mult $t0, $a1       # compute vertical offset (relative to the top)
    mflo $t0            # extract the result from 'lo' register
    mult $t1, $a0       # compute horizontal offset (relative to the left)
    mflo $t1            # extract the result from 'lo' register
    
    add $t0, $t0, $t1   # combine offsets
    add $t0, $t0, $gp   # calculate the address relative to the bitmap
    
    move $v0, $t0       # save the address in the return register
    
    lw $t1, 0($sp)      # restore the original $t1 value
    lw $t0, 4($sp)      # restore the original $t0 value
    addi $sp, $sp, 8    # reclaim stack space
.end_macro

.macro draw_pixel (%x, %y, %colour)
    # draws a pixel with specified colour at location (x,y) on bitmap display
    
    get_pixel (%x, %y)    # fetch the bitmap address corresponding to (x,y)
    sw %colour, 0($v0)    # write colour value to memory
.end_macro

.macro random_colour ()
    # generates a random colour out of red, green, and blue
    
    addi $sp, $sp, -16      # reserve stack space for four (more) registers
    sw $t0, 12($sp)         # preserve $t0
    sw $v0, 8($sp)          # preserve $v0
    sw $a0, 4($sp)          # preserve $a0
    sw $a1, 0($sp)          # preserve $a1
    
    li $v0, 42          # load syscall code for RANDGEN
    li $a0, 0           # set up RANGEN with generator 0
    li $a1, 3           # set the upper limit for the random number as 2
    syscall             # make the system call, returning to $a0
    
    li $t0, 0                       # load zero as the number corresponding to red
    beq $a0, $t0, select_red        # if zero, return red
    li $t0, 1                       # load one as the number corresponding to green
    beq $a0, $t0, select_green      # if one, return green
    li $t0, 2                       # load two as the number corresponding to blue
    beq $a0, $t0, select_blue       # if two, return blue
    
    select_red:              # assign red to $t3
        lw $t0, red
        j select_done
    select_green:            # assign green to $t3
        lw $t0, green
        j select_done
    select_blue:             # assign blue to $t3
        lw $t0, blue
        j select_done

    select_done: 
        move $v1, $t0     # store selected colour in return register
        
        lw $a1, 0($sp)       # preserve $a1
        lw $a0, 4($sp)       # preserve $a0
        lw $v0, 8($sp)       # preserve $v0
        lw $t0, 12($sp)      # preserve $t0
        addi $sp, $sp, 16    # reclaim stack space
.end_macro

.macro draw_square (%x, %y, %colour)
    # draws a square starting at (x,y) of the given colour
    
    move $a0, %x              # cache x-coordinate to avoid overwriting
    move $a1, %y              # cache y-coordinate to avoid overwriting
    move $a2, %colour         # cache direction to avoid overwriting
    
    addi $sp, $sp, -12      # reserve stack space for three (more) registers
    sw $t0, 8($sp)          # preserve $t0
    sw $t1, 4($sp)          # preserve $t1
    sw $t2, 0($sp)          # preserve $t2
    
    move $t0, $a0        # working copy of x-coordinate
    move $t1, $a1        # working copy of y-coordinate
    move $t2, $a2        # working copy of colour
    
    draw_pixel ($t0, $t1, $t2)      # draw the first pixel
    addi $t0, $t0, 1                # move the x-coordinate over by one (move right)
    draw_pixel ($t0, $t1, $t2)      # draw the second pixel
    addi $t1, $t1, 1                # move the y-coordinate up by one (move down)
    draw_pixel ($t0, $t1, $t2)      # draw the third pixel
    addi $t0, $t0, -1               # move the x-coordinate back by one (move left)
    draw_pixel ($t0, $t1, $t2)      # draw the fourth pixel
    
    lw $t2, 0($sp)       # restore the original $t2 value
    lw $t1, 4($sp)       # restore the original $t1 value
    lw $t0, 8($sp)       # restore the original $t0 value
    addi $sp, $sp, 12    # reclaim stack space
.end_macro


.macro draw_virus (%x, %y, %colour1, %colour2)
    # draws a square starting at (x,y) of the given colour
    
    move $a0, %x              # cache x-coordinate to avoid overwriting
    move $a1, %y              # cache y-coordinate to avoid overwriting
    move $a2, %colour1         # cache direction to avoid overwriting
    move $a3, %colour2
    
    addi $sp, $sp, -16      # reserve stack space for three (more) registers
    sw $t3, 12($sp)          # preserve $t2
    sw $t0, 8($sp)          # preserve $t0
    sw $t1, 4($sp)          # preserve $t1
    sw $t2, 0($sp)          # preserve $t2
    
    move $t0, $a0        # working copy of x-coordinate
    move $t1, $a1        # working copy of y-coordinate
    move $t2, $a2        # working copy of colour
    move $t3, $a3
    
    draw_pixel ($t0, $t1, $t2)      # draw the first pixel
    addi $t0, $t0, 1                # move the x-coordinate over by one (move right)
    draw_pixel ($t0, $t1, $t3)      # draw the second pixel
    addi $t1, $t1, 1                # move the y-coordinate up by one (move down)
    draw_pixel ($t0, $t1, $t2)      # draw the third pixel
    addi $t0, $t0, -1               # move the x-coordinate back by one (move left)
    draw_pixel ($t0, $t1, $t3)      # draw the fourth pixel
    
    lw $t2, 0($sp)       # restore the original $t2 value
    lw $t1, 4($sp)       # restore the original $t1 value
    lw $t0, 8($sp)       # restore the original $t0 value
    lw $t3, 12($sp)       # restore the original $t0 value
    addi $sp, $sp, 16    # reclaim stack space
.end_macro

.macro get_coordinates (%address)
    # given an address in the bitmap, retrieve the corresponding (x,y) coordinates
    
    move $a0, %address      # load the address into a function argument register
    
    sub $t0, $a0, $gp       # fetch offset of address from display's base address
    srl $t0, $t0, 2         # divide index by four to fetch pixel index (shift right by 2)
    li $t1, 256             # load width of the display
    div $t0, $t1            # divide the index by the width of display
    mfhi $v0                # set the x coordinate to remainder
    mflo $v1                # set the y coordinate to quotient
.end_macro

.macro move_square (%x, %y, %direction)
    # assuming no collisions, moves the square starting at (x,y) the given direction
    
    move $a0, %x                 # cache x-coordinate to avoid overwriting
    move $a1, %y                 # cache y-coordinate to avoid overwriting
    move $a2, %direction         # cache the direction to avoid overwriting
    
    addi $sp, $sp, -20      # reserve stack space for five (more) registers
    sw $t0, 16($sp)         # preserve $t0
    sw $t1, 12($sp)         # preserve $t1
    sw $t2, 8($sp)          # preserve $t2
    sw $t3, 4($sp)          # preserve $t3
    sw $t4, 0($sp)          # preserve $t4
    
    move $t0, $a0            # working copy of x-coordinate
    move $t1, $a1            # working copy of y-coordinate
    move $t2, $a2            # working copy of the direction
    
    get_pixel ($a0, $a1)        # fetch the address corresponding to the coordinate
    lw $t3, 0($v0)              # fetch the colour of the coordinate
    
    lw $t4, black                   # get background colour
    draw_square ($t0, $t1, $t4)     # "erase" square at original position
    
    beq $t2, 1, shift_left          # handle leftward movement
    beq $t2, 2, shift_right         # handle rightward movement
    beq $t2, 3, shift_up            # handle upward movement
    beq $t2, 4, shift_down          # handle downward movement
    
    shift_left:
        subi $t0, $t0, 2                    # shift the x-coordinate left by two units
        j movement_complete                 # completed, jump back
    shift_right:
        addi $t0, $t0, 2                    # shift the x-coordinate right by two units
        j movement_complete                 # completed, jump back
    shift_up:
        subi $t1, $t1, 2                    # shift the y-coordinate up by two units
        j movement_complete                 # completed, jump back
    shift_down:
        addi $t1, $t1, 2                    # shift the y-coordinate down by two units
        j movement_complete                 # completed, jump back
   
    movement_complete:
        draw_square ($t0, $t1, $t3)         # draw the square at the new coordinates with the original colour
        
        lw $t4, 0($sp)       # restore the original $t4 value
        lw $t3, 4($sp)       # restore the original $t3 value
        lw $t2, 8($sp)       # restore the original $t2 value
        lw $t1, 12($sp)      # restore the original $t1 value
        lw $t0, 16($sp)      # restore the original $t0 value
        addi $sp, $sp, 20    # reclaim stack space
.end_macro

.macro move_capsule (%direction)
    # move the current capsule the specified direction
    
    li $a0, %direction      # move the direction into a safe register to avoid overwriting
    
    addi $sp, $sp, -12      # allocate space for three (more) registers on the stack
    sw $t0, 8($sp)          # $t0 is used in this macro, save it to the stack to avoid overwriting
    sw $t1, 4($sp)          # $t1 is used in this macro, save it to the stack to avoid overwriting
    sw $t2, 0($sp)          # $t2 is used in this macro, save it to the stack to avoid overwriting
    
    move $t2, $a0                  # load the direction into a temporary register to avoid being overwritten
    
    beq $s2, 1, move_vertical_capsule          # move the second half of the vertical capsule
    beq $s2, 2, move_horizontal_capsule        # move the second half of the horizontal capsule
    
    move_vertical_capsule:
        addi $t1, $s1, 2                        # the second half is below of the first half
        move_square ($s0, $t1, $t2)             # move the capsule's second half first to avoid being overwritten
        move_square ($s0, $s1, $t2)             # move first half second, avoids overwriting the second half
        j move_capsule_done                     # return back to main
        
    move_horizontal_capsule:
        beq $t2, 1, move_horizontal_capsule_left    # if moving left, move the capsule's first half first
        
        addi $t0, $s0, 2                        # the second half is to the right of the first half
        move_square ($t0, $s1, $t2)             # move the second half first to avoid being overwritten
        move_square ($s0, $s1, $t2)             # move first half second, avoids overwriting the second half
        j move_capsule_done                     # return back to main
        
    move_horizontal_capsule_left: 
        move_square ($s0, $s1, $t2)             # move the first half first to avoid being overwritten
        addi $t0, $s0, 2                        # the second half is to the right of the first half
        move_square ($t0, $s1, $t2)             # move the second half second, avoids overwriting the first half
        j move_capsule_done                     # return back to main
 
    move_capsule_done:                  
        lw $t2, 0($sp)      # restore the original $t2 value
        lw $t1, 4($sp)      # restore the original $t1 value
        lw $t0, 8($sp)      # restore the original $t0 value
        addi $sp, $sp, 12   # reclaim stack space
.end_macro

.macro new_capsule ()
    # generates a new capsule in the mouth of the bottle using the stored next capsule info
    # then generates a new preview capsule
    
    addi $sp, $sp, -4       # allocate space for one register on the stack
    sw $t0, 0($sp)          # save $t0
    
    # Load the stored next capsule info
    lw $s3, next_capsule_color1      # first half color from memory
    li $s0, 16                      # set the x-coordinate (mouth position)
    li $s1, 16                      # set the y-coordinate (mouth position)
    draw_square ($s0, $s1, $s3)     # draw the first half
    
    lw $s4, next_capsule_color2      # second half color from memory
    lw $s2, next_capsule_orientation # orientation from memory
    
    # Draw second half based on orientation
    beq $s2, 1, draw_vertical_next
    # Horizontal orientation (default)
    li $t0, 18                      # x position for right half
    draw_square ($t0, $s1, $s4)     # draw right half
    j after_draw_next
    
    draw_vertical_next:
    li $t1, 18                      # y position for bottom half
    draw_square ($s0, $t1, $s4)     # draw bottom half
    
    after_draw_next:
    #save_info()  # save the capsule info to memory
    
    # Now generate the NEXT next capsule (preview)
    random_colour ()                # generate random color for preview first half
    sw $v1, next_capsule_color1     # store in memory
    
    random_colour ()                # generate random color for preview second half
    sw $v1, next_capsule_color2     # store in memory
    
    # Draw the preview capsule (always horizontal)
    li $s2, 2                       # horizontal orientation
    sw $s2, next_capsule_orientation # store orientation
    
    lw $t0, next_capsule_x          # preview position x
    lw $t1, next_capsule_y          # preview position y
    lw $t2, next_capsule_color1     # first half color
    draw_square ($t0, $t1, $t2)     # draw first half
    
    addi $t0, $t0, 2                # x position for right half
    lw $t2, next_capsule_color2     # second half color
    draw_square ($t0, $t1, $t2)     # draw second half
    
    lw $t0, 0($sp)       # restore $t0
    addi $sp, $sp, 4     # free stack space
.end_macro

.macro fetch_capsule_addr (%x, %y)
    # give (x,y) coordinates on the display, return the corresponding address in game memory
    
    move $a0, %x             # move the x-coordinate into a safe register
    move $a1, %y             # move the y-coordinate into a safe register
    
    addi $sp, $sp, -8           # allocate space for two (more) registers on the stack
    sw $t0, 4($sp)              # $t0 is used in this macro, save it to the stack to avoid overwriting
    sw $t1, 0($sp)              # $t1 is used in this macro, save it to the stack to avoid overwriting
    
    move $t0, $a0               # load x-coordinate into the first function argument register
    move $t1, $a1               # load y-coordinate into the second function argument register
    
    subi $t0, $t0, 6            # subtract the playing area offset from the x-coordinate
    subi $t1, $t1, 18           # subtract the playing area offset from the y-coordinate
    
    mul $t0, $t0, 4            # calculate the x-offset of the pixel (relative to the left)
    mul $t1, $t1, 96           # calculate the y-offset of the pixel (relative to the top)
    
    add $t0, $t0, $t1           # calculate the overall byte offset
 
    la $t1, GAME_MEMORY         # fetch the address of the game memory
    add $t0, $t0, $t1           # calculate the address relative to the game memory address offset
    
    move $v0, $t0               # save the address

    lw $t1, 0($sp)              # restore the original $t1 value
    lw $t0, 4($sp)              # restore the original $t0 value
    addi $sp, $sp, 8           # free space used by the two registers
.end_macro

.macro remove_info (%x, %y)
    # removes the information about a pixel at the (x,y) coordinates from the game memory
    
    move $a0, %x                        # load x-coordinate into a function argument register
    move $a1, %y                        # load y-coordinate into a function argumnet register
    
    addi $sp, $sp, -8        # allocate space for two (more) register on the stack
    sw $t0, 4($sp)           # $t0 is used in this macro, save it to the stack to avoid overwriting
    sw $t1, 0($sp)           # $t1 is used in this macro, save it to the stack to avoid overwriting
    
    fetch_capsule_addr ($a0, $a1)         # fetch the address of the pixel in memory
    sb $zero, 0($v0)                    # erase the block type
    lb $t1, 1($v0)                      # fetch the connection orientation of the block
    sb $zero, 1($v0)                    # erase the connection orientation
    
    beq $t1, 0, remove_info_done        # if not connected to anything, done
    beq $t1, 1, remove_left             # if connected on the left
    beq $t1, 2, remove_right            # if connected on the right
    beq $t1, 3, remove_up               # if connected above
    beq $t1, 4, remove_down             # if connected below
    
    remove_left:
        subi $t0, $a0, 2                    # shift the x-coordinate left by one block
        fetch_capsule_addr ($t0, $a1)         # fetch the address in memory
        j remove_info_done                  # update the second half's connection orientation
    remove_right:
        addi $t0, $a0, 2                    # shift the x-coordinate right by one block
        fetch_capsule_addr ($t0, $a1)         # fetch the address in memory
        j remove_info_done                  # update the second half's connection orientation
    remove_up:
        subi $t0, $a1, 2                    # shift the y-coordinate up by one block
        fetch_capsule_addr ($a0, $t0)         # fetch the address in memory
        j remove_info_done                  # update the second half's connection orientation
    remove_down:
        addi $t0, $a1, 2                    # shift the y-coordinate down by one block
        fetch_capsule_addr ($a0, $t0)         # fetch the address in memory
        j remove_info_done                  # update the second half's connection orientation
        
    remove_info_done:
        sb $zero, 1($v0)                    # set the other half's connection orientation to zero
       
        lw $t1, 0($sp)          # restore the original value of $t1
        lw $t0, 4($sp)          # restore the original value of $t0
        addi $sp, $sp, 8        # free space used by the register
    
.end_macro

.macro get_info (%x, %y)
    # Fetches pixel information at (x, y)
    # $v0: Block type (1 = capsule, 2 = virus)
    # $v1: Connection direction (0 = none, 1-4 = left, right, up, down)

    addi $sp, $sp, -4      # Allocate space for one register on the stack
    sw   $t0, 0($sp)       # Save $t0 to the stack

    move $a0, %x           # Load x-coordinate
    move $a1, %y           # Load y-coordinate

    fetch_capsule_addr ($a0, $a1)  # Fetch address of the pixel in memory

    move $t0, $v0          # Store pixel address temporarily
    lb   $v0, 0($t0)       # Load block type (first byte)
    lb   $v1, 1($t0)       # Load connection direction (second byte)

    lw   $t0, 0($sp)       # Restore original $t0
    addi $sp, $sp, 4       # Free allocated stack space
.end_macro

.macro save_info ()
    # Saves current capsule data into memory

    addi $sp, $sp, -8      # Allocate space for two registers on the stack
    sw   $t0, 4($sp)       # Save $t0
    sw   $t1, 0($sp)       # Save $t1

    fetch_capsule_addr ($s0, $s1)  # Get memory address of pixel

    li   $t1, 1            # Load capsule type code
    sb   $t1, 0($v0)       # Store block type at the first byte

    beq  $s2, 1, save_info_vertical   # Handle vertical capsule
    beq  $s2, 2, save_info_horizontal # Handle horizontal capsule

    save_info_vertical:
    li   $t1, 4            # Orientation code for 'down'
    sb   $t1, 1($v0)       # Save direction byte

    addi $t0, $s1, 2       # Compute y-coordinate for the second half
    fetch_capsule_addr ($s0, $t0)  # Fetch second half address

    li   $t1, 1
    sb   $t1, 0($v0)       # Store block type

    li   $t1, 3            # Orientation code for 'up'
    sb   $t1, 1($v0)       # Save direction byte

    j save_info_done       # Return to caller

    save_info_horizontal:
        li   $t1, 2            # Orientation code for 'right'
        sb   $t1, 1($v0)       # Save direction byte
    
        addi $t0, $s0, 2       # Compute x-coordinate for the second half
        fetch_capsule_addr ($t0, $s1)  # Fetch second half address
    
        li   $t1, 1
        sb   $t1, 0($v0)       # Store block type
    
        li   $t1, 1            # Orientation code for 'left'
        sb   $t1, 1($v0)       # Save direction byte

    j save_info_done       # Return to caller

    save_info_done:
        lw   $t1, 0($sp)       # Restore $t1
        lw   $t0, 4($sp)       # Restore $t0
        addi $sp, $sp, 8       # Free stack space
.end_macro

.macro move_info_down (%x, %y)
    # Moves pixel data one block down

    addi $sp, $sp, -4      # Allocate space for one register
    sw   $t0, 0($sp)       # Save $t0

    fetch_capsule_addr (%x, %y)  # Fetch address of current pixel

    lb   $t0, 0($v0)       # Load block type
    sb   $t0, 192($v0)     # Store block type in pixel below

    lb   $t0, 1($v0)       # Load connection direction
    sb   $t0, 193($v0)     # Store connection direction in pixel below

    sb   $zero, 0($v0)     # Clear current block type
    sb   $zero, 1($v0)     # Clear current connection direction

    lw   $t0, 0($sp)       # Restore original $t0
    addi $sp, $sp, 4       # Free stack space
.end_macro

.macro save_ra ()
    # saves the current return address in $ra to the stack, for when there are nested helper labels
    
    addi $sp, $sp, -4       # allocate space on the stack
    sw $ra, 0($sp)          # store the original $ra of main on the stack
.end_macro

.macro load_ra ()
    # loads the most recently saved return address back into $ra from the stack
    
    lw $ra, 0($sp)          # restore the original address
    addi $sp, $sp, 4        # deallocate the space on the stack
.end_macro



##############################################################################
# Main Game Code
##############################################################################

    # Run the game.
main:
      # Show difficulty selection menu
    jal select_difficulty
    jal initialize_game 
    
    # Initialize the game
    jal draw_scene
    jal load_bitmap_image
    jal place_viruses               # place 3 viruses in the bottle
    jal init_music
    new_capsule()
    
    # Initialize gravity timer
    li $v0, 30
    syscall
    sw $a0, last_gravity_time
    
    j game_loop

game_loop:
    # play Dr.Mario theme music
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    jal play_fever_music    # call music function
    lw $ra, 0($sp)
    addi $sp, $sp, 4

        # 1. Check for keyboard input
    lw $t0, ADDR_KBRD
    lw $t1, 0($t0)              # Keyboard control flag
    beq $t1, 0, check_gravity   # If no key pressed, check gravity
    
    # Handle keyboard input
    lw $t0, 4($t0)              # Actual key code
    beq $t0, 0x71, Q_pressed    # Q: quit game
    beq $t0, 0x70, P_pressed    # P: pause/unpause
    
    # Only process other keys if not paused
    lw $t1, is_paused
    bnez $t1, finalize_game_loop
    
    beq $t0, 0x77, check_W      # W: rotate
    beq $t0, 0x61, check_A      # A: move left
    beq $t0, 0x73, check_S      # S: move down
    beq $t0, 0x64, check_D      # D: move right
    
    j finalize_game_loop        # Other keys: ignore and continue

check_gravity:
    # Check if gravity is paused
    lw $t0, gravity_paused
    bnez $t0, finalize_game_loop  # If paused, skip gravity
    
    # Get current system time
    li $v0, 30
    syscall
    
    # Calculate time since last gravity move
    lw $t1, last_gravity_time
    lw $t2, gravity_interval    # Load current gravity interval
    sub $t3, $a0, $t1           # Current time - last move time
    
    # Only move if interval has elapsed
    blt $t3, $t2, finalize_game_loop
    
    # Time to move down!
    sw $a0, last_gravity_time   # Update last move time
    
    # Attempt to move capsule down
    j check_S
    
    # Continue with normal game loop
    j finalize_game_loop    
    
finalize_game_loop:
    # Check for completed rows/columns
    jal check_column_match
    jal check_row_match

no_rows_or_columns:
    # Small delay to maintain game speed
    li $v0, 32
    li $a0, 15                  # 15ms delay (~60fps)
    syscall
    
    # Repeat game loop
    j game_loop
    
check_game_over:
  
        # check if pixels to the bottom are black or gray
        addi $t2, $s0, 0               # store x-coord of the pixel to the left into t2
        addi $t3, $s1, 2              # store y-coord of the pixel to the left into t3 
        get_pixel ($t2, $t3)           # get the address of the pixel to the left into v0 
        lw $t5, 0($v0)                 # load the color of the pixel at that address into t5 
        lw $t6, black                  # Load black into $t6 
        lw $t7, gray                  # Load gray into $t5 
        
        # If the pixel below is black, continue to check if its gray 
        beq $t5, $t6, check_gray        

        # If the pixel below is gray, no ploblem and skip the check_game_over
        check_gray:
          beq $t5, $t7, skip

        # The pixel below must be a capsule, check if its at the mouth of the bottle 
        la $t8, 20                    # Load the y-coordinate of the pixel below ino t8
        beq $t3, $t8, Q_pressed       # If its y-coordinate equal to the y-coordinate of the mouth, then quit 

        # Otherwise,  no ploblem and skip the check_game_over
        j skip 
 
skip: # create new capsule and jump to game_loop_done
  save_info()
  new_capsule()
  j finalize_game_loop       
 select_difficulty:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    difficulty_loop:
        # Print prompt
        li $v0, 4
        la $a0, difficulty_prompt
        syscall
        
        # Get user input
        li $v0, 5
        syscall
        
        # Validate input
        blt $v0, 1, invalid_input
        bgt $v0, 3, invalid_input
        
        # Valid input - store difficulty
        sw $v0, difficulty
        j difficulty_done
        
    invalid_input:
        li $v0, 4
        la $a0, invalid_input_msg
        syscall
        j difficulty_done
        
    difficulty_done:
        lw $ra, 0($sp)
        addi $sp, $sp, 4
        jr $ra

    initialize_game:
        addi $sp, $sp, -4
        sw $ra, 0($sp)
        
        # Set virus count based on difficulty
        lw $t0, difficulty
        beq $t0, 1, set_easy
        beq $t0, 2, set_medium
        beq $t0, 3, set_hard
        
        set_easy:
            lw $t1, easy_viruses
            lw $t2, easy_gravity
            j set_difficulty_params
            
        set_medium:
            lw $t1, medium_viruses
            lw $t2, medium_gravity
            j set_difficulty_params
            
        set_hard:
            lw $t1, hard_viruses
            lw $t2, hard_gravity
            
        set_difficulty_params:
            sw $t1, virus_count
            sw $t2, gravity_interval
        
        lw $ra, 0($sp)
        addi $sp, $sp, 4
        jr $ra
       
      
check_collisions:

    # case 1: W pressed (rotate)
    check_W:
      beq $s2, 1, check_W_vertical   # If capsule is vertical, proceed with check_W_vertical
      beq $s2, 2, check_W_horizontal # If capsule is horizontal, proceed with check_W_horizontal
    
      check_W_horizontal: # If capsule is horizontal:
          # Check if pixels below the capsule are black 
          addi $t2, $s0, 0               # Store x-coord of the pixel below into $t2
          addi $t3, $s1, 2               # Store y-coord of the pixel below into $t3 
          get_pixel ($t2, $t3)           # Get the address of the pixel below into $v0 
          lw $t5, 0($v0)                 # Load the color of the pixel at that address into $t5 
          lw $t6, black                  # Load black into $t6 
          
          # If the pixel below is black, continue with W_pressed
          beq $t5, $t6, W_pressed        # If the color of the pixel is black, continue with W_pressed
      
          # Otherwise, create new capsules
          j finalize_game_loop
      
      check_W_vertical: # If capsule is vertical:
      
        # check for left side 
          check_left_W:
            # Check if pixels to the left of the capsule are black 
            addi $t7, $s0, -1               # Store x-coord of the pixel to the left into $t7
            addi $t8, $s1, 0               # Store y-coord of the pixel to the left into $t8 
            get_pixel ($t7, $t8)           # Get the address of the pixel to the right into $v0 
            lw $t5, 0($v0)                 # Load the color of the pixel at that address into $t5 
            lw $t6, black                  # Load black into $t6 
            
            # If the pixel to the top left is not black, continue with finalize_game_loop
            bne $t5, $t6, finalize_game_loop
           
            # If the pixel to the top left is black, continue with check_W_bottom
            check_W_bottom_left:
              addi $t7, $s0, -1               # Store x-coord of the pixel to the right into $t2
              addi $t8, $s1, 3               # Store y-coord of the pixel to the right into $t3 
              get_pixel ($t7, $t8)           # Get the address of the pixel to the right into $v0 
              lw $t5, 0($v0)                 # Load the color of the pixel at that address into $t5
                
              # If the pixel to the bottom left is black, continue with W_pressed
              bne $t5, $t6, finalize_game_loop        # If the color of the pixel is not black, end 
        

        # check for right side 
        
          # Check if pixels to the right of the capsule are black 
          addi $t2, $s0, 2               # Store x-coord of the pixel to the right into $t2
          addi $t3, $s1, 0               # Store y-coord of the pixel to the right into $t3 
          get_pixel ($t2, $t3)           # Get the address of the pixel to the right into $v0 
          lw $t5, 0($v0)                 # Load the color of the pixel at that address into $t5 
          lw $t6, black                  # Load black into $t6 
          
          # If the pixel to the right is black, continue with check_W_bottom
          bne $t5, $t6, shift_left_W        # If the color of the top pixel is black, continue to chekc if bottom is also black 

          check_W_bottom:
            addi $t2, $s0, 0               # Store x-coord of the pixel to the right into $t2
            addi $t3, $s1, 3               # Store y-coord of the pixel to the right into $t3 
            get_pixel ($t2, $t3)           # Get the address of the pixel to the right into $v0 
            lw $t5, 0($v0)                 # Load the color of the pixel at that address into $t5
              
            # If the pixel to the right is black, continue with check_left_W
            beq $t5, $t6, shift_left_W        # If the color of the pixel is black, continue with check_left_W
            # otherswise continue with W_pressed
            j W_pressed
      
          shift_left_W:
            # Otherwise, shift left then continue with W_pressed
            move_capsule (1)            # move the capsule left
            subi $s0, $s0, 2            # update the x-coordinate
            j W_pressed
            #j finalize_game_loop        # If the pixel is not black, prevent 
            

    # case 2: S pressed  
    check_S:

      beq $s2, 1, check_S_vertical # if capusule is vertical then proceed with check_D_vertical
      beq $s2, 2, check_S_horizontal  # if capusule is horizontal then proceed with check_D_horizontal

      check_S_horizontal: # if capusule is horizontal: 

        # check if pixels to the bottom left is black 
        addi $t2, $s0, 0               # store x-coord of the pixel to the left into t2
        addi $t3, $s1, 2              # store y-coord of the pixel to the left into t3 
        get_pixel ($t2, $t3)           # get the address of the pixel to the left into v0 
        lw $t5, 0($v0)                 # load the color of the pixel at that address into t5 
        lw $t6, black                  # load black into t6 
        
        # if so then continue with S_pressed
        beq $t5, $t6, check_right           # if the color of the pixel is black then continue with check_right
        
        # otherwise check if bottle is full 
        j check_game_over

        # If not full, create new capsule and jump to game_loop_done
        j skip

        check_right:
            # check if pixels to the bottom right is black 
          addi $t7, $s0, 3               # store x-coord of the pixel to the left into t2
          addi $t8, $s1, 2              # store y-coord of the pixel to the left into t3 
          get_pixel ($t7, $t8)           # get the address of the pixel to the left into v0 
          lw $t5, 0($v0)                 # load the color of the pixel at that address into t5 
          lw $t6, black                  # load black into t6 
          
          # if so then continue with S_pressed
          beq $t5, $t6, S_pressed           # if the color of the pixel is black then continue with S_pressed

  
        # otherwise check if bottle is full 
        j check_game_over

        # If not full, create new capsule and jump to game_loop_done
        j skip

      check_S_vertical: # if capusule is vertical: 
      
        # check if pixels to the left are black 
        addi $t2, $s0, 0               # store x-coord of the pixel to the left into t2
        addi $t3, $s1, 5              # store y-coord of the pixel to the left into t3 
        get_pixel ($t2, $t3)           # get the address of the pixel to the left into v0 
        lw $t5, 0($v0)                 # load the color of the pixel at that address into t5 
        lw $t6, black                  # load black into t6

        # if so then continue with D_pressed
        beq $t5, $t6, S_pressed           # if the color of the pixel is black then continue with D_pressed
  
        # otherwise check if bottle is full 
        j check_game_over

        # If not full, create new capsule and jump to game_loop_done
        j skip



    # case 3: A pressed  
    check_A: 
      
      beq $s2, 1, check_A_vertical # if capusule is vertical then proceed with check_A_vertical
      beq $s2, 2, check_A_horizontal  # if capusule is horizontal then proceed with check_A_horizontal

      check_A_horizontal: # if capusule is horizontal: 

        # check if pixels to the left are black 
        addi $t2, $s0, -1               # store x-coord of the pixel to the left into t2
        addi $t3, $s1, 0               # store y-coord of the pixel to the left into t3 
        get_pixel ($t2, $t3)           # get the address of the pixel to the left into v0 
        lw $t5, 0($v0)                 # load the color of the pixel at that address into t5 
        lw $t6, black                  # load black into t6 
        
        # if so then continue with A_pressed
        beq $t5, $t6, check_A_vertical           # if the color of the pixel is black then continue with A_pressed
  
        # otherwise jump to game_loop_done
        j finalize_game_loop

      check_A_vertical: # if capusule is vertical: 
      
        # check if pixels to the left bottom half are black 
        addi $t2, $s0, -1               # store x-coord of the pixel to the left into t2
        addi $t3, $s1, 3               # store y-coord of the pixel to the left into t3 
        get_pixel ($t2, $t3)           # get the address of the pixel to the left into v0 
        lw $t5, 0($v0)                 # load the color of the pixel at that address into t5 
        lw $t6, black                  # load black into t6

        # if so then continue with check_A_upper
        beq $t5, $t6, check_A_upper           # if the color of the pixel is black then continue with check_A_upper
  
        # otherwise jump to game_loop_done
        j finalize_game_loop

        check_A_upper:
          # check if pixels to the left upper half are black 
          addi $t2, $s0, -1               # store x-coord of the pixel to the left into t2
          addi $t3, $s1, 0               # store y-coord of the pixel to the left into t3 
          get_pixel ($t2, $t3)           # get the address of the pixel to the left into v0 
          lw $t5, 0($v0)                 # load the color of the pixel at that address into t5 
          lw $t6, black                  # load black into t6
  
          # if so then continue with A_pressed
          beq $t5, $t6, A_pressed           # if the color of the pixel is black then continue with D_pressed
    
          # otherwise jump to game_loop_done
          j finalize_game_loop


    # case 4: D pressed 
    check_D:

      beq $s2, 1, check_D_vertical # if capusule is vertical then proceed with check_D_vertical
      beq $s2, 2, check_D_horizontal  # if capusule is horizontal then proceed with check_D_horizontal

      check_D_horizontal: # if capusule is horizontal: 

        # check if pixels to the right are black 
        addi $t2, $s0, 4               # store x-coord of the pixel to the left into t2
        addi $t3, $s1, 0               # store y-coord of the pixel to the left into t3 
        get_pixel ($t2, $t3)           # get the address of the pixel to the left into v0 
        lw $t5, 0($v0)                 # load the color of the pixel at that address into t5 
        lw $t6, black                  # load black into t6 
        
        # if so then continue with D_pressed
        beq $t5, $t6, D_pressed           # if the color of the pixel is black then continue with D_pressed
  
        # otherwise jump to game_loop_done
        j finalize_game_loop

      check_D_vertical: # if capusule is vertical: 
      
        # check if pixels to the right bottom half are black 
        addi $t2, $s0, 2               # store x-coord of the pixel to the left into t2
        addi $t3, $s1, 3               # store y-coord of the pixel to the left into t3 
        get_pixel ($t2, $t3)           # get the address of the pixel to the left into v0 
        lw $t5, 0($v0)                 # load the color of the pixel at that address into t5 
        lw $t6, black                  # load black into t6

        # if so then continue with check_D_upper
        beq $t5, $t6, check_D_upper           # if the color of the pixel is black then continue with check_D_upper
  
        # otherwise jump to game_loop_done
        j finalize_game_loop

        check_D_upper:
                  # check if pixels to the right upper half are black 
        addi $t2, $s0, 2               # store x-coord of the pixel to the left into t2
        addi $t3, $s1, 0               # store y-coord of the pixel to the left into t3 
        get_pixel ($t2, $t3)           # get the address of the pixel to the left into v0 
        lw $t5, 0($v0)                 # load the color of the pixel at that address into t5 
        lw $t6, black                  # load black into t6

        # if so then continue with check_D_bottom
        beq $t5, $t6, D_pressed           # if the color of the pixel is black then continue with check_D_bottom
  
        # otherwise jump to game_loop_done
        j finalize_game_loop

##############################################################################
# Matching and Collapse Functions
##############################################################################

check_row_match:
    # Checks for 4+ consecutive same-color blocks in rows
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    li $s7, 3           # Minimum blocks needed for a match (4-1)
    jal check_rows
    
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

check_column_match:
    # Checks for 4+ consecutive same-color blocks in columns
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    li $s7, 3           # Minimum blocks needed for a match (4-1)
    jal check_columns
    
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

animation_delay:
    # Small delay for visual effect
    li $v0, 32
    li $a0, 50         # 100ms delay
    syscall
    jr $ra

collapse_playing_area:
    # After blocks are removed, collapse any blocks down the playing area
    # $t0: current x-coordinate
    # $t1: current y-coordinate
    # $t2: curr colour
    # $t3: black
    # $t4: max x-coordinate
    # $t5: max y-coordinate
    # $t6: block info
    # $t7: temporary multipurpose

    lw $t3, black       # load the colour black
    li $t4, 30          # initialize the maximum x-coordinate
    li $t5, 26          # initialize the maximum y-coordinate
    
collapse_loops:
    li $t1, 54          # initialize the starting y-coordinate to the playing area offset
    
collapse_for_y:
    blt $t1, $t5, collapse_end_loops   # if for-loop is done, collapsing is complete
    li $t0, 6                          # initialize the starting x-coordinate
    
collapse_for_x:
    bgt $t0, $t4, collapse_next_y      # if for-loop is done, iterate to next row
    
    get_pixel ($t0, $t1)               # fetch the address of the current pixel
    lw $t2, 0($v0)                     # fetch the colour of the current pixel
    beq $t2, $t3, collapse_next_x      # if the block is black, skip to next iteration
    
    lw $t2, 512($v0)                   # fetch the colour of the block below it
    beq $t2, $t3, collapse_block       # if black, collapse the block down
    j collapse_next_x                  # else, supported; move on to next block
    
collapse_next_x:
    addi $t0, $t0, 2        # increment to the next x-coordinate
    j collapse_for_x        # continue the for-loop
            
collapse_next_y:
    subi $t1, $t1, 2        # increment to the next y-coordinate
    j collapse_for_y        # continue the for-loop
        
collapse_block:
    get_info ($t0, $t1)     # fetch the accessory information about the current block 
    move $t6, $v0           # fetch the block type
    beq $t6, 2, collapse_next_x  # if a virus, skip to the next iteration
    
    move $t6, $v1           # else, a capsule; fetch its orientation
    
    get_pixel ($t0, $t1)               # fetch the address of the current pixel
    lw $t2, 512($v0)                   # fetch the colour of the block below it
    beq $t2, $t3, check_virus_below    # if black space below, check if there's a virus there
    j collapse_next_x                   # if not black below, block is supported
    
check_virus_below:
    addi $t7, $t1, 2                   # y coordinate of block below
    get_info ($t0, $t7)                # get info of block below
    li $t7, 2                          # virus type code
    beq $v0, $t7, collapse_next_x      # if supported by virus, skip to next
    
    # Only proceed with specific orientations we know how to handle
    beq $t6, 0, collapse_direct        # if capsule half is not connected to another half
    beq $t6, 2, collapse_right         # if connected to the right
    beq $t6, 3, collapse_up            # if connected above
    j collapse_next_x                  # if orientation doesn't match expected cases, skip this block
        
collapse_direct:
    li $t5, 4
    move_square ($t0, $t1, $t5)     # move the current block down
    move_info_down ($t0, $t1)     # move the game memory information down
    jal animation_delay           # sleep for animation
    j collapse_loops              # restart the full looping process
            
collapse_right:
    get_pixel ($t0, $t1)          # fetch the address of the current pixel
    lw $t2, 516($v0)              # fetch the colour of the block below and to the right
    bne $t2, $t3, collapse_next_x # second capsule half is supported, return to next iteration
    li $t5, 4        
    move_square ($t0, $t1, $t5)     # move the current block down
    move_info_down ($t0, $t1)     # move the game memory information down
    addi $t0, $t0, 2              # move to the next capsule half
    j collapse_direct             # move the next half down
    
collapse_up:
    li $t5, 4
    move_square ($t0, $t1, $t5)     # move the current block down
    move_info_down ($t0, $t1)     # move the game memory information down
    subi $t1, $t1, 2              # move to the capsule half above
    j collapse_direct             # move the next half down
        
collapse_end_loops:
    j finalize_game_loop         # restart the collapsing process
        
reset_consecutive:
    li $t6, 1           # set the current consecutive number of blocks to one
    move $t8, $t0       # set the x-coordinate to the current position
    move $t9, $t1       # set the y-coordinate to the current position
    jr $ra              # return to the for-loops        
    
check_rows:
    # checks for any matching blocks in each row and removes them
    # $t0: x-coordinate
    # $t1: y-coordinate
    # $t2: black
    # $t3: current colour
    # $t4: max x
    # $t5: max y
    # $t6: num consecutive
    # $t7: current consecutive colour
    # $t8: start of colour x-coordinate
    # $t9: start of colour y-coordinate
    # $s7: min num of blocks per row - 1

    save_ra()           # save return address for nested jumps
    
    lw $t2, black       # load the colour black
    li $t4, 32          # load the maximum x-coordinate + 4 (to not clip off last pixel)
    li $t5, 58          # load the maximum y-coordinate
    
rows_loops:
    li $t1, 18          # initialize y-coordinate to the playing area offset
        
rows_for_y:
    beq $t1, $t5, rows_end_loops  # if for-loop is done, row checking is completed
        
    li $t0, 6           # initialize x-coordinate to the playing area offset
    jal reset_consecutive # reset consecutive coordinates to current position
    move $t7, $t2       # set current consecutive colour to black by default
        
rows_for_x:
    beq $t0, $t4, rows_next_y  # if for-loop is done, iterate to next y-coordinate
                
    get_pixel ($t0, $t1)       # fetch the address of the current block
    lw $t3, 0($v0)             # extract its colour
                
    beq $t3, $t2, rows_found_black  # if black, skip to next iteration
    bne $t3, $t7, rows_diff_colour  # if different colour than current consecutive
                
    addi $t6, $t6, 1    # same colour, increment consecutive count
    j rows_next_x       # continue to next iteration
            
rows_diff_colour:
    bgt $t6, $s7, rows_remove_match  # if valid matching found, remove it
    jal reset_consecutive            # else, reset to current pixel
    move $t7, $t3                   # set consecutive colour to current pixel
    j rows_next_x                   # continue to next iteration
                    
rows_found_black:
    bgt $t6, $s7, rows_remove_match  # if valid matching found, remove it
    jal reset_consecutive            # reset consecutive information
    move $t7, $t2                   # set current consecutive colour to black
    j rows_next_x                   # continue to next iteration
                    
rows_next_x:
    addi $t0, $t0, 2    # increment the x-coordinate
    j rows_for_x        # return to the for-loop
            
rows_next_y:
    addi $t1, $t1, 2    # increment the y-coordinate
    j rows_for_y        # return to the for-loop
    
rows_remove_match:
    rows_match_loop:
        beq $t8, $t0, rows_end_match_loop  # once all of match is removed, move on
        draw_square ($t8, $t9, $t2)        # remove the block at current coordinates
        remove_info ($t8, $t9)              # remove block's information
        addi $t8, $t8, 2                   # increment to next block
        jal animation_delay                # sleep for animation
        j rows_match_loop
                
rows_end_match_loop: 
    addi $sp, $sp, 4     # original address isn't needed, deallocate space
    j collapse_playing_area  # collapse blocks and recheck everything
            
rows_end_loops:
    load_ra()           # restore original return address
    jr $ra              # return to original call
            

check_columns:
    # checks for any matching blocks in each column and removes them
    # same logic as rows but for columns
    
    save_ra()
    lw $t2, black
    li $t4, 30          
    li $t5, 60          
columns_loops:
    li $t0, 6
columns_for_x:
    beq $t0, $t4, columns_end_loops
    li $t1, 18
    jal reset_consecutive
    move $t7, $t2
columns_for_y:
    beq $t1, $t5, columns_next_x
    get_pixel ($t0, $t1)
    lw $t3, 0($v0)
    beq $t3, $t2, columns_found_black
    bne $t3, $t7, columns_diff_colour
    addi $t6, $t6, 1
    j columns_next_y
columns_diff_colour:
    bgt $t6, $s7, columns_remove_match
    jal reset_consecutive
    move $t7, $t3
    j columns_next_y
columns_found_black:
    bgt $t6, $s7, columns_remove_match
    jal reset_consecutive
    move $t7, $t2
    j columns_next_y
columns_next_y:
    addi $t1, $t1, 2
    j columns_for_y
columns_next_x:
    addi $t0, $t0, 2
    j columns_for_x
columns_remove_match:
    columns_match_loop:
        beq $t9, $t1, columns_end_match_loop
        draw_square ($t8, $t9, $t2)
        remove_info ($t8, $t9)
        addi $t9, $t9, 2
        jal animation_delay
        j columns_match_loop
columns_end_match_loop: 
    addi $sp, $sp, 4
    j collapse_playing_area
columns_end_loops:
    load_ra()
    jr $ra

check_speed_up:
    addi $sp, $sp, -4
    sw $ra, 0($sp)          # Save return address
    
    # Increment clear counter
    lw $t0, clear_count
    addi $t0, $t0, 1
    sw $t0, clear_count
    
    # Check if we've cleared 3 rows/columns
    li $t1, 3
    bne $t0, $t1, speed_up_done
    
    # Speed up gravity
    lw $t2, gravity_interval
    lw $t3, gravity_step
    sub $t2, $t2, $t3
    
    # Enforce minimum gravity speed
    lw $t3, min_gravity
    bge $t2, $t3, apply_new_gravity
    move $t2, $t3
        
    apply_new_gravity:
        sw $t2, gravity_interval
        sw $zero, clear_count    # Reset counter
        
    speed_up_done:
        lw $ra, 0($sp)          # Restore return address
        addi $sp, $sp, 4
        jr $ra
          
  
# Pause gravity - stops automatic downward movement
pause_gravity:
    addi $sp, $sp, -4        # Save return address
    sw $ra, 0($sp)
    
    li $t0, 1
    sw $t0, gravity_paused   # Set gravity_paused flag to 1 (true)
    

    
    lw $ra, 0($sp)           # Restore return address
    addi $sp, $sp, 4
    jr $ra

# Resume gravity - re-enables automatic downward movement  
resume_gravity:
    addi $sp, $sp, -4        # Save return address
    sw $ra, 0($sp)
    
    sw $zero, gravity_paused # Set gravity_paused flag to 0 (false)
    
    # Reset gravity timer so it starts fresh
    li $v0, 30
    syscall
    sw $a0, last_gravity_time
    
    
    lw $ra, 0($sp)           # Restore return address
    addi $sp, $sp, 4
    jr $ra



# Increase gravity speed (make fall faster)
increase_gravity:
    lw $t0, gravity_interval
    lw $t1, min_gravity
    lw $t2, gravity_step
    sub $t0, $t0, $t2           # Decrease interval = faster
    bge $t0, $t1, store_gravity # Don't go below minimum
    move $t0, $t1               # Use minimum if exceeded
    
store_gravity:
    sw $t0, gravity_interval
    jr $ra

# Decrease gravity speed (make fall slower)
decrease_gravity:
    lw $t0, gravity_interval
    lw $t1, base_gravity
    lw $t2, gravity_step
    add $t0, $t0, $t2           # Increase interval = slower
    ble $t0, $t1, store_gravity # Don't go above baseline
    move $t0, $t1               # Use baseline if exceeded
    j store_gravity

# Reset to default gravity
reset_gravity:
    lw $t0, base_gravity
    sw $t0, gravity_interval
    jr $ra
    
W_pressed:
    # assuming no collision will occur, rotate the capsule 90 degrees clockwise
    
    beq $s2, 1, rotate_vertical             # if the capsule is vertical, rotate to horizontal
    beq $s2, 2, rotate_horizontal           # if the capsule is horizontal, rotate to vertical
    
    rotate_horizontal:
        li $t2, 4                           # set the direction to move to down
        move_square ($s0, $s1, $t2)         # move the first half of the capsule down
        addi $t0, $s0, 2                    # the second half is to the right of the original position
        li $t2, 1                           # set the direction to move to left
        move_square ($t0, $s1, $t2)         # move the second half of teh capsule left
        li $s2, 1                           # set the capsule's orientation to vertical
        j w_pressed_done
    
    rotate_vertical:
        addi $t1, $s1, 2                    # the second half of the capsule is below the first half
        li $t2, 2                           # set the direction to move to right
        move_square ($s0, $t1, $t2)         # move the capsule's second half right
        addi $t0, $s0, 2                    # the second half is now to the right of its original position
        li $t2, 3                           # set the direction to move to up
        move_square ($t0, $t1, $t2)         # move the capsule's second half up
        li $s2, 2                           # set the capsule's orientation to horizontal
        j w_pressed_done                    # return back to main
        
    w_pressed_done: j finalize_game_loop    # return back to the game loop
    
A_pressed:
    # assuming no collision will occur, move the capsule to the left
    move_capsule (1)            # move the capsule left
    subi $s0, $s0, 2            # update the x-coordinate
    j finalize_game_loop        # return back to the game loops

S_pressed:
    # assuming no collisions will occur, move the capsule down
    move_capsule (4)            # move the capsule down
    addi $s1, $s1, 2            # update the y-coordinate
    j finalize_game_loop        # return back to the game loop

D_pressed:
    # assuming no collision will occur, move the capsule to the right
    move_capsule (2)            # move the capsue right
    addi $s0, $s0, 2            # update the x-coordinate
    j finalize_game_loop        # return back to the game loop

Q_pressed:
    li $v0, 10          # load the syscall code for quitting the program
   syscall              # invoke the syscall
   
P_pressed:
    lw $t0, is_paused
    beqz $t0, pause_game       # If not paused, pause the game
    j unpause_game             # Else, unpause the game

pause_game:
    li $t0, 1
    sw $t0, is_paused          # Set paused flag
    jal pause_gravity          # Stop automatic movement
    jal load_pause_image
    
    j finalize_game_loop

unpause_game:
    sw $zero, is_paused        # Clear paused flag
    jal resume_gravity         # Resume automatic movement
    jal load_unpause_image
    
    j finalize_game_loop

display_pause_message:
    
draw_scene:
    # draws the initial static scene
    
    save_ra ()              # there are nested helper labels, save the original return address
    
    # initialize variables to draw the vertical walls of the bottle
    li $t2, 42              # set the number of loops to perform to draw each line
    lw $t3, gray            # load the colour gray
    li $t5, 256             # set the increment to move to the next pixel (down)
    
    # draw the left wall
    addi $t0, $gp, 4368     # set the starting coordinate for the left wall's first pass
    jal paint_line          # paint the left wall
    addi $t0, $gp, 4116     # set the starting coordinate for the left wall's second pass
    li $t2, 44              # draw the inner line one pixel longer than the inner
    jal paint_line          # paint the left wall
    
    # draw the right wall
    addi $t0, $gp, 4216     # set the starting coordinate for the right wall's first pass
    jal paint_line          # paint the right wall
    addi $t0, $gp, 4476     # set the starting coordinate for the right wall's second pass
    li $t2, 42              # draw the outer line one pixel shorter than the inner
    jal paint_line          # paint the right wall
    
    # draw the bottom
    li $t2, 24              # set the number of loops to perform to draw the line
    li $t5, 4               # set the increment to move to the next pixel (across)
    
    addi $t0, $gp, 14872    # set the starting coordinate for the bottom
    jal paint_line          # paint the bottom of the bottle
    addi $t0, $gp, 15128    # set the starting coordinate for the bottom
    jal paint_line          # paint the bottom of the bottle
    
    # draw the mouth
    li $t2, 8               # update number of loops to perform: horizontal portion
    li $t5, 4               # set increment value: draw horizontally
    addi $t0, $gp, 4120     # update coordinate
    jal paint_line          # paint the line
    addi $t0, $gp, 4376
    jal paint_line
    addi $t0, $gp, 4184
    jal paint_line
    addi $t0, $gp, 4440
    jal paint_line
    
    li $t2, 4               # update number of loops to perform: first vertical portion 
    li $t5, 256             # set incremental value: draw vertically
    addi $t0, $gp, 3120     # update coordinate
    jal paint_line          # paint the line
    addi $t0, $gp, 3124
    jal paint_line
    addi $t0, $gp, 3160
    jal paint_line
    addi $t0, $gp, 3164
    jal paint_line
    
    
    #  Initialize the preview capsule with random colors
    random_colour ()
    sw $v1, next_capsule_color1
    
    random_colour ()
    sw $v1, next_capsule_color2
    
    # Draw initial preview capsule (always horizontal)
    lw $t0, next_capsule_x
    lw $t1, next_capsule_y
    lw $t2, next_capsule_color1
    draw_square ($t0, $t1, $t2)
    
    addi $t0, $t0, 2
    lw $t2, next_capsule_color2
    draw_square ($t0, $t1, $t2)

    load_ra ()              # fetch the original return address
    jr $ra                  # return back to main

    # helper label that paints a line for a given number of pixels long
    paint_line:
    
        li $t1, 0           # reset the initial value of i = 0
        j inner_paint       # enters the for-loop
        
        inner_paint:
            beq $t1, $t2, jump_to_ra    # once for-loop is done, return to label call in draw_bottle
                sw $t3, 0($t0)          # paint the pixel gray
                add $t0, $t0, $t5       # move to the next pixel (row down or pixel to the right)
                addi $t1, $t1, 1        # increment i
            j inner_paint               # continue the for-loop

##############################################################################
# Virus Placement
##############################################################################
place_viruses:
    # Modified to use the virus_count from difficulty selection
    save_ra()
    
    lw $t9, virus_count    # Get count based on difficulty
    li $t8, 0              # Counter for placed viruses
    
place_viruses_loop:
    beq $t8, $t9, place_viruses_done
    
    # Generate random x position (aligned to pill grid)
    li $v0, 42
    li $a0, 0
    li $a1, 11             # 11 possible x positions (6-28 in steps of 2)
    syscall
    
    sll $t0, $a0, 1        # Multiply by 2
    addi $t0, $t0, 6       # Now 6-28 in steps of 2

    # Generate random y position in bottom half
    li $v0, 42
    li $a0, 0
    li $a1, 11             # 11 possible y positions (34-56 in steps of 2)
    syscall
    
    sll $t1, $a0, 1
    addi $t1, $t1, 34
    
    # Validate coordinates before proceeding
    blt $t0, 6, place_viruses_loop   # x < 6 is invalid
    bgt $t0, 28, place_viruses_loop  # x > 28 is invalid
    blt $t1, 34, place_viruses_loop  # y < 34 is invalid
    bgt $t1, 56, place_viruses_loop  # y > 56 is invalid
    
    # Check if position is empty
    get_pixel($t0, $t1)
    move $t4, $v0           # Save the address (in case $v0 gets modified)
    
    # Verify we got a valid address
    beqz $t4, place_viruses_loop     # Address 0 is invalid
    li $t5, 0x10000000      # Typical MARS display memory base
    blt $t4, $t5, place_viruses_loop # Address too low is invalid
    
    lw $t2, 0($t4)          # Load pixel color
    lw $t3, black
    bne $t2, $t3, place_viruses_loop
    
    # Choose random virus color (0=red, 1=blue, 2=yellow)
    li $v0, 42
    li $a0, 0
    li $a1, 3
    syscall
    
    beq $a0, 0, place_red_virus
    beq $a0, 1, place_blue_virus
    
    # Green virus
    lw $t2, green
    lw $t3, dark_green
    j draw_virus
    
place_red_virus:
    lw $t2, red
    lw $t3, dark_red
    j draw_virus
    
place_blue_virus:
    lw $t2, blue
    lw $t3, dark_blue
    
draw_virus:
    draw_virus($t0, $t1, $t2, $t3)

    fetch_capsule_addr ($t0, $t1)     # fetch the address of the block in memory
    li $t5, 2                       # load the block type code for virus
    sb $t5, 0($v0)                  # save the block type code as the first byte
    sb $zero, 1($v0)                # save the orientation direction code as zero (not connected)
    
    # add additional check to ensure virus info is stored correctly
    get_info ($t0, $t1)             # verify the info was stored correctly
    bne $v0, 2, place_viruses_loop  # if not stored as virus, try again
    bnez $v1, place_viruses_loop    # if has orientation, try again
    
    addi $t8, $t8, 1
    j place_viruses_loop
    
place_viruses_done:
    load_ra()
    jr $ra
##############################################################################
# Music Functions
##############################################################################
# Plays the Dr.Mario theme as background music
# Uses syscall 31 for asynchronous playback
play_fever_music:
    # Save registers
    addi $sp, $sp, -16
    sw $ra, 0($sp)
    sw $s0, 4($sp)
    sw $s1, 8($sp)
    sw $s2, 12($sp)

    # Get current system time
    li $v0, 30             # System time syscall
    syscall                # Returns time in $a0 (low) and $a1 (high)
    move $s0, $a0          # Store current time in $s0

    # Load last note time
    lw $s1, fever_last_note_time

    # Check if enough time has passed since last note
    sub $t0, $s0, $s1      # Current time - last note time

    # Get current note info
    lw $t1, fever_current_note    # Get current note index
    la $t2, fever_music           # Load base address of music data
    sll $t3, $t1, 4              # Multiply index by 16 (4 words per note)
    add $t2, $t2, $t3            # Get address of current note

    # Load note data
    lw $t4, 0($t2)               # Load pitch
    lw $t5, 4($t2)               # Load duration

    # Check if it's time to play the next note
    blt $t0, $t5, play_fever_end  # If not enough time passed, skip

    # Check for end of sequence marker (-1)
    li $t6, -1
    beq $t4, $t6, reset_fever_music

    # Set up note parameters
    move $a0, $t4                # Pitch
    lw $a1, 4($t2)               # Duration
    lw $a2, 8($t2)               # Instrument
    lw $a3, 12($t2)              # Volume

    # Play the note
    li $v0, 31                   # MIDI out async syscall
    syscall

    # Update last note time
    sw $s0, fever_last_note_time

    # Increment note index
    addi $t1, $t1, 1
    sw $t1, fever_current_note
    j play_fever_end

reset_fever_music:
    # Reset to beginning of sequence
    li $t0, 0
    sw $t0, fever_current_note
    # Update last note time to ensure immediate playback of first note
    sw $s0, fever_last_note_time

play_fever_end:
    # Restore registers
    lw $ra, 0($sp)
    lw $s0, 4($sp)
    lw $s1, 8($sp)
    lw $s2, 12($sp)
    addi $sp, $sp, 16

    jr $ra

# Initialize music variables and play first note
init_music:
    # Reset music variables
    li $t0, 0
    sw $t0, fever_current_note  # Start at first note

    # Get current time as initial value
    li $v0, 30       # System time syscall
    syscall
    sw $a0, fever_last_note_time

    # Play first note immediately
    la $t2, fever_music
    lw $a0, 0($t2)   # Pitch
    lw $a1, 4($t2)   # Duration
    lw $a2, 8($t2)   # Instrument
    lw $a3, 12($t2)  # Volume

    # Play the note
    li $v0, 31       # MIDI out async
    syscall

    # Set current note to 1 (next note)
    li $t0, 1
    sw $t0, fever_current_note

    jr $ra

##############################################################################
# Bitmap Loader Functions
##############################################################################

# Function to load and display a bitmap image
# This function should be called after the draw_scene function
load_bitmap_image:
    # Save registers
    addi $sp, $sp, -20
    sw $ra, 0($sp)
    sw $s0, 4($sp)
    sw $s1, 8($sp)
    sw $s2, 12($sp)
    sw $s3, 16($sp)
    
    # Remember original $gp value
    move $s3, $gp
    
    jal load_bitmap
    
    # Restore original $gp value
    move $gp, $s3
    
load_bitmap_done:
    # Restore registers
    lw $s3, 16($sp)
    lw $s2, 12($sp)
    lw $s1, 8($sp)
    lw $s0, 4($sp)
    lw $ra, 0($sp)
    addi $sp, $sp, 20
    
    jr $ra

# Function to display the bitmap at a specific position
# Parameters: $a0 = x position, $a1 = y position
display_bitmap:
    # Save registers
    addi $sp, $sp, -24
    sw $ra, 0($sp)
    sw $s0, 4($sp)
    sw $s1, 8($sp)
    sw $s2, 12($sp)
    sw $s3, 16($sp)
    sw $s4, 20($sp)
    
    # Save parameters
    move $s0, $a0         # x position
    move $s1, $a1         # y position
    
    # Load bitmap dimensions
    li $s2, 64  # Width constant
    li $s3, 64  # Height constant
    
    # Get bitmap data address
    la $s4, mario_bitmap
    
display_bitmap_loop:
    lw $t1, 0($s4)        # Load pixel index
    beq $t1, -1, display_bitmap_done  # If -1, we're done
    
    lw $t2, 4($s4)        # Load pixel color
    
    # Calculate original x, y coordinates from the index
    div $t1, $s2
    mfhi $t3              # x = index % width
    mflo $t4              # y = index / width
    
    # Calculate new screen coordinates
    add $t3, $t3, $s0     # x = x + offset_x
    add $t4, $t4, $s1     # y = y + offset_y
    
    # Draw the pixel at the new position
    draw_pixel($t3, $t4, $t2)
    
    # Move to next data pair
    addi $s4, $s4, 8
    j display_bitmap_loop
    
display_bitmap_done:
    # Restore registers
    lw $s4, 20($sp)
    lw $s3, 16($sp)
    lw $s2, 12($sp)
    lw $s1, 8($sp)
    lw $s0, 4($sp)
    lw $ra, 0($sp)
    addi $sp, $sp, 24
    
    jr $ra

load_bitmap:
    la $t0, mario_bitmap    # Load address of bitmap data

load_bitmap_loop:
    lw $t1, 0($t0)         # Load pixel index
    beq $t1, -1, load_bitmap_done  # If -1, we're done
    lw $t2, 4($t0)         # Load pixel color
    sll $t3, $t1, 2        # Multiply index by 4 (4 bytes per pixel)
    add $t4, $gp, $t3      # Calculate actual memory address
    sw $t2, 0($t4)         # Store color at the calculated address
    addi $t0, $t0, 8       # Move to next pixel data pair
    j load_bitmap_loop     # Repeat

##############################################################################
# Pause Bitmap Display Functions
##############################################################################

# Function to load and display a pause image
load_pause_image:
    # Save registers
    addi $sp, $sp, -20
    sw $ra, 0($sp)
    sw $s0, 4($sp)
    sw $s1, 8($sp)
    sw $s2, 12($sp)
    sw $s3, 16($sp)
    
    # Remember original $gp value
    move $s3, $gp
    
    jal load_pause_bitmap
    
    # Restore original $gp value
    move $gp, $s3
    
load_pause_done:
    # Restore registers
    lw $s3, 16($sp)
    lw $s2, 12($sp)
    lw $s1, 8($sp)
    lw $s0, 4($sp)
    lw $ra, 0($sp)
    addi $sp, $sp, 20
    
    jr $ra

# Function to display the bitmap at a specific position
# Parameters: $a0 = x position, $a1 = y position
display_pause:
    # Save registers
    addi $sp, $sp, -24
    sw $ra, 0($sp)
    sw $s0, 4($sp)
    sw $s1, 8($sp)
    sw $s2, 12($sp)
    sw $s3, 16($sp)
    sw $s4, 20($sp)
    
    # Save parameters
    move $s0, $a0         # x position
    move $s1, $a1         # y position
    
    # Load bitmap dimensions
    li $s2, 64  # Width constant
    li $s3, 64  # Height constant
    
    # Get bitmap data address
    la $s4, pause_bitmap
    
display_pause_loop:
    lw $t1, 0($s4)        # Load pixel index
    beq $t1, -1, display_pause_done  # If -1, we're done
    
    lw $t2, 4($s4)        # Load pixel color
    
    # Calculate original x, y coordinates from the index
    div $t1, $s2
    mfhi $t3              # x = index % width
    mflo $t4              # y = index / width
    
    # Calculate new screen coordinates
    add $t3, $t3, $s0     # x = x + offset_x
    add $t4, $t4, $s1     # y = y + offset_y
    
    # Draw the pixel at the new position
    draw_pixel($t3, $t4, $t2)
    
    # Move to next data pair
    addi $s4, $s4, 8
    j display_pause_loop
    
display_pause_done:
    # Restore registers
    lw $s4, 20($sp)
    lw $s3, 16($sp)
    lw $s2, 12($sp)
    lw $s1, 8($sp)
    lw $s0, 4($sp)
    lw $ra, 0($sp)
    addi $sp, $sp, 24
    
    jr $ra

load_pause_bitmap:
    la $t0, pause_bitmap    # Load address of bitmap data

load_pause_loop:
    lw $t1, 0($t0)         # Load pixel index
    beq $t1, -1, load_pause_done  # If -1, we're done
    lw $t2, 4($t0)         # Load pixel color
    sll $t3, $t1, 2        # Multiply index by 4 (4 bytes per pixel)
    add $t4, $gp, $t3      # Calculate actual memory address
    sw $t2, 0($t4)         # Store color at the calculated address
    addi $t0, $t0, 8       # Move to next pixel data pair
    j load_pause_loop     # Repeat

##############################################################################
# Unpause Bitmap Display Functions
##############################################################################

# Function to load and display a pause image
load_unpause_image:
    # Save registers
    addi $sp, $sp, -20
    sw $ra, 0($sp)
    sw $s0, 4($sp)
    sw $s1, 8($sp)
    sw $s2, 12($sp)
    sw $s3, 16($sp)
    
    # Remember original $gp value
    move $s3, $gp
    
    jal load_unpause_bitmap
    
    # Restore original $gp value
    move $gp, $s3
    
load_unpause_done:
    # Restore registers
    lw $s3, 16($sp)
    lw $s2, 12($sp)
    lw $s1, 8($sp)
    lw $s0, 4($sp)
    lw $ra, 0($sp)
    addi $sp, $sp, 20
    
    jr $ra

# Function to display the bitmap at a specific position
# Parameters: $a0 = x position, $a1 = y position
display_unpause:
    # Save registers
    addi $sp, $sp, -24
    sw $ra, 0($sp)
    sw $s0, 4($sp)
    sw $s1, 8($sp)
    sw $s2, 12($sp)
    sw $s3, 16($sp)
    sw $s4, 20($sp)
    
    # Save parameters
    move $s0, $a0         # x position
    move $s1, $a1         # y position
    
    # Load bitmap dimensions
    li $s2, 64  # Width constant
    li $s3, 64  # Height constant
    
    # Get bitmap data address
    la $s4, unpause_bitmap
    
display_unpause_loop:
    lw $t1, 0($s4)        # Load pixel index
    beq $t1, -1, display_unpause_done  # If -1, we're done
    
    lw $t2, 4($s4)        # Load pixel color
    
    # Calculate original x, y coordinates from the index
    div $t1, $s2
    mfhi $t3              # x = index % width
    mflo $t4              # y = index / width
    
    # Calculate new screen coordinates
    add $t3, $t3, $s0     # x = x + offset_x
    add $t4, $t4, $s1     # y = y + offset_y
    
    # Draw the pixel at the new position
    draw_pixel($t3, $t4, $t2)
    
    # Move to next data pair
    addi $s4, $s4, 8
    j display_unpause_loop
    
display_unpause_done:
    # Restore registers
    lw $s4, 20($sp)
    lw $s3, 16($sp)
    lw $s2, 12($sp)
    lw $s1, 8($sp)
    lw $s0, 4($sp)
    lw $ra, 0($sp)
    addi $sp, $sp, 24
    
    jr $ra

load_unpause_bitmap:
    la $t0, unpause_bitmap    # Load address of bitmap data

load_unpause_loop:
    lw $t1, 0($t0)         # Load pixel index
    beq $t1, -1, load_unpause_done  # If -1, we're done
    lw $t2, 4($t0)         # Load pixel color
    sll $t3, $t1, 2        # Multiply index by 4 (4 bytes per pixel)
    add $t4, $gp, $t3      # Calculate actual memory address
    sw $t2, 0($t4)         # Store color at the calculated address
    addi $t0, $t0, 8       # Move to next pixel data pair
    j load_unpause_loop     # Repeat

##############################################################################
# Global Helpers
##############################################################################

# allows 'beq' to jump to a register (usually $ra)
jump_to_ra: jr $ra
