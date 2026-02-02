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
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PricingMessage {
    pub symbol: String,
    pub sequence_number: u64,
    pub price: f64,
    pub currency: String,
    pub venue: String,
    pub timestamp: String, // ISO 8601
    pub bid_ask: String,   // "bid" or "ask"
    pub quantity: u64,
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
