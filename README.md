# Solution Description

## Quick run
Setting up the database in Docker involves building an image for the PostgreSQL database, starting the container, and executing the init.sql file. This file contains the necessary Data Definition Language (DDL) statements for schema creation and initial data loading.

    docker-compose up --build

Run cuaration

    export PGPASSWORD=postgres   
    psql -h localhost -p 5432 -U postgres -d memfault -a -f queries/curation.sql

Run example query for median calculation

    psql -h localhost -p 5432 -U postgres -d memfault -a -f queries/battery_percentile.sql


## Database
I opted for PostgreSQL for this assignment for the following reasons:

1. **Ease of Setup with Docker:** PostgreSQL is straightforward to set up and manage using Docker. This allows for a seamless and consistent environment, making it easier to work on the assignment.

2. **Indexing and Partitioning Support:** PostgreSQL offers support for indexing and partitioning, which are essential for optimizing query performance on large datasets.

3. **JSON Data Handling:** PostgreSQL's ability to handle JSON data is very convenient for scenarios where flexible and semi-structured data formats are involved. This feature enhances the versatility of the database.

4. **Transferable Principles:** The principles applied in this assignment using PostgreSQL can be transferred to other database systems as well. The concepts of indexing, partitioning, and optimizing queries are applicable across different databases.

**Note:** Partitions managing is a disaster in postgres, you can see you can see how I handle it within the `curation.sql` file. 

## Layers

### Staging Layer

In the staging layer, I use this space to store raw data for cohorts, devices, events, and software_versions. I assume this data is delivered to these tables from some sort of message queue (e.g., Kafka). It's important to note that I consider this data delivery process to occur outside the scope of this assignment.

DDL (Data Definition Language) statements for creating these tables are provided in the [database/init.sql](database/init.sql) file. All the tables in this layer utilize the `id` column as a Primary Key, which means they are indexed by this identifier.

Additionally, I've applied partitioning to the `events` table based on the `created_date` field on a daily basis. I view the `created_date` as the timestamp of an event's creation in the table. If this interpretation is incorrect, an alternative approach could be introducing an additional field named `_ingested_at` and use it for partitioning purposes.

    CREATE TABLE staging.cohorts (
        id INT PRIMARY KEY,
        name VARCHAR(255),
        project_id INT
    );
    
    CREATE TABLE staging.devices (
        id INT PRIMARY KEY,
        project_id INT,
        device_serial VARCHAR(255),
        cohort_id INT
    );
    
    CREATE TABLE staging.events (
        id INT PRIMARY KEY,
        project_id INT,
        captured_date TIMESTAMP WITH TIME ZONE,
        created_date TIMESTAMP WITH TIME ZONE,
        type VARCHAR(255),
        software_version_id INT,
        device_id INT,
        event_info JSONB
    );
    
    CREATE TABLE staging.software_versions (
        id INT PRIMARY KEY,
        project_id INT,
        version VARCHAR(255)
    );


-- Indexes
CREATE INDEX idx_heartbeat_project_id ON curated.heartbeat(project_id);
-- Other indexes as needed


### Curated Layer

In this step, I've combined all the tables mentioned above into a single, denormalized data source `curated.heartbeat`. It aims to enhance the efficiency of analytical queries that we intend to run on this data.

I've also adjusted the partitioning key to `captured_date` for this layer. I perceive the `captured_date` as a 'business' timestamp, representing the moment of the initial event appearance on a device. Consequently, all aggregations will be based on this timestamp.

Each partition within this layer includes an index on the `project_id` column. I don't anticipate significant utilization of the `event_id` anymore, it's noteworthy that most queries will likely involve filtering based on `project_id`. Therefore, I find the change in the indexing column to be valid.

It's important to mention that I've opted for a partitioned index strategy rather than a single large index on the parent table. Partitioned indexes can be rebuilt more efficiently when working with smaller subsets of data (e.g., weekly or monthly), eliminating the need to load a large index for the entire historical dataset. This approach also reduces the risk of index skew.

I've left metrics as JSON to allow users easily add new metrics without any additional changes in DB.

Load to `curated.heartbeat` happens incrementally. To save last loaded timestamp `params.load_log` is being used. It allows to run `curation.sql` with any needed schedule without significant overheads.

    CREATE TABLE curated.heartbeat (
        event_id INT PRIMARY KEY,
        project_id INT,
        device_id INT,
        captured_date TIMESTAMP WITH TIME ZONE,
        created_date TIMESTAMP WITH TIME ZONE,
        software_version_id INT,
        version VARCHAR(255),
        device_serial VARCHAR(255),
        cohort_id INT,
        cohort_name VARCHAR(255),
        metrics JSONB
    );

### Metrics calculation

The majority of the metrics mentioned in the example section can be calculated relatively efficiently using the `curated.heartbeat` table. To further optimize the process, we can calculate certain aggregates. For instance, I've chosen to perform percentile calculations for the battery metric.

To address this requirement, I've taken the following steps:

1. **Materialized View:** I've designed a materialized view named `curated.battery_percentile` within the `database/init.sql` file. This view aims to provide an optimized structure for aggregating the data needed for percentile calculations.

2. **Data Update:** In the `queries/curation.sql` script, I update the materialized view. It's worth noting that this process could be further enhanced—for instance, by updating only the changed partitions instead of refreshing the entire view.

3. **Calculation Function:** To facilitate percentile calculations, I've created the `calculate_battery_percentile` function in the `queries/battery_percentile.sql` script. This function takes care of performing the actual percentile calculations on the data within the `curated.battery_percentile` materialized view.


## Scaling
I've designed this system with certain limitations to maintain simplicity for the sake of this take-home assignment. To facilitate scaling, we can consider the following strategies:

1. **Sharding:** Create separate databases for different groups of projects. Since most aggregations occur at the project level, this approach can distribute the load effectively.

2. **Caching:** Implementing a caching layer can prove beneficial, particularly when dealing with a substantial volume of uniform requests. Usage of Redis for example can be beneficial.

3. **Database Switch:** Consider migrating to a clustered solution such as Greenplum, TimescaleDB, or ClickHouse. These databases are designed to handle large-scale data and analytics workloads.

4. **Task Scheduling:** Leverage scheduling instruments like Apache Airflow to manage and automate batch jobs. This can streamline regular data processing tasks.

5. **Stream Processing:** Introduce streaming frameworks like Apache Spark or Apache Flink for near-real-time data curation. All the transformations performed in curation.sql can be seamlessly translated to stream-based operations.

6. **Data Archival:** Optimize storage costs by moving historical data to cold storage. This approach helps in retaining data while reducing the overall storage footprint.