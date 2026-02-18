#pragma once

#include "types.hpp"
#include "bigquery_client.hpp"
#include <mutex>
#include <thread>
#include <atomic>
#include <map>
#include <random>

namespace simulator {

class Simulator {
public:
    Simulator(Config config);
    ~Simulator();

    void Start();
    void Stop();
    Status GetStatus();
    std::map<std::string, double> GetPrices();
    void UpdateConfig(Config config);

    // Callback for UI updates (Socket.IO equivalent)
    using MessageCallback = std::function<void(const PricingMessage&)>;
    using PriceUpdateCallback = std::function<void(const PriceUpdate&)>;
    using ProgressCallback = std::function<void(const BurstProgress&)>;

    void SetCallbacks(MessageCallback msg_cb, PriceUpdateCallback pu_cb, ProgressCallback prog_cb) {
        msg_cb_ = msg_cb;
        pu_cb_ = pu_cb;
        prog_cb_ = prog_cb;
    }

private:
    void Initialize();
    void RunLoop();
    void HandleBurst();
    PricingMessage GenerateMessage();
    void Tick();

    Config config_;
    std::atomic<bool> running_{false};
    std::atomic<bool> burst_active_{false};
    uint64_t sequence_number_{0};
    
    std::map<std::string, double> prices_;
    std::vector<std::pair<std::string, std::string>> pairs_;
    
    std::mutex state_mutex_;
    std::thread loop_thread_;
    std::thread burst_thread_;
    
    std::unique_ptr<BigQueryClient> bq_client_;
    
    MessageCallback msg_cb_;
    PriceUpdateCallback pu_cb_;
    ProgressCallback prog_cb_;

    std::mt19937 rng_;
};

} // namespace simulator
