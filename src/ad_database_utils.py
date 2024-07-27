import hashlib
import mysql.connector
from mysql.connector import Error
import unicodedata
import random


CANADIAN_PROVINCES = {
    'Alberta', 'British Columbia', 'Manitoba', 'New Brunswick', 'Newfoundland and Labrador',
    'Nova Scotia', 'Ontario', 'Prince Edward Island', 'Quebec', 'Saskatchewan', 
    'Northwest Territories', 'Yukon', 'Nunavut'
}

funder_cache = {}
page_cache = {}

def load_funder_cache(db_connection):
    global funder_cache
    cursor = db_connection.cursor(dictionary=True)
    cursor.execute("SELECT id, name FROM funders")
    funders = cursor.fetchall()
    funder_cache = {normalize_name(funder['name']): funder['id'] for funder in funders}

def load_page_cache(db_connection):
    global page_cache
    cursor = db_connection.cursor(dictionary=True)
    cursor.execute("SELECT id, name FROM pages")
    pages = cursor.fetchall()
    page_cache = {page['id']: page['name'] for page in pages}

def normalize_name(name):
    nfkd_form = unicodedata.normalize('NFKD', name)
    return ''.join([c for c in nfkd_form if not unicodedata.combining(c)]).lower()

def get_or_create_funder_id(funder_name, db_connection):
    global funder_cache
    funder_name_normalized = normalize_name(funder_name)
    if funder_name_normalized in funder_cache:
        return funder_cache[funder_name_normalized]
    
    funder_id = insert_new_funder(funder_name, db_connection)
    funder_cache[funder_name_normalized] = funder_id
    return funder_id

def insert_new_funder(funder_name, db_connection):
    cursor = db_connection.cursor()
    cursor.execute("INSERT INTO funders (name) VALUES (%s)", (funder_name,))
    db_connection.commit()
    return cursor.lastrowid

def generate_deterministic_id(username):
    hash_object = hashlib.md5(username.encode())
    hash_int = int(hash_object.hexdigest(), 16)
    return hash_int % 1000000000000000000

def generate_random_id():
    return random.randint(10**17, 10**18 - 1)

def get_or_create_page(page_id, page_name, db_connection):
    global page_cache

    is_derived_id = False
    if page_id is None or page_id == 0 or page_id == "0" or str(page_id).strip() == '':
        if page_name and str(page_name).strip() != '':
            page_id = generate_deterministic_id(page_name)
            is_derived_id = True
        else:
            page_id = generate_random_id()
    try:
        page_id = int(page_id)
    except ValueError:
        raise ValueError("page_id must be an integer")

    if len(str(abs(page_id))) >= 19:
        raise ValueError("page_id length must be less than 19 digits")

    if page_id in page_cache:
        return page_id

    insert_new_page(page_id, page_name, is_derived_id, db_connection)
    page_cache[page_id] = page_name

    return page_id

def insert_new_page(page_id, page_name, is_derived_id, db_connection):
    cursor = db_connection.cursor()
    cursor.execute("INSERT INTO pages (id, name, is_derived_id) VALUES (%s, %s, %s)", 
                   (page_id, page_name, is_derived_id))
    db_connection.commit()

def generate_content_id(ad_data):
    full_text = ' '.join(filter(None, [
        ad_data.get('body', ''),
        ad_data.get('description', ''),
        ad_data.get('link_title', '')
    ]))
    content_id = hashlib.sha256(full_text.encode()).hexdigest()
    return content_id

