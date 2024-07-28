-- Drop existing tables if they exist
DROP TABLE IF EXISTS ad_provinces;
DROP TABLE IF EXISTS ad_demographics;
DROP TABLE IF EXISTS ads;
DROP TABLE IF EXISTS pages;
DROP TABLE IF EXISTS funders;

-- Funders table
CREATE TABLE funders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    INDEX idx_funder_name (name),
    INDEX idx_funders_id_name (id, name)
);

-- Insert the "Unspecified" funder
INSERT INTO funders (id, name) VALUES (0, 'Unspecified');

-- Pages table
CREATE TABLE pages (
    id BIGINT PRIMARY KEY,
    name VARCHAR(255),
    is_derived_id BOOLEAN,
    INDEX idx_name (name),
    INDEX idx_pages_id_name (id, name)
);

-- Ads table
CREATE TABLE ads (
    id BIGINT PRIMARY KEY,
    page_id BIGINT NOT NULL,
    funder_id INT NOT NULL,
    created_date DATETIME,
    start_date DATETIME,
    end_date DATETIME,
    is_active BOOLEAN DEFAULT FALSE,
    ad_library_url TEXT,
    currency VARCHAR(10),
    audience_min INT,
    audience_max INT,
    views_min INT,
    views_max INT,
    cost_min DECIMAL(10, 2),
    cost_max DECIMAL(10, 2),
    content_id VARCHAR(64),
    platforms VARCHAR(255) DEFAULT NULL,
    languages VARCHAR(255) DEFAULT NULL,
    body TEXT,
    link_url TEXT,
    description TEXT,
    link_title TEXT,
    provinces JSON,
    demographics JSON,
    FOREIGN KEY (page_id) REFERENCES pages(id),
    FOREIGN KEY (funder_id) REFERENCES funders(id),
    INDEX idx_date_range (start_date, end_date),
    INDEX idx_page_date_range (page_id, start_date, end_date),
    INDEX idx_funder_date_range (funder_id, start_date, end_date),
    FULLTEXT INDEX idx_full_text (body, description, link_title),
    FULLTEXT INDEX idx_full_text_body (body),
    INDEX idx_ads_id (id),
    INDEX idx_ads_covering (id, page_id, funder_id),
    INDEX idx_funder_page_date (funder_id, page_id, start_date, end_date)
);

-- Ad demographics table
CREATE TABLE ad_demographics (
    ad_id BIGINT,
    gender ENUM('male', 'female', 'unknown', 'unspecified') DEFAULT 'unspecified',
    age_range ENUM('13-17', '18-24', '25-34', '35-44', '45-54', '55-64', '65+', 'unspecified') DEFAULT 'unspecified',
    age_gender_percentage FLOAT,
    PRIMARY KEY (ad_id, gender, age_range),
    FOREIGN KEY (ad_id) REFERENCES ads(id),
    INDEX idx_gender (gender),
    INDEX idx_age_range (age_range),
);

-- Ad provinces table
CREATE TABLE ad_provinces (
    ad_id BIGINT,
    province ENUM(
        'Alberta', 'British Columbia', 'Manitoba', 'New Brunswick',
        'Newfoundland and Labrador', 'Nova Scotia', 'Ontario',
        'Prince Edward Island', 'Quebec', 'Saskatchewan',
        'Northwest Territories', 'Yukon', 'Nunavut',
        'Overseas', 'Unspecified'
    ) DEFAULT 'Unspecified',
    province_percentage FLOAT NOT NULL,
    PRIMARY KEY (ad_id, province),
    FOREIGN KEY (ad_id) REFERENCES ads(id),
    INDEX idx_province (province),
);

DELIMITER //
DROP PROCEDURE IF EXISTS get_pivot_table //

