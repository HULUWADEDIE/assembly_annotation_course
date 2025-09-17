#!/usr/bin/env bash
#SBATCH --cpus-per-task=2
#SBATCH --mem=40G
#SBATCH --time=02:00:00
#SBATCH --job-name=fastqc
#SBATCH --output=/data/users/lyang/assembly_annotation_course/read_QC/fastqc_output_%j.o
#SBATCH --error=/data/users/lyang/assembly_annotation_course/read_QC/fastqc_error_%j.e
#SBATCH --partition=pibu_el8
#SBATCH --mail-user=lan.yang@students.unibe.ch
#SBATCH --mail-type=END,FAIL

# 加载 FastQC 模块
module load FastQC/0.11.9-Java-11

# 定义输出目录
OUTDIR=/data/users/lyang/assembly_annotation_course/read_QC/fastqc_results
mkdir -p $OUTDIR

# 定义输入数据目录
INPUT1=/data/users/lyang/assembly_annotation_course/Pyl-1
INPUT2=/data/users/lyang/assembly_annotation_course/RNAseq_Sha

# 运行 FastQC
fastqc -o $OUTDIR $INPUT1/*.fastq.gz
fastqc -o $OUTDIR $INPUT2/*.fastq.gz
