import os
import sys
import json
from datetime import datetime
import pytz
from fb_ads_library_api import FbAdsLibraryTraversal
from ad_database_utils import (
    get_or_create_funder_id,
    get_or_create_page,
    batch_insert_ads,
    batch_insert_demographic_data,
    batch_insert_region_data,
    prepare_region_data,
    prepare_demographic_data,
    process_in_batches,
    truncate_fields
)

CANADIAN_PROVINCES = {
    'Alberta', 'British Columbia', 'Manitoba', 'New Brunswick', 'Newfoundland and Labrador',
    'Nova Scotia', 'Ontario', 'Prince Edward Island', 'Quebec', 'Saskatchewan', 
    'Northwest Territories', 'Yukon', 'Nunavut'
}

def ad_collector(start_date, db_connection, facebook_api_keys):

    collector = FbAdsLibraryTraversal(
        facebook_api_keys,
        "id,ad_creation_time,ad_creative_bodies,ad_creative_link_captions,ad_creative_link_descriptions,ad_creative_link_titles,ad_delivery_start_time,ad_delivery_stop_time,ad_snapshot_url,currency,delivery_by_region,demographic_distribution,bylines,impressions,languages,page_id,page_name,publisher_platforms,spend,target_locations,target_gender,target_ages,estimated_audience_size",
        ".",
        "CA",
        ad_delivery_date_min=start_date,
        api_version="v20.0"
    )

    timezone = pytz.timezone('America/Toronto') 
    now = datetime.now(timezone).date()
    
    ads_list = []
    demographic_data_list = []
    region_data_list = []

    for ads in collector.generate_ad_archives():
        for ad in ads:
            funder_name = ad.get('bylines').strip() if ad.get('bylines') and ad.get('bylines').strip() else 'Unspecified'
            funder_id = get_or_create_funder_id(funder_name, db_connection)
            page_id = get_or_create_page(ad.get('page_id'), ad.get('page_name'), db_connection)

            # Prepare region data
            prepared_regions = prepare_region_data(ad.get('delivery_by_region'))
            
            # Prepare demographic data
            prepared_demographics = prepare_demographic_data(ad.get('demographic_distribution'))
            
            # Add funder_id, page_id, prepared regions, and prepared demographics to the ad dictionary
            ad_data = {
                'id': ad.get('id'),
                'page_id': page_id,
                'funder_id': funder_id,
                'created_date': datetime.strptime(ad['ad_creation_time'], '%Y-%m-%d') if 'ad_creation_time' in ad else None,
                'start_date': datetime.strptime(ad['ad_delivery_start_time'], '%Y-%m-%d') if 'ad_delivery_start_time' in ad else None,
                'end_date': datetime.strptime(ad['ad_delivery_stop_time'], '%Y-%m-%d') if 'ad_delivery_stop_time' in ad else now,
                'is_active': not ad.get('ad_delivery_stop_time'),
                'ad_library_url': ad.get('ad_snapshot_url'),
                'currency': ad.get('currency'),
                'audience_min': ad['estimated_audience_size']['lower_bound'] if 'estimated_audience_size' in ad and 'lower_bound' in ad['estimated_audience_size'] else None,
                'audience_max': ad['estimated_audience_size']['upper_bound'] if 'estimated_audience_size' in ad and 'upper_bound' in ad['estimated_audience_size'] else ad['estimated_audience_size']['lower_bound'] if 'estimated_audience_size' in ad and 'lower_bound' in ad['estimated_audience_size'] else None,
                'views_min': ad['impressions']['lower_bound'] if 'impressions' in ad and 'lower_bound' in ad['impressions'] else None,
                'views_max': ad['impressions']['upper_bound'] if 'upper_bound' in ad['impressions'] else None,
                'cost_min': ad['spend']['lower_bound'] if 'spend' in ad and 'lower_bound' in ad['spend'] else None,
                'cost_max': ad['spend']['upper_bound'] if 'upper_bound' in ad['spend'] else None,
                'platforms': ','.join(ad.get('publisher_platforms', [])),
                'languages': ','.join(ad.get('languages', [])),
                'body': ', '.join(ad.get('ad_creative_bodies', [])),
                'link_url': ', '.join(ad.get('ad_creative_link_captions', [])),
                'description': ', '.join(ad.get('ad_creative_link_descriptions', [])),
                'link_title': ', '.join(ad.get('ad_creative_link_titles', [])),
                'provinces': json.dumps(prepared_regions),  # Add prepared regions as JSON
                'demographics': json.dumps(prepared_demographics)  # Add prepared demographics as JSON
            }

            # Add demographic data to demographic_data_list
            for demographic in prepared_demographics:
                demographic_data_list.append((ad_data['id'], demographic['gender'], demographic['age_range'], demographic['percentage']))
                
            # Add region data to region_data_list
            for region in prepared_regions:
                region_data_list.append((ad_data['id'], region['region'], region['percentage']))

            ads_list.append(ad_data)
            
    fields_to_truncate = ['body', 'description', 'link_title']
    truncate_fields(ads_list, 5000, fields_to_truncate)

    process_in_batches(ads_list, 1000, db_connection, batch_insert_ads)
    process_in_batches(demographic_data_list, 1000, db_connection, batch_insert_demographic_data)
    process_in_batches(region_data_list, 1000, db_connection, batch_insert_region_data)

    return ads_list, demographic_data_list, region_data_list

