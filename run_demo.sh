#!/usr/bin/env bash
# Automated demo runner for TumorTwin sample tasks (HGG or TNBC).
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $0 [--task HGG|TNBC] [--patient PATIENT_ID] [--data-root PATH] [--venv PATH]

Options:
  --task        Demo task to run (HGG or TNBC). Default: TNBC.
  --patient     Patient identifier. Defaults to HGG_demo_001 or TNBC_demo_001 based on task.
  --data-root   Directory containing patient folders or tarballs. Default: input_files.
  --venv        Path to Python virtual environment to activate. Default: .venv.
USAGE
}

TASK="TNBC"
PATIENT=""
DATA_ROOT="input_files"
VENV_PATH=".venv"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)
      TASK="$2"; shift 2 ;;
    --patient)
      PATIENT="$2"; shift 2 ;;
    --data-root)
      DATA_ROOT="$2"; shift 2 ;;
    --venv)
      VENV_PATH="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1 ;;
  esac
done

# Resolve defaults
if [[ -z "$PATIENT" ]]; then
  if [[ "$TASK" == "HGG" ]]; then
    PATIENT="HGG_demo_001"
  else
    PATIENT="TNBC_demo_001"
  fi
fi

ARCHIVE_PATH="$DATA_ROOT/${PATIENT}.tar.gz"
PATIENT_DIR="$DATA_ROOT/${PATIENT}"

# Validate input data
if [[ -d "$PATIENT_DIR" ]]; then
  echo "[demo] Using extracted patient data at $PATIENT_DIR"
elif [[ -f "$ARCHIVE_PATH" ]]; then
  echo "[demo] Extracting $ARCHIVE_PATH to $DATA_ROOT"
  tar -xzf "$ARCHIVE_PATH" -C "$DATA_ROOT"
else
  echo "[demo] Missing patient data. Expected directory $PATIENT_DIR or archive $ARCHIVE_PATH" >&2
  exit 1
fi

if [[ ! -d "$VENV_PATH" ]]; then
  echo "[demo] Virtual environment not found at $VENV_PATH" >&2
  exit 1
fi

if [[ ! -f "$VENV_PATH/bin/activate" ]]; then
  echo "[demo] Virtual environment activation script missing at $VENV_PATH/bin/activate" >&2
  exit 1
fi

# Activate environment and run the demo loader
source "$VENV_PATH/bin/activate"

echo "[demo] Running demo loader for task=$TASK patient=$PATIENT"
python docker/run_demo.py --task "$TASK" --patient "$PATIENT" --image-dir "$PATIENT_DIR"

# Run evaluation: compute AUC and CCC, then save a quick-look plot
export DEMO_TASK="$TASK"
export PATIENT_DIR_ABS="$PATIENT_DIR"
python - <<'PY'
import os
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from scipy.stats import rankdata

from tumortwin.postprocessing.qoi import compute_voxel_ccc
from tumortwin.types.imaging import NibabelNifti


def compute_auc(labels: np.ndarray, scores: np.ndarray) -> float:
    """Compute ROC AUC without external dependencies.

    Uses the Mann-Whitney U statistic over ranked scores.
    """
    labels = labels.astype(int)
    scores = scores.astype(float)

    pos = scores[labels == 1]
    neg = scores[labels == 0]
    if len(pos) == 0 or len(neg) == 0:
        raise ValueError("Need at least one positive and one negative sample to compute AUC")

    ranks = rankdata(np.concatenate([pos, neg]))
    rank_sum_pos = ranks[: len(pos)].sum()
    return (rank_sum_pos - len(pos) * (len(pos) + 1) / 2) / (len(pos) * len(neg))


def load_first(paths: list[Path], kind: str) -> Path:
    if not paths:
        raise FileNotFoundError(f"No {kind} files found for evaluation")
    return paths[0]


task = os.environ["DEMO_TASK"].upper()
patient_dir = Path(os.environ["PATIENT_DIR_ABS"]).resolve()

adc_paths = sorted(patient_dir.glob("ADC_*.nii.gz"))
roi_paths = sorted(patient_dir.glob("ROI_enhance*.nii.gz"))

pred_path = load_first(adc_paths, "ADC")
truth_path = load_first(adc_paths[1:] if len(adc_paths) > 1 else adc_paths, "ADC")
roi_path = load_first(roi_paths, "ROI_enhance mask")

pred_img = NibabelNifti.from_file(pred_path)
truth_img = NibabelNifti.from_file(truth_path)
roi_img = NibabelNifti.from_file(roi_path)

labels = (roi_img.array > 0).astype(int).ravel()
scores = pred_img.array.ravel()
auc = compute_auc(labels, scores)
ccc = compute_voxel_ccc(pred_img, truth_img, roi_img)

print(f"[demo] AUC (ADC vs ROI_enhance): {auc:.4f}")
print(f"[demo] CCC (ADC pair within ROI): {ccc:.4f}")

fig, axes = plt.subplots(1, 2, figsize=(10, 4))
axes[0].hist(
    [scores[labels == 0], scores[labels == 1]],
    bins=40,
    label=["Background", "ROI"],
    color=["#7f7f7f", "#d62728"],
    alpha=0.85,
)
axes[0].set_title("ADC intensity by class")
axes[0].legend()
axes[0].set_xlabel("ADC value")
axes[0].set_ylabel("Voxel count")

thresholds = np.linspace(scores.min(), scores.max(), 100)
tpr = []
fpr = []
for thr in thresholds:
    preds = scores >= thr
    tp = np.sum((preds == 1) & (labels == 1))
    fp = np.sum((preds == 1) & (labels == 0))
    fn = np.sum((preds == 0) & (labels == 1))
    tn = np.sum((preds == 0) & (labels == 0))
    tpr.append(tp / (tp + fn) if tp + fn else 0.0)
    fpr.append(fp / (fp + tn) if fp + tn else 0.0)

axes[1].plot(fpr, tpr, label=f"ROC (AUC={auc:.3f})")
axes[1].plot([0, 1], [0, 1], "k--", linewidth=0.8)
axes[1].set_xlabel("False positive rate")
axes[1].set_ylabel("True positive rate")
axes[1].set_title("ROC curve")
axes[1].legend()

out_path = Path("assets") / f"{task.lower()}_{patient_dir.name}_evaluation.png"
out_path.parent.mkdir(parents=True, exist_ok=True)
fig.tight_layout()
fig.savefig(out_path)
print(f"[demo] Saved evaluation plot to {out_path}")
PY
