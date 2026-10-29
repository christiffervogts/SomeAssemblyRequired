module slicer
    use, intrinsic :: iso_fortran_env, only: real64, real32, int16, int32, int64
    implicit none

    integer, parameter :: wp = real64      !working precision, only change it here

    !2D point, basically struct point { double x, y; } from C
    type :: point
        real(wp) :: x = 0.0_wp
        real(wp) :: y = 0.0_wp
    end type point

contains

subroutine SliceAtHeight(h, nverts, q, x, y, z, points, npts, loop_start, nloops)
    real(wp), intent(in) :: h                   !height of the slice
    integer,  intent(in) :: nverts              !total vertices, 3 per triangle
    integer,  intent(in) :: q                   !quality, points per mm
    real(wp), intent(in) :: x(:), y(:), z(:)    !vertex coordinates
    type(point), allocatable, intent(out) :: points(:)
    integer, allocatable, intent(out) :: loop_start(:)
    integer, intent(out) :: npts, nloops

    real(wp), parameter :: tol = 1.0e-4_wp     !how close two endpoints have to be to count as the same point (mm)
    real(wp), allocatable :: sx1(:), sy1(:), sx2(:), sy2(:)
    integer, allocatable :: order(:), loop_first(:), cnt(:), startpos(:)
    logical, allocatable :: used(:)

    integer :: ntri, t, e, nseg, k, i, j, m, cur, nxt, best, v(3)
    integer :: ea(3), eb(3), nc, lo, hi
    real(wp) :: qx(2), qy(2), s, f, len_seg
    real(wp) :: ux, uy, uz, wx, wy, wz, nx, ny, dx, dy
    logical :: above(3)

    ntri = nverts / 3
    allocate(sx1(ntri), sy1(ntri), sx2(ntri), sy2(ntri))
    ea = [1, 2, 3]
    eb = [2, 3, 1]

    !step 1: find the segment where each triangle crosses z = h
    nseg = 0
    do t = 1, ntri
        v = [3*t-2, 3*t-1, 3*t]
        above = z(v) >= h
        if (all(above) .or. .not. any(above)) cycle

        nc = 0
        do e = 1, 3
            i = v(ea(e));  j = v(eb(e))
            if (above(ea(e)) .neqv. above(eb(e))) then
                !always interpolate from the lower z vertex so two triangles sharing an edge get the exact same point
                if (z(i) <= z(j)) then
                    lo = i;  hi = j
                else
                    lo = j;  hi = i
                end if
                s = (h - z(lo)) / (z(hi) - z(lo))
                nc = nc + 1
                qx(nc) = x(lo) + s*(x(hi) - x(lo))
                qy(nc) = y(lo) + s*(y(hi) - y(lo))
            end if
        end do
        if (nc /= 2) cycle

        !skip zero length segments, happens when the plane just touches a vertex
        if (sqrt((qx(2)-qx(1))**2 + (qy(2)-qy(1))**2) < tol) cycle

        !triangle normal (just the xy part) from the vertex winding
        ux = x(v(2))-x(v(1)); uy = y(v(2))-y(v(1)); uz = z(v(2))-z(v(1))
        wx = x(v(3))-x(v(1)); wy = y(v(3))-y(v(1)); wz = z(v(3))-z(v(1))
        nx = uy*wz - uz*wy
        ny = uz*wx - ux*wz

        !direction that keeps the inside on the left (CCW for outer loops)
        dx = -ny;  dy = nx
        nseg = nseg + 1
        if ((qx(2)-qx(1))*dx + (qy(2)-qy(1))*dy >= 0.0_wp) then
            sx1(nseg) = qx(1); sy1(nseg) = qy(1)
            sx2(nseg) = qx(2); sy2(nseg) = qy(2)
        else
            sx1(nseg) = qx(2); sy1(nseg) = qy(2)
            sx2(nseg) = qx(1); sy2(nseg) = qy(1)
        end if
    end do

    npts = 0;  nloops = 0
    if (nseg == 0) then
        allocate(points(0), loop_start(0))
        !HERE nothing at this height so control goes back to main with no points
        return
    end if

    !step 2: chain the segments into loops, each one starts at the lowest point left
    allocate(used(nseg), order(nseg), loop_first(nseg))
    used = .false.
    k = 0
    do while (k < nseg)
        best = 0
        do i = 1, nseg
            if (used(i)) cycle
            if (best == 0) then
                best = i
            else if (sy1(i) < sy1(best) .or. &
                    (sy1(i) == sy1(best) .and. sx1(i) < sx1(best))) then
                best = i
            end if
        end do

        nloops = nloops + 1
        loop_first(nloops) = k + 1
        cur = best
        do
            used(cur) = .true.
            k = k + 1
            order(k) = cur
            nxt = 0
            do j = 1, nseg
                if (used(j)) cycle
                if (abs(sx1(j)-sx2(cur)) < tol .and. &
                    abs(sy1(j)-sy2(cur)) < tol) then
                    nxt = j
                    exit
                end if
            end do
            if (nxt == 0) exit      !loop closed (or theres a gap in the mesh)
            cur = nxt
        end do
    end do

    !step 3: turn each segment into points, how many depends on the quality
    allocate(cnt(nseg), startpos(nseg))
    do k = 1, nseg
        i = order(k)
        len_seg = sqrt((sx2(i)-sx1(i))**2 + (sy2(i)-sy1(i))**2)
        cnt(k) = max(1, ceiling(len_seg * real(q, wp)))
    end do

    startpos(1) = 1
    do k = 2, nseg
        startpos(k) = startpos(k-1) + cnt(k-1)
    end do
    npts = sum(cnt)

    allocate(points(npts), loop_start(nloops))
    do k = 1, nseg
        i = order(k)
        do m = 0, cnt(k) - 1
            f = real(m, wp) / real(cnt(k), wp)   !the end point belongs to the next segment
            points(startpos(k)+m)%x = sx1(i) + f*(sx2(i) - sx1(i))
            points(startpos(k)+m)%y = sy1(i) + f*(sy2(i) - sy1(i))
        end do
    end do
    do i = 1, nloops
        loop_start(i) = startpos(loop_first(i))
    end do

    !HERE all the points are stored in points(1:npts) so control goes back to main
