# extract-harness

Runs the shipping `PDFExtractor` natively on macOS, where Vision works — the iOS
Simulator can't create an inference context, so the unit tests only run on a device.

```sh
swiftc -O Tools/shim.swift NamesAndFaces/Import/PDFExtractor.swift Tools/main.swift -o /tmp/extract-harness
/tmp/extract-harness Tests/Fixtures
```
