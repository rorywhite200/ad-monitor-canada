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
    INDEX idx_start_date (start_date),
    INDEX idx_page_date_range (page_id, start_date, end_date),
    INDEX idx_funder_date_range (funder_id, start_date, end_date),
    INDEX idx_funder (funder_id),
    FULLTEXT INDEX idx_full_text (body, description, link_title),
    FULLTEXT INDEX idx_full_text_body_desc (body, description),
    FULLTEXT INDEX idx_full_text_body (body),
    FULLTEXT INDEX idx_full_text_desc (description),
    FULLTEXT INDEX idx_full_text_link_title (link_title),
    FULLTEXT INDEX idx_full_text_link_url (link_url),
    INDEX idx_ads_page_id (page_id),
    INDEX idx_ads_id (id),
    INDEX idx_ads_created_at (created_date),
    INDEX idx_ads_covering (id, page_id, funder_id),
    INDEX idx_funder_page_date (funder_id, page_id, start_date, end_date),
    INDEX idx_is_active (is_active)
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
    INDEX idx_ad_id (ad_id)
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
    INDEX idx_ad_id (ad_id)
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
    
    IF p_group_by = 'funder' THEN
        SELECT 
            f.id AS funder_id,
            f.name AS funder_name,
            COUNT(DISTINCT a.id) AS ad_count,
            SUM(a.cost_min) AS total_spend_min,
            SUM(a.cost_max) AS total_spend_max,
            SUM(a.views_min) AS total_views_min,
            SUM(a.views_max) AS total_views_max
        FROM 
            ads a
        JOIN 
            funders f ON a.funder_id = f.id
        WHERE 
            f.name != 'Unspecified'
            AND (p_keyword IS NULL OR 
                 MATCH(a.body, a.description, a.link_title) AGAINST(p_keyword IN BOOLEAN MODE))
            AND (
                (a.start_date <= p_end_date AND a.end_date >= p_start_date)
                OR (a.start_date <= p_end_date AND a.end_date IS NULL)
                OR (a.start_date IS NULL AND a.end_date >= p_start_date)
                OR (a.start_date IS NULL AND a.end_date IS NULL AND a.is_active = TRUE)
            )
        GROUP BY 
            f.id, f.name
        ORDER BY 
            ad_count DESC;
    ELSEIF p_group_by = 'page' THEN
        SELECT 
            p.id AS page_id,
            p.name AS page_name,
            COUNT(a.id) AS ad_count,
            SUM(a.cost_min) AS total_spend_min,
            SUM(a.cost_max) AS total_spend_max,
            SUM(a.views_min) AS total_views_min,
            SUM(a.views_max) AS total_views_max
        FROM 
            ads a
        JOIN 
            pages p ON a.page_id = p.id
        WHERE 
            (p_keyword IS NULL OR 
             MATCH(a.body, a.description, a.link_title) AGAINST(p_keyword IN BOOLEAN MODE))
            AND (
                (a.start_date <= p_end_date AND a.end_date >= p_start_date)
                OR (a.start_date <= p_end_date AND a.end_date IS NULL)
                OR (a.start_date IS NULL AND a.end_date >= p_start_date)
                OR (a.start_date IS NULL AND a.end_date IS NULL AND a.is_active = TRUE)
            )
        GROUP BY 
            p.id, p.name
        ORDER BY 
            ad_count DESC;
    ELSEIF p_group_by = 'both' THEN
        SELECT 
            f.id AS funder_id,
            f.name AS funder_name,
            p.id AS page_id,
            p.name AS page_name,
            COUNT(a.id) AS ad_count,
            SUM(a.cost_min) AS total_spend_min,
            SUM(a.cost_max) AS total_spend_max,
            SUM(a.views_min) AS total_views_min,
            SUM(a.views_max) AS total_views_max
        FROM 
            ads a
        JOIN 
            funders f ON a.funder_id = f.id
        JOIN 
            pages p ON a.page_id = p.id
        WHERE 
            f.name != 'Unspecified'
            AND (p_keyword IS NULL OR 
                 MATCH(a.body, a.description, a.link_title) AGAINST(p_keyword IN BOOLEAN MODE))
            AND (
                (a.start_date <= p_end_date AND a.end_date >= p_start_date)
                OR (a.start_date <= p_end_date AND a.end_date IS NULL)
                OR (a.start_date IS NULL AND a.end_date >= p_start_date)
                OR (a.start_date IS NULL AND a.end_date IS NULL AND a.is_active = TRUE)
            )
        GROUP BY 
            f.id, f.name, p.id, p.name
        ORDER BY 
            ad_count DESC;
    END IF;
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