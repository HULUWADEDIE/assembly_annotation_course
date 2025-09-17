#!/usr/bin/env bash

#SBATCH --time=1-00:00:00
#SBATCH --mem=16G
#SBATCH --cpus-per-task=4
#SBATCH --job-name=fastp
#SBATCH --partition=pibu_el8
#SBATCH --output=/data/users/lyang/assembly_annotation_course/read_QC/fastp_output_%j.o
#SBATCH --error=/data/users/lyang/assembly_annotation_course/read_QC/fastp_error_%j.e
#SBATCH --mail-user=lan.yang@students.unibe.ch
#SBATCH --mail-type=END

WORKDIR=/data/users/lyang/assembly_annotation_course
cd $WORKDIR

# 输出目录
mkdir -p read_QC/fastp

# 输入文件
READ1=RNAseq_Sha/ERR754081_1.fastq.gz
READ2=RNAseq_Sha/ERR754081_2.fastq.gz

OUT1=read_QC/fastp/ERR754081_1.trimmed.fastq.gz
OUT2=read_QC/fastp/ERR754081_2.trimmed.fastq.gz

REPORT_HTML=read_QC/fastp/fastp_report.html
REPORT_JSON=read_QC/fastp/fastp_report.json

echo "=== Checking fastp availability... ==="

# 1) 尝试 module
if module spider fastp &> /dev/null; then
    echo "Found fastp module, using module load"
    module load fastp
    fastp -i $READ1 -I $READ2 -o $OUT1 -O $OUT2 \
          --thread 4 --html $REPORT_HTML --json $REPORT_JSON

# 2) 尝试容器
elif ls /containers/apptainer/fastp*.sif &> /dev/null; then
    FASTP_SIF=$(ls /containers/apptainer/fastp*.sif | head -n 1)
    echo "No module, using apptainer container: $FASTP_SIF"
    apptainer exec --bind $WORKDIR $FASTP_SIF fastp \
          -i $READ1 -I $READ2 -o $OUT1 -O $OUT2 \
          --thread 4 --html $REPORT_HTML --json $REPORT_JSON

# 3) 如果都找不到
else
    echo "ERROR: fastp not found (neither module nor container)"
    exit 1
fi

echo "=== fastp finished successfully ==="
