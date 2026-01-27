This terraform module creates the following resources

<ol>
<li>Subscription to pubsub topic</li>
<li>Bigquery table for storing the data</li>
<li>Dataflow job for streaming the data from pubsub to bigquery</li>
<li>Bigquery authorized view for retreiving data with given delay in seconds</li>
</ol>

Notes:

<ul>
<li>The dataflow job is a flex template job and uses the PubSub_to_BigQuery_Flex template.</li>
<li>The authorized view queries the Bigquery table with consists of persisted events and cached events. This can potentially lead to duplicate records in the authorized view.  If these duplicates are not desired, then use the module bqmergewithauthorizedview instead.</li>
</ul>