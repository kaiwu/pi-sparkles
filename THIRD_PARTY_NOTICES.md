# Third-party notices

The all-in-one JavaScript bundle includes or derives from the following
third-party software. These notices do not change the licence of Pi Sparkles.

| Component | Version | Licence | Project |
| --- | --- | --- | --- |
| PDF.js (`pdfjs-dist`) | 6.2.108 | Apache-2.0 | https://github.com/mozilla/pdf.js |
| Gleam standard library | 1.0.3 and 1.0.5 | Apache-2.0 | https://github.com/gleam-lang/stdlib |
| Gleam JSON | 3.1.0 | Apache-2.0 | https://github.com/gleam-lang/json |
| Gleam JavaScript | 1.0.1 | Apache-2.0 | https://github.com/gleam-lang/javascript |

The complete Apache License, Version 2.0 is distributed in `LICENSE`.
`pdfjs-dist` remains an exact runtime dependency because the PDF text path
resolves packaged CMap assets from it. Pi host packages are not bundled into
the npm tarball.
