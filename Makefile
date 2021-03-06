PATH := node_modules/.bin:$(PATH)

define EXPAND_EXPORTS
export $(word 1, $(subst =, , $(1))) := $(word 2, $(subst =, , $(1)))
endef

# load .env
$(foreach a,$(shell cat .env 2> /dev/null),$(eval $(call EXPAND_EXPORTS,$(a))))
# expand PG* environment vars
$(foreach a,$(shell set -a && source .env 2> /dev/null; node_modules/.bin/pgexplode),$(eval $(call EXPAND_EXPORTS,$(a))))

# helper rule to see PG environment settings
test_pg_envs:
	$(shell echo env)

define create_relation
@psql -v ON_ERROR_STOP=1 -qXc "\d $(subst db/,,$@)" > /dev/null 2>&1 || \
	psql -v ON_ERROR_STOP=1 -qX1f sql/$(subst db/,,$@).sql
endef

define create_extension
@psql -v ON_ERROR_STOP=1 -qXc "\dx $(subst db/,,$@)" | grep $(subst db/,,$@) > /dev/null 2>&1 || \
	psql -v ON_ERROR_STOP=1 -qXc "CREATE EXTENSION $(subst db/,,$@)"
endef

define create_function
@psql -v ON_ERROR_STOP=1 -qXc "\df $(subst db/,,$@)" | grep -i $(subst db/,,$@) > /dev/null 2>&1 || \
	psql -v ON_ERROR_STOP=1 -qX1f sql/$(subst db/,,$@).sql
endef

define MIGRATION_SQL_WRAPPER
CREATE FUNCTION migrate(migration_name text)
RETURNS void
AS $$$$
BEGIN
  PERFORM id FROM migrations WHERE name = migration_name;

  IF NOT FOUND THEN
	RAISE NOTICE 'Running migration: %', migration_name;

{{content}}

	INSERT INTO migrations (name) VALUES (migration_name);
  END IF;

  RETURN;
END
$$$$ LANGUAGE plpgsql;

SELECT migrate('{{name}}');

DROP FUNCTION migrate(text);
endef

export MIGRATION_SQL_WRAPPER

define migrate
	test -f sql/migrations/$(strip $(1)).sql && \
		echo "$${MIGRATION_SQL_WRAPPER//\{\{name\}\}/$(strip $(1))}" | \
		perl -pe "s/\{\{content\}\}/$$(cat sql/migrations/$(strip $(1)).sql)/" | \
		psql -qX1 > /dev/null ;
endef

define run_migrations
	@$(foreach migration,$(shell ls sql/migrations/ 2> /dev/null | sed 's/\..*//'),$(call migrate,$(migration)))
endef


.PHONY: DATABASE_URL

DATABASE_URL:
	@test "${$@}" || (echo "$@ is undefined" && false)

TARGET_GEOJSON_OR_SHAPEFILE_ABSPATH:
	@test "${$@}" || (echo "$@ is undefined" && false)

#######################################
### Twitter stuff #####################
#######################################

twitterHarvesterTable:
# Needs better way of importing the csv file
	cd harvesters && rm twitter_stream_to_import* \
	&& cp twitter_stream.csv.1 twitter_stream_to_import.csv \
	&& psql -U openspaces -h geo.local -c "drop table if exists tweets_harvest;" \
	&& psql -U openspaces -h geo.local -c "create table tweets_harvest (id_str varchar, place varchar, something varchar, coords varchar(40), username varchar(20), fullname varchar(40), client varchar(80), date timestamp, retweet_count int, favorite_count int, lang varchar(3), content varchar);" \
	&& /usr/local/bin/csvclean twitter_stream_to_import.csv \
	&& psql -U openspaces -h geo.local -c "\copy tweets_harvest FROM 'twitter_stream_to_import_out.csv' DELIMITER ',' CSV;" \
	&& psql -U openspaces -h geo.local -c "alter table tweets_harvest add column wkt varchar;" \
	&& psql -U openspaces -h geo.local -c "update tweets_harvest set wkt = regexp_replace(regexp_replace(regexp_replace(coords, ']', ')'), ',', ''), '\[', 'POINT(');" \
	&& psql -U openspaces -h geo.local -c "SELECT AddGeometryColumn('tweets_harvest','the_geom',4326,'POINT',2);" \
	&& psql -U openspaces -h geo.local -c "UPDATE tweets_harvest SET the_geom = GeometryFromText(wkt, 4326);" \
	&& psql -U openspaces -h geo.local -c "create table park_tweets_temp as select park.su_id as su_id, park.unit_name as su_name, tweet.* from cpad_2013b_superunits_ids as park join tweets_harvest as tweet on ST_Contains(park.geom,tweet.the_geom);" \
	&& psql -U openspaces -h geo.local -c "insert into park_tweets select * from park_tweets_temp;" \
