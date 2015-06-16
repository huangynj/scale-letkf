program scaleles_ens
  !-----------------------------------------------------------------------------

  USE common
  USE common_mpi
  USE common_scale
  USE common_mpi_scale

  use scale_process, only: &
     PRC_MPIstart,      &
     PRC_MPIsplit_letkf,&
     LOCAL_COMM_WORLD
  use mod_les_driver

  implicit none

  REAL(r_dble) :: rtimer00,rtimer
  INTEGER :: ierr, it, im
  CHARACTER(11) :: stdoutf='NOUT-000000'
  CHARACTER(11) :: timer_fmt='(A30,F10.2)'

  CHARACTER(len=H_LONG) :: confname='0000/run.conf'

  integer :: LOCAL_myrank, LOCAL_nmax

  character(len=6400) :: cmd, icmd
  character(len=10) :: myranks

!-----------------------------------------------------------------------
! Initial settings
!-----------------------------------------------------------------------

  CALL initialize_mpi
  rtimer00 = MPI_WTIME()

  WRITE(stdoutf(6:11), '(I6.6)') myrank
  WRITE(6,'(3A,I6.6)') 'STDOUT goes to ',stdoutf,' for MYRANK ', myrank
  OPEN(6,FILE=stdoutf)
  WRITE(6,'(A,I6.6,2A)') 'MYRANK=',myrank,', STDOUTF=',stdoutf

!-----------------------------------------------------------------------
! Pre-processing scripts
!-----------------------------------------------------------------------

  if (COMMAND_ARGUMENT_COUNT() >= 5) then
    write(6,'(A)') 'Run pre-processing scripts'
    cmd = 'bash'
    call get_command_argument(2, icmd)
    cmd = trim(cmd) // ' ' // trim(icmd)
    call get_command_argument(3, icmd)
    cmd = trim(cmd) // ' ' // trim(icmd) // '_pre'
    call get_command_argument(4, icmd)
    cmd = trim(cmd) // ' ' // trim(icmd)
    call get_command_argument(5, icmd)
    cmd = trim(cmd) // ' ' // trim(icmd)
    write (myranks, '(I10)') myrank
    cmd = trim(cmd) // ' ' // trim(myranks)

    WRITE(6,'(A,I6.6,3A)') 'MYRANK ',myrank,' is running a script: [', trim(cmd), ']'
    call system(trim(cmd))
  end if

  CALL MPI_BARRIER(MPI_COMM_WORLD,ierr)
  rtimer = MPI_WTIME()
  WRITE(6,timer_fmt) '### TIMER(PRE_SCRIPT):',rtimer-rtimer00
  rtimer00=rtimer

!-----------------------------------------------------------------------

  call set_common_conf

  call set_mem_node_proc(MEMBER+1,NNODES,PPN,MEM_NODES,MEM_NP)

  CALL MPI_BARRIER(MPI_COMM_WORLD,ierr)
  rtimer = MPI_WTIME()
  WRITE(6,timer_fmt) '### TIMER(INITIALIZE):',rtimer-rtimer00
  rtimer00=rtimer

!-----------------------------------------------------------------------
! Run SCALE-LES
!-----------------------------------------------------------------------

  if (myrank_mem_use) then

!    if (MEM_NP /= PRC_NUM_X * PRC_NUM_Y) then
!      write(6,'(A,I10)') 'MEM_NP    = ', MEM_NP
!      write(6,'(A,I10)') 'PRC_NUM_X = ', PRC_NUM_X
!      write(6,'(A,I10)') 'PRC_NUM_Y = ', PRC_NUM_Y
!      write(6,'(A)') 'MEM_NP should be equal to PRC_NUM_X * PRC_NUM_Y.'
!      stop
!    end if

    ! start SCALE MPI
    call PRC_MPIstart

    ! split MPI communicator for LETKF
    call PRC_MPIsplit_letkf(MEM_NP, nitmax, nprocs, proc2mem, myrank, &
                            LOCAL_myrank, LOCAL_nmax)

    do it = 1, nitmax
      im = proc2mem(1,it,myrank+1)
      if (im >= 1 .and. im <= MEMBER+1) then

        if (im == MEMBER+1) then
          WRITE(confname(1:4),'(A4)') 'mean'
        else
          WRITE(confname(1:4),'(I4.4)') proc2mem(1,it,myrank+1)
        end if

        WRITE(6,'(A,I6.6,2A)') 'MYRANK ',myrank,' is running a model with configuration file: ', confname

        call scaleles ( LOCAL_COMM_WORLD,   &
                        MPI_COMM_NULL,    &
                        MPI_COMM_NULL,     &
                        confname )
      end if
    end do ! [ it = 1, nitmax ]

  else ! [ myrank_mem_use ]

    write (6, '(A,I6.6,A)') 'MYRANK=',myrank,': This process is not used!'

  end if ! [ myrank_mem_use ]

  CALL MPI_BARRIER(MPI_COMM_WORLD,ierr)
  rtimer = MPI_WTIME()
  WRITE(6,timer_fmt) '### TIMER(SCALE_LES):',rtimer-rtimer00
  rtimer00=rtimer

!-----------------------------------------------------------------------
! Post-processing scripts
!-----------------------------------------------------------------------

  if (COMMAND_ARGUMENT_COUNT() >= 5) then
    write(6,'(A)') 'Run post-processing scripts'
    cmd = 'bash'
    call get_command_argument(2, icmd)
    cmd = trim(cmd) // ' ' // trim(icmd)
    call get_command_argument(3, icmd)
    cmd = trim(cmd) // ' ' // trim(icmd) // '_post'
    call get_command_argument(4, icmd)
    cmd = trim(cmd) // ' ' // trim(icmd)
    call get_command_argument(5, icmd)
    cmd = trim(cmd) // ' ' // trim(icmd)
!    write (myranks, '(I10)') myrank
    cmd = trim(cmd) // ' ' // trim(myranks)

    WRITE(6,'(A,I6.6,3A)') 'MYRANK ',myrank,' is running a script: [', trim(cmd), ']'
    call system(trim(cmd))
  end if

  CALL MPI_BARRIER(MPI_COMM_WORLD,ierr)
  rtimer = MPI_WTIME()
  WRITE(6,timer_fmt) '### TIMER(POST_SCRIPT):',rtimer-rtimer00
  rtimer00=rtimer

!-----------------------------------------------------------------------
! Finalize
!-----------------------------------------------------------------------

  CALL finalize_mpi

  stop
end program scaleles_ens