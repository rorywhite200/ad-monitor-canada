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
  FOREIGN KEY (page_id) REFERENCES pages(id),
  FOREIGN KEY (funder_id) REFERENCES funders(id),
  INDEX idx_date_range (starts_at, ends_at),
  INDEX idx_page_date_range (page_id, starts_at, ends_at),
  INDEX idx_funder_date_range (funder_id, starts_at, ends_at),
  FULLTEXT INDEX idx_full_text (full_text)
);

-- Ad content table
CREATE TABLE ad_content (
  id INT AUTO_INCREMENT PRIMARY KEY,
  ad_id BIGINT,
  component ENUM('body', 'caption', 'description', 'link_title'),
  text TEXT,
  FOREIGN KEY (ad_id) REFERENCES ads(id),
  INDEX idx_ad_component (ad_id, component)
);

-- Ad demographics table
CREATE TABLE ad_demographics (
  id INT AUTO_INCREMENT PRIMARY KEY,
  ad_id BIGINT,
  gender ENUM('Male', 'Female', 'Unknown'),
  age_range ENUM('13-17', '18-24', '25-34', '35-44', '45-54', '55-64', '65+', 'All'),
  percentage FLOAT,
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
  percentage FLOAT,
  FOREIGN KEY (ad_id) REFERENCES ads(id),
  INDEX idx_province (name)
);

-- Ad languages table
CREATE TABLE ad_languages (
  id INT AUTO_INCREMENT PRIMARY KEY,
  ad_id BIGINT,
  language_code VARCHAR(10),
  FOREIGN KEY (ad_id) REFERENCES ads(id),
  INDEX idx_language (language_code)
);

-- Ad platforms table
CREATE TABLE ad_platforms (
  id INT AUTO_INCREMENT PRIMARY KEY,
  ad_id BIGINT,
  name ENUM('Facebook', 'Instagram', 'Messenger', 'Audience Network'),
  FOREIGN KEY (ad_id) REFERENCES ads(id),
  INDEX idx_platform (name)
);

-- Stored procedure to update ad full text
DELIMITER //
CREATE PROCEDURE update_ad_full_text(IN ad_id_param BIGINT)
BEGIN
  UPDATE ads a
  SET full_text = (
    SELECT GROUP_CONCAT(text SEPARATOR ' ')
    FROM ad_content
    WHERE ad_id = ad_id_param AND component != 'caption'
  ),
  full_text_id = SHA2(full_text, 256)
  WHERE a.id = ad_id_param;
END //
DELIMITER ;