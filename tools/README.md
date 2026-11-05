# Developer tools

Scripts used to produce the reverse-engineering evidence. They are not part of
the runtime build.

- `ApplyNames.java` - Ghidra headless script that renames functions from
  `docs/method_names.csv`.
- `ExportNames.java` - Ghidra script that exports function entry points and
  names.
- `extract_rtti.py` - extracts RTTI/vtable data from the PE and writes the
  JSON consumed by `docs/RTTI.md`.

These scripts expect a Ghidra installation and the analyzed project described
in `docs/REVERSE-ENGINEERING.md`. They are development aids; CI does not run
them.