CREATE PROCEDURE get_pivot_table(
    IN p_keyword VARCHAR(255),
    IN p_start_date DATE,
    IN p_end_date DATE,
    IN p_group_by VARCHAR(10)
)
BEGIN
    -- Set default value for p_group_by if it's NULL
    IF p_group_by IS NULL OR p_group_by = '' THEN
        SET p_group_by = 'page';
    END IF;
    
    -- Common Table Expression (CTE) to calculate the spending estimates
    WITH ad_spending_estimates AS (
        SELECT 
            id,
            page_id,
            funder_id,
            -- Calculate the days the ad overlapped with the specified period
            GREATEST(
                DATEDIFF(
                    LEAST(COALESCE(end_date, CURDATE()), p_end_date),
                    GREATEST(start_date, p_start_date)
                ) + 1,
                0
            ) AS days_active_in_period,
            -- Calculate daily spending estimates
            cost_min / GREATEST(DATEDIFF(COALESCE(end_date, CURDATE()), start_date), 1) AS daily_min_spend,
            cost_max / GREATEST(DATEDIFF(COALESCE(end_date, CURDATE()), start_date), 1) AS daily_max_spend,
            -- Calculate daily views estimates
            views_min / GREATEST(DATEDIFF(COALESCE(end_date, CURDATE()), start_date), 1) AS daily_min_views,
            views_max / GREATEST(DATEDIFF(COALESCE(end_date, CURDATE()), start_date), 1) AS daily_max_views
        FROM ads
        WHERE 
            (p_keyword IS NULL OR MATCH(body, description, link_title) AGAINST(p_keyword IN BOOLEAN MODE))
            AND (
                (start_date <= p_end_date AND end_date >= p_start_date)
                OR (start_date <= p_end_date AND end_date IS NULL)
                OR (start_date IS NULL AND end_date >= p_start_date)
                OR (start_date IS NULL AND end_date IS NULL AND is_active = TRUE)
            )
            AND currency = 'CAD'
    )
    
    -- Main query using the CTE
    SELECT 
        group_id AS id,
        group_name AS name,
        COUNT(DISTINCT ad_id) AS ad_count,
        SUM(min_spend_for_period) AS total_min_spend_for_period,
        SUM(max_spend_for_period) AS total_max_spend_for_period,
        SUM(min_views_for_period) AS total_min_views_for_period,
        SUM(max_views_for_period) AS total_max_views_for_period
    FROM (
        SELECT 
            CASE 
                WHEN p_group_by = 'funder' THEN f.id 
                WHEN p_group_by = 'page' THEN p.id
                ELSE CONCAT(f.id, '-', p.id)
            END AS group_id,
            CASE 
                WHEN p_group_by = 'funder' THEN f.name 
                WHEN p_group_by = 'page' THEN p.name
                ELSE CONCAT(f.name, ' - ', p.name)
            END AS group_name,
            ase.id AS ad_id,
            ase.daily_min_spend * ase.days_active_in_period AS min_spend_for_period,
            ase.daily_max_spend * ase.days_active_in_period AS max_spend_for_period,
            ase.daily_min_views * ase.days_active_in_period AS min_views_for_period,
            ase.daily_max_views * ase.days_active_in_period AS max_views_for_period
        FROM 
            ad_spending_estimates ase
        JOIN 
            funders f ON ase.funder_id = f.id
        JOIN 
            pages p ON ase.page_id = p.id
        WHERE 
            f.name != 'Unspecified' OR p_group_by = 'page'
    ) AS subquery
    GROUP BY 
        group_id, group_name
    ORDER BY 
        ad_count DESC;
END //

DELIMITER ;

-- Drop the view if it exists
DROP VIEW IF EXISTS ads_view;

-- Create the view
CREATE VIEW ads_view AS
SELECT
    a.id AS ad_id,
    a.page_id,
    p.name AS page_name,
    f.name AS funder_name,
    a.start_date,
    a.end_date,
    a.is_active,
    a.ad_library_url,
    a.currency,
    a.views_min,
    a.views_max,
    a.cost_min,
    a.cost_max,
    a.platforms,
    a.languages,
    a.body,
    a.link_url,
    a.description,
    a.link_title,
    a.provinces,
    a.demographics
FROM ads a
JOIN pages p ON a.page_id = p.id
JOIN funders f ON a.funder_id = f.id;

-- Drop the view if it exists
DROP VIEW IF EXISTS ads_view_demographics;

-- Create the view
CREATE VIEW ads_view_demographics AS
SELECT
    a.id AS ad_id,
    p.name AS page_name,
    f.name AS funder_name,
    a.start_date,
    a.end_date,
    a.is_active,
    a.ad_library_url,
    a.currency,
    a.views_min,
    a.views_max,
    a.cost_min,
    a.cost_max,
    a.platforms,
    a.languages,
    a.body,
    a.link_url,
    a.description,
    a.link_title,
    ad.gender,
    ad.age_range,
    ad.age_gender_percentage
FROM ads a
JOIN pages p ON a.page_id = p.id
JOIN funders f ON a.funder_id = f.id
LEFT JOIN ad_demographics ad ON a.id = ad.ad_id;

-- Drop the view if it exists
DROP VIEW IF EXISTS ads_view_provinces;

-- Create the view
CREATE VIEW ads_view_provinces AS
SELECT
    a.id AS ad_id,
    p.name AS page_name,
    f.name AS funder_name,
    a.start_date,
    a.end_date,
    a.is_active,
    a.ad_library_url,
    a.currency,
    a.views_min,
    a.views_max,
    a.cost_min,
    a.cost_max,
    a.platforms,
    a.languages,
    a.body,
    a.link_url,
    a.description,
    a.link_title,
    ap.province,
    ap.province_percentage
FROM ads a
JOIN pages p ON a.page_id = p.id
JOIN funders f ON a.funder_id = f.id
LEFT JOIN ad_provinces ap ON a.id = ap.ad_id;