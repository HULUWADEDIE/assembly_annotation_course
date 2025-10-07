#!/usr/bin/env bash
#SBATCH --time=1-00:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=16
#SBATCH --job-name=hifiasm
#SBATCH --partition=pibu_el8
#SBATCH --output=/data/users/lyang/assembly_annotation_course/assemblies/logs/hifiasm_%j.o
#SBATCH --error=/data/users/lyang/assembly_annotation_course/assemblies/logs/hifiasm_%j.e
#SBATCH --mail-user=lan.yang@students.unibe.ch
#SBATCH --mail-type=END,FAIL

set -euo pipefail

# ---------- paths ----------
WORKDIR="/data/users/lyang/assembly_annotation_course"
READDIR="$WORKDIR/Pyl-1"
OUTDIR="$WORKDIR/assemblies/hifiasm"
LOGDIR="$WORKDIR/assemblies/logs"
PREFIX="$OUTDIR/pyl1"
SIF="/containers/apptainer/hifiasm_0.25.0.sif"

mkdir -p "$OUTDIR" "$LOGDIR"

echo "[INFO] Workdir: $WORKDIR"
echo "[INFO] Readdir: $READDIR"
echo "[INFO] Outdir : $OUTDIR"
echo "[INFO] CPUs   : ${SLURM_CPUS_PER_TASK:-16}"

# ---------- collect reads ----------
shopt -s nullglob
READS_ARR=( "$READDIR"/*.fastq.gz "$READDIR"/*.fq.gz "$READDIR"/*.fastq )
shopt -u nullglob

if (( ${#READS_ARR[@]} == 0 )); then
  echo "[ERROR] No reads found under: $READDIR"
  exit 2
fi

echo "[INFO] Host can see ${#READS_ARR[@]} read file(s):"
printf '  - %s\n' "${READS_ARR[@]}"

echo "[INFO] Container-side listing of Pyl-1 (before run):"
apptainer exec --bind /data:/data "$SIF" ls -l "$READDIR" || true

# ---------- run hifiasm (NO inner bash -lc, pass args directly) ----------
echo "[INFO] Running hifiasm..."
apptainer exec --bind /data:/data "$SIF" \
  hifiasm -o "$PREFIX" -t "${SLURM_CPUS_PER_TASK}" \
  "${READS_ARR[@]}"

echo "[INFO] hifiasm finished."

# ---------- unconditional GFA -> FASTA ----------
echo "[INFO] Converting GFA -> FASTA (unconditional)"
awk '/^S/{print ">"$2;print $3}' "${PREFIX}.p_ctg.gfa" > "${PREFIX}.p_ctg.fa"
awk '/^S/{print ">"$2;print $3}' "${PREFIX}.a_ctg.gfa" > "${PREFIX}.a_ctg.fa"
awk '/^S/{print ">"$2;print $3}' "${PREFIX}.r_utg.gfa" > "${PREFIX}.r_utg.fa"  # 可选

echo "[INFO] Done. Outputs under: $OUTDIR"