end subroutine SliceAtHeight

!reads an STL (binary or ascii) into x, y, z, 3 vertices per triangle
subroutine read_stl(fname, x, y, z, nverts, ok)
    character(len=*), intent(in) :: fname
    real(wp), allocatable, intent(out) :: x(:), y(:), z(:)
    integer, intent(out) :: nverts
    logical, intent(out) :: ok                !false if the file is missing or cant be read

    integer :: u, ios, ntri, t, k, n
    integer(int64) :: fsize
    integer(int32) :: ntri32
    integer(int16) :: attr
    real(real32) :: f(12)                     !normal (3) then the 3 vertices (9)
    character(len=256) :: line
    real(wp) :: vx, vy, vz
    logical :: ex, is_binary

    ok = .false.
    nverts = 0
    inquire(file=fname, exist=ex, size=fsize)
    if (.not. ex) return

    open(newunit=u, file=fname, access='stream', form='unformatted', status='old', &
         action='read', convert='little_endian', iostat=ios)
    if (ios /= 0) return

    !binary STL = 80 byte header, a triangle count, then 50 bytes per triangle, so the file size gives it away
    is_binary = .false.
    if (fsize >= 84) then
        read(u, pos=81, iostat=ios) ntri32
        if (ios == 0) is_binary = (fsize == 84_int64 + 50_int64*int(ntri32, int64))
    end if

    if (is_binary) then
        ntri = int(ntri32)
        nverts = 3*ntri
        allocate(x(nverts), y(nverts), z(nverts))
        do t = 1, ntri
            read(u, pos=85_int64 + 50_int64*(t-1), iostat=ios) f, attr
            if (ios /= 0) then
                close(u);  return
            end if
            do k = 1, 3
                x(3*t-3+k) = real(f(3*k+1), wp)
                y(3*t-3+k) = real(f(3*k+2), wp)
                z(3*t-3+k) = real(f(3*k+3), wp)
            end do
        end do
        close(u)
    else
        !ascii STL, first pass counts the vertex lines, second pass reads them
        close(u)
        open(newunit=u, file=fname, status='old', action='read', iostat=ios)
        if (ios /= 0) return
        n = 0
        do
            read(u, '(a)', iostat=ios) line
            if (ios /= 0) exit
            line = adjustl(line)
            if (line(1:6) == 'vertex' .or. line(1:6) == 'VERTEX') n = n + 1
        end do
        if (n == 0 .or. mod(n, 3) /= 0) then
            close(u);  return
        end if
        rewind(u)
        nverts = n
        allocate(x(n), y(n), z(n))
        k = 0
        do
            read(u, '(a)', iostat=ios) line
            if (ios /= 0) exit
            line = adjustl(line)
            if (line(1:6) == 'vertex' .or. line(1:6) == 'VERTEX') then
                read(line(7:), *, iostat=ios) vx, vy, vz
                if (ios /= 0) then
                    close(u);  return
                end if
                k = k + 1
                x(k) = vx;  y(k) = vy;  z(k) = vz
            end if
        end do
        close(u)
    end if

    ok = .true.
