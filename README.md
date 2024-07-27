# Ad Monitor Canada

<img src="https://github.com/rorywhite200/ad-monitor-canada/assets/125914446/6339ee9f-9509-4a21-b0c0-bfc6f568cbc7" alt="ad monitor" width="200">

## Overview

**Ad Monitor Canada** collects and stores political advertising data from Meta's platforms.

Every 24 hours, our Github Actions workflow queries the **Meta Ad Library API** for all political advertisements shown in Canada over the past month. The ads are inserted into a MySQL database, allowing journalists and researchers to query the data.

## Data collection

Ad data is harvested from the [Meta Ad Library API](https://www.facebook.com/ads/library/api/?source=nav-header). The `main.py` file initiates the process and the `ad_collector.py` orchestrates the data collection using `fb_ads_library_api.py` to request data and helper functions in `ad_database_utils.py` to submit the results to a MySQL database.

- `fb_ads_library_api.py` was adapted from an example in the [Facebook Ad Library API Script Repository](https://github.com/facebookresearch/Ad-Library-API-Script-Repository).
- `ad_collector.py` was inspired by the [PoliDashboard](https://github.com/smlabto/polidashboard).

Meta Ad Library API keys are defined as Github Secrets and rotated to avoid rate limits. We use a sliding window approach to avoid requesting too many ads.

## Data wrangling

- **Ad end dates**: To handle ongoing ads, empty end dates are imputed with the date of collection and status is tracked through the `is_active` property.
- **Text truncation**: Body, description, link title capped at 5,000 characters each to enable storage.
- **Region categorization**: Data for non-Canadian regions is aggregated as '_Overseas_'
- **Handling nulls**: Missing gender/age/funder/region labeled '_Unspecified_' or '_unspecified_' while absent page IDs are replaced with hashed page_name.

## Data storage

### Database structure

Our database comprises five tables: `ads`, `funders`, `pages`, `ad_demographics` and `ad_provinces.`

### Views
- `ads_view`: One row per ad, joined with its `funder_name` and `page_name`
- `ads_view_demographics`: Multiple rows per ad with one for each target demographic
- `ads_view_provinces`: Multiple rows per ad with one for each target province

### Procedures
`get_pivot_table`: Aggregates summary statistics for funders, pages or both, filtered by keyword and date range.

**Get aggregated totals for funders of ads mentioning "climate" that were active between January 15th and July 15th 2024:**
```sql
CALL get_pivot_table('climate', '2024-01-15', '2024-06-15', 'funder')

--- Replace the word 'funder' with 'page' to get page level data, or 'both' to view a combination
```

**Get aggregated totals for pages for all ads active since February 12th 2019:**
```sql
CALL get_pivot_table(NULL, '2019-02-12', NULL, 'page')
```





## Questions

### How does this differ from the PoliDashboard approach?

PoliDashboard tracks ads launched in the past three days but does not follow these ads over the longer term. We update statistics daily for all ads that have been active in the last month, allowing us to monitor spending, views and status.



