This terraform module creates the following resources

<ol>
<li>Subscription to pubsub topic</li>
<li>Bigquery table for storing the staged data with a retention of given days</li>
<li>Bigquery table for storing the final data with a retention of given days</li>
<li>Dataflow job for streaming the data from pubsub to bigquery</li>
<li>Bigquery authorized view for retreiving data with given delay in seconds</li>
</ol>

Notes:

<ul>
<li>The dataflow job is a flex template job and uses the PubSub_to_BigQuery_Flex template.</li>
<li>A second bigquery table (final) that is a merge of the staged table and its cache with duplicates removed to ensure that authprized view does not have duplicates.</li>
<li>The staging bigquery table has a shorter retention period in order to reduce storage costs.</li>
<li>If duplicate records are acceptable then use the module authorizedview instead.</li>
</ul>