&& psql -U openspaces -h geo.local -c "drop table if exists park_tweets_temp;"

#######################################
### Foursquare stuff ##################
#######################################

# Run once to create the table.
foursquareActivityTable:
	psql -U openspaces -h geo.local -c "drop table if exists foursquare_venue_activity;" \
	&& psql -U openspaces -h geo.local -c "create table foursquare_venue_activity (venueid varchar(80), timestamp timestamp default NOW(), checkinscount bigint, userscount bigint, tipcount bigint, likescount bigint, mayor_id varchar(20), mayor_firstname varchar(80), mayor_lastname varchar(80));" \

# Run once to create the table.
foursquareVenuesActivityView:
	psql -U openspaces -h geo.local -c "drop view park_foursquare_venues_activity;" \
	&& psql -U openspaces -h geo.local -c "create view park_foursquare_venues_activity as select a.*, b.timestamp, b.checkinscount, b.userscount, b.tipcount, b.likescount, b.mayor_id, b.mayor_firstname, b.mayor_lastname from park_foursquare_venues a left join (select distinct on (venueid) * from foursquare_venue_activity order by venueid, timestamp desc) as b on a.venueid = b.venueid;"

#######################################
### Totals ############################
#######################################

parkTotals:
	psql -U openspaces -h geo.local -c "create view park_totals as select parks.su_id, parks.unit_name, parks.agncy_id, parks.agncy_name, parks.gis_acres, foursquare.venuecount, foursquare.checkinscount, foursquare.userscount, flickr.flickrphotos, flickr.flickrusers, instagram.instagramphotos, instagram.instagramusers, twitter.tweets, twitter.twitterusers from cpad_2013b_superunits_ids as parks left join (select su_id, count(venueid) as venuecount, sum(checkinscount) as checkinscount, sum(userscount) as userscount from park_foursquare_venues_activity group by su_id) as foursquare on parks.su_id = foursquare.su_id left join (select su_id, count(photoid) as flickrphotos, count(distinct owner) as flickrusers from park_flickr_photos group by su_id) as flickr on parks.su_id = flickr.su_id left join (select su_id, count(photoid) as instagramphotos, count(distinct userid) as instagramusers from park_instagram_photos group by su_id) as instagram on parks.su_id = instagram.su_id left join (select su_id, count(id_str) as tweets, count(distinct username) as twitterusers from park_tweets group by su_id) as twitter on parks.su_id = twitter.su_id;"

flickr: db/flickr deps/foreman
	foreman run flickr

foursquare_venues_cpad: db/foursquare_cpad deps/foreman
	foreman run foursquare_venues

foursquare_venues_custom: db/foursquare_custom deps/foreman
	foreman run foursquare_venues

instagram: db/instagram_cpad deps/foreman
	foreman run instagram

deps/foreman:
	@type ogr2ogr 2> /dev/null 1>&2 || sudo gem install foreman || (echo "Please install foreman" && false)

deps/gdal:
	@type ogr2ogr 2> /dev/null 1>&2 || brew install gdal > /dev/null 2>&1 || sudo apt-get install gdal-bin || (echo "Please install gdal" && false)

deps/pv:
	@type pv 2> /dev/null 1>&2 || brew install pv > /dev/null 2>&1 || sudo apt-get install pv || (echo "Please install pv" && false)

deps/npm:
	@npm install

export DEFAULT_SUPERUNIT_TABLENAME = superunits_temp
cpad_2015a_defaults:
	$(eval DEFAULT_SUPERUNIT_TABLENAME := $(word 1,$(subst _defaults,,$@)))
	$(eval TARGET_GEOJSON_OR_SHAPEFILE_ABSPATH := data/cpad_2015a_superunits_name_manager_access.zip/CPAD_2015a_SuperUnits.shp)

data/cpad_2015a_superunits_name_manager_access.zip:
	@mkdir -p $$(dirname $@)
	@curl -sLf http://data.stamen.com.s3.amazonaws.com/caliparks/CPAD_2015a_SuperUnits.zip -o $@

db: DATABASE_URL deps/npm
	@psql -c "SELECT 1" > /dev/null 2>&1 || \
	createdb

db/all: db/cpad_superunits db/flickr_cpad db/foursquare_cpad db/instagram_cpad

db/postgis: db
	$(call create_extension)

