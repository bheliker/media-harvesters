www.caliparks.org Social Media Harvesters
==================================================
Mapping social media activity in parks and other open spaces. This repository contains the Heroku-based Node.js social
media harvesters. Most of this code has been copied over from the [local-harvester branch](https://github.com/stamen/parks.stamen.com/tree/local-harvester) of the repository.
These harvesters collect geotagged content from Flickr, Foursquare, and Instagram. (currently Twitter is handled using a separate codebase)

  * [About the Project](#about-the-project)
  * [Getting Started Locally](#getting-started-locally)
    * [overview of environment variables](#overview-of-environment-variables)
    * [overview of the database setup](#overview-of-the-database-tables)
    * [harvest ye photos](#harvest-ye-photos)
  * [Setting Up CPAD Superunits DB](#setting-up-cpad-superunits-db)
  * [Setting Up Custom Shapefiles and GeoJSON DB](#setting-up-custom-shapefiles-and-geojson-db)
  * [Foursquare Harvesting](#foursquare-harvesting)
  * [Flickr Harvesting](#flickr-harvesting)
  * [Instagram Harvesting](#instagram-harvesting)
  * [About the Algorithms](#about-the-algorithms)


About the Project
=======================
We are collecting all geocoded tweets, flickr photos, instagram photos, and foursquare venues (and check-in counts) within
the boundaries of every open space listed in the [California Protected Areas Database (CPAD)](http://calands.org), specifically
the CPAD "superunits". In this document "parks" and "open spaces" are used interchangeably, but we really mean "superunits".

Getting Started Locally
=======================
The following steps have been tested on Mac and Debian systems

overview of environment variables
-------------------------------------------
0. The application uses `foreman` and `make` to execute commands. Both use environment variables from the `.env` file
in the root directory. Copy the `sample.env` to an `.env` file and fill it out. In various spots the directions talk about
the expected values if you're unsure how to fill them out right now:

    ```bash
	DATABASE_URL=postgres://username@hostname:port/dbname # required
    TARGET_GEOJSON_OR_SHAPEFILE_ABSPATH=YOURPATHHERE
    FLICKR_CLIENT_ID=YOURCLIENTIDHERE
    FLICKR_CLIENT_SECRET=YOURCLIENTSECRETHERE
    FOURSQUARE_CLIENT_ID=YOURCLIENTIDHERE
    FOURSQUARE_CLIENT_SECRET=YOURCLIENTSECRETHERE
    INSTAGRAM_CLIENT_ID=YOURCLIENTIDHERE
    INSTAGRAM_CLIENT_SECRET=YOURSECRETIDHERE
    ```

overview of the database setup
--------------------------------
0. Install `PostgreSQL 9.x` and `PostGIS 2.x` onto your developer system

0. Make sure the user you'll run commands as is also a [PostgreSQL Superuser](http://www.postgresql.org/docs/9.2/static/sql-createrole.html):

    ```bash
    rancho@trusty64$ sudo -u postgres psql -c "CREATE ROLE rancho LOGIN SUPERUSER;"
    ```

0. Make sure the `DATABASE_URL` environment variable is filled out, it's required by the `Makefile`:

    ```bash
    # assuming your user is 'rancho' and the database is 'openspaces'
    # the connection string `postgres://username@hostname:port/dbname` becomes
    DATABASE_URL=postgres://rancho@localhost:5432/openspaces
    ```

0. Each harvester works with their own specific tables and a shared `superunits` table. For example, the output tables
that are generated to run the Instagram harvester for CPAD park areas are listed below. For more information about
setting up the CPAD database read the section [Setting Up CPAD Superunits DB](#setting-up-cpad-superunits-db)

    ```bash
    # a table of CPAD superunit polygon geometries from a downloaded CPAD shapefile
    cpad_2015b

    # a table of CPAD superunit geometries, the same ones above, with some column names changed
    superunits

    # smaller hexagon geometries derived from the table `superunits` geometries
    instagram_reqions

    # point geometries indicating the (lng,lat) of where Instagram photos were found after running the harvesters
    instagram_photos
    ```

0. Let's play with some sample data in this repository to setup custom park areas based on our own datasets.
Read the section [Setting Up Custom Shapefiles and GeoJSON](#setting-up-custom-shapefiles-and-geojson-db)

0. Move on to the [Harvesting Ye Photos Section](#harvest-ye-photos)

harvest ye photos
------------------------------------------
With the database setup, the next step is to run the Node.js harvesters which query Flickr, Foursquare or Instagram for photos related to the loaded park areas.
We can kick off these harvesters using `foreman` commands such as:

    $ foreman run instagram

Review the harvester-specific sections [Foursquare Harvesting](#foursquare-harvesting),
[Flickr Harvesting](#flickr-harvesting), and [Instagram Harvesting](#instagram-harvesting) for instructions on running each


Setting Up CPAD Superunits DB
==============================
If you want to seed the database with CPAD park geometries then you need to run a `make` command for the intended harvester.
Below we load CPAD geometries for an Instagram harvester, Flickr harvester and Foursquare harvester:

```bash
$ make db/instagram_cpad
$ make db/flickr_cpad
$ make db/foursquare_cpad
```


Setting Up Custom Shapefiles and GeoJSON DB
============================================
Use your own park geometries to seed the database and influence where the harvesters collect social media. Let's play with some sample data in this repository to setup custom park areas

0. The `Makefile` command `db/instagram_custom` can load our own Shapefile or GeoJSON datasets into the `superunits` table
( it can also load a Shapefile inside a zipfile ). There are several datasets in this repository's `testdata/` directory. They include:

    ```bash
    # a GeoJSON file in WGS-84
    test.json

    # a Shapefile in Pseudo Mercator
    test_epsg_3857

    # a zipfile that contains a Shapefile
    # called `test_epsg_3310.shp` in the root directory
    # in California Albers
    test_epsg_3310.zip

    # a zipfile that contains a Shapefile
    # called `test_epsg_3310.shp` in a `subfolders/` directory
    # in California Albers
    test_epsg_3310_in_subfolder.zip
    ```

0. Pick one dataset from `testdata/` and copy the absolute path to it. Because it has the most complicated path,
this example will use `test_epsg_3310_in_subfolder.zip`. Now update the `.env` file with the absolute path:

    ```bash
    # note the full path to the Shapefile includes the child folder
    TARGET_GEOJSON_OR_SHAPEFILE_ABSPATH=/usr/local/src/dev/harvester/testdata/test_epsg_3310_in_subfolder.zip/subfolders/test_epsg_3310.shp
    ```

0. Change to the root harvester directory, the one with the `Makefile` in it

0. Now load the dataset and create the required tables for the harvester you want. Here we are preparing the
database for Instagram where `db/flickr_custom` would be for Flickr:

    ```bash
    $ make db/instagram_custom
    ```

0. Here's the intended output tables and data we care about:

    ```bash
    $ psql -c "\d"
                   List of relations
     Schema |           Name           |   Type   | Owner
    --------+--------------------------+----------+--------
     public | instagram_photos         | table    | rancho
     public | instagram_regions        | table    | rancho
     public | superunits               | table    | rancho


    $ psql -c "SELECT count(*) from superunits;"
     count
    -------
        85
    (1 row)
    ```

Foursquare Harvesting
=======================
0. If you don't have one, go sign up for a Foursquare account and
then [register the harvester application ](https://foursquare.com/developers/apps). Registering the application should
generate a `Client Id` and `Client Secret` that you'll want to save in the `.env` file as:

    ```bash
    FOURSQUARE_CLIENT_ID=12412523erwty7654598
    FOURSQUARE_CLIENT_SECRET=12412523erwty7654598
    ```
0. The harvester is all setup to run against Foursquare. Change to the root harvester directory, the one with the `Makefile` in it.

0. Harvesting the venues the first time (determining the existence of venues in each park) is the hard part.
This should be re-run periodically to catch any new venues that appear (more to come later). To collect venues the first time run:

    ```bash
    $ foreman run foursquare_venues
    ```

0. To update the checkin counts for already-harvested venues run:

    ```bash
    $ foreman run foursquare_update
    ```

0. The app saves harvested photos to the table `foursquare_venues`


Flickr Harvesting
===================
0. If you don't have one, go sign up for a Flickr account and
then [register the harvester application ](https://www.flickr.com/services/apps/create/apply/). Registering the application should
generate a `Key` and `Secret` that you'll want to save in the `.env` file as:

    ```bash
    FLICKR_CLIENT_ID=12412523erwty7654598 # key
    FLICKR_CLIENT_SECRET=12412523erwty7654598
    ```
0. The harvester is all setup to run against Flickr. Change to the root harvester directory, the one with the `Makefile` in it.
To run locally type `foreman run flickr`. The CLI node app queries the Flickr API for bounding box of each park.

0. The app saves harvested photos to the table `flickr_photos`


Instagram Harvesting
=======================
0. If you don't have one, go sign up for an Instagram account and
then [register the harvester application](https://www.instagram.com/developer/clients/manage/). As of `12/01/2015` it seems
that you'll have to promote the application out of `Sandbox Mode` to be able to get API results back. Read more about
[going live](https://www.instagram.com/developer/sandbox/) for instructions on how to do that. Registering the application should
generate a `Client ID` and `Client Secret` that you'll want to save in the `.env` file as:

    ```bash
    INSTAGRAM_CLIENT_ID=12412523erwty7654598
    INSTAGRAM_CLIENT_SECRET=12412523erwty7654598
    ```

0. The harvester is all setup to run against Instagram. Change to the root harvester directory, the one with the `Makefile` in it.
To run locally type `foreman run instagram`. The CLI node app queries the Instagram API for an array of circles covering each park.

0. The app saves harvested photos to the table `instagram_photos`

About the Algorithms
======================

Add more here (including screenshots).

For a summary of what the different harvesters do, and how they do it, read this blog post: [Mapping the Intersection Between Social Media and Open Spaces in California](http://content.stamen.com/mapping_the_intersection_between_social_media_and_open_spaces_in_ca)

