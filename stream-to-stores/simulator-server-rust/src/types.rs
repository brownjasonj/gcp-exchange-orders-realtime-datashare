use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Config {
    pub periodicity_ms: u64,
    pub price_variation_percentage: f64,
    pub gcp_project_id: String,
    pub pubsub_topic_name: String,
    pub symbols: Vec<String>,
    pub currencies: Vec<String>,
    pub venues: Vec<String>,
    #[serde(default = "default_burst_size")]
    pub burst_size: u64,
    #[serde(default = "default_pubsub_batch_messages")]
    pub pubsub_batch_messages: usize,
    #[serde(default = "default_pubsub_batch_delay_ms")]
    pub pubsub_batch_delay_ms: u64,
}

fn default_pubsub_batch_messages() -> usize {
    1000
}

fn default_pubsub_batch_delay_ms() -> u64 {
    10
}

fn default_burst_size() -> u64 {
    1_000_000
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PricingMessage {
    pub symbol: String,
    #[serde(rename = "sequenceNumber")]
    pub sequence_number: i64,
    pub price: f64,
    pub currency: String,
    pub venue: String,
    pub timestamp: String,
    #[serde(rename = "bidAsk")]
    pub bid_ask: String,
    pub quantity: i64,
    #[serde(rename = "publishTime")]
    pub publish_time: String,
    #[serde(rename = "ingestion_time", skip_serializing_if = "Option::is_none")]
    pub ingestion_time: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Status {
    pub is_running: bool,
    pub config: Config,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PriceUpdate {
    pub symbol: String,
    pub currency: String,
    pub price: f64,
    pub bid_ask: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BurstProgress {
    pub percent_complete: u8,
    pub message_count: u64,
    pub phase: String, // "generating" or "publishing"
}
