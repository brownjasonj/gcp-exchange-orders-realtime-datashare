use crate::types::{Config, PricingMessage, Status, PriceUpdate};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{RwLock, Mutex};
use tokio::task::JoinHandle;
use tokio::time::{interval, timeout, Duration};
use rand::Rng;
use socketioxide::SocketIo;
use google_cloud_pubsub::client::{Client, ClientConfig};
use google_cloud_pubsub::publisher::Publisher;
use google_cloud_googleapis::pubsub::v1::PubsubMessage;
use tracing::{info, error};
use chrono::Utc;


struct State {
    config: Config,
    prices: HashMap<String, f64>,
    pairs: Vec<(String, String)>,
    running: bool,
    sequence_number: u64,
}

#[derive(Clone)]
pub struct Simulator {
    state: Arc<RwLock<State>>,
    io: SocketIo,
    pubsub: Option<Client>,
    publisher: Arc<RwLock<Option<Publisher>>>,
    task_handle: Arc<Mutex<Option<JoinHandle<()>>>>,
}

impl Simulator {
    pub async fn new(config: Config, io: SocketIo) -> Self {
        // Add timeout to PubSub client creation to avoid startup hangs
        let pubsub_future = async {
            let config = ClientConfig::default().with_auth().await
                .map_err(|e| format!("Auth error: {}", e))?;
            Client::new(config).await
                .map_err(|e| format!("Client error: {}", e))
        };

        let pubsub = match timeout(Duration::from_secs(5), pubsub_future).await {
            Ok(Ok(client)) => Some(client),
            Ok(Err(e)) => {
                error!("Failed to create PubSub client: {}", e);
                None
            }
            Err(_) => {
                error!("Timed out creating PubSub client");
                None
            }
        };

        let sim = Self {
            state: Arc::new(RwLock::new(State {
                config: config.clone(),
                prices: HashMap::new(),
                pairs: Vec::new(),
                running: false,
                sequence_number: 0,
            })),
            io,
            pubsub,
            publisher: Arc::new(RwLock::new(None)),
            task_handle: Arc::new(Mutex::new(None)),
        };

        sim.initialize().await;
        sim
    }

    pub async fn initialize(&self) {
        let mut state = self.state.write().await;
        let shard_index: usize = std::env::var("SHARD_INDEX").unwrap_or("0".to_string()).parse().unwrap_or(0);
        let total_shards: usize = std::env::var("TOTAL_SHARDS").unwrap_or("1".to_string()).parse().unwrap_or(1);
        let topic_name = state.config.pubsub_topic_name.clone();

        info!("Initializing simulator shard {}/{}", shard_index, total_shards);

        // Recreate publisher if client exists
        if let Some(client) = &self.pubsub {
             let topic = client.topic(&topic_name);
             // Ensure topic exists? We assume it exists or we just publish to it.
             // Usually we should check or create, but for simulator we assume infra is there.
             
             // Stop old publisher if any
             let mut pub_guard = self.publisher.write().await;
             if let Some(mut old_pub) = pub_guard.take() {
                 let _ = old_pub.shutdown().await;
             }
             
             // Create new publisher
             // Note: new_publisher starts a background task immediately
             *pub_guard = Some(topic.new_publisher(None));
        }

        let my_symbols: Vec<String> = state.config.symbols
            .iter()
            .enumerate()
            .filter(|(i, _)| i % total_shards == shard_index)
            .map(|(_, s)| s.clone())
            .collect();

        state.pairs.clear();
        state.prices.clear();

        let mut rng = rand::rng();

        let currencies = state.config.currencies.clone();

        for symbol in &my_symbols {
            for currency in &currencies {
                let pair_key = format!("{}:{}", symbol, currency);
                let initial_value = (rng.random_range(10.0f64..1000.0f64) * 100.0).round() / 100.0;
                state.prices.insert(pair_key, initial_value);
                state.pairs.push((symbol.clone(), currency.clone()));
            }
        }

        info!("Simulator initialized with {} pairs", state.pairs.len());
    }