end subroutine read_stl

!checks if the part can be slid around (just x and y, z doesnt matter) so every point on every layer lands in the ring the arm can reach
!rin and rout are the inner and outer edge of that ring (mm), tx and ty are how far to slide it, ok is false if there is no way it fits
subroutine fit_to_reach(x, y, z, nverts, layer_height, rin, rout, tx, ty, ok)
    real(wp), intent(in)  :: x(:), y(:), z(:)
    integer,  intent(in)  :: nverts
    real(wp), intent(in)  :: layer_height, rin, rout
    real(wp), intent(out) :: tx, ty
    logical,  intent(out) :: ok

    real(wp), parameter :: cell   = 1.0_wp       !size of the squares the outline gets boiled down to (mm)
    real(wp), parameter :: margin = 1.5_wp       !everything has to stay this far inside the ring edges (mm)
    real(wp), parameter :: step   = 2.0_wp       !how far apart the positions we try are (mm)
    logical, allocatable :: occ(:,:), outside(:,:)
    integer, allocatable :: stkx(:), stky(:)
    integer, parameter :: dxs(4) = [1, -1, 0, 0], dys(4) = [0, 0, 1, -1]
    integer :: sp, qx0, qy0, nxi, nyi, d
    real(wp), allocatable :: cx(:), cy(:)
    type(point), allocatable :: pts(:)
    integer, allocatable :: ls(:)
    real(wp) :: xmin, xmax, ymin, ymax, zmin, zmax, h, xc, yc, sx, sy, best, clr, btx, bty
    integer :: nx, ny, ix, iy, nlayers, layer, np, nl, i, j, m, ng
    logical :: found

    ok = .false.
    tx = 0.0_wp;  ty = 0.0_wp

    xmin = minval(x(1:nverts));  xmax = maxval(x(1:nverts))
    ymin = minval(y(1:nverts));  ymax = maxval(y(1:nverts))
    zmin = minval(z(1:nverts));  zmax = maxval(z(1:nverts))

    !wider than the whole reach circle, no point even trying
    if (xmax - xmin > 2.0_wp*rout .or. ymax - ymin > 2.0_wp*rout) return

    !slice every layer (same heights as the real run) and mark which squares have an outline in them
    nx = int((xmax - xmin) / cell) + 1
    ny = int((ymax - ymin) / cell) + 1
    allocate(occ(0:nx+1, 0:ny+1))     !one extra ring of empty squares around the edge
    occ = .false.
    nlayers = max(1, ceiling((zmax - zmin) / layer_height - 1.0e-9_wp))
    do layer = 1, nlayers
        h = zmin + (real(layer, wp) - 0.5_wp) * layer_height
        call SliceAtHeight(h, nverts, 1, x, y, z, pts, np, ls, nl)
        do i = 1, np
            ix = min(nx, max(1, int((pts(i)%x - xmin) / cell) + 1))
            iy = min(ny, max(1, int((pts(i)%y - ymin) / cell) + 1))
            occ(ix, iy) = .true.
        end do
    end do

    m = count(occ)
    if (m == 0) then               !nothing to print at all, so nothing to fit
        ok = .true.
        return
    end if
    allocate(cx(m), cy(m))
    m = 0
    do iy = 1, ny
        do ix = 1, nx
            if (occ(ix, iy)) then
                m = m + 1
                cx(m) = xmin + (real(ix, wp) - 0.5_wp) * cell
                cy(m) = ymin + (real(iy, wp) - 0.5_wp) * cell
            end if
        end do
    end do

    !flood fill from the outside edge, anything the flood cant reach is inside a loop of the outline
    !the shoulder cant be inside the part (the arm base would be sitting in the print) so we need to know where that is
    allocate(outside(0:nx+1, 0:ny+1), stkx((nx+2)*(ny+2)), stky((nx+2)*(ny+2)))
    outside = .false.
    outside(0, 0) = .true.
    sp = 1;  stkx(1) = 0;  stky(1) = 0
    do while (sp > 0)
        qx0 = stkx(sp);  qy0 = stky(sp);  sp = sp - 1
        do d = 1, 4
            nxi = qx0 + dxs(d);  nyi = qy0 + dys(d)
            if (nxi < 0 .or. nxi > nx+1 .or. nyi < 0 .or. nyi > ny+1) cycle
            if (occ(nxi, nyi) .or. outside(nxi, nyi)) cycle
            outside(nxi, nyi) = .true.
            sp = sp + 1;  stkx(sp) = nxi;  stky(sp) = nyi
        end do
    end do

    !already fits where it is? then dont touch it
    if (clearance(0.0_wp, 0.0_wp, margin) >= margin .and. .not. encloses(0.0_wp, 0.0_wp)) then
        ok = .true.
        return
    end if

    !otherwise try putting the middle of the part at a bunch of spots and keep the one that sits furthest from both edges
    xc = 0.5_wp * (xmin + xmax)
    yc = 0.5_wp * (ymin + ymax)
    best = margin
    found = .false.
    ng = ceiling(rout / step)
    do i = -ng, ng
        sx = real(i, wp) * step
        do j = -ng, ng
            sy = real(j, wp) * step
            if (sx**2 + sy**2 > rout**2) cycle
            if (encloses(sx - xc, sy - yc)) cycle     !shoulder would end up inside the part
            clr = clearance(sx - xc, sy - yc, best)
            if (clr >= best) then
                best = clr
                btx = sx - xc;  bty = sy - yc
                found = .true.
            end if
        end do
    end do

    if (found) then
        tx = btx;  ty = bty
        ok = .true.
    end if

