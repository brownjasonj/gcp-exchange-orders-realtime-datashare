mod config;
mod simulator;
mod types;

use axum::{
    extract::{State, Json},
    routing::{get, post},
    Router,
};
use config::{load_config, save_config};
use simulator::Simulator;
use types::Config;
use socketioxide::{
    extract::SocketRef,
    SocketIo,
};
use tower_http::cors::CorsLayer;
use tower_http::services::ServeDir;
use tracing::{info, Level, warn};
use tracing_subscriber::FmtSubscriber;
use std::net::SocketAddr;
use std::path::Path;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Use println for immediate feedback in logs (tracing might be buffered or not init yet)
    println!("Starting Simulator Server...");

    let subscriber = FmtSubscriber::builder()
        .with_max_level(Level::INFO)
        .finish();
    if let Err(e) = tracing::subscriber::set_global_default(subscriber) {
        eprintln!("Failed to set subscriber: {}", e);
    }

    let config_path = std::env::var("CONFIG_PATH").unwrap_or_else(|_| "config.json".to_string());
    println!("Loading config from: {}", config_path);
    let config = load_config(&config_path);
    
    let (layer, io) = SocketIo::new_layer();
    
    println!("Initializing Simulator...");
    let simulator = Simulator::new(config, io.clone()).await;
    
    let sim_for_socket = simulator.clone();
    io.ns("/", move |socket: SocketRef| {
        let sim = sim_for_socket.clone();
        async move {
            info!("Client connected: {}", socket.id);
            let status = sim.get_status().await;
            let _ = socket.emit("status", &status);
            let prices = sim.get_prices().await;
            let _ = socket.emit("prices", &prices);
        }
    });

    let ui_dist = "../simulator-ui/dist/ui/browser";
    let serve_dir = if Path::new(ui_dist).exists() {
        ServeDir::new(ui_dist)
    } else {
        warn!("UI dist not found at {}, serving current dir as fallback (likely 404s)", ui_dist);
        ServeDir::new(".")
    };

    let app = Router::new()
        .route("/api/config", get(get_config).post(update_config))
        .route("/api/start", post(start_sim))
        .route("/api/stop", post(stop_sim))
        .route("/api/status", get(get_status))
        .route("/api/prices", get(get_prices))
        .fallback_service(serve_dir)
        .layer(layer)
        .layer(CorsLayer::permissive())
        .with_state(simulator);

    let port_str = std::env::var("PORT").unwrap_or_else(|_| "8080".to_string());
    let port = port_str.parse::<u16>().unwrap_or(8080);
    
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    println!("Server binding to {}", addr);
    info!("Server binding to {}", addr);
    
    let listener = tokio::net::TcpListener::bind(addr).await?;
    println!("Server listening on {}", addr);
    axum::serve(listener, app).await?;

    Ok(())
}

async fn get_config(State(sim): State<Simulator>) -> Json<Config> {
    Json(sim.get_status().await.config)
}

#[derive(serde::Serialize)]
struct ConfigResponse {
    success: bool,
    config: Config,
}

async fn update_config(State(sim): State<Simulator>, Json(config): Json<Config>) -> Json<ConfigResponse> {
    let config_path = std::env::var("CONFIG_PATH").unwrap_or_else(|_| "config.json".to_string());
    if let Err(e) = save_config(&config_path, &config) {
        warn!("Failed to save config: {}", e);
    }
    
    sim.update_config(config.clone()).await;
    let status = sim.get_status().await;
    let _ = sim.io.emit("status", &status).await;
    
    Json(ConfigResponse {
        success: true,
        config,
    })
}

#[derive(serde::Serialize)]
struct SuccessResponse {
    success: bool,
}

async fn start_sim(State(sim): State<Simulator>) -> Json<SuccessResponse> {
    sim.start().await;
    let status = sim.get_status().await;
    let _ = sim.io.emit("status", &status).await;
    Json(SuccessResponse { success: true })
}

async fn stop_sim(State(sim): State<Simulator>) -> Json<SuccessResponse> {
    sim.stop().await;
    let status = sim.get_status().await;
    let _ = sim.io.emit("status", &status).await;
    Json(SuccessResponse { success: true })
}

async fn get_status(State(sim): State<Simulator>) -> Json<types::Status> {
    Json(sim.get_status().await)
}

async fn get_prices(State(sim): State<Simulator>) -> Json<std::collections::HashMap<String, f64>> {
    Json(sim.get_prices().await)
}