def batch_insert_ads(ads_data, db_connection):
    print("Inserting ad data")
    cursor = db_connection.cursor()
    insert_query = """
        INSERT INTO ads (id, page_id, funder_id, created_date, start_date, end_date, is_active,
                         ad_library_url, currency, audience_min, audience_max, 
                         views_min, views_max, cost_min, cost_max, platforms, 
                         languages, body, link_url, description, link_title, content_id, provinces, demographics)
        VALUES (%(id)s, %(page_id)s, %(funder_id)s, %(created_date)s, %(start_date)s, 
                %(end_date)s, %(is_active)s, %(ad_library_url)s, %(currency)s, %(audience_min)s, 
                %(audience_max)s, %(views_min)s, %(views_max)s, %(cost_min)s, 
                %(cost_max)s, %(platforms)s, %(languages)s, %(body)s, %(link_url)s, 
                %(description)s, %(link_title)s, %(content_id)s, %(provinces)s, %(demographics)s)
        ON DUPLICATE KEY UPDATE
            page_id = VALUES(page_id),
            funder_id = VALUES(funder_id),
            created_date = VALUES(created_date),
            start_date = VALUES(start_date),
            end_date = VALUES(end_date),
            is_active = VALUES(is_active),
            ad_library_url = VALUES(ad_library_url),
            currency = VALUES(currency),
            audience_min = VALUES(audience_min),
            audience_max = VALUES(audience_max),
            views_min = VALUES(views_min),
            views_max = VALUES(views_max),
            cost_min = VALUES(cost_min),
            cost_max = VALUES(cost_max),
            platforms = VALUES(platforms),
            languages = VALUES(languages),
            body = VALUES(body),
            link_url = VALUES(link_url),
            description = VALUES(description),
            link_title = VALUES(link_title),
            content_id = VALUES(content_id),
            provinces = VALUES(provinces),
            demographics = VALUES(demographics)
    """
    
    for ad in ads_data:
        content_id = generate_content_id(ad)
        ad['content_id'] = content_id
    
    cursor.executemany(insert_query, ads_data)
    print("Finished inserting ad data")
    db_connection.commit()

def batch_insert_demographic_data(demographic_data, db_connection):
    print("Inserting demographic data")
    cursor = db_connection.cursor()
    insert_query = """
        INSERT INTO ad_demographics (ad_id, gender, age_range, age_gender_percentage)
        VALUES (%s, %s, %s, %s)
        ON DUPLICATE KEY UPDATE
            age_gender_percentage = VALUES(age_gender_percentage)
    """
    cursor.executemany(insert_query, demographic_data)
    db_connection.commit()

def batch_insert_region_data(region_data, db_connection):
    print("Inserting region data")
    cursor = db_connection.cursor()
    insert_query = """
        INSERT INTO ad_provinces (ad_id, province, province_percentage)
        VALUES (%s, %s, %s)
        ON DUPLICATE KEY UPDATE
            province_percentage = VALUES(province_percentage)
    """
    cursor.executemany(insert_query, region_data)
    db_connection.commit()


def prepare_region_data(regions):
    if not regions or regions == '':
        return [{'region': 'Unspecified', 'percentage': 1.0}]
    
    canadian_regions = []
    overseas_percentage = 0.0

    for region in regions:
        # Check if the region has the 'region' and 'percentage' properties
        if 'region' not in region or region['region'] is None or 'percentage' not in region or region['percentage'] is None:
            continue  # Skip this iteration if required properties are missing

        if region['region'] in CANADIAN_PROVINCES:
            canadian_regions.append({'region': region['region'], 'percentage': float(region['percentage'])})
        else:
            overseas_percentage += float(region['percentage'])

    if overseas_percentage > 0:
        canadian_regions.append({'region': 'Overseas', 'percentage': overseas_percentage})

    return canadian_regions

def prepare_demographic_data(demographics):
    expected_age_ranges = {'13-17', '18-24', '25-34', '35-44', '45-54', '55-64', '65+', 'unspecified'}
    expected_genders = {'male', 'female', 'unknown', 'unspecified'}
    prepared_demographics = []
    
    for demographic in demographics or [{'gender': 'unspecified', 'age': 'unspecified', 'percentage': 1.0}]:

        if 'age' not in demographic or 'percentage' not in demographic or demographic['percentage'] is None or 'gender' not in demographic:
            continue  # Skip this iteration if required properties are missing

        age_range = demographic['age'] if demographic['age'] in expected_age_ranges else 'unspecified'
        gender = demographic['gender'] if demographic['gender'] in expected_genders else 'unspecified'
        prepared_demographics.append({
            'gender': gender,
            'age_range': age_range,
            'percentage': float(demographic['percentage'])
        })
    
    return prepared_demographics

def process_in_batches(items, batch_size, connection, process_function):
    total_items = len(items)
    for start in range(0, total_items, batch_size):
        batch = items[start:start + batch_size]
        process_function(batch, connection)

def truncate_fields(items, max_length, fields):
    for item in items:
        for field in fields:
            if field in item and len(item[field]) > max_length:
                item[field] = item[field][:max_length]