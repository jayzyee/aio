from pathlib import Path


def main() -> int:
    output = Path("report.txt")
    output.write_text("generic project report\n", encoding="utf-8")
    print(output.read_text(encoding="utf-8"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
