program scaleles_ens
  !-----------------------------------------------------------------------------

  use mpi
  use common_mpi, only: &
     nprocs, &
     myrank
  use common_nml
  use common_scale, only: &
     set_common_conf
  use common_mpi_scale, only: &
     proc2mem, &
     nitmax, &
     set_mem_node_proc, &
     mpi_timer

  use scale_stdio, only: &
     H_LONG, &
     IO_L, &
     IO_FID_CONF, &
     IO_FID_LOG, &
     IO_FID_STDOUT
  use scale_process, only: &
     PRC_MPIstart, &
     PRC_UNIVERSAL_setup, &
     PRC_GLOBAL_setup, &
     PRC_MPIfinish, &
     PRC_MPIsplit, &
     PRC_MPIsplit_letkf, &
     PRC_UNIVERSAL_myrank, &
     PRC_DOMAIN_nlim, &
     PRC_GLOBAL_COMM_WORLD, &
     PRC_LOCAL_COMM_WORLD
  use mod_rm_driver

  implicit none

  integer :: it, its, ite, im, ierr
  character(7) :: stdoutf='-000000'

  character(len=H_LONG) :: confname
  character(len=H_LONG) :: confname_dummy

  integer :: universal_comm
  integer :: universal_nprocs
  logical :: universal_master
  integer :: universal_myrank
  integer :: global_comm
  integer :: local_comm
  integer :: intercomm_parent
  integer :: intercomm_child

  integer :: NUM_DOMAIN
  integer :: PRC_DOMAINS(PRC_DOMAIN_nlim)
  character(len=H_LONG) :: confname_dummy2(PRC_DOMAIN_nlim)

  character(len=6400) :: cmd1, cmd2, icmd
  character(len=10) :: myranks
  integer :: iarg

!-----------------------------------------------------------------------
! Initial settings
!-----------------------------------------------------------------------

  NUM_DOMAIN = 1
  PRC_DOMAINS = 0
  confname_dummy2 = ""

  ! start MPI
  call PRC_MPIstart( universal_comm ) ! [OUT]

  call mpi_timer('', 1)

  call PRC_UNIVERSAL_setup( universal_comm,   & ! [IN]
                            universal_nprocs, & ! [OUT]
                            universal_master  ) ! [OUT]
  universal_myrank = PRC_UNIVERSAL_myrank
  nprocs = universal_nprocs
  myrank = universal_myrank

  WRITE(6,'(A,I6.6,A,I6.6)') 'Hello from MYRANK ',universal_myrank,'/',universal_nprocs-1

  if (command_argument_count() >= 3) then
    write (myranks, '(I10)') universal_myrank
    call get_command_argument(3, icmd)
    cmd1 = 'bash ' // trim(icmd) // ' ensfcst_1' // ' ' // trim(myranks)
    cmd2 = 'bash ' // trim(icmd) // ' ensfcst_2' // ' ' // trim(myranks)
    do iarg = 4, command_argument_count()
      call get_command_argument(iarg, icmd)
      cmd1 = trim(cmd1) // ' ' // trim(icmd)
      cmd2 = trim(cmd2) // ' ' // trim(icmd)
    end do
  end if

  if (command_argument_count() >= 2) then
    call get_command_argument(2, icmd)
    if (trim(icmd) /= '') then
      WRITE(stdoutf(2:7), '(I6.6)') universal_myrank
