import argparse
import json
import shutil
import sys
import urllib.request
import zipfile
from pathlib import Path
from typing import Iterable, List, Tuple

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from app.config import DATA_DIR
from scripts.import_local_catalog import (
    IMPORTS_DIR,
    USDA_FOUNDATION_PATH,
    USDA_SR_PATH,
    load_usda_foods,
    main as import_catalog_main,
)


DOWNLOAD_SPECS = [
    {
        "label": "USDA Foundation Foods zip",
        "url": "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_json_2025-12-18.zip",
        "target": IMPORTS_DIR / "usda_foundation_2025_json.zip",
    },
    {
        "label": "USDA SR Legacy zip",
        "url": "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_json_2018-04.zip",
        "target": IMPORTS_DIR / "usda_sr_legacy_json.zip",
    },
    {
        "label": "ICMR-NIN IFCT PDF",
        "url": "https://www.nin.res.in/ebooks/IFCT2017_16122024.pdf",
        "target": IMPORTS_DIR / "ifct_2017_full_copy.pdf",
    },
]


def ensure_import_dir() -> None:
    IMPORTS_DIR.mkdir(parents=True, exist_ok=True)


def download_file(url: str, target: Path) -> None:
    ensure_import_dir()
    with urllib.request.urlopen(url) as response, target.open("wb") as output:
        shutil.copyfileobj(response, output)


def extract_zip_member(zip_path: Path, member_name: str, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path) as archive:
        member = None
        for name in archive.namelist():
            if name.endswith(member_name):
                member = name
                break
        if member is None:
            raise FileNotFoundError("Could not find {0} in {1}".format(member_name, zip_path))
        with archive.open(member) as source, output_path.open("wb") as output:
            shutil.copyfileobj(source, output)


def verify_layout() -> List[Tuple[str, bool, str]]:
    checks: List[Tuple[str, bool, str]] = []
    for spec in DOWNLOAD_SPECS:
        exists = spec["target"].exists()
        checks.append((str(spec["target"].relative_to(ROOT_DIR)), exists, "download"))

    foundation_ok = USDA_FOUNDATION_PATH.exists()
    sr_ok = USDA_SR_PATH.exists()
    checks.append((str(USDA_FOUNDATION_PATH.relative_to(ROOT_DIR)), foundation_ok, "extract"))
    checks.append((str(USDA_SR_PATH.relative_to(ROOT_DIR)), sr_ok, "extract"))

    if foundation_ok:
        try:
            foods = load_usda_foods(USDA_FOUNDATION_PATH)
            checks.append(("foundation_json_shape", isinstance(foods, list) and len(foods) > 0, "schema"))
        except Exception as exc:  # pragma: no cover - surfaced in CLI output
            checks.append(("foundation_json_shape", False, str(exc)))
    if sr_ok:
        try:
            foods = load_usda_foods(USDA_SR_PATH)
            checks.append(("sr_legacy_json_shape", isinstance(foods, list) and len(foods) > 0, "schema"))
        except Exception as exc:  # pragma: no cover - surfaced in CLI output
            checks.append(("sr_legacy_json_shape", False, str(exc)))
    return checks


def extract_archives() -> None:
    extract_zip_member(
        IMPORTS_DIR / "usda_foundation_2025_json.zip",
        USDA_FOUNDATION_PATH.name,
        USDA_FOUNDATION_PATH,
    )
    extract_zip_member(
        IMPORTS_DIR / "usda_sr_legacy_json.zip",
        USDA_SR_PATH.name,
        USDA_SR_PATH,
    )


def print_checks(checks: Iterable[Tuple[str, bool, str]]) -> bool:
    ok = True
    for name, passed, detail in checks:
        status = "OK" if passed else "FAIL"
        print("{0} {1} [{2}]".format(status, name, detail))
        ok = ok and passed
    return ok


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Download, verify, and import local nutrition source data."
    )
    parser.add_argument("--download", action="store_true", help="Download source archives and PDF.")
    parser.add_argument("--extract", action="store_true", help="Extract the USDA JSON payloads.")
    parser.add_argument("--verify", action="store_true", help="Verify the expected layout and payload shape.")
    parser.add_argument("--import", dest="do_import", action="store_true", help="Import the local catalog into SQLite.")
    parser.add_argument(
        "--force",
        action="store_true",
        help="Redownload files even if they already exist.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not any([args.download, args.extract, args.verify, args.do_import]):
        args.download = True
        args.extract = True
        args.verify = True

    ensure_import_dir()

    if args.download:
        for spec in DOWNLOAD_SPECS:
            target = spec["target"]
            if target.exists() and not args.force:
                print("SKIP {0} already exists".format(target.relative_to(ROOT_DIR)))
                continue
            print("DOWNLOAD {0}".format(spec["url"]))
            download_file(spec["url"], target)

    if args.extract:
        extract_archives()
        print("EXTRACT completed")

    if args.verify:
        if not print_checks(verify_layout()):
            return 1

    if args.do_import:
        import_catalog_main()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
