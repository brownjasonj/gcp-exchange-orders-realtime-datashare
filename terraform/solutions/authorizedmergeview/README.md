This terraform module creates the following resources:

<ol>
<li>Subscription to pubsub topic</li>
<li>Bigquery table for storing the staged data</li>
<li>Dataflow job for streaming the data from pubsub to bigquery</li>
<li>Bigquery authorized view which performs a merge (deduplication) on-the-fly and applies a time delay</li>
</ol>

Notes:

<ul>
<li>The dataflow job is a flex template job and uses the PubSub_to_BigQuery_Flex template.</li>
<li>The authorized view uses a windowing function (`ROW_NUMBER()`) to deduplicate data from the staged table on-the-fly, using the same logic as the scheduled merge in the `authorizedview-withstaging-dataflow` solution.</li>
<li>The view also filters for data within the last hour to maintain performance, mirroring the original merge query logic.</li>
<li>This solution avoids the need for a separate 'final' table and a scheduled merge job, at the cost of higher query complexity and compute for the view.</li>
</ul>