db/cpad_2015a: data/cpad_2015a_superunits_name_manager_access.zip cpad_2015a_defaults db/load_data

db/load_data: TARGET_GEOJSON_OR_SHAPEFILE_ABSPATH db/postgis deps/gdal deps/pv deps/npm
	@psql -c "\d $(DEFAULT_SUPERUNIT_TABLENAME)" > /dev/null 2>&1 || \
	$(if $(findstring .zip, $(TARGET_GEOJSON_OR_SHAPEFILE_ABSPATH)), \
	    $(eval TARGET := /vsizip/$(TARGET_GEOJSON_OR_SHAPEFILE_ABSPATH)), \
	    $(eval TARGET := $(TARGET_GEOJSON_OR_SHAPEFILE_ABSPATH))) \
	ogr2ogr --config PG_USE_COPY YES \
		-t_srs EPSG:3857 \
		-nlt PROMOTE_TO_MULTI \
		-nln $(DEFAULT_SUPERUNIT_TABLENAME) \
		-lco GEOMETRY_NAME=geom \
		-lco SRID=3857 \
		-overwrite \
		-f PGDump /vsistdout/ $(TARGET) | pv | psql -q

export LAYER_NAME 
export TARGET_FILE
db/ogrinfo_setup: TARGET_GEOJSON_OR_SHAPEFILE_ABSPATH 
	$(if $(findstring .zip, $(TARGET_GEOJSON_OR_SHAPEFILE_ABSPATH)), \
		$(eval TARGET_FILE := /vsizip/$(TARGET_GEOJSON_OR_SHAPEFILE_ABSPATH)), \
		$(eval TARGET_FILE := $(TARGET_GEOJSON_OR_SHAPEFILE_ABSPATH))) \
	$(if $(findstring .json, $(TARGET_GEOJSON_OR_SHAPEFILE_ABSPATH)), \
		$(eval LAYER_NAME := OGRGeoJSON), \
		$(eval LAYER_NAME := $(basename $(notdir $(TARGET_GEOJSON_OR_SHAPEFILE_ABSPATH)))))

db/ogrinfo_validate_data: TARGET_GEOJSON_OR_SHAPEFILE_ABSPATH db/ogrinfo_setup deps/gdal
	@ogrinfo -ro -so $(TARGET_FILE) $(LAYER_NAME) 2> /dev/null | grep -i "Geometry: Polygon" > /dev/null 2>&1 \
	|| (echo Error exit_code="$$?": make sure your $(TARGET_FILE) is \'Polygon\' features && false)

db/cpad_superunits: db/cpad_2015a
	$(call create_relation)

db/custom_superunits: db/load_data
	$(call create_relation)

db/superunit_changes: db
	$(call create_relation)

db/renumber_cpad_superunits: db/superunit_changes
	psql -v ON_ERROR_STOP=1 -qX1f sql/renumber_cpad_superunits.sql

db/migrate: db/migrations
	$(call run_migrations)

db/migrations: db
	$(call create_relation)

db/CDB_RectangleGrid: db
	$(call create_function)

db/CDB_HexagonGrid: db
	$(call create_function)

db/GetIntersectingHexagons: db/CDB_HexagonGrid
	$(call create_function)

#######################################
### Flickr database tables ############
#######################################
db/flickr_custom: db/ogrinfo_validate_data db/custom_superunits db/load_data db/flickr_photos db/flickr_regions

db/flickr_cpad: db/cpad_superunits db/flickr_photos db/flickr_regions

db/flickr_photos: db
	$(call create_relation)

db/flickr_regions: db/CDB_RectangleGrid
	$(call create_relation)

#######################################
### Foursquare database tables ########
#######################################
db/foursquare_custom: db/ogrinfo_validate_data db/custom_superunits db/load_data db/foursquare_venues db/foursquare_regions

db/foursquare_cpad: db/cpad_superunits db/foursquare_venues db/foursquare_regions

db/foursquare_venues: db
	$(call create_relation)

db/foursquare_regions: db/CDB_RectangleGrid
	$(call create_relation)

#######################################
### Instagram database tables #########
#######################################
db/instagram_custom: db/ogrinfo_validate_data db/custom_superunits db/load_data db/instagram_regions db/instagram_photos

db/instagram_cpad: db/cpad_superunits db/instagram_regions db/instagram_photos

db/instagram_photos: db
	$(call create_relation)

db/instagram_regions: db/GetIntersectingHexagons
	$(call create_relation)

.PHONY: migration/%

migration/%:
	@mkdir -p sql/migrations
	touch sql/migrations/$(shell date +'%Y%m%d%H%M')-$(subst migration/,,$@).sql
