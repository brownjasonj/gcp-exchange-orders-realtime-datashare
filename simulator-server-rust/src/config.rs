use crate::types::Config;
use std::fs;
use std::path::Path;
use tracing::{error, warn};

pub fn load_config(path: &str) -> Config {
    if Path::new(path).exists() {
        match fs::read_to_string(path) {
            Ok(content) => match serde_json::from_str(&content) {
                Ok(config) => return config,
                Err(e) => error!("Failed to parse config: {}", e),
            },
            Err(e) => error!("Failed to read config file: {}", e),
        }
    } else {
        warn!("Config file not found at {}", path);
    }

    // Default config
    Config {
        periodicity_ms: 1000,
        price_variation_percentage: 1.0,
        gcp_project_id: std::env::var("PROJECT_ID").unwrap_or_else(|_| "loading".to_string()),
        pubsub_topic_name: std::env::var("PUBSUB_TOPIC").unwrap_or_else(|_| "pricing-topic".to_string()),
        symbols: vec!["BTC".to_string(), "ETH".to_string()],
        currencies: vec!["USD".to_string()],
        venues: vec!["GCP".to_string()],
        burst_size: 1_000_000,
    }
}

pub fn save_config(path: &str, config: &Config) -> std::io::Result<()> {
    let content = serde_json::to_string_pretty(config)?;
    fs::write(path, content)?;
    Ok(())
}
