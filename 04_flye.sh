#!/usr/bin/env bash
#SBATCH --time=1-00:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=16
#SBATCH --job-name=flye_hifi
#SBATCH --partition=pibu_el8
#SBATCH --output=/data/users/lyang/assembly_annotation_course/assemblies/logs/flye_%j.o
#SBATCH --error=/data/users/lyang/assembly_annotation_course/assemblies/logs/flye_%j.e
#SBATCH --mail-user=lan.yang@students.unibe.ch
#SBATCH --mail-type=END,FAIL
set -euo pipefail

# === 路径与参数 ===
WORKDIR="/data/users/lyang/assembly_annotation_course"
READS_DIR="$WORKDIR/Pyl-1"
OUTDIR="$WORKDIR/assemblies/flye"
GENOME_SIZE="135m"
SIF="/containers/apptainer/flye_2.9.5.sif"

mkdir -p "$OUTDIR"

# 收集 reads（fastq 或 fastq.gz）
shopt -s nullglob
reads=( "$READS_DIR"/*.fastq.gz "$READS_DIR"/*.fastq )
if (( ${#reads[@]} == 0 )); then
  echo "[ERROR] No FASTQ found in $READS_DIR" >&2
  exit 2
fi
echo "[INFO] Found ${#reads[@]} reads under $READS_DIR"
printf '  - %s\n' "${reads[@]}"

# === 先尝试：绑定 /data，检查容器内是否能读到 ===
export APPTAINER_BINDPATH="/data"
probe="${reads[0]}"
echo "[INFO] Probe inside container: $probe"
if apptainer exec --bind /data:/data --security label=disable "$SIF" \
   bash -lc "test -r '$probe' && zcat -f '$probe' | head -n 1 >/dev/null 2>&1"; then
  echo "[INFO] Container CAN read /data. Running Flye directly on /data..."
  apptainer exec --bind /data:/data --security label=disable "$SIF" flye \
    --pacbio-hifi "${reads[@]}" \
    --out-dir "$OUTDIR" \
    --threads "${SLURM_CPUS_PER_TASK}" \
    --genome-size "$GENOME_SIZE"
  exit 0
fi

# === 兜底：拷到本地盘再跑（避免 /data 未挂载/SELinux 限制） ===
echo "[WARN] Container cannot read /data. Falling back to SLURM_TMPDIR..."
mkdir -p "$SLURM_TMPDIR/reads" "$SLURM_TMPDIR/flye_out"
# 使用 rsync 显示进度与校验
rsync -av --inplace --no-W "${reads[@]}" "$SLURM_TMPDIR/reads/"

# 在本地盘运行（同时绑定本地盘路径，确保容器可读）
apptainer exec --bind "$SLURM_TMPDIR:$SLURM_TMPDIR" --security label=disable "$SIF" flye \
  --pacbio-hifi "$SLURM_TMPDIR/reads/"*.fastq* \
  --out-dir "$SLURM_TMPDIR/flye_out" \
  --threads "${SLURM_CPUS_PER_TASK}" \
  --genome-size "$GENOME_SIZE"

# 回写结果
rsync -av "$SLURM_TMPDIR/flye_out/" "$OUTDIR/"
echo "[INFO] Flye finished. Results synced to $OUTDIR"
