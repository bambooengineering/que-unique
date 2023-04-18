# Integration test

This folder contains all the files and a script to ensure that que-unique works in a
full integration test.

First start a postgres docker container with:

`docker run -p 5432:5432 -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=postgres postgres:14.7`

Then run the following, submitting a QUE_VERSION environment variable to test.

`QUE_VERSION=1.4.0 RAILS_VERSION=6.1.7.3 ruby test.rb`