contains

    !how far the closest outline square is from either edge of the ring after sliding by (ttx, tty)
    !quits early once its worse than thresh because that spot is already no good
    function clearance(ttx, tty, thresh) result(c)
        real(wp), intent(in) :: ttx, tty, thresh
        real(wp) :: c, r
        integer :: k
        c = huge(1.0_wp)
        do k = 1, m
            r = sqrt((cx(k) + ttx)**2 + (cy(k) + tty)**2)
            c = min(c, r - rin, rout - r)
            if (c < thresh) return
        end do
    end function clearance

    !true if the shoulder (the origin) would be inside a loop of the outline after sliding by (ttx, tty)
    function encloses(ttx, tty) result(r)
        real(wp), intent(in) :: ttx, tty
        logical :: r
        real(wp) :: fx, fy
        r = .false.
        fx = (-ttx - xmin) / cell                 !where the shoulder lands on the squares, in square units
        fy = (-tty - ymin) / cell
        if (fx < 0.0_wp .or. fx >= real(nx, wp) .or. fy < 0.0_wp .or. fy >= real(ny, wp)) return
        r = .not. outside(int(fx) + 1, int(fy) + 1)
    end function encloses

end subroutine fit_to_reach

end module slicer


program main
    use slicer
    implicit none

    real(wp), allocatable :: x(:), y(:), z(:)
    type(point), allocatable :: points(:)
    integer, allocatable :: loop_start(:)
    integer :: nverts, npts, nloops, i, ios, k
    logical :: ok

    logical :: visual_input = .true.              !true prints the vertices, the points on each layer and the instructions, false only prints the important stuff
    character(len=256) :: fname                   !the STL file the user gives
    character(len=256) :: base                    !the STL name with the folder and the .stl taken off
    character(len=270) :: outname                 !base + .NNGCC
    integer :: q                                  !quality, points per mm
    real(wp) :: nozzle                            !nozzle size (mm), also used as the layer height
    real(wp) :: layer_height
    real(wp) :: L1, L2                            !link lengths, asked in inches then converted to mm so they match the mesh
    real(wp), parameter :: steps_per_rad = 64.0_wp    !not sure this is right, CHECK it against the motors/gearing
    real(wp) :: tx, ty                            !how far the part got slid to fit in the reach area

    real(wp) :: h, zmin, zmax
    integer :: nlayers, layer

    integer :: u, cur1, cur2                      !u is the output file, cur is where each motor is right now (in steps)
    logical :: have_pos = .false.                 !false until the arm has a starting position
    integer :: tot_loops = 0, tot_cmds = 0        !running totals so we can print a summary at the end

    !---- ask the user for everything ----
    write(*, '(a)', advance='no') 'STL file (assumed to be in mm): '
    read(*, '(a)') fname
    fname = trim(adjustl(fname))
    call read_stl(trim(fname), x, y, z, nverts, ok)
    if (.not. ok) stop 'couldnt read that STL file (missing, empty, or not a valid STL)'

    !output is named after the STL, chop off the folder part and the extension
    base = fname
    k = max(index(base, '/', back=.true.), index(base, '\', back=.true.))
    if (k > 0) base = base(k+1:)
    k = index(base, '.', back=.true.)
    if (k > 1) base = base(1:k-1)
    outname = trim(base) // '.NNGCC'

    write(*, '(a)', advance='no') 'quality (points per mm, whole number): '
    read(*, *, iostat=ios) q
    if (ios /= 0 .or. q < 1) stop 'quality has to be a whole number of at least 1'

    write(*, '(a)', advance='no') 'nozzle size (mm): '
    read(*, *, iostat=ios) nozzle
    if (ios /= 0 .or. nozzle <= 0.0_wp) stop 'nozzle size has to be a positive number'
    layer_height = nozzle                          !using the nozzle size as the layer height, change this line if you want something like 0.8*nozzle

    write(*, '(a)', advance='no') 'link 1 length (in): '
    read(*, *, iostat=ios) L1
    if (ios /= 0 .or. L1 <= 0.0_wp) stop 'link 1 has to be a positive number'

    write(*, '(a)', advance='no') 'link 2 length (in): '
    read(*, *, iostat=ios) L2
    if (ios /= 0 .or. L2 <= 0.0_wp) stop 'link 2 has to be a positive number'

    L1 = L1 * 25.4_wp                              !inches to mm
    L2 = L2 * 25.4_wp

    !---- can the part be slid into the area the arm reaches? if not quit right now ----
    call fit_to_reach(x, y, z, nverts, layer_height, abs(L1 - L2), L1 + L2, tx, ty, ok)
    if (.not. ok) then
        print '(a)', 'this part cant fit in the area the arm can reach, quitting.'
        print '(a,f8.1,a,f8.1,a)', '  the arm reaches a ring from ', abs(L1 - L2), ' mm to ', L1 + L2, ' mm around the shoulder'
        print '(a,f8.1,a,f8.1,a)', '  the part is ', maxval(x) - minval(x), ' mm wide and ', maxval(y) - minval(y), ' mm deep'
        stop 'try a smaller part, or longer links'
    end if
    if (abs(tx) > 1.0e-9_wp .or. abs(ty) > 1.0e-9_wp) then
        x = x + tx
        y = y + ty
        print '(a,f9.3,a,f9.3,a)', 'moved the part by x = ', tx, ' mm, y = ', ty, ' mm so it fits'
    else
        print '(a)', 'the part already fits where it is, not moving it'
    end if

    !first print every vertex
    if (visual_input) then
        print '(a)', 'vertices (index, x, y, z):'
        do i = 1, nverts
            print '(i6, 3f12.4)', i, x(i), y(i), z(i)
        end do
    end if

    zmin = minval(z)
    zmax = maxval(z)
    nlayers = max(1, ceiling((zmax - zmin) / layer_height - 1.0e-9_wp))   !the tiny number stops rounding from adding an extra layer
    if (visual_input) print '(a,i0,a,f8.3,a,f8.3)', 'layers = ', nlayers, ', z from ', zmin, ' to ', zmax

    open(newunit=u, file=trim(outname), access="stream", form="unformatted", status="replace", convert='little_endian')   !only open it once, otherwise replace wipes it every loop

    do layer = 1, nlayers
        !slice in the middle of the layer, slicing exactly on the bottom or top face gives nothing
        h = zmin + (real(layer, wp) - 0.5_wp) * layer_height

        call SliceAtHeight(h, nverts, q, x, y, z, points, npts, loop_start, nloops)

        !HERE all the points for this layer are done, control is back in main
        if (visual_input) then
            print '(a,i0,a,f8.3,a,i0,a,i0,a)', 'layer ', layer, ', h = ', h, ', npts = ', npts, ', nloops = ', nloops, ':'
            do i = 1, npts
                print '(i6, 2f12.4)', i, points(i)%x, points(i)%y
            end do
            print '(a)', 'instructions:'
        end if

        write(u) 'C', 64_int64                      !start of the layer is a C064 now (the letter C, 7 bits in 1 byte, then 64 as a 64 bit number)
        if (visual_input) print '(a)', 'C064'
        call points2NNGCC
    end do

    close(u)
    print '(a,i0,a,i0,a,i0,a)', 'wrote ' // trim(outname) // ': ', nlayers, ' layers, ', &
          tot_loops, ' loops, ', tot_cmds, ' move commands'

contains

    !two link planar inverse kinematics for one point, this is the copy pasted block turned into one routine
    subroutine ik(px, py, th1, th2, ok)
        real(wp), intent(in)  :: px, py
        real(wp), intent(out) :: th1, th2     !th1 is the shoulder (absolute), th2 is the elbow (relative to link 1)
        logical,  intent(out) :: ok           !false if the point cant be reached
        real(wp) :: d, C, C0

        d  = sqrt(px**2 + py**2)               !d is the distance from the origin to the point
        ok = .not. (d > L1 + L2 .or. d < abs(L1 - L2) .or. d < 1.0e-9_wp)
        th1 = 0.0_wp;  th2 = 0.0_wp
        if (.not. ok) return

        !C is the angle at the shoulder between link 1 and the line to the point, C0 is the angle of that line itself
        !the clamp is so rounding right at the edge of reach cant make acos return NaN
        C  = acos(max(-1.0_wp, min(1.0_wp, (L1**2 + d**2 - L2**2) / (2.0_wp*L1*d))))
        C0 = atan2(py, px)
        th1 = C0 - C                                    !elbow down, use C0 + C for elbow up
        th2 = atan2(py - L1*sin(th1), px - L1*cos(th1)) - th1

        !wrap both to (-pi, pi] so a move never jumps a whole turn
        th1 = atan2(sin(th1), cos(th1))
        th2 = atan2(sin(th2), cos(th2))
    end subroutine ik

    !turns the points on the current layer into motor commands, one loop at a time, the arm keeps its position from the last layer
    subroutine points2NNGCC
        real(wp) :: th1, th2
        integer :: li, lo, hi, pointIndex, tgt1, tgt2, steps1, steps2   !li is the loop number, lo and hi are its first and last point, tgt is where the motor needs to go
        logical :: ok, skip1
        character(len=16) :: s1, s2
        character(len=1)  :: dir1, dir2      !capital or lowercase letter, tells the arduino which way to turn
        character(len=64) :: msg

        if (npts == 0) return

        skip1 = .false.
        if (.not. have_pos) then
            !very first point ever, assuming the arm starts sitting on it
            call ik(points(1)%x, points(1)%y, th1, th2, ok)
            if (.not. ok) then
                print *, 'point 1 is out of reach, nothing written for this layer'
                return
            end if
            cur1 = nint(th1 * steps_per_rad)
            cur2 = nint(th2 * steps_per_rad)
            have_pos = .true.
            skip1 = .true.
        end if

        do li = 1, nloops
            lo = loop_start(li)
            if (li < nloops) then
                hi = loop_start(li + 1) - 1         !the loop ends right before the next one starts
            else
                hi = npts
            end if
            if (li == 1 .and. skip1) lo = lo + 1     !the arm is already sitting on point 1

            !from the second layer on the first point of a loop is also a move, the arm travels there from where it was
            do pointIndex = lo, hi
                call ik(points(pointIndex)%x, points(pointIndex)%y, th1, th2, ok)
                if (.not. ok) then
                    print '(a,i0,a)', 'point ', pointIndex, ' out of reach, skipped'
                    cycle
                end if

                !keep track of the total step position so the rounding doesnt add up over time
                tgt1 = nint(th1 * steps_per_rad)
                tgt2 = nint(th2 * steps_per_rad)
                steps1 = tgt1 - cur1                  !new minus old, so positive is the direction its actually moving
                steps2 = tgt2 - cur2
                cur1 = tgt1;  cur2 = tgt2
                if (steps1 == 0 .and. steps2 == 0) cycle

                dir1 = merge('A', 'a', steps1 > 0)    !if a motor spins backwards just swap the letters
                dir2 = merge('B', 'b', steps2 > 0)
                write(s1, '(I0)') abs(steps1)
                write(s2, '(I0)') abs(steps2)
                msg = dir1 // trim(s1) // dir2 // trim(s2)

                write(u) dir1, int(abs(steps1), int64), dir2, int(abs(steps2), int64)   !binary, letter (7 bits in 1 byte) then 64 bit step count, twice
                tot_cmds = tot_cmds + 1
                if (visual_input) print '(a)', trim(msg)
            end do

            write(u) 'C', 64_int64                    !end of this loop, one C064 every time (the letter C, 7 bits in 1 byte, then 64 as a 64 bit number)
            tot_loops = tot_loops + 1
            if (visual_input) print '(a)', 'C064'
        end do
    end subroutine points2NNGCC

end program main
