import finance_market_authorities/authority
import finance_track

pub fn all() -> List(authority.Authority) {
  [
    source(
      id: "cn_csrc",
      name: "China Securities Regulatory Commission (CSRC)",
      roles: [authority.SecuritiesRegulator],
      url: "https://www.csrc.gov.cn/csrc_en/c102023/common_zcnr.shtml?channelid=e9958c689bef4d468d81dc93c8d3479f",
      scope: "Unified mainland securities-market regulation and enforcement; not an issuer quote feed.",
      access: authority.PublicReadOnlySnapshot,
      redistribution: authority.NoRedistribution,
      limitations: [
        "finance_csrc_allows_only_market_monthly_market_weekly_and_consultation_feedback_pages",
        "raw_html_snapshot_only",
        "semantic_decoder_not_implemented",
      ],
    ),
    source(
      id: "cn_sse",
      name: "Shanghai Stock Exchange (SSE)",
      roles: [
        authority.FrontlineListingRegulator,
        authority.IssuerDisclosureRepository,
        authority.CalendarAndRulesPublisher,
      ],
      url: "https://www.sse.com.cn/disclosure/listedinfo/announcement/?PC=PC",
      scope: "SSE issuer announcements, listing supervision, calendars, rules, and dated notices.",
      access: authority.PublicSearchAccessUnreviewed,
      redistribution: authority.UnreviewedRedistribution,
      limitations: [
        "supported_machine_contract_not_approved",
        "venue_provenance_required",
      ],
    ),
    source(
      id: "cn_szse",
      name: "Shenzhen Stock Exchange (SZSE)",
      roles: [
        authority.FrontlineListingRegulator,
        authority.IssuerDisclosureRepository,
        authority.CalendarAndRulesPublisher,
      ],
      url: "https://www.szse.cn/disclosure/notice/company/index.html",
      scope: "SZSE issuer notices, listing supervision, calendars, rules, and dated notices.",
      access: authority.PublicSearchAccessUnreviewed,
      redistribution: authority.UnreviewedRedistribution,
      limitations: [
        "supported_machine_contract_not_approved",
        "venue_provenance_required",
      ],
    ),
    source(
      id: "cn_bse",
      name: "Beijing Stock Exchange (BSE)",
      roles: [
        authority.FrontlineListingRegulator,
        authority.IssuerDisclosureRepository,
        authority.CalendarAndRulesPublisher,
      ],
      url: "https://www.bse.cn/disclosure/announcement.html",
      scope: "BSE issuer announcements, listing supervision, calendars, rules, and dated notices.",
      access: authority.PublicSearchAccessUnreviewed,
      redistribution: authority.UnreviewedRedistribution,
      limitations: [
        "supported_machine_contract_not_approved",
        "venue_provenance_required",
      ],
    ),
    source(
      id: "cn_cninfo",
      name: "CNINFO",
      roles: [authority.IssuerDisclosureRepository],
      url: "https://www.cninfo.com.cn/?lang=zh",
      scope: "SZSE statutory disclosure platform with multi-venue presentation; exact known PDFs can be captured from the official repository, while aggregation never proves or erases the publishing venue.",
      access: authority.PublicReadOnlySnapshot,
      redistribution: authority.NoRedistribution,
      limitations: [
        "finance_cninfo_allows_only_one_exact_known_document_path_per_runtime",
        "public_search_contract_not_approved",
        "raw_pdf_bytes_and_structural_page_count_only",
        "semantic_decoder_and_text_layer_ocr_not_implemented",
        "repository_artifact_does_not_prove_issuing_venue",
      ],
    ),
    source(
      id: "cn_mof_cas",
      name: "Ministry of Finance — Chinese Accounting Standards",
      roles: [authority.AccountingStandardSetter],
      url: "https://kjs.mof.gov.cn/zt/kjzzss/kuaijizhunzeshishi/",
      scope: "CAS accounting standards; CSRC separately owns public-company disclosure requirements.",
      access: authority.LicenceReviewRequired,
      redistribution: authority.UnreviewedRedistribution,
      limitations: [
        "standard_version_required",
        "standard_redistribution_not_approved",
      ],
    ),
    source(
      id: "cn_mof_xbrl",
      name: "Ministry of Finance — CAS XBRL taxonomy",
      roles: [authority.ElectronicTaxonomyPublisher],
      url: "https://kjs.mof.gov.cn/zhengcefabu/201010/t20101020_343461.htm",
      scope: "National CAS XBRL general taxonomy and related electronic financial-reporting materials.",
      access: authority.LicenceReviewRequired,
      redistribution: authority.UnreviewedRedistribution,
      limitations: [
        "taxonomy_version_required",
        "taxonomy_redistribution_not_approved",
      ],
    ),
  ]
}

pub fn registry() -> authority.Registry {
  let assert Ok(value) = authority.registry(finance_track.Cn, all())
  value
}

fn source(
  id id: String,
  name name: String,
  roles roles: List(authority.Role),
  url url: String,
  scope scope: String,
  access access: authority.Access,
  redistribution redistribution: authority.Redistribution,
  limitations limitations: List(String),
) -> authority.Authority {
  let assert Ok(value) =
    authority.new(
      track: finance_track.Cn,
      id: id,
      name: name,
      roles: roles,
      official_url: url,
      scope: scope,
      access: access,
      redistribution: redistribution,
      limitations: limitations,
    )
  value
}
