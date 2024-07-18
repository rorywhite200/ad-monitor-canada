-- Funders table
CREATE TABLE funders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) UNIQUE NOT NULL
);

-- Pages table
CREATE TABLE pages (
    id BIGINT PRIMARY KEY,
    name VARCHAR(255),
    INDEX idx_name (name)
);

-- Ads table
CREATE TABLE ads (
    id BIGINT PRIMARY KEY,
    page_id BIGINT,
    funder_id INT,
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
    full_text_id VARCHAR(64) UNIQUE,
    platforms VARCHAR(255) DEFAULT NULL,
    languages VARCHAR(255) DEFAULT NULL,
    body TEXT,
    caption TEXT,
    description TEXT,
    link_title TEXT,
    FOREIGN KEY (page_id) REFERENCES pages(id),
    FOREIGN KEY (funder_id) REFERENCES funders(id),
    INDEX idx_date_range (starts_at, ends_at),
    INDEX idx_page_date_range (page_id, starts_at, ends_at),
    INDEX idx_funder_date_range (funder_id, starts_at, ends_at),
    FULLTEXT INDEX idx_full_text (full_text)
);

-- Ad demographics table
CREATE TABLE ad_demographics (
    id INT AUTO_INCREMENT PRIMARY KEY,
    ad_id BIGINT,
    gender ENUM('Male', 'Female', 'Unknown'),
    age_range ENUM('13-17', '18-24', '25-34', '35-44', '45-54', '55-64', '65+'),
    age_gender_percentage FLOAT,
    FOREIGN KEY (ad_id) REFERENCES ads(id),
    INDEX idx_ad_gender_age (ad_id, gender, age_range),
    INDEX idx_gender (gender),
    INDEX idx_age_range (age_range)
);

-- Ad provinces table
CREATE TABLE ad_provinces (
    id INT AUTO_INCREMENT PRIMARY KEY,
    ad_id BIGINT,
    name VARCHAR(255),
    province_percentage FLOAT,
    FOREIGN KEY (ad_id) REFERENCES ads(id),
    INDEX idx_province (name)
);

-- Stored procedure to update ad full text
DELIMITER //
CREATE PROCEDURE update_ad_full_text(IN ad_id_param BIGINT)
BEGIN
    UPDATE ads
    SET full_text = CONCAT_WS(' ', body, caption, description, link_title),
        full_text_id = SHA2(CONCAT_WS(' ', body, caption, description, link_title), 256)
    WHERE id = ad_id_param;
END //
DELIMITER ;

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
    a.caption,
    a.description,
    a.link_title,
    a.full_text,
    a.full_text_id,
    ad.gender,
    ad.age_range,
    ad.age_gender_percentage,
    ap.name AS province_name,
    ap.province_percentage
FROM 
    ads a
LEFT JOIN pages p ON a.page_id = p.id
LEFT JOIN funders f ON a.funder_id = f.id
LEFT JOIN ad_demographics ad ON a.id = ad.ad_id
LEFT JOIN ad_provinces ap ON a.id = ap.ad_id;