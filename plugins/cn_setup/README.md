# pi_sparkles_cn_setup

Experimental isolated mainland-China preflight. It registers `/cn-setup`,
`/cn-sources`, `cn_capabilities`, `cn_authorities`, and `cn_provider_health`.

Results visibly carry `track: "cn"`, CNY, `Asia/Shanghai`, `zh-CN`, and a
versioned `trackContext`. The plugin reports the installed pure identity,
calendar, rules, document/attachment, and accounting foundations while keeping
every provider-backed capability blocked until its source and rights are
approved.

The source view identifies CSRC, SSE, SZSE, BSE, CNINFO, and the Ministry of
Finance CAS/XBRL surfaces with official HTTPS links, exact roles, operational
access state, redistribution state, and limitations. A verified authority is
not reported as an unrestricted machine provider. The three exact
`finance_csrc` raw-HTML paths and exact, already-known `finance_cninfo` PDF paths
are marked `public_read_only_snapshot`; both remain no-redistribution and have
no semantic decoder. Exact PDFs receive bounded real-parser structural page
inspection, but no text-layer or OCR claim. CNINFO public search and all other
public/search surfaces remain unreviewed. A CNINFO repository artifact does not
prove an SSE/SZSE/BSE origin without separate official metadata.

No HK, SEC, OpenFIGI, or generic tool can satisfy a CN capability. The plugin
performs no network, environment, filesystem, or secret access, and unknown
providers remain `unknown` rather than healthy.
