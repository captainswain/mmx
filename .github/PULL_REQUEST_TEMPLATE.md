## Summary

Describe the change and the behaviour it fixes or adds.

## Evidence and scope

- [ ] I read `docs/REVERSE-ENGINEERING.md` / `docs/ARCHITECTURE.md` where relevant.
- [ ] New claims are labelled observed, inferred or unknown.
- [ ] No Autodesk source code was copied.

## Tests

- [ ] `dart analyze` passes.
- [ ] `dart test` passes.
- [ ] `flutter analyze` passes (if the app changed).
- [ ] `flutter test` passes (if the app changed).
- [ ] New or changed geometry logic has watertightness/manifoldness/volume
      assertions, not only a smoke test.

## Notes

Link the issue, include a minimal reproducer, and mention any intentional
fallback or approximation.
