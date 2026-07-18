class VirtualSMS
  # ISO-3166 alpha-2 -> platform-network numeric country ID.
  #
  # Required only by create_rental(tier: "platform"): the backend's
  # provider-rental create endpoint takes a numeric ID, while every other
  # rentals endpoint resolves country_code server-side. Not every ISO code
  # the platform lists elsewhere is rental-capable on this tier; a country
  # missing from this table means it isn't available for platform-tier
  # rentals. Ported byte-for-byte from the internal MCP client's
  # PLATFORM_TIER_COUNTRY_IDS table so this SDK never drifts from it.
  PLATFORM_TIER_COUNTRY_IDS = {
    'RU' => 0, 'UA' => 1, 'KZ' => 2, 'CN' => 3, 'PH' => 4, 'MM' => 5, 'ID' => 6, 'MY' => 7, 'KE' => 8, 'TZ' => 9,
    'VN' => 10, 'KG' => 11, 'IL' => 13, 'HK' => 14, 'PL' => 15, 'GB' => 16, 'MG' => 17, 'CD' => 18, 'NG' => 19,
    'MO' => 20, 'EG' => 21, 'IN' => 22, 'IE' => 23, 'KH' => 24, 'LA' => 25, 'HT' => 26, 'CI' => 27, 'GM' => 28,
    'RS' => 29, 'YE' => 30, 'ZA' => 31, 'RO' => 32, 'CO' => 33, 'EE' => 34, 'AZ' => 35, 'CA' => 36, 'MA' => 37,
    'GH' => 38, 'AR' => 39, 'UZ' => 40, 'CM' => 41, 'TD' => 42, 'DE' => 43, 'LT' => 44, 'HR' => 45, 'SE' => 46,
    'IQ' => 47, 'NL' => 48, 'LV' => 49, 'AT' => 50, 'BY' => 51, 'TH' => 52, 'SA' => 53, 'MX' => 54, 'TW' => 55,
    'ES' => 56, 'IR' => 57, 'DZ' => 58, 'SI' => 59, 'BD' => 60, 'SN' => 61, 'TR' => 62, 'CZ' => 63, 'LK' => 64,
    'PE' => 65, 'PK' => 66, 'NZ' => 67, 'GN' => 68, 'ML' => 69, 'VE' => 70, 'ET' => 71, 'MN' => 72, 'BR' => 73,
    'AF' => 74, 'UG' => 75, 'AO' => 76, 'CY' => 77, 'FR' => 78, 'PG' => 79, 'MZ' => 80, 'NP' => 81, 'BE' => 82,
    'BG' => 83, 'HU' => 84, 'MD' => 85, 'IT' => 86, 'PY' => 87, 'HN' => 88, 'TN' => 89, 'NI' => 90, 'TL' => 91,
    'BO' => 92, 'CR' => 93, 'GT' => 94, 'AE' => 95, 'ZW' => 96, 'PR' => 97, 'SD' => 98, 'TG' => 99, 'KW' => 100,
    'SV' => 101, 'LY' => 102, 'JM' => 103, 'TT' => 104, 'EC' => 105, 'SZ' => 106, 'OM' => 107, 'BA' => 108,
    'DO' => 109, 'SY' => 110, 'QA' => 111, 'PA' => 112, 'CU' => 113, 'MR' => 114, 'SL' => 115, 'JO' => 116,
    'PT' => 117, 'BB' => 118, 'BI' => 119, 'BJ' => 120, 'BN' => 121, 'BS' => 122, 'BW' => 123, 'CF' => 125,
    'GD' => 127, 'GE' => 128, 'GR' => 129, 'GW' => 130, 'GY' => 131, 'IS' => 132, 'KM' => 133, 'KN' => 134,
    'LR' => 135, 'LS' => 136, 'MW' => 137, 'NA' => 138, 'NE' => 139, 'RW' => 140, 'SK' => 141, 'SR' => 142,
    'TJ' => 143, 'MC' => 144, 'BH' => 145, 'RE' => 146, 'ZM' => 147, 'US' => 187
  }.freeze
end
