import json
import re
from datetime import datetime
import requests

def get_ad_archive_id(data):
    """
    Extract ad_archive_id from ad_snapshot_url
    """
    return re.search(r"/\?id=([0-9]+)", data["ad_snapshot_url"]).group(1)

class FbAdsLibraryTraversal:
    default_url_pattern = (
        "https://graph.facebook.com/{}/ads_archive?unmask_removed_content=true&ad_type=POLITICAL_AND_ISSUE_ADS&access_token={}&"
        + "fields={}&search_terms={}&ad_reached_countries={}&search_page_ids={}&ad_delivery_date_min={}&ad_delivery_date_max={}&"
        + "ad_active_status={}&limit={}"
    )
    
    default_api_version = "v20.0"

    def __init__(
        self,
        access_tokens,
        fields,
        search_term,
        country,
        search_page_ids="",
        ad_delivery_date_min="1970-01-01",
        ad_delivery_date_max="1970-01-01",
        ad_active_status="ALL",
        initial_page_limit=500,
        api_version=None,
        retry_limit=0,
    ):
        self.access_tokens = access_tokens
        self.access_token = access_tokens[0]
        self.fields = fields
        self.search_term = search_term
        self.country = country
        self.search_page_ids = search_page_ids
        self.ad_active_status = ad_active_status
        self.initial_page_limit = initial_page_limit
        self.retry_limit = retry_limit
        self.ad_delivery_date_min = ad_delivery_date_min
        self.ad_delivery_date_max = ad_delivery_date_max
        if api_version is None:
            self.api_version = self.default_api_version
        else:
            self.api_version = api_version

    def generate_ad_archives(self):
        next_page_url = self.default_url_pattern.format(
            self.api_version,
            self.access_token,
            self.fields,
            self.search_term,
            self.country,
            self.search_page_ids,
            self.ad_delivery_date_min,
            self.ad_delivery_date_max,
            self.ad_active_status,
            self.initial_page_limit,
        )
        return self.__class__._get_ad_archives_from_url(
            next_page_url, 
            start_date=self.ad_delivery_date_min, 
            stop_date=self.ad_delivery_date_max, 
            retry_limit=self.retry_limit, 
            initial_page_limit=self.initial_page_limit,
            access_tokens=self.access_tokens
        )

    @staticmethod
    def _get_ad_archives_from_url(
        next_page_url, start_date="1970-01-01", stop_date=datetime.now().strftime('%Y-%m-%d'), retry_limit=5, initial_page_limit=500, access_tokens=None
    ):
        print(next_page_url)
        error_count = 0
        generation_count = 0
        api_key_index = 0
        current_page_limit = initial_page_limit
        successful_items_count = 0
        responsive_mode = False
        reached_single_item = False

        print(f"Starting to fetch ad archives with initial page limit: {initial_page_limit}")

        while next_page_url is not None:
            try:
                # Adjust the limit in the URL
                next_page_url = re.sub(r'limit=\d+', f'limit={current_page_limit}', next_page_url)
                print(f"Fetching URL with current page limit: {current_page_limit}")
                
                response = requests.get(next_page_url)
                FbAdsLibraryTraversal.print_rate_limit_headers(response.headers)

                response_data = json.loads(response.text)
                
                if "error" in response_data:
                    error_code = response_data["error"].get("code")
                    print(f"Error encountered: {response_data['error']}")
                    error_count += 1
                    print(f"Error count: {error_count}, Retry limit: {retry_limit}")

                    if error_code in [613, 190, 100]:
                        print(f"Error code {error_code} encountered. Rotating API key.")
                        api_key_index += 1
                        if api_key_index >= len(access_tokens):
                            print("All API keys have been exhausted. Terminating process.")
                            break
                        api_key = access_tokens[api_key_index % len(access_tokens)]
                        next_page_url = re.sub(r'access_token=[^&]+', f'access_token={api_key}', next_page_url)
                        print(f"Switched to API key {api_key_index + 1}")

                    if error_count >= retry_limit:
                        responsive_mode = True
                        print("Entering responsive mode due to repeated errors.")
                    
                    if responsive_mode:
                        if current_page_limit > 1:
                            new_limit = max(1, current_page_limit // 2)
                            print(f"Responsive mode: Halving page limit from {current_page_limit} to {new_limit}")
                            current_page_limit = new_limit
                            error_count = 0
                        elif "ad_creative_bodies" in next_page_url:
                            print("Removing ad_creative_bodies from URL for problematic ads.")
                            next_page_url = next_page_url.replace(
                                "ad_creation_time,ad_creative_bodies,ad_creative_link_captions",
                                "ad_creation_time,ad_creative_link_captions"
                            )
                            reached_single_item = True
                            error_count = 0
                        else:
                            print("Multiple errors encountered. Terminating process.")
                            break
                    continue

                filtered = response_data["data"]
                yield filtered

                generation_count += 1
                successful_items_count += len(filtered)
                print(f"Generation {generation_count}: Found {len(filtered)} matching ads. Total successful: {successful_items_count}")

                if "paging" in response_data and len(filtered) == current_page_limit:
                    next_page_url = response_data["paging"]["next"]
                    if reached_single_item:
                        print("Resetting to initial page limit after successful processing of single item.")
                        current_page_limit = initial_page_limit
                        successful_items_count = 0
                        responsive_mode = False
                        error_count = 0
                        reached_single_item = False
                        # Add ad_creative_bodies back to the URL
                        if "ad_creative_bodies" not in next_page_url:
                            next_page_url = next_page_url.replace(
                                "ad_creation_time,ad_creative_link_captions",
                                "ad_creation_time,ad_creative_bodies,ad_creative_link_captions"
                            )
                            print("Added ad_creative_bodies back to the URL after successful processing.")
                    elif successful_items_count >= initial_page_limit:
                        print("Resetting to initial page limit after successful processing of full batch.")
                        current_page_limit = initial_page_limit
                        successful_items_count = 0
                        responsive_mode = False
                        error_count = 0
                else:
                    next_page_url = None
                    break
            
            except Exception as e:
                print(f"Exception occurred: {e}")
                print(f"Headers: {response.headers if 'response' in locals() else 'No response headers available'}")
                error_count += 1
                if error_count >= retry_limit:
                    responsive_mode = True
                    print("Entering responsive mode due to repeated exceptions.")
                continue

        print(f"Finished processing. Total generations: {generation_count}")

    @staticmethod
    def print_rate_limit_headers(headers):
        rate_limit_keys = ['X-App-Usage', 'X-Ad-Account-Usage', 'X-Business-Use-Case-Usage']
        for key in rate_limit_keys:
            if key in headers:
                print(f"{key}: {headers[key]}")
        print("Other headers:")
        for key, value in headers.items():
            if key not in rate_limit_keys:
                print(f"{key}: {value}")

    @classmethod
    def generate_ad_archives_from_url(cls, failure_url, after_date="1970-01-01"):
        """
        if we failed from error, later we can just continue from the last failure url
        """
        return cls._get_ad_archives_from_url(failure_url, after_date=after_date)