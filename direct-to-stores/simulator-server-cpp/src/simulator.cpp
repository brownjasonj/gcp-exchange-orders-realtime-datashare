#include "simulator.hpp"
#include <chrono>
#include <iomanip>
#include <sstream>
#include <iostream>

namespace simulator {

Simulator::Simulator(Config config) 
    : config_(std::move(config)), rng_(std::random_device{}()) {
    
    Initialize();
}

Simulator::~Simulator() {
    Stop();
}

void Simulator::Initialize() {
    std::lock_guard<std::mutex> lock(state_mutex_);
    
    // Sharding logic
    const char* shard_index_env = std::getenv("SHARD_INDEX");
    const char* total_shards_env = std::getenv("TOTAL_SHARDS");
    int shard_index = shard_index_env ? std::stoi(shard_index_env) : 0;
    int total_shards = total_shards_env ? std::stoi(total_shards_env) : 1;

    std::cout << "Initializing C++ Simulator Shard " << shard_index << "/" << total_shards << std::endl;

    pairs_.clear();
    prices_.clear();

    bq_client_ = std::make_unique<BigQueryClient>(
        config_.gcp_project_id, 
        config_.bigquery_dataset_id, 
        config_.bigquery_table_id
    );

    std::uniform_real_distribution<double> dist(10.0, 1000.0);
    
    for (size_t i = 0; i < config_.symbols.size(); ++i) {
        if (static_cast<int>(i % total_shards) == shard_index) {
            const auto& symbol = config_.symbols[i];
            for (const auto& currency : config_.currencies) {
                std::string key = symbol + ":" + currency;
                double initial_price = std::round(dist(rng_) * 100.0) / 100.0;
                prices_[key] = initial_price;
                pairs_.push_back({symbol, currency});
            }
        }
    }
    
    std::cout << "Simulator initialized with " << pairs_.size() << " pairs." << std::endl;
}

void Simulator::Start() {
    if (running_.exchange(true)) return;
    
    loop_thread_ = std::thread(&Simulator::RunLoop, this);
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
    
    config_ = std::move(config);
    Initialize();
    
    if (was_running) Start();
}

void Simulator::RunLoop() {
    // Handle burst first if requested
    if (config_.burst_size > 0) {
        HandleBurst();
    }

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
    
    std::cout << "[BURST] Starting generation of " << total << " messages..." << std::endl;
    std::vector<PricingMessage> all_messages;
    all_messages.reserve(total);

    // 1. Generation Phase
    uint8_t last_reported_gen = 0;
    if (prog_cb_) prog_cb_({0, 0, "generating"});

    for (uint64_t i = 0; i < total && running_; ++i) {
        all_messages.push_back(GenerateMessage());
        
        uint8_t percent = static_cast<uint8_t>((i + 1) * 100 / total);
        if (percent >= last_reported_gen + 5 || i == total - 1) {
            last_reported_gen = percent;
            if (prog_cb_) prog_cb_({percent, i + 1, "generating"});
        }
    }

    if (!running_) {
        burst_active_ = false;
        return;
    }

    std::cout << "[BURST] Generation complete. Starting publishing..." << std::endl;

    // 2. Publishing Phase
    uint64_t total_published = 0;
    uint8_t last_reported_pub = 0;
    const uint64_t batch_size = 1000;

    if (prog_cb_) prog_cb_({0, 0, "publishing"});

    for (uint64_t i = 0; i < all_messages.size() && running_; i += batch_size) {
        uint64_t end = std::min(i + batch_size, static_cast<uint64_t>(all_messages.size()));
        std::vector<PricingMessage> batch;
        batch.assign(all_messages.begin() + i, all_messages.begin() + end);
        
        auto now_pub = std::chrono::system_clock::now();
        auto in_time_t_pub = std::chrono::system_clock::to_time_t(now_pub);
        std::stringstream ss_pub;
        ss_pub << std::put_time(std::gmtime(&in_time_t_pub), "%Y-%m-%dT%H:%M:%SZ");
        std::string publish_time = ss_pub.str();

        for (auto& msg : batch) {
            msg.publish_time = publish_time;
        }
        
        bq_client_->StreamMessages(batch);
        total_published += batch.size();

        uint8_t percent = static_cast<uint8_t>(total_published * 100 / total);
        if (percent >= last_reported_pub + 5 || total_published == total) {
            last_reported_pub = percent;
            if (prog_cb_) prog_cb_({percent, total_published, "publishing"});
        }
    }

    std::cout << "[BURST] Burst complete." << std::endl;
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

    uint64_t seq = sequence_number_++;
    std::string venue = config_.venues[venue_dist(rng_)];
    std::string timestamp = ss.str();
    std::string bid_ask = bid_ask_dist(rng_) == 0 ? "bid" : "ask";
    std::string event_id = pair.first + venue + bid_ask + std::to_string(seq) + timestamp;

    PricingMessage msg{
        pair.first,
        seq,
        new_price,
        pair.second,
        venue,
        timestamp,
        bid_ask,
        qty_dist(rng_),
        "", // publishTime
        event_id
    };

    return msg;
}

void Simulator::Tick() {
    auto msg = GenerateMessage();
    
    if (msg_cb_) msg_cb_(msg);
    if (pu_cb_) pu_cb_({msg.symbol, msg.currency, msg.price, msg.bid_ask});
    
    auto now_pub = std::chrono::system_clock::now();
    auto in_time_t_pub = std::chrono::system_clock::to_time_t(now_pub);
    std::stringstream ss_pub;
    ss_pub << std::put_time(std::gmtime(&in_time_t_pub), "%Y-%m-%dT%H:%M:%SZ");
    msg.publish_time = ss_pub.str();

    bq_client_->StreamMessage(msg);
} 


} // namespace simulator
