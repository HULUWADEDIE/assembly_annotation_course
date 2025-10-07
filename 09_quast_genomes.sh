#!/usr/bin/env bash
#SBATCH --time=12:00:00
#SBATCH --mem=32G
#SBATCH --cpus-per-task=8
#SBATCH --job-name=quast_all
#SBATCH --partition=pibu_el8
#SBATCH --output=/data/users/lyang/assembly_annotation_course/assessments/logs/quast_%j.o
#SBATCH --error=/data/users/lyang/assembly_annotation_course/assessments/logs/quast_%j.e
#SBATCH --mail-user=lan.yang@students.unibe.ch
#SBATCH --mail-type=END,FAIL
set -euo pipefail

# ===== 基本路径 =====
WORKDIR="/data/users/lyang/assembly_annotation_course"
ASSEMBLIES="$WORKDIR/assemblies"
OUTBASE="$WORKDIR/assessments/quast"
LOGDIR="$WORKDIR/assessments/logs"
REFBASE="/data/courses/assembly-annotation-course/references"
SIF="/containers/apptainer/quast_5.2.0.sif"
mkdir -p "$OUTBASE/no_ref" "$OUTBASE/with_ref" "$LOGDIR"

CPU="${SLURM_CPUS_PER_TASK:-8}"

# ===== 1) 找到三套组装（flye/hifiasm/lja），必要时把 hifiasm 的 p_ctg.gfa 转成 fa =====
F_FLYE=""
for c in "$ASSEMBLIES/flye/assembly.fasta" \
         "$ASSEMBLIES/flye/contigs.fasta" \
         "$ASSEMBLIES/flye/"*.fa \
         "$ASSEMBLIES/flye/"*.fasta; do
  [[ -s "$c" ]] && { F_FLYE="$c"; break; }
done
[[ -z "${F_FLYE:-}" ]] && echo "[WARN] Flye FASTA not found under $ASSEMBLIES/flye"

H_DIR="$ASSEMBLIES/hifiasm"
F_HIFIASM=""
for c in "$H_DIR/"*.p_ctg.fa "$H_DIR/"*.r_utg.fa "$H_DIR/"*.fa; do
  [[ -s "$c" ]] && { F_HIFIASM="$c"; break; }
done
if [[ -z "${F_HIFIASM:-}" ]]; then
  GFA=$(ls "$H_DIR/"*p_ctg.gfa 2>/dev/null | head -n1 || true)
  if [[ -n "${GFA:-}" && -s "$GFA" ]]; then
    F_HIFIASM="${GFA%.gfa}.fa"
    echo "[INFO] Converting Hifiasm GFA -> FASTA: $GFA -> $F_HIFIASM"
    awk '/^S/{print ">"$2;print $3}' "$GFA" > "$F_HIFIASM"
  else
    echo "[WARN] Hifiasm FASTA/GFA not found under $H_DIR"
  fi
fi

F_LJA=""
for c in "$ASSEMBLIES/lja/contigs.fasta" \
         "$ASSEMBLIES/lja/assembly.fasta" \
         "$ASSEMBLIES/lja/"*.fa \
         "$ASSEMBLIES/lja/"*.fasta; do
  [[ -s "$c" ]] && { F_LJA="$c"; break; }
done
[[ -z "${F_LJA:-}" ]] && echo "[WARN] LJA FASTA not found under $ASSEMBLIES/lja"

# 组装列表 & 标签
ASSEMBLY_LIST=()
LABELS=()
[[ -n "${F_FLYE:-}"    ]] && { ASSEMBLY_LIST+=("$F_FLYE");    LABELS+=("flye"); }
[[ -n "${F_HIFIASM:-}" ]] && { ASSEMBLY_LIST+=("$F_HIFIASM"); LABELS+=("hifiasm"); }
[[ -n "${F_LJA:-}"     ]] && { ASSEMBLY_LIST+=("$F_LJA");     LABELS+=("lja"); }

if (( ${#ASSEMBLY_LIST[@]} == 0 )); then
  echo "[ERROR] No assemblies found. Please check $ASSEMBLIES/*"; exit 2
fi

LABELS_CSV=$(IFS=,; echo "${LABELS[*]}")

# ===== 2) 无参考运行 QUAST =====
echo "[INFO] Running QUAST without reference on: ${LABELS_CSV}"
apptainer exec --bind /data:/data "$SIF" \
  quast.py \
    --threads "$CPU" \
    --eukaryote \
    --no-sv \
    --est-ref-size 135000000 \
    --labels "$LABELS_CSV" \
    -o "$OUTBASE/no_ref" \
    "${ASSEMBLY_LIST[@]}"

# ===== 3) 找参考与注释（Arabidopsis thaliana）并有参考运行 =====
# 参考 fasta：优先 Arabidopsis/TAIR10 命名，其次任一 *.fa|*.fna|*.fasta
REF_FA=""
for r in "$REFBASE/"*Arabidopsis*.[Ff][Aa] \
         "$REFBASE/"*TAIR*.[Ff][Aa] \
         "$REFBASE/"*.fa "$REFBASE/"*.fna "$REFBASE/"*.fasta; do
  [[ -s "$r" ]] && { REF_FA="$r"; break; }
done
if [[ -z "${REF_FA:-}" ]]; then
  echo "[ERROR] Reference FASTA not found under $REFBASE"; exit 3
fi

# 注释 gff/gtf（可选）
REF_GFF=""
for g in "$REFBASE/"*.gff3 "$REFBASE/"*.gff "$REFBASE/"*.gtf; do
  [[ -s "$g" ]] && { REF_GFF="$g"; break; }
done

echo "[INFO] Running QUAST with reference:"
echo "      REF = $REF_FA"
[[ -n "${REF_GFF:-}" ]] && echo "      GFF = $REF_GFF" || echo "      GFF = (none, features skipped)"

# 组装命令
QUAST_CMD=(quast.py
  --threads "$CPU"
  --eukaryote
  --no-sv
  --labels "$LABELS_CSV"
  -r "$REF_FA"
  -o "$OUTBASE/with_ref"
)
# 有注释就加 --features
[[ -n "${REF_GFF:-}" ]] && QUAST_CMD+=(--features "$REF_GFF")
# 组装输入
QUAST_CMD+=("${ASSEMBLY_LIST[@]}")

apptainer exec --bind /data:/data "$SIF" "${QUAST_CMD[@]}"

echo "[INFO] Done. Reports are here:"
echo "  - Without reference: $OUTBASE/no_ref/report.tsv  (and report.html)"
echo "  - With reference   : $OUTBASE/with_ref/report.tsv (and report.html)"
