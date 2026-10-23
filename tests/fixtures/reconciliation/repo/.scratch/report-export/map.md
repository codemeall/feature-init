# Source map

- Formatter and quoting: src/export.mjs, exportReport and quote.
- Unit checks for visible rows, stable order and escaping: tests/export.test.mjs.
- Date conversion: the toISOString call in src/export.mjs; it has not been localized.
- Performance acceptance: no runtime evidence; see verification.md.
- The current implementation constructs one complete string. No decision record explains that choice.
