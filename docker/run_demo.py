"""
Command-line helper to run TumorTwin demo tasks inside the Docker image.

Example usages:
    python docker/run_demo.py --task HGG --patient HGG_demo_001
    python docker/run_demo.py --task TNBC --patient TNBC_demo_001
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Tuple

# Allow running without installing the package in editable mode
REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.append(str(REPO_ROOT))

from tumortwin.types.hgg_data import HGGPatientData
from tumortwin.types.tnbc_data import TNBCPatientData


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run TumorTwin demo tasks")
    parser.add_argument(
        "--task",
        choices=["HGG", "TNBC"],
        default="HGG",
        help="Which demo pipeline to run.",
    )
    parser.add_argument(
        "--patient",
        default=None,
        help=(
            "Patient identifier (defaults to HGG_demo_001 or TNBC_demo_001 based on the task). "
            "The ID should match a folder under input_files/."
        ),
    )
    parser.add_argument(
        "--image-dir",
        default=None,
        help=(
            "Directory containing NIfTI files referenced by the patient JSON. "
            "If omitted, the script uses input_files/<patient>."
        ),
    )
    return parser.parse_args()


def resolve_patient(task: str, patient_arg: str | None) -> Tuple[str, Path, Path]:
    default_patient = "HGG_demo_001" if task == "HGG" else "TNBC_demo_001"
    patient = patient_arg or default_patient
    patient_dir = Path("input_files") / patient
    config_path = patient_dir / f"{patient}.json"
    if not config_path.exists():
        raise FileNotFoundError(f"Could not find config file at {config_path}")
    image_dir = Path(patient_dir)
    return patient, config_path, image_dir


def run_hgg(config_path: Path, image_dir: Path) -> None:
    patient = HGGPatientData.from_file(config_path, image_dir=image_dir)
    print(f"Loaded HGG patient: {patient.patient}")
    print(f"Total visits: {len(patient.visits)}")
    print(f"Brain mask shape: {patient.brainmask_image.array.shape}")
    visit = patient.visits[0]
    print(
        "First visit ROI voxel counts (enhance / nonenhance): "
        f"{visit.roi_enhance_image.array.sum()} / {visit.roi_nonenhance_image.array.sum()}"
    )


def run_tnbc(config_path: Path, image_dir: Path) -> None:
    patient = TNBCPatientData.from_file(config_path, image_dir=image_dir)
    print(f"Loaded TNBC patient: {patient.patient}")
    print(f"Total visits: {len(patient.visits)}")
    print(f"Breast mask shape: {patient.breastmask_image.array.shape}")
    visit = patient.visits[0]
    print(
        "First visit ROI voxel count: "
        f"{visit.roi_enhance_image.array.sum()}"
    )


def main() -> None:
    args = parse_args()
    patient, config_path, inferred_image_dir = resolve_patient(args.task, args.patient)
    image_dir = Path(args.image_dir) if args.image_dir else inferred_image_dir

    print(f"Running {args.task} demo for patient {patient}")
    if args.task == "HGG":
        run_hgg(config_path, image_dir)
    else:
        run_tnbc(config_path, image_dir)


if __name__ == "__main__":
    main()
