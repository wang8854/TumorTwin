# Reproducing TumorTwin demos and results

This guide explains how to clone the repository, create an isolated Python 3.11 environment, install dependencies with locked versions, prepare demo data, run a demo notebook (HGG or TNBC), and compute evaluation metrics such as AUC and CCC.

## 1. Clone the repository and create a virtual environment

```bash
git clone https://github.com/OncologyModelingGroup/TumorTwin.git
cd TumorTwin

# Option A: conda (recommended)
conda create -n tumortwin python=3.11 anaconda
conda activate tumortwin

# Option B: venv (lightweight)
python3.11 -m venv tumortwin-env
source tumortwin-env/bin/activate  # (Windows: .\\tumortwin-env\\Scripts\\activate)
```

## 2. Install dependencies and lock versions

The project pins its runtime dependencies in `pyproject.toml`; install them directly and capture the resolved versions for reproducibility:

```bash
# Standard install
pip install .

# (Optional) development extras
pip install -e ".[dev]"

# Freeze the exact versions used in your environment
pip freeze > requirements.lock.txt
```

If you want to reproduce a colleague's environment, simply run `pip install -r requirements.lock.txt` using their lockfile.

## 3. Prepare data inputs

Patient configuration files live under `input_files/` and reference NIfTI volumes via an `{$image_dir}` placeholder. Before running a demo, download/unpack the provided demo image archives (e.g., `HGG_demo_001.tar.gz`, `TNBC_demo_001.tar.gz`) into a directory of your choice and point `image_dir` to that folder. The configuration schema includes:

- Top-level modality paths such as `brainmask`, `T1_post`, `T1_pre`, and `T2_flair` for HGG cases.【F:input_files/HGG_demo_001/HGG_demo_001.json†L1-L7】
- A list of longitudinal `visits`, each with timestamps plus ADC volumes and ROI masks for enhancing and non-enhancing tumor regions.【F:input_files/HGG_demo_001/HGG_demo_001.json†L7-L67】
- Treatment histories like `radiotherapy` entries with dose and units fields.【F:input_files/HGG_demo_001/HGG_demo_001.json†L68-L120】

When loading patient data, the library automatically substitutes `{$image_dir}` using the `image_dir` argument in `.from_file()` or an `image_dir` variable in your `.env`, so you can keep configs portable across machines.【F:docs/developers/developer.md†L17-L23】 All imaging files are expected to be 3D NIfTI (`.nii` or `.nii.gz`) volumes aligned to a common grid.

## 4. Run a demo notebook (HGG or TNBC)

Launch Jupyter in the repo root and open one of the bundled notebooks:

```bash
jupyter lab  # or: jupyter notebook
```

- `tutorials/HGG_Demo.ipynb` (High-grade glioma)【F:docs/installation.md†L81-L83】
- `tutorials/TNBC_Demo.ipynb` (Triple-negative breast cancer)【F:docs/installation.md†L81-L83】

Before executing the notebook, set an environment variable pointing to your unpacked images, for example:

```bash
export image_dir=/absolute/path/to/HGG_demo_001
```

Run the notebook cells to load the patient JSON, crop volumes as needed, fit the tumor model, and generate predictions.

## 5. Evaluate results (AUC, CCC, Dice, TTC, TTV)

After generating model predictions and ground-truth/reference masks or volumes, you can compute quality-of-interest metrics using the built-in utilities in `tumortwin/postprocessing/qoi.py`:

```python
from tumortwin.postprocessing.qoi import (
    compute_ccc,          # concordance correlation coefficient for vectors
    compute_voxel_ccc,    # voxel-wise CCC within an ROI mask
    compute_voxel_dice,   # Dice coefficient on thresholded volumes
    compute_voxel_ttc,    # total tumor cellularity (requires carrying capacity)
    compute_voxel_ttv,    # total tumor volume (threshold-based)
)

# Example: CCC over ROI voxels
ccc = compute_voxel_ccc(pred_img, truth_img, roi_img)

# Example: Dice on binary masks
dice = compute_voxel_dice(pred_img, truth_img, threshold=0.5)

# Tumor burden summaries
ttc = compute_voxel_ttc(pred_img, carrying_capacity=10.0)
ttv = compute_voxel_ttv(pred_img, threshold=0.5)
```
【F:tumortwin/postprocessing/qoi.py†L6-L163】

To report AUC for a classification-style task (e.g., voxel-wise lesion detection), flatten your predicted probabilities and binary labels, then use your preferred ROC AUC implementation, such as `sklearn.metrics.roc_auc_score`, and record the value alongside CCC/Dice/TTC/TTV for a complete evaluation.
