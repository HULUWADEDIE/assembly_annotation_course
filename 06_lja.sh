#!/usr/bin/env bash
#SBATCH --time=1-00:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=16
#SBATCH --job-name=lja
#SBATCH --partition=pibu_el8
#SBATCH --output=/data/users/lyang/assembly_annotation_course/assemblies/logs/lja_%j.o
#SBATCH --error=/data/users/lyang/assembly_annotation_course/assemblies/logs/lja_%j.e
#SBATCH --mail-user=lan.yang@students.unibe.ch
#SBATCH --mail-type=END,FAIL

set -euo pipefail

# 路径
WORKDIR="/data/users/lyang/assembly_annotation_course"
READS_DIR="$WORKDIR/Pyl-1"   # 这是一个指向 /data/courses/... 的符号链接
OUTDIR="$WORKDIR/assemblies/lja"
SIF="/containers/apptainer/lja-0.2.sif"

mkdir -p "$OUTDIR"

# 1) 在提交运行前打印并校验输入文件列表
echo "[INFO] Host listing of Pyl-1:"
ls -l "$READS_DIR" || true

shopt -s nullglob
mapfile -t READ_FILES < <(printf '%s\n' "$READS_DIR"/*.fastq "$READS_DIR"/*.fastq.gz)
shopt -u nullglob

if (( ${#READ_FILES[@]} == 0 )); then
  echo "[ERROR] No FASTQ/FASTQ.GZ files found under $READS_DIR"
  exit 1
fi

# 2) 组装 LJA 命令
CMD=( lja -o "$OUTDIR" -t "${SLURM_CPUS_PER_TASK}" )
for f in "${READ_FILES[@]}"; do
  CMD+=( --reads "$f" )
done

echo "[INFO] LJA command to run:"
printf ' %q' "${CMD[@]}"; echo

# 3) 关键修复：同时绑定符号链接的目标根目录 (/data/courses)，
#    以免容器内出现断链从而导致找不到输入文件
#    （仍保留绑定 $WORKDIR，方便写出结果）
apptainer exec \
  --bind "$WORKDIR","/data/courses" \
  "$SIF" \
  "${CMD[@]}"

# 4) 如果 LJA 在你的镜像里不支持 .gz（极少见），可改用解压到临时目录的方案：
#    TMPREADS="$OUTDIR/tmp_reads"; mkdir -p "$TMPREADS"
#    for gz in "${READ_FILES[@]}"; do
#      base=$(basename "$gz" .gz)
#      pigz -dc "$gz" > "$TMPREADS/$base"
#    done
#    然后将上面的 READ_FILES 改成 "$TMPREADS"/*.fastq 再执行 LJA。
