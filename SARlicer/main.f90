program hello
    implicit none

    integer :: quality=100  !mwsured in millimeters
    integer :: ios

    real :: nozzleSize=0.4
    real :: layerHeight
    real :: height
    real :: x
    real :: y
    real :: z
    character(len=256) :: fname
    character(len=128) :: line

    integer(8) :: fsize
    integer(4) :: ntri_hdr
    logical :: is_binary

    print *, "What is the fame of the file? (255 char max for the path.)"
    read *, fname

    print *, "what is the quality of this print?"
    read *, quality

    print *, "What is the diameter of your nozzle?"
    read *, nozzleSize

    layerHeight = 0.8*nozzleSize

    ! ---- check whether the file is binary or ASCII ----
    open(10, file=trim(fname), access='stream', form='unformatted', &
         status='old', action='read', iostat=ios)
    if (ios /= 0) then
        print *, "Could not open: ", trim(fname)
        stop 1
    end if

    inquire(10, size=fsize)
    is_binary = .false.
    if (fsize >= 84) then
        read(10, pos=81) ntri_hdr
        if (fsize == 84_8 + 50_8*ntri_hdr) is_binary = .true.
    end if
    close(10)

    ! ---- if binary, convert it with the C program ----
    if (is_binary) then
        print *, "Binary STL detected, converting..."
        call execute_command_line('./stl2ascii "' // trim(fname) // '" converted.stl', &
                                  exitstat=ios)
        if (ios /= 0) then
            print *, "Conversion failed. Is ./stl2ascii in this folder?"
            stop 1
        end if
        fname = "converted.stl"
    end if

    ! ---- print every vertex ----
    open(10, file=trim(fname), status='old', action='read', iostat=ios)
    if (ios /= 0) then
        print *, "Could not open: ", trim(fname)
        stop 1
    end if
    do
        read(10, '(A)', iostat=ios) line
        if(ios /= 0) exit
        line = adjustl(line)
        if(line(1:6) == 'vertex')then
            read(line(7:), *) x, y, z
            print *, x, y, z
        end if
    end do
    close(10)

end program