    pub async fn start(&self) {
        let mut state_guard = self.state.write().await;
        if state_guard.running {
            return;
        }
        state_guard.running = true;
        let periodicity = state_guard.config.periodicity_ms;
        drop(state_guard);

        let sim_clone = self.clone();
        let mut handle_guard = self.task_handle.lock().await;
        
        if let Some(handle) = handle_guard.take() {
            handle.abort();
        }

        info!("Starting simulation loop with periodicity {}ms", periodicity);

        *handle_guard = Some(tokio::spawn(async move {
            let mut ticker = interval(Duration::from_millis(periodicity));
            loop {
                ticker.tick().await;

                let (is_running, periodicity_check) = {
                    let s = sim_clone.state.read().await;
                    (s.running, s.config.periodicity_ms)
                };

                if !is_running {
                    break;
                }
                
                if ticker.period().as_millis() as u64 != periodicity_check {
                     ticker = interval(Duration::from_millis(periodicity_check));
                     ticker.tick().await; 
                }

                sim_clone.tick().await;
            }
        }));
    }

    pub async fn stop(&self) {
        let mut state = self.state.write().await;
        state.running = false;
        drop(state);

        let mut handle = self.task_handle.lock().await;
        if let Some(h) = handle.take() {
            h.abort();
        }
        info!("Simulation stopped");
    }

    pub async fn get_status(&self) -> Status {
        let state = self.state.read().await;
        Status {
            is_running: state.running,
            config: state.config.clone(),
        }
    }

    pub async fn get_prices(&self) -> HashMap<String, f64> {
        let state = self.state.read().await;
        state.prices.clone()
    }

    pub async fn update_config(&self, new_config: Config) {
        let was_running = { self.state.read().await.running };
        if was_running {
            self.stop().await;
        }

        {
            let mut state = self.state.write().await;
            state.config = new_config;
        }
        
        self.initialize().await;

        if was_running {
            self.start().await;
        }
    }

    async fn tick(&self) {
         let (msg, _topic_name) = {
            let mut state = self.state.write().await;
            let mut rng = rand::rng();

            if state.pairs.is_empty() {
                return;
            }
            
            let pair_idx = rng.random_range(0..state.pairs.len());
            let (symbol, currency) = state.pairs[pair_idx].clone();
            let key = format!("{}:{}", symbol, currency);
            
            let current_price = *state.prices.get(&key).unwrap_or(&100.0);
            
            let variation = state.config.price_variation_percentage;
            let change = (rng.random::<f64>() * 2.0 - 1.0) * variation;
            let factor = 1.0 + change / 100.0;
            let mut new_price = current_price * factor;
            if new_price < 0.01 { new_price = 0.01; }
            new_price = (new_price * 100.0).round() / 100.0;
            
            state.prices.insert(key.clone(), new_price);
            
            let venue_idx = rng.random_range(0..state.config.venues.len());
            let venue = state.config.venues[venue_idx].clone();
            
            let msg = PricingMessage {
                symbol: symbol.clone(),
                sequence_number: state.sequence_number,
                price: new_price,
                currency: currency.clone(),
                venue,
                timestamp: Utc::now().to_rfc3339(),
                bid_ask: if rng.random_bool(0.5) { "bid".to_string() } else { "ask".to_string() },
                quantity: rng.random_range(1..1001),
            };
            
            state.sequence_number += 1;
            
            (msg, state.config.pubsub_topic_name.clone())
        };

        let _ = self.io.emit("message", &msg).await;
        
        let update = PriceUpdate {
            symbol: msg.symbol.clone(),
            currency: msg.currency.clone(),
            price: msg.price,
            bid_ask: msg.bid_ask.clone(),
        };
        let _ = self.io.emit("priceUpdate", &update).await;
        
        // Publish to PubSub using cached publisher
        let publisher_guard = self.publisher.read().await;
        if let Some(publisher) = &*publisher_guard {
            match serde_json::to_vec(&msg) {
                 Ok(data) => {
                     // Fire and forget - await the enqueue, not the result
                     // wait, publisher.publish() returns an Awaiter. 
                     // If we await it, we wait for the message to be sent.
                     // For high throughput, we might spawn it?
                     // Or just await it? It should be fast if batching is used (it returns when enqueued? no, usually when acked).
                     // Google Cloud PubSub crate `publish` waits for ack.
                     // Using `publish` in a loop will throttle us to latency of Pub/Sub.
                     // We should spawn a task to await it if we want fire-and-forget.
                     let publisher = publisher.clone();
                     tokio::spawn(async move {
                         let _ = publisher.publish(PubsubMessage {
                             data: data.into(),
                             ..Default::default()
                         }).await;
                     });
                 },
                 Err(e) => error!("Failed to serialize message: {}", e),
             }
        }
    }
}
