#!/usr/bin/env bash
#SBATCH --time=1-00:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=16
#SBATCH --job-name=busco_all
#SBATCH --partition=pibu_el8
#SBATCH --output=/data/users/lyang/assembly_annotation_course/assessments/logs/busco_%j.o
#SBATCH --error=/data/users/lyang/assembly_annotation_course/assessments/logs/busco_%j.e
#SBATCH --mail-user=lan.yang@students.unibe.ch
#SBATCH --mail-type=END,FAIL
set -euo pipefail

# ===== 基本路径 =====
WORKDIR="/data/users/lyang/assembly_annotation_course"
ASSEMBLIES="$WORKDIR/assemblies"
OUTBASE="$WORKDIR/assessments/busco"
LOGDIR="$WORKDIR/assessments/logs"
SIF="/containers/apptainer/busco_5.7.1.sif"
mkdir -p "$OUTBASE" "$LOGDIR"

# 本地 BUSCO 数据缓存（已解压好）
BUSCO_DB="$WORKDIR/busco_downloads"
LINEAGE_DIR="$BUSCO_DB/lineages/brassicales_odb10"
if [[ ! -d "$LINEAGE_DIR" ]]; then
  echo "[ERROR] Not found lineage directory: $LINEAGE_DIR"
  echo "       请确认已解压到此处。"
  exit 1
fi

# 固定谱系（课程要求）
USE_AUTO=0
LINEAGE="brassicales_odb10"
CPU="${SLURM_CPUS_PER_TASK:-16}"

# 覆盖旧结果
FORCE=1

run_busco () {
  local fasta="$1"   # 输入FASTA
  local mode="$2"    # genome 或 transcriptome
  local name="$3"    # 输出目录名

  if [[ ! -s "$fasta" ]]; then
    echo "[ERROR] FASTA not found or empty: $fasta"
    return 1
  fi

  local outdir="$OUTBASE/${name}_${mode}"
  mkdir -p "$outdir"

  local extra=()
  (( FORCE )) && extra+=(--force)

  echo "[INFO] Running BUSCO ($mode) on $name (OFFLINE; lineage=$LINEAGE)"
  if (( USE_AUTO )); then
    # 离线环境不建议 auto-lineage，仅保留接口
    apptainer exec --bind /data:/data "$SIF" \
      busco --mode "$mode" \
            --auto-lineage \
            --offline \
            --download_path "$BUSCO_DB" \
            --cpu "$CPU" \
            -i "$fasta" \
            -o "${name}_${mode}" \
            --out_path "$outdir" \
            "${extra[@]}"
  else
    apptainer exec --bind /data:/data "$SIF" \
      busco --mode "$mode" \
            --lineage "$LINEAGE" \
            --offline \
            --download_path "$BUSCO_DB" \
            --cpu "$CPU" \
            -i "$fasta" \
            -o "${name}_${mode}" \
            --out_path "$outdir" \
            "${extra[@]}"
  fi
}

# ===== 1) Flye（基因组）=====
F_FLYE=""
for c in "$ASSEMBLIES/flye/assembly.fasta" \
         "$ASSEMBLIES/flye/contigs.fasta" \
         "$ASSEMBLIES/flye/"*.fa \
         "$ASSEMBLIES/flye/"*.fasta; do
  [[ -s "$c" ]] && { F_FLYE="$c"; break; }
done
[[ -n "${F_FLYE:-}" ]] && run_busco "$F_FLYE" genome "flye" || echo "[WARN] Flye FASTA not found."

# ===== 2) Hifiasm（基因组，必要时 GFA->FA）=====
H_DIR="$ASSEMBLIES/hifiasm"
H_FA=""
for c in "$H_DIR/"*.p_ctg.fa "$H_DIR/"*.r_utg.fa; do
  [[ -s "$c" ]] && { H_FA="$c"; break; }
done
if [[ -z "${H_FA:-}" ]]; then
  GFA=$(ls "$H_DIR/"*p_ctg.gfa 2>/dev/null | head -n1 || true)
  if [[ -n "${GFA:-}" && -s "$GFA" ]]; then
    H_FA="${GFA%.gfa}.fa"
    echo "[INFO] Converting GFA -> FASTA: $GFA -> $H_FA"
    awk '/^S/{print ">"$2;print $3}' "$GFA" > "$H_FA"
  fi
fi
[[ -n "${H_FA:-}" && -s "$H_FA" ]] && run_busco "$H_FA" genome "hifiasm" \
  || echo "[WARN] Hifiasm FASTA not found（检查 *.p_ctg.gfa 是否存在；会自动转换）。"

# ===== 3) LJA（基因组）=====
F_LJA=""
for c in "$ASSEMBLIES/lja/contigs.fasta" \
         "$ASSEMBLIES/lja/assembly.fasta" \
         "$ASSEMBLIES/lja/"*.fa \
         "$ASSEMBLIES/lja/"*.fasta; do
  [[ -s "$c" ]] && { F_LJA="$c"; break; }
done
[[ -n "${F_LJA:-}" ]] && run_busco "$F_LJA" genome "lja" || echo "[WARN] LJA FASTA not found."

# ===== 4) Trinity（转录组）=====
T_DIR="$ASSEMBLIES/trinity"
F_TRINITY=""
for c in "$T_DIR/Trinity.fasta" "$T_DIR/Trinity.tmp.fasta" "$T_DIR/"*.fa "$T_DIR/"*.fasta; do
  [[ -s "$c" ]] && { F_TRINITY="$c"; break; }
done
[[ -n "${F_TRINITY:-}" ]] && run_busco "$F_TRINITY" transcriptome "trinity" \
  || echo "[WARN] Trinity FASTA not found。"

# ===== 5) 汇总 =====
echo -e "sample\tmode\tC\tS\tD\tF\tM\tn" > "$OUTBASE/busco_summary.tsv"
shopt -s nullglob
for s in "$OUTBASE"/*/short_summary*.txt; do
  name=$(basename "$(dirname "$s")")
  C=$(grep -Eo 'C:[0-9.]+%' "$s" | head -1 | sed 's/C://')
  S=$(grep -Eo 'S:[0-9.]+%' "$s" | head -1 | sed 's/S://')
  D=$(grep -Eo 'D:[0-9.]+%' "$s" | head -1 | sed 's/D://')
  F=$(grep -Eo 'F:[0-9.]+%' "$s" | head -1 | sed 's/F://')
  M=$(grep -Eo 'M:[0-9.]+%' "$s" | head -1 | sed 's/M://')
  n=$(grep -Eo 'n:[0-9]+'   "$s" | head -1 | sed 's/n://')
  mode="genome"; [[ "$name" == trinity_* || "$name" == *transcriptome* ]] && mode="transcriptome"
  echo -e "${name}\t${mode}\t${C}\t${S}\t${D}\t${F}\t${M}\t${n}" >> "$OUTBASE/busco_summary.tsv"
done
shopt -u nullglob

echo "[INFO] All done. See: $OUTBASE and $OUTBASE/busco_summary.tsv"
