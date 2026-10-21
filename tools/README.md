# Developer Tools

These tools are manually run diagnostics and regression harnesses. They are not
part of the Mos app target.

- `hidpp/`: Logitech HID++ probing, divert, undivert, and verification scripts.
- `regression/`: small standalone regression harnesses that compile selected app
  components outside the full Xcode test target.

Run scripts from the repository root unless a script says otherwise.

The button-core lifecycle harness uses test doubles for event taps and options;
it does not install global event taps or post input events:

```bash
mkdir -p .cache
swiftc Mos/ButtonCore/ButtonCore.swift tools/regression/button-core-lifecycle-tests.swift -o .cache/button-core-lifecycle-tests
.cache/button-core-lifecycle-tests
```
