#!/bin/bash
#===============================================================================
#
#  Wrap fcst.sh in a K-computer job script and run it.
#
#  October 2014, created,                 Guo-Yuan Lien
#
#-------------------------------------------------------------------------------
#
#  Usage:
#    fcst_K.sh [STIME ETIME MEMBERS CYCLE CYCLE_SKIP IF_VERF IF_EFSO ISTEP FSTEP]
#
#===============================================================================

cd "$(dirname "$0")"

#===============================================================================
# Configuration

. config.all
(($? != 0)) && exit $?
. config.fcst
(($? != 0)) && exit $?

. src/func_distribute.sh
. src/func_datetime.sh
. src/func_util.sh
. src/func_fcst.sh

#-------------------------------------------------------------------------------

setting

jobscrp='fcst_job.sh'

#-------------------------------------------------------------------------------

echo

for vname in DIR OUTDIR ANLWRF OBS OBSNCEP MEMBER NNODES PPN \
             FCSTLEN FCSTOUT EFSOFLEN EFSOFOUT FOUT_OPT \
             STIME ETIME MEMBERS CYCLE CYCLE_SKIP IF_VERF IF_EFSO ISTEP FSTEP; do
  printf '  %-10s = %s\n' $vname ${!vname}
done

echo
echo "Create a job script '$jobscrp'..."
echo

#===============================================================================

#mkdir -p $LOGDIR

#if ((MACHINE_TYPE == 10 && PREP == 0)); then
#  mkdir -p $TMP/runlog
#  sleep 0.01s
##  exec 2>> $TMP/runlog/${myname1}.err
#else
#  sleep 0.01s
#####exec 2>> $LOGDIR/${myname1}.err
#fi

#===============================================================================
# Determine the distibution schemes

safe_init_tmpdir $TMPS

declare -a procs
declare -a mem2proc
declare -a node
declare -a name_m
declare -a node_m

NODEFILE_DIR="$TMPS/node"
safe_init_tmpdir $NODEFILE_DIR
distribute_fcst "$MEMBERS" $CYCLE - $NODEFILE_DIR

#===============================================================================




cp $SCRP_DIR/config.all $TMPS


if ((TMPDAT_MODE == 3 || TMPRUN_MODE == 3 || TMPOUT_MODE == 3)); then
  USE_RANKDIR=1
  echo "USE_RANKDIR=1" >> $TMPS/config.all
  echo "SCRP_DIR='.'" >> $TMPS/config.all
  echo "LOGDIR='./log'" >> $TMPS/config.all
else
  USE_RANKDIR=0
  echo "USE_RANKDIR=0" >> $TMPS/config.all
  echo "SCRP_DIR='.'" >> $TMPS/config.all
  echo "LOGDIR='./log'" >> $TMPS/config.all
fi

echo "NODEFILE_DIR='./node'" >> $TMPS/config.all



STAGING_DIR="$TMPS/staging"

safe_init_tmpdir $STAGING_DIR
staging_list


#### walltime limit as a variable!!!
#### rscgrp automatically determined!!!
#### OMP_NUM_THREADS, PARALLEL as a variable!!!
#### ./runscp ./runlog as a variable

cat > $jobscrp << EOF
#!/bin/sh
##PJM -g ra000015
#PJM --rsc-list "node=$NNODES"
#PJM --rsc-list "elapse=00:01:00"
#PJM --rsc-list "rscgrp=small"
##PJM --rsc-list "node-quota=29GB"
#PJM --mpi "shape=$NNODES"
#PJM --mpi "proc=$((NNODES*PPN))"
#PJM --mpi assign-online-node
#PJM --stg-transfiles all
EOF

if ((USE_RANKDIR == 1)); then
  echo "#PJM --mpi \"use-rankdir\"" >> $jobscrp
fi

bash $SCRP_DIR/src/stage_K.sh $STAGING_DIR >> $jobscrp

#########################
cat >> $jobscrp << EOF
#PJM --stgout "./* /volume63/data/ra000015/gylien/scale-letkf/scale/run/tmp/"
#PJM --stgout-dir "./node /volume63/data/ra000015/gylien/scale-letkf/scale/run/tmp/node"
#PJM --stgout-dir "./dat /volume63/data/ra000015/gylien/scale-letkf/scale/run/tmp/dat"
#PJM --stgout-dir "./run /volume63/data/ra000015/gylien/scale-letkf/scale/run/tmp/run"
#PJM --stgout-dir "./out /volume63/data/ra000015/gylien/scale-letkf/scale/run/tmp/out"
#PJM --stgout-dir "./log /volume63/data/ra000015/gylien/scale-letkf/scale/run/tmp/runlog"
EOF
#########################

cat >> $jobscrp << EOF
#PJM -s
. /work/system/Env_base
export OMP_NUM_THREADS=1
export PARALLEL=1

ls -l .

./fcst.sh

ls -l .

EOF

echo "Run pjstgchk..."
echo
pjstgchk $jobscrp
(($? != 0)) && exit $?

echo

## submit job

## wait for job to finish

#===============================================================================

#safe_rm_tmpdir $TMPS

#===============================================================================

exit 0