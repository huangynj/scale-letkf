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

  integer, parameter :: maxlen = 6400
  character(len=maxlen) :: cmd, cmd1, cmd2
!  integer :: nprocs, myrank, ierr, pos

!-----------------------------------------------------------------------
! Initial settings
!-----------------------------------------------------------------------

  CALL initialize_mpi
  rtimer00 = MPI_WTIME()

  WRITE(stdoutf(6:11), '(I6.6)') myrank
  WRITE(6,'(3A,I6.6)') 'STDOUT goes to ',stdoutf,' for MYRANK ', myrank
  OPEN(6,FILE=stdoutf)
  WRITE(6,'(A,I6.6,2A)') 'MYRANK=',myrank,', STDOUTF=',stdoutf

! Pre-processing scripts
!-----------------------------------------------------------------------

  CALL MPI_BARRIER(MPI_COMM_WORLD,ierr)
  if (myrank == 0) then
    if (COMMAND_ARGUMENT_COUNT() < 5) then
      write(6,*) 'Error: Insufficient arguments.'
      stop
    else
      cmd1 = 'bash'
      cmd2 = 'bash'
      call get_command_argument(2, cmd)
      cmd1 = trim(cmd1) // ' ' // trim(cmd)
      cmd2 = trim(cmd2) // ' ' // trim(cmd)
      call get_command_argument(3, cmd)
      cmd1 = trim(cmd1) // ' ' // trim(cmd)
      cmd2 = trim(cmd2) // ' ' // trim(cmd)
      call get_command_argument(4, cmd)
      cmd1 = trim(cmd1) // ' ' // trim(cmd) // '_pre'
      cmd2 = trim(cmd2) // ' ' // trim(cmd) // '_post'
      call get_command_argument(5, cmd)
      cmd1 = trim(cmd1) // ' ' // trim(cmd)
      cmd2 = trim(cmd2) // ' ' // trim(cmd)
    endif

    write(6,*) trim(cmd1)
    call system(trim(cmd1))
  end if

!-----------------------------------------------------------------------

  CALL MPI_BARRIER(MPI_COMM_WORLD,ierr)
  call set_common_conf

  !
  ! Set up node and process distribution
  !
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


!-----------------------------------------------------------------------
! Finalize
!-----------------------------------------------------------------------

! Post-processing scripts
!-----------------------------------------------------------------------

  CALL MPI_BARRIER(MPI_COMM_WORLD,ierr)
  if (myrank == 0) then
    write(6,*) trim(cmd2)
    call system(trim(cmd2))
  end if

!-----------------------------------------------------------------------

  CALL MPI_BARRIER(MPI_COMM_WORLD,ierr)
  rtimer = MPI_WTIME()
  WRITE(6,timer_fmt) '### TIMER(SCALE_LES):',rtimer-rtimer00
  rtimer00=rtimer

  CALL finalize_mpi

!-----------------------------------------------------------------------

  stop
end program scaleles_ens
