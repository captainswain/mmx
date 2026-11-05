# Documentation

Start here:

- [`REVERSE-ENGINEERING.md`](REVERSE-ENGINEERING.md) - the evidence-backed
  report on Meshmixer 3.5.0: artifact identity, `.mix` layout, tool semantics,
  RTTI, method names, and what remains unknown.
- [`RTTI.md`](RTTI.md) - class and vtable attribution.
- [`METHODS.md`](METHODS.md) - recovered `Class::Method` names and related
  open-source projects.
- [`TOOL-MATRIX.md`](TOOL-MATRIX.md) - every recovered tool/action mapped to
  the kernel, Studio UI, tests and status.
- [`ARCHITECTURE.md`](ARCHITECTURE.md) - technology choices, module map and
  performance engineering.
- [`CLI.md`](CLI.md) - command-line reference and examples.
- [`TESTING.md`](TESTING.md) - test commands, coverage and known gaps.
- [`REMEDIATION-PLAN.md`](REMEDIATION-PLAN.md) - the completed correctness and
  coverage pass.
- [`FINISH-PLAN.md`](FINISH-PLAN.md) - the remaining work to close the project:
  evidence closure, feature parity, oracle validation and release.
- [`reference/`](reference/) - public Autodesk API headers, help notes and the
  command parameter reference used as source evidence.

The project labels claims as **[observed]** (directly evidenced from the
binary, public headers or runtime), **[inferred]** (a reasoned conclusion) and
**[unknown]** (not established). Keep that distinction when editing docs.
