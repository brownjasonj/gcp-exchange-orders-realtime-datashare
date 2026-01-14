<h3>The solution consists of</h3>
<ul>
<li>A BigQuery Dataset for pay-walled data with a table (Table 1) containing all data messages.</li>
<li>An Analytics Hub Exchange for pay-walled data with the pay-walled data published in it.</li>
<li>A PubSub subscription with a Dataflow job subscriber that publishes all messages to Table 1 immediately.</li>
<li>A BigQuery Dataset for free data a table (Table 2) containing all messages delayed by Z minutes.</li>
<li>An Analytics Hub Exchange for free data with the BigQuery Dataset for free data published in it </li>
<li>A Pubsub subscription that triggers a Cloud Function/Cloud Run.  If the timestamp of the message is M_T and now() - M_T >=  Z minutes, the function publishes to Table 2, otherwise the function doesn’t acknowledge the message  and set the timeout acknowledgement in PubSub to be
<ul>
<li>10 minutes, if now() - M_T > 10 minutes</li>
<li>now() - M_T, otherwise</li>
</ul>
</li>
</ul>