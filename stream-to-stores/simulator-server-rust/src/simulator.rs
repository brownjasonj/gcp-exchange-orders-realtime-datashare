use crate::types::{Config, PricingMessage, Status, PriceUpdate};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{RwLock, Mutex};
use tokio::task::{JoinHandle, JoinSet, unconstrained};
use std::sync::atomic::{AtomicBool, Ordering};
use tokio::time::{interval, timeout, Duration};
use rand::Rng;
use socketioxide::SocketIo;
use google_cloud_pubsub::client::{Client, ClientConfig};
use google_cloud_pubsub::publisher::{Publisher, PublisherConfig};
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
    pub io: SocketIo,
    pubsub: Option<Client>,
    publisher: Arc<RwLock<Option<Publisher>>>,
    task_handle: Arc<Mutex<Option<JoinHandle<()>>>>,
    burst_active: Arc<AtomicBool>,
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
            burst_active: Arc::new(AtomicBool::new(false)),
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
             
             // Create new publisher with batch settings from config (clamped to GCP limit of 1000)
             let publisher_config = PublisherConfig {
                 bundle_size: state.config.pubsub_batch_messages.min(1000),
                 flush_interval: Duration::from_millis(state.config.pubsub_batch_delay_ms),
                 ..Default::default()
             };
             
             // Note: new_publisher starts a background task immediately
             *pub_guard = Some(topic.new_publisher(Some(publisher_config)));
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
        let burst_size = state_guard.config.burst_size;
        let batch_size = state_guard.config.pubsub_batch_messages;
        drop(state_guard);

        let sim_clone = self.clone();
        let mut handle_guard = self.task_handle.lock().await;
        
        if let Some(handle) = handle_guard.take() {
            handle.abort();
        }

        info!("Starting simulation loop with periodicity {}ms", periodicity);

        *handle_guard = Some(tokio::spawn(async move {
            if burst_size > 0 {
                info!("Generating burst of {} messages...", burst_size);
                let mut burst_msgs = Vec::with_capacity(burst_size as usize);
                let mut last_reported_percent = 0;
                
                // Emit 0% start
                let _ = sim_clone.io.emit("burstProgress", &crate::types::BurstProgress { 
                    percent_complete: 0, 
                    message_count: 0,
                    phase: "generating".to_string()
                }).await;

                for i in 0..burst_size {
                    if let Some(msg) = sim_clone.generate_message().await {
                         burst_msgs.push(msg);
                    }
                    
                    let percent = ((i + 1) as f64 / burst_size as f64 * 100.0) as u8;
                    if percent >= last_reported_percent + 5 {
                        last_reported_percent = percent;
                        let _ = sim_clone.io.emit("burstProgress", &crate::types::BurstProgress { 
                            percent_complete: percent, 
                            message_count: i + 1,
                            phase: "generating".to_string()
                        }).await;
                    }
                    
                    if (i + 1) % 10000 == 0 {
                        info!("Generated {} burst messages", i + 1);
                    }
                }

                // Final Generation Update (100%)
                let _ = sim_clone.io.emit("burstProgress", &crate::types::BurstProgress { 
                    percent_complete: 100, 
                    message_count: burst_msgs.len() as u64,
                    phase: "generating".to_string()
                }).await;
                
                info!("Burst generation complete. Total: {}", burst_msgs.len());
                
                // Start Publishing Phase (Sequential)
                sim_clone.burst_active.store(true, Ordering::SeqCst);
                let publisher_guard = sim_clone.publisher.read().await;
                if let Some(publisher) = &*publisher_guard {
                    let publisher = publisher.clone();
                    // We can drop guard here as we have a clone of the publisher client
                    drop(publisher_guard);

                    info!("Publishing burst of {} messages...", burst_msgs.len());
                    
                    // Emit 0% publishing
                     let _ = sim_clone.io.emit("burstProgress", &crate::types::BurstProgress { 
                        percent_complete: 0, 
                        message_count: 0,
                        phase: "publishing".to_string()
                    }).await;

                    let total_msgs = burst_msgs.len();
                    let mut completed = 0;
                    let mut last_reported_percent = 0;

                    // Calculate number of parallel tasks for each chunk
                    // Dividing pubsubBatchMessages by the maximum pubsub batch size (1000)
                    let max_pubsub_batch_size = 1000;
                    let num_workers = (batch_size + max_pubsub_batch_size - 1) / max_pubsub_batch_size;
                    let sub_chunk_size = (batch_size + num_workers - 1) / num_workers;

                    info!("Parallelizing burst publishing with ~{} tasks per batch (sub-chunk size: {})", num_workers, sub_chunk_size);

                    for chunk in burst_msgs.chunks(batch_size) {
                        let mut join_set = JoinSet::new();

                        for sub_chunk in chunk.chunks(sub_chunk_size) {
                            let publisher = publisher.clone();
                            let messages = sub_chunk.to_vec();
                            
                            join_set.spawn(unconstrained(async move {
                                let mut awaiters = Vec::with_capacity(messages.len());
                                for msg in messages {
                                    if let Ok(data_str) = serde_json::to_string(&msg) {
                                        let data = data_str.clone().into_bytes();
                                        let awaiter = publisher.publish(PubsubMessage {
                                            data: data.into(),
                                            ..Default::default()
                                        }).await;
                                        awaiters.push((awaiter, data_str));
                                    }
                                }
                                
                                let mut local_completed = 0;
                                for (awaiter, payload) in awaiters {
                                    match awaiter.get().await {
                                        Ok(_) => local_completed += 1,
                                        Err(e) => error!("Burst publish error: {}; payload: {}", e, payload),
                                    }
                                }
                                local_completed
                            }));
                        }

                        // Monitor progress as tasks complete
                        while let Some(res) = join_set.join_next().await {
                            match res {
                                Ok(local_success) => {
                                    completed += local_success;
                                    let percent = (completed as f64 / total_msgs as f64 * 100.0) as u8;
                                     
                                    if percent >= last_reported_percent + 5 {
                                        last_reported_percent = percent;
                                        let _ = sim_clone.io.emit("burstProgress", &crate::types::BurstProgress { 
                                            percent_complete: percent, 
                                            message_count: completed as u64,
                                            phase: "publishing".to_string()
                                        }).await;
                                    }
                                },
                                Err(e) => error!("Publishing task failed: {}", e),
                            }
                        }
                    }
                    
                    // Final publishing update (100%)
                    let _ = sim_clone.io.emit("burstProgress", &crate::types::BurstProgress { 
                        percent_complete: 100, 
                        message_count: completed as u64,
                        phase: "publishing".to_string()
                    }).await;

                    info!("Burst publish complete.");
                } else {
                    error!("No publisher available for burst!");
                }
                sim_clone.burst_active.store(false, Ordering::SeqCst);

            }

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
                
                if sim_clone.burst_active.load(Ordering::Relaxed) {
                    tokio::task::yield_now().await;
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

    async fn generate_message(&self) -> Option<PricingMessage> {
        let mut state = self.state.write().await;
        let mut rng = rand::rng();

        if state.pairs.is_empty() {
            return None;
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
            sequence_number: state.sequence_number as i64,
            price: new_price,
            currency: currency.clone(),
            venue,
            timestamp: Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true),
            bid_ask: if rng.random_bool(0.5) { "bid".to_string() } else { "ask".to_string() },
            quantity: rng.random_range(1..1001) as i64,
            publish_time: Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true),
            ingestion_time: None,
        };
        
        state.sequence_number += 1;
        Some(msg)
    }

    async fn publish_message(&self, msg: &PricingMessage) {
        let publisher_guard = self.publisher.read().await;
        if let Some(publisher) = &*publisher_guard {
            match serde_json::to_string(msg) {
                 Ok(data_str) => {
                     let data = data_str.clone().into_bytes();
                     let publisher = publisher.clone();
                     tokio::spawn(async move {
                         let awaiter = publisher.publish(PubsubMessage {
                             data: data.into(),
                             ..Default::default()
                         }).await;
                         
                         if let Err(e) = awaiter.get().await {
                             error!("Publish notification error: {}; payload: {}", e, data_str);
                         }
                     });
                 },
                 Err(e) => error!("Failed to serialize message: {}", e),
             }
        }
    }

    async fn tick(&self) {
        if let Some(msg) = self.generate_message().await {
            let _ = self.io.emit("message", &msg).await;
            
            let update = PriceUpdate {
                symbol: msg.symbol.clone(),
                currency: msg.currency.clone(),
                price: msg.price,
                bid_ask: msg.bid_ask.clone(),
            };
            let _ = self.io.emit("priceUpdate", &update).await;
            
            self.publish_message(&msg).await;
        }
    }
}
