#!/usr/bin/env bash
#SBATCH --time=08:00:00
#SBATCH --mem=32G
#SBATCH --cpus-per-task=8
#SBATCH --job-name=nucmer_mummerplot
#SBATCH --partition=pibu_el8
#SBATCH --output=/data/users/lyang/assembly_annotation_course/assessments/logs/nucmer_%j.o
#SBATCH --error=/data/users/lyang/assembly_annotation_course/assessments/logs/nucmer_%j.e
#SBATCH --mail-user=lan.yang@students.unibe.ch
#SBATCH --mail-type=END,FAIL
set -euo pipefail

# ========= 基本路径 =========
WORKDIR="/data/users/lyang/assembly_annotation_course"
ASSEMBLIES="$WORKDIR/assemblies"
REFBASE="/data/courses/assembly-annotation-course/references"
OUTBASE="$WORKDIR/assessments/mummer"
LOGDIR="$WORKDIR/assessments/logs"
SIF="/containers/apptainer/mummer4_gnuplot.sif"
CPU="${SLURM_CPUS_PER_TASK:-8}"
mkdir -p "$OUTBASE/ref" "$OUTBASE/pairwise" "$LOGDIR"

APPT="apptainer exec --bind /data:/data $SIF"

# ========= 找参考 =========
REF_FA=""
for r in "$REFBASE/"*Arabidopsis*.[Ff][Aa] \
         "$REFBASE/"*TAIR*.[Ff][Aa] \
         "$REFBASE/"*.fa "$REFBASE/"*.fna "$REFBASE/"*.fasta; do
  [[ -s "$r" ]] && { REF_FA="$r"; break; }
done
[[ -n "$REF_FA" ]] || { echo "[ERROR] Reference FASTA not found under $REFBASE"; exit 2; }
echo "[INFO] Reference: $REF_FA"

# ========= 找三套组装（必要时把 hifiasm 的 GFA 转 FASTA）=========
find_fa () { local d="$1" f=""; for c in "$d/"*.fa "$d/"*.fasta; do [[ -s "$c" ]] && { f="$c"; break; }; done; [[ -n "$f" ]] && echo "$f"; }

F_FLYE=$(find_fa "$ASSEMBLIES/flye" || true)
[[ -z "${F_FLYE:-}" ]] && for c in "$ASSEMBLIES/flye/assembly.fasta" "$ASSEMBLIES/flye/contigs.fasta"; do [[ -s "$c" ]] && { F_FLYE="$c"; break; }; done

H_DIR="$ASSEMBLIES/hifiasm"
F_HIFIASM=$(find_fa "$H_DIR" || true)
if [[ -z "${F_HIFIASM:-}" ]]; then
  GFA=$(ls "$H_DIR/"*p_ctg.gfa 2>/dev/null | head -n1 || true)
  if [[ -n "${GFA:-}" && -s "$GFA" ]]; then
    F_HIFIASM="${GFA%.gfa}.fa"
    echo "[INFO] Converting Hifiasm GFA -> FASTA: $GFA -> $F_HIFIASM"
    awk '/^S/{print ">"$2;print $3}' "$GFA" > "$F_HIFIASM"
  fi
fi

F_LJA=$(find_fa "$ASSEMBLIES/lja" || true)
[[ -z "${F_LJA:-}" ]] && for c in "$ASSEMBLIES/lja/contigs.fasta" "$ASSEMBLIES/lja/assembly.fasta"; do [[ -s "$c" ]] && { F_LJA="$c"; break; }; done

declare -A ASM
[[ -n "${F_FLYE:-}"    ]] && ASM[flye]="$F_FLYE"
[[ -n "${F_HIFIASM:-}" ]] && ASM[hifiasm]="$F_HIFIASM"
[[ -n "${F_LJA:-}"     ]] && ASM[lja]="$F_LJA"
(( ${#ASM[@]} > 0 )) || { echo "[ERROR] No assemblies found."; exit 3; }

echo "[INFO] Assemblies:"
for k in "${!ASM[@]}"; do echo "  $k -> ${ASM[$k]}"; done

# ========= 封装：跑 nucmer + mummerplot =========
run_one () { # $1=ref.fa  $2=query.fa  $3=prefix  $4=outdir
  local ref="$1" qry="$2" pref="$3" out="$4"
  mkdir -p "$out"
  echo "[INFO] NUCmer: $pref"
  $APPT nucmer --prefix "$out/$pref" --breaklen 1000 --mincluster 1000 --threads "$CPU" "$ref" "$qry"

  # 可读性坐标表（未过滤原始 .delta）
  $APPT show-coords -rcl "$out/$pref.delta" > "$out/$pref.coords.txt"

  echo "[INFO] mummerplot (dotplot PNG): $pref"
  $APPT mummerplot -R "$ref" -Q "$qry" \
      --filter --large --layout --fat \
      -t png -p "$out/$pref" "$out/$pref.delta"
  # 生成的图片在 $out/$pref.png
}

# ========= A) 每个组装 vs 参考 =========
for lab in "${!ASM[@]}"; do
  run_one "$REF_FA" "${ASM[$lab]}" "${lab}_vs_ref" "$OUTBASE/ref"
done

# ========= B) 组装之间两两比较（双向）=========
labels=( "${!ASM[@]}" )
for (( i=0; i<${#labels[@]}; i++ )); do
  for (( j=i+1; j<${#labels[@]}; j++ )); do
    A="${labels[$i]}"; B="${labels[$j]}"
    run_one "${ASM[$A]}" "${ASM[$B]}" "${A}_vs_${B}" "$OUTBASE/pairwise"
    run_one "${ASM[$B]}" "${ASM[$A]}" "${B}_vs_${A}" "$OUTBASE/pairwise"
  done
done

echo "[INFO] All done."
echo "  With reference:    $OUTBASE/ref/*_vs_ref.png  (coords in *.coords.txt)"
echo "  Assembly vs assembly: $OUTBASE/pairwise/*_vs_*.png"