!      WRITE(6,'(3A,I6.6)') 'STDOUT goes to ',trim(icmd)//stdoutf,' for MYRANK ', universal_myrank
      OPEN(6,FILE=trim(icmd)//stdoutf)
      WRITE(6,'(A,I6.6,2A)') 'MYRANK=',universal_myrank,', STDOUTF=',trim(icmd)//stdoutf
    end if
  end if

!-----------------------------------------------------------------------
! Pre-processing scripts
!-----------------------------------------------------------------------

  if (command_argument_count() >= 3) then
    write (6,'(A)') 'Run pre-processing scripts'
    write (6,'(A,I6.6,3A)') 'MYRANK ',universal_myrank,' is running a script: [', trim(cmd1), ']'
    call system(trim(cmd1))
  end if

  call mpi_timer('PRE_SCRIPT', 1, barrier=universal_comm)

!-----------------------------------------------------------------------

  call set_common_conf(universal_nprocs)
  call set_mem_node_proc(MEMBER+2)

  call mpi_timer('INITIALIZE', 1, barrier=universal_comm)

!-----------------------------------------------------------------------
! Run SCALE-RM
!-----------------------------------------------------------------------

  ! split MPI communicator for LETKF
  call PRC_MPIsplit_letkf( universal_comm,                   & ! [IN]
                           MEM_NP, nitmax, universal_nprocs, proc2mem, & ! [IN]
                           global_comm                       ) ! [OUT]

  if (global_comm /= MPI_COMM_NULL) then

    call PRC_GLOBAL_setup( .false.,    & ! [IN]
                           global_comm ) ! [IN]

    !--- split for nesting
    ! communicator split for nesting domains
    call PRC_MPIsplit( global_comm,      & ! [IN]
                       NUM_DOMAIN,       & ! [IN]
                       PRC_DOMAINS(:),   & ! [IN]
                       confname_dummy2(:), & ! [IN]
                       .false.,          & ! [IN]
                       .false.,          & ! [IN] flag bulk_split
                       .false.,          & ! [IN] no reordering
                       local_comm,       & ! [OUT]
                       intercomm_parent, & ! [OUT]
                       intercomm_child,  & ! [OUT]
                       confname_dummy    ) ! [OUT]

    if (MEMBER_ITER == 0) then
      its = 1
      ite = nitmax
    else
      its = MEMBER_ITER
      ite = MEMBER_ITER
    end if

    do it = its, ite
      im = proc2mem(1,it,universal_myrank+1)
      if (im >= 1 .and. im <= MEMBER_RUN) then
        if (CONF_FILES_SEQNUM) then
          call file_member_replace(im, CONF_FILES, confname)
        else
          if (im <= MEMBER) then
            call file_member_replace(im, CONF_FILES, confname)
          else if (im == MEMBER+1) then
            call file_member_replace(0, CONF_FILES, confname, memf_mean)
          else if (im == MEMBER+2) then
            call file_member_replace(0, CONF_FILES, confname, memf_mdet)
          end if
        end if
        WRITE(6,'(A,I6.6,2A)') 'MYRANK ',universal_myrank,' is running a model with configuration file: ', trim(confname)

        call scalerm ( local_comm, &
                       intercomm_parent, &
                       intercomm_child, &
                       trim(confname) )
      end if
    end do ! [ it = its, ite ]

  else ! [ global_comm /= MPI_COMM_NULL ]

    write (6, '(A,I6.6,A)') 'MYRANK=',universal_myrank,': This process is not used!'

  end if ! [ global_comm /= MPI_COMM_NULL ]

  ! Close logfile, configfile
  if ( IO_L ) then
    if( IO_FID_LOG /= IO_FID_STDOUT ) close(IO_FID_LOG)
  endif
  close(IO_FID_CONF)

  call mpi_timer('SCALE_RM', 1, barrier=universal_comm)

!-----------------------------------------------------------------------
! Post-processing scripts
!-----------------------------------------------------------------------

  if (command_argument_count() >= 3) then
    write (6,'(A)') 'Run post-processing scripts'
    write (6,'(A,I6.6,3A)') 'MYRANK ',universal_myrank,' is running a script: [', trim(cmd2), ']'
    call system(trim(cmd2))
  end if

  call mpi_timer('POST_SCRIPT', 1, barrier=universal_comm)

!-----------------------------------------------------------------------
! Finalize
!-----------------------------------------------------------------------

!  call PRC_MPIfinish

  call MPI_Finalize(ierr)

  stop
end program scaleles_ens
