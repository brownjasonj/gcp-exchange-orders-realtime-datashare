#include "simulator.hpp"
#include <chrono>
#include <iomanip>
#include <sstream>
#include <iostream>

namespace simulator {

Simulator::Simulator(Config config) 
    : config_(std::move(config)), rng_(std::random_device{}()) {
    
    bq_client_ = std::make_unique<BigQueryClient>(
        config_.gcp_project_id, 
        config_.bigquery_dataset_id, 
        config_.bigquery_table_id
    );

    // Initialize prices
    std::uniform_real_distribution<double> dist(10.0, 1000.0);
    for (const auto& symbol : config_.symbols) {
        for (const auto& currency : config_.currencies) {
            std::string key = symbol + ":" + currency;
            double initial_price = std::round(dist(rng_) * 100.0) / 100.0;
            prices_[key] = initial_price;
            pairs_.push_back({symbol, currency});
        }
    }
}

Simulator::~Simulator() {
    Stop();
}

void Simulator::Start() {
    if (running_.exchange(true)) return;
    
    loop_thread_ = std::thread(&Simulator::RunLoop, this);
    
    if (config_.burst_size > 0) {
        burst_thread_ = std::thread(&Simulator::HandleBurst, this);
    }
}

void Simulator::Stop() {
    running_ = false;
    if (loop_thread_.joinable()) loop_thread_.join();
    if (burst_thread_.joinable()) burst_thread_.join();
}

Status Simulator::GetStatus() {
    std::lock_guard<std::mutex> lock(state_mutex_);
    return {running_.load(), config_};
}

std::map<std::string, double> Simulator::GetPrices() {
    std::lock_guard<std::mutex> lock(state_mutex_);
    return prices_;
}

void Simulator::UpdateConfig(Config config) {
    bool was_running = running_;
    if (was_running) Stop();
    
    {
        std::lock_guard<std::mutex> lock(state_mutex_);
        config_ = std::move(config);
        
        // Re-init
        pairs_.clear();
        prices_.clear();
        std::uniform_real_distribution<double> dist(10.0, 1000.0);
        for (const auto& symbol : config_.symbols) {
            for (const auto& currency : config_.currencies) {
                std::string key = symbol + ":" + currency;
                double initial_price = std::round(dist(rng_) * 100.0) / 100.0;
                prices_[key] = initial_price;
                pairs_.push_back({symbol, currency});
            }
        }
        
        bq_client_ = std::make_unique<BigQueryClient>(
            config_.gcp_project_id, 
            config_.bigquery_dataset_id, 
            config_.bigquery_table_id
        );
    }
    
    if (was_running) Start();
}

void Simulator::RunLoop() {
    while (running_) {
        auto start = std::chrono::steady_clock::now();
        
        if (!burst_active_) {
            Tick();
        }
        
        auto end = std::chrono::steady_clock::now();
        auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(end - start);
        auto sleep_time = std::chrono::milliseconds(config_.periodicity_ms) - elapsed;
        
        if (sleep_time > std::chrono::milliseconds(0)) {
            std::this_thread::sleep_for(sleep_time);
        }
    }
}

void Simulator::HandleBurst() {
    burst_active_ = true;
    uint64_t total = config_.burst_size;
    std::vector<PricingMessage> batch;
    batch.reserve(1000);

    if (prog_cb_) prog_cb_({0, 0, "generating"});

    for (uint64_t i = 0; i < total && running_; ++i) {
        batch.push_back(GenerateMessage());
        
        if (batch.size() >= 1000 || i == total - 1) {
            uint8_t percent = static_cast<uint8_t>((i + 1) * 100 / total);
            if (prog_cb_) prog_cb_({percent, i + 1, "publishing"});
            
            bq_client_->StreamMessages(batch);
            batch.clear();
        }
    }

    if (prog_cb_) prog_cb_({100, total, "complete"});
    burst_active_ = false;
}

PricingMessage Simulator::GenerateMessage() {
    std::lock_guard<std::mutex> lock(state_mutex_);
    
    if (pairs_.empty()) return {};

    std::uniform_int_distribution<size_t> pair_dist(0, pairs_.size() - 1);
    auto& pair = pairs_[pair_dist(rng_)];
    std::string key = pair.first + ":" + pair.second;
    
    double current_price = prices_[key];
    std::uniform_real_distribution<double> var_dist(-config_.price_variation_percentage, config_.price_variation_percentage);
    double change = var_dist(rng_) / 100.0;
    double new_price = std::max(0.01, std::round(current_price * (1.0 + change) * 100.0) / 100.0);
    
    prices_[key] = new_price;

    auto now = std::chrono::system_clock::now();
    auto in_time_t = std::chrono::system_clock::to_time_t(now);
    std::stringstream ss;
    ss << std::put_time(std::gmtime(&in_time_t), "%Y-%m-%dT%H:%M:%SZ");

    std::uniform_int_distribution<size_t> venue_dist(0, config_.venues.size() - 1);
    std::uniform_int_distribution<int> bid_ask_dist(0, 1);
    std::uniform_int_distribution<uint64_t> qty_dist(1, 1000);

    PricingMessage msg{
        pair.first,
        sequence_number_++,
        new_price,
        pair.second,
        config_.venues[venue_dist(rng_)],
        ss.str(),
        bid_ask_dist(rng_) == 0 ? "bid" : "ask",
        qty_dist(rng_)
    };

    return msg;
}

void Simulator::Tick() {
    auto msg = GenerateMessage();
    
    if (msg_cb_) msg_cb_(msg);
    if (pu_cb_) pu_cb_({msg.symbol, msg.currency, msg.price, msg.bid_ask});
    
    bq_client_->StreamMessage(msg);
}

} // namespace simulator
