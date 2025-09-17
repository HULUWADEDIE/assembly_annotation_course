#!/usr/bin/env bash
#SBATCH --cpus-per-task=4
#SBATCH --mem=80G
#SBATCH --time=08:00:00
#SBATCH --job-name=jellyfish
#SBATCH --output=/data/users/lyang/assembly_annotation_course/read_QC/kmer_counting/output_jellyfish_%j.o
#SBATCH --error=/data/users/lyang/assembly_annotation_course/read_QC/kmer_counting/error_jellyfish_%j.e
#SBATCH --partition=pibu_el8
#SBATCH --mail-user=lan.yang@students.unibe.ch
#SBATCH --mail-type=END,FAIL

# 加载 Jellyfish 模块
module load Jellyfish/2.3.0

# 输出目录
OUTDIR=/data/users/lyang/assembly_annotation_course/read_QC/kmer_counting
mkdir -p $OUTDIR
cd $OUTDIR

# 输入数据（PacBio HiFi reads）
PACBIO=/data/users/lyang/assembly_annotation_course/Pyl-1/*.fastq.gz

# k-mer 计数 (m=21，可调整 k-mer 大小)
jellyfish count -C -m 21 -s 5G -t 4 \
    <(zcat $PACBIO) \
    -o $OUTDIR/pyl1_reads.jf

# 生成直方图
jellyfish histo -t 4 $OUTDIR/pyl1_reads.jf > $OUTDIR/pyl1_reads.histo
