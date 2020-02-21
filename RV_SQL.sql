/***** Question 2 *****/
/* Assume Tables were Loaded as Below */ 
CREATE TABLE eduDf
(
  user_id varchar(100) NOT NULL,
  major varchar(200),
  startdate date,
  enddate date
);
COPY eduDf(user_id,major,startdate,enddate) 
FROM 'education.csv' DELIMITER ',' CSV HEADER;

CREATE TABLE posDf
(
  user_id varchar(100) NOT NULL,
  jobtitle varchar(200),
  startdate date,
  enddate date
);
COPY posDf(user_id,jobtitle,startdate,enddate) 
FROM 'positions.csv' DELIMITER ',' CSV HEADER;


CREATE TABLE senDf
(
  user_id varchar(100) NOT NULL,
  jobtitle varchar(200),
  seniority numeric 
);
COPY senDf(user_id,jobtitle,seniority) 
FROM 'jobtitle_seniority.csv' DELIMITER ',' CSV HEADER;

/* Begin Labeling */
/* modify eduDf table  */

UPDATE eduDf SET major = "" WHERE major IS NULL;
ALTER TABLE eduDf 
    ALTER major drop default,
    ALTER major type text[] using array[major], -- change major to a text ARRAY
    ALTER major set default '{}',
    ADD COLUMN hasbach boolean DEFAULT FALSE,
    ADD COLUMN startyear numeric DEFAULT NULL,
    ADD COLUMN endyear numeric DEFAULT NULL;
UPDATE eduDf
    SET startyear = date_part('year', startdate),
    SET endyear = date_part('year', enddate);

/* UDF hasbach_f:
set hasbach to True if row in edu_df has a bachelor word in major field */
CREATE FUNCTION hasbach_f() RETURNS VOID AS $$
DECLARE 
    BAwlist text[] := '{ "bachelor", "bachelor\'s", "BACHELOR", "BACHELOR\'S", "Bachelor", \
                            "Bachelor\'s", "BA", "B.A.", "B.A", "BS", "B.S.", "BSc", "B.Sc."}';
    MBAwlist text[] := '{ "MBA", "M.B.A", "M.B.A." }';
BEGIN
    UPDATE eduDf
        SET hasbach = TRUE
        WHERE major && BAwlist AND NOT major && MBAwlist;
END; 
$$LANGUAGE plpgsql;



/* execute hasbach_f() to update eduDf*/
SELECT hasbach_f();

/* generate table newDf, unique row for 45048 user_ids, all those that has bachelor degrees from eduDf */
CREATE TABLE newDf AS (
    SELECT user_id, MIN(startyear) AS min_startyear, MIN(endyear) AS min_endyear
    FROM eduDf 
    WHERE basbach = TRUE
    GROUP BY user_id    
);

/* Calcuate labeled Age by setting user's earliest bachelor degree start year as Age 18 and calculate current age */
ALTER TABLE newDf
    ADD COLUMN est_min_startyear numeric DEFAULT NULL, 
    ADD COLUMN first_bach_start_year numeric DEFAULT NULL,
    ADD COLUMN Age numeric DEFAULT NULL,
    ADD COLUMN True_or_Predicted varchar(10) DEFAULT "True";
/*if the user has Null in either start or end year estimate by taking the smaller value of start year or end year - 4 */
UPDATE newDf SET est_min_startyear = min_endyear - 4 WHERE min_endyear IS NOT NULL;
UPDATE newDf SET first_bach_start_year = LEAST(min_startyear, est_min_startyear);
UPDATE newDf SET Age = 2019 - first_bach_start_year +18 WHERE first_bach_start_year IS NOT NULL;
/*if the user has no start or end year for any bachelor degrees, assign that user as a prediciton user */
UPDATE newDf SET True_or_Predicted = "Predicted" WHERE Age IS NULL; 



/* create label_fin to be stacked on job_pred_fin and sen_pred_fin for finalDf later */
CREATE TABLE label_fin AS (
    SELECT user_id, Age, True_or_Predicted
    FROM newDf
    WHERE True_or_Predicted = "True"
    
);


/* Begin Predicting */
/* merge seniority and position tables and create the startyear field */
CREATE TABLE senposDf AS (
    SELECT pos.user_id pos.jobtitle, sen.seniorty, date_part('year', pos.startdate) AS startyear
    FROM senDf AS sen
    FULL JOIN posDf AS pos
    ON sen.user_id = pos.user_id AND sen.jobtitle = pos.jobtitle    
);

/* generate infoDf, first job start year, and minimum and maximum seniority for each 100,000 users */
CREATE TABLE infoDf AS (
  SELECT user_id, min(startyear) AS first_job_year, min(seniority) AS min_sen, max(seniority) AS max_sen
  FROM senposDf
  GROUP BY user_id  
);

