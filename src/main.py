import mysql.connector
from mysql.connector import Error
from datetime import datetime, timedelta
from ad_collector import ad_collector
from ad_database_utils import load_funder_cache, load_page_cache
import os
from dotenv import load_dotenv
import pytz

# Load environment variables from .env file
load_dotenv(override=True)

def main():
    # Set parameters directly
    db_params = {
        'host': os.getenv('DB_HOST'),
        'database': os.getenv('DB_DATABASE'),
        'user': os.getenv('DB_USER'),
        'password': os.getenv('DB_PASSWORD'),
        'port': int(os.getenv('DB_PORT'))
    }

    facebook_api_keys = []
    for i in range(1, 8):
        key = os.getenv(f'FACEBOOK_API_KEY_{i}')
        if key:
            facebook_api_keys.append(key)
    
    # Connect to the database 
    try:
        connection = mysql.connector.connect(**db_params)
        cursor = connection.cursor(dictionary=True)
    except Error as error:
        print(f"Error while connecting to MySQL: {error}")
        return

    # Set the date range for ad collection
    timezone = pytz.timezone('America/Toronto')  # Set to Ottawa's timezone
    now = datetime.now(timezone)
    
    if now.hour == 0:  # Check if it's 12 AM
        # Collect data for the last 30 days
        start_date = now - timedelta(days=30)
    else:
        # Collect data for the current day
        start_date = now - timedelta(days=0)
    
    start_date_str = start_date.strftime('%Y-%m-%d')

    load_funder_cache(connection)
    load_page_cache(connection)

    # Call the ad_collector function
    try:
        collected_ads = ad_collector(start_date_str, connection, facebook_api_keys)
    except Exception as e:
        print(f"An error occurred during ad collection: {e}")
    finally:
        if connection.is_connected():
            cursor.close()
            connection.close()
            print("MySQL connection is closed")

if __name__ == "__main__":
    main()