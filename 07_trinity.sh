#!/usr/bin/env bash
#SBATCH --time=1-00:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=16
#SBATCH --job-name=trinity
#SBATCH --partition=pibu_el8
#SBATCH --output=/data/users/lyang/assembly_annotation_course/assemblies/logs/trinity_%j.o
#SBATCH --error=/data/users/lyang/assembly_annotation_course/assemblies/logs/trinity_%j.e
#SBATCH --mail-user=lan.yang@students.unibe.ch
#SBATCH --mail-type=END,FAIL

set -euo pipefail

WORKDIR="/data/users/lyang/assembly_annotation_course"
RNADIR="$WORKDIR/RNAseq_Sha"
OUTDIR="$WORKDIR/assemblies/trinity"

mkdir -p "$OUTDIR"

# 生成逗号分隔的左右端文件列表（顺序按文件名排序）
LEFT=$(ls "$RNADIR"/*_1.fastq.gz | sort | paste -sd, -)
RIGHT=$(ls "$RNADIR"/*_2.fastq.gz | sort | paste -sd, -)

module load Trinity

Trinity --seqType fq \
  --left  "$LEFT" \
  --right "$RIGHT" \
  --CPU "${SLURM_CPUS_PER_TASK}" \
  --max_memory 64G \
  --output "$OUTDIR"