/*generate comDf, unique row for each 100,000 users, of which 39838 are labeled users */
CREATE TABLE comDf AS (
    SELECT i.user_id, i.first_job_year, i.min_sen, i.max_sen, n.first_bach_start_year, n.Age, n.True_or_Predicted
    FROM infoDf AS i
    LEFT JOIN newDf as n
    ON i.userid = n.user_id

);
/* fill in "Predicted" for remaining prediction users*/
UPDATE combDf SET True_or_Predicted = "Predicted" WHERE True_or_Predicted IS NULL;


/*create table m_job_year to predict Age for the no bachelor degree users that have the same first job year as users with bachelor degrees, use average of matched users' Age*/

CREATE TABLE m_job_year AS(
    SELECT * FROM 
        (SELECT c.user_id, c.first_job_year, c.True_or_Predicted
         FROM comDf AS c
         WHERE c.True_or_Predicted = "Predicted" AND c.first_job_year IS NOT NULL) AS predDf
    LEFT JOIN  
        (SELECT t.first_job_year, t.Age
         FROM comDf AS t
         WHERE t.True_or_Predicted = "True" AND t.first_job_year IS NOT NULL) AS labelDf
    ON predDf.first_job_year = labelDf.first_job_year
);

/* create job_pred_fin to be stacked on sen_pred_fin and label_fin for finalDf later */
/* unique rows for each 46199 users_ids, whose Age are predicted using this 'averge age of same first job year' method */
CREATE TABLE job_pred_fin AS (
    SELECT user_id, first_job_year, AVG(Age) AS Age, True_or_Predicted
    FROM m_job_year
    GROUP BY user_id, first_job_year
); 
/* there are 31 first job start years that have no other labeled users with the same start year, they are quite senior, use simple rule of setting first job year as Age 22 and calculate current age*/
UPDATE job_pred_fin SET Age = 2019 - first_job_year + 22 WHERE Age IS NULL;
ALTER TABLE job_pred_fin DROP COLUMN first_job_year; -- drop unused field for union later


/* for the remaining prediction users, use closes in min and max seniority method to predict Age */
/* create table of all labeled users, their senority and min and max senority */
CREATE TABLE comDf_label_sen AS(
    SELECT user_id, min_sen, max_sen, Age
    FROM comDf
    WHERE True_or_Predicted = "True"
    );
ALTER TABLE comDf_label_sen
    ADD PRIMARY KEY user_id;

/* creat comDf_pred_sen table, subset of prediction users that do not have 
first job year in order to do the job year match method */
CREATE TABLE comDf_pred_sen AS(
    SELECT user_id, min_sen, max_sen, True_or_Predicted -- Age is all Null at this step so omitted
    FROM comDf
    WHERE True_or_Predicted = "Predicted" AND user_id NOT IN (SELECT j.user_id FROM job_pred_fin AS j)
    );

ALTER TABLE comDf_pred_sen
    ADD PRIMARY KEY user_id;
    ADD COLUMN label_user_id varchar(100) DEFAULT NULL, -- user_id of the closest labeled user in min and max seniority 



/* creat function that uses L1 distance between labeled user and prediction users min and max seniorities to find the best match */   
CREATE FUNCTION findSenMatch() 
  RETURNS VOID 
AS
$$
DECLARE 
   t_row comDf_pred_sen%rowtype;
BEGIN
    FOR t_row in SELECT * FROM comDf_pred_sen LOOP
        update comDf_pred_sen AS p
            set  p.label_user_id = ( 
                    SELECT l.user_id
                    FROM comDf_label_sen AS l
                    ORDER BY abs(l.min_sen - t_row.min_sen) + abs(l.max_sen - t_row.max_sen ) DESC
                    LIMIT 1                   
                )
        where p.user_id = t_row.user_id; 
    END LOOP;
END;
$$ 
LANGUAGE plpgsql;


/* execute findSenMatch() to find the closest label user's Age */
SELECT findSenMatch();


/* generate table sen_pred_fin for stacking, unique row of 13963 user-ids that are predicted using the 
average of closes in min seniority and max seniority among labeled users*/
CREATE TABLE sen_pred_fin AS (
    SELECT p.user_id, l.Age, p.True_or_Predicted
    FROM comDf_pred_sen AS p
    INNER JOIN comDf_label_sen AS l
    ON p.label_user_id = l.user_id
    );


/**** generate finalDf ****/
SELECT * FROM 
(SELECT * FROM label_fin
UNION
SELECT * FROM job_pred_fin
UNION
SELECT * FROM sen_pred_fin) AS final_Df







