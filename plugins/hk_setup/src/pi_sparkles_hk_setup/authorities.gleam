import finance_market_authorities/authority
import finance_track

pub fn all() -> List(authority.Authority) {
  [
    source(
      id: "hk_sfc",
      name: "Securities and Futures Commission (SFC)",
      roles: [authority.SecuritiesRegulator],
      url: "https://www.sfc.hk/EN/about-the-sfc/our-role/",
      scope: "Hong Kong statutory securities and futures regulation and oversight of listing regulation.",
      access: authority.PublicReadOnlySnapshot,
      redistribution: authority.NoRedistribution,
      limitations: [
        "finance_sfc_allows_only_press_release_rss",
        "raw_xml_snapshot_only",
        "semantic_decoder_not_implemented",
      ],
    ),
    source(
      id: "hk_sehk",
      name: "Stock Exchange of Hong Kong (SEHK)",
      roles: [authority.FrontlineListingRegulator],
      url: "https://www.sfc.hk/en/Regulatory-functions/Corporates",
      scope: "Frontline regulator of listed companies under SFC supervision; the linked SFC page documents the role split.",
      access: authority.VerifiedReference,
      redistribution: authority.ReferenceLinkOnly,
      limitations: ["regulatory_role_reference_not_a_data_feed"],
    ),
    source(
      id: "hk_hkexnews",
      name: "HKEXnews",
      roles: [authority.IssuerDisclosureRepository],
      url: "https://www2.hkexnews.hk/Global/Exchange/About-Us?sc_lang=en",
      scope: "Centralized official issuer filings, disclosures, and HKEX-generated issuer regulatory information; exact known PDFs can be captured from HKEXnews.",
      access: authority.PublicReadOnlySnapshot,
      redistribution: authority.NoRedistribution,
      limitations: [
        "finance_hkex_allows_only_one_exact_known_document_path_per_runtime",
        "public_search_contract_not_approved",
        "raw_pdf_bytes_and_structural_page_count_only",
        "semantic_decoder_and_text_layer_ocr_not_implemented",
      ],
    ),
    source(
      id: "hk_hkicpa",
      name: "Hong Kong Institute of Certified Public Accountants (HKICPA)",
      roles: [authority.AccountingStandardSetter],
      url: "https://www.hkicpa.org.hk/en/Standards-setting/Standards/Members-Handbook-and-Due-Process/Due-Process/Financial-reporting",
      scope: "HKFRS standard setting; qualifying HK issuers may instead report under accepted IFRS or CASBE rules.",
      access: authority.LicenceReviewRequired,
      redistribution: authority.UnreviewedRedistribution,
      limitations: [
        "standard_copyright_review_required",
        "fact_standard_must_be_explicit",
      ],
    ),
    source(
      id: "hk_hkex_calendars",
      name: "HKEX calendars and rules",
      roles: [authority.CalendarAndRulesPublisher],
      url: "https://www.hkex.com.hk/mutual-market/stock-connect/reference-materials/trading-hour%2C-trading-and-settlement-calendar?sc_lang=en",
      scope: "Official HKEX and Stock Connect schedules; local HK, derivatives, and Connect calendars are distinct datasets.",
      access: authority.LicenceReviewRequired,
      redistribution: authority.UnreviewedRedistribution,
      limitations: [
        "calendar_scope_must_be_explicit",
        "fixture_rights_not_approved",
      ],
    ),
    source(
      id: "hk_hkex_iis",
      name: "HKEX Issuer Information Feed Service (IIS)",
      roles: [authority.ProductionIssuerFeed],
      url: "https://www.hkex.com.hk/Services/Market-Data-Services/Infrastructure/Issuer-Information-feed-Service-%28IIS%29?sc_lang=en",
      scope: "Versioned production feed of listed-company and issuer news and announcements.",
      access: authority.ProductionContractRequired,
      redistribution: authority.ContractControlled,
      limitations: [
        "production_contract_required",
        "transmission_version_required",
      ],
    ),
    source(
      id: "hk_hkex_market_data",
      name: "HKEX market-data licensing",
      roles: [authority.MarketDataLicensor],
      url: "https://www.hkex.com.hk/Services/Market-Data-Services/Real-Time-Data-Services/Data-Licensing?sc_lang=en",
      scope: "HKEX real-time and delayed market-data products and redistribution licences; separate from issuer filings.",
      access: authority.ProductionContractRequired,
      redistribution: authority.ContractControlled,
      limitations: [
        "named_product_required",
        "entitlement_and_redistribution_required",
      ],
    ),
  ]
}

pub fn registry() -> authority.Registry {
  let assert Ok(value) = authority.registry(finance_track.Hk, all())
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
      track: finance_track.Hk,
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
