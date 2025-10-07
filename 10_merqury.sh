#!/usr/bin/env bash
#SBATCH --time=12:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=16
#SBATCH --job-name=merqury_all
#SBATCH --partition=pibu_el8
#SBATCH --output=/data/users/lyang/assembly_annotation_course/assessments/logs/merqury_%j.o
#SBATCH --error=/data/users/lyang/assembly_annotation_course/assessments/logs/merqury_%j.e
#SBATCH --mail-user=lan.yang@students.unibe.ch
#SBATCH --mail-type=END,FAIL
set -euo pipefail

# ===== 基本路径 =====
WORKDIR="/data/users/lyang/assembly_annotation_course"
ASSEMBLIES="$WORKDIR/assemblies"
READS_DIR="$WORKDIR/Pyl-1"                         # 你的 HiFi/Illumina 读长目录
OUTBASE="$WORKDIR/assessments/merqury"
LOGDIR="$WORKDIR/assessments/logs"
SIF="/containers/apptainer/merqury_1.3.sif"
mkdir -p "$OUTBASE" "$LOGDIR"

CPU="${SLURM_CPUS_PER_TASK:-16}"
K=21          # 可按要求改 21/31
FORCE=1       # 1=覆盖旧结果

# 统一给容器设置 MERQURY 变量
MERQURY_PATH="/usr/local/share/merqury"
APPT="apptainer exec --bind /data:/data --env MERQURY=${MERQURY_PATH} ${SIF}"

# ===== 找读长 =====
readarray -t READS < <(ls "$READS_DIR"/*.{fastq,fq}.gz "$READS_DIR"/*.{fastq,fq} 2>/dev/null || true)
if (( ${#READS[@]} == 0 )); then
  echo "[ERROR] No reads in $READS_DIR (expecting *.fastq.gz/.fq.gz)"; exit 2
fi

# ===== 找三套组装（必要时把 hifiasm 的 GFA -> FA）=====
find_fa () { local d="$1" f=""; for c in "$d/"*.fa "$d/"*.fasta; do [[ -s "$c" ]] && { f="$c"; break; }; done; [[ -n "$f" ]] && echo "$f"; }
F_FLYE=$(find_fa "$ASSEMBLIES/flye" || true)
[[ -z "${F_FLYE:-}" ]] && for c in "$ASSEMBLIES/flye/assembly.fasta" "$ASSEMBLIES/flye/contigs.fasta"; do [[ -s "$c" ]] && { F_FLYE="$c"; break; }; done

H_DIR="$ASSEMBLIES/hifiasm"; F_HIFIASM=$(find_fa "$H_DIR" || true)
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

# ===== 构建/复用 reads.meryl =====
MERYL_DIR="$OUTBASE/meryl"
READS_MERYL="$MERYL_DIR/reads.k${K}.meryl"
mkdir -p "$MERYL_DIR"
if [[ -d "$READS_MERYL" ]] && (( ! FORCE )); then
  echo "[INFO] Reusing existing meryl DB: $READS_MERYL"
else
  [[ -d "$READS_MERYL" && FORCE -eq 1 ]] && rm -rf "$READS_MERYL"
  echo "[INFO] Building meryl DB @ k=$K -> $READS_MERYL"
  $APPT meryl count k="$K" output "$READS_MERYL" threads="$CPU" "${READS[@]}"
fi

# ===== 跑每个组装（在各自输出目录内执行；outprefix 用相对名；确保 logs/ 存在）=====
SUMMARY="$OUTBASE/summary.tsv"
echo -e "sample\tk\tQV\terror_rate\tcompleteness\tout_dir" > "$SUMMARY"

run_merqury () {  # $1: label  $2: asm.fa
  local label="$1" asm="$2" outdir="$OUTBASE/$label"
  mkdir -p "$outdir"; (( FORCE )) && rm -rf "$outdir"/* || true
  echo "[INFO] merqury -> $label"
  $APPT bash -lc "set -euo pipefail; cd '$outdir'; mkdir -p logs; merqury.sh '$READS_MERYL' '$asm' '$label'"

  # 抓指标
  local qv="$outdir/${label}.qv" comp="$outdir/${label}.completeness.stats"
  local QV=NA ERR=NA COMP=NA
  [[ -s "$qv"  ]] && QV=$(awk 'tolower($1) ~ /^qv|^merqury/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9.]+$/){print $i; exit}}' "$qv")
  [[ -s "$qv"  ]] && ERR=$(awk 'tolower($0) ~ /error/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9.]+(e-?[0-9]+)?$/){val=$i}} END{if(val!="") print val}' "$qv")
  [[ -s "$comp" ]] && COMP=$(awk 'tolower($0) ~ /completeness/ {for(i=1;i<=NF;i++) if($i ~ /[0-9.]+%/){print $i; exit}}' "$comp")
  echo -e "${label}\t${K}\t${QV:-NA}\t${ERR:-NA}\t${COMP:-NA}\t${outdir}" >> "$SUMMARY"
}

for label in "${!ASM[@]}"; do run_merqury "$label" "${ASM[$label]}"; done

echo "[INFO] Done. Summary -> $SUMMARY"
echo "Check: $OUTBASE/{flye,hifiasm,lja}/*.qv *.completeness.stats *.spectra-cn.pdf"
