-- Drop existing tables if they exist
DROP TABLE IF EXISTS ad_provinces;
DROP TABLE IF EXISTS ad_demographics;
DROP TABLE IF EXISTS ads;
DROP TABLE IF EXISTS pages;
DROP TABLE IF EXISTS funders;
-- Drop existing view if it exists
DROP VIEW IF EXISTS ad_data_export;

-- Funders table
CREATE TABLE funders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE
);

-- Insert the "Unspecified" funder
INSERT INTO funders (id, name) VALUES (0, 'Unspecified');

-- Pages table
CREATE TABLE pages (
    id BIGINT PRIMARY KEY,
    name VARCHAR(255),
    is_derived_id BOOLEAN,
    INDEX idx_name (name)
);

-- Ads table
CREATE TABLE ads (
    id BIGINT PRIMARY KEY,
    page_id BIGINT NOT NULL,
    funder_id INT NOT NULL,
    created_at DATETIME,
    starts_at DATETIME,
    ends_at DATETIME,
    ad_library_url TEXT,
    currency VARCHAR(10),
    audience_min INT,
    audience_max INT,
    views_min INT,
    views_max INT,
    cost_min DECIMAL(10, 2),
    cost_max DECIMAL(10, 2),
    full_text TEXT,
    full_text_id VARCHAR(64),
    platforms VARCHAR(255) DEFAULT NULL,
    languages VARCHAR(255) DEFAULT NULL,
    body TEXT,
    link_url TEXT,
    description TEXT,
    link_title TEXT,
    FOREIGN KEY (page_id) REFERENCES pages(id),
    FOREIGN KEY (funder_id) REFERENCES funders(id),
    INDEX idx_date_range (starts_at, ends_at),
    INDEX idx_page_date_range (page_id, starts_at, ends_at),
    INDEX idx_funder_date_range (funder_id, starts_at, ends_at),
    INDEX idx_funder (funder_id),
    INDEX idx_full_text_id (full_text_id),
    FULLTEXT INDEX idx_full_text (full_text)
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
    INDEX idx_age_range (age_range)
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
    INDEX idx_province (province)
);

-- View for easy data export
CREATE OR REPLACE VIEW ad_data_export AS
SELECT
    a.id AS ad_id,
    a.page_id,
    p.name AS page_name,
    a.funder_id,
    f.name AS funder_name,
    a.created_at,
    a.starts_at,
    a.ends_at,
    a.ad_library_url,
    a.currency,
    a.audience_min,
    a.audience_max,
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
    a.full_text,
    a.full_text_id,
    ad.gender,
    ad.age_range,
    ad.age_gender_percentage,
    ap.province AS province_name,
    ap.province_percentage
FROM
    ads a
LEFT JOIN pages p ON a.page_id = p.id
LEFT JOIN funders f ON a.funder_id = f.id
LEFT JOIN ad_demographics ad ON a.id = ad.ad_id
LEFT JOIN ad_provinces ap ON a.id = ap.ad_id;