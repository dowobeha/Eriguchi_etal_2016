#!/bin/bash
#PBS -l walltime=96:00:00
#PBS -l nodes=1:ppn=56
#PBS -N parse
#PBS -j oe
#PBS -q cl
#PBS -o /projects/cl/enju/run.log


ducttape /projects/cl/enju/run.tape -C /projects/cl/enju/run.tconf -y